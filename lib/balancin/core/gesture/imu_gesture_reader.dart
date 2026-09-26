import 'dart:collection';
import 'dart:math' as math;

import '../ble/imu_frame_parser.dart';
import 'gesture_reader.dart';

/// Umbrales del lector IMU (plan §4.2). Son mutables para ajustarlos en vivo
/// desde el panel de ajuste del tablero; los valores por defecto son la
/// propuesta inicial del plan, validada con gestos sintéticos.
class ImuTuning {
  /// ω suavizada por encima de esto → empieza a contar como movimiento (°/s).
  double onDps = 25;

  /// ω suavizada por debajo de esto → deja de contar (histéresis) (°/s).
  double offDps = 12;

  /// ω que corresponde a vel01 = 1 (°/s).
  double omegaMaxDps = 400;

  /// Excursión angular en 0,8 s que corresponde a amp = 1 (°).
  double ampFullDeg = 90;

  /// Recorrido angular por cada nota del niño (°). Equivale a los 42 px del dedo.
  double articulationDeg = 25;

  /// |ω| mínima en el eje dominante para contar una inversión de sacudida (°/s).
  double shakeMinDps = 80;

  /// |ω| mínima para actualizar la dirección (°/s).
  double dirMinDps = 15;

  /// Desviación estándar máxima por eje para considerar el stick quieto (°/s).
  double stillStdDps = 3;

  /// Ventana de quietud para estimar el bias del giroscopio (ms).
  double calibrationMs = 500;

  /// Cuánto se corrige el bias en cada estimación posterior a la primera (0–1).
  double biasAlpha = 0.2;

  /// Suavizado de ω: ω = ω*keep + |g|*(1-keep).
  double omegaEmaKeep = 0.7;
}

class _Hist {
  _Hist(this.t, this.thx, this.thy, this.thz, this.gx, this.gy, this.gz);
  final double t;
  final double thx, thy, thz; // ángulo integrado (°)
  final double gx, gy, gz; // velocidad angular corregida (°/s)

  double th(int axis) => axis == 0 ? thx : (axis == 1 ? thy : thz);
  double g(int axis) => axis == 0 ? gx : (axis == 1 ? gy : gz);
}

class _Still {
  _Still(this.t, this.x, this.y, this.z);
  final double t;
  final double x, y, z;
}

int _sgn(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

/// Lectura de gesto desde el giroscopio de un stick (MPU6050, protocolo v2).
///
/// Produce las mismas señales que [TouchGestureReader] a partir de la velocidad
/// angular:
///   moving  histéresis de dos niveles sobre ω suavizada + ventana de 200 ms
///   vel01   ω / 400 °/s
///   amp     excursión angular (3 ejes) en 0,8 s / 90°
///   dx, dy  signo del eje dominante y del segundo eje
///   shake   ≥ 4 inversiones del eje dominante con |ω| > 80 °/s en 0,6 s
///   articulaciones: una cada 25° de recorrido angular mientras hay movimiento
///
/// El bias del giroscopio se estima SOLO cuando el stick está realmente quieto
/// (desviación baja durante 0,5 s). Mientras no hay una primera calibración,
/// el lector se considera quieto (nunca genera notas por error).
///
/// Tiempos: [addSample] recibe la hora de llegada en el reloj del teléfono
/// (la misma base que usa el motor). La integración usa el reloj del ESP32
/// (`tMs`), que es más preciso que la hora de llegada por BLE.
class ImuGestureReader implements GestureReader {
  ImuGestureReader({ImuTuning? tuning}) : tuning = tuning ?? ImuTuning();

  final ImuTuning tuning;

  // --- calibración (se conserva en reset) ---
  double _bx = 0, _by = 0, _bz = 0;
  bool _calibrated = false;
  final ListQueue<_Still> _still = ListQueue<_Still>();

  // --- estado de movimiento ---
  final ListQueue<_Hist> _h = ListQueue<_Hist>();
  double _thx = 0, _thy = 0, _thz = 0;
  double _omega = 0;
  bool _active = false;
  double _lastMove = -1e9;
  double _lastArrival = -1e9;
  int? _prevT;
  double _acc = 0;
  int _dx = 0, _dy = 0;
  bool _shake = false;
  bool _moving = false;
  double _amp = 0;
  int _dominant = 2;
  ImuSample? _lastSample;
  int _samplesTotal = 0;

  // ---------------- GestureReader ----------------
  @override
  bool get moving => _moving;
  @override
  double get lastMove => _lastMove;
  @override
  double get amp => _amp;
  @override
  double get vel01 => (_omega / tuning.omegaMaxDps).clamp(0.0, 1.0).toDouble();
  @override
  int get dx => _dx;
  @override
  int get dy => _dy;
  @override
  bool get shake => _shake;

  // ---------------- Depuración / panel de ajuste ----------------
  bool get calibrated => _calibrated;

  /// Bias estimado por eje (°/s).
  ({double x, double y, double z}) get biasDps => (x: _bx, y: _by, z: _bz);

  /// ω suavizada (°/s).
  double get omegaDps => _omega;

  /// Eje dominante del gesto: 0 = X, 1 = Y, 2 = Z.
  int get dominantAxis => _dominant;

  /// Hay movimiento según la histéresis (sin la ventana de 200 ms).
  bool get active => _active;

  /// Última muestra cruda recibida.
  ImuSample? get lastSample => _lastSample;

  /// Muestras recibidas desde el último reset.
  int get samplesTotal => _samplesTotal;

  /// Hora de llegada (reloj del teléfono, ms) de la última muestra.
  double get lastArrivalMs => _lastArrival;

  /// Muestras por segundo (según la hora de llegada, último segundo).
  double get sampleRateHz => _h.length.toDouble();

  /// Recorrido angular pendiente de convertirse en notas (°).
  double get pendingArticulationDeg => _acc;

  /// Agrega una muestra del stick. [nowMs] = hora de llegada en el reloj del teléfono.
  void addSample(ImuSample s, double nowMs) {
    final t = tuning;
    _lastArrival = nowMs;
    _lastSample = s;
    _samplesTotal++;
    final rx = s.gxDps, ry = s.gyDps, rz = s.gzDps;

    // 1) Estimación del bias cuando el stick está quieto.
    _still.add(_Still(nowMs, rx, ry, rz));
    while (_still.isNotEmpty && nowMs - _still.first.t > t.calibrationMs) {
      _still.removeFirst();
    }
    if (_still.length >= 20 && nowMs - _still.first.t >= t.calibrationMs * 0.9) {
      final n = _still.length;
      var mx = 0.0, my = 0.0, mz = 0.0;
      for (final q in _still) {
        mx += q.x;
        my += q.y;
        mz += q.z;
      }
      mx /= n;
      my /= n;
      mz /= n;
      var vx = 0.0, vy = 0.0, vz = 0.0;
      for (final q in _still) {
        vx += (q.x - mx) * (q.x - mx);
        vy += (q.y - my) * (q.y - my);
        vz += (q.z - mz) * (q.z - mz);
      }
      final lim = t.stillStdDps * t.stillStdDps;
      if (vx / n < lim && vy / n < lim && vz / n < lim) {
        if (!_calibrated) {
          _bx = mx;
          _by = my;
          _bz = mz;
          _calibrated = true;
        } else {
          _bx += (mx - _bx) * t.biasAlpha;
          _by += (my - _by) * t.biasAlpha;
          _bz += (mz - _bz) * t.biasAlpha;
        }
      }
    }
    if (!_calibrated) {
      _prevT = s.tMs;
      return;
    }

    // 2) Integración con el reloj del ESP32.
    final prev = _prevT;
    var dt = prev == null ? 0.0 : ImuFrameParser.ticksDiff(s.tMs, prev) / 1000;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    _prevT = s.tMs;

    final gx = rx - _bx, gy = ry - _by, gz = rz - _bz;
    _thx += gx * dt;
    _thy += gy * dt;
    _thz += gz * dt;

    final om = math.sqrt(gx * gx + gy * gy + gz * gz);
    _omega = _omega * t.omegaEmaKeep + om * (1 - t.omegaEmaKeep);
    if (_omega > t.onDps) {
      _active = true;
    } else if (_omega < t.offDps) {
      _active = false;
    }
    if (_active) {
      _lastMove = nowMs;
      _acc += om * dt;
    }

    _h.add(_Hist(nowMs, _thx, _thy, _thz, gx, gy, gz));
    while (_h.isNotEmpty && nowMs - _h.first.t > 1000) {
      _h.removeFirst();
    }
  }

  @override
  void update(double now) {
    final t = tuning;
    if (now - _lastArrival > 100) {
      // Sin datos (stick desconectado o cola BLE atrasada): ω decae.
      _omega *= 0.85;
      if (_omega < t.offDps) _active = false;
    }
    _moving = now - _lastMove < 200;

    // Ventana de 0,8 s: amplitud, eje dominante, dirección y sacudida.
    var n = 0;
    final minTh = [1e18, 1e18, 1e18];
    final maxTh = [-1e18, -1e18, -1e18];
    final energy = [0.0, 0.0, 0.0];
    _Hist? last;
    for (final q in _h) {
      if (now - q.t > 800) continue;
      n++;
      for (var a = 0; a < 3; a++) {
        final th = q.th(a);
        if (th < minTh[a]) minTh[a] = th;
        if (th > maxTh[a]) maxTh[a] = th;
        energy[a] += q.g(a) * q.g(a);
      }
      last = q;
    }
    if (n < 2 || last == null) {
      _amp = 0;
      _shake = false;
      return;
    }
    var exc2 = 0.0;
    for (var a = 0; a < 3; a++) {
      final r = maxTh[a] - minTh[a];
      exc2 += r * r;
    }
    _amp = (math.sqrt(exc2) / t.ampFullDeg).clamp(0.0, 1.0).toDouble();

    final order = [0, 1, 2]..sort((a, b) => energy[b].compareTo(energy[a]));
    _dominant = order[0];
    final second = order[1];
    if (last.g(_dominant).abs() > t.dirMinDps) _dx = _sgn(last.g(_dominant));
    if (last.g(second).abs() > t.dirMinDps) _dy = _sgn(last.g(second));

    var inv = 0;
    var lastSign = 0;
    for (final q in _h) {
      if (now - q.t > 600) continue;
      final v = q.g(_dominant);
      if (v.abs() <= t.shakeMinDps) continue;
      final sx = _sgn(v);
      if (lastSign != 0 && sx != lastSign) inv++;
      lastSign = sx;
    }
    _shake = inv >= 4;
  }

  @override
  int consumeArticulations() {
    var n = 0;
    while (_acc >= tuning.articulationDeg) {
      _acc -= tuning.articulationDeg;
      n++;
    }
    return n;
  }

  @override
  void discardArticulations() {
    _acc = 0;
  }

  /// Reinicia el estado de movimiento. CONSERVA la calibración del giroscopio
  /// (es una propiedad del sensor, no de la sesión).
  @override
  void reset() {
    _h.clear();
    _thx = _thy = _thz = 0;
    _omega = 0;
    _active = false;
    _lastMove = -1e9;
    _prevT = null;
    _acc = 0;
    _dx = 0;
    _dy = 0;
    _shake = false;
    _moving = false;
    _amp = 0;
    _samplesTotal = 0;
  }

  /// Olvida la calibración: el lector vuelve a esperar 0,5 s de quietud.
  void resetCalibration() {
    _calibrated = false;
    _bx = _by = _bz = 0;
    _still.clear();
    reset();
  }
}
