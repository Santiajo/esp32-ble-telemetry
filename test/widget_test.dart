import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esp32_ble_telemetry/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Smoke test de TelemetryStationApp y elementos del Dashboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TelemetryStationApp());
    await tester.pump();

    // Verificar AppBar
    expect(find.text('Estación Telemétrica · ESP32 BLE'), findsOneWidget);

    // Verificar presencia de los chips de ESP A y ESP B
    expect(find.textContaining('ESP A'), findsWidgets);
    expect(find.textContaining('ESP B'), findsWidgets);

    // Verificar secciones clave
    expect(find.text('Plano Cartesiano 2D (Posición X / Y)'), findsOneWidget);
    expect(find.text('Análisis Telemétrico en Tiempo Real'), findsOneWidget);
  });
}
