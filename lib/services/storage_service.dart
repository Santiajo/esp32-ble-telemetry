import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de almacenamiento para persistir direcciones MAC de los ESP32 emparejados.
class StorageService {
  static const String _prefijoKey = 'mac_esp_';

  /// Guarda la dirección MAC para la placa especificada ('A' o 'B').
  static Future<void> guardarMac(String etiqueta, String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefijoKey$etiqueta', mac);
  }

  /// Recupera la dirección MAC guardada para la placa especificada.
  static Future<String?> obtenerMac(String etiqueta) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefijoKey$etiqueta');
  }

  /// Elimina la dirección MAC guardada de la placa especificada.
  static Future<void> borrarMac(String etiqueta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefijoKey$etiqueta');
  }
}
