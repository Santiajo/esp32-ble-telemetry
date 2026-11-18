import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:esp32_ble_telemetry/epu_app/epu_root.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Como el prototipo de Epu: solo vertical y barras del sistema transparentes.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const TelemetryStationApp());
}

/// Aplicación Epu.
///
/// Abre el flujo Eco de Joaquín (`lib/epu`) sobre los sticks reales
/// (`lib/epu_app`). El `MaterialApp` de afuera sostiene las herramientas del
/// equipo (banco de pruebas, que se abre manteniendo pulsado el logo del Home);
/// la app v2 «Balancín» sigue en `lib/balancin_v2` y no se borra.
class TelemetryStationApp extends StatelessWidget {
  const TelemetryStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Epu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const EpuRoot(),
    );
  }
}
