/// Inclinación del stick desde el MPU6050 (plan v2 §4.1).
///
/// Filtro complementario sobre la dirección de la gravedad medida, `ĝ`
/// (vector unitario en el marco del sensor):
///   1. Predicción con el giroscopio (bias restado): `ĝ` gira −ω·dt.
///   2. Corrección con el acelerómetro: `ĝ ← normalizar(ĝ + kAccel·(â − ĝ))`,
///      solo si `| |a| − |a|reposo | < accelGate` (en un gesto brusco manda el giroscopio).
///   3. Ángulos en el marco del usuario ([AxisMap]): `atan2(ĝ·derecha, ĝ·g0)` y
///      `atan2(ĝ·arriba, ĝ·g0)`, en grados.
///
/// El bias del giroscopio y el largo de |a| en reposo se estiman SOLO con el
/// stick quieto: desviación del giro < 3 °/s durante 0,5 s (como
/// `ImuGestureReader`) Y la gravedad sin cambiar más de 2° en esa ventana. Lo
/// segundo evita confundir un giro lento y constante con el bias.
/// Hasta la primera estimación del bias, `ĝ` sale solo del acelerómetro (el
/// stick B tiene ~41,6 °/s de bias: integrarlo sin restar derivaría en segundos).
///
/// `dt` sale del reloj del ESP32 (`t_ms`), con vuelta de reloj y un tope de
/// 0,1 s para huecos de BLE.
library;

import 'dart:collection';
import 'dart:math' as math;

import '../../../balancin/core/ble/imu_frame_parser.dart';
import '../params.dart';
import 'axis_map.dart';
import 'vec3.dart';

class _Still {
  _Still(this.t, this.w, this.mag, this.dir);
  final double t; // ms (reloj del ESP desenrollado)
  final V3 w; // giro crudo (°/s)
  final double mag; // |a| (g)
  final V3 dir; // â
}

class TiltReader {
  TiltReader({SyncParams? params, AxisMap? axes, this.uprightAxis = 1, this.rightAxis = 0})
      : params = params ?? SyncParams(),
        _axes = axes,
        _axesFromDefault = axes == null;

  /// `kAccel` y `accelGate` (ajustables en el banco).
  final SyncParams params;

  /// Ejes por defecto (§10.1): vertical = Y, derecha = X.
  final int uprightAxis, rightAxis;

  static const double stillStdDps = 3;
  static const double stillMaxTiltDeg = 2;
  static const double stillWindowMs = 500;
  static const double biasAlpha = 0.2;
  static const double maxDtS = 0.1;

  AxisMap? _axes;
  bool _axesFromDefault;

  V3 _bias = V3.zero;
  bool _calibrated = false;
  double _restMag = 1;
  final ListQueue<_Still> _still = ListQueue<_Still>();

  V3? _g;
  int? _prevT;
  double _tU = 0;
  bool _correcting = false;
  double _accMag = 1;

  ImuSample? _lastSample;
  double _lastArrival = -1e9;
  int _samplesTotal = 0;
  final ListQueue<double> _arrivals = ListQueue<double>();

  // ---------------- salida ----------------

  /// Hay al menos una muestra válida.
  bool get hasTilt => _g != null && _axes != null;

  /// Inclinación hacia la derecha (°).
  double get tiltX => hasTilt ? _axes!.tiltDeg(_g!).x : 0;

  /// Inclinación hacia arriba/adelante (°).
  double get tiltY => hasTilt ? _axes!.tiltDeg(_g!).y : 0;

  /// Gravedad estimada (unitaria, marco del sensor). Para el asistente de ejes.
  V3? get gravity => _g;

  // ---------------- diagnóstico (banco) ----------------

  bool get calibrated => _calibrated;
  V3 get biasDps => _bias;
  double get restMagG => _restMag;
  double get accelMagG => _accMag;

  /// La última muestra corrigió con el acelerómetro (si no, solo giroscopio).
  bool get correcting => _correcting;
  AxisMap? get axes => _axes;

  /// Los ejes son los supuestos por defecto (no salieron del asistente ni de un valor guardado).
  bool get axesFromDefault => _axesFromDefault;
  ImuSample? get lastSample => _lastSample;
  double get lastArrivalMs => _lastArrival;
  int get samplesTotal => _samplesTotal;

  /// Muestras recibidas en el último segundo (por hora de llegada).
  double get sampleRateHz => _arrivals.length.toDouble();

  // ---------------- control ----------------

  /// Ejes del asistente o guardados para este stick.
  void setAxes(AxisMap map) {
    _axes = map;
    _axesFromDefault = false;
  }

  /// Vuelve a los ejes por defecto (se resuelven con la próxima muestra).
  void useDefaultAxes() {
    _axes = _g == null ? null : AxisMap.defaultFor(_g!, uprightAxis: uprightAxis, rightAxis: rightAxis);
    _axesFromDefault = true;
  }

  /// Olvida el bias: vuelve a esperar 0,5 s de quietud (y usa solo el acelerómetro).
  void resetCalibration() {
    _calibrated = false;
    _bias = V3.zero;
    _restMag = 1;
    _still.clear();
  }

  /// [arrivalMs] = hora de llegada en el reloj del teléfono.
  void addSample(ImuSample s, double arrivalMs) {
    _lastSample = s;
    _lastArrival = arrivalMs;
    _samplesTotal++;
    _arrivals.add(arrivalMs);
    while (_arrivals.isNotEmpty && arrivalMs - _arrivals.first > 1000) {
      _arrivals.removeFirst();
    }

    final a = V3(s.axG, s.ayG, s.azG);
    final mag = a.length;
    final ah = a.normalized();
    if (ah == null) return; // lectura nula: sensor desconectado o saturado en 0
    _accMag = mag;
    final w = V3(s.gxDps, s.gyDps, s.gzDps);

    final prev = _prevT;
    var dt = prev == null ? 0.0 : ImuFrameParser.ticksDiff(s.tMs, prev) / 1000;
    if (dt < 0) dt = 0;
    if (dt > maxDtS) dt = maxDtS;
    _prevT = s.tMs;
    _tU += dt * 1000;

    _updateStill(w, mag, ah);

    final g = _g;
    if (g == null || !_calibrated) {
      _g = ah;
      _correcting = true;
    } else {
      var next = g;
      final om = (w - _bias) * (math.pi / 180);
      final speed = om.length;
      if (speed > 0 && dt > 0) next = next.rotate(om * (1 / speed), -speed * dt);
      _correcting = (mag - _restMag).abs() < params.accelGate;
      if (_correcting) next = next + (ah - next) * params.kAccel;
      _g = next.normalized() ?? ah;
    }
    _axes ??= AxisMap.defaultFor(_g!, uprightAxis: uprightAxis, rightAxis: rightAxis);
  }

  void _updateStill(V3 w, double mag, V3 dir) {
    _still.add(_Still(_tU, w, mag, dir));
    while (_still.isNotEmpty && _tU - _still.first.t > stillWindowMs) {
      _still.removeFirst();
    }
    if (_still.length < 20 || _tU - _still.first.t < stillWindowMs * 0.9) return;
    final n = _still.length;
    var m = V3.zero;
    var mm = 0.0;
    var md = V3.zero;
    for (final q in _still) {
      m = m + q.w;
      mm += q.mag;
      md = md + q.dir;
    }
    m = m * (1 / n);
    mm /= n;
    final meanDir = md.normalized();
    if (meanDir == null) return;
    const maxTilt = stillMaxTiltDeg * math.pi / 180;
    for (final q in _still) {
      if (q.dir.angleTo(meanDir) > maxTilt) return;
    }
    var vx = 0.0, vy = 0.0, vz = 0.0;
    for (final q in _still) {
      final d = q.w - m;
      vx += d.x * d.x;
      vy += d.y * d.y;
      vz += d.z * d.z;
    }
    const lim = stillStdDps * stillStdDps;
    if (vx / n >= lim || vy / n >= lim || vz / n >= lim) return;
    if (!_calibrated) {
      _bias = m;
      _restMag = mm;
      _calibrated = true;
    } else {
      _bias = _bias + (m - _bias) * biasAlpha;
      _restMag += (mm - _restMag) * biasAlpha;
    }
  }
}
