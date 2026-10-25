// Núcleo v2: lo que no cubre la paridad con el prototipo (plan v2, fase 1).
// Límite del plano (§5.2), calibración (§4.3), nivel 1 con cierre al lograrlo
// (§10.2), Libre, pausa/cierre, parámetros, luz y registro de sesión.

import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin_v2/core/calibration.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/light_model.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/stick_state.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/synthetic_source.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

const fps = 1000 / 60;

/// Corre el motor de [from] a [to] ms a 60 fps y devuelve los eventos.
List<SyncEvent> runFor(SyncEngine e, double from, double to) {
  final out = <SyncEvent>[];
  for (var now = from; now < to; now += fps) {
    out.addAll(e.tick(now));
  }
  return out;
}

SyncEngine v2Engine() => SyncEngine(closeOnIdle: true, isLevelEnabled: enabledLevelIds.contains);

void main() {
  group('límite del plano', () {
    final p = SyncParams();

    test('inclinaciones extremas o inválidas dejan el punto dentro de ±6', () {
      final st = StickState(Role.child);
      final inputs = [1000.0, -1000.0, 89.9, -720.0, double.nan, double.infinity, double.negativeInfinity, 1e308];
      var t = 0.0;
      for (final x in inputs) {
        for (final y in inputs) {
          st.feedTilt(x, y, p);
          st.update(t += fps, fps / 1000, p);
          for (final v in [st.raw.x, st.raw.y, st.pos.x, st.pos.y]) {
            expect(v.isFinite, isTrue);
            expect(v.abs(), lessThanOrEqualTo(planeLimit));
          }
        }
      }
    });

    test('al pasarse del rango, el punto queda en el borde e indica hacia dónde', () {
      final st = StickState(Role.child); // rango por defecto 45°
      st.feedTilt(90, -10, p);
      expect(st.raw.x, planeLimit);
      expect(st.overflow.x, greaterThan(0));
      expect(st.overflow.y, 0);
      expect(st.atEdge, isTrue);
      st.feedTilt(-90, 0, p);
      expect(st.raw.x, -planeLimit);
      expect(st.overflow.x, lessThan(0));
      st.feedTilt(20, 20, p);
      expect(st.atEdge, isFalse);
    });

    test('se mide la fracción del tiempo en el borde', () {
      final st = StickState(Role.adult);
      var t = 0.0;
      for (var i = 0; i < 60; i++) {
        st.feedTilt(i < 15 ? 80 : 10, 0, p); // 15 de 60 cuadros fuera de rango
        st.update(t += fps, fps / 1000, p);
      }
      expect(st.edgeFraction, closeTo(0.25, 1e-9));
    });

    test('las lecturas no finitas se ignoran (no mueven el punto)', () {
      final st = StickState(Role.adult);
      st.feedTilt(15, 15, p);
      final before = st.raw;
      st.feedTilt(double.nan, 3, p);
      expect(st.raw.x, before.x);
      expect(st.raw.y, before.y);
    });
  });

  group('calibración', () {
    final p = SyncParams();

    test('como el prototipo: centro del primer segundo, medio rango de los percentiles, mínimo por rol', () {
      final p = SyncParams.prototype();
      final c = Calibration();
      for (var t = 0.0; t < 6000; t += 10) {
        final s = t / 1000;
        // Adulto: gesto chico (±10°) alrededor de 5°. Niño: amplio (±40°) alrededor de −3°.
        c.add(Role.adult, t, P2(5 + (t < 1000 ? 0 : 10 * math.sin(s * 3)), 0));
        c.add(Role.child, t, P2(-3, -3 + (t < 1000 ? 0 : 40 * math.sin(s * 2))));
      }
      final a = c.result(Role.adult, p)!, k = c.result(Role.child, p)!;
      expect(a.cx, closeTo(5, 1e-9));
      expect(a.hr, p.minA, reason: '±10° < mínimo de 15°');
      expect(k.cy, closeTo(-3, 1e-9));
      expect(k.hr, inInclusiveRange(38, 40.01));
    });

    test('robusta: un stick apoyado al empezar no corre el centro (prueba del 18-10-2026)', () {
      final c = Calibration();
      for (var t = 0.0; t < 6000; t += 16) {
        final s = t / 1000;
        if (t < 1500) {
          // Apoyado en la mesa: inclinación enorme y quieto.
          c.add(Role.child, t, const P2(10, 85), moving: false);
        } else {
          // En la mano, balanceándose ±30° alrededor de (5, −3).
          c.add(Role.child, t, P2(5 + 4 * math.sin(s * 5), -3 + 30 * math.sin(s * 4)));
        }
      }
      final robusta = c.result(Role.child, SyncParams())!;
      expect(robusta.cx, closeTo(5, 1));
      expect(robusta.cy, closeTo(-3, 1.5));
      expect(robusta.hrY, closeTo(30, 2));
      expect(robusta.hrX, SyncParams().minC, reason: 'casi no se movió hacia los lados: mínimo');
      final proto = c.result(Role.child, SyncParams.prototype())!;
      expect(proto.cy, closeTo(85, 1), reason: 'el prototipo toma la postura de la mesa como centro');
    });

    test('robusta: sin movimiento suficiente no calibra', () {
      final c = Calibration();
      for (var t = 0.0; t < 6000; t += 16) {
        c.add(Role.adult, t, const P2(0, 0), moving: t < 300);
      }
      expect(c.result(Role.adult, SyncParams()), isNull);
    });

    test('tras calibrar con el stick apoyado al empezar, el punto ya no vive en el borde', () {
      final e = SyncEngine(isLevelEnabled: (_) => false);
      e.drive = (now) {
        final s = now / 1000;
        for (final st in [e.adult, e.child]) {
          if (now < 1500) {
            st.feedTilt(10, 85, e.params); // apoyado
          } else {
            st.feedTilt(5, -3 + 30 * math.sin(s * 4), e.params);
          }
        }
      };
      e.start(mode: PlayMode.levels, calibrate: true, now: 0);
      for (var now = 0.0; now < 20000; now += fps) {
        e.tick(now);
      }
      expect(e.adult.cal, isNotNull);
      expect(e.child.edgeFraction, lessThan(0.15));
      expect(e.adult.edgeFraction, lessThan(0.15));
    });

    test('sin datos suficientes no calibra', () {
      final c = Calibration();
      c.add(Role.adult, 0, P2.zero);
      expect(c.result(Role.adult, p), isNull);
      expect(c.result(Role.child, p), isNull);
    });

    test('tras calibrar, el gesto chico del adulto llega tan lejos como el amplio del niño', () {
      final st = StickState(Role.adult)..cal = const StickCal(cx: 0, cy: 0, hr: 15);
      st.feedTilt(0, 15, p);
      expect(st.raw.y, planeLimit);
      final kid = StickState(Role.child)..cal = const StickCal(cx: 0, cy: 0, hr: 40);
      kid.feedTilt(0, 40, p);
      expect(kid.raw.y, planeLimit);
      final uncal = StickState(Role.adult);
      uncal.feedTilt(0, 15, p);
      expect(uncal.raw.y, 3, reason: 'sin calibrar, 15° de 30° = mitad del plano');
    });

    test('la sesión con calibración avisa y después empieza el nivel', () {
      final e = v2Engine();
      e.drive = (now) => synthDrive(e, SynthQuality.cycle, now);
      final ev = e.start(mode: PlayMode.levels, calibrate: true, now: 0);
      expect(ev.whereType<SayEvent>().single.text, 'Muévanse libremente unos segundos.');
      expect(e.state, EngineState.calibrating);
      final later = runFor(e, 0, 6200);
      expect(later.whereType<CalibrationDoneEvent>(), hasLength(1));
      expect(e.state, EngineState.playing);
      expect(e.adult.cal, isNotNull);
      expect(e.child.cal, isNotNull);
    });
  });

  group('nivel 1 «Juntos»', () {
    test('se logra con 8 s en sincronía, cambia la guía a los 4 s y (sin seguir) va al final', () {
      final e = SyncEngine(params: SyncParams()..autoNext = 0, closeOnIdle: true, isLevelEnabled: enabledLevelIds.contains);
      e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
      final start = e.start(mode: PlayMode.levels, now: 0);
      expect(start.whereType<SayEvent>().single.text,
          'Nivel 1. Juntos. Suban y bajen los sticks al mismo tiempo. Guía el adulto, luego el niño.');
      final ev = runFor(e, 0, 30000);
      final guides = ev.whereType<GuideChangedEvent>().toList();
      expect(guides.map((g) => g.guide), [Role.child], reason: 'una sola vez');
      expect(ev.whereType<SayEvent>().map((s) => s.text), contains('Ahora guía el niño.'));
      final done = ev.whereType<LevelCompletedEvent>().single;
      expect(done.levelId, 1);
      final phrase = ev.whereType<PhraseEvent>().single;
      expect(phrase.midi, [60, 62, 64, 67]);
      final closed = ev.whereType<SessionClosedEvent>().single;
      expect(closed.byIdle, isFalse);
      expect(closed.at - done.at, closeTo(phraseDuration(4, 0.24) * 1000 + 2200, fps + 1e-6));
      expect(closed.record.levels, [1]);
      expect(closed.record.mode, 'levels');
      expect(closed.record.traj, isNotEmpty);
      expect(e.report()['niveles_logrados'], [1]);
      expect(ev.whereType<SayEvent>().where((s) => s.text.startsWith('Nivel 2')), isEmpty,
          reason: 'con «seguir al siguiente nivel» apagado no continúa');
    });

    test('con «seguir al siguiente nivel» (por defecto) continúa con el 2 en la misma sesión', () {
      final e = v2Engine();
      e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
      e.start(mode: PlayMode.levels, now: 0);
      final ev = runFor(e, 0, 20000);
      expect(ev.whereType<LevelCompletedEvent>().first.levelId, 1);
      expect(ev.whereType<SessionClosedEvent>(), isEmpty);
      expect(ev.whereType<SayEvent>().map((s) => s.text),
          contains('Nivel 2. Espejo. Frente a frente, como en un espejo. Guía el niño, luego el adulto.'));
      expect(e.level!.id, 2);
      expect(e.levelTelemetry.map((l) => l.nivel), [1, 2]);
    });

    test('lejos de la sincronía no hay progreso', () {
      final e = v2Engine();
      e.drive = (now) => synthDrive(e, SynthQuality.lejos, now);
      e.start(mode: PlayMode.levels, now: 0);
      runFor(e, 0, 15000);
      expect(e.levelsDone, isEmpty);
      expect(e.current!.sinc, lessThan(e.current!.juego * 0.5));
    });

    test('solo cuenta la altura: el movimiento lateral no cambia d', () {
      // Mismo movimiento vertical, con y sin movimiento lateral muy distinto: misma d.
      double dWith(double Function(double s) ax, double Function(double s) cx, {SyncParams? p}) {
        final e = SyncEngine(params: p, isLevelEnabled: enabledLevelIds.contains)..start(mode: PlayMode.levels, now: 0);
        for (var i = 0; i < 300; i++) {
          final s = i * fps / 1000;
          feedPlane(e.adult, ax(s), 2 * math.sin(s), e);
          feedPlane(e.child, cx(s), 2 * math.sin(s), e);
          e.tick(i * fps);
        }
        return e.d;
      }

      for (final p in [SyncParams(), SyncParams.prototype()]) {
        final quieto = dWith((s) => 0, (s) => 0, p: p);
        final lateral = dWith((s) => 5 * math.sin(s * 2), (s) => -5 * math.sin(s * 3), p: p);
        expect(lateral, closeTo(quieto, 1e-9));
        expect(lateral, lessThan(0.05));
      }
    });

    test('si se mueve uno solo, el progreso no avanza', () {
      for (final mover in Role.values) {
        final e = v2Engine();
        e.drive = (now) {
          final s = now / 1000;
          final st = e.stick(mover), other = e.stick(mover == Role.adult ? Role.child : Role.adult);
          feedPlane(st, 0, 4 * math.sin(s * 3), e);
          feedPlane(other, 0, 0, e);
        };
        e.start(mode: PlayMode.levels, now: 0);
        runFor(e, 0, 10000);
        expect(e.prog, 0, reason: 'se mueve solo $mover');
        expect(e.stick(mover).active(10000), isTrue);
      }
    });

    test('quietos 30 s: la sesión se cierra sola', () {
      final e = v2Engine();
      e.start(mode: PlayMode.levels, now: 0);
      final ev = runFor(e, 0, 32000);
      final closed = ev.whereType<SessionClosedEvent>().single;
      expect(closed.byIdle, isTrue);
      expect(closed.at, greaterThan(30000));
    });

    test('en el banco (closeOnIdle = false) no se cierra por quietud', () {
      final e = SyncEngine(isLevelEnabled: enabledLevelIds.contains)..start(mode: PlayMode.levels, now: 0);
      expect(runFor(e, 0, 40000).whereType<SessionClosedEvent>(), isEmpty);
    });
  });

  group('modo Libre', () {
    test('d es bajo para juntos, espejo y sube y baja', () {
      final e = SyncEngine()..start(mode: PlayMode.free, now: 0);
      var now = 0.0;
      void place(double ax, double ay, double cx, double cy) {
        feedPlane(e.adult, ax, ay, e);
        feedPlane(e.child, cx, cy, e);
        for (var i = 0; i < 120; i++) {
          e.tick(now += fps);
        }
      }

      place(2, 3, 2, 3); // juntos
      expect(e.syncDistance(Relation.free, now), lessThan(0.05));
      place(2, 3, -2, 3); // espejo
      expect(e.syncDistance(Relation.free, now), lessThan(0.05));
      place(2, 3, 2, -3); // sube y baja
      expect(e.syncDistance(Relation.free, now), lessThan(0.05));
      place(4, 3, -1, -5); // nada en común
      expect(e.syncDistance(Relation.free, now), greaterThan(2));
    });

    test('no hay progreso ni guía, y el registro dice «free»', () {
      final e = SyncEngine(closeOnIdle: true);
      e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
      final ev = e.start(mode: PlayMode.free, now: 0);
      expect(ev.whereType<SayEvent>().single.text, 'Juego libre. Busquen un movimiento en común.');
      runFor(e, 0, 20000);
      expect(e.prog, 0);
      expect(e.syncT, greaterThan(5));
      final rec = e.close(20000).whereType<SessionClosedEvent>().single.record;
      expect(rec.isFree, isTrue);
      expect(rec.levels, isEmpty);
    });
  });

  group('pérdida y cierre', () {
    test('en pausa no avanza, se puede terminar, y no se cierra dos veces', () {
      final e = v2Engine();
      e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
      e.start(mode: PlayMode.levels, now: 0);
      runFor(e, 0, 3000);
      final juego = e.current!.juego;
      e.pause();
      runFor(e, 3000, 6000);
      expect(e.current!.juego, juego);
      expect(e.close(6000).whereType<SessionClosedEvent>(), hasLength(1));
      expect(e.close(6100), isEmpty);
      expect(e.resume(6200), isEmpty);
      expect(e.running, isFalse);
    });

    test('al volver el stick sigue la misma sesión y su telemetría', () {
      final e = v2Engine();
      e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
      e.start(mode: PlayMode.levels, now: 0);
      runFor(e, 0, 3000);
      final lt = e.current;
      e.pause();
      e.resume(5000);
      runFor(e, 5000, 7000);
      expect(e.current, same(lt));
      expect(e.levelTelemetry, hasLength(1));
    });
  });

  group('parámetros', () {
    test('JSON de ida y vuelta; claves desconocidas o inválidas se ignoran', () {
      final p = SyncParams()
        ..tolScale = 1.3
        ..kAccel = 0.05;
      final q = SyncParams.fromJson({...p.toJson(), 'vibMs': 80, 'alpha': 'x', 'onSpeed': double.nan});
      expect(q.tolScale, 1.3);
      expect(q.kAccel, 0.05);
      expect(q.alpha, 0.2);
      expect(q.onSpeed, 2.5);
      expect(q.toJson().containsKey('vibMs'), isFalse);
      q.resetToDefaults();
      expect(q.toJson(), SyncParams().toJson());
    });
  });

  group('luz', () {
    test('quietos: las dos mitades tenues y con su color', () {
      final e = SyncEngine()..start(mode: PlayMode.levels, now: 0);
      e.tick(0);
      final l = lightFrame(e, 0);
      expect(l.topOpacity, closeTo(0.14, 1e-12));
      expect(l.bottomOpacity, closeTo(0.14, 1e-12));
      expect(l.top, lightAdult);
      expect(l.bottom, lightChild);
    });

    test('en sincronía las dos se acercan al oliva', () {
      final e = SyncEngine();
      e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
      e.start(mode: PlayMode.levels, now: 0);
      runFor(e, 0, 5000);
      expect(e.inSync, isTrue);
      final l = lightFrame(e, 5000);
      expect(l.blend, greaterThan(0.5));
      expect((l.top.g - lightOlive.g).abs(), lessThan((lightAdult.g - lightOlive.g).abs()));
    });
  });

  test('registro de sesión: JSON de ida y vuelta', () {
    const r = SessionRecord(t: 5, mode: 'levels', levels: [1], dur: 12.5, sync: 0.4, song: false, lead: -0.2, traj: [
      [1, 2, 3, 4]
    ]);
    final back = SessionRecord.fromJson(r.toJson());
    expect(back.toJson(), r.toJson());
  });
}
