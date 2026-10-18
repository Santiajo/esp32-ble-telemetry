import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/params.dart';

/// Preferencias del banco de prueba v2: parámetros de ajuste y voz.
abstract final class BenchStore {
  static const String _paramsKey = 'balancin_v2_params';
  static const String _voiceKey = 'balancin_v2_voz';

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

  static Future<bool> loadVoice() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_voiceKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveVoice(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_voiceKey, on);
    } catch (_) {}
  }
}
