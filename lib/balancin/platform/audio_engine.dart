import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/audio/synth_renderer.dart';
import '../core/constants.dart';
import '../core/engine/sound_command.dart';

/// Motor de audio de plataforma basado en `flutter_soloud`.
///
/// Cumple con la especificación de Balancín (fase 3 del plan):
/// 1. Inicialización en baja latencia (44.1 kHz, mono, buffer configurable).
/// 2. Renderizado previo en un Isolate de las 100 notas pentatónicas y sonidos del sistema.
/// 3. Interpretación inmediata de [SoundCommand] sin bloquear el hilo de UI.
/// 4. Resonancias cacheadas dinámicamente y reproducidas con sus desfases temporales.
class AudioEngine {
  static const int defaultBufferSize = 512;
  static const int lowLatencyBufferSize = 256;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  int _renderTimeMs = 0;
  int get renderTimeMs => _renderTimeMs;

  int _loadTimeMs = 0;
  int get loadTimeMs => _loadTimeMs;

  double _currentBusGain = BalancinConst.busGain;
  double get currentBusGain => _currentBusGain;

  final Map<String, AudioSource> _sources = {};
  final List<Timer> _activeTimers = [];

  /// Número de voces actualmente reproduciéndose en el motor.
  int get voiceCount {
    if (!_isInitialized || !SoLoud.instance.isInitialized) return 0;
    try {
      return SoLoud.instance.getVoiceCount();
    } catch (_) {
      return 0;
    }
  }

  /// Inicializa el motor de audio SoLoud y precarga en memoria todos los WAVs base.
  Future<void> init({int bufferSize = defaultBufferSize}) async {
    if (_isInitialized) return;

    // 1. Renderizar en segundo plano (Isolate) los 103 sonidos base (100 notas + 3 sistema)
    final renderSw = Stopwatch()..start();
    final wavMap = await Isolate.run(_renderAllBaseWavs);
    renderSw.stop();
    _renderTimeMs = renderSw.elapsedMilliseconds;

    // 2. Inicializar SoLoud nativo
    await SoLoud.instance.init(
      sampleRate: SynthRenderer.sampleRate,
      bufferSize: bufferSize,
      channels: Channels.mono,
    );

    SoLoud.instance.setMaxActiveVoiceCount(64);
    SoLoud.instance.setGlobalVolume(BalancinConst.busGain);
    _currentBusGain = BalancinConst.busGain;

    // 3. Activar limitador global si está disponible
    try {
      SoLoud.instance.filters.limiterFilter.activate();
      SoLoud.instance.filters.limiterFilter.threshold.value = -3.0;
    } catch (_) {
      // Si la plataforma no soporta el filtro limiter, continúa sin él
    }

    // 4. Cargar en memoria todos los AudioSource
    final loadSw = Stopwatch()..start();
    for (final entry in wavMap.entries) {
      final source = await SoLoud.instance.loadMem(entry.key, entry.value);
      _sources[entry.key] = source;
    }
    loadSw.stop();
    _loadTimeMs = loadSw.elapsedMilliseconds;

    _isInitialized = true;
  }

  static Map<String, Uint8List> _renderAllBaseWavs() {
    final map = <String, Uint8List>{};
    for (final family in TimbreFamily.values) {
      for (var i = 0; i < BalancinConst.numNotes; i++) {
        final key = SynthRenderer.noteKey(family, i);
        map[key] = SynthRenderer.renderNoteWav(family, i);
      }
    }
    map['opening.wav'] = SynthRenderer.renderOpeningWav();
    map['final.wav'] = SynthRenderer.renderFinalWav();
    map['chime.wav'] = SynthRenderer.renderChimeWav();
    return map;
  }

  /// Despacha comandos de sonido emitidos por el motor determinista.
  void handle(List<SoundCommand> cmds) {
    if (!_isInitialized) return;

    for (final cmd in cmds) {
      switch (cmd) {
        case NoteOn():
          final key = SynthRenderer.noteKey(cmd.family, cmd.index);
          final source = _sources[key];
          if (source != null) {
            SoLoud.instance.play(
              source,
              volume: SynthRenderer.volumeFor(cmd.gain),
            );
          }
        case OpeningSound():
          final source = _sources['opening.wav'];
          if (source != null) {
            SoLoud.instance.play(
              source,
              volume: SynthRenderer.bakedVolume,
            );
          }
        case FinalSound():
          final source = _sources['final.wav'];
          if (source != null) {
            SoLoud.instance.play(
              source,
              volume: SynthRenderer.bakedVolume,
            );
          }
        case FieldResonance():
          _playFieldResonance(cmd);
        case BusFade():
          if (cmd.from != null) {
            _currentBusGain = cmd.from!;
            SoLoud.instance.setGlobalVolume(cmd.from!);
          }
          _currentBusGain = cmd.to;
          SoLoud.instance.fadeGlobalVolume(
            cmd.to,
            Duration(milliseconds: (cmd.seconds * 1000).round()),
          );
      }
    }
  }

  void _playFieldResonance(FieldResonance cmd) {
    final plan = fieldResonancePlan(cmd);
    for (final entry in plan) {
      _scheduleResonanceTone(entry.key, entry.tone);
    }
  }

  Future<void> _scheduleResonanceTone(String key, ToneSpec tone) async {
    AudioSource? source = _sources[key];
    if (source == null) {
      final wav = await Isolate.run(() => SynthRenderer.renderToneWav(tone));
      if (!_isInitialized) return;
      source = await SoLoud.instance.loadMem(key, wav);
      _sources[key] = source;
    }

    final delayMs = (tone.offsetS * 1000).round();
    if (delayMs <= 0) {
      if (_isInitialized) {
        SoLoud.instance.play(source, volume: SynthRenderer.bakedVolume);
      }
    } else {
      late final Timer timer;
      timer = Timer(Duration(milliseconds: delayMs), () {
        _activeTimers.remove(timer);
        if (_isInitialized) {
          SoLoud.instance.play(source!, volume: SynthRenderer.bakedVolume);
        }
      });
      _activeTimers.add(timer);
    }
  }

  /// Reproduce la campanita de vinculación.
  void playChime() {
    if (!_isInitialized) return;
    final source = _sources['chime.wav'];
    if (source != null) {
      SoLoud.instance.play(source, volume: SynthRenderer.bakedVolume);
    }
  }

  /// Libera recursos y desinicializa SoLoud.
  Future<void> dispose() async {
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
    _sources.clear();
    _isInitialized = false;

    if (SoLoud.instance.isInitialized) {
      await SoLoud.instance.deinitAsync();
    }
  }
}
