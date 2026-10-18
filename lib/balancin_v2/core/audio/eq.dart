/// Ecualización del prototipo como ganancia por frecuencia (plan v2 §4.6).
///
/// El prototipo pasa todo por: pasa-altos 70 Hz (Q 0,7) → low-shelf 220 Hz
/// (+1 dB) → pico 1,4 kHz (−2 dB, Q 0,8) → high-shelf 3,8 kHz (−5 dB) →
/// pasa-bajos 8,5 kHz (Q 0,5). En v2 todo el sonido es suma de senos (voces
/// continuas y parciales de cada nota), y un filtro lineal sobre un seno solo
/// cambia su amplitud: basta con multiplicar cada seno por la respuesta del
/// filtro en su frecuencia. Mismo resultado, sin la latencia de un EQ por
/// bloques (el `ParametricEq` de SoLoud usa STFT).
///
/// Fórmulas de los `BiquadFilterNode` de Web Audio (Audio EQ Cookbook; en
/// Web Audio el Q de los pasa-altos/bajos va en dB y los shelf usan S = 1).
library;

import 'dart:math' as math;

const double eqSampleRate = 44100;

class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a0, this.a1, this.a2);
  final double b0, b1, b2, a0, a1, a2;

  /// |H(e^{jω})| en [hz].
  double magnitude(double hz) {
    final w = 2 * math.pi * hz / eqSampleRate;
    final c1 = math.cos(w), s1 = math.sin(w), c2 = math.cos(2 * w), s2 = math.sin(2 * w);
    final nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2);
    final dr = a0 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2);
    return math.sqrt((nr * nr + ni * ni) / (dr * dr + di * di));
  }
}

_Biquad _pass(double f0, double qDb, {required bool high}) {
  final w0 = 2 * math.pi * f0 / eqSampleRate;
  final alpha = math.sin(w0) / (2 * math.pow(10, qDb / 20));
  final c = math.cos(w0);
  return high
      ? _Biquad((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
      : _Biquad((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha);
}

_Biquad _shelf(double f0, double gainDb, {required bool high}) {
  final a = math.pow(10, gainDb / 40).toDouble();
  final w0 = 2 * math.pi * f0 / eqSampleRate;
  final c = math.cos(w0);
  final alpha = math.sin(w0) / 2 * math.sqrt(2); // S = 1
  final k = 2 * math.sqrt(a) * alpha;
  if (high) {
    return _Biquad(
      a * ((a + 1) + (a - 1) * c + k),
      -2 * a * ((a - 1) + (a + 1) * c),
      a * ((a + 1) + (a - 1) * c - k),
      (a + 1) - (a - 1) * c + k,
      2 * ((a - 1) - (a + 1) * c),
      (a + 1) - (a - 1) * c - k,
    );
  }
  return _Biquad(
    a * ((a + 1) - (a - 1) * c + k),
    2 * a * ((a - 1) - (a + 1) * c),
    a * ((a + 1) - (a - 1) * c - k),
    (a + 1) + (a - 1) * c + k,
    -2 * ((a - 1) + (a + 1) * c),
    (a + 1) + (a - 1) * c - k,
  );
}

_Biquad _peak(double f0, double gainDb, double q) {
  final a = math.pow(10, gainDb / 40).toDouble();
  final w0 = 2 * math.pi * f0 / eqSampleRate;
  final alpha = math.sin(w0) / (2 * q);
  final c = math.cos(w0);
  return _Biquad(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a);
}

final List<_Biquad> _chain = [
  _pass(70, 0.7, high: true),
  _shelf(220, 1, high: false),
  _peak(1400, -2, 0.8),
  _shelf(3800, -5, high: true),
  _pass(8500, 0.5, high: false),
];

/// Ganancia lineal de la cadena de EQ del prototipo para un seno de [hz].
double eqGain(double hz) {
  if (hz <= 0 || hz >= eqSampleRate / 2) return 0;
  var g = 1.0;
  for (final f in _chain) {
    g *= f.magnitude(hz);
  }
  return g;
}

/// Lo mismo en dB (para tests y el banco).
double eqGainDb(double hz) => 20 * math.log(eqGain(hz)) / math.ln10;
