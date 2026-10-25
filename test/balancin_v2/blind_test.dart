// Opciones para jugar sin ver el plano (plan v2 §15): zonas, trazo, solo el
// lado, borde que no cuenta, campanita de guía y sonidos que ubican. De fábrica
// solo viene «zonas y trazo» (§16); la paridad con el prototipo está en
// parity_test.dart.

import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin_v2/core/audio/layers.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/stick_state.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/synthetic_source.dart';
import 'package:flutter_test/flutter_test.dart';

const fps = 1000 / 60;

typedef Pos = ({double x, double y});

/// Como `feedPlane`, pero sin recortar: más allá de ±6 el stick queda pegado al borde.
void feed(StickState st, Pos p, SyncEngine e) {
  final r = st.range(e.params);
  st.feedTilt(r.cx + p.x / planeLimit * r.hrX, r.cy + p.y / planeLimit * r.hrY, e.params);
}

/// Juega el nivel [levelId] con [params] (sin seguir al siguiente). El adulto y
/// el niño siguen [adult] y [child] (posiciones en el plano según los segundos).
SyncEngine play(int levelId, SyncParams params, Pos Function(double s) adult, Pos Function(double s) child,
    {double seconds = 20, List<SyncEvent>? events}) {
  final e = SyncEngine(params: params..autoNext = 0, isLevelEnabled: (_) => true);
  e.drive = (now) {
    final s = now / 1000;
    feed(e.adult, adult(s), e);
    feed(e.child, child(s), e);
  };
  final ev = e.start(mode: PlayMode.levels, levelIndex: levelId - 1, now: 0);
  events?.addAll(ev);
  for (var now = 0.0; now < seconds * 1000 && e.running; now += fps) {
    final out = e.tick(now);
    events?.addAll(out);
  }
  return e;
}

/// Sube y baja lento (0,4 Hz) con [amp] alrededor de [center].
Pos Function(double) wave(double amp, {double center = 0, double phase = 0, double x = 0}) =>
    (s) => (x: x, y: center + amp * math.sin(2 * math.pi * 0.4 * s + phase));

void main() {
  test('de fábrica: zonas y trazo, lo demás apagado; «Sin vista» lo enciende todo', () {
    final d = SyncParams();
    expect(d.usesZones && d.usesTrace, isTrue);
    expect(SyncParams.prototype().matchMode, 0, reason: 'el prototipo mide por punto');
    for (final k in ['sideOnly', 'edgeNoSync', 'guideChime', 'sharedScale', 'sideTimbre', 'fifthRamp']) {
      expect(d[k], 0, reason: k);
    }
    final b = SyncParams.blind();
    expect(b.usesZones && b.usesTrace, isTrue);
    expect(b.sideOnly + b.edgeNoSync + b.guideChime + b.sharedScale + b.sideTimbre + b.fifthRamp, 6);
    expect(SyncParams.fromJson(b.toJson()).toJson(), b.toJson(), reason: 'se guarda y se recupera');
  });

  group('zonas', () {
    test('«Juntos»: misma franja cuenta aunque las alturas difieran', () {
      // Los dos entre 2,5 y 5,5 (franja de arriba), pero cuando uno sube el otro baja.
      final zonas = play(1, SyncParams()..matchMode = 1, wave(1.5, center: 4), wave(1.5, center: 4, phase: math.pi));
      expect(zonas.levelsDone, [1]);
      final punto = play(1, SyncParams()..matchMode = 0, wave(1.5, center: 4), wave(1.5, center: 4, phase: math.pi));
      expect(punto.levelsDone, isEmpty, reason: 'con el punto, hasta 3 de diferencia queda fuera de la tolerancia');
    });

    test('fuera de la franja, d = lo que falta para entrar', () {
      final e = SyncEngine(params: SyncParams()..matchMode = 1..syncLagMs = 0..velWeight = 0);
      e.start(mode: PlayMode.levels, now: 0);
      feedPlane(e.adult, 0, 4, e);
      feedPlane(e.child, 0, 0, e);
      for (var now = 0.0; now < 3000; now += fps) {
        e.tick(now);
      }
      expect(e.d, closeTo(2, 0.05), reason: 'franja de arriba = [2, 6]; el niño en 0');
      final z = e.targetZone(3000)!;
      expect([z.y0, z.y1], [2, 6]);
      expect([z.x0, z.x1], [-6, 6], reason: 'en «Juntos» el lado no se mide');
    });
  });

  group('trazo', () {
    test('mismo vaivén con distinta amplitud y centro: cuenta', () {
      final e = play(1, SyncParams()..matchMode = 2, wave(5), wave(1.5, center: -3));
      expect(e.levelsDone, [1]);
    });

    test('vaivén al revés (uno sube, el otro baja): no cuenta', () {
      final e = play(1, SyncParams()..matchMode = 2, wave(5), wave(5, phase: math.pi));
      expect(e.levelsDone, isEmpty);
    });

    test('los dos quietos en la misma esquina: no hay trazo', () {
      final e = play(1, SyncParams()..matchMode = 2, (s) => (x: 6.0, y: 6.0), (s) => (x: 6.0, y: 6.0), seconds: 10);
      expect(e.traceSimilarity(Relation.together, 10000), 0);
      expect(e.inSync, isFalse);
    });

    test('«Sube y baja» con trazo: alturas opuestas cuentan', () {
      final e = play(4, SyncParams()..matchMode = 2, wave(4), wave(2, phase: math.pi));
      expect(e.levelsDone, [4]);
    });

    test('zonas y trazo: hacen falta los dos', () {
      final p = SyncParams()..matchMode = 3;
      // Mismo trazo pero el niño muy abajo (otra franja).
      expect(play(1, p.copy(), wave(1.5, center: 4), wave(1.5, center: -4)).levelsDone, isEmpty);
      // Mismo trazo y misma franja.
      expect(play(1, p.copy(), wave(1.5, center: 4), wave(1.5, center: 3.8)).levelsDone, [1]);
    });
  });

  group('valores de fábrica (zonas y trazo)', () {
    test('niveles 1 a 4 con el gesto de cada relación', () {
      expect(play(1, SyncParams(), wave(4), wave(2.5, center: -1)).levelsDone, [1], reason: 'Juntos');
      Pos sway(double s) => (x: 4 * math.sin(2 * math.pi * 0.4 * s), y: 3 * math.sin(2 * math.pi * 0.4 * s));
      expect(play(2, SyncParams(), sway, (s) => (x: -sway(s).x, y: sway(s).y)).levelsDone, [2], reason: 'Espejo');
      expect(play(3, SyncParams(), sway, sway).levelsDone, [3], reason: 'Iguales');
      expect(play(4, SyncParams(), wave(4), wave(4, phase: math.pi)).levelsDone, [4], reason: 'Sube y baja');
    });

    test('nivel 5 «Mismo pulso» no cambia: mismo ritmo cuenta', () {
      Pos Function(double) beat(double amp, double phase) => (s) => (x: 0.0, y: amp * math.sin(2 * math.pi * 0.8 * s + phase));
      expect(play(5, SyncParams(), beat(4, 0), beat(2, 1)).levelsDone, [5]);
    });

    test('el gesto equivocado no cuenta', () {
      expect(play(1, SyncParams(), wave(4), wave(4, phase: math.pi)).levelsDone, isEmpty, reason: 'Juntos al revés');
      expect(play(4, SyncParams(), wave(4), wave(4)).levelsDone, isEmpty, reason: 'Sube y baja copiando');
    });
  });

  group('solo el lado en «Espejo» e «Iguales»', () {
    Pos side(double s) => (x: 4 * math.sin(2 * math.pi * 0.4 * s), y: 0);

    test('«Espejo»: lados opuestos con alturas distintas cuentan', () {
      final p = SyncParams()..sideOnly = 1;
      final e = play(2, p, (s) => (x: side(s).x, y: 3), (s) => (x: -side(s).x, y: -3));
      expect(e.levelsDone, [2]);
      expect(play(2, SyncParams()..matchMode = 0, (s) => (x: side(s).x, y: 3), (s) => (x: -side(s).x, y: -3)).levelsDone, isEmpty);
    });

    test('«Iguales»: mismo lado cuenta; lado contrario, no', () {
      final p = SyncParams()..sideOnly = 1;
      expect(play(3, p.copy(), side, (s) => (x: side(s).x, y: 2)).levelsDone, [3]);
      expect(play(3, p.copy(), side, (s) => (x: -side(s).x, y: 2)).levelsDone, isEmpty);
    });
  });

  test('pegados al borde no cuenta (el atajo de las esquinas)', () {
    // Los dos empujan más allá del borde de arriba y se mueven de lado (activos).
    Pos pinned(double s) => (x: 3 * math.sin(2 * math.pi * 0.5 * s), y: 9);
    final punto = SyncParams()..matchMode = 0;
    expect(play(1, punto.copy(), pinned, pinned).levelsDone, [1], reason: 'midiendo por punto, el atajo funciona');
    expect(play(1, punto.copy()..edgeNoSync = 1, pinned, pinned).levelsDone, isEmpty);
    expect(play(1, SyncParams(), pinned, pinned).levelsDone, isEmpty, reason: 'con trazo, quietos en el borde no hay trazo');
  });

  test('campanita al cambiar de guía, solo si está encendida', () {
    final con = <SyncEvent>[], sin = <SyncEvent>[];
    play(1, SyncParams()..guideChime = 1, wave(4), wave(4), events: con);
    play(1, SyncParams(), wave(4), wave(4), events: sin);
    expect(con.whereType<GuideChangedEvent>(), isNotEmpty);
    expect(con.whereType<ChimeEvent>().length, con.whereType<GuideChangedEvent>().length);
    expect(sin.whereType<ChimeEvent>(), isEmpty);
  });

  group('sonidos que ubican', () {
    SyncEngine at(SyncParams p, Pos a, Pos c) {
      final e = SyncEngine(params: p);
      e.start(mode: PlayMode.levels, now: 0);
      e.drive = (now) {
        // Un poco de movimiento para estar activos.
        final w = 0.8 * math.sin(now / 80);
        feedPlane(e.adult, a.x + w, a.y, e);
        feedPlane(e.child, c.x + w, c.y, e);
      };
      return e;
    }

    List<NoteCmd> childNotes(SyncEngine e) {
      final l = AudioLayers();
      final out = <NoteCmd>[];
      for (var now = 0.0; now < 3000; now += fps) {
        e.tick(now);
        out.addAll(l.update(now, fps / 1000, e).where((n) => !n.passing));
      }
      return out;
    }

    test('escala común: a la misma altura, la misma nota una octava arriba', () {
      final e = at(SyncParams()..sharedScale = 1, (x: 0, y: 3), (x: 0, y: 3));
      final notes = childNotes(e);
      expect(notes, isNotEmpty);
      final ai = ((e.adult.pos.y + 6) / 12 * (adultScale.length - 1)).round();
      expect(notes.last.midi, adultScale[ai] + 12);
      expect(sharedChildScale, [for (final m in adultScale) m + 12]);
    });

    test('el lado cambia el timbre del niño', () {
      final der = childNotes(at(SyncParams()..sideTimbre = 1, (x: 0, y: 0), (x: 4, y: 0)));
      final izq = childNotes(at(SyncParams()..sideTimbre = 1, (x: 0, y: 0), (x: -4, y: 0)));
      expect(der.map((n) => n.family).toSet(), {NoteFamily.glock});
      expect(izq.map((n) => n.family).toSet(), {NoteFamily.marimba});
      final normal = childNotes(at(SyncParams(), (x: 0, y: 0), (x: 4, y: 0)));
      expect(normal.map((n) => n.family).toSet(), {NoteFamily.marimba});
    });

    test('quinta gradual: sube entre 2·tol y tol', () {
      expect(AudioLayers.fifthLevel(3, 1.2, 1, ramp: true), 0);
      expect(AudioLayers.fifthLevel(1.8, 1.2, 1, ramp: true), closeTo(0.5, 1e-9));
      expect(AudioLayers.fifthLevel(1, 1.2, 0, ramp: true), 1);
      expect(AudioLayers.fifthLevel(1.8, 1.2, 1, ramp: false), 0, reason: 'prototipo: solo afinado');
      expect(AudioLayers.fifthLevel(1, 1.2, 0, ramp: false), 1);
    });
  });
}
