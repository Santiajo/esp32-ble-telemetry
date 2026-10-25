import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/tilt/axis_map.dart';

/// Ejes de cada stick (plan v2 §5.3), guardados por su MAC: el asistente se hace
/// una vez por placa y vale para el banco y para el juego.
abstract final class AxisStore {
  static String _key(String mac) => 'balancin_v2_ejes_${mac.toUpperCase()}';

  static Future<AxisMap?> load(String? mac) async {
    if (mac == null || mac.isEmpty) return null;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(mac));
      if (raw == null) return null;
      return AxisMap.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? mac, AxisMap map) async {
    if (mac == null || mac.isEmpty) return;
    try {
      await (await SharedPreferences.getInstance()).setString(_key(mac), jsonEncode(map.toJson()));
    } catch (_) {}
  }

  static Future<void> clear(String? mac) async {
    if (mac == null || mac.isEmpty) return;
    try {
      await (await SharedPreferences.getInstance()).remove(_key(mac));
    } catch (_) {}
  }
}
