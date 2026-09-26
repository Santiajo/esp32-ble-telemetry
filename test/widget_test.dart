import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esp32_ble_telemetry/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Smoke test de TelemetryStationApp y HomeScreen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TelemetryStationApp());
    await tester.pump();

    // Verifica que HomeScreen se monte mostrando la vista de preparación de sonidos
    expect(find.text('Preparando sonidos…'), findsOneWidget);
  });
}
