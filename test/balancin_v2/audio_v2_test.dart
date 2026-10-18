// Fase 3: núcleo del audio v2 (plan v2 §4.6). La paridad de las capas con el
// prototipo está en parity_test.dart; aquí: EQ, envolventes, planes de notas y
// detalles de las capas que la paridad no mide.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:esp32_ble_telemetry/balancin/core/audio/synth_renderer.dart' show Partial;
import 'package:esp32_ble_telemetry/balancin_v2/core/audio/eq.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/audio/layers.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/audio/reverb.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/audio/synth_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/synthetic_source.dart';
import 'package:flutter_test/flutter_test.dart';

double peakIn(Float64List s, double fromS, double toS) {
  var m = 0.0;
  for (var i = (fromS * SynthV2.sampleRate).round(); i < (toS * SynthV2.sampleRate).round() && i < s.length; i++) {
    m = math.max(m, s[i].abs());
  }
  return m;
}

void main() {
  group('EQ del prototipo', () {
    test('casi plana en la zona media, corta graves y agudos', () {
      expect(eqGainDb(440).abs(), lessThan(1.5));
      expect(eqGainDb(262).abs(), lessThan(1.5));
      expect(eqGainDb(20), lessThan(-15), reason: 'pasa-altos de 70 Hz');
      // High-shelf de −5 dB en 3,8 kHz con pendiente S = 1: −2,2 dB en 3,8 kHz, −3 en 6 kHz, −5 en 9 kHz.
      expect(eqGainDb(6000), inInclusiveRange(-4, -2));
      expect(eqGainDb(9000), lessThan(-4.5));
      expect(eqGainDb(12000), lessThan(eqGainDb(6000) - 3), reason: 'pasa-bajos de 8,5 kHz');
      expect(eqGainDb(1400), lessThan(eqGainDb(700)), reason: 'pico −2 dB en 1,4 kHz');
    });

    test('fuera de rango no suena', () {
      expect(eqGain(0), 0);
      expect(eqGain(30000), 0);
    });
  });

  group('síntesis', () {
    const sine440 = TimbreV2('prueba', 1, [Partial(1, 1, 1)]);

    test('ataque de 12 ms y caída exponencial con τ = decay/4,5', () {
      final s = SynthV2.render(const [ToneV2(midi: 69, timbre: sine440, gain: 0.5)]);
      final pk = 0.5 * eqGain(440);
      expect(peakIn(s, 0, 0.004), lessThan(pk * 0.4), reason: 'todavía subiendo');
      expect(peakIn(s, 0.010, 0.016), closeTo(pk, pk * 0.02));
      const tau = 1 / 4.5;
      expect(peakIn(s, 0.012 + tau - 0.002, 0.012 + tau + 0.002), closeTo(pk / math.e, pk * 0.03));
      expect(s.length, (1.25 * 44100).ceil() + 1, reason: 'se corta a decay + 0,25 s');
    });

    test('omite parciales sobre 9 kHz y atenúa los de más de 3 kHz', () {
      expect(childNoteTone(84).audiblePartials, 2, reason: 'do6 × 10 = 10,5 kHz no suena');
      expect(childNoteTone(60).audiblePartials, 3);
    });

    test('la canción completa no satura el WAV', () {
      final s = SynthV2.render(songTones([for (final l in levels) l.id]));
      final m = s.fold(0.0, (a, b) => math.max(a, b.abs()));
      expect(m, lessThan(2), reason: 'toWav guarda a media escala: satura sobre 2');
      expect(m, greaterThan(0.1));
    });

    test('planes de notas como el prototipo', () {
      final ph = phraseTones([60, 62, 64, 67]);
      expect(ph.map((t) => t.offsetS), [0.05, 0.29, 0.53, 0.77].map((v) => closeTo(v, 1e-12)));
      expect(ph.every((t) => t.gain == 0.17 && t.dec == 2), isTrue);
      final song = songTones([1, 2]);
      expect(song.length, 10);
      expect(song.first.midi, 48, reason: 'bajo = raíz − 12');
      expect(song[5].offsetS, closeTo(0.1 + 4 * 0.3, 1e-12), reason: 'el bajo del nivel 2 entra con su primera nota');
      expect(closingTones().map((t) => t.midi), [48, 52, 55]);
      expect(allPhraseMidi(), containsAll([60, 62, 64, 67, 69, 72]));
    });

    test('WAV PCM mono de 16 bits', () {
      final w = SynthV2.wav(chimeTones());
      expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
      expect(ByteData.sublistView(w).getUint16(22, Endian.little), 1);
    });
  });

  group('reverb incorporada (la de SoLoud no sirve en mono)', () {
    test('un impulso deja una cola que decae y se apaga', () {
      final dry = Float64List(441)..[0] = 1;
      final wet = applyReverb(dry);
      expect(wet.length, 441 + 66150, reason: '1,5 s de cola');
      expect(wet.every((v) => v.isFinite), isTrue);
      double rms(double a, double b) {
        var e = 0.0;
        var n = 0;
        for (var i = (a * 44100).round(); i < (b * 44100).round(); i++) {
          e += wet[i] * wet[i];
          n++;
        }
        return math.sqrt(e / n);
      }

      final early = rms(0.05, 0.25), late = rms(1.2, 1.5);
      expect(early, greaterThan(0));
      expect(late, lessThan(early * 0.1), reason: 'al menos −20 dB en ~1,2 s');
    });

    test('sin retorno no cambia nada', () {
      final dry = Float64List.fromList([0.1, -0.2, 0.3]);
      expect(applyReverb(dry, s: ReverbSettings.off), same(dry));
    });

    test('la canción completa con reverb no satura el WAV', () {
      final s = applyReverb(SynthV2.render(songTones([for (final l in levels) l.id])));
      final m = s.fold(0.0, (a, b) => math.max(a, b.abs()));
      expect(m, lessThan(2));
    });
  });

  group('capas', () {
    test('Glide sigue la curva de setTargetAtTime', () {
      final g = Glide(0)..setTarget(1, 0.1);
      g.step(0.1);
      expect(g.value, closeTo(1 - 1 / math.e, 1e-12));
    });

    test('desafinación: 0 dentro de la tolerancia, sube hasta maxDetune en d = 6', () {
      expect(AudioLayers.detune(1.0, 1.2, 4), 0);
      expect(AudioLayers.detune(1.2, 1.2, 4), 0);
      expect(AudioLayers.detune(1.21, 1.2, 4), closeTo(0.5, 0.01));
      expect(AudioLayers.detune(6, 1.2, 4), 4);
      expect(AudioLayers.detune(9, 1.2, 4), 4);
    });

    test('en sincronía suena la quinta; lejos, el batido', () {
      for (final q in [SynthQuality.sync, SynthQuality.lejos]) {
        final e = SyncEngine();
        e.drive = (now) => synthDrive(e, q, now);
        final l = AudioLayers();
        e.start(mode: PlayMode.levels, now: 0);
        var fifthOn = 0, beat = 0, n = 0;
        for (var now = 0.0; now < 6000; now += 1000 / 60) {
          e.tick(now);
          l.update(now, e.lastDt, e);
          l.advance(e.lastDt);
          if (now > 2000) {
            n++;
            if (l.fifthGain.target > 0) fifthOn++;
            if (l.detuneTarget > 0) beat++;
          }
        }
        if (q == SynthQuality.sync) {
          expect(fifthOn / n, greaterThan(0.8));
        } else {
          expect(beat / n, greaterThan(0.8));
          expect(fifthOn / n, lessThan(0.2), reason: 'lejos solo coinciden por momentos');
        }
      }
    });

    test('las amplitudes que salen incluyen la EQ', () {
      final l = AudioLayers()
        ..adultGain.value = 0.12
        ..adultHz.value = 130.8;
      expect(l.voices[0].amp, closeTo(0.12 * eqGain(130.8), 1e-12));
      expect(l.voices[1].amp, closeTo(0.12 * 0.22 * eqGain(260), 1e-3));
    });

    test('silencio: todas las ganancias van a 0 con τ 0,3 s', () {
      final l = AudioLayers()
        ..adultGain.setTarget(0.12, 0.1)
        ..relGain.setTarget(0.045, 0.15);
      l.silence();
      for (final g in [l.adultGain, l.relGain, l.fifthGain]) {
        expect(g.target, 0);
        expect(g.tau, 0.3);
      }
    });

    test('pad: sin frases ganadas no suena; con el nivel 1 recorre do-re-mi-sol', () {
      final e = SyncEngine()..start(mode: PlayMode.levels, now: 0);
      final l = AudioLayers()..startPad(0);
      expect(l.firePad(500, e, const []), isEmpty);
      final notes = <int>[];
      for (var t = 600.0; t <= 600 + 420 * 4; t += 420) {
        notes.addAll(l.firePad(t, e, const [1]).map((n) => n.midi));
      }
      // Disparos en 840, 1260, 1680 y 2100 ms (el de 420 fue sin frases).
      expect(notes, [60, 62, 64, 67]);
      e.close(3000);
      expect(l.firePad(5000, e, const [1]), isEmpty, reason: 'sesión cerrada');
    });
  });
}
