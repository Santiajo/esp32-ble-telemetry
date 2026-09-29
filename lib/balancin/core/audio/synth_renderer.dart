import 'dart:math' as math;
import 'dart:typed_data';

import '../engine/sound_command.dart';
import '../scale.dart';

// Síntesis aditiva del prototipo (plan §4.7), renderizada a WAV en memoria.
//
// Réplica de `AU.tone()` del prototipo (Web Audio): por cada parcial, un
// oscilador con envolvente exponencial que sube de 0,0001 al pico en 4 ms y
// cae de nuevo a 0,0001 en `decay * duraciónRelativa`, y se detiene 50 ms
// después.
//
// Dart puro: la capa de plataforma lo llama (idealmente en un Isolate) y
// entrega los bytes a `SoLoud.loadMem`.

enum Waveform { sine, triangle }

/// Carácter del sonido.
///
/// - [prototipo]: réplica exacta del prototipo web (ataque exponencial de 4 ms,
///   sin filtro). Punzante en los agudos y con un "clic" al inicio de cada nota.
/// - [suave] (por defecto, pedido del usuario el 28-09-2026): ataque de 12 ms con
///   curva de coseno (sin clic) y un pasa-bajos de 1.er orden sobre cada parcial
///   (−3 dB en 2,8 kHz, −6 dB por octava) que redondea los agudos.
class SynthVoicing {
  const SynthVoicing({
    required this.name,
    required this.attackS,
    required this.smoothAttack,
    this.lowpassHz,
  });

  final String name;
  final double attackS;

  /// true = subida con medio coseno (suave); false = exponencial (prototipo).
  final bool smoothAttack;

  /// Frecuencia de corte del pasa-bajos por parcial, o null sin filtro.
  final double? lowpassHz;

  static const prototipo = SynthVoicing(name: 'prototipo', attackS: 0.004, smoothAttack: false);
  static const suave = SynthVoicing(name: 'suave', attackS: 0.012, smoothAttack: true, lowpassHz: 2800);

  /// Ganancia de un parcial de [hz] tras el pasa-bajos (1 sin filtro).
  double partialGain(double hz) {
    final fc = lowpassHz;
    if (fc == null) return 1;
    final r = hz / fc;
    return 1 / math.sqrt(1 + r * r);
  }

  /// Envolvente de subida en [t] segundos (0 → [peak]).
  double attackEnvelope(double t, double peak, double floor) {
    if (t <= 0) return smoothAttack ? 0 : floor;
    if (t >= attackS) return peak;
    if (smoothAttack) return peak * 0.5 * (1 - math.cos(math.pi * t / attackS));
    return floor * math.pow(peak / floor, t / attackS).toDouble();
  }
}

/// Parcial: [ratio] de frecuencia, [gain] relativa y [dur] (duración relativa al decay).
class Partial {
  const Partial(this.ratio, this.gain, this.dur);
  final double ratio;
  final double gain;
  final double dur;
}

class Timbre {
  const Timbre({required this.wave, required this.decay, required this.partials});
  final Waveform wave;

  /// Decay base en segundos.
  final double decay;
  final List<Partial> partials;
}

abstract final class Timbres {
  static const marimba = Timbre(wave: Waveform.sine, decay: 0.8, partials: [
    Partial(1, 1, 1),
    Partial(4, 0.3, 0.25),
    Partial(9, 0.15, 0.12),
  ]);
  static const mixta = Timbre(wave: Waveform.sine, decay: 1.1, partials: [
    Partial(1, 1, 1),
    Partial(3, 0.3, 0.5),
    Partial(5.4, 0.18, 0.4),
  ]);
  static const glock = Timbre(wave: Waveform.sine, decay: 1.6, partials: [
    Partial(1, 1, 1),
    Partial(2.76, 0.45, 0.9),
    Partial(5.4, 0.25, 0.7),
    Partial(8.9, 0.12, 0.5),
  ]);
  static const oculto = Timbre(wave: Waveform.triangle, decay: 2.2, partials: [
    Partial(1, 0.7, 1),
    Partial(1.5, 0.45, 0.9),
    Partial(2, 0.35, 0.8),
    Partial(3, 0.2, 0.6),
  ]);

  /// Timbre grave de los sonidos de sistema (apertura y final).
  static const low = Timbre(wave: Waveform.sine, decay: 3, partials: [
    Partial(1, 1, 1),
    Partial(2, 0.25, 0.6),
    Partial(3, 0.1, 0.4),
  ]);

  /// Campanita de "stick vinculado" del onboarding (MIDI 72, ganancia 0,25).
  static const chime = Timbre(wave: Waveform.sine, decay: 0.5, partials: [
    Partial(1, 1, 1),
    Partial(3, 0.3, 0.5),
  ]);

  static Timbre of(TimbreFamily f) => switch (f) {
        TimbreFamily.marimba => marimba,
        TimbreFamily.mixta => mixta,
        TimbreFamily.glock => glock,
        TimbreFamily.oculto => oculto,
      };
}

/// Una nota dentro de un render: altura, timbre, ganancia, decay opcional y
/// desfase de inicio en segundos.
class ToneSpec {
  const ToneSpec({
    required this.midi,
    required this.timbre,
    this.gain = 1,
    this.decay,
    this.offsetS = 0,
  });
  final num midi;
  final Timbre timbre;
  final double gain;

  /// Si es null se usa `timbre.decay`.
  final double? decay;
  final double offsetS;

  double get effectiveDecay => decay ?? timbre.decay;

  /// Segundos hasta que la nota termina (último parcial + 50 ms).
  double get endS {
    var maxDur = 0.0;
    for (final p in timbre.partials) {
      maxDur = math.max(maxDur, p.dur);
    }
    return offsetS + effectiveDecay * maxDur + SynthRenderer.tailS;
  }
}

// ---------------------------------------------------------------------------
// Planes de notas de los sonidos de sistema (mismos valores que el prototipo)
// ---------------------------------------------------------------------------

/// Apertura del campo: MIDI 48, 55, 60 · LOW · ganancias .22/.17/.12 · decay 3 · cada 60 ms.
List<ToneSpec> openingTones() => [
      for (var i = 0; i < 3; i++)
        ToneSpec(
          midi: const [48, 55, 60][i],
          timbre: Timbres.low,
          gain: 0.22 - i * 0.05,
          decay: 3,
          offsetS: i * 0.06,
        ),
    ];

/// Cierre de sesión: MIDI 48, 52, 55 · LOW · ganancia .2 · decay 5 · cada 120 ms.
List<ToneSpec> finalTones() => [
      for (var i = 0; i < 3; i++)
        ToneSpec(
          midi: const [48, 52, 55][i],
          timbre: Timbres.low,
          gain: 0.2,
          decay: 5,
          offsetS: i * 0.12,
        ),
    ];

/// Stick vinculado: MIDI 72 · ganancia .25.
List<ToneSpec> chimeTones() => const [ToneSpec(midi: 72, timbre: Timbres.chime, gain: 0.25)];

/// Resonancia del campo al detenerse el niño: desde `lo`, con paso `max(1, floor(n/6))`,
/// ganancia .13, decay 2,4, cada 70 ms. Cada nota trae su clave de caché.
List<({String key, ToneSpec tone})> fieldResonancePlan(FieldResonance r) {
  if (r.count <= 0) return const [];
  final step = math.max(1, r.count ~/ 6);
  final timbre = Timbres.of(r.family);
  final out = <({String key, ToneSpec tone})>[];
  var k = 0;
  for (var i = 0; i < r.count; i += step) {
    final index = r.lo + i;
    out.add((
      key: SynthRenderer.resonanceKey(r.family, index),
      tone: ToneSpec(
        midi: kNotes[index],
        timbre: timbre,
        gain: 0.13,
        decay: 2.4,
        offsetS: k * 0.07,
      ),
    ));
    k++;
  }
  return out;
}

List<ToneSpec> fieldResonanceTones(FieldResonance r) =>
    [for (final e in fieldResonancePlan(r)) e.tone];

/// Nota del niño: se renderiza a ganancia 1 y la ganancia de [NoteOn] se aplica
/// al reproducir con [SynthRenderer.volumeFor].
ToneSpec noteTone(TimbreFamily family, int index) =>
    ToneSpec(midi: kNotes[index], timbre: Timbres.of(family));

// ---------------------------------------------------------------------------

abstract final class SynthRenderer {
  static const int sampleRate = 44100;

  /// Carácter por defecto (constante: los Isolates ven el mismo valor).
  static const SynthVoicing defaultVoicing = SynthVoicing.suave;

  /// Ataque del prototipo (4 ms). El ataque en uso es `voicing.attackS`.
  static const double attackS = 0.004;
  static const double floorGain = 0.0001;
  static const double tailS = 0.05;

  /// Los renders se guardan a la mitad de escala para no saturar (la suma de
  /// parciales llega a ~1,8). El volumen de reproducción compensa.
  static const double renderScale = 0.5;

  /// Límite de frecuencia de un parcial (evita aliasing).
  static double maxPartialHz(int sr) => sr * 0.45;

  /// Volumen de reproducción para una nota renderizada a ganancia 1.
  static double volumeFor(double gain) => gain / renderScale;

  /// Volumen de reproducción para un render con las ganancias ya incorporadas.
  static const double bakedVolume = 1 / renderScale;

  /// Renderiza una lista de notas a muestras flotantes (escala real, sin [renderScale]).
  static Float64List renderTones(
    List<ToneSpec> tones, {
    int sr = sampleRate,
    SynthVoicing voicing = defaultVoicing,
  }) {
    var endS = 0.0;
    for (final t in tones) {
      endS = math.max(endS, t.endS);
    }
    final out = Float64List((endS * sr).ceil() + 1);
    for (final t in tones) {
      _addTone(out, t, sr, voicing);
    }
    return out;
  }

  static void _addTone(Float64List out, ToneSpec t, int sr, SynthVoicing v) {
    final f0 = midiToHz(t.midi);
    final start = (t.offsetS * sr).round();
    for (final p in t.timbre.partials) {
      final freq = f0 * p.ratio;
      if (freq >= maxPartialHz(sr)) continue;
      final peak = math.max(0.0002, t.gain * p.gain * v.partialGain(freq));
      final endT = t.effectiveDecay * p.dur; // fin de la caída (s)
      final stopT = endT + tailS; // el oscilador se detiene aquí
      final attackN = math.max(1, (v.attackS * sr).round());
      final decayN = math.max(1, ((endT - v.attackS) * sr).round());
      final stopN = (stopT * sr).round();
      // Multiplicadores por muestra de las rampas exponenciales.
      final upStep = math.pow(peak / floorGain, 1 / attackN).toDouble();
      final downStep = math.pow(floorGain / peak, 1 / decayN).toDouble();
      final w = 2 * math.pi * freq / sr;
      final harmonics = t.timbre.wave == Waveform.triangle
          ? _triangleHarmonics(freq, sr)
          : const <int>[];
      var env = v.smoothAttack ? 0.0 : floorGain;
      for (var n = 0; n < stopN; n++) {
        final idx = start + n;
        if (idx >= out.length) break;
        if (v.smoothAttack && n < attackN) {
          env = peak * 0.5 * (1 - math.cos(math.pi * n / attackN));
        }
        final phase = w * n;
        final s = t.timbre.wave == Waveform.sine
            ? math.sin(phase)
            : _triangle(phase, harmonics);
        out[idx] += s * env;
        if (n < attackN) {
          if (v.smoothAttack) {
            if (n == attackN - 1) env = peak;
          } else {
            env *= upStep;
          }
        } else if (n < attackN + decayN) {
          env *= downStep;
        } else {
          env = floorGain;
        }
      }
    }
  }

  /// Armónicos impares (1, 3, 5, 7, 9) de un triángulo de banda limitada, bajo el límite de aliasing.
  static List<int> _triangleHarmonics(double freq, int sr) {
    final out = <int>[];
    for (var k = 1; k <= 9; k += 2) { // hasta el 9.º armónico: el resto aporta <1 %
      if (freq * k >= maxPartialHz(sr)) break;
      out.add(k);
    }
    return out;
  }

  static double _triangle(double phase, List<int> harmonics) {
    var s = 0.0;
    for (final k in harmonics) {
      final sign = ((k - 1) ~/ 2).isEven ? 1.0 : -1.0;
      s += sign * math.sin(k * phase) / (k * k);
    }
    return s * 8 / (math.pi * math.pi);
  }

  /// Convierte muestras flotantes a un WAV PCM 16-bit mono, aplicando [renderScale].
  static Uint8List toWav(Float64List samples, {int sr = sampleRate}) {
    final dataBytes = samples.length * 2;
    final b = ByteData(44 + dataBytes);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little); // tamaño del bloque fmt
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sr, Endian.little);
    b.setUint32(28, sr * 2, Endian.little); // byte rate
    b.setUint16(32, 2, Endian.little); // block align
    b.setUint16(34, 16, Endian.little); // bits por muestra
    ascii(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * renderScale * 32767).round().clamp(-32768, 32767).toInt();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// Nota del niño a ganancia 1 (reproducir con `volumeFor(noteOn.gain)`).
  static Uint8List renderNoteWav(TimbreFamily family, int index,
          {SynthVoicing voicing = defaultVoicing}) =>
      toWav(renderTones([noteTone(family, index)], voicing: voicing));

  /// Una nota de resonancia de campo con la ganancia incorporada (reproducir con [bakedVolume]).
  static Uint8List renderToneWav(ToneSpec tone) =>
      toWav(renderTones([ToneSpec(midi: tone.midi, timbre: tone.timbre, gain: tone.gain, decay: tone.decay)]));

  /// Sonidos de sistema con ganancias incorporadas (reproducir con [bakedVolume]).
  static Uint8List renderOpeningWav() => toWav(renderTones(openingTones()));
  static Uint8List renderFinalWav() => toWav(renderTones(finalTones()));
  static Uint8List renderChimeWav() => toWav(renderTones(chimeTones()));

  /// Clave estable para cachear el WAV de una nota de juego.
  static String noteKey(TimbreFamily family, int index) => 'note_${family.name}_$index.wav';

  /// Clave estable para cachear el WAV de una nota de resonancia de campo.
  static String resonanceKey(TimbreFamily family, int index) => 'res_${family.name}_$index.wav';
}
