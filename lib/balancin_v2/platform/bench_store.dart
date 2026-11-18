import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/params.dart';

/// Preferencias del banco de prueba v2: parámetros de ajuste y voz.
abstract final class BenchStore {
  static const String _paramsKey = 'balancin_v2_params';
  static const String _voiceKey = 'balancin_v2_voz_on'; // clave nueva: por defecto apagada
  static const String _versionKey = 'balancin_v2_params_version';

  /// Versión de los valores de fábrica. 3 = solo tercios y trazo (§20): los valores
  /// guardados antes pasan a medir así una vez; después se respeta lo elegido en Ajuste.
  static const int paramsVersion = 3;

  static Future<SyncParams> loadParams() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_paramsKey);
      if (raw == null) return SyncParams();
      final params = SyncParams.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      if ((p.getInt(_versionKey) ?? 1) < paramsVersion) {
        final factory = SyncParams();
        params
          ..matchMode = factory.matchMode
          ..zoneCount = factory.zoneCount
          ..zoneStrict = factory.zoneStrict;
        await saveParams(params);
      }
      return params;
    } catch (_) {
      return SyncParams();
    }
  }

  static Future<void> saveParams(SyncParams params) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_paramsKey, jsonEncode(params.toJson()));
      await p.setInt(_versionKey, paramsVersion);
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
