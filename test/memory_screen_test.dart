import 'package:esp32_ble_telemetry/balancin/core/telemetry/session_metrics.dart';
import 'package:esp32_ble_telemetry/balancin/platform/audio_engine.dart';
import 'package:esp32_ble_telemetry/balancin/platform/stick_hub.dart';
import 'package:esp32_ble_telemetry/balancin/screens/experience/memory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MemoryScreen muestra título y tarjetas del reporte de ejemplo', (tester) async {
    // Mismos valores que el primer test de session_memory_test.dart (#app=resumen)
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

    final report = buildSessionReport(m, DateTime.utc(2026, 9, 26));

    final audioEngine = AudioEngine();
    final hub = StickHub();

    await tester.pumpWidget(
      MaterialApp(
        home: MemoryScreen(
          report: report,
          audioEngine: audioEngine,
          hub: hub,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¡Sonaron juntos!'), findsOneWidget);
    expect(find.text('3 pausas, 2 regresos'), findsOneWidget);
    expect(find.text('Guardar este recuerdo'), findsOneWidget);
    expect(find.text('Detalle técnico'), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);

    hub.dispose();
  });
}
