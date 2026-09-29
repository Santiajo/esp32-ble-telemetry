import 'dart:collection';
import 'dart:math' as math;

import '../constants.dart';
import '../gesture/gesture_reader.dart';
import '../scale.dart';
import '../telemetry/session_metrics.dart';
import 'sound_command.dart';

/// Estados del sistema (plan §4.3). Nombres del prototipo.
enum BalancinState {
  /// Ningún stick activo. Silencio.
  reposo,

  /// Solo el adulto (A): una resonancia de apertura y luego silencio.
  espera,

  /// Solo el niño (B): silencio absoluto.
  silencio,

  /// Ambos: A define el campo, B articula dentro de él.
  activo,

  /// Se detuvo el niño: el campo queda resonando y decae.
  latN,

  /// Se detuvo el adulto: el campo se estrecha hasta agotarse.
  latA,
}

/// Regímenes de relación (índices de [kRegimeNames]).
enum Regime { estable, desplazamiento, densa, minima, coincidencias }

/// El campo de alturas que abre y sostiene el adulto.
class FieldState {
  /// Ancho continuo (0–14).
  double width = 0;

  /// Registro: centro del campo sobre el índice de escala (0–24).
  double center = BalancinConst.centerInitial;

  /// Alturas abiertas (entero, 0–14).
  int count = 0;

  /// Primera altura del campo.
  int lo = 0;

  /// Posición del niño dentro del campo.
  int pos = 0;

  /// Fin del timbre oculto (ms).
  double hiddenUntil = 0;

  /// Velocidad de migración del centro (alturas/s, suavizada).
  double rate = 0;

  bool get isOpen => count > 0;

  void reset() {
    width = 0;
    center = BalancinConst.centerInitial;
    count = 0;
    lo = 0;
    pos = 0;
    hiddenUntil = 0;
    rate = 0;
  }

  /// grave · medio · agudo
  String get registerName => center < BalancinConst.marimbaMaxCenter
      ? 'grave'
      : center < BalancinConst.mixtaMaxCenter
          ? 'medio'
          : 'agudo';
}

/// Motor del Balancín: máquina de estados, campo, articulación, timbre oculto,
/// regímenes y telemetría. Port del bucle `frame()` del prototipo.
///
/// Dart puro y determinista: el tiempo ([now], en ms) lo inyecta quien llama
/// (el Ticker en la app, un bucle simulado en los tests). No toca audio:
/// devuelve [SoundCommand]s.
///
/// Los roles siguen al lector, no a la persona: [adult] es siempre el stick A
/// (grande) y [child] el stick B (pequeño). Intercambiar sticks físicamente no
/// requiere configuración (criterio 7).
class BalancinEngine {
  BalancinEngine({required this.adult, required this.child});

  /// Lector del stick A (abre y sostiene el campo). Se puede reemplazar (dedo → IMU).
  GestureReader adult;

  /// Lector del stick B (articula dentro del campo).
  GestureReader child;

  final FieldState field = FieldState();
  SessionMetrics metrics = SessionMetrics();

  BalancinState? _state;
  bool _running = false;
  bool _closed = false;
  double _last = 0;
  double _latStart = 0;
  double _now = 0;
  DateTime _startedAt = DateTime.now();
  final ListQueue<double> _evTimes = ListQueue<double>();
  Regime? _regime;

  BalancinState get state => _state ?? BalancinState.reposo;
  bool get running => _running;
  bool get closed => _closed;
  DateTime get startedAt => _startedAt;

  /// Notas del niño en el último segundo.
  int get eventsPerSecond => _evTimes.length;

  /// Régimen del último tick en ACTIVO (null fuera de ACTIVO).
  Regime? get regime => _regime;

  /// Hay timbre oculto activo.
  bool get hiddenActive => _now < field.hiddenUntil;

  /// Segundos que le quedan al timbre oculto.
  double get hiddenRemainingS =>
      hiddenActive ? (field.hiddenUntil - _now) / 1000 : 0;

  /// Familia tímbrica vigente.
  TimbreFamily get family => _familyAt(_now);

  double? _smoothedGain;

  /// Familia principal y, cerca de un límite de registro, la familia vecina con
  /// su proporción (0–0,5) para mezclar ambas.
  ({TimbreFamily main, TimbreFamily? blend, double amount}) _familyBlendAt(double now) {
    final main = _familyAt(now);
    const w = BalancinConst.timbreCrossfadeWidth;
    if (main == TimbreFamily.oculto || w <= 0) return (main: main, blend: null, amount: 0.0);
    const bounds = [
      (at: BalancinConst.marimbaMaxCenter, low: TimbreFamily.marimba, high: TimbreFamily.mixta),
      (at: BalancinConst.mixtaMaxCenter, low: TimbreFamily.mixta, high: TimbreFamily.glock),
    ];
    for (final b in bounds) {
      final d = field.center - b.at;
      if (d.abs() < w) {
        final t = (d + w) / (2 * w); // 0 = lado grave del límite, 1 = lado agudo
        final other = main == b.low ? b.high : b.low;
        final amount = t < 0.5 ? t : 1 - t;
        return (main: main, blend: other, amount: amount);
      }
    }
    return (main: main, blend: null, amount: 0.0);
  }

  TimbreFamily _familyAt(double now) {
    if (now < field.hiddenUntil) return TimbreFamily.oculto;
    if (field.center < BalancinConst.marimbaMaxCenter) return TimbreFamily.marimba;
    if (field.center < BalancinConst.mixtaMaxCenter) return TimbreFamily.mixta;
    return TimbreFamily.glock;
  }

  // ---------------------------------------------------------------------------
  // Ciclo de sesión
  // ---------------------------------------------------------------------------

  /// Inicia una sesión nueva en REPOSO. [wallClock] solo se usa para el campo
  /// `inicio` del reporte.
  List<SoundCommand> start(double now, {DateTime? wallClock}) {
    metrics = SessionMetrics();
    _evTimes.clear();
    _smoothedGain = null;
    adult.reset();
    child.reset();
    field.reset();
    _closed = false;
    _regime = null;
    _state = null;
    final out = <SoundCommand>[];
    _setState(BalancinState.reposo, now, out);
    _running = true;
    _last = now;
    _now = now;
    _startedAt = wallClock ?? DateTime.now();
    return out;
  }

  /// Pérdida de conexión de un stick: pausa el motor y apaga el bus en 1,2 s.
  List<SoundCommand> pause() {
    if (!_running) return const [];
    _running = false;
    return const [BusFade(to: 0, seconds: BalancinConst.lostFadeS)];
  }

  /// Reanuda tras una pérdida: vuelve a REPOSO conservando la telemetría
  /// y sube el bus en 0,6 s.
  List<SoundCommand> resume(double now) {
    if (_running || _closed) return const [];
    adult.reset();
    child.reset();
    final out = <SoundCommand>[];
    _state = null; // como el prototipo: no se cierra la latencia en curso
    _setState(BalancinState.reposo, now, out);
    out.add(const BusFade(from: 0, to: BalancinConst.busGain, seconds: BalancinConst.resumeFadeS));
    _running = true;
    _last = now;
    _now = now;
    return out;
  }

  /// Termina la sesión (botón "Terminar" o "Terminar y ver el recuerdo" desde la pérdida).
  List<SoundCommand> end(double now) => _close(now, <SoundCommand>[]);

  /// Registra un intercambio de sticks en el tablero (solo telemetría).
  void registerSwap() => metrics.swaps++;

  /// Reporte JSON de la sesión (claves del prototipo).
  Map<String, Object> report() => buildSessionReport(metrics, _startedAt);

  List<SoundCommand> _close(double now, List<SoundCommand> out) {
    if (_closed) return out;
    _running = false;
    _closed = true;
    if (_state == BalancinState.latN || _state == BalancinState.latA) {
      metrics.latDur.add((now - _latStart) / 1000);
    }
    out.add(const FinalSound());
    return out;
  }

  /// Cambia de estado, contabiliza latencias/reanudaciones y dispara sonidos de sistema.
  void _setState(BalancinState s, double now, List<SoundCommand> out) {
    if (s == _state) return;
    final wasLatency =
        _state == BalancinState.latN || _state == BalancinState.latA;
    if (wasLatency) {
      metrics.latDur.add((now - _latStart) / 1000);
      if (s == BalancinState.activo) metrics.resum++;
    }
    if (s == BalancinState.latN || s == BalancinState.latA) {
      _latStart = now;
      metrics.latN++;
    }
    if (s == BalancinState.espera) out.add(const OpeningSound());
    if (s == BalancinState.latN) {
      out.add(FieldResonance(lo: field.lo, count: field.count, family: _familyAt(now)));
    }
    _state = s;
  }

  // ---------------------------------------------------------------------------
  // Tick (un frame del prototipo)
  // ---------------------------------------------------------------------------

  /// Avanza el motor al instante [now] (ms). Quien llama debe haber alimentado
  /// los lectores antes (dedo, simuladores, BLE). Devuelve los sonidos a emitir.
  List<SoundCommand> tick(double now) {
    if (!_running) return const [];
    final out = <SoundCommand>[];
    var dt = (now - _last) / 1000;
    if (!dt.isFinite || dt < 0) dt = 0;
    dt = math.min(BalancinConst.maxDtS, dt);
    _last = now;
    _now = now;

    final ad = adult;
    final ch = child;
    ad.update(now);
    ch.update(now);
    final a = ad.moving;
    final c = ch.moving;

    // 1) Transiciones de estado
    switch (state) {
      case BalancinState.reposo:
        if (a && c) {
          _setState(BalancinState.activo, now, out);
        } else if (a) {
          _setState(BalancinState.espera, now, out);
        } else if (c) {
          _setState(BalancinState.silencio, now, out);
        }
      case BalancinState.espera:
        if (a && c) {
          _setState(BalancinState.activo, now, out);
        } else if (!a) {
          _setState(BalancinState.reposo, now, out);
        }
      case BalancinState.silencio:
        if (a && c) {
          _setState(BalancinState.activo, now, out);
        } else if (!c) {
          _setState(BalancinState.reposo, now, out);
        }
      case BalancinState.activo:
        if (!c && now - ch.lastMove > BalancinConst.latencyHoldMs) {
          _setState(BalancinState.latN, now, out);
        } else if (!a && now - ad.lastMove > BalancinConst.latencyHoldMs) {
          _setState(BalancinState.latA, now, out);
        }
      case BalancinState.latN:
      case BalancinState.latA:
        if (a && c) {
          _setState(BalancinState.activo, now, out);
        } else if (now - _latStart > BalancinConst.latencyCloseMs) {
          return _close(now, out);
        }
    }
    final st = state;

    // 2) Dinámica del campo: el adulto lo ensancha con la amplitud y mueve el
    //    registro con la velocidad. Sin adulto, el campo se estrecha.
    final f = field;
    final prevCenter = f.center;
    if (a &&
        (st == BalancinState.activo ||
            st == BalancinState.espera ||
            st == BalancinState.latN)) {
      final targetWidth = BalancinConst.widthMin + BalancinConst.widthSpan * ad.amp;
      f.width += (targetWidth - f.width) * math.min(1.0, dt * BalancinConst.widthResponse);
      final targetCenter =
          BalancinConst.centerMin + BalancinConst.centerSpan * ad.vel01;
      f.center += (targetCenter - f.center) * math.min(1.0, dt * BalancinConst.centerResponse);
    } else if (st == BalancinState.latN) {
      f.width -= BalancinConst.shrinkLatN * dt;
    } else if (st == BalancinState.activo ||
        st == BalancinState.latA ||
        st == BalancinState.espera) {
      f.width -= BalancinConst.shrinkActive * dt;
    } else {
      f.width -= BalancinConst.shrinkRest * dt;
    }
    f.width = f.width.clamp(0.0, BalancinConst.fieldMaxWidth).toDouble();
    f.count = f.width < BalancinConst.openThreshold ? 0 : jsRound(f.width);
    f.lo = math.max(0, math.min(BalancinConst.numNotes - f.count, jsRound(f.center - f.count / 2)));
    final dc = (f.center - prevCenter).abs();
    f.rate = f.rate * BalancinConst.rateKeep +
        (dt > 0 ? dc / dt : 0.0) * (1 - BalancinConst.rateKeep);

    // 3) Timbre oculto: ambos sacuden a la vez durante el juego activo.
    if (st == BalancinState.activo && ad.shake && ch.shake && now >= f.hiddenUntil) {
      f.hiddenUntil = now + BalancinConst.hiddenDurationMs;
      metrics.hidden++;
    }
    final hidden = now < f.hiddenUntil;

    // 4) Articulación del niño: una nota por unidad de recorrido, cuantizada al
    //    campo. Sin campo no hay notas (criterio 1).
    if ((st == BalancinState.activo || st == BalancinState.latA) && f.count > 0) {
      final n = ch.consumeArticulations();
      for (var i = 0; i < n; i++) {
        var step = -ch.dy + ch.dx;
        if (step == 0) step = 1;
        f.pos = ((f.pos + step) % f.count + f.count) % f.count;
        final idx = f.lo + f.pos;
        final target = (BalancinConst.noteGainBase + BalancinConst.noteGainSpan * ch.amp) *
            BalancinConst.noteGainScale;
        // Suavizado entre notas consecutivas: evita saltos bruscos de intensidad.
        final prevGain = _smoothedGain;
        const keep = BalancinConst.noteGainSmoothingKeep;
        final gain = prevGain == null ? target : prevGain * keep + target * (1 - keep);
        _smoothedGain = gain;
        final fb = _familyBlendAt(now);
        out.add(NoteOn(
          index: idx,
          midi: kNotes[idx],
          family: fb.main,
          gain: gain,
          hidden: hidden,
          fieldLo: f.lo,
          fieldCount: f.count,
          blendFamily: fb.blend,
          blendAmount: fb.amount,
        ));
        metrics.events++;
        _evTimes.add(now);
      }
    } else {
      ch.discardArticulations();
    }
    while (_evTimes.isNotEmpty && now - _evTimes.first > BalancinConst.eventWindowMs) {
      _evTimes.removeFirst();
    }
    final evs = _evTimes.length;

    // 5) Métricas y clasificación en régimen (solo durante ACTIVO).
    metrics.total += dt;
    if (a && f.count > 0) metrics.fieldOpen += dt;
    metrics.variation += dc;
    if (st == BalancinState.activo) {
      metrics.active += dt;
      final Regime r;
      if (hidden) {
        r = Regime.coincidencias;
      } else if (f.rate > BalancinConst.regimeShiftRate) {
        r = Regime.desplazamiento;
      } else if (f.count >= BalancinConst.denseMinCount && evs >= BalancinConst.denseMinEvents) {
        r = Regime.densa;
      } else if (f.count <= BalancinConst.sparseMaxCount && evs <= BalancinConst.sparseMaxEvents) {
        r = Regime.minima;
      } else {
        r = Regime.estable;
      }
      metrics.reg[r.index] += dt;
      _regime = r;
    } else {
      _regime = null;
    }
    return out;
  }
}
