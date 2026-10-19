import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/params.dart';

/// Preferencias del banco de prueba v2: parámetros de ajuste y voz.
abstract final class BenchStore {
  static const String _paramsKey = 'balancin_v2_params';
  static const String _voiceKey = 'balancin_v2_voz_on'; // clave nueva: por defecto apagada

  static Future<SyncParams> loadParams() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_paramsKey);
      if (raw == null) return SyncParams();
      return SyncParams.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return SyncParams();
    }
  }

  static Future<void> saveParams(SyncParams params) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_paramsKey, jsonEncode(params.toJson()));
    } catch (_) {}
  }

  static const String _calKey = 'balancin_v2_calibrar_al_empezar';

  /// Calibrar el rango de cada persona (6 s) al empezar cada sesión del banco. Por defecto sí.
  static Future<bool> loadCalOnStart() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_calKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveCalOnStart(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_calKey, on);
    } catch (_) {}
  }

  static Future<bool> loadVoice() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_voiceKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveVoice(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_voiceKey, on);
    } catch (_) {}
  }
}
