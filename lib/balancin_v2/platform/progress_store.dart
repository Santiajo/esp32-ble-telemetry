import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/telemetry.dart';

/// Lo que la app recuerda entre sesiones (plan v2 §4.8; `store` del prototipo):
/// los niveles logrados (la canción), las últimas 20 sesiones y si ya se hizo
/// la preparación. Todo queda solo en el teléfono.
abstract final class ProgressStore {
  /// Mismas claves que el prototipo (y la de preparación compartida con v1).
  static const String progressKey = 'balancin_progress';
  static const String sessionsKey = 'balancin-sesiones-v2';
  static const String onboardedKey = 'balancin_onboarding_done';
  static const int maxSessions = 20;

  static Future<SharedPreferences?> _p() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> progress() async {
    final p = await _p();
    try {
      final raw = p?.getString(progressKey);
      if (raw == null) return [];
      return [for (final v in jsonDecode(raw) as List) (v as num).toInt()];
    } catch (_) {
      return [];
    }
  }

  static Future<void> addProgress(int levelId) async {
    final p = await _p();
    final got = await progress();
    if (got.contains(levelId)) return;
    got.add(levelId);
    await p?.setString(progressKey, jsonEncode(got));
  }

  static Future<List<SessionRecord>> sessions() async {
    final p = await _p();
    try {
      final raw = p?.getString(sessionsKey);
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List) SessionRecord.fromJson((j as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Guarda la sesión al principio de la lista (como `unshift` del prototipo), si duró más de 2 s.
  static Future<void> addSession(SessionRecord r) async {
    if (r.dur <= 2) return;
    final p = await _p();
    final list = [r, ...await sessions()].take(maxSessions).toList();
    await p?.setString(sessionsKey, jsonEncode([for (final s in list) s.toJson()]));
  }

  static Future<bool> onboarded() async => (await _p())?.getBool(onboardedKey) ?? false;

  static Future<void> setOnboarded() async => (await _p())?.setBool(onboardedKey, true);
}
