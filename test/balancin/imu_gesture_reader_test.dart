// Tests del lector IMU con gestos sintéticos a 100 Hz, usando el bias real
// medido en el stick B (≈ 41,6 °/s en X). Escenarios validados antes con una
// réplica en Python del algoritmo.

import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin/core/gesture/imu_gesture_reader.dart';
import 'package:flutter_test/flutter_test.dart';

const biasX = 41.6, biasY = -0.7, biasZ = -2.0;

/// Convierte °/s a LSB del giroscopio (±1000 °/s).
int lsb(double dps) => (dps * ImuFrameParser.gyroLsbPerDps).round();

/// Alimenta [r] con muestras cada 10 ms de [t0] a [t1] (ms). [gz] = rotación
/// real en Z (°/s) en función del tiempo en s. Las muestras llegan en ráfagas de
/// [burst] (como por BLE). [onFrame] se llama a 60 Hz después de `update`.
double feed(
  ImuGestureReader r,
  double t0,
  double t1,
  double Function(double s) gz, {
  int burst = 1,
  double noise = 0.5,
  int seed = 1,
  void Function(double frameMs)? onFrame,
}) {
  final rnd = math.Random(seed);
  double jitter() => (rnd.nextDouble() * 2 - 1) * noise;
  final pending = <ImuSample>[];
  var t = t0;
  var frame = t0;
  while (t < t1) {
    pending.add(ImuSample(
      tMs: t.toInt(),
      ax: 0,
      ay: 0,
      az: 4096,
      gx: lsb(biasX + jitter()),
      gy: lsb(biasY + jitter()),
      gz: lsb(biasZ + gz(t / 1000) + jitter()),
    ));
    if (pending.length >= burst) {
      for (final s in pending) {
        r.addSample(s, t);
      }
      pending.clear();
    }
    t += 10;
    while (frame <= t) {
      r.update(frame);
      onFrame?.call(frame);
      frame += 1000 / 60;
    }
  }
  return t;
}

double still(double s) => 0;

ImuGestureReader calibrated({int burst = 1}) {
  final r = ImuGestureReader();
  feed(r, 0, 1000, still, burst: burst);
  return r;
}

void main() {
  test('en reposo estima el bias real (≈ 41,6 °/s en X) y queda quieto', () {
    final r = calibrated();
    r.update(1000);
    expect(r.calibrated, isTrue);
    expect(r.biasDps.x, closeTo(biasX, 0.3));
    expect(r.biasDps.z, closeTo(biasZ, 0.3));
    expect(r.moving, isFalse);
    expect(r.vel01, lessThan(0.02));
    expect(r.consumeArticulations(), 0);
  });

  test('antes de calibrar nunca reporta movimiento', () {
    final r = ImuGestureReader();
    feed(r, 0, 1000, (s) => 200 * math.sin(2 * math.pi * 1.5 * s));
    r.update(1000);
    expect(r.calibrated, isFalse);
    expect(r.moving, isFalse);
    expect(r.consumeArticulations(), 0);
  });

  test('vaivén de 200 °/s a 1,5 Hz: movimiento continuo, amplitud y notas', () {
    final r = calibrated();
    final moving = <bool>[];
    feed(r, 1000, 3000, (s) => 200 * math.sin(2 * math.pi * 1.5 * (s - 1)),
        onFrame: (f) {
      if (f > 1300) moving.add(r.moving);
    });
    expect(moving.every((m) => m), isTrue);
    expect(r.vel01, greaterThan(0.05));
    // Excursión pico a pico = 2·200/(2π·1,5) ≈ 42° → amp ≈ 0,47.
    expect(r.amp, closeTo(0.47, 0.06));
    // ∫|ω| ≈ 127 °/s · 2 s ≈ 254° → ~10 notas de 25°.
    expect(r.consumeArticulations(), inInclusiveRange(8, 12));
    expect(r.dominantAxis, 2);
  });

  test('al detenerse deja de moverse en ~200 ms', () {
    final r = calibrated();
    feed(r, 1000, 3000, (s) => 200 * math.sin(2 * math.pi * 1.5 * (s - 1)));
    feed(r, 3000, 3250, still);
    r.update(3250);
    expect(r.moving, isFalse);
  });

  test('criterio 8: gesto pequeño del adulto (40 °/s, 1 Hz) no parpadea', () {
    final r = calibrated();
    final moving = <bool>[];
    feed(r, 1000, 4000, (s) => 40 * math.sin(2 * math.pi * (s - 1)), onFrame: (f) {
      if (f > 1300) moving.add(r.moving);
    });
    expect(moving.where((m) => !m), isEmpty);
  });

  test('sacudida rápida (6 Hz, 300 °/s) sí; vaivén lento (1 Hz) no', () {
    final fast = calibrated();
    feed(fast, 1000, 2000, (s) => 300 * math.sin(2 * math.pi * 6 * (s - 1)));
    fast.update(2000);
    expect(fast.shake, isTrue);

    final slow = calibrated();
    feed(slow, 1000, 2500, (s) => 200 * math.sin(2 * math.pi * (s - 1)));
    slow.update(2500);
    expect(slow.shake, isFalse);
  });

  test('la dirección sigue el sentido del giro', () {
    final r = calibrated();
    feed(r, 1000, 1110, (s) => 200 * math.sin(2 * math.pi * 1.5 * (s - 1)));
    r.update(1110);
    expect(r.dx, 1);
  });

  test('ráfagas BLE (3 muestras cada 30 ms) no cortan el movimiento', () {
    final r = calibrated(burst: 3);
    final moving = <bool>[];
    feed(r, 1000, 3000, (s) => 200 * math.sin(2 * math.pi * 1.5 * (s - 1)), burst: 3,
        onFrame: (f) {
      if (f > 1300) moving.add(r.moving);
    });
    expect(moving.every((m) => m), isTrue);
  });

  test('ruido de 2,5 °/s en reposo: calibra y no se mueve', () {
    final r = ImuGestureReader();
    feed(r, 0, 1000, still, noise: 2.5);
    r.update(1000);
    expect(r.calibrated, isTrue);
    expect(r.moving, isFalse);
  });

  test('reset conserva la calibración; resetCalibration la olvida', () {
    final r = calibrated();
    r.reset();
    expect(r.calibrated, isTrue);
    r.resetCalibration();
    expect(r.calibrated, isFalse);
  });

  test('sin datos (desconexión) deja de moverse', () {
    final r = calibrated();
    feed(r, 1000, 2000, (s) => 200 * math.sin(2 * math.pi * 1.5 * (s - 1)));
    for (var f = 2000.0; f < 2600; f += 16) {
      r.update(f);
    }
    expect(r.moving, isFalse);
    expect(r.vel01, lessThan(0.05));
  });
}
