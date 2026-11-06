import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/stick_state.dart';

/// Última calibración de cada stick, por su MAC (plan v2 §18). El juego vuelve a
/// medir el rango al empezar; esta se usa si en esos 6 s no hubo movimiento suficiente.
abstract final class CalStore {
  static String _key(String mac) => 'balancin_v2_cal_${mac.toUpperCase()}';

  static Future<StickCal?> load(String? mac) async {
    if (mac == null || mac.isEmpty) return null;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(mac));
      if (raw == null) return null;
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      double v(String k) => (j[k] as num).toDouble();
      final hrX = v('hrX'), hrY = v('hrY');
      if (!(hrX > 0) || !(hrY > 0)) return null;
      return StickCal(cx: v('cx'), cy: v('cy'), hr: 0, hrX: hrX, hrY: hrY);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? mac, StickCal cal) async {
    if (mac == null || mac.isEmpty) return;
    try {
      await (await SharedPreferences.getInstance()).setString(_key(mac), jsonEncode(cal.toJson()));
    } catch (_) {}
  }
}
