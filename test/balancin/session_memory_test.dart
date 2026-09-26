import 'package:esp32_ble_telemetry/balancin/core/telemetry/session_metrics.dart';
import 'package:esp32_ble_telemetry/balancin/session/session_memory.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> reportFrom(SessionMetrics m) => buildSessionReport(m, DateTime.utc(2026, 9, 26));

void main() {
  test('sesión del ejemplo del prototipo (#app=resumen)', () {
    // Mismos valores que el deep link "resumen" del prototipo.
    final m = SessionMetrics()
      ..total = 762
      ..active = 551
      ..fieldOpen = 610
      ..latN = 3
      ..resum = 2
      ..events = 612
      ..variation = 37.4
      ..hidden = 1;
    m.latDur.addAll([4.2, 7.8, 20]);
    m.reg.setAll(0, [288, 71, 84, 62, 46]);

    final mem = SessionMemory.fromReport(reportFrom(m));
    expect(mem.title, '¡Sonaron juntos!');
    expect(mem.subtitle, '13 min de juego · 612 notas del niño');
    expect(mem.segments.length, 5);
    expect(mem.segments.fold<double>(0, (a, s) => a + s.fraction), closeTo(1, 1e-9));
    expect(mem.legend.first, 'En su ritmo · 52%');
    expect(mem.cards.map((c) => c.tone), ['lav', 'yel', 'oli']);
    expect(mem.cards[0].title, '3 pausas, 2 regresos');
    expect(mem.cards[1].title, '1 vez sacudieron a la vez');
    expect(mem.cards[2].title, '37 alturas recorridas');
  });

  test('sesión en silencio: título amable, cinta neutra y sin leyenda', () {
    final m = SessionMetrics()..total = 40;
    final mem = SessionMemory.fromReport(reportFrom(m));
    expect(mem.title, 'Hoy quedó en silencio');
    expect(mem.subtitle, startsWith('Faltó que los dos sticks'));
    expect(mem.segments.single.regimeIndex, -1);
    expect(mem.legend, isEmpty);
    expect(mem.cards[1].title, 'Ninguna coincidencia todavía');
  });

  test('singulares y duración en segundos si dura menos de medio minuto', () {
    final m = SessionMetrics()
      ..total = 25
      ..active = 20
      ..latN = 1
      ..resum = 1
      ..events = 30
      ..hidden = 2;
    m.reg[0] = 20;
    final mem = SessionMemory.fromReport(reportFrom(m));
    expect(mem.subtitle, '25 s de juego · 30 notas del niño');
    expect(mem.cards[0].title, '1 pausa, 1 regreso');
    expect(mem.cards[1].title, '2 veces sacudieron a la vez');
    expect(mem.segments.single.name, 'En su ritmo');
  });

  test('sin pistas del timbre oculto cuando se pide (especificación §3.4)', () {
    final m = SessionMetrics()..total = 60;
    final withHint = SessionMemory.fromReport(reportFrom(m));
    final noHint = SessionMemory.fromReport(reportFrom(m), hintHiddenTimbre: false);
    expect(withHint.cards[1].body, contains('Sacudir'));
    expect(noHint.cards[1].body.toLowerCase(), isNot(contains('sacud')));
  });
}
