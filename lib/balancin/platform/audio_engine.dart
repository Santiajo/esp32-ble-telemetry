import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/audio/synth_renderer.dart';
import '../core/constants.dart';
import '../core/engine/sound_command.dart';

/// Motor de audio de plataforma basado en `flutter_soloud`.
///
/// 1. Inicialización en baja latencia (44,1 kHz, mono, buffer configurable).
/// 2. Render previo en un Isolate de las 100 notas pentatónicas y los sonidos
///    del sistema (voz suave por defecto, ver [SynthVoicing]).
/// 3. Interpreta [SoundCommand] sin bloquear la UI; las notas cerca de un
///    límite de registro se mezclan con la familia vecina (cambio de timbre gradual).
/// 4. Resonancias de campo renderizadas bajo demanda y cacheadas.
/// 5. **Autorrecuperación** (28-09-2026): Android puede detener el audio nativo
///    (app en segundo plano, llamada, cambio de salida de audio). Si al volver
///    a primer plano SoLoud no está inicializado, o si una reproducción falla,
///    el motor se reinicia solo y recarga los sonidos desde la caché en memoria,
///    sin volver a sintetizarlos.
class AudioEngine with WidgetsBindingObserver {
  static const int defaultBufferSize = 512;
  static const int lowLatencyBufferSize = 256;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _recovering = false;
  int _recoveries = 0;

  /// Veces que el motor se reinició solo (diagnóstico).
  int get recoveries => _recoveries;

  int _bufferSize = defaultBufferSize;

  int _renderTimeMs = 0;
  int get renderTimeMs => _renderTimeMs;

  int _loadTimeMs = 0;
  int get loadTimeMs => _loadTimeMs;

  double _currentBusGain = BalancinConst.busGain;
  double get currentBusGain => _currentBusGain;

  /// WAV en memoria (base y resonancias) para recargar tras un reinicio.
  final Map<String, Uint8List> _wavs = {};
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

  /// Inicializa SoLoud y precarga todos los WAV base.
  Future<void> init({int bufferSize = defaultBufferSize}) async {
    if (_isInitialized) return;
    _bufferSize = bufferSize;

    final renderSw = Stopwatch()..start();
    final wavMap = await Isolate.run(_renderAllBaseWavs);
    renderSw.stop();
    _renderTimeMs = renderSw.elapsedMilliseconds;
    _wavs.addAll(wavMap);

    final loadSw = Stopwatch()..start();
    await _startSoLoud();
    loadSw.stop();
    _loadTimeMs = loadSw.elapsedMilliseconds;

    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Arranca SoLoud y carga todas las fuentes de [_wavs].
  Future<void> _startSoLoud() async {
    await SoLoud.instance.init(
      sampleRate: SynthRenderer.sampleRate,
      bufferSize: _bufferSize,
      channels: Channels.mono,
    );
    SoLoud.instance.setMaxActiveVoiceCount(64);
    SoLoud.instance.setGlobalVolume(_currentBusGain);
    try {
      SoLoud.instance.filters.limiterFilter.activate();
      SoLoud.instance.filters.limiterFilter.threshold.value = -3.0;
    } catch (_) {
      // Si la plataforma no soporta el limitador, se continúa sin él.
    }
    _sources.clear();
    for (final entry in _wavs.entries) {
      _sources[entry.key] = await SoLoud.instance.loadMem(entry.key, entry.value);
    }
  }

  static Map<String, Uint8List> _renderAllBaseWavs() {
    final map = <String, Uint8List>{};
    for (final family in TimbreFamily.values) {
      for (var i = 0; i < BalancinConst.numNotes; i++) {
        map[SynthRenderer.noteKey(family, i)] = SynthRenderer.renderNoteWav(family, i);
      }
    }
    map['opening.wav'] = SynthRenderer.renderOpeningWav();
    map['final.wav'] = SynthRenderer.renderFinalWav();
    map['chime.wav'] = SynthRenderer.renderChimeWav();
    return map;
  }

  // ---------------------------------------------------------------------------
  // Autorrecuperación
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(ensureAlive());
  }

  /// Verifica que SoLoud siga activo; si no, lo reinicia. Llamar también desde
  /// la UI antes de una sesión si se quiere asegurar el audio.
  Future<void> ensureAlive() async {
    if (!_isInitialized || _recovering) return;
    if (!SoLoud.instance.isInitialized) {
      await _recover();
    } else {
      try {
        SoLoud.instance.setGlobalVolume(_currentBusGain);
      } catch (_) {
        await _recover();
      }
    }
  }

  Future<void> _recover() async {
    if (_recovering || !_isInitialized) return;
    _recovering = true;
    try {
      for (final t in _activeTimers) {
        t.cancel();
      }
      _activeTimers.clear();
      try {
        if (SoLoud.instance.isInitialized) await SoLoud.instance.deinitAsync();
      } catch (_) {}
      await _startSoLoud();
      _recoveries++;
      debugPrint('[AudioEngine] audio reiniciado (recuperación #$_recoveries)');
    } catch (e) {
      debugPrint('[AudioEngine] no se pudo reiniciar el audio: $e');
    } finally {
      _recovering = false;
    }
  }

  /// Reproduce con protección: si SoLoud falla, agenda una recuperación.
  void _safePlay(AudioSource? source, double volume) {
    if (source == null || _recovering) return;
    try {
      if (!SoLoud.instance.isInitialized) {
        unawaited(_recover());
        return;
      }
      SoLoud.instance.play(source, volume: volume);
    } catch (e) {
      debugPrint('[AudioEngine] fallo al reproducir: $e');
      unawaited(_recover());
    }
  }

  // ---------------------------------------------------------------------------
  // Comandos
  // ---------------------------------------------------------------------------

  /// Despacha comandos de sonido emitidos por el motor determinista.
  void handle(List<SoundCommand> cmds) {
    if (!_isInitialized) return;

    for (final cmd in cmds) {
      switch (cmd) {
        case NoteOn():
          final volume = SynthRenderer.volumeFor(cmd.gain);
          final blend = cmd.blendFamily;
          if (blend != null && cmd.blendAmount > 0.02) {
            // Mezcla de igual potencia entre la familia principal y la vecina.
            final a = cmd.blendAmount.clamp(0.0, 0.5).toDouble();
            _safePlay(_sources[SynthRenderer.noteKey(cmd.family, cmd.index)], volume * math.sqrt(1 - a));
            _safePlay(_sources[SynthRenderer.noteKey(blend, cmd.index)], volume * math.sqrt(a));
          } else {
            _safePlay(_sources[SynthRenderer.noteKey(cmd.family, cmd.index)], volume);
          }
        case OpeningSound():
          _safePlay(_sources['opening.wav'], SynthRenderer.bakedVolume);
        case FinalSound():
          _safePlay(_sources['final.wav'], SynthRenderer.bakedVolume);
        case FieldResonance():
          for (final entry in fieldResonancePlan(cmd)) {
            unawaited(_scheduleResonanceTone(entry.key, entry.tone));
          }
        case BusFade():
          _currentBusGain = cmd.to;
          try {
            if (cmd.from != null) SoLoud.instance.setGlobalVolume(cmd.from!);
            SoLoud.instance.fadeGlobalVolume(
              cmd.to,
              Duration(milliseconds: (cmd.seconds * 1000).round()),
            );
          } catch (e) {
            debugPrint('[AudioEngine] fallo en el fade del bus: $e');
            unawaited(_recover());
          }
      }
    }
  }

  Future<void> _scheduleResonanceTone(String key, ToneSpec tone) async {
    try {
      var source = _sources[key];
      if (source == null) {
        var wav = _wavs[key];
        if (wav == null) {
          wav = await Isolate.run<Uint8List>(() => SynthRenderer.renderToneWav(tone));
          _wavs[key] = wav;
        }
        if (!_isInitialized || _recovering) return;
        source = await SoLoud.instance.loadMem(key, wav);
        _sources[key] = source;
      }
      final delayMs = (tone.offsetS * 1000).round();
      if (delayMs <= 0) {
        _safePlay(source, SynthRenderer.bakedVolume);
      } else {
        late final Timer timer;
        timer = Timer(Duration(milliseconds: delayMs), () {
          _activeTimers.remove(timer);
          if (_isInitialized) _safePlay(_sources[key], SynthRenderer.bakedVolume);
        });
        _activeTimers.add(timer);
      }
    } catch (e) {
      debugPrint('[AudioEngine] fallo en resonancia de campo: $e');
    }
  }

  /// Reproduce la campanita de vinculación.
  void playChime() {
    if (!_isInitialized) return;
    _safePlay(_sources['chime.wav'], SynthRenderer.bakedVolume);
  }

  /// Libera recursos y desinicializa SoLoud.
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
    _sources.clear();
    _wavs.clear();
    _isInitialized = false;
    if (SoLoud.instance.isInitialized) {
      await SoLoud.instance.deinitAsync();
    }
  }
}
