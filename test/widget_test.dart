import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esp32_ble_telemetry/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('La app abre el flujo Epu en «Inicio» la primera vez',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TelemetryStationApp());
    // EpuRoot lee si ya hicieron la preparación y abre la primera pantalla.
    for (var i = 0; i < 20 && find.text('¡Comencemos!').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('¡Comencemos!'), findsOneWidget);
    expect(find.text('Un instrumento para sonar juntos'), findsOneWidget);
  });
}
