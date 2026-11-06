/// Chequeo guiado de un stick (plan v2 §17): dice si el stick se conecta, si mide
/// lo que el juego necesita y, si no, qué hacer. Dart puro: se alimenta con
/// [tick] y una [StickSnapshot], y no conoce el Bluetooth ni la pantalla.
///
/// Pasos: conexión → quieto (mide el giro) → adelante → derecha (ejes, con el
/// asistente) → rango (la misma calibración del juego) → llegar a los bordes.
///
/// Mide las causas que impiden pasar un nivel sin que nadie lo note:
/// - **levantar sin inclinar:** el sensor mide inclinación, no altura. Se reconoce
///   porque |a| cambia y la dirección de la gravedad no.
/// - **stick girado en la mano:** «Juntos» solo mira adelante y atrás; sujetarlo
///   girado 90° lleva ese gesto a otro eje, y 180° lo invierte. El paso de ejes lo
///   detecta y lo corrige para esta forma de sujetarlo.
/// - **calibración sin datos:** si no se mueve lo suficiente en esos 6 s, el juego
///   sigue con el rango por defecto.
/// - **gesto lento:** bajo [SyncParams.onSpeed] la persona cuenta como quieta.
library;

import 'calibration.dart';
import 'levels.dart';
import 'params.dart';
import 'stick_state.dart';
import 'tilt/axis_map.dart';
import 'tilt/vec3.dart';

enum CheckStep { link, rest, forward, right, range, reach, done }

enum CheckGrade { ok, warn, fail }

/// Un resultado del chequeo, en palabras para quien sostiene el stick.
class CheckFinding {
  const CheckFinding(this.grade, this.title, this.detail);
  final CheckGrade grade;
  final String title, detail;

  @override
  String toString() => '${grade.name}: $title';
}

/// Lo que se sabe del stick en este instante.
class StickSnapshot {
  const StickSnapshot({
    required this.connected,
    required this.receiving,
    required this.hz,
    required this.tiltX,
    required this.tiltY,
    required this.gravity,
    required this.accelMagG,
    required this.restMagG,
    required this.gyroReady,
    required this.stillCount,
    required this.axes,
    this.lagMs = 0,
    this.gaps = 0,
  });

  final bool connected;

  /// Llegaron muestras en el último segundo.
  final bool receiving;
  final double hz, tiltX, tiltY;
  final V3? gravity;
  final double accelMagG, restMagG;

  /// El giro tiene un bias que usar (medido o guardado).
  final bool gyroReady;

  /// Veces que una quietud real midió el bias.
  final int stillCount;
  final AxisMap? axes;

  /// Retraso de los datos (ms) y cortes desde que se abrió el stick.
  final double lagMs;
  final int gaps;

  bool get live => connected && receiving && gravity != null;
}

class StickCheck {
  StickCheck({required this.role, required this.params, this.onAxes}) : plane = StickState(role);

  final Role role;
  final SyncParams params;

  /// Los ejes medidos están listos: guardarlos y aplicarlos al lector.
  final void Function(AxisMap axes)? onAxes;

  /// El punto del stick, para dibujarlo en los pasos de rango y bordes.
  final StickState plane;

  static const double linkTimeoutMs = 20000;
  static const double linkSettleMs = 500;
  static const double minHz = 20;
  static const double goodHz = 40;
  static const double restMinMs = 1500;
  static const double restTimeoutMs = 10000;
  static const double tiltTimeoutMs = 20000;
  static const double tiltGoalDeg = 25;
  static const double tiltBackDeg = 12;
  static const double liftNoTiltDeg = 10;
  static const double liftGateG = 0.15;
  static const double liftMinMs = 800;
  static const double reachMinMs = 4000;
  static const double reachTimeoutMs = 15000;
  static const double reachEdge = 5.5;
  static const double maxLagMs = 150;
  static const double maxLostMs = 8000;

  /// Bajo esto los ejes de antes valían; sobre [flippedDeg], estaban invertidos.
  static const double turnedDeg = 35;
  static const double flippedDeg = 145;

  CheckStep step = CheckStep.link;
  final List<CheckFinding> findings = [];

  /// Calibración que salió del paso de rango (la misma cuenta del juego).
  StickCal? cal;

  /// Se está levantando el stick sin inclinarlo.
  bool lifting = false;

  /// El stick dejó de mandar datos: el paso está detenido.
  bool paused = false;

  final AxisWizard _wizard = AxisWizard();
  final Calibration _cal = Calibration();
  AxisMap? _oldAxes;
  double? _last;
  double _stepStart = 0;
  double _elapsed = 0;
  double _liveMs = 0;
  double _lostMs = 0;
  double _liftMs = 0;
  int? _still0;
  bool _top = false, _bottom = false, _left = false, _right = false;
  double _activeMs = 0;

  // Mediciones para el video y el archivo de datos.
  final Map<String, int> _stepMs = {};
  double? _hz, _peakForward, _peakRight, _shiftDeg, _activePct;
  double _liftTotalMs = 0;
  int? _calMoving, _calTotal, _gaps0;
  int _gaps = 0;
  double _lagMs = 0;

  double get elapsedMs => _elapsed;

  /// Avance del paso actual (0–1).
  double get progress {
    final v = switch (step) {
      CheckStep.link => _liveMs / linkSettleMs,
      CheckStep.rest => _elapsed / restTimeoutMs,
      CheckStep.forward || CheckStep.right => _wizard.currentTiltDeg / tiltGoalDeg,
      CheckStep.range => _elapsed / Calibration.durationMs,
      CheckStep.reach => [_top, _bottom, _left, _right].where((b) => b).length / 4,
      CheckStep.done => 1.0,
    };
    return v.clamp(0.0, 1.0).toDouble();
  }

  /// Bordes del plano alcanzados en el último paso.
  ({bool top, bool bottom, bool left, bool right}) get reached => (top: _top, bottom: _bottom, left: _left, right: _right);

  /// El peor resultado.
  CheckGrade get grade {
    if (findings.any((f) => f.grade == CheckGrade.fail)) return CheckGrade.fail;
    return findings.any((f) => f.grade == CheckGrade.warn) ? CheckGrade.warn : CheckGrade.ok;
  }

  String get title => switch (step) {
        CheckStep.link => 'Conectando el stick',
        CheckStep.rest => 'Déjalo quieto',
        CheckStep.forward => 'Inclínalo hacia adelante',
        CheckStep.right => 'Inclínalo hacia tu derecha',
        CheckStep.range => 'Muévelo como al jugar',
        CheckStep.reach => 'Lleva el punto a los cuatro bordes',
        CheckStep.done => switch (grade) {
            CheckGrade.ok => 'Este stick está bien',
            CheckGrade.warn => 'Funciona, con observaciones',
            CheckGrade.fail => 'Hay algo que arreglar',
          },
      };

  String get instruction => switch (step) {
        CheckStep.link => 'Enciende el stick y acércalo al teléfono.',
        CheckStep.rest => 'Sostenlo vertical como al jugar, sin moverlo. También puedes apoyarlo.',
        CheckStep.forward => 'Sin levantar el brazo, inclina la punta lejos de ti y vuelve a la posición vertical.',
        CheckStep.right => 'Sin levantar el brazo, inclina la punta hacia tu derecha y vuelve a la posición vertical.',
        CheckStep.range => 'Inclínalo adelante, atrás y a los lados, con el gesto que usarás en el juego.',
        CheckStep.reach => 'Mueve el punto hasta tocar el marco arriba, abajo, a la izquierda y a la derecha.',
        CheckStep.done => 'Resultado del chequeo.',
      };

  /// Aviso del momento, si lo hay.
  String? get hint {
    if (paused) return 'El stick dejó de mandar datos. Acércalo al teléfono.';
    if (lifting) return 'Eso es levantar el stick. El juego solo mide la inclinación: inclina la punta.';
    if ((step == CheckStep.forward || step == CheckStep.right) && _wizard.currentTiltDeg >= tiltGoalDeg) {
      return 'Bien. Ahora vuelve a la posición vertical.';
    }
    return null;
  }

  void tick(double now, StickSnapshot s) {
    if (step == CheckStep.done) return;
    final last = _last;
    _last = now;
    if (last == null) _stepStart = now;
    final dtMs = last == null ? 0.0 : (now - last).clamp(0.0, 100.0).toDouble();

    if (step != CheckStep.link && !s.live) {
      paused = true;
      lifting = false;
      _stepStart += dtMs; // el tiempo sin datos no cuenta para el paso
      _lostMs += dtMs;
      if (_lostMs > maxLostMs) {
        _fail('El stick se desconectó', 'Se perdió la señal durante el chequeo. Revisa la batería y acércalo al teléfono.');
      }
      return;
    }
    paused = false;
    _lostMs = 0;
    _gaps = s.gaps - (_gaps0 ?? s.gaps);
    _lagMs = _lagMs > s.lagMs ? _lagMs : s.lagMs;
    _elapsed = now - _stepStart;

    switch (step) {
      case CheckStep.link:
        _link(s, dtMs, now);
      case CheckStep.rest:
        _rest(s, now);
      case CheckStep.forward:
      case CheckStep.right:
        _tilt(s, dtMs, now);
      case CheckStep.range:
        _range(s, dtMs, now);
      case CheckStep.reach:
        _reach(s, dtMs, now);
      case CheckStep.done:
        break;
    }
  }

  /// Mediciones en líneas cortas, para leerlas en un cuadro del video.
  List<String> get dataLines {
    String n(double? v, [String unit = '']) => v == null ? '–' : '${v.round()}$unit';
    final c = cal;
    return [
      'Datos: ${n(_hz, ' por segundo')}',
      'Inclinó adelante ${n(_peakForward, '°')} · derecha ${n(_peakRight, '°')}',
      'Giro corregido ${n(_shiftDeg, '°')}',
      'Levantó sin inclinar ${(_liftTotalMs / 1000).toStringAsFixed(1)} s',
      'Rango ${c == null ? 'sin calibrar' : '±${c.hrY.round()}° adelante, ±${c.hrX.round()}° lados'}',
      'Muestras en movimiento ${_calMoving ?? '–'} de ${_calTotal ?? '–'} (mínimo ${Calibration.minMovingSamples})',
      'En movimiento ${n(_activePct, ' %')}',
      'Retraso ${_lagMs.round()} ms · $_gaps cortes',
    ];
  }

  Map<String, Object?> toJson() => {
        'rol': role.name,
        'resultado': grade.name,
        'hallazgos': [
          for (final f in findings) {'nivel': f.grade.name, 'titulo': f.title, 'detalle': f.detail}
        ],
        'ms_por_paso': _stepMs,
        'datos_por_segundo': _hz,
        'inclino_adelante_grados': _peakForward,
        'inclino_derecha_grados': _peakRight,
        'giro_corregido_grados': _shiftDeg,
        'levanto_sin_inclinar_ms': _liftTotalMs,
        'calibracion': cal?.toJson(),
        'calibracion_muestras': {'en_movimiento': _calMoving, 'total': _calTotal, 'minimo': Calibration.minMovingSamples},
        'bordes': {'arriba': _top, 'abajo': _bottom, 'izquierda': _left, 'derecha': _right},
        'porcentaje_en_movimiento': _activePct,
        'retraso_ms': _lagMs,
        'cortes': _gaps,
      };

  void _go(CheckStep next, double now) {
    _stepMs[step.name] = _elapsed.round();
    step = next;
    _stepStart = now;
    _elapsed = 0;
    lifting = false;
  }

  void _add(CheckGrade g, String title, String detail) => findings.add(CheckFinding(g, title, detail));

  void _fail(String title, String detail) {
    _add(CheckGrade.fail, title, detail);
    step = CheckStep.done;
  }

  void _link(StickSnapshot s, double dtMs, double now) {
    _liveMs = s.live && s.hz >= minHz ? _liveMs + dtMs : 0;
    if (_liveMs >= linkSettleMs) {
      final hz = s.hz.round();
      _hz = s.hz;
      if (s.hz >= goodHz) {
        _add(CheckGrade.ok, 'Conexión', 'Llegan $hz datos por segundo.');
      } else {
        _add(CheckGrade.warn, 'Conexión lenta', 'Llegan $hz datos por segundo (lo normal es 50 o 100). Acerca el stick al teléfono.');
      }
      _gaps0 = s.gaps;
      _oldAxes = s.axes;
      _still0 = s.stillCount;
      _go(CheckStep.rest, now);
      return;
    }
    if (_elapsed < linkTimeoutMs) return;
    if (!s.connected) {
      _fail('El stick no conectó', 'Revisa que esté encendido y con batería: su luz parpadea mientras espera al teléfono.');
    } else {
      _fail('Conectó, pero no manda datos', 'Si la luz parpadea muy rápido, el sensor no responde: revisa los cables. Si no, vuelve a cargar el firmware.');
    }
  }

  void _rest(StickSnapshot s, double now) {
    _wizard.feed(s.gravity!);
    final measured = s.stillCount > (_still0 ?? s.stillCount);
    final over = _elapsed >= restTimeoutMs;
    if (!(measured && _elapsed >= restMinMs) && !over) return;
    if (measured) {
      _add(CheckGrade.ok, 'Giroscopio', 'Se midió su error con el stick quieto.');
    } else if (s.gyroReady) {
      _add(CheckGrade.warn, 'Giroscopio', 'No quedó quieto el tiempo suficiente; se usa la medición guardada de este stick.');
    } else {
      _add(CheckGrade.warn, 'Giroscopio sin medir', 'No quedó quieto el tiempo suficiente y el punto puede temblar. Apóyalo en una mesa y repite.');
    }
    if (!_wizard.next()) {
      _fail('Sin datos del sensor', 'Repite el chequeo.');
      return;
    }
    _liftMs = 0;
    _go(CheckStep.forward, now);
  }

  void _tilt(StickSnapshot s, double dtMs, double now) {
    final g = s.gravity!;
    _wizard.feed(g);
    final cur = g.angleTo(_wizard.neutral!) * 180 / 3.141592653589793;
    final moved = (s.accelMagG - s.restMagG).abs() > liftGateG;
    lifting = moved && cur < liftNoTiltDeg && _wizard.currentTiltDeg < tiltGoalDeg;
    if (lifting) {
      _liftMs += dtMs;
      _liftTotalMs += dtMs;
    }

    final done = _wizard.currentTiltDeg >= tiltGoalDeg && cur < tiltBackDeg;
    if (!done && _elapsed < tiltTimeoutMs) return;

    final forward = step == CheckStep.forward;
    if (forward) {
      _peakForward = _wizard.currentTiltDeg;
    } else {
      _peakRight = _wizard.currentTiltDeg;
    }
    final wasLifting = _liftMs >= liftMinMs;
    if (!_wizard.next()) {
      if (_wizard.step == WizardStep.failed) {
        _fail('Los dos gestos fueron casi iguales', 'Adelante y derecha deben ser gestos distintos. Repite el chequeo sin girar el stick en la mano.');
      } else if (wasLifting) {
        // Sigue a la calibración: con este gesto, también hay que saber qué mide.
        _add(CheckGrade.fail, 'Levantas el stick sin inclinarlo', _liftAdvice);
        _liftMs = 0;
        _go(CheckStep.range, now);
      } else {
        _fail('No se detectó la inclinación', 'Hay que inclinar al menos ${AxisWizard.minTiltDeg.round()}° hacia ${forward ? 'adelante' : 'la derecha'}.');
      }
      return;
    }
    if (wasLifting) _add(CheckGrade.warn, 'Primero levantó el stick', _liftAdvice);
    _liftMs = 0;
    if (forward) {
      _go(CheckStep.right, now);
    } else {
      _axesDone();
      _go(CheckStep.range, now);
    }
  }

  static const String _liftAdvice = 'El sensor mide la inclinación, no la altura. Subir el brazo con el stick derecho '
      'no mueve el punto: hay que inclinar la punta. Conviene explicarlo antes de jugar.';

  void _axesDone() {
    final axes = _wizard.result!;
    final old = _oldAxes;
    if (old != null) {
      final deg = old.up.angleTo(axes.up) * 180 / 3.141592653589793;
      _shiftDeg = deg;
      if (deg >= flippedDeg) {
        _add(CheckGrade.warn, 'El stick estaba al revés', 'Adelante se medía como atrás, y así «Juntos» no se puede lograr. Quedó corregido para esta forma de sujetarlo.');
      } else if (deg >= turnedDeg) {
        _add(CheckGrade.warn, 'El stick estaba girado ${deg.round()}°', 'Parte del gesto adelante-atrás no llegaba al eje que mide «Juntos». Quedó corregido para esta forma de sujetarlo.');
      } else {
        _add(CheckGrade.ok, 'Orientación', 'Adelante y derecha se miden bien.');
      }
    }
    onAxes?.call(axes);
  }

  void _feedPlane(StickSnapshot s, double dtMs, double now) {
    plane.feedTilt(s.tiltX, s.tiltY, params);
    plane.update(now, (dtMs / 1000).clamp(0.0, 0.05).toDouble(), params);
  }

  void _range(StickSnapshot s, double dtMs, double now) {
    _feedPlane(s, dtMs, now);
    final moving = plane.speed > params.onSpeed;
    _cal.add(role, _elapsed, plane.tilt, moving: moving);
    lifting = !moving && (s.accelMagG - s.restMagG).abs() > liftGateG;
    if (lifting) _liftTotalMs += dtMs;
    if (_elapsed <= Calibration.durationMs) return;
    final c = _cal.result(role, params);
    cal = c;
    _calMoving = _cal.movingCount(role);
    _calTotal = _cal.count(role);
    if (c == null) {
      _fail('No se calibró', 'En estos 6 s casi no hubo movimiento, y en el juego pasaría lo mismo: seguiría con el rango por defecto. '
          'Repite con gestos más amplios y más rápidos.');
      return;
    }
    _add(CheckGrade.ok, 'Calibración', 'Rango medido: ±${c.hrY.round()}° adelante y ±${c.hrX.round()}° a los lados.');
    plane
      ..cal = c
      ..reset()
      ..resetEdgeStats();
    _go(CheckStep.reach, now);
  }

  void _reach(StickSnapshot s, double dtMs, double now) {
    _feedPlane(s, dtMs, now);
    final p = plane.pos;
    _top |= p.y >= reachEdge;
    _bottom |= p.y <= -reachEdge;
    _right |= p.x >= reachEdge;
    _left |= p.x <= -reachEdge;
    if (plane.speed > params.onSpeed) _activeMs += dtMs;
    final all = _top && _bottom && _left && _right;
    if (!(all && _elapsed >= reachMinMs) && _elapsed < reachTimeoutMs) return;

    if (_top && _bottom) {
      _add(CheckGrade.ok, 'Adelante y atrás', 'El punto llega arriba y abajo, que es lo que mide «Juntos».');
    } else {
      _add(CheckGrade.fail, 'El punto no llega ${_top ? 'abajo' : _bottom ? 'arriba' : 'arriba ni abajo'}',
          'Así cuesta mucho lograr «Juntos». Repite el chequeo con el mismo gesto que usarás en el juego.');
    }
    if (!(_left && _right)) {
      _add(CheckGrade.warn, 'El punto no llega a ${_left ? 'la derecha' : _right ? 'la izquierda' : 'los lados'}', 'Importa en «Espejo» e «Iguales».');
    }
    _stepMs[step.name] = _elapsed.round();
    _activePct = 100 * _activeMs / _elapsed;
    if (_lagMs > maxLagMs) {
      _add(CheckGrade.warn, 'Señal con retraso', 'Los datos llegaron hasta ${_lagMs.round()} ms tarde y el punto irá detrás del gesto. Acerca el stick o apágalo y vuelve a encenderlo.');
    }
    if (_gaps > 0) {
      _add(CheckGrade.warn, 'Señal con cortes', 'El stick dejó de mandar datos $_gaps veces. Revisa la batería y acércalo al teléfono.');
    }
    if (_activeMs / _elapsed < 0.4) {
      _add(CheckGrade.warn, 'Gesto lento', 'Más de la mitad del tiempo contó como quieto, y quieto no suma progreso. Hay que moverse un poco más rápido.');
    }
    step = CheckStep.done;
  }
}
