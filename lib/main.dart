import 'package:flutter/material.dart';
import 'package:esp32_ble_telemetry/balancin/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelemetryStationApp());
}

/// Aplicación principal de Monitoreo Telemétrico ESP32 BLE.
class TelemetryStationApp extends StatelessWidget {
  const TelemetryStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balancín',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFCC),
          secondary: Color(0xFFFF5722),
          surface: Color(0xFF141414),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111111),
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
