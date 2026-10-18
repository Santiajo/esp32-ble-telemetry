// Fase 2: inclinación desde el MPU6050 (plan v2 §4.1, §5.3, §10.1).
//
// Un simulador genera líneas v2 como las del firmware (±8 g, ±1000 °/s,
// 100 Hz, enteros con ruido, bias del giroscopio, escala del acelerómetro y
// vuelta de `ticks_ms`) a partir de una orientación conocida. Convención:
// el stick rota un ángulo θ(t) alrededor de un eje fijo del cuerpo `k`; un
// vector fijo en el mundo, visto desde el sensor, gira −θ alrededor de `k`.
//
// Montaje real (stick B, 17-10-2026): con el stick vertical la gravedad cae en
// +Z. Inclinar a la derecha (θ > 0) = girar alrededor de −Y (la gravedad pasa a
// +X); inclinar hacia adelante/arriba = girar alrededor de +X (pasa a +Y).

import 'dart:io';
import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/stick_state.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/axis_map.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/imu_trace.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/tilt_reader.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/vec3.dart';
import 'package:flutter_test/flutter_test.dart';

const deg = math.pi / 180;
const kSide = V3(0, -1, 0);
const kFwd = V3.ex;

/// Rampa suave de 0 a 1 entre [t0] y [t1] (s).
double smooth(double t, double t0, double t1) {
  if (t <= t0) return 0;
  if (t >= t1) return 1;
  final u = (t - t0) / (t1 - t0);
  return u * u * (3 - 2 * u);
}

class StickSim {
  StickSim({
    this.upright = V3.ez,
    this.bias = const V3(41.6, 0, 0), // stick B real
    this.accelScale = 1.0,
    this.accelNoiseG = 0.01,
    this.gyroNoiseDps = 0.7,
    this.startTicks = 123456,
    int seed = 7,
  }) : _rnd = math.Random(seed);

  final V3 upright; // eje del sensor que apunta hacia arriba con el stick vertical
  final V3 bias; // °/s
  final double accelScale;
  final double accelNoiseG, gyroNoiseDps;
  final int startTicks;
  final math.Random _rnd;

  double _n(double amp) => (_rnd.nextDouble() * 2 - 1) * amp;
  int _i16(double v) => v.round().clamp(-32768, 32767);

  /// Gravedad vista por el sensor con el stick rotado [theta] (rad) alrededor de [k].
  V3 gravityAt(V3 k, double theta) => upright.rotate(k, -theta);

  /// Genera [seconds] s a 100 Hz desde [t0] (s). [theta] en rad; [lin] = aceleración
  /// lineal en g en el marco inicial del sensor. [skip] descarta muestras (huecos de BLE).
  List<TraceSample> run(
    double t0,
    double seconds, {
    V3 k = kSide,
    double Function(double t)? theta,
    V3 Function(double t)? lin,
    bool Function(double t)? skip,
  }) {
    final th = theta ?? (_) => 0.0;
    final out = <TraceSample>[];
    final n = (seconds * 100).round();
    for (var i = 0; i < n; i++) {
      final t = t0 + i / 100;
      if (skip != null && skip(t)) continue;
      const h = 1e-4;
      final w = (th(t + h) - th(t - h)) / (2 * h); // rad/s
      final ang = th(t);
      var a = gravityAt(k, ang);
      if (lin != null) a = a + lin(t).rotate(k, -ang);
      final gyroDps = k * (w / deg) + bias;
      final ticks = (startTicks + (t * 1000).round()) % ImuFrameParser.ticksPeriod;
      out.add(TraceSample(
        t * 1000,
        ImuSample(
          tMs: ticks,
          ax: _i16((a.x * accelScale + _n(accelNoiseG)) * 4096),
          ay: _i16((a.y * accelScale + _n(accelNoiseG)) * 4096),
          az: _i16((a.z * accelScale + _n(accelNoiseG)) * 4096),
          gx: _i16((gyroDps.x + _n(gyroNoiseDps)) * 32.8),
          gy: _i16((gyroDps.y + _n(gyroNoiseDps)) * 32.8),
          gz: _i16((gyroDps.z + _n(gyroNoiseDps)) * 32.8),
        ),
      ));
    }
    return out;
  }
}

/// Pasa la traza al lector y devuelve (t, tiltX, tiltY) por muestra.
List<({double t, double x, double y})> feed(TiltReader r, List<TraceSample> trace) {
  final out = <({double t, double x, double y})>[];
  for (final s in trace) {
    r.addSample(s.sample, s.arrivalMs);
    out.add((t: s.arrivalMs / 1000, x: r.tiltX, y: r.tiltY));
  }
  return out;
}

void main() {
  group('reposo', () {
    test('stick B (bias 41,6 °/s): calibra y no deriva en 2 minutos', () {
      final r = TiltReader();
      final out = feed(r, StickSim().run(0, 120));
      expect(r.calibrated, isTrue);
      expect(r.biasDps.x, closeTo(41.6, 0.5));
      final drift = out.where((p) => p.t > 1).map((p) => math.max(p.x.abs(), p.y.abs())).reduce(math.max);
      expect(drift, lessThan(1), reason: 'deriva máxima $drift°');
    });

    test('stick A (|a| = 1,08 g): aprende el reposo y sigue corrigiendo', () {
      final r = TiltReader();
      feed(r, StickSim(accelScale: 1.08, bias: const V3(-3.4, 6.0, 0.9)).run(0, 3));
      expect(r.restMagG, closeTo(1.08, 0.01));
      expect(r.correcting, isTrue);
      expect(r.tiltX.abs(), lessThan(1));
    });

    test('montado al revés (vertical = −Z): el neutro toma el signo medido', () {
      final r = TiltReader();
      feed(r, StickSim(upright: -V3.ez).run(0, 3));
      expect(r.axes!.g0.z, -1);
      expect(r.tiltX.abs(), lessThan(1));
      expect(r.tiltY.abs(), lessThan(1));
    });
  });

  group('inclinación (ejes por defecto §10.1: derecha = X, vertical = Z)', () {
    test('muñeca hacia los lados 30° → tiltX ≈ 30°, tiltY ≈ 0', () {
      final r = TiltReader();
      final out = feed(r, StickSim().run(0, 6, k: kSide, theta: (t) => 30 * deg * smooth(t, 2, 3)));
      expect(out.last.x, closeTo(30, 1));
      expect(out.last.y.abs(), lessThan(1));
    });

    test('hacia adelante 30° → tiltY ≈ 30°, tiltX ≈ 0', () {
      final r = TiltReader();
      final out = feed(r, StickSim().run(0, 6, k: kFwd, theta: (t) => 30 * deg * smooth(t, 2, 3)));
      expect(out.last.y, closeTo(30, 1));
      expect(out.last.x.abs(), lessThan(1));
    });

    test('giro rápido (60° en 0,3 s): el giroscopio sigue el gesto', () {
      final r = TiltReader();
      double th(double t) => 60 * deg * smooth(t, 2, 2.3);
      final out = feed(r, StickSim().run(0, 5, k: kSide, theta: th));
      final during = out.where((p) => p.t >= 2 && p.t <= 2.6);
      final err = during.map((p) => (p.x - th(p.t) / deg).abs()).reduce(math.max);
      expect(err, lessThan(3), reason: 'error durante el giro $err°');
      expect(out.last.x, closeTo(60, 1));
    });

    test('sacudida de 3 g sin girar: el punto casi no se mueve', () {
      final r = TiltReader();
      final out = feed(
        r,
        StickSim().run(0, 8, lin: (t) => t < 2 ? V3.zero : V3.ex * (3 * math.sin(2 * math.pi * 3 * t))),
      );
      final shake = out.where((p) => p.t > 2).map((p) => math.max(p.x.abs(), p.y.abs())).reduce(math.max);
      expect(shake, lessThan(3), reason: 'error máximo durante la sacudida $shake°');
    });

    test('sacudida mientras está inclinado 20°: conserva la inclinación', () {
      final r = TiltReader();
      final out = feed(
        r,
        StickSim().run(0, 8,
            k: kSide,
            theta: (t) => 20 * deg * smooth(t, 1.5, 2),
            lin: (t) => t < 3 ? V3.zero : V3.ey * (2.5 * math.sin(2 * math.pi * 4 * t))),
      );
      final err = out.where((p) => p.t > 3).map((p) => (p.x - 20).abs()).reduce(math.max);
      expect(err, lessThan(3), reason: 'error máximo $err°');
    });

    test('balanceo continuo de ±25° a 0,8 Hz (nivel 1): sigue la curva', () {
      final r = TiltReader();
      double th(double t) => t < 2 ? 0 : 25 * deg * math.sin(2 * math.pi * 0.8 * (t - 2));
      final out = feed(r, StickSim().run(0, 20, k: kFwd, theta: th));
      final err = out.where((p) => p.t > 3).map((p) => (p.y - th(p.t) / deg).abs()).reduce(math.max);
      expect(err, lessThan(2), reason: 'error máximo $err°');
    });
  });

  group('robustez', () {
    test('un giro lento y constante no se confunde con el bias', () {
      final r = TiltReader();
      feed(r, StickSim().run(0, 5, k: kSide, theta: (t) => t < 2 ? 0 : 20 * deg * (t - 2))); // 20 °/s por 3 s
      expect(r.biasDps.x, closeTo(41.6, 1));
      expect(r.biasDps.y.abs(), lessThan(1), reason: 'el giro de 20 °/s no debe entrar al bias');
    });

    test('sin quietud inicial usa el acelerómetro y no deriva', () {
      final r = TiltReader();
      double th(double t) => 30 * deg * math.sin(t * 0.7) + 5 * deg * math.sin(t * 5);
      final out = feed(r, StickSim().run(0, 6, k: kSide, theta: th));
      expect(r.calibrated, isFalse);
      final err = out.map((p) => (p.x - th(p.t) / deg).abs()).reduce(math.max);
      expect(err, lessThan(3));
    });

    test('vuelta del reloj del ESP32 (2^30 ms) sin saltos', () {
      final r = TiltReader();
      final sim = StickSim(startTicks: ImuFrameParser.ticksPeriod - 2500);
      final out = feed(r, sim.run(0, 6, k: kSide, theta: (t) => 15 * deg * smooth(t, 3, 4)));
      expect(out.last.x, closeTo(15, 1));
    });

    test('hueco de 300 ms sin datos a mitad del gesto', () {
      final r = TiltReader();
      final out = feed(
        r,
        StickSim().run(0, 6, k: kSide, theta: (t) => 30 * deg * smooth(t, 2, 3), skip: (t) => t > 2.4 && t < 2.7),
      );
      expect(out.last.x, closeTo(30, 1.5));
      expect(out.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
    });

    test('lectura de aceleración nula (sensor caído) se ignora', () {
      final r = TiltReader();
      feed(r, StickSim().run(0, 2));
      final before = r.tiltX;
      r.addSample(const ImuSample(tMs: 999999, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0), 5000);
      expect(r.tiltX, before);
      expect(r.tiltX.isFinite, isTrue);
    });
  });

  group('montaje distinto y asistente de ejes (§5.3)', () {
    test('si «derecha» es otro eje del sensor, un mapa propio da los mismos ángulos', () {
      // Placa girada 90° alrededor de la vertical: inclinar a la derecha mueve la gravedad hacia +Y.
      final trace = StickSim().run(0, 6, k: kFwd, theta: (t) => 30 * deg * smooth(t, 2, 3));
      final porDefecto = TiltReader();
      final out1 = feed(porDefecto, trace);
      expect(out1.last.y, closeTo(30, 1), reason: 'con el mapa por defecto aparece como «arriba»');
      final propio = TiltReader(axes: AxisMap.fromRight(V3.ez, V3.ey));
      final out2 = feed(propio, trace);
      expect(out2.last.x, closeTo(30, 1));
      expect(out2.last.y.abs(), lessThan(1));
    });

    test('el asistente reconstruye los ejes por defecto desde los gestos', () {
      final sim = StickSim(seed: 3);
      final w = AxisWizard();
      final r = TiltReader();
      void phase(List<TraceSample> tr) {
        for (final s in tr) {
          r.addSample(s.sample, s.arrivalMs);
          w.feed(r.gravity!);
        }
      }

      phase(sim.run(0, 2));
      expect(w.next(), isTrue);
      // Cada paso: inclinar y volver a reposo (un stick real no salta de una pose a otra).
      phase(sim.run(2, 2, k: kFwd, theta: (t) => 25 * deg * (smooth(t, 2.2, 2.7) - smooth(t, 3.2, 3.7)))); // arriba
      expect(w.next(), isTrue);
      phase(sim.run(4, 2, k: kSide, theta: (t) => 25 * deg * (smooth(t, 4.2, 4.7) - smooth(t, 5.2, 5.7)))); // derecha
      expect(w.next(), isTrue);
      expect(w.step, WizardStep.done);
      final m = w.result!;
      final def = AxisMap.defaultFor(V3.ez);
      expect(m.g0.angleTo(def.g0) / deg, lessThan(2));
      expect(m.right.angleTo(def.right) / deg, lessThan(3));
      expect(m.up.angleTo(def.up) / deg, lessThan(3));
    });

    test('el asistente pide más inclinación y rechaza ejes casi iguales', () {
      final w = AxisWizard();
      for (var i = 0; i < 50; i++) {
        w.feed(V3.ey);
      }
      expect(w.next(), isTrue);
      w.feed(V3.ey.rotate(V3.ex, -5 * deg)); // solo 5°
      expect(w.next(), isFalse);
      expect(w.error, contains('arriba'));
      expect(w.step, WizardStep.up);
      w.feed(V3.ey.rotate(V3.ex, -25 * deg));
      expect(w.next(), isTrue);
      w.feed(V3.ey.rotate(V3.ex, -30 * deg)); // «derecha» en la misma dirección que arriba
      expect(w.next(), isFalse);
      expect(w.step, WizardStep.failed);
    });

    test('el mapa se guarda y se recupera', () {
      final m = AxisMap.fromRight(V3.ey, -V3.ez)!;
      final back = AxisMap.fromJson(m.toJson())!;
      expect(back.right.angleTo(m.right), lessThan(1e-9));
      expect(back.up.angleTo(m.up), lessThan(1e-9));
      expect(AxisMap.fromJson({'g0': 'x'}), isNull);
      expect(AxisMap.fromRight(V3.ey, V3.ey), isNull, reason: 'derecha paralela al neutro');
    });
  });

  group('integración con el plano', () {
    test('inclinar el stick 90° deja el punto en el borde, nunca afuera', () {
      final r = TiltReader();
      final st = StickState(Role.child);
      final p = SyncParams();
      var t = 0.0;
      for (final s in StickSim().run(0, 5, k: kSide, theta: (t) => 90 * deg * smooth(t, 2, 3))) {
        r.addSample(s.sample, s.arrivalMs);
        st.feedTilt(r.tiltX, r.tiltY, p);
        st.update(t += 10, 0.01, p);
        expect(st.pos.x.abs(), lessThanOrEqualTo(planeLimit));
      }
      expect(r.tiltX, closeTo(90, 2));
      expect(st.raw.x, planeLimit);
      expect(st.atEdge, isTrue);
    });
  });

  group('traza real del stick B (Thonny, 5 Hz, 17-10-2026)', () {
    final trace = ImuTrace.decode(File('test/balancin_v2/golden/stick_b_vertical_thonny_5hz.trace').readAsStringSync());

    test('vertical = +Z: el mapa por defecto lo toma y los ángulos salen de la gravedad', () {
      expect(trace.length, 182);
      final r = TiltReader();
      for (final s in trace) {
        r.addSample(s.sample, s.arrivalMs);
        // A 5 Hz nunca hay 0,5 s con 20 muestras: queda en modo solo acelerómetro (exacto).
        final x = math.atan2(s.sample.axG, s.sample.azG) / deg;
        expect(r.tiltX, closeTo(x, 1.5));
      }
      expect(r.calibrated, isFalse);
      expect(r.axes!.g0.z, 1);
      expect(r.axes!.right.x, 1);
      expect(r.axes!.up.y, 1, reason: 'con Z vertical y X a la derecha, adelante = +Y');
      final xs = trace.map((s) => math.atan2(s.sample.axG, s.sample.azG) / deg).toList()..sort();
      expect(xs[xs.length ~/ 2], inInclusiveRange(18, 24), reason: 'descanso ladeado ~21° hacia X');
    });

    test('el giroscopio en X marca ~41 °/s quieto (bias del stick B, como en septiembre)', () {
      final gx = trace.map((s) => s.sample.gxDps).toList()..sort();
      expect(gx[gx.length ~/ 2], closeTo(41, 1.5));
    });
  });

  test('trazas: ida y vuelta, con comentarios y líneas dañadas', () {
    final tr = StickSim().run(0, 0.5);
    final text = ImuTrace.encode(tr, comments: ['rol B', 'prueba']);
    final back = ImuTrace.decode('$text\nbasura\n12.0\tv2,1,2\n');
    expect(back.length, tr.length);
    expect(back.first.sample.toString(), tr.first.sample.toString());
    expect(back.last.arrivalMs, closeTo(tr.last.arrivalMs, 0.05));
  });
}
