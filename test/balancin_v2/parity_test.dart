// Paridad del motor v2 con el prototipo HTML (plan v2, fase 1).
//
// Los datos de referencia salen de ejecutar el código del prototipo en Node:
//   node tool/parity/gen_golden.mjs
// Cada escenario se reproduce aquí con el mismo reloj (60 fps) y la misma
// fuente sintética, y se comparan estados, d, progreso, posiciones, eventos,
// telemetría y registro de sesión.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/synthetic_source.dart';

const _eps = 1e-6;

SynthQuality? _q(Object? s) => switch (s) {
      'sync' => SynthQuality.sync,
      'cerca' => SynthQuality.cerca,
      'lejos' => SynthQuality.lejos,
      'cycle' => SynthQuality.cycle,
      _ => null,
    };

void _close(String what, num actual, num expected) {
  final tol = _eps * (1 + expected.abs());
  if ((actual - expected).abs() > tol) {
    fail('$what: Dart $actual ≠ prototipo $expected');
  }
}

void _deepClose(String what, Object? actual, Object? expected) {
  if (expected is num && actual is num) {
    _close(what, actual, expected);
  } else if (expected is List && actual is List) {
    expect(actual.length, expected.length, reason: '$what: largo');
    for (var i = 0; i < expected.length; i++) {
      _deepClose('$what[$i]', actual[i], expected[i]);
    }
  } else if (expected is Map && actual is Map) {
    for (final k in expected.keys) {
      _deepClose('$what.$k', actual[k], expected[k]);
    }
  } else {
    expect(actual, expected, reason: what);
  }
}

Map<String, Object?> _eventJson(SyncEvent e) => switch (e) {
      SayEvent(:final text) => {'t': e.at, 'kind': 'say', 'text': text},
      PhraseEvent(:final midi) => {'t': e.at, 'kind': 'phrase', 'midi': midi},
      FlashEvent(:final long) => {'t': e.at, 'kind': 'flash', 'long': long},
      SongEvent(:final levelIds) => {'t': e.at, 'kind': 'song', 'ids': levelIds},
      _ => const {},
    };

void main() {
  final golden = jsonDecode(File('test/balancin_v2/golden/proto_scenarios.json').readAsStringSync()) as Map<String, dynamic>;
  final fpsMs = (golden['fpsMs'] as num).toDouble();
  final t0 = (golden['t0'] as num).toDouble();
  final sampleEvery = golden['sampleEvery'] as int;

  for (final sc in (golden['scenarios'] as List).cast<Map<String, dynamic>>()) {
    test('paridad · ${sc['name']}', () {
      final e = SyncEngine(closeOnIdle: sc['app'] as bool);
      SynthQuality? quality;
      e.drive = (now) {
        final q = quality;
        if (q != null) synthDrive(e, q, now);
      };
      final events = <Map<String, Object?>>[];
      Map<String, Object?>? record;
      void collect(List<SyncEvent> evs) {
        for (final ev in evs) {
          final j = _eventJson(ev);
          if (j.isNotEmpty) events.add(j);
          if (ev is SessionClosedEvent && record == null) {
            record = ev.record.toJson();
          }
        }
      }

      collect(e.start(
        mode: sc['mode'] == 'free' ? PlayMode.free : PlayMode.levels,
        levelIndex: sc['li'] as int,
        calibrate: sc['cal'] as bool,
        now: t0,
      ));
      final actions = (sc['actions'] as List).cast<Map<String, dynamic>>();
      final samples = (sc['samples'] as List).cast<Map<String, dynamic>>();
      var si = 0;
      for (var f = 0; f < (sc['frames'] as int); f++) {
        final now = t0 + f * fpsMs;
        for (final a in actions) {
          if (a['f'] == f) quality = _q(a['synth']);
        }
        collect(e.tick(now));
        if (f % sampleEvery == 0) {
          final s = samples[si++];
          final at = '${sc['name']} f=$f';
          expect(e.state.name, s['state'], reason: '$at state');
          expect(e.running, s['running'], reason: '$at running');
          _close('$at d', e.d, s['d'] as num);
          expect(e.inSync, s['inSync'], reason: '$at inSync');
          _close('$at prog', e.prog, s['prog'] as num);
          expect(e.guide.name, s['guide'], reason: '$at guide');
          expect(e.levelIndex, s['li'], reason: '$at li');
          expect(e.part, s['part'], reason: '$at part');
          _deepClose('$at adulto', [e.adult.pos.x, e.adult.pos.y, e.adult.speed], s['a']);
          _deepClose('$at niño', [e.child.pos.x, e.child.pos.y, e.child.speed], s['c']);
          expect(e.adult.active(now), s['aAct'], reason: '$at adulto activo');
          expect(e.child.active(now), s['cAct'], reason: '$at niño activo');
        }
      }
      expect(si, samples.length);
      _deepClose('${sc['name']} eventos', events, sc['events']);

      final rep = e.report();
      final want = sc['report'] as Map<String, dynamic>;
      for (final k in ['modo', 'duracion_s', 'en_sincronia_s', 'niveles_logrados', 'cancion_completa', 'niveles']) {
        _deepClose('${sc['name']} report.$k', rep[k], want[k]);
      }

      final wantRec = sc['record'] as Map<String, dynamic>?;
      if (wantRec == null) {
        expect(record, isNull, reason: '${sc['name']}: no debía cerrarse');
      } else {
        expect(record, isNotNull, reason: '${sc['name']}: debía cerrarse');
        final r = record!;
        for (final k in ['mode', 'levels', 'dur', 'sync', 'song', 'lead']) {
          _deepClose('${sc['name']} record.$k', r[k], wantRec[k]);
        }
        final traj = r['traj'] as List;
        expect(traj.length, wantRec['trajLen'], reason: '${sc['name']} record.traj');
        _deepClose('${sc['name']} record.traj', traj.take(40).toList(), wantRec['traj']);
      }
    });
  }
}
