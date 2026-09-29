import 'dart:typed_data';

import 'package:esp32_ble_telemetry/balancin/core/audio/light_envelope.dart';
import 'package:esp32_ble_telemetry/balancin/core/audio/synth_renderer.dart';
import 'package:esp32_ble_telemetry/balancin/core/engine/sound_command.dart';
import 'package:esp32_ble_telemetry/balancin/core/scale.dart';
import 'package:flutter_test/flutter_test.dart';

const pureSine = Timbre(wave: Waveform.sine, decay: 1, partials: [Partial(1, 1, 1)]);

int maxAbsInt16(Uint8List wav) {
  final b = ByteData.sublistView(wav);
  var m = 0;
  for (var i = 44; i < wav.length; i += 2) {
    final v = b.getInt16(i, Endian.little).abs();
    if (v > m) m = v;
  }
  return m;
}

void main() {
  group('SynthRenderer', () {
    test('WAV PCM 16-bit mono 44,1 kHz con cabecera válida', () {
      final samples = SynthRenderer.renderTones(const [ToneSpec(midi: 69, timbre: pureSine)]);
      final wav = SynthRenderer.toWav(samples);
      final b = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint16(22, Endian.little), 1); // mono
      expect(b.getUint32(24, Endian.little), 44100);
      expect(b.getUint16(34, Endian.little), 16);
      expect(b.getUint32(40, Endian.little), samples.length * 2);
      expect(wav.length, 44 + samples.length * 2);
    });

    test('la frecuencia fundamental es la de la nota (A4 = 440 Hz)', () {
      final s = SynthRenderer.renderTones(const [ToneSpec(midi: 69, timbre: pureSine)]);
      const from = 441; // desde 10 ms
      const to = from + 8820; // 200 ms
      var crossings = 0;
      for (var i = from + 1; i < to; i++) {
        if ((s[i - 1] < 0) != (s[i] < 0)) crossings++;
      }
      final hz = crossings / 2 / 0.2;
      expect(hz, closeTo(440, 5));
    });

    test('envolvente del prototipo: ataque de 4 ms al pico y caída exponencial hasta ~0,0001', () {
      final s = SynthRenderer.renderTones(
        const [ToneSpec(midi: 69, timbre: pureSine)],
        voicing: SynthVoicing.prototipo,
      );
      var peak = 0.0;
      for (var i = 0; i < 441; i++) {
        if (s[i].abs() > peak) peak = s[i].abs();
      }
      expect(peak, inInclusiveRange(0.9, 1.0001));
      // A la mitad del decay (0,5 s) la envolvente es ~√(0,0001) = 0,01.
      var mid = 0.0;
      for (var i = 22050 - 200; i < 22050 + 200; i++) {
        if (s[i].abs() > mid) mid = s[i].abs();
      }
      expect(mid, closeTo(0.01, 0.003));
      // Al final (1 s) queda en el piso.
      var end = 0.0;
      for (var i = 44100 + 10; i < s.length; i++) {
        if (s[i].abs() > end) end = s[i].abs();
      }
      expect(end, lessThan(0.00015));
    });

    test('voz suave (por defecto): sin golpe inicial, pico a los 12 ms y misma caída', () {
      expect(SynthRenderer.defaultVoicing.name, 'suave');
      final suave = SynthRenderer.renderTones(const [ToneSpec(midi: 69, timbre: pureSine)]);
      final proto = SynthRenderer.renderTones(
        const [ToneSpec(midi: 69, timbre: pureSine)],
        voicing: SynthVoicing.prototipo,
      );
      double maxAbs(Float64List x, int from, int to) {
        var m = 0.0;
        for (var i = from; i < to; i++) {
          if (x[i].abs() > m) m = x[i].abs();
        }
        return m;
      }

      // En los primeros 4 ms el prototipo ya llegó al pico; la voz suave va por ~1/4.
      expect(maxAbs(proto, 0, 176), greaterThan(0.9));
      expect(maxAbs(suave, 0, 176), lessThan(0.3));
      // A los 30 ms ambas están en el pico (el filtro apenas toca 440 Hz).
      expect(maxAbs(suave, 0, 1323), closeTo(0.988, 0.01));
      // La caída es la misma: a 0,5 s ~0,01.
      expect(maxAbs(suave, 22050 - 200, 22050 + 200), closeTo(0.01, 0.003));
    });

    test('pasa-bajos de la voz suave: −3 dB en 2,8 kHz, transparente en graves', () {
      const v = SynthVoicing.suave;
      expect(v.partialGain(2800), closeTo(0.7071, 1e-3));
      expect(v.partialGain(100), greaterThan(0.999));
      expect(SynthVoicing.prototipo.partialGain(8000), 1);
      // El glockenspiel más agudo suena más redondo (menos pico) con la voz suave.
      final suaveWav = SynthRenderer.renderNoteWav(TimbreFamily.glock, 24);
      final protoWav = SynthRenderer.renderNoteWav(TimbreFamily.glock, 24, voicing: SynthVoicing.prototipo);
      expect(maxAbsInt16(suaveWav), lessThan(maxAbsInt16(protoWav)));
    });

    test('ninguna nota de ninguna familia satura el WAV', () {
      for (final f in TimbreFamily.values) {
        for (final idx in [0, 12, 24]) {
          final wav = SynthRenderer.renderNoteWav(f, idx);
          expect(maxAbsInt16(wav), lessThan(32000), reason: '$f · $idx');
        }
      }
    });

    test('duración de cada familia = decay del parcial más largo + 50 ms', () {
      expect(noteTone(TimbreFamily.marimba, 0).endS, closeTo(0.85, 1e-9));
      expect(noteTone(TimbreFamily.mixta, 0).endS, closeTo(1.15, 1e-9));
      expect(noteTone(TimbreFamily.glock, 0).endS, closeTo(1.65, 1e-9));
      expect(noteTone(TimbreFamily.oculto, 0).endS, closeTo(2.25, 1e-9));
    });

    test('volumeFor compensa la escala de render', () {
      expect(SynthRenderer.volumeFor(0.3) * SynthRenderer.renderScale, closeTo(0.3, 1e-12));
    });
  });

  group('Planes de sonidos de sistema', () {
    test('apertura: 48, 55, 60 con ganancias .22/.17/.12 cada 60 ms', () {
      final t = openingTones();
      expect(t.map((e) => e.midi), [48, 55, 60]);
      expect(t.map((e) => e.gain), [closeTo(0.22, 1e-9), closeTo(0.17, 1e-9), closeTo(0.12, 1e-9)]);
      expect(t.map((e) => e.offsetS), [0, closeTo(0.06, 1e-9), closeTo(0.12, 1e-9)]);
      expect(t.every((e) => e.effectiveDecay == 3), isTrue);
    });

    test('final: 48, 52, 55 con decay 5 cada 120 ms', () {
      final t = finalTones();
      expect(t.map((e) => e.midi), [48, 52, 55]);
      expect(t.every((e) => e.effectiveDecay == 5), isTrue);
      expect(t.last.offsetS, closeTo(0.24, 1e-9));
    });

    test('resonancia de campo: paso max(1, n~/6), dentro del campo y con claves únicas', () {
      const r = FieldResonance(lo: 3, count: 12, family: TimbreFamily.mixta);
      final plan = fieldResonancePlan(r);
      expect(plan.length, 6); // 12 alturas, paso 2
      for (final e in plan) {
        final idx = kNotes.indexOf(e.tone.midi.toInt());
        expect(idx, inInclusiveRange(3, 14));
        expect(e.tone.gain, 0.13);
        expect(e.tone.effectiveDecay, 2.4);
      }
      expect(plan.map((e) => e.key).toSet().length, plan.length);
      expect(fieldResonancePlan(const FieldResonance(lo: 0, count: 0, family: TimbreFamily.marimba)), isEmpty);
    });
  });

  group('LightEnvelope', () {
    test('sin sonido la luz está apagada; una nota la enciende y luego decae a 0', () {
      final l = LightEnvelope();
      expect(l.level(0), 0);
      l.onCommands([
        const NoteOn(
          index: 10,
          midi: 69,
          family: TimbreFamily.marimba,
          gain: 0.3,
          hidden: false,
          fieldLo: 5,
          fieldCount: 10,
        ),
      ], 1000);
      final early = l.level(1010);
      final later = l.level(1400);
      expect(early, greaterThan(0.3));
      expect(later, lessThan(early));
      expect(l.level(3000), 0);
      expect(l.liveVoices, 0);
    });

    test('muchas notas simultáneas no pasan de 1', () {
      final l = LightEnvelope();
      l.onCommands([
        for (var i = 0; i < 30; i++)
          NoteOn(
            index: i % 25,
            midi: kNotes[i % 25],
            family: TimbreFamily.glock,
            gain: 0.3,
            hidden: false,
            fieldLo: 0,
            fieldCount: 25,
          ),
      ], 0);
      expect(l.level(5), lessThanOrEqualTo(1));
    });

    test('BusFade no agrega voces', () {
      final l = LightEnvelope();
      l.onCommands(const [BusFade(to: 0, seconds: 1.2)], 0);
      expect(l.liveVoices, 0);
    });
  });
}
