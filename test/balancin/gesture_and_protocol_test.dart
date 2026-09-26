import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin/core/constants.dart';
import 'package:esp32_ble_telemetry/balancin/core/gesture/touch_gesture_reader.dart';
import 'package:esp32_ble_telemetry/balancin/core/scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Escala pentatónica', () {
    test('25 alturas, de C3 (48) a A7 (105), solo C D E G A', () {
      expect(kNotes.length, 25);
      expect(kNotes.first, 48);
      expect(kNotes.last, 105);
      for (var i = 1; i < kNotes.length; i++) {
        expect(kNotes[i], greaterThan(kNotes[i - 1]));
      }
      expect(kNotes.every((m) => kPentatonicPitchClasses.contains(m % 12)), isTrue);
    });

    test('midiToHz: A4 = 440 Hz, C4 ≈ 261,63 Hz', () {
      expect(midiToHz(69), closeTo(440, 1e-9));
      expect(midiToHz(60), closeTo(261.6256, 1e-3));
    });

    test('jsRound replica Math.round de JavaScript', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-0.5), 0);
      expect(jsRound(-1.5), -1);
      expect(jsRound(2.49), 2);
    });
  });

  group('TouchGestureReader', () {
    test('una articulación cada 42 px de recorrido', () {
      final r = TouchGestureReader();
      for (var i = 0; i <= 42; i++) {
        r.feed(i * 10.0, 100, i * 16.0, 400, 600); // 420 px en línea recta
      }
      expect(r.consumeArticulations(), 10);
      expect(r.consumeArticulations(), 0);
    });

    test('discardArticulations descarta el recorrido pendiente', () {
      final r = TouchGestureReader();
      r.feed(0, 0, 0, 400, 600);
      r.feed(100, 0, 16, 400, 600);
      r.discardArticulations();
      expect(r.consumeArticulations(), 0);
    });

    test('moving: verdadero hasta 200 ms después del último movimiento', () {
      final r = TouchGestureReader();
      r.feed(0, 0, 0, 400, 600);
      r.feed(10, 0, 10, 400, 600);
      r.update(100);
      expect(r.moving, isTrue);
      r.update(10 + BalancinConst.movingWindowMs + 1);
      expect(r.moving, isFalse);
    });

    test('shake: oscilación rápida en X sí, barrido en un sentido no', () {
      final osc = TouchGestureReader();
      for (var t = 0; t <= 600; t += 10) {
        final x = ((t ~/ 50) % 2 == 0) ? 100.0 + (t % 50) : 150.0 - (t % 50);
        osc.feed(x, 100, t.toDouble(), 400, 600);
      }
      osc.update(600);
      expect(osc.shake, isTrue);

      final sweep = TouchGestureReader();
      for (var t = 0; t <= 600; t += 10) {
        sweep.feed(t.toDouble() / 2, 100, t.toDouble(), 400, 600);
      }
      sweep.update(600);
      expect(sweep.shake, isFalse);
    });

    test('vel01 y amp quedan en 0–1 incluso con movimientos enormes', () {
      final r = TouchGestureReader();
      r.feed(0, 0, 0, 400, 600);
      r.feed(400, 600, 5, 400, 600);
      r.update(5);
      expect(r.vel01, inInclusiveRange(0, 1));
      expect(r.vel01, 1);
      expect(r.amp, 1);
    });

    test('dirección: signo del último desplazamiento mayor a 0,5 px', () {
      final r = TouchGestureReader();
      r.feed(100, 100, 0, 400, 600);
      r.feed(90, 110, 16, 400, 600);
      expect(r.dx, -1);
      expect(r.dy, 1);
      r.feed(90.2, 110.3, 32, 400, 600); // movimiento mínimo: no cambia la dirección
      expect(r.dx, -1);
      expect(r.dy, 1);
    });

    test('reset deja el lector quieto y sin historia', () {
      final r = TouchGestureReader();
      r.feed(0, 0, 0, 400, 600);
      r.feed(50, 0, 16, 400, 600);
      r.reset();
      r.update(20);
      expect(r.moving, isFalse);
      expect(r.x, isNull);
      expect(r.consumeArticulations(), 0);
    });
  });

  group('Protocolo BLE v2', () {
    test('parsea una línea real del stick B', () {
      final s = ImuFrameParser.parse('v2,774,-1529,-3783,486,1366,-24,-67');
      expect(s, isNotNull);
      expect(s!.tMs, 774);
      expect(s.ax, -1529);
      expect(s.gz, -67);
      // Magnitud en reposo ≈ 1 g con la escala ±8 g.
      final g2 = s.axG * s.axG + s.ayG * s.ayG + s.azG * s.azG;
      expect(g2, closeTo(1.0, 0.05));
      // Bias real del giroscopio del stick B en reposo (~41,6 °/s en X): la app debe restarlo.
      expect(s.gxDps, closeTo(41.6, 0.1));
    });

    test('rechaza líneas legadas, mezcladas, incompletas o fuera de rango', () {
      expect(ImuFrameParser.parse('120,-340'), isNull);
      expect(ImuFrameParser.parse('v2,774,-1529,-3783,486,1366,-24'), isNull);
      expect(ImuFrameParser.parse('v2,774,-1529,-3783v2,974,-1541,-3770,486,1358,-20,-79'), isNull);
      expect(ImuFrameParser.parse('v2,774,-1529,-3783,486,1366,-24,abc'), isNull);
      expect(ImuFrameParser.parse('v2,774,-1529,-3783,486,1366,-24,40000'), isNull);
      expect(ImuFrameParser.parse(''), isNull);
    });

    test('isV2 distingue el protocolo nuevo del legado', () {
      expect(ImuFrameParser.isV2('v2,1,2,3,4,5,6,7'), isTrue);
      expect(ImuFrameParser.isV2('120,-340'), isFalse);
    });

    test('ticksDiff maneja la vuelta de reloj de MicroPython (2^30)', () {
      expect(ImuFrameParser.ticksDiff(1010, 1000), 10);
      expect(ImuFrameParser.ticksDiff(5, ImuFrameParser.ticksPeriod - 5), 10);
      expect(ImuFrameParser.ticksDiff(ImuFrameParser.ticksPeriod - 5, 5), -10);
    });
  });
}
