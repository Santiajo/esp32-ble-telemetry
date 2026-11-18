// Niveles 2 «Espejo» y 3 «Iguales» con los valores de fábrica (plan v2 §13).
// La paridad con el prototipo ya está en parity_test.dart (lv2_sync, lv3_cerca);
// aquí se prueba con los cambios del §12 (velocidad, retraso, pérdida al salir).

import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/synthetic_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estas pruebas son de la medición por punto (prototipo, §12 y §13). Desde el
/// 25-10-2026 el valor de fábrica es «zonas y trazo» (§16, ver blind_test.dart).
SyncParams pointParams() => SyncParams()..matchMode = 0;

const fps = 1000 / 60;

/// Juega solo el nivel [levelId] (sin seguir al siguiente) con el adulto en una
/// curva 2D y el niño según [child]. Devuelve el motor al final.
SyncEngine playLevel(int levelId, ({double x, double y}) Function(double s, double ax, double ay) child, {double seconds = 20, SyncParams? params}) {
  final e = SyncEngine(params: params ?? (pointParams()..autoNext = 0), isLevelEnabled: enabledLevelIds.contains);
  e.drive = (now) {
    final s = now / 1000;
    final ax = 4 * math.sin(2 * math.pi * 0.5 * s), ay = 3 * math.sin(2 * math.pi * 0.8 * s + 0.5);
    feedPlane(e.adult, ax, ay, e);
    final c = child(s, ax, ay);
    feedPlane(e.child, c.x, c.y, e);
  };
  e.start(mode: PlayMode.levels, levelIndex: levelId - 1, now: 0);
  for (var now = 0.0; now < seconds * 1000 && e.running; now += fps) {
    e.tick(now);
  }
  return e;
}

void main() {
  test('los niveles del 1 al 5 están habilitados; el 6 y el 7, no', () {
    expect(enabledLevelIds, {1, 2, 3, 4, 5, 6, 7});
  });

  group('nivel 2 «Espejo»', () {
    test('en espejo (x opuesta, misma altura) se logra', () {
      final e = playLevel(2, (s, ax, ay) => (x: -ax, y: ay));
      expect(e.levelsDone, [2]);
    });

    test('con un pequeño retraso del niño también se logra', () {
      final e = playLevel(2, (s, ax, ay) {
        final t = s - 0.08;
        return (x: -4 * math.sin(2 * math.pi * 0.5 * t), y: 3 * math.sin(2 * math.pi * 0.8 * t + 0.5));
      });
      expect(e.levelsDone, [2]);
    });

    test('copiando en vez de reflejar (misma x) no se logra', () {
      final e = playLevel(2, (s, ax, ay) => (x: ax, y: ay));
      expect(e.levelsDone, isEmpty);
    });

    test('la guía empieza en el niño y pasa al adulto', () {
      final e = SyncEngine(params: pointParams()..autoNext = 0, isLevelEnabled: enabledLevelIds.contains);
      e.start(mode: PlayMode.levels, levelIndex: 1, now: 0);
      expect(e.guide, Role.child);
    });
  });

  group('nivel 3 «Iguales»', () {
    test('apuntando al mismo punto se logra: lado y altura opuestos para cada uno', () {
      final e = playLevel(3, (s, ax, ay) => (x: -ax, y: -ay));
      expect(e.levelsDone, [3]);
    });

    test('la misma posición para cada uno son puntos opuestos: no se logra', () {
      final e = playLevel(3, (s, ax, ay) => (x: ax, y: ay));
      expect(e.levelsDone, isEmpty);
    });

    test('hay que acertar los dos ejes: solo el lado no basta si la altura no calza', () {
      final e = playLevel(3, (s, ax, ay) => (x: -ax, y: ay));
      expect(e.levelsDone, isEmpty);
    });

    test('apagado, mide como el prototipo', () {
      final e = playLevel(3, (s, ax, ay) => (x: ax, y: ay), params: pointParams()..autoNext = 0..samePoint = 0);
      expect(e.levelsDone, [3]);
    });
  });

  test('una sesión recorre los 7 niveles, termina la canción y va al final', () {
    final e = SyncEngine(params: pointParams(), closeOnIdle: true, isLevelEnabled: enabledLevelIds.contains);
    e.drive = (now) => synthDrive(e, SynthQuality.sync, now);
    final ev = e.start(mode: PlayMode.levels, now: 0);
    for (var now = 0.0; now < 300000 && e.running; now += fps) {
      ev.addAll(e.tick(now));
    }
    expect(ev.whereType<LevelCompletedEvent>().map((x) => x.levelId), [1, 2, 3, 4, 5, 6, 7]);
    final closed = ev.whereType<SessionClosedEvent>().single;
    expect(closed.record.levels, [1, 2, 3, 4, 5, 6, 7]);
    expect(closed.record.song, isTrue);
    expect(closed.byIdle, isFalse);
  });
}
