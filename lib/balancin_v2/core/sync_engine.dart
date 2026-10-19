/// Motor de sincronía de la mecánica v2 (plan v2 §4.4; objeto `G` y `frame()` del prototipo).
///
/// Determinista: el tiempo llega por parámetro (`now`, ms) y la entrada son
/// las inclinaciones que se dan a [adult] y [child] con `feedTilt`. Los
/// efectos (voz, frases, destellos, cierre) salen como [SyncEvent] en el
/// valor de retorno de [start], [tick] y compañía. Los `setTimeout` del
/// prototipo son temporizadores internos que corren al empezar cada [tick].
library;

import 'dart:math' as math;

import 'calibration.dart';
import 'lead_lag.dart';
import 'levels.dart';
import 'params.dart';
import 'stick_state.dart';
import 'telemetry.dart';

enum EngineState { idle, calibrating, playing, levelComplete, songComplete }

enum PlayMode { free, levels }

sealed class SyncEvent {
  const SyncEvent(this.at);

  /// Instante (ms) en que se produjo.
  final double at;
}

/// La voz dice [text].
class SayEvent extends SyncEvent {
  const SayEvent(super.at, this.text);
  final String text;
  @override
  String toString() => 'say($text)';
}

/// Suena una frase (notas MIDI, [step] s entre notas).
class PhraseEvent extends SyncEvent {
  const PhraseEvent(super.at, this.midi, this.step, this.gain);
  final List<int> midi;
  final double step, gain;
  @override
  String toString() => 'phrase($midi)';
}

/// Suena la canción completa (frases de [levelIds], en orden).
class SongEvent extends SyncEvent {
  const SongEvent(super.at, this.levelIds);
  final List<int> levelIds;
}

/// Destello de la luz (corto al lograr un nivel, largo con la canción).
class FlashEvent extends SyncEvent {
  const FlashEvent(super.at, {required this.long});
  final bool long;
}

class GuideChangedEvent extends SyncEvent {
  const GuideChangedEvent(super.at, this.guide);
  final Role guide;
}

/// La frase se arma durante el nivel (§12.3): al pasar cada cuarto del progreso
/// suena su nota ([up]); si el progreso vuelve a bajar de ese cuarto, la nota «cae».
class PhraseStepEvent extends SyncEvent {
  const PhraseStepEvent(super.at, this.step, this.midi, {required this.up});
  final int step; // 1–3
  final int midi;
  final bool up;
  @override
  String toString() => 'step($step ${up ? '↑' : '↓'})';
}

/// Un nivel quedó logrado: guardarlo en el progreso.
class LevelCompletedEvent extends SyncEvent {
  const LevelCompletedEvent(super.at, this.levelId);
  final int levelId;
}

class CalibrationDoneEvent extends SyncEvent {
  const CalibrationDoneEvent(super.at, this.adult, this.child);
  final StickCal? adult, child;
}

/// La sesión terminó: ir al final con [record].
class SessionClosedEvent extends SyncEvent {
  const SessionClosedEvent(super.at, this.record, {required this.byIdle});
  final SessionRecord record;

  /// Cerró sola por inactividad ([SyncParams.endAfter]).
  final bool byIdle;
}

class _Timer {
  _Timer(this.due, this.seq, this.run);
  final double due;
  final int seq;
  final void Function(double now) run;
}

/// Duración de `playPhrase` (s), que fija cuándo sigue el flujo.
double phraseDuration(int notes, double step) => notes * step + 1;

/// Duración de `playSong` (s).
double songDuration(int levelCount) => levelCount * 4 * 0.3 + 2;

class SyncEngine {
  SyncEngine({
    SyncParams? params,
    this.closeOnIdle = false,
    bool Function(int levelId)? isLevelEnabled,
    DateTime Function()? wallClock,
  })  : params = params ?? SyncParams(),
        isLevelEnabled = isLevelEnabled ?? ((_) => true),
        wallClock = wallClock ?? DateTime.now;

  final SyncParams params;

  /// `appMode` del prototipo: cerrar tras [SyncParams.endAfter] s sin juego (flujo de usuario, no el banco).
  bool closeOnIdle;

  /// Si es `false` para el nivel siguiente, al lograr uno la sesión se cierra (plan v2 §10.2).
  final bool Function(int levelId) isLevelEnabled;
  final DateTime Function() wallClock;

  final StickState adult = StickState(Role.adult);
  final StickState child = StickState(Role.child);

  /// Se llama al empezar cada [tick], después de los temporizadores y antes de
  /// actualizar los sticks (como `synthDrive` en `frame()`).
  void Function(double now)? drive;

  // ---- estado (G) ----
  PlayMode mode = PlayMode.levels;
  int levelIndex = 0;
  int part = 0;
  EngineState state = EngineState.idle;
  double prog = 0;
  bool inSync = false;
  double d = 6;
  Role guide = Role.adult;
  bool _guideSwitched = false;
  final List<LevelTelemetry> levelTelemetry = [];
  LevelTelemetry? current;
  final List<int> levelsDone = [];
  double _t0 = 0;
  DateTime startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  double total = 0;
  double syncT = 0;
  double bothT = 0;
  final List<List<double>> traj = [];
  double _trajT = 0;
  double? _idleSince;
  bool _pausedEp = false;
  double? _outSince; // fuera de la zona moviéndose los dos (§12.1)
  int _stepReached = 0; // cuartos de la frase ya sonados (§12.3)
  double _lagT = 0;
  LeadLag? lastLeadLag;
  bool song = false;

  bool running = false;

  /// `dt` (s, con tope de 0,05) del último [tick], para las capas de audio.
  double lastDt = 0;
  bool _closed = true;
  double _last = 0;

  Calibration? _cal;
  double _calT0 = 0;

  // Lo que vio el último tick (para la luz y el banco).
  bool adultActive = false;
  bool childActive = false;
  bool get bothActive => adultActive && childActive;

  final List<_Timer> _timers = [];
  int _timerSeq = 0;
  final List<SyncEvent> _out = [];

  // ---------------- consultas ----------------

  Level? get level => mode == PlayMode.levels ? levels[levelIndex] : null;

  Relation get relation {
    final l = level;
    if (l == null) return Relation.free;
    return l.isSong ? l.parts[part] : l.relation;
  }

  double get tol => (level?.tol ?? 1.2) * params.tolScale;

  double get secs => (level?.sec ?? 8) * params.secScale;

  /// Progreso del nivel (o de la parte) entre 0 y 1.
  double get progFraction => level == null ? 0 : (prog / secs).clamp(0.0, 1.0).toDouble();

  bool get calibrating => state == EngineState.calibrating;

  /// ms transcurridos de la calibración (0 si no está calibrando).
  double calibrationElapsed(double now) => calibrating ? now - _calT0 : 0;

  StickState stick(Role r) => r == Role.adult ? adult : child;

  // ---------------- ciclo de vida ----------------

  List<SyncEvent> start({required PlayMode mode, int levelIndex = 0, bool calibrate = false, required double now}) {
    this.mode = mode;
    this.levelIndex = levelIndex;
    part = 0;
    prog = 0;
    inSync = false;
    levelTelemetry.clear();
    current = null;
    levelsDone.clear();
    _t0 = now;
    startedAt = wallClock();
    total = 0;
    syncT = 0;
    bothT = 0;
    traj.clear();
    _trajT = 0;
    _idleSince = null;
    _pausedEp = false;
    _outSince = null;
    _stepReached = 0;
    _lagT = 0;
    lastLeadLag = null;
    song = false;
    _timers.clear();
    adult.reset();
    child.reset();
    running = true;
    _closed = false;
    _last = now;
    if (calibrate) {
      _startCal(now);
    } else {
      _beginPlay(now);
    }
    return _flush();
  }

  /// Vuelve a medir el rango de cada persona (botón «Calibrar rango» del banco).
  List<SyncEvent> recalibrate(double now) {
    if (running) _startCal(now);
    return _flush();
  }

  /// Cambia de nivel o a Libre sin cortar la sesión (selector del banco).
  List<SyncEvent> switchTo({required PlayMode mode, int levelIndex = 0, required double now}) {
    this.mode = mode;
    this.levelIndex = levelIndex;
    if (running) _beginPlay(now);
    return _flush();
  }

  /// Se perdió un stick: el juego queda en pausa (`loseStick`).
  void pause() {
    running = false;
  }

  /// Volvió el stick (`resumeSession`): misma sesión, sticks reiniciados.
  List<SyncEvent> resume(double now) {
    if (_closed) return _flush();
    adult.reset();
    child.reset();
    _idleSince = null;
    if (state == EngineState.idle) _beginPlay(now);
    running = true;
    _last = now;
    return _flush();
  }

  /// Termina la sesión ahora («Terminar»). También funciona en pausa
  /// («Terminar y ver el recuerdo» de la pantalla de pérdida).
  List<SyncEvent> close(double now) {
    if (_closed) return _flush();
    running = true;
    _close(now, byIdle: false);
    return _flush();
  }

  // ---------------- tick (frame) ----------------

  List<SyncEvent> tick(double now) {
    if (!running) return _flush();
    _runTimers(now);
    if (!running) return _flush();
    var dt = (now - _last) / 1000;
    if (!dt.isFinite || dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    lastDt = dt;
    _last = now;
    drive?.call(now);
    final p = params;
    adult.update(now, dt, p);
    child.update(now, dt, p);
    final aA = adult.active(now), cA = child.active(now), both = aA && cA, tol = this.tol;
    adultActive = aA;
    childActive = cA;
    total += dt;

    if (state == EngineState.calibrating) {
      for (final st in [adult, child]) {
        if (st.has) _cal!.add(st.role, now - _calT0, st.tilt, moving: st.speed > p.onSpeed);
      }
      if (now - _calT0 > Calibration.durationMs) _finishCal(now);
    }

    d = syncDistance(relation, now);
    final wasInSync = inSync;
    inSync = inSync ? d <= p.hyst * tol : d < tol;

    if (state == EngineState.playing) {
      final lt = current!;
      lt.juego += dt;
      lt.dS += d;
      lt.dN++;
      if (both) {
        bothT += dt;
        if (inSync) {
          lt.sinc += dt;
          syncT += dt;
          lt.primera ??= toFixedNum((now - _t0) / 1000 - lt.inicio, 1);
          if (mode == PlayMode.levels) prog += dt;
        }
      }
      if (!both) {
        _idleSince ??= now;
        final idle = now - _idleSince!;
        if (idle > p.idleAfter * 1000) {
          if (!_pausedEp) {
            _pausedEp = true;
            lt.pausas++;
          }
          prog = math.max(0, prog - p.decay * dt);
        }
        if (closeOnIdle && idle > p.endAfter * 1000) {
          _close(now, byIdle: true);
          return _flush();
        }
      } else {
        if (_pausedEp) {
          lt.reanud++;
          _pausedEp = false;
        }
        _idleSince = null;
      }
      // §12.1: salir de la zona moviéndose los dos cuesta, tras un margen.
      if (mode == PlayMode.levels && both && !inSync) {
        if (_outSince == null) {
          _outSince = now;
          if (wasInSync) lt.salidas++;
        }
        if (p.slipDrain > 0 && now - _outSince! > p.slipGrace * 1000) {
          prog = math.max(0, prog - p.slipDrain * dt);
        }
      } else {
        _outSince = null;
      }
      _phraseSteps(now);
      final l = level;
      if (l != null) {
        if (!l.isSong && l.guides.length > 1 && l.guides[1] != null && !_guideSwitched && prog >= secs / 2) {
          _guideSwitched = true;
          _setGuide(l.guides[1]!, now);
        }
        if (prog >= secs) {
          if (l.isSong && part < l.parts.length - 1) {
            _partComplete(now);
          } else {
            _levelComplete(now);
          }
        }
      }
      if (both && now - _lagT > 500) {
        _lagT = now;
        final ll = leadLag(adult, child, now);
        lastLeadLag = ll;
        if (ll != null) {
          lt.lagS += ll.lag;
          lt.lagN++;
          if (ll.lag < -0.05) lt.adultoSigue++;
        }
      }
    }

    if (now - _trajT > 100 && (adult.has || child.has)) {
      _trajT = now;
      traj.add([adult.pos.x, adult.pos.y, child.pos.x, child.pos.y].map((v) => jsRound(v * 10) / 10).toList());
      if (traj.length > 3000) {
        final keep = [for (var i = 0; i < traj.length; i += 2) traj[i]];
        traj
          ..clear()
          ..addAll(keep);
      }
    }
    return _flush();
  }

  // ---------------- distancia ----------------

  /// Distancia entre el niño y donde debería estar según la relación (`syncDist`).
  double syncDistance(Relation rel, double t) {
    if (params.syncLagMs > 0 && rel != Relation.pulse && rel != Relation.follow) return _lagDistance(rel, t);
    final base = _positionDistance(rel, t);
    final w = params.velWeight;
    if (w <= 0) return base;
    // §12.2: la sincronía mira también la velocidad (misma transformación que la posición).
    final pv = adult.vel, cv = child.vel;
    final dv = switch (rel) {
      Relation.together => (cv.y - pv.y).abs(),
      Relation.seesaw => (cv.y + pv.y).abs(),
      Relation.mirror => _hypot(cv.x + pv.x, cv.y - pv.y),
      Relation.same => _hypot(cv.x - pv.x, cv.y - pv.y),
      Relation.free || Relation.song => [
          (cv.y - pv.y).abs(),
          _hypot(cv.x + pv.x, cv.y - pv.y),
          (cv.y + pv.y).abs(),
        ].reduce(math.min),
      Relation.pulse || Relation.follow => 0.0,
    };
    return base + w * dv;
  }

  /// §12.5: `d` con tolerancia de retraso. Prueba desfases τ de −syncLagMs a
  /// +syncLagMs (cada 20 ms; τ > 0 = el niño va detrás) y se queda con el mejor:
  /// el promedio de la distancia de la relación en los últimos 100 ms con el
  /// adulto (o el niño) corrido τ, más `velWeight` por la diferencia de velocidad
  /// medida en esos mismos 100 ms. Así un mismo gesto con un pequeño desfase
  /// cuenta como sincronía a cualquier velocidad; un gesto distinto, no.
  double _lagDistance(Relation rel, double t) {
    final maxLag = params.syncLagMs, w = params.velWeight;
    const stepMs = 20.0, spanMs = 100.0;
    const offsets = [0.0, 25.0, 50.0, 75.0, 100.0];
    var best = double.infinity;
    for (var tau = -maxLag; tau <= maxLag + 1e-9; tau += stepMs) {
      final pa = tau > 0 ? tau : 0.0, ca = tau < 0 ? -tau : 0.0;
      var s = 0.0;
      for (final k in offsets) {
        s += _pairDistance(rel, adult.at(t - k - pa), child.at(t - k - ca));
      }
      var cost = s / offsets.length;
      if (w > 0) {
        final p0 = adult.at(t - pa), p1 = adult.at(t - pa - spanMs);
        final c0 = child.at(t - ca), c1 = child.at(t - ca - spanMs);
        const inv = 1000 / spanMs;
        cost += w *
            _velDistance(rel, P2((p0.x - p1.x) * inv, (p0.y - p1.y) * inv), P2((c0.x - c1.x) * inv, (c0.y - c1.y) * inv));
      }
      if (cost < best) best = cost;
    }
    return best;
  }

  static double _pairDistance(Relation rel, P2 p, P2 c) => switch (rel) {
        Relation.together => (c.y - p.y).abs(),
        Relation.seesaw => (c.y + p.y).abs(),
        Relation.mirror => _hypot(c.x + p.x, c.y - p.y),
        Relation.same => _hypot(c.x - p.x, c.y - p.y),
        _ => [
            (c.y - p.y).abs() + (c.x - p.x).abs() * 0.5,
            _hypot(c.x + p.x, c.y - p.y),
            (c.y + p.y).abs() + (c.x - p.x).abs() * 0.5,
          ].reduce(math.min),
      };

  static double _velDistance(Relation rel, P2 pv, P2 cv) => switch (rel) {
        Relation.together => (cv.y - pv.y).abs(),
        Relation.seesaw => (cv.y + pv.y).abs(),
        Relation.mirror => _hypot(cv.x + pv.x, cv.y - pv.y),
        Relation.same => _hypot(cv.x - pv.x, cv.y - pv.y),
        _ => [(cv.y - pv.y).abs(), _hypot(cv.x + pv.x, cv.y - pv.y), (cv.y + pv.y).abs()].reduce(math.min),
      };

  double _positionDistance(Relation rel, double t) {
    final p = adult.pos, c = child.pos;
    switch (rel) {
      case Relation.together:
        return (c.y - p.y).abs();
      case Relation.seesaw:
        return (c.y + p.y).abs();
      case Relation.mirror:
        return _hypot(c.x + p.x, c.y - p.y);
      case Relation.same:
        return _hypot(c.x - p.x, c.y - p.y);
      case Relation.pulse:
        final ra = adult.rhythm(t, params), rc = child.rhythm(t, params);
        if (ra.amp < 1 || rc.amp < 1 || ra.f == 0 || rc.f == 0) return 6;
        return math.min(6, 6 * (rc.f - ra.f).abs() / math.max(rc.f, ra.f));
      case Relation.follow:
        final gd = guide == Role.child ? child : adult, fl = guide == Role.child ? adult : child;
        var best = 1e9;
        for (var lag = 0.0; lag <= params.followLag + 1e-6; lag += 0.1) {
          var s = 0.0;
          for (var i = 0; i < 15; i++) {
            final tt = t - i * 100;
            final f = fl.at(tt), g = gd.at(tt - lag * 1000);
            s += _hypot(f.x - g.x, f.y - g.y);
          }
          best = math.min(best, s / 15);
        }
        return math.min(6, best);
      case Relation.free:
      case Relation.song:
        return [
          (c.y - p.y).abs() + (c.x - p.x).abs() * 0.5,
          _hypot(c.x + p.x, c.y - p.y),
          (c.y + p.y).abs() + (c.x - p.x).abs() * 0.5,
        ].reduce(math.min);
    }
  }

  /// Dónde debería estar el niño, para dibujar la zona objetivo en el plano (`target`).
  P2? target(double now) {
    final p = adult.pos, c = child.pos;
    return switch (relation) {
      Relation.together => P2(c.x, p.y),
      Relation.seesaw => P2(c.x, -p.y),
      Relation.mirror => P2(-p.x, p.y),
      Relation.same => P2(p.x, p.y),
      Relation.follow => guide == Role.adult ? adult.at(now - 500) : null,
      _ => null,
    };
  }

  // ---------------- telemetría ----------------

  Map<String, Object?> report() => {
        'proyecto': 'Balancín · mecánica v2',
        'nota': 'Solo métricas de movimiento. Sin audio, imagen ni datos identificables.',
        'inicio': startedAt.toUtc().toIso8601String(),
        'modo': mode == PlayMode.free ? 'libre' : 'niveles',
        'duracion_s': toFixedNum(total, 1),
        'en_sincronia_s': toFixedNum(syncT, 1),
        'niveles_logrados': List<int>.of(levelsDone),
        'cancion_completa': song,
        'parametros': params.toJson(),
        'niveles': [for (final lt in levelTelemetry) lt.toReportJson()],
      };

  SessionRecord sessionRecord() {
    final lags = levelTelemetry.where((l) => l.lagN > 0).toList();
    final lead = lags.isEmpty ? null : lags.map((l) => l.lagS / l.lagN).reduce((a, b) => a + b) / lags.length;
    final step = math.max(1, (traj.length / 300).ceil());
    return SessionRecord(
      t: wallClock().millisecondsSinceEpoch,
      mode: mode == PlayMode.free ? 'free' : 'levels',
      levels: List<int>.of(levelsDone),
      dur: total,
      sync: total > 0 ? syncT / total : 0,
      song: song,
      lead: lead,
      traj: [for (var i = 0; i < traj.length; i += step) traj[i]],
    );
  }

  // ---------------- flujo interno ----------------

  void _emit(SyncEvent e) => _out.add(e);

  List<SyncEvent> _flush() {
    final r = List<SyncEvent>.of(_out);
    _out.clear();
    return r;
  }

  void _after(double now, double ms, void Function(double now) run) => _timers.add(_Timer(now + ms, _timerSeq++, run));

  void _runTimers(double now) {
    while (running) {
      _Timer? next;
      for (final t in _timers) {
        if (t.due <= now && (next == null || t.due < next.due || (t.due == next.due && t.seq < next.seq))) next = t;
      }
      if (next == null) return;
      _timers.remove(next);
      next.run(now);
    }
  }

  LevelTelemetry _newLT(Object id, double now) => LevelTelemetry(id, (now - _t0) / 1000);

  void _startCal(double now) {
    state = EngineState.calibrating;
    _calT0 = now;
    _cal = Calibration();
    adult.cal = null;
    child.cal = null;
    _emit(SayEvent(now, 'Muévanse libremente unos segundos.'));
  }

  void _finishCal(double now) {
    final c = _cal!;
    adult.cal = c.result(Role.adult, params);
    child.cal = c.result(Role.child, params);
    adult.resetEdgeStats();
    child.resetEdgeStats();
    _cal = null;
    _emit(CalibrationDoneEvent(now, adult.cal, child.cal));
    _beginPlay(now);
  }

  void _beginPlay(double now) {
    if (mode == PlayMode.levels) {
      _startLevel(now);
    } else {
      state = EngineState.playing;
      current = _newLT('libre', now);
      levelTelemetry.add(current!);
      _emit(SayEvent(now, 'Juego libre. Busquen un movimiento en común.'));
    }
  }

  void _startLevel(double now) {
    final l = level!;
    state = EngineState.playing;
    prog = 0;
    part = 0;
    guide = l.firstGuide;
    _guideSwitched = false;
    inSync = false;
    _outSince = null;
    _stepReached = 0;
    current = _newLT(l.id, now);
    levelTelemetry.add(current!);
    _emit(SayEvent(now, 'Nivel ${l.id}. ${l.name}. ${l.text} ${l.guideText}.'));
  }

  /// §12.3: una nota de la frase por cada cuarto del progreso (el cuarto final es el
  /// nivel logrado). Baja con 0,25 s de margen para no repetir la nota en el borde.
  void _phraseSteps(double now) {
    final l = level;
    if (params.phraseSteps <= 0 || l == null || l.isSong) return;
    final q = secs / 4;
    final step = (prog / q).floor().clamp(0, 3);
    if (step > _stepReached) {
      for (var k = _stepReached + 1; k <= step; k++) {
        _emit(PhraseStepEvent(now, k, l.phraseMidi[k - 1], up: true));
      }
      _stepReached = step;
    } else if (_stepReached > 0 && prog < _stepReached * q - 0.25) {
      _emit(PhraseStepEvent(now, _stepReached, l.phraseMidi[_stepReached - 1], up: false));
      _stepReached--;
    }
  }

  void _setGuide(Role role, double now) {
    guide = role;
    _emit(GuideChangedEvent(now, role));
    _emit(SayEvent(now, 'Ahora guía ${roleNames[role]}.'));
  }

  void _partComplete(double now) {
    final l = level!;
    _emit(PhraseEvent(now, [l.phraseMidi[part]], 0.24, 0.2));
    part++;
    prog = 0;
    inSync = false;
    guide = l.guides[part] ?? Role.adult;
    _emit(GuideChangedEvent(now, guide));
    _emit(SayEvent(now, 'Ahora, ${relationNames[l.parts[part]]}. Guía ${roleNames[guide]}.'));
  }

  void _levelComplete(double now) {
    final l = level!;
    state = EngineState.levelComplete;
    current!.completado = toFixedNum((now - _t0) / 1000 - current!.inicio, 1);
    if (!levelsDone.contains(l.id)) levelsDone.add(l.id);
    _emit(LevelCompletedEvent(now, l.id));
    _emit(FlashEvent(now, long: false));
    _emit(PhraseEvent(now, l.phraseMidi, 0.24, 0.17));
    final dur = phraseDuration(l.phrase.length, 0.24);
    if (l.isSong) {
      _after(now, dur * 1000 + 300, (t) {
        state = EngineState.songComplete;
        song = true;
        _emit(SayEvent(t, 'Terminaron la canción.'));
        _emit(FlashEvent(t, long: true));
        _emit(SongEvent(t, [for (final x in levels) x.id]));
        _after(t, songDuration(levels.length) * 1000 + 800, (t2) => _close(t2, byIdle: false));
      });
    } else {
      _after(now, dur * 1000 + 2200, (t) {
        if (state != EngineState.levelComplete) return;
        final next = levelIndex + 1;
        if (next < levels.length && isLevelEnabled(levels[next].id)) {
          levelIndex = next;
          _startLevel(t);
        } else {
          _close(t, byIdle: false);
        }
      });
    }
  }

  void _close(double now, {required bool byIdle}) {
    if (!running) return;
    running = false;
    _closed = true;
    _timers.clear();
    final rec = sessionRecord();
    state = EngineState.idle;
    _emit(SessionClosedEvent(now, rec, byIdle: byIdle));
  }
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);
