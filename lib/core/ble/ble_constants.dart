import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Constantes BLE para el protocolo Nordic UART Service (NUS)
/// utilizado por las placas ESP32 telemétricas.
class BleConstants {
  /// UUID estándar del servicio Nordic UART Service (NUS)
  static final Guid serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');

  /// UUID de la característica TX (Notificaciones del ESP32 a la App)
  static final Guid txCharUuid = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  /// Prefijo general esperado en los nombres BLE de los ESP32
  static const String prefixName = 'ESP32';

  /// Nombre esperado para la placa A
  static const String nameDispA = 'ESP32-MPU-A';

  /// Nombre esperado para la placa B
  static const String nameDispB = 'ESP32-MPU-B';

  /// Balancín: nombres del firmware v2 (firmware/balancin_stick/main.py).
  /// Stick A = grande (adulto) · Stick B = pequeño (niño).
  static const String nameStickA = 'ESP32-BAL-A';
  static const String nameStickB = 'ESP32-BAL-B';

  /// Nombres aceptados por rol (firmware v2 y firmware antiguo).
  static const List<String> namesForA = [nameStickA, nameDispA];
  static const List<String> namesForB = [nameStickB, nameDispB];
}
