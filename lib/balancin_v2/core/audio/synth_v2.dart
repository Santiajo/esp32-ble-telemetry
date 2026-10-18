/// Síntesis de las notas de la mecánica v2 (plan v2 §4.6; `FAM` y `AU.tone` del prototipo).
///
/// Por parcial: seno con ataque lineal de 12 ms hasta el pico y caída
/// exponencial con constante `decay·dur/4,5` (`setTargetAtTime`), cortado a
/// `decay·dur + 0,25 s`. Pico = `gain·g·(0,6 si f > 3 kHz)`; parciales sobre
/// 9 kHz se omiten. Además cada parcial se multiplica por la respuesta de la
/// EQ del prototipo en su frecuencia ([eqGain]). La reverb también va
/// incorporada en el WAV ([applyReverb]): la de SoLoud no sirve en mono.
///
/// La atenuación por polifonía del prototipo (`1/√(1 + 0,35·voces)`) depende
/// de cuántas voces suenan en ese momento: la aplica el motor de plataforma al
/// reproducir ([polyphonyGain]).
///
/// Dart puro: los WAV se generan en un Isolate y se cargan con `SoLoud.loadMem`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../../balancin/core/audio/synth_renderer.dart' show Partial, SynthRenderer;
import '../levels.dart';
import 'eq.dart';
import 'reverb.dart';

class TimbreV2 {
  const TimbreV2(this.name, this.decay, this.partials);
  final String name;
  final double decay; // s
  final List<Partial> partials;
}

abstract final class TimbresV2 {
  static const marimba = TimbreV2('marimba', 1.1, [Partial(1, 1, 1), Partial(4, 0.16, 0.3), Partial(10, 0.04, 0.12)]);
  static const glock = TimbreV2('glock', 1.9, [Partial(1, 1, 1), Partial(2.76, 0.22, 0.7), Partial(5.4, 0.07, 0.4)]);
  static const pad = TimbreV2('pad', 1.6, [Partial(1, 1, 1), Partial(2, 0.12, 0.5)]);
  static const low = TimbreV2('low', 3, [Partial(1, 1, 1), Partial(2, 0.25, 0.6), Partial(3, 0.1, 0.4)]);
}

double midiHz(num m) => 440 * math.pow(2, (m - 69) / 12).toDouble();

/// Atenuación por polifonía del prototipo, con [voices] parciales sonando.
double polyphonyGain(int voices) => 1 / math.sqrt(1 + voices * 0.35);

/// Máximo de parciales simultáneos del prototipo (por encima no suena la nota nueva).
const int maxPartialVoices = 22;

class ToneV2 {
  const ToneV2({required this.midi, required this.timbre, this.gain = 1, this.decay, this.offsetS = 0});
  final num midi;
  final TimbreV2 timbre;
  final double gain;
  final double? decay;
  final double offsetS;

  double get dec => decay ?? timbre.decay;

  double get endS {
    var d = 0.0;
    for (final p in timbre.partials) {
      d = math.max(d, p.dur);
    }
    return offsetS + dec * d + SynthV2.stopTailS;
  }

  /// Parciales que suenan (bajo 9 kHz), para contar voces.
  int get audiblePartials => timbre.partials.where((p) => midiHz(midi) * p.ratio <= SynthV2.maxPartialHz).length;
}

abstract final class SynthV2 {
  static const int sampleRate = 44100;
  static const double attackS = 0.012;
  static const double stopTailS = 0.25;
  static const double maxPartialHz = 9000;

  /// Muestras flotantes de una lista de notas (escala real).
  static Float64List render(List<ToneV2> tones, {int sr = sampleRate}) {
    var end = 0.0;
    for (final t in tones) {
      end = math.max(end, t.endS);
    }
    final out = Float64List((end * sr).ceil() + 1);
    for (final t in tones) {
      _add(out, t, sr);
    }
    return out;
  }

  static void _add(Float64List out, ToneV2 t, int sr) {
    final f0 = midiHz(t.midi);
    final start = (t.offsetS * sr).round();
    final attackN = math.max(1, (attackS * sr).round());
    for (final p in t.timbre.partials) {
      final fr = f0 * p.ratio;
      if (fr > maxPartialHz) continue;
      final pk = math.max(0.0002, t.gain * p.gain * (fr > 3000 ? 0.6 : 1)) * eqGain(fr);
      final tau = t.dec * p.dur / 4.5;
      final stopN = ((t.dec * p.dur + stopTailS) * sr).round();
      final decayMul = math.exp(-1 / (tau * sr));
      final w = 2 * math.pi * fr / sr;
      var env = 0.0;
      for (var n = 0; n < stopN; n++) {
        final idx = start + n;
        if (idx >= out.length) break;
        if (n < attackN) {
          env = pk * n / attackN;
        } else if (n == attackN) {
          env = pk;
        } else {
          env *= decayMul;
        }
        out[idx] += math.sin(w * n) * env;
      }
    }
  }

  /// WAV PCM 16-bit mono con la reverb incorporada (a media escala, como v1:
  /// reproducir con [SynthRenderer.volumeFor]).
  static Uint8List wav(List<ToneV2> tones, {ReverbSettings reverb = ReverbSettings.prototype}) =>
      SynthRenderer.toWav(applyReverb(render(tones), s: reverb));
}

// ---------------------------------------------------------------------------
// Planes de notas (mismos valores que el prototipo)
// ---------------------------------------------------------------------------

/// Nota del niño (marimba) a ganancia 1: la ganancia real se aplica al reproducir.
ToneV2 childNoteTone(int midi) => ToneV2(midi: midi, timbre: TimbresV2.marimba);

/// Nota del pad que repite las frases ganadas, a ganancia 1.
ToneV2 padTone(int midi) => ToneV2(midi: midi, timbre: TimbresV2.pad, decay: 1.6);

/// Nota suelta de glock con decay 2 (frases), a ganancia 1.
ToneV2 phraseNoteTone(int midi) => ToneV2(midi: midi, timbre: TimbresV2.glock, decay: 2);

/// `playPhrase(names, step, gain)`: glock, decay 2, ganancias incorporadas.
List<ToneV2> phraseTones(List<int> midi, {double step = 0.24, double gain = 0.17}) => [
      for (var i = 0; i < midi.length; i++)
        ToneV2(midi: midi[i], timbre: TimbresV2.glock, gain: gain, decay: 2, offsetS: 0.05 + i * step),
    ];

/// `playSong(ids)`: por nivel, un bajo low (raíz − 12) y sus 4 notas en glock, cada 0,3 s.
List<ToneV2> songTones(List<int> levelIds) {
  const step = 0.3;
  final out = <ToneV2>[];
  var k = 0;
  for (final id in levelIds) {
    final ph = levelById(id).phraseMidi;
    out.add(ToneV2(midi: ph.first - 12, timbre: TimbresV2.low, gain: 0.12, decay: 2.4, offsetS: 0.1 + k * step));
    for (final m in ph) {
      out.add(ToneV2(midi: m, timbre: TimbresV2.glock, gain: 0.13, decay: 2, offsetS: 0.1 + k * step));
      k++;
    }
  }
  return out;
}

/// Cierre de sesión: do3, mi3, sol3 en low, ganancia 0,16, decay 4, cada 0,12 s.
List<ToneV2> closingTones() => [
      for (var i = 0; i < 3; i++) ToneV2(midi: const [48, 52, 55][i], timbre: TimbresV2.low, gain: 0.16, decay: 4, offsetS: i * 0.12),
    ];

/// Stick vinculado (preparación): do5 en glock, ganancia 0,2, decay 0,8.
List<ToneV2> chimeTones() => const [ToneV2(midi: 72, timbre: TimbresV2.glock, gain: 0.2, decay: 0.8)];

/// Notas de todas las frases (para precargar pad y notas sueltas de glock).
Set<int> allPhraseMidi() => {for (final l in levels) ...l.phraseMidi};
