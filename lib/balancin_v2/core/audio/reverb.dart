/// Reverb mono incorporada en los WAV (plan v2 §4.6).
///
/// El prototipo manda una copia de todo por un convolver (cola de 2,4 s,
/// pasa-bajos de 3,2 kHz, retorno 0,2). En el teléfono no se puede usar el
/// `FreeverbFilter` de SoLoud: solo admite estéreo y el motor corre en mono
/// (en release procesa memoria que no es suya y suena a ruido; visto en la
/// prueba del 18-10-2026). Como la reverb es lineal, se aplica al renderizar
/// cada nota, frase o canción: mismo resultado, sin costo en tiempo real.
///
/// Algoritmo Freeverb (Jezar) en mono: 8 filtros peine con amortiguación en
/// paralelo y 4 pasa-todo en serie, con las longitudes de Freeverb a 44,1 kHz.
/// `roomSize` 0,5 → realimentación 0,84 → caída de ~1,2 s, parecida a la cola
/// del convolver del prototipo (ruido × (1 − t)^3,2).
library;

import 'dart:math' as math;
import 'dart:typed_data';

class ReverbSettings {
  const ReverbSettings({this.roomSize = 0.5, this.damp = 0.5, this.wet = 0.2, this.inputLowpassHz = 3200, this.tailS = 1.5});

  final double roomSize; // 0–1
  final double damp; // 0–1
  /// Ganancia del retorno de la reverb (0,2 en el prototipo).
  final double wet;
  final double inputLowpassHz;

  /// Cola que se agrega al final del render (s).
  final double tailS;

  static const prototype = ReverbSettings();
  static const off = ReverbSettings(wet: 0, tailS: 0);
}

class _Comb {
  _Comb(int size) : _buf = Float64List(size);
  final Float64List _buf;
  int _i = 0;
  double _store = 0;

  double process(double input, double feedback, double damp1, double damp2) {
    final out = _buf[_i];
    _store = out * damp2 + _store * damp1;
    _buf[_i] = input + _store * feedback;
    if (++_i >= _buf.length) _i = 0;
    return out;
  }
}

class _Allpass {
  _Allpass(int size) : _buf = Float64List(size);
  final Float64List _buf;
  int _i = 0;

  double process(double input) {
    final bufout = _buf[_i];
    final out = -input + bufout;
    _buf[_i] = input + bufout * 0.5;
    if (++_i >= _buf.length) _i = 0;
    return out;
  }
}

const List<int> _combTuning = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const List<int> _allpassTuning = [556, 441, 341, 225];

/// Devuelve [dry] + reverb, con [ReverbSettings.tailS] segundos más de cola.
Float64List applyReverb(Float64List dry, {ReverbSettings s = ReverbSettings.prototype, int sr = 44100}) {
  if (s.wet <= 0) return dry;
  final scale = sr / 44100;
  final combs = [for (final n in _combTuning) _Comb(math.max(1, (n * scale).round()))];
  final allpasses = [for (final n in _allpassTuning) _Allpass(math.max(1, (n * scale).round()))];
  final feedback = s.roomSize * 0.28 + 0.7; // Freeverb: scaleroom 0,28 + offsetroom 0,7
  final damp1 = s.damp * 0.4, damp2 = 1 - damp1;
  const fixedGain = 0.015, scaleWet = 3.0;
  final lpA = math.exp(-2 * math.pi * s.inputLowpassHz / sr);
  final out = Float64List(dry.length + (s.tailS * sr).round());
  var lp = 0.0;
  for (var i = 0; i < out.length; i++) {
    final x = i < dry.length ? dry[i] : 0.0;
    lp = x * (1 - lpA) + lp * lpA;
    final input = lp * fixedGain;
    var acc = 0.0;
    for (final c in combs) {
      acc += c.process(input, feedback, damp1, damp2);
    }
    for (final a in allpasses) {
      acc = a.process(acc);
    }
    out[i] = x + acc * s.wet * scaleWet;
  }
  return out;
}
