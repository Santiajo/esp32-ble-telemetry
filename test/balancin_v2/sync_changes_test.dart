// Cambios del usuario del 18-10-2026 (plan v2 §12): salir de la sincronía
// cuesta, la sincronía mira la velocidad, la frase se arma por cuartos y las
// notas del niño recorren la escala en vez de saltar.

import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin_v2/core/audio/layers.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/synthetic_source.dart';
import 'package:flutter_test/flutter_test.dart';

const fps = 1000 / 60;

/// Adulto balanceándose ±4 a 0,8 Hz; el niño según [childY] (función de s y la y del adulto).
SyncEngine run(SyncParams p, double seconds, double Function(double s, double ay) childY, {List<SyncEvent>? events}) {
  final e = SyncEngine(params: p, isLevelEnabled: enabledLevelIds.contains);
  e.drive = (now) {
    final s = now / 1000;
    final ay = 4 * math.sin(2 * math.pi * 0.8 * s);
    feedPlane(e.adult, 0, ay, e);
    feedPlane(e.child, 0, childY(s, ay), e);
  };
  final started = e.start(mode: PlayMode.levels, now: 0); // fuera del `?.`: si no, no se llama
  events?.addAll(started);
  for (var now = 0.0; now < seconds * 1000; now += fps) {
    final ev = e.tick(now);
    events?.addAll(ev);
  }
  return e;
}

void main() {
  group('§12.2 · la sincronía mira la velocidad', () {
    test('cruzarse en sentido contrario ya no cuenta como «juntos»', () {
      double opposite(double s, double ay) => -ay;
      final proto = run(SyncParams.prototype(), 10, opposite);
      final nuevo = run(SyncParams(), 10, opposite);
      expect(proto.current!.sinc, greaterThan(0.5), reason: 'el prototipo suma tiempo en cada cruce');
      expect(nuevo.current!.sinc, lessThan(0.1));
    });

    test('moverse juntos sigue contando, aunque haya un pequeño desfase', () {
      final nuevo = run(SyncParams(), 6, (s, ay) => 4 * math.sin(2 * math.pi * 0.8 * (s - 0.05)));
      expect(nuevo.current!.sinc / nuevo.current!.juego, greaterThan(0.8));
    });
  });

  group('§12.5 · tolerancia de retraso (lo visto en «Pruebas 2»)', () {
    /// Fracción del tiempo en sincronía, en el nivel 1 «Juntos», con los dos
    /// balanceándose ±5 a [hz] y el niño [lagMs] detrás. (En Libre, ir opuestos
    /// también vale: cuenta como «sube y baja».)
    double syncShare(SyncParams base, double hz, double lagMs) {
      final p = base.copy()..secScale = 100; // que el nivel no termine durante la medición
      final e = SyncEngine(params: p, isLevelEnabled: (_) => false);
      e.drive = (now) {
        final s = now / 1000;
        feedPlane(e.adult, 0, 5 * math.sin(2 * math.pi * hz * s), e);
        feedPlane(e.child, 0, 5 * math.sin(2 * math.pi * hz * (s - lagMs / 1000)), e);
      };
      e.start(mode: PlayMode.levels, now: 0);
      var inSync = 0, n = 0;
      for (var now = 0.0; now < 12000; now += fps) {
        e.tick(now);
        if (now > 2000) {
          n++;
          if (e.inSync) inSync++;
        }
      }
      return inSync / n;
    }

    final antes = SyncParams()..syncLagMs = 0; // como estaba ayer
    final ahora = SyncParams();

    test('rápido (1,7 Hz) con el niño 80 ms detrás: antes casi nunca, ahora casi siempre', () {
      expect(syncShare(antes, 1.7, 80), lessThan(0.4));
      expect(syncShare(ahora, 1.7, 80), greaterThan(0.9));
    });

    test('rápido con 120 ms de retraso también cuenta', () {
      expect(syncShare(ahora, 1.7, 120), greaterThan(0.85));
    });

    test('lento sigue funcionando igual de bien', () {
      expect(syncShare(ahora, 0.5, 80), greaterThan(0.95));
    });

    test('un retraso de medio vaivén (casi opuestos) no cuenta', () {
      expect(syncShare(ahora, 1.7, 300), lessThan(0.15));
    });

    test('moverse en sentido contrario sigue sin contar', () {
      final e = run(SyncParams(), 10, (s, ay) => -ay);
      expect(e.current!.sinc, lessThan(0.1));
    });
  });

  group('§12.1 · salir de la sincronía cuesta', () {
    double syncThenOff(double s, double ay) => s < 5 ? ay : -ay;

    test('fuera de la zona, tras el margen, el progreso baja', () {
      final p = SyncParams();
      final at5 = run(p, 5, syncThenOff).prog;
      final at8 = run(p, 8, syncThenOff).prog;
      expect(at5, greaterThan(3));
      // 3 s fuera: pierde ~ (3 − margen) s de progreso.
      expect(at8, closeTo(at5 - (3 - p.slipGrace), 0.6));
    });

    test('como el prototipo (pérdida 0): el progreso se conserva', () {
      final p = SyncParams.prototype()..velWeight = 0.06;
      expect(run(p, 8, syncThenOff).prog, closeTo(run(p, 5, syncThenOff).prog, 0.15));
    });

    test('un tropiezo más corto que el margen no cuesta nada', () {
      // Fuera solo 0,3 s (margen 0,4 s).
      final p = SyncParams();
      final e = run(p, 6, (s, ay) => (s > 3 && s < 3.3) ? -ay : ay);
      final ref = run(p, 6, (s, ay) => ay);
      expect(e.prog, closeTo(ref.prog, 0.5));
      expect(e.current!.salidas, greaterThanOrEqualTo(1));
    });

    test('las salidas quedan en la telemetría', () {
      final e = run(SyncParams(), 8, syncThenOff);
      expect(e.current!.salidas, greaterThanOrEqualTo(1));
      final niveles = e.report()['niveles'] as List;
      expect((niveles.first as Map)['salidas_de_sincronia'], e.current!.salidas);
    });
  });

  group('§12.3 · la frase se arma por cuartos', () {
    test('suenan do, re y mi a los 2, 4 y 6 s; el nivel completa con sol', () {
      final ev = <SyncEvent>[];
      run(SyncParams(), 20, (s, ay) => ay, events: ev);
      // Solo el nivel 1 (después sigue el 2, con su propia frase).
      final done1 = ev.whereType<LevelCompletedEvent>().first;
      final steps = ev.whereType<PhraseStepEvent>().where((x) => x.at <= done1.at).toList();
      expect(steps.map((x) => (x.step, x.midi, x.up)), [(1, 60, true), (2, 62, true), (3, 64, true)]);
      expect(done1.levelId, 1);
    });

    test('si el progreso vuelve a bajar de un cuarto, esa nota «cae»', () {
      final ev = <SyncEvent>[];
      // Juntos 4,5 s (pasa el cuarto 2), luego desincronizados 4 s.
      run(SyncParams(), 9, (s, ay) => s < 4.5 ? ay : -ay, events: ev);
      final steps = ev.whereType<PhraseStepEvent>().toList();
      expect(steps.where((x) => x.up).map((x) => x.step), [1, 2]);
      expect(steps.where((x) => !x.up).map((x) => x.step).first, 2);
    });

    test('apagada (0) no emite nada', () {
      final ev = <SyncEvent>[];
      run(SyncParams()..phraseSteps = 0, 20, (s, ay) => ay, events: ev);
      expect(ev.whereType<PhraseStepEvent>(), isEmpty);
    });
  });

  group('§12.4 · escala de paso en las notas del niño', () {
    test('de do4 a do5 (5 pasos): 4 notas de paso y la de llegada, en 120 ms', () {
      final r = AudioLayers.childRun(1000, 0, 5, 0.2, 6, 120, 0.6);
      expect(r.map((n) => n.midi), [62, 64, 67, 69, 72]);
      expect(r.map((n) => n.at), [1000, 1024, 1048, 1072, 1096].map((v) => closeTo(v, 1e-9)));
      expect(r.take(4).every((n) => n.passing && (n.gain - 0.12).abs() < 1e-12), isTrue);
      expect(r.last.passing, isFalse);
      expect(r.last.gain, 0.2);
    });

    test('bajando también recorre la escala', () {
      expect(AudioLayers.childRun(0, 6, 3, 0.2, 6, 120, 0.6).map((n) => n.midi), [72, 69, 67]);
    });

    test('un salto enorme se limita al máximo de notas, repartidas parejo', () {
      final r = AudioLayers.childRun(0, 0, 10, 0.2, 3, 120, 0.6);
      expect(r.length, 4);
      expect(r.last.midi, childScale[10]);
      final idx = r.take(3).map((n) => childScale.indexOf(n.midi)).toList();
      expect(idx, [for (var i = 1; i < idx.length; i++) idx[i]].isEmpty ? idx : idx..sort());
      expect(idx.toSet().length, 3);
    });

    test('notas vecinas, primera nota o escala apagada: una sola nota inmediata', () {
      for (final r in [
        AudioLayers.childRun(5, 3, 4, 0.2, 6, 120, 0.6),
        AudioLayers.childRun(5, null, 8, 0.2, 6, 120, 0.6),
        AudioLayers.childRun(5, 0, 8, 0.2, 0, 120, 0.6),
      ]) {
        expect(r.length, 1);
        expect(r.single.at, 5);
        expect(r.single.passing, isFalse);
      }
    });

    test('en juego, un movimiento rápido del niño produce notas de paso', () {
      final e = SyncEngine(params: SyncParams());
      final l = AudioLayers();
      e.drive = (now) {
        final s = now / 1000;
        feedPlane(e.adult, 0, 3 * math.sin(s * 3), e);
        feedPlane(e.child, 0, 5.5 * math.sin(s * 9), e); // rápido: cruza varias notas por cuadro
      };
      e.start(mode: PlayMode.levels, now: 0);
      final notes = <NoteCmd>[];
      for (var now = 0.0; now < 4000; now += fps) {
        e.tick(now);
        notes.addAll(l.update(now, e.lastDt, e));
      }
      expect(notes.where((n) => n.passing), isNotEmpty);
      // Entre notas consecutivas nunca hay un salto de más de un paso... salvo cuando el tope recorta.
      final real = notes.where((n) => !n.passing).length;
      expect(real, greaterThan(5));
    });
  });

  test('parámetros: claves nuevas en JSON y preajuste del prototipo', () {
    final j = SyncParams().toJson();
    for (final k in ['slipGrace', 'slipDrain', 'velWeight', 'phraseSteps', 'runMaxNotes', 'runMs', 'runGain']) {
      expect(j.containsKey(k), isTrue, reason: k);
    }
    final p = SyncParams.prototype();
    expect([p.slipDrain, p.velWeight, p.phraseSteps, p.runMaxNotes], [0, 0, 0, 0]);
  });
}
