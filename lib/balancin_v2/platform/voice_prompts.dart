import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Voz de consignas (plan v2 §4.6): marcador con el texto a voz del teléfono,
/// como `say()` del prototipo, hasta tener audios grabados.
///
/// Apagada por defecto (pedido del usuario del 18-10-2026: tapa los sonidos del
/// juego); se enciende desde el banco o la prueba de audio. Cada frase corta la anterior. Velocidad 0,95 y tono 1,05 del prototipo
/// (en Android la velocidad normal de flutter_tts es 0,5).
class VoicePrompts {
  VoicePrompts({this.enabled = false});

  bool enabled;
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Idioma que quedó en uso (para mostrarlo en el banco).
  String? language;

  static const List<String> preferredLanguages = ['es-CL', 'es-US', 'es-419', 'es-ES', 'es'];

  Future<void> init() async {
    if (_ready) return;
    try {
      for (final lang in preferredLanguages) {
        final ok = await _tts.isLanguageAvailable(lang);
        if (ok == true || ok == 1) {
          await _tts.setLanguage(lang);
          language = lang;
          break;
        }
      }
      await _tts.setSpeechRate(0.95 * 0.5);
      await _tts.setPitch(1.05);
      await _tts.setVolume(1);
      _ready = true;
    } catch (e) {
      debugPrint('[VoicePrompts] texto a voz no disponible: $e');
    }
  }

  Future<void> say(String text) async {
    if (!enabled || !_ready) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[VoicePrompts] no se pudo hablar: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
