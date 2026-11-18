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

  /// Epu: sticks XIAO ESP32-C3 + ICM-42688-P (firmware/epu_stick/main.py), mismo protocolo v2.
  /// Nombres definitivos (EPU-5, confirmados el 18-11): con espacios y en minúscula.
  static const String nameEpuAdult = 'Epu - adulto';
  static const String nameEpuChild = 'Epu - niño';
  static const String nameEpuChildAscii = 'Epu - nino';

  /// Nombres del primer firmware Epu (18-11), por si un stick no se actualizó.
  static const String nameEpuAdultV1 = 'Epu-Adulto';
  static const String nameEpuChildV1 = 'Epu-Niño';

  /// Nombres aceptados por rol (Epu, firmware v2 y firmware antiguo).
  static const List<String> namesForA = [nameEpuAdult, nameEpuAdultV1, nameStickA, nameDispA];
  static const List<String> namesForB = [nameEpuChild, nameEpuChildAscii, nameEpuChildV1, nameStickB, nameDispB];
}
