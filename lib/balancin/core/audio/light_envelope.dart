import 'dart:math' as math;

import '../engine/sound_command.dart';
import '../scale.dart';
import 'synth_renderer.dart';

class _Voice {
  _Voice(this.startMs, this.tone);
  final double startMs;
  final ToneSpec tone;
}

/// Modelo de la luz difusa (plan §4.7): la luz sigue la amplitud del sonido y
/// no tiene información propia.
///
/// En vez de medir el audio real (el prototipo usa un AnalyserNode), suma las
/// envolventes de las voces vivas con las mismas curvas del sintetizador.
/// Es determinista y no depende del motor de audio.
///
/// `level = clamp(rms * 6, 0, 1)`, igual que el prototipo.
class LightEnvelope {
  final List<_Voice> _voices = [];

  /// Registra los sonidos que emitió el motor en el instante [nowMs].
  void onCommands(Iterable<SoundCommand> cmds, double nowMs) {
    for (final c in cmds) {
      switch (c) {
        case NoteOn():
          _add(nowMs, [ToneSpec(midi: c.midi, timbre: Timbres.of(c.family), gain: c.gain)]);
        case OpeningSound():
          _add(nowMs, openingTones());
        case FieldResonance():
          _add(nowMs, fieldResonanceTones(c));
        case FinalSound():
          _add(nowMs, finalTones());
        case BusFade():
          break; // el bus lo aplica quien llama a [level] con busGain
      }
    }
  }

  void _add(double nowMs, List<ToneSpec> tones) {
    for (final t in tones) {
      _voices.add(_Voice(nowMs, t));
    }
  }

  /// Número de voces vivas (útil para depurar la polifonía).
  int get liveVoices => _voices.length;

  void clear() => _voices.clear();

  /// Nivel de luz 0–1 en [nowMs]. [busGain] es la ganancia actual del bus (0,8 normal).
  double level(double nowMs, {double busGain = 0.8}) {
    _voices.removeWhere((v) => (nowMs - v.startMs) / 1000 > v.tone.endS);
    var sumSq = 0.0;
    for (final v in _voices) {
      final t = (nowMs - v.startMs) / 1000 - v.tone.offsetS;
      if (t < 0) continue;
      for (final p in v.tone.timbre.partials) {
        final a = _partialEnvelope(t, v.tone, p) * busGain;
        sumSq += a * a / 2; // RMS de una sinusoide = amplitud / √2
      }
    }
    final rms = math.sqrt(sumSq);
    return (rms * 6).clamp(0.0, 1.0).toDouble();
  }

  static double _partialEnvelope(double t, ToneSpec tone, Partial p) {
    final freq = midiToHz(tone.midi) * p.ratio;
    if (freq >= SynthRenderer.maxPartialHz(SynthRenderer.sampleRate)) return 0;
    const floor = SynthRenderer.floorGain;
    const attack = SynthRenderer.attackS;
    final peak = math.max(0.0002, tone.gain * p.gain);
    final end = tone.effectiveDecay * p.dur;
    if (t < attack) return floor * math.pow(peak / floor, t / attack);
    if (t < end) return peak * math.pow(floor / peak, (t - attack) / (end - attack));
    return 0;
  }
}
