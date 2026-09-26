// Tests del motor del Balancín contra los criterios de aceptación de la
// especificación (§11) usando los simuladores de movimiento del prototipo.
// Tiempo simulado a 60 Hz; no requieren dispositivo.

import 'package:esp32_ble_telemetry/balancin/core/constants.dart';
import 'package:esp32_ble_telemetry/balancin/core/engine/balancin_engine.dart';
import 'package:esp32_ble_telemetry/balancin/core/engine/sound_command.dart';
import 'package:esp32_ble_telemetry/balancin/core/gesture/synthetic_motion.dart';
import 'package:esp32_ble_telemetry/balancin/core/gesture/touch_gesture_reader.dart';
import 'package:esp32_ble_telemetry/balancin/core/scale.dart';
import 'package:flutter_test/flutter_test.dart';

const double frameMs = 1000 / 60;
const double panelW = 400;
const double panelH = 600;

class Rec {
  Rec(this.t, this.cmd, this.state);
  final double t;
  final SoundCommand cmd;
  final BalancinState state;
}

class Sim {
  Sim() {
    engine = BalancinEngine(adult: adult, child: child);
    engine.start(0, wallClock: DateTime.utc(2026, 9, 26));
  }

  final adult = TouchGestureReader();
  final child = TouchGestureReader();
  late final BalancinEngine engine;
  final log = <Rec>[];

  void moveAdult(double now, {double speed = 1}) {
    final p = SyntheticMotion.adult(now / 1000, speed: speed);
    adult.feedFraction(p.fx, p.fy, now, panelW, panelH);
  }

  void moveChild(double now) {
    final p = SyntheticMotion.childDemo(now / 1000);
    child.feedFraction(p.fx, p.fy, now, panelW, panelH);
  }

  void shakeBoth(double now) {
    final p = SyntheticMotion.shake(now / 1000);
    adult.feedFraction(p.fx, p.fy, now, panelW, panelH);
    child.feedFraction(p.fx, p.fy, now, panelW, panelH);
  }

  /// Corre el motor de [from] a [to] ms llamando a [drive] antes de cada tick.
  /// [onTick] se llama después de cada tick (para inspeccionar el estado).
  double run(double from, double to, void Function(double now) drive,
      {void Function(double now)? onTick}) {
    var now = from;
    while (now <= to) {
      drive(now);
      for (final c in engine.tick(now)) {
        log.add(Rec(now, c, engine.state));
      }
      onTick?.call(now);
      if (!engine.running) break;
      now += frameMs;
    }
    return now;
  }

  void both(double now) {
    moveAdult(now);
    moveChild(now);
  }

  Iterable<NoteOn> notes({double after = -1, double before = double.infinity}) => log
      .where((r) => r.t > after && r.t < before)
      .map((r) => r.cmd)
      .whereType<NoteOn>();

  Iterable<T> cmds<T extends SoundCommand>() => log.map((r) => r.cmd).whereType<T>();
}

void main() {
  group('Criterios de aceptación (banco, simulados)', () {
    test('1 · Stick B solo: silencio absoluto, cualquiera sea el movimiento', () {
      final s = Sim();
      s.run(frameMs, 10000, s.moveChild);
      expect(s.engine.state, BalancinState.silencio);
      expect(s.log, isEmpty, reason: 'no debe emitirse ningún sonido');
    });

    test('2 · Stick A solo desde REPOSO: exactamente una resonancia y luego nada', () {
      final s = Sim();
      s.run(frameMs, 10000, s.moveAdult);
      expect(s.engine.state, BalancinState.espera);
      expect(s.cmds<OpeningSound>().length, 1);
      expect(s.cmds<NoteOn>(), isEmpty);
      expect(s.log.length, 1);
    });

    test('3 y 4 · Ambos: respuesta continua, notas dentro del campo y pentatónicas', () {
      final s = Sim();
      s.run(frameMs, 20000, s.both);
      expect(s.engine.state, BalancinState.activo);
      final notes = s.notes().toList();
      expect(notes.length, greaterThan(50));
      for (final n in notes) {
        expect(n.index, inInclusiveRange(n.fieldLo, n.fieldLo + n.fieldCount - 1));
        expect(n.midi, kNotes[n.index]);
        expect(kPentatonicPitchClasses, contains(n.midi % 12));
      }
      // Respuesta continua: no hay huecos de más de 1 s entre notas tras el arranque.
      final times = s.log.where((r) => r.cmd is NoteOn).map((r) => r.t).toList();
      for (var i = 1; i < times.length; i++) {
        if (times[i] > 2000) expect(times[i] - times[i - 1], lessThan(1000));
      }
    });

    test('5 y 6 · Latencia del niño: resonancia, sin notas y reanudación sin corte', () {
      final s = Sim();
      s.run(frameMs, 5000, s.both);
      s.run(5000 + frameMs / 2, 9000, s.moveAdult);
      expect(s.engine.state, BalancinState.latN);
      final res = s.log.where((r) => r.cmd is FieldResonance).toList();
      expect(res.length, 1);
      // Entra en latencia ~1,5 s después de que el niño se detiene.
      expect(res.single.t, inInclusiveRange(6000, 7200));
      expect(s.notes(after: 5300, before: 9000), isEmpty);
      expect(s.cmds<FinalSound>(), isEmpty);

      s.run(9000 + frameMs / 2, 10000, s.both);
      expect(s.engine.state, BalancinState.activo);
      expect(s.engine.metrics.resum, 1);
      expect(s.engine.metrics.latDur.length, 1);
      expect(s.cmds<BusFade>(), isEmpty, reason: 'la reanudación no corta el audio');
    });

    test('5 · Latencia del adulto: el campo se estrecha gradualmente hasta agotarse', () {
      final s = Sim();
      s.run(frameMs, 5000, s.both);
      double? entry;
      var prevWidth = s.engine.field.width;
      var maxDrop = 0.0;
      s.run(5000 + frameMs / 2, 19000, s.moveChild, onTick: (now) {
        if (s.engine.state == BalancinState.latA) entry ??= now;
        final w = s.engine.field.width;
        if (prevWidth - w > maxDrop) maxDrop = prevWidth - w;
        prevWidth = w;
      });
      expect(entry, isNotNull);
      expect(s.engine.state, BalancinState.latA);
      // Nunca cae más de lo que permite 1,6 alturas/s en un tick (sin cortes abruptos).
      expect(maxDrop, lessThanOrEqualTo(BalancinConst.shrinkActive * BalancinConst.maxDtS + 1e-9));
      // Mientras queda campo el niño sigue sonando; después, silencio.
      expect(s.notes(after: entry!, before: entry! + 1500), isNotEmpty);
      expect(s.engine.field.count, 0);
      expect(s.notes(after: 18000), isEmpty);
    });

    test('Latencia de más de 20 s cierra la sesión con la resonancia final', () {
      final s = Sim();
      s.run(frameMs, 5000, s.both);
      s.run(5000 + frameMs / 2, 40000, s.moveChild);
      expect(s.engine.closed, isTrue);
      expect(s.engine.running, isFalse);
      expect(s.cmds<FinalSound>().length, 1);
      expect(s.engine.metrics.latDur.last, greaterThanOrEqualTo(20));
    });

    test('7 · Los roles siguen al lector; intercambiar sticks solo se registra', () {
      final s = Sim();
      s.run(frameMs, 3000, s.both);
      final before = s.engine.state;
      s.engine.registerSwap();
      expect(s.engine.metrics.swaps, 1);
      expect(s.engine.state, before);
    });

    test('9 · Régimen 2: el mismo patrón del niño suena más agudo si el adulto acelera', () {
      double meanMidi(double speed) {
        final s = Sim();
        s.run(frameMs, 12000, (now) {
          s.moveAdult(now, speed: speed);
          s.moveChild(now);
        });
        final ms = s.notes(after: 6000).map((n) => n.midi).toList();
        expect(ms, isNotEmpty);
        return ms.reduce((a, b) => a + b) / ms.length;
      }

      final slow = meanMidi(1);
      final fast = meanMidi(7);
      expect(fast, greaterThan(slow + 12));
    });

    test('Timbre oculto: ambos sacuden a la vez → 6 s de timbre oculto', () {
      final s = Sim();
      s.run(frameMs, 9000, (now) {
        final cyc = (now / 1000) % 16;
        if (cyc > 5 && cyc < 6.2) {
          s.shakeBoth(now);
        } else {
          s.both(now);
        }
      });
      expect(s.engine.metrics.hidden, 1);
      expect(s.notes().where((n) => n.family == TimbreFamily.oculto), isNotEmpty);
      expect(s.engine.metrics.reg[Regime.coincidencias.index], greaterThan(0));
    });

    test('Sacudida de un solo stick no abre timbre oculto', () {
      final s = Sim();
      s.run(frameMs, 9000, (now) {
        final cyc = (now / 1000) % 16;
        s.moveAdult(now);
        if (cyc > 5 && cyc < 6.2) {
          final p = SyntheticMotion.shake(now / 1000);
          s.child.feedFraction(p.fx, p.fy, now, panelW, panelH);
        } else {
          s.moveChild(now);
        }
      });
      expect(s.engine.metrics.hidden, 0);
    });
  });

  group('Pérdida de stick', () {
    test('pausa apaga el bus y reanudar vuelve a REPOSO conservando la telemetría', () {
      final s = Sim();
      s.run(frameMs, 5000, s.both);
      final events = s.engine.metrics.events;
      final pause = s.engine.pause();
      expect(pause.single, isA<BusFade>().having((f) => f.to, 'to', 0));
      expect(s.engine.tick(6000), isEmpty);

      final resume = s.engine.resume(7000);
      expect(s.engine.state, BalancinState.reposo);
      expect(resume.whereType<BusFade>().single.to, BalancinConst.busGain);
      expect(s.engine.metrics.events, events);

      final end = s.engine.end(8000);
      expect(end.single, isA<FinalSound>());
      expect(s.engine.end(9000), isEmpty, reason: 'no se cierra dos veces');
    });
  });

  group('Reporte de telemetría (criterio 11)', () {
    test('claves del prototipo, sin identificadores y porcentajes que suman 100', () {
      final s = Sim();
      s.run(frameMs, 15000, s.both);
      s.engine.end(15000);
      final r = s.engine.report();
      expect(r.keys.toSet(), {
        'proyecto',
        'nota',
        'inicio',
        'duracion_total_s',
        'juego_activo_s',
        'campo_abierto_s',
        'latencias',
        'reanudaciones',
        'eventos_nino',
        'variacion_campo_alturas',
        'timbres_ocultos',
        'intercambios_stick',
        'regimenes',
      });
      final flat = r.toString().toLowerCase();
      for (final banned in ['mac', 'device', 'dispositivo', 'email', 'nombre']) {
        expect(flat.contains(banned), isFalse, reason: 'no debe incluir "$banned"');
      }
      final regs = (r['regimenes']! as List).cast<Map<String, Object>>();
      expect(regs.length, 5);
      final pct = regs.fold<double>(0, (a, g) => a + (g['porcentaje']! as double));
      expect(pct, closeTo(100, 0.6));
      expect(r['eventos_nino'], s.engine.metrics.events);
    });
  });
}
