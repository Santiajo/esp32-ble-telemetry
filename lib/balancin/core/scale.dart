import 'dart:math' as math;

import 'constants.dart';

/// 25 alturas pentatónicas (C mayor: C D E G A) en 5 octavas, en MIDI desde C3.
/// `NOTES[i] = 48 + 12*floor(i/5) + [0,2,4,7,9][i%5]`
final List<int> kNotes = List<int>.unmodifiable(
  List<int>.generate(
    BalancinConst.numNotes,
    (i) =>
        BalancinConst.baseMidi +
        12 * (i ~/ 5) +
        BalancinConst.pentatonicOffsets[i % 5],
  ),
);

/// Frecuencia en Hz de una nota MIDI (A4 = 440 Hz).
double midiToHz(num midi) => 440.0 * math.pow(2, (midi - 69) / 12).toDouble();

/// Clases de altura (0–11) permitidas por la escala.
final Set<int> kPentatonicPitchClasses =
    Set<int>.unmodifiable(BalancinConst.pentatonicOffsets);

/// `Math.round` de JavaScript (redondea .5 hacia +∞), para paridad exacta con el prototipo.
int jsRound(double x) => (x + 0.5).floor();
