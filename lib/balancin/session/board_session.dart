import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/app_clock.dart';
import '../core/audio/light_envelope.dart';
import '../core/constants.dart';
import '../core/engine/balancin_engine.dart';
import '../core/engine/sound_command.dart';
import '../core/gesture/gesture_reader.dart';
import '../core/gesture/synthetic_motion.dart';
import '../core/gesture/touch_gesture_reader.dart';

/// Mitad de la pantalla del tablero.
enum PanelSide { left, right }

/// Rol sonoro de un stick (sigue al stick, no a la persona).
enum StickRole { adult, child }

/// Causa de pérdida de un stick (pantalla de pérdida del prototipo).
enum LossCause { alcance, bateria }

/// Textos de cada estado (`STATES` del prototipo).
const Map<BalancinState, ({String name, String desc})> kStateTexts = {
  BalancinState.reposo: (
    name: 'Reposo',
    desc: 'Ningún stick en movimiento. El motor de síntesis está en silencio.',
  ),
  BalancinState.espera: (
    name: 'Espera',
    desc: 'Solo se mueve el stick del adulto: el campo se abre con una única resonancia que decae. '
        'Después, nada, hasta que el niño entre.',
  ),
  BalancinState.silencio: (
    name: 'Silencio absoluto',
    desc: 'Solo se mueve el stick del niño: no hay campo donde sonar. Hace falta el otro.',
  ),
  BalancinState.activo: (
    name: 'Juego activo',
    desc: 'El adulto abre y sostiene el campo; el niño articula dentro de él. La relación entre '
        'ambos movimientos decide la textura. No hay forma incorrecta.',
  ),
  BalancinState.latN: (
    name: 'Latencia',
    desc: 'Se detuvo el niño: el campo queda resonando y decae lentamente. Invitación a volver, no sanción.',
  ),
  BalancinState.latA: (
    name: 'Latencia',
    desc: 'Se detuvo el adulto: el campo se estrecha y los eventos del niño van quedando sin alturas hasta apagarse.',
  ),
};

/// Textos de cada panel (`COPY` del prototipo).
const Map<StickRole, ({String title, String body, String mapping})> kPanelTexts = {
  StickRole.adult: (
    title: 'Stick grande · adulto',
    body: 'Abre y sostiene el campo. Gestos lentos y pequeños bastan.',
    mapping: 'Amplitud → ancho del campo · Velocidad → registro (lento grave, rápido agudo) · '
        'Quietud → el campo se estrecha',
  ),
  StickRole.child: (
    title: 'Stick pequeño · niño',
    body: 'Articula dentro del campo. Sin campo, no suena.',
    mapping: 'Velocidad → densidad rítmica · Amplitud → intensidad · Dirección → recorrido melódico dentro del campo',
  ),
};

/// Destello de una nota en el modo eje (posición relativa 0–1, 600 ms).
class EjeFlash {
  EjeFlash({required this.x, required this.y, required this.hidden, required this.bornMs});
  final double x;
  final double y;
  final bool hidden;
  final double bornMs;
}

/// Estado visual de la luz del modo eje (dos franjas, `glowT` / `glowB` del prototipo).
class EjeGlow {
  const EjeGlow({
    required this.topScale,
    required this.bottomScale,
    required this.opacity,
    required this.hidden,
  });
  static const zero = EjeGlow(topScale: 0, bottomScale: 0, opacity: 0.2, hidden: false);

  /// Escala vertical de la franja superior (carga más cuando el registro es agudo).
  final double topScale;

  /// Escala vertical de la franja inferior (carga más cuando el registro es grave).
  final double bottomScale;
  final double opacity;

  /// Color: amarillo `#F2E44A` si hay timbre oculto; si no, violeta `#7B5FCB`.
  final bool hidden;
}

/// Orquesta una sesión del tablero de validación (pantalla `#session` del prototipo).
///
/// La UI solo dibuja y reenvía toques:
///  - llama a [tick] en cada frame (Ticker),
///  - llama a [setPanelSize] y [feedPanel] desde los paneles,
///  - lee los getters para pintar.
/// El sonido sale por [onSound] (conectar a `AudioEngine.handle`).
///
/// El reloj por defecto es [AppClock]: toques, ticks y muestras BLE comparten la misma base de tiempo.
class BoardSession extends ChangeNotifier {
  BoardSession({
    required this.onSound,
    double Function()? clock,
    math.Random? random,
  })  : _clock = clock ?? AppClock.nowMs,
        _random = random ?? math.Random() {
    engine = BalancinEngine(adult: adultTouch, child: childTouch);
  }


  final void Function(List<SoundCommand> cmds) onSound;
  final double Function() _clock;
  final math.Random _random;

  /// Lectores táctiles de cada rol (el dedo "es" el stick).
  final TouchGestureReader adultTouch = TouchGestureReader();
  final TouchGestureReader childTouch = TouchGestureReader();
  late final BalancinEngine engine;
  final LightEnvelope light = LightEnvelope();

  double get nowMs => _clock();

  // ---------------------------------------------------------------------------
  // Configuración del tablero
  // ---------------------------------------------------------------------------

  /// Qué rol lee cada mitad de la pantalla (intercambiable).
  final Map<PanelSide, StickRole> sides = {
    PanelSide.left: StickRole.adult,
    PanelSide.right: StickRole.child,
  };

  final Map<PanelSide, ({double w, double h})> _panelSize = {
    PanelSide.left: (w: 400, h: 600),
    PanelSide.right: (w: 400, h: 600),
  };

  bool _autoChild = false;
  bool get autoChild => _autoChild;

  bool _autoAdult = false;
  bool get autoAdult => _autoAdult;

  /// Velocidad del "Adulto automático" (1 = normal, 7 = rápido/agudo).
  double autoAdultSpeed = 1;

  DemoScenario? _demo;
  DemoScenario? get demo => _demo;

  bool _ejeMode = false;
  bool get ejeMode => _ejeMode;

  StickRole? _lostRole;
  StickRole? get lostRole => _lostRole;
  LossCause? _lostCause;
  LossCause? get lostCause => _lostCause;

  // ---------------------------------------------------------------------------
  // Estado visual derivado
  // ---------------------------------------------------------------------------

  double _bus = BalancinConst.busGain;
  double _lightLevel = 0;

  /// Nivel de luz 0–1 (LED del tablero y franjas del modo eje).
  double get lightLevel => _lightLevel;

  final Map<int, ({double t, bool hidden})> _flashes = {};
  final List<EjeFlash> _ejeFlashes = [];
  List<EjeFlash> get ejeFlashes => List.unmodifiable(_ejeFlashes);

  /// Duración del destello de una columna de la banda (ms).
  static const double flashMs = 140;

  /// Duración de un destello del modo eje (ms).
  static const double ejeFlashMs = 600;

  BalancinState get state => engine.state;
  String get stateName => kStateTexts[state]!.name;
  String get stateDesc => kStateTexts[state]!.desc;
  bool get running => engine.running;
  bool get closed => engine.closed;
  FieldState get field => engine.field;
  bool get hiddenActive => engine.hiddenActive;

  /// Columna [i] (0–24) dentro del campo abierto.
  bool columnOn(int i) => field.count > 0 && i >= field.lo && i < field.lo + field.count;

  /// Destello de la columna [i]: null = sin destello; si no, si fue con timbre oculto.
  bool? columnFlash(int i) {
    final f = _flashes[i];
    if (f == null || nowMs - f.t > flashMs) return null;
    return f.hidden;
  }

  String get fieldText => field.count > 0
      ? 'Campo abierto: ${field.count} alturas disponibles · registro ${field.registerName} · '
          'el niño articula a ${engine.eventsPerSecond} ev/s'
      : 'Campo cerrado. Sin campo, el stick del niño no produce nada.';

  /// Texto del timbre oculto, o null si no hay.
  String? get hiddenText => hiddenActive
      ? 'Timbre oculto abierto por coincidencia · ${engine.hiddenRemainingS.toStringAsFixed(1)} s'
      : null;

  GestureReader readerFor(StickRole r) => r == StickRole.adult ? engine.adult : engine.child;
  TouchGestureReader touchFor(StickRole r) => r == StickRole.adult ? adultTouch : childTouch;

  /// Posición del punto en el panel [side] (px), o null si no hay.
  ({double x, double y})? dotFor(PanelSide side) {
    final r = touchFor(sides[side]!);
    final x = r.x, y = r.y;
    if (x == null || y == null) return null;
    return (x: x, y: y);
  }

  bool panelMoving(PanelSide side) => readerFor(sides[side]!).moving;

  // ---------------------------------------------------------------------------
  // Fuentes externas (stick BLE real)
  // ---------------------------------------------------------------------------

  final Map<StickRole, GestureReader> _external = {};

  /// Conecta un lector externo (p. ej. `ImuGestureReader` del stick real) al
  /// rol [role]. Con `null` el rol vuelve al dedo. El lector se reinicia, pero
  /// un `ImuGestureReader` conserva su calibración.
  void attachReader(StickRole role, GestureReader? reader) {
    if (reader == null) {
      _external.remove(role);
    } else {
      _external[role] = reader;
    }
    final r = reader ?? touchFor(role);
    r.reset();
    if (role == StickRole.adult) {
      engine.adult = r;
    } else {
      engine.child = r;
    }
    notifyListeners();
  }

  /// El rol [role] lo mueve un lector externo (stick real), no el dedo.
  bool isExternal(StickRole role) => _external.containsKey(role);

  /// Lector externo del rol, si hay.
  GestureReader? externalReader(StickRole role) => _external[role];

  /// Tarjetas de telemetría en vivo (tablero), en el orden del prototipo.
  List<({String value, String label})> get telemetryCards {
    final m = engine.metrics;
    return [
      (value: '${m.active.toStringAsFixed(0)} s', label: 'juego activo'),
      (value: '${m.fieldOpen.toStringAsFixed(0)} s', label: 'campo abierto · permanencia del adulto'),
      (value: '${m.latN}', label: 'latencias'),
      (value: '${m.resum}', label: 'reanudaciones'),
      (value: '${m.events}', label: 'eventos del niño'),
      (value: '${m.hidden}', label: 'timbres ocultos'),
    ];
  }

  /// Tarjetas del cierre de sesión (`renderSummary` del prototipo).
  List<({String value, String label})> get summaryCards {
    final r = engine.report();
    final lat = r['latencias']! as Map<String, Object>;
    return [
      (value: '${r['duracion_total_s']} s', label: 'duración total'),
      (value: '${r['juego_activo_s']} s', label: 'juego activo'),
      (value: '${r['campo_abierto_s']} s', label: 'campo abierto'),
      (value: '${lat['cantidad']}', label: 'latencias'),
      (value: '${lat['duracion_media_s']} s', label: 'duración media de latencia'),
      (value: '${r['reanudaciones']}', label: 'reanudaciones'),
      (value: '${r['eventos_nino']}', label: 'eventos del niño'),
      (value: '${r['variacion_campo_alturas']}', label: 'variación del campo (alturas recorridas)'),
      (value: '${r['timbres_ocultos']}', label: 'timbres ocultos hallados'),
      (value: '${r['intercambios_stick']}', label: 'intercambios de stick'),
    ];
  }

  /// Barras de regímenes del cierre: nombre y porcentaje (0–100).
  List<({String name, double percent})> get regimeBars {
    final regs = (engine.report()['regimenes']! as List).cast<Map<String, Object>>();
    return [
      for (final g in regs) (name: g['regimen']! as String, percent: g['porcentaje']! as double),
    ];
  }

  /// Reporte JSON completo (para exportar).
  Map<String, Object> report() => engine.report();

  /// Luz del modo eje: franjas superior/inferior según registro y nivel.
  EjeGlow get ejeGlow {
    final f = field;
    final sz = f.count > 0
        ? 0.3 + f.count / BalancinConst.fieldMaxWidth * 0.7
        : (state == BalancinState.espera ? 0.5 : 0.0);
    final reg = ((f.center - BalancinConst.centerMin) / BalancinConst.centerSpan).clamp(0.0, 1.0).toDouble();
    return EjeGlow(
      topScale: sz * (0.55 + 0.45 * reg),
      bottomScale: sz * (1 - 0.45 * reg),
      opacity: 0.2 + 0.8 * _lightLevel,
      hidden: hiddenActive,
    );
  }

  // ---------------------------------------------------------------------------
  // Ciclo de sesión
  // ---------------------------------------------------------------------------

  void start() {
    final now = nowMs;
    _flashes.clear();
    _ejeFlashes.clear();
    light.clear();
    _bus = BalancinConst.busGain;
    _lostRole = null;
    _lostCause = null;
    // Restaura el volumen del bus: si la sesión anterior terminó durante una
    // pérdida de stick (bus en 0, sin reanudar), la nueva quedaría muda.
    _emit([
      const BusFade(to: BalancinConst.busGain, seconds: 0.3),
      ...engine.start(now, wallClock: DateTime.now()),
    ], now);
    notifyListeners();
  }

  /// Un frame: simuladores → motor → sonido y luz. Llamar desde un Ticker.
  void tick() {
    final now = nowMs;
    if (engine.running) {
      _drive(now);
      _emit(engine.tick(now), now);
    }
    _lightLevel = light.level(now, busGain: _bus);
    _ejeFlashes.removeWhere((f) => now - f.bornMs > ejeFlashMs);
    notifyListeners();
  }

  /// Termina la sesión (botón "Terminar sesión").
  void end() {
    final now = nowMs;
    _emit(engine.end(now), now);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Entradas
  // ---------------------------------------------------------------------------

  /// Tamaño actual del panel [side] (px). Llamar al hacer layout.
  void setPanelSize(PanelSide side, double w, double h) {
    _panelSize[side] = (w: w, h: h);
  }

  /// Posición del dedo en el panel [side], en px locales del panel.
  void feedPanel(PanelSide side, double x, double y) {
    final s = _panelSize[side]!;
    touchFor(sides[side]!).feed(x, y, nowMs, s.w, s.h);
  }

  /// "Intercambiar sticks": cada mitad pasa a leer el otro rol.
  void swapSides() {
    final l = sides[PanelSide.left]!;
    sides[PanelSide.left] = sides[PanelSide.right]!;
    sides[PanelSide.right] = l;
    adultTouch.x = adultTouch.y = null;
    childTouch.x = childTouch.y = null;
    engine.registerSwap();
    notifyListeners();
  }

  void setAutoChild(bool on) {
    _autoChild = on;
    if (!on) childTouch.x = childTouch.y = null;
    notifyListeners();
  }

  void setAutoAdult(bool on, {double? speed}) {
    _autoAdult = on;
    if (speed != null) autoAdultSpeed = speed;
    if (!on) adultTouch.x = adultTouch.y = null;
    notifyListeners();
  }

  /// Escenario de demo del prototipo (null = apagado).
  void setDemo(DemoScenario? d) {
    _demo = d;
    notifyListeners();
  }

  void setEjeMode(bool on) {
    _ejeMode = on;
    notifyListeners();
  }

  PanelSide _sideOf(StickRole r) =>
      sides[PanelSide.left] == r ? PanelSide.left : PanelSide.right;

  void _drive(double now) {
    final t = now / 1000;
    if (_autoChild) {
      final s = _panelSize[_sideOf(StickRole.child)]!;
      final p = SyntheticMotion.childAuto(t);
      childTouch.feedFraction(p.fx, p.fy, now, s.w, s.h);
    }
    if (_autoAdult) {
      final s = _panelSize[_sideOf(StickRole.adult)]!;
      final p = SyntheticMotion.adult(t, speed: autoAdultSpeed);
      adultTouch.feedFraction(p.fx, p.fy, now, s.w, s.h);
    }
    final d = _demo;
    if (d != null) {
      final s = _panelSize[_sideOf(StickRole.adult)]!;
      driveDemo(d, now, adult: adultTouch, child: childTouch, w: s.w, h: s.h);
    }
  }

  // ---------------------------------------------------------------------------
  // Pérdida de stick (se conecta a BLE real en la fase 6)
  // ---------------------------------------------------------------------------

  /// Pausa el juego y apaga el sonido suavemente (1,2 s).
  void loseStick(StickRole role, LossCause cause) {
    _lostRole = role;
    _lostCause = cause;
    _emit(engine.pause(), nowMs);
    _ejeMode = false;
    notifyListeners();
  }

  /// Reanuda desde REPOSO conservando la telemetría.
  void resumeAfterLoss() {
    final now = nowMs;
    _lostRole = null;
    _lostCause = null;
    _emit(engine.resume(now), now);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------

  void _emit(List<SoundCommand> cmds, double now) {
    if (cmds.isEmpty) return;
    for (final c in cmds) {
      switch (c) {
        case NoteOn():
          _flashes[c.index] = (t: now, hidden: c.hidden);
          if (_ejeMode) {
            _ejeFlashes.add(EjeFlash(
              x: 0.10 + 0.80 * c.index / (BalancinConst.numNotes - 1),
              y: _random.nextBool() ? 0.08 + _random.nextDouble() * 0.12 : 0.80 + _random.nextDouble() * 0.12,
              hidden: c.hidden,
              bornMs: now,
            ));
          }
        case BusFade():
          _bus = c.to;
        case OpeningSound():
        case FieldResonance():
        case FinalSound():
          break;
      }
    }
    light.onCommands(cmds, now);
    onSound(cmds);
  }
}

