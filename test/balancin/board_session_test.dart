import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin/core/constants.dart';
import 'package:esp32_ble_telemetry/balancin/core/engine/balancin_engine.dart';
import 'package:esp32_ble_telemetry/balancin/core/engine/sound_command.dart';
import 'package:esp32_ble_telemetry/balancin/core/gesture/imu_gesture_reader.dart';
import 'package:esp32_ble_telemetry/balancin/core/gesture/synthetic_motion.dart';
import 'package:esp32_ble_telemetry/balancin/session/board_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sesión con reloj simulado.
class Harness {
  Harness() {
    session = BoardSession(
      onSound: sounds.addAll,
      clock: () => now,
      random: math.Random(1),
    );
    session.setPanelSize(PanelSide.left, 400, 600);
    session.setPanelSize(PanelSide.right, 400, 600);
    session.start();
  }

  double now = 0;
  final sounds = <SoundCommand>[];
  late final BoardSession session;

  void runFor(double ms) {
    final end = now + ms;
    while (now < end) {
      now += 1000 / 60;
      session.tick();
    }
  }
}

void main() {
  test('cada sesión nueva restaura el volumen del bus (aunque la anterior terminara tras una pérdida)', () {
    final h = Harness();
    final fade = h.sounds.whereType<BusFade>().first;
    expect(fade.to, BalancinConst.busGain);

    // Pérdida → terminar sin reanudar → el bus quedó en 0 → nueva sesión lo sube.
    h.session.loseStick(StickRole.child, LossCause.alcance);
    h.session.end();
    expect(h.sounds.whereType<BusFade>().last.to, 0);
    h.session.start();
    expect(h.sounds.whereType<BusFade>().last.to, BalancinConst.busGain);
  });

  test('arranca en REPOSO con el campo cerrado', () {
    final h = Harness();
    h.session.tick();
    expect(h.session.state, BalancinState.reposo);
    expect(h.session.stateName, 'Reposo');
    expect(h.session.fieldText, startsWith('Campo cerrado'));
    expect(h.session.columnOn(12), isFalse);
  });

  test('adulto y niño automáticos: juego activo, notas, destellos y luz', () {
    final h = Harness();
    h.session.setAutoAdult(true);
    h.session.setAutoChild(true);
    h.runFor(8000);
    expect(h.session.state, BalancinState.activo);
    expect(h.sounds.whereType<NoteOn>(), isNotEmpty);
    expect(h.session.fieldText, startsWith('Campo abierto'));
    // Avanza hasta el próximo tick que emita una nota y revisa su destello.
    NoteOn? fresh;
    for (var i = 0; i < 600 && fresh == null; i++) {
      final before = h.sounds.length;
      h.now += 1000 / 60;
      h.session.tick();
      final newNotes = h.sounds.skip(before).whereType<NoteOn>();
      if (newNotes.isNotEmpty) fresh = newNotes.last;
    }
    expect(fresh, isNotNull);
    expect(h.session.columnFlash(fresh!.index), isNotNull);
    expect(h.session.columnOn(fresh.index), isTrue);
    expect(h.session.lightLevel, greaterThan(0));
  });

  test('solo niño automático: silencio absoluto', () {
    final h = Harness();
    h.session.setAutoChild(true);
    h.runFor(5000);
    expect(h.session.state, BalancinState.silencio);
    expect(h.sounds.where((c) => c is! BusFade), isEmpty);
    expect(h.session.lightLevel, 0);
  });

  test('los toques del panel izquierdo mueven al adulto; tras intercambiar, al niño', () {
    final h = Harness();
    for (var i = 0; i < 20; i++) {
      h.now += 16;
      h.session.feedPanel(PanelSide.left, 100 + i * 10, 300);
      h.session.tick();
    }
    expect(h.session.state, BalancinState.espera);
    expect(h.sounds.whereType<OpeningSound>().length, 1);

    h.session.swapSides();
    expect(h.session.sides[PanelSide.left], StickRole.child);
    expect(h.session.engine.metrics.swaps, 1);
    expect(h.session.dotFor(PanelSide.left), isNull);
    h.now += 500; // el adulto queda quieto
    for (var i = 0; i < 20; i++) {
      h.now += 16;
      h.session.feedPanel(PanelSide.left, 100 + i * 10, 300);
      h.session.tick();
    }
    expect(h.session.state, BalancinState.silencio);
  });

  test('demo "oculto" abre el timbre oculto y la luz del eje se vuelve amarilla', () {
    final h = Harness();
    h.session.setDemo(DemoScenario.oculto);
    h.session.setEjeMode(true);
    h.runFor(7000);
    expect(h.session.engine.metrics.hidden, 1);
    expect(h.session.hiddenText, isNotNull);
    expect(h.session.ejeGlow.hidden, isTrue);
    expect(h.session.ejeFlashes, isNotEmpty);
    for (final f in h.session.ejeFlashes) {
      expect(f.x, inInclusiveRange(0.1, 0.9));
    }
  });

  test('pérdida de stick: apaga el bus, pausa y reanuda conservando la telemetría', () {
    final h = Harness();
    h.session.setAutoAdult(true);
    h.session.setAutoChild(true);
    h.runFor(5000);
    final events = h.session.engine.metrics.events;
    h.session.loseStick(StickRole.child, LossCause.alcance);
    expect(h.session.lostRole, StickRole.child);
    expect(h.sounds.last, isA<BusFade>().having((b) => b.to, 'to', 0));
    expect(h.session.running, isFalse);
    h.runFor(2000);
    expect(h.session.engine.metrics.events, events);

    h.session.resumeAfterLoss();
    expect(h.session.lostRole, isNull);
    expect(h.session.running, isTrue);
    expect(h.sounds.whereType<BusFade>().last.to, BalancinConst.busGain);
  });

  test('terminar: resonancia final, cierre y reporte con 10 tarjetas y 5 regímenes', () {
    final h = Harness();
    h.session.setAutoAdult(true);
    h.session.setAutoChild(true);
    h.runFor(6000);
    h.session.end();
    expect(h.session.closed, isTrue);
    expect(h.sounds.last, isA<FinalSound>());
    expect(h.session.summaryCards.length, 10);
    final bars = h.session.regimeBars;
    expect(bars.length, 5);
    expect(bars.fold<double>(0, (a, b) => a + b.percent), closeTo(100, 0.6));
    expect(h.session.report()['eventos_nino'], h.session.engine.metrics.events);
  });

  test('tarjetas de telemetría en vivo: 6, en el orden del prototipo', () {
    final h = Harness();
    final cards = h.session.telemetryCards;
    expect(cards.map((c) => c.label), [
      'juego activo',
      'campo abierto · permanencia del adulto',
      'latencias',
      'reanudaciones',
      'eventos del niño',
      'timbres ocultos',
    ]);
  });

  group('Stick real (lector IMU conectado al rol del niño)', () {
    /// Simula el stick B: bias real en X y rotación [gz] (°/s) en Z, a 100 Hz,
    /// con un tick del tablero por muestra.
    void feedImu(Harness h, ImuGestureReader imu, double ms, double Function(double s) gz) {
      final end = h.now + ms;
      while (h.now < end) {
        h.now += 10;
        imu.addSample(
          ImuSample(
            tMs: h.now.toInt(),
            ax: 0,
            ay: 0,
            az: 4096,
            gx: (41.6 * ImuFrameParser.gyroLsbPerDps).round(),
            gy: 0,
            gz: (gz(h.now / 1000) * ImuFrameParser.gyroLsbPerDps).round(),
          ),
          h.now,
        );
        h.session.tick();
      }
    }

    test('stick B solo: silencio; con adulto automático: suena', () {
      final h = Harness();
      final imu = ImuGestureReader();
      h.session.attachReader(StickRole.child, imu);
      expect(h.session.isExternal(StickRole.child), isTrue);
      expect(h.session.engine.child, same(imu));

      feedImu(h, imu, 1000, (s) => 0); // calibración en reposo
      expect(imu.calibrated, isTrue);

      feedImu(h, imu, 3000, (s) => 200 * math.sin(2 * math.pi * 1.5 * s));
      expect(h.session.state, BalancinState.silencio);
      expect(h.sounds.where((c) => c is! BusFade), isEmpty, reason: 'criterio 1 con el stick real');

      h.session.setAutoAdult(true);
      feedImu(h, imu, 4000, (s) => 200 * math.sin(2 * math.pi * 1.5 * s));
      expect(h.session.state, BalancinState.activo);
      expect(h.sounds.whereType<NoteOn>(), isNotEmpty);
      expect(h.session.panelMoving(PanelSide.right), isTrue);
    });

    test('attachReader(null) devuelve el rol al dedo y conserva la calibración', () {
      final h = Harness();
      final imu = ImuGestureReader();
      h.session.attachReader(StickRole.child, imu);
      feedImu(h, imu, 1000, (s) => 0);
      h.session.attachReader(StickRole.child, null);
      expect(h.session.isExternal(StickRole.child), isFalse);
      expect(h.session.engine.child, same(h.session.childTouch));
      expect(imu.calibrated, isTrue);
    });
  });
}
