// Trazas reales de la prueba con usuarios del 05-11-2026 (plan v2 §18).

import 'dart:io';
import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/imu_trace.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/tilt_reader.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/vec3.dart';
import 'package:flutter_test/flutter_test.dart';

List<TraceSample> trace(String name) => ImuTrace.decode(File('test/balancin_v2/golden/$name').readAsStringSync());

double median(List<double> v) => (List.of(v)..sort())[v.length ~/ 2];

/// Dirección de la aceleración promediada ±150 ms: la gravedad vista sin el filtro.
List<V3> reference(List<TraceSample> t) => [
      for (var i = 0; i < t.length; i++)
        () {
          var s = V3.zero;
          for (var k = math.max(0, i - 15); k <= math.min(t.length - 1, i + 15); k++) {
            final q = t[k].sample;
            s = s + V3(q.axG, q.ayG, q.azG);
          }
          return s.normalized()!;
        }()
    ];

void main() {
  group('stick A con cortes de 1 s (pasada «inclinando»)', () {
    final t = trace('stick_a_inclinar_cortes.trace');
    final ref = reference(t);
    final r = TiltReader()..seedBias(const V3(-3.4, 6, 0.9), 1.13);
    final err = <double>[];
    for (final s in t) {
      r.addSample(s.sample, s.arrivalMs);
      err.add(r.gravity!.angleTo(ref[err.length]) * 180 / math.pi);
    }

    test('cuenta los 16 cortes', () => expect(r.gaps, 16));

    test('tras un corte vuelve a la gravedad enseguida (antes: 2,8 s)', () {
      final back = <double>[];
      for (var i = 1; i < t.length; i++) {
        if (ImuFrameParser.ticksDiff(t[i].sample.tMs, t[i - 1].sample.tMs) < 150) continue;
        var n = 0;
        while (i + n < t.length && n < 300 && err[i + n] >= 5) {
          n++;
        }
        back.add(n / 100);
      }
      expect(back, hasLength(16));
      expect(median(back), lessThan(0.5));
    });

    test('el error del filtro baja', () {
      final s = List.of(err.sublist(50))..sort();
      expect(s[(s.length * 0.95).floor()], lessThan(20), reason: 'antes el 5 % peor pasaba de 30°');
    });
  });

  test('stick B lento: mide los ~450 ms de retraso de la cola del Bluetooth', () {
    final t = trace('stick_b_retraso.trace');
    final r = TiltReader();
    for (final s in t) {
      r.addSample(s.sample, s.arrivalMs);
    }
    expect(r.lagMs, inInclusiveRange(380, 520));
    expect(r.sampleRateHz, lessThan(45));
  });

  test('stick A sano: casi sin retraso', () {
    final t = trace('stick_a_inclinar_cortes.trace').sublist(1500, 2400);
    final r = TiltReader();
    for (final s in t) {
      r.addSample(s.sample, s.arrivalMs);
    }
    expect(r.lagMs, lessThan(40));
  });

  test('la corrección con la gravedad es por tiempo: igual a 33 Hz que a 100 Hz', () {
    double settle(int stepMs) {
      final r = TiltReader()..seedBias(V3.zero, 1);
      var t = 0;
      void add(int ax, int az) {
        r.addSample(ImuFrameParser.parse('v2,$t,$ax,0,$az,0,0,0')!, t.toDouble());
        t += stepMs;
      }

      add(2048, 3547); // arranca inclinado 30°
      while (t < 3000) {
        add(0, 4096);
        if (r.gravity!.angleTo(V3.ez) < 5 * math.pi / 180) return t / 1000;
      }
      return 3;
    }

    final fast = settle(10), slow = settle(30);
    expect(fast, closeTo(0.9, 0.2), reason: 'a 100 Hz sigue igual que antes');
    expect((slow - fast).abs(), lessThan(0.15));
  });

  test('un corte con el stick acelerando espera a la primera lectura limpia', () {
    final p = SyncParams();
    final r = TiltReader(params: p)..seedBias(V3.zero, 1);
    var t = 0;
    void add(int ax, int az) {
      r.addSample(ImuFrameParser.parse('v2,$t,$ax,0,$az,0,0,0')!, t.toDouble());
      t += 10;
    }

    add(0, 4096);
    t += 1000; // corte
    add(4096, 4096); // 1,4 g: fuera de la compuerta
    expect(r.gravity!.angleTo(V3.ez), lessThan(0.01), reason: 'no se copia una lectura con el empujón de la mano');
    add(2048, 3547); // gravedad limpia, 30°
    expect(r.gravity!.angleTo(const V3(0.5, 0, 0.866)), lessThan(0.01));
  });
}
