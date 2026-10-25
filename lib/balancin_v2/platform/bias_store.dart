import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/tilt/vec3.dart';

/// Error del giroscopio en reposo (bias) y |a| de reposo de cada stick, por su
/// MAC. Cada partida crea un `TiltReader` nuevo: con esto parte ya calibrado en
/// vez de leer solo el acelerómetro (que tirita) hasta la primera quietud.
abstract final class BiasStore {
  static String _key(String mac) => 'balancin_v2_bias_${mac.toUpperCase()}';

  static Future<({V3 bias, double restMag})?> load(String? mac) async {
    if (mac == null || mac.isEmpty) return null;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(mac));
      if (raw == null) return null;
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      final bias = V3.fromJson(j['bias']);
      final mag = (j['restMag'] as num).toDouble();
      if (!bias.x.isFinite || !bias.y.isFinite || !bias.z.isFinite || !(mag > 0.5 && mag < 1.5)) return null;
      return (bias: bias, restMag: mag);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? mac, V3 bias, double restMag) async {
    if (mac == null || mac.isEmpty) return;
    try {
      await (await SharedPreferences.getInstance())
          .setString(_key(mac), jsonEncode({'bias': bias.toJson(), 'restMag': restMag}));
    } catch (_) {}
  }
}
