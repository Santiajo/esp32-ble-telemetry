// §17: chequeo guiado de un stick, con un stick simulado.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/diagnostics.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/stick_check.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/axis_map.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/imu_trace.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/tilt_reader.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/vec3.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/stick_check_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stick simulado. [turnDeg] = cuánto está girado en la mano respecto de los ejes de
/// fábrica, alrededor de la vertical.
class FakeStick {
  FakeStick({this.turnDeg = 0}) : axes = AxisMap.fromRight(V3.ez, V3.ex)!;

  final double turnDeg;
  AxisMap axes;
  bool connected = true, receiving = true;
  double hz = 100;
  int still = 0;
  bool wasStill = false;
  double lag = 0;
  int gaps = 0;

  double fwd = 0, side = 0; // inclinación real (°) hacia adelante y a la derecha de quien sostiene
  double mag = 1; // |a|

  V3 get gravity {
    final t = turnDeg * math.pi / 180;
    final u0 = AxisMap.fromRight(V3.ez, V3.ex)!;
    final fwdDir = u0.up * math.cos(t) + u0.right * math.sin(t);
    final rightDir = u0.right * math.cos(t) - u0.up * math.sin(t);
    final f = fwd * math.pi / 180, s = side * math.pi / 180;
    return (V3.ez + fwdDir * math.tan(f) + rightDir * math.tan(s)).normalized()!;
  }

  StickSnapshot read() {
    final t = axes.tiltDeg(gravity);
    return StickSnapshot(
      connected: connected,
      receiving: receiving,
      hz: receiving ? hz : 0,
      tiltX: t.x,
      tiltY: t.y,
      gravity: gravity,
      accelMagG: mag,
      restMagG: 1,
      gyroReady: still > 0,
      stillCount: still,
      axes: axes,
      lagMs: lag,
      gaps: gaps,
    );
  }
}

const double frame = 1000 / 60;

/// Un participante que sigue las consignas. Se puede cambiar cada gesto.
class Run {
  Run(this.stick, {this.params, bool verify = false}) {
    check = StickCheck(role: Role.adult, params: params ?? SyncParams(), onAxes: (a) => stick.axes = a, verifyAxes: verify);
  }

  final FakeStick stick;
  final SyncParams? params;
  late final StickCheck check;
  double now = 0;

  /// Avanza hasta terminar. [act] mueve el stick según el paso y el tiempo del paso.
  void play(void Function(CheckStep step, double ms, FakeStick s) act) {
    for (var i = 0; i < 12000 && check.step != CheckStep.done; i++) {
      now += frame;
      act(check.step, check.elapsedMs, stick);
      check.tick(now, stick.read());
    }
  }
}

/// Sigue bien todas las consignas.
void goodUser(CheckStep step, double ms, FakeStick s) {
  s.mag = 1;
  switch (step) {
    case CheckStep.link:
      break;
    case CheckStep.rest:
      s
        ..fwd = 0
        ..side = 0;
      if (ms > 600 && !s.wasStill) {
        s.still++;
        s.wasStill = true;
      }
    case CheckStep.forward:
      s
        ..fwd = 30 * math.sin(ms / 1400 * math.pi).clamp(0.0, 1.0)
        ..side = 0;
    case CheckStep.right:
      s
        ..fwd = 0
        ..side = 30 * math.sin(ms / 1400 * math.pi).clamp(0.0, 1.0);
    case CheckStep.range:
    case CheckStep.reach:
      s
        ..fwd = 30 * math.sin(2 * math.pi * ms / 1500)
        ..side = 30 * math.sin(2 * math.pi * ms / 2100 + 1);
    case CheckStep.done:
      break;
  }
}

/// Pasa una traza real por el lector y el chequeo de usuarios.
StickCheck replay(List<TraceSample> t) {
  final p = SyncParams();
  final r = TiltReader(params: p);
  final c = StickCheck(role: Role.adult, params: p, onAxes: r.setAxes, verifyAxes: true);
  final t0 = t.first.arrivalMs;
  var k = 0;
  for (var now = 0.0; now < t.last.arrivalMs - t0 + 25000 && c.step != CheckStep.done; now += frame) {
    while (k < t.length && t[k].arrivalMs - t0 <= now) {
      r.addSample(t[k].sample, t[k].arrivalMs - t0);
      k++;
    }
    final stale = !r.hasTilt || (k < t.length && now - r.lastArrivalMs > 1000);
    c.tick(
      now,
      StickSnapshot(
        connected: true,
        receiving: !stale,
        hz: stale ? 0 : 100,
        tiltX: r.tiltX,
        tiltY: r.tiltY,
        gravity: r.gravity,
        accelMagG: r.accelMagG,
        restMagG: r.restMagG,
        gyroReady: r.calibrated,
        stillCount: r.stillCount,
        axes: r.axes,
      ),
    );
  }
  return c;
}

List<String> titles(StickCheck c, CheckGrade g) => [
      for (final f in c.findings)
        if (f.grade == g) f.title
    ];

void main() {
  group('chequeo de un stick', () {
    test('quien sigue las consignas: todo bien y queda calibrado', () {
      final r = Run(FakeStick())..play(goodUser);
      expect(r.check.step, CheckStep.done);
      expect(r.check.grade, CheckGrade.ok, reason: '${r.check.findings}');
      expect(r.check.cal, isNotNull);
      expect(r.check.cal!.hrY, closeTo(30, 4));
      expect(titles(r.check, CheckGrade.ok), containsAll(['Conexión', 'Giroscopio', 'Orientación', 'Calibración', 'Adelante y atrás']));
    });

    test('stick girado 90° en la mano: lo detecta y lo corrige', () {
      final s = FakeStick(turnDeg: 90);
      expect(s.axes.tiltDeg((s..fwd = 30).gravity).y.abs(), lessThan(1), reason: 'sin corregir, «adelante» no mueve la altura');
      s.fwd = 0;
      final r = Run(s)..play(goodUser);
      expect(titles(r.check, CheckGrade.warn), contains('El stick estaba girado 90°'));
      expect(r.check.grade, CheckGrade.warn);
      expect(s.axes.tiltDeg((s..fwd = 30..side = 0).gravity).y, closeTo(30, 1), reason: 'ahora adelante = altura');
    });

    test('stick al revés: «Juntos» no se podría lograr, lo avisa y lo corrige', () {
      final s = FakeStick(turnDeg: 180);
      final r = Run(s)..play(goodUser);
      expect(titles(r.check, CheckGrade.warn), contains('El stick estaba al revés'));
      expect(s.axes.tiltDeg((s..fwd = 30..side = 0).gravity).y, closeTo(30, 1));
    });

    test('levantar el stick sin inclinarlo: dice que eso no se mide', () {
      final r = Run(FakeStick())
        ..play((step, ms, s) {
          if (step != CheckStep.forward) return goodUser(step, ms, s);
          s
            ..fwd = 0
            ..mag = 1 + 0.3 * math.sin(ms / 150);
        });
      expect(titles(r.check, CheckGrade.fail), ['Levantas el stick sin inclinarlo']);
      expect(r.check.cal, isNotNull, reason: 'sigue a la calibración, y aquí inclinó bien');
    });

    test('quien solo levanta llega a la calibración y se ve que no calibra', () {
      final r = Run(FakeStick())
        ..play((step, ms, s) {
          if (step == CheckStep.rest || step == CheckStep.link) return goodUser(step, ms, s);
          s
            ..fwd = 0
            ..side = 0
            ..mag = 1 + 0.3 * math.sin(ms / 150);
        });
      expect(titles(r.check, CheckGrade.fail), ['Levantas el stick sin inclinarlo', 'No se calibró']);
      expect(r.check.cal, isNull);
      expect((r.check.toJson()['calibracion_muestras'] as Map)['en_movimiento'], 0);
      expect(r.check.dataLines.join('\n'), contains('Muestras en movimiento 0 de'));
    });

    test('mientras levanta, lo avisa en el momento', () {
      final r = Run(FakeStick());
      String? seen;
      r.play((step, ms, s) {
        if (step != CheckStep.forward) return goodUser(step, ms, s);
        s.mag = 1.4;
        seen ??= r.check.hint;
      });
      expect(seen, contains('levantar'));
    });

    test('casi sin moverse en el paso de rango: «No se calibró», como pasaría en el juego', () {
      final r = Run(FakeStick())
        ..play((step, ms, s) {
          if (step != CheckStep.range) return goodUser(step, ms, s);
          s
            ..fwd = 0
            ..side = 0;
        });
      expect(titles(r.check, CheckGrade.fail), ['No se calibró']);
      expect(r.check.cal, isNull);
    });

    test('calibrar con gesto amplio y jugar con uno chico: el punto no llega a los bordes', () {
      final r = Run(FakeStick())
        ..play((step, ms, s) {
          goodUser(step, ms, s);
          if (step == CheckStep.reach) {
            s
              ..fwd /= 3
              ..side /= 3;
          }
        });
      expect(r.check.grade, CheckGrade.fail);
      expect(titles(r.check, CheckGrade.fail).single, contains('no llega'));
    });

    test('llegar cerca del marco no basta: hay que tocarlo', () {
      final r = Run(FakeStick())
        ..play((step, ms, s) {
          goodUser(step, ms, s);
          if (step == CheckStep.reach) {
            s
              ..fwd *= 0.75 // llega a ~4,5 de 6: antes pasaba
              ..side *= 0.75;
          }
        });
      expect(r.check.reached.top, isFalse);
      expect(r.check.grade, CheckGrade.fail);
    });

    test('retraso y cortes de la señal quedan en el resultado', () {
      final s = FakeStick();
      final r = Run(s);
      var i = 0;
      r.play((step, ms, q) {
        goodUser(step, ms, q);
        q
          ..lag = 440
          ..gaps = step == CheckStep.link ? 2 : 2 + (i++ ~/ 200);
      });
      expect(titles(r.check, CheckGrade.warn), containsAll(['Señal con retraso', 'Señal con cortes']));
      expect(r.check.toJson()['retraso_ms'], 440);
      expect(r.check.toJson()['cortes'] as int, greaterThan(0));
    });

    test('el stick no conecta', () {
      final s = FakeStick()..connected = false;
      final r = Run(s)..play(goodUser);
      expect(titles(r.check, CheckGrade.fail), ['El stick no conectó']);
    });

    test('conecta pero no manda datos', () {
      final s = FakeStick()..receiving = false;
      final r = Run(s)..play(goodUser);
      expect(titles(r.check, CheckGrade.fail), ['Conectó, pero no manda datos']);
    });

    test('se corta a mitad: el paso se detiene y termina diciéndolo', () {
      final r = Run(FakeStick());
      r.play((step, ms, s) {
        goodUser(step, ms, s);
        if (step == CheckStep.range && ms > 2000) s.receiving = false;
      });
      expect(titles(r.check, CheckGrade.fail), ['El stick se desconectó']);
    });

    test('un corte breve no cuenta como tiempo del paso', () {
      final r = Run(FakeStick());
      var cut = 0;
      r.play((step, ms, s) {
        goodUser(step, ms, s);
        s.receiving = !(step == CheckStep.range && ms > 2000 && cut++ < 120);
      });
      expect(r.check.grade, CheckGrade.ok, reason: '${r.check.findings}');
    });
  });

  group('ejes en la calibración de usuarios', () {
    // turnDeg −90 = montaje real: adelante = −X del sensor, derecha = +Y.
    test('con el stick bien sujeto pasa', () {
      final r = Run(FakeStick(turnDeg: -90), verify: true)..play(goodUser);
      expect(r.check.grade, CheckGrade.ok, reason: '${r.check.findings}');
      expect(r.check.cal, isNotNull);
    });

    test('girado 90° no avanza, avisa en el momento y queda sin calibrar', () {
      final r = Run(FakeStick(), verify: true);
      String? seen;
      r.play((step, ms, s) {
        goodUser(step, ms, s);
        if (step == CheckStep.forward) seen ??= r.check.hint;
      });
      expect(seen, contains('hacia el lado'));
      expect(titles(r.check, CheckGrade.fail), ['Eje incorrecto']);
      expect(r.check.cal, isNull);
    });

    test('al revés no avanza y dice que va hacia atrás', () {
      final r = Run(FakeStick(turnDeg: 90), verify: true);
      String? seen;
      r.play((step, ms, s) {
        goodUser(step, ms, s);
        if (step == CheckStep.forward) seen ??= r.check.hint;
      });
      expect(seen, contains('hacia atrás'));
      expect(r.check.cal, isNull);
    });

    test('repetir el gesto de adelante en el paso de la derecha no avanza', () {
      final r = Run(FakeStick(turnDeg: -90), verify: true);
      String? seen;
      r.play((step, ms, s) {
        goodUser(step, ms, s);
        if (step == CheckStep.right) {
          s
            ..side = 0
            ..fwd = 30 * math.sin(ms / 1400 * math.pi).clamp(0.0, 1.0);
          seen ??= r.check.hint;
        }
      });
      expect(seen, contains('adelante-atrás'));
      expect(titles(r.check, CheckGrade.fail), ['Eje incorrecto']);
    });

    test('un stick que no está vertical no pasa de la quietud', () {
      final s = FakeStick(turnDeg: -90);
      final r = Run(s, verify: true)
        ..play((step, ms, q) {
          goodUser(step, ms, q);
          if (step == CheckStep.rest) q.fwd = 80;
        });
      expect(titles(r.check, CheckGrade.fail), ['El stick no estaba vertical']);
    });

    test('el banco no lo exige: sirve para diagnosticar', () {
      final r = Run(FakeStick())..play(goodUser);
      expect(r.check.cal, isNotNull);
    });

    // Fin de los pasos de ejes en cada traza: después hay movimiento libre.
    for (final (name, axesEndMs) in [('chequeo_a', 6300.0), ('chequeo_b', 9200.0)]) {
      test('gestos reales ($name): pasan bien sujetos y no con el sensor girado 90°', () {
        final t = ImuTrace.decode(File('test/balancin_v2/golden/$name.trace').readAsStringSync());
        expect(replay(t).findings.map((f) => f.title), contains('Orientación'));
        final turned = [
          for (final q in t.where((q) => q.arrivalMs - t.first.arrivalMs < axesEndMs))
            TraceSample(
              q.arrivalMs,
              ImuSample(tMs: q.sample.tMs, ax: q.sample.ay, ay: -q.sample.ax, az: q.sample.az, gx: q.sample.gy, gy: -q.sample.gx, gz: q.sample.gz),
            )
        ];
        expect(replay(turned).findings.map((f) => f.title), contains('Eje incorrecto'));
      });
    }
  });

  group('datos de la prueba', () {
    test('el resultado guarda lo medido, también en las líneas del video', () {
      final s = FakeStick(turnDeg: 90);
      final r = Run(s)..play(goodUser);
      final j = r.check.toJson();
      expect(j['resultado'], 'warn');
      expect(j['giro_corregido_grados'] as double, closeTo(90, 1));
      expect(j['inclino_adelante_grados'] as double, closeTo(30, 2));
      expect((j['calibracion'] as Map)['hrY'] as double, closeTo(30, 4));
      expect((j['ms_por_paso'] as Map).keys, containsAll(['link', 'rest', 'forward', 'right', 'range']));
      expect(r.check.dataLines.join('\n'), contains('Giro corregido 90°'));
    });

    test('al levantar sin inclinar queda registrado cuánto tiempo', () {
      final r = Run(FakeStick())
        ..play((step, ms, s) {
          if (step != CheckStep.forward) return goodUser(step, ms, s);
          s.mag = 1.4;
        });
      expect(r.check.toJson()['levanto_sin_inclinar_ms'] as double, greaterThan(15000));
    });

    test('el archivo es JSON y su traza se puede reproducir', () {
      final line = ImuTrace.encode([TraceSample(12.5, ImuFrameParser.parse('v2,100,0,0,4096,0,0,0')!)]);
      final json = diagnosticJson(
        kind: 'chequeo',
        when: DateTime(2026, 11, 5, 21, 57),
        params: SyncParams(),
        data: Run(FakeStick()).check.toJson(),
        traces: {'adult': line},
      );
      final j = jsonDecode(json) as Map<String, Object?>;
      expect(j['version'], appVersion);
      expect((j['parametros'] as Map)['matchMode'], 3);
      expect(ImuTrace.decode((j['trazas'] as Map)['adult'] as String).single.arrivalMs, 12.5);
      expect(diagnosticStamp(DateTime(2026, 11, 5, 21, 7)), '20261105-2107');
    });

    test('la versión que se ve en pantalla es la del pubspec', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $appVersion+'));
    });
  });

  group('motor', () {
    test('perder un stick durante la calibración la vuelve a empezar', () {
      final p = SyncParams();
      final e = SyncEngine(params: p, wallClock: () => DateTime(2026));
      var now = 0.0;
      e.start(mode: PlayMode.levels, calibrate: true, now: now);
      void run(double ms) {
        for (final end = now + ms; now < end;) {
          now += frame;
          final y = 30 * math.sin(now / 200);
          e.adult.feedTilt(0, y, p);
          e.child.feedTilt(0, y, p);
          e.tick(now);
        }
      }

      run(1000);
      e.pause();
      now += 10000;
      e.resume(now);
      e.tick(now + frame);
      expect(e.state, EngineState.calibrating, reason: 'antes terminaba al instante, con 1 s de datos');
      run(6200);
      expect(e.state, EngineState.playing);
      expect(e.adult.cal, isNotNull);
      expect(e.calSamples[Role.adult]!.moving, greaterThan(30));
    });

    test('con los siete abiertos, una sesión sigue del 6 al 7 con «seguir al siguiente»', () {
      expect(enabledLevelIds, {1, 2, 3, 4, 5, 6, 7});
      final e = SyncEngine(isLevelEnabled: enabledLevelIds.contains, wallClock: () => DateTime(2026));
      var now = 0.0;
      e.start(mode: PlayMode.levels, levelIndex: 5, now: now);
      e.prog = e.secs;
      final p = e.params;
      for (var i = 0; i < 400 && e.levelIndex == 5; i++) {
        now += frame;
        final y = 30 * math.sin(now / 200);
        e.adult.feedTilt(0, y, p);
        e.child.feedTilt(0, y, p);
        e.tick(now);
      }
      expect(e.levelIndex, 6);
      expect(e.state, EngineState.playing);
    });
  });

  group('pantalla', () {
    Future<void> show(WidgetTester tester, FakeStick s) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(MaterialApp(
        home: StickCheckScreen(role: Role.child, params: SyncParams(), read: s.read, saveAxes: (a) => s.axes = a),
      ));
    }

    testWidgets('sin datos muestra el primer paso y al final el resultado, sin desbordes', (tester) async {
      final s = FakeStick()..connected = false;
      await show(tester, s);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Chequeo del stick del niño'), findsOneWidget);
      expect(find.text('Conectando el stick'), findsOneWidget);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Hay algo que arreglar'), findsOneWidget);
      expect(find.text('El stick no conectó'), findsOneWidget);
      expect(find.text('Repetir'), findsOneWidget);
      expect(find.textContaining('Versión $appVersion'), findsOneWidget);
      await tester.tap(find.text('Repetir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Conectando el stick'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('para usuarios: sin lecturas técnicas ni compartir', (tester) async {
      final s = FakeStick()..connected = false;
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(MaterialApp(
        home: StickCheckScreen(role: Role.adult, params: SyncParams(), read: s.read, saveAxes: (_) {}, forUsers: true, title: 'Stick del adulto'),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Stick del adulto'), findsOneWidget);
      expect(find.textContaining('Sin datos del stick'), findsNothing);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Listo'), findsOneWidget);
      expect(find.textContaining('Versión'), findsNothing);
      expect(find.text('Compartir datos'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('graba la traza, la cierra una vez y la manda al compartir', (tester) async {
      final s = FakeStick()..connected = false;
      var starts = 0, stops = 0;
      String? sent;
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(MaterialApp(
        home: StickCheckScreen(
          role: Role.adult,
          params: SyncParams(),
          read: s.read,
          saveAxes: (_) {},
          startTrace: () => starts++,
          stopTrace: () {
            stops++;
            return 'traza';
          },
          share: (j) async => sent = j,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Sin datos del stick'), findsOneWidget);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect((starts, stops), (1, 1));
      await tester.tap(find.text('Compartir datos'));
      await tester.pump();
      expect(((jsonDecode(sent!) as Map)['trazas'] as Map)['adult'], 'traza');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(stops, 1, reason: 'al salir no se cierra dos veces');
    });
  });
}
