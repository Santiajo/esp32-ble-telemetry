import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'epu/app.dart';

/// Punto de entrada.
///
/// Para conectar los sticks reales, antes de `runApp`:
/// ```dart
/// EpuSticks.fuente = MiFuenteBluetooth();   // ver lib/epu/juego/fuente_sticks.dart
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // El prototipo es solo vertical.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Barras del sistema transparentes sobre el fondo de la app.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const EpuEcoApp());
}
