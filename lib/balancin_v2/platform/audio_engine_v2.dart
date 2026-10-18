import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../balancin/core/audio/synth_renderer.dart' show SynthRenderer;
import '../core/audio/layers.dart';
import '../core/audio/synth_v2.dart';
import '../core/levels.dart';
import '../core/sync_engine.dart';

/// Motor de audio de la mecánica v2 sobre `flutter_soloud` (plan v2 §4.6).
///
/// - **Voces continuas** (voz del adulto y tono de relación): 5 ondas senoidales
///   de SoLoud que suenan siempre; en cada cuadro [frame] les pasa la frecuencia
///   y la amplitud que calcula [AudioLayers] (con la EQ ya incorporada). El
///   volumen se cambia con un fundido del largo del cuadro para no producir clics.
/// - **Notas** (niño, pad, frases, canción, cierre, campanita): WAV renderizados
///   en un Isolate con [SynthV2]. Las notas sueltas se guardan a ganancia 1 y la
///   ganancia (con la atenuación por polifonía del prototipo) se aplica al tocar.
/// - **Mezcla**: volumen global 0,6 (bus 0,8 × master 0,75 del prototipo) y, como
///   filtros globales, compresor → limitador. La EQ va incorporada en cada seno
///   ([eqGain]) y la reverb en cada WAV (`applyReverb`): el `FreeverbFilter` de
///   SoLoud solo admite estéreo y en mono suena a ruido (prueba del 18-10-2026).
/// - **Diagnóstico**: cada capa se puede silenciar ([muteAdult], [muteRelation],
///   [muteChild], [mutePad]) y el compresor se puede apagar ([compressorOn]).
///
/// Convive con el `AudioEngine` de v1 durante la transición: si SoLoud ya está
/// iniciado lo reutiliza, y al [release] deja los filtros globales como estaban
/// (solo el limitador de v1 en −3 dB).
class AudioEngineV2 with WidgetsBindingObserver {
  static const double globalVolume = 0.8 * 0.75;
  static const int bufferSize = 512;

  bool muteAdult = false;
  bool muteRelation = false;
  bool muteChild = false;
  bool mutePad = false;
  bool _compressorOn = true;
  bool get compressorOn => _compressorOn;
  set compressorOn(bool on) {
    _compressorOn = on;
    try {
      final c = SoLoud.instance.filters.compressorFilter;
      if (on && !c.isActive) {
        _configureFilters();
      } else if (!on && c.isActive) {
        c.deactivate();
      }
    } catch (_) {}
  }

  bool _ready = false;
  bool get isReady => _ready;
  bool _ownsSoLoud = false;
  bool _busy = false;

  int renderTimeMs = 0;

  final Map<String, Uint8List> _wavs = {};
  final Map<String, AudioSource> _sources = {};
  final List<AudioSource> _waveSources = [];
  final List<SoundHandle> _waveHandles = [];
  final List<double> _lastAmp = [0, 0, 0, 0, 0];

  /// Fin (ms del reloj de la app) y parciales de cada nota sonando: para la polifonía.
  final List<({double end, int partials})> _sounding = [];

  static String childKey(int midi) => 'v2_child_$midi';
  static String padKey(int midi) => 'v2_pad_$midi';
  static String glockKey(int midi) => 'v2_glock_$midi';
  static String phraseKey(int levelId) => 'v2_phrase_$levelId';
  static String songKey(List<int> ids) => 'v2_song_${ids.join('-')}';
  static const String closingKey = 'v2_closing';
  static const String chimeKey = 'v2_chime';

  // ---------------------------------------------------------------------------
  // Inicio y cierre
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_ready || _busy) return;
    _busy = true;
    try {
      final sw = Stopwatch()..start();
      _wavs.addAll(await Isolate.run(_renderBase));
      renderTimeMs = sw.elapsedMilliseconds;
      await _start();
      _ready = true;
      WidgetsBinding.instance.addObserver(this);
    } finally {
      _busy = false;
    }
  }

  static Map<String, Uint8List> _renderBase() {
    final m = <String, Uint8List>{};
    for (final midi in childScale) {
      m[childKey(midi)] = SynthV2.wav([childNoteTone(midi)]);
    }
    for (final midi in allPhraseMidi()) {
      m[padKey(midi)] = SynthV2.wav([padTone(midi)]);
      m[glockKey(midi)] = SynthV2.wav([phraseNoteTone(midi)]);
    }
    for (final l in levels) {
      m[phraseKey(l.id)] = SynthV2.wav(phraseTones(l.phraseMidi));
    }
    m[closingKey] = SynthV2.wav(closingTones());
    m[chimeKey] = SynthV2.wav(chimeTones());
    return m;
  }

  Future<void> _start() async {
    final s = SoLoud.instance;
    if (!s.isInitialized) {
      await s.init(sampleRate: SynthV2.sampleRate, bufferSize: bufferSize, channels: Channels.mono);
      _ownsSoLoud = true;
    }
    s.setMaxActiveVoiceCount(64);
    s.setGlobalVolume(globalVolume);
    _configureFilters();
    _sources.clear();
    for (final e in _wavs.entries) {
      _sources[e.key] = await s.loadMem(e.key, e.value);
    }
    _waveSources.clear();
    _waveHandles.clear();
    for (var i = 0; i < 5; i++) {
      final src = await s.loadWaveform(WaveForm.sin, false, 1, 0);
      s.setWaveformFreq(src, 130);
      _waveSources.add(src);
      _waveHandles.add(s.play(src, volume: 0));
      _lastAmp[i] = 0;
    }
  }

  void _configureFilters() {
    final f = SoLoud.instance.filters;
    try {
      // El orden de activación es el orden de la cadena: compresor → limitador.
      if (f.freeverbFilter.isActive) f.freeverbFilter.deactivate(); // solo estéreo: nunca en mono
      if (f.limiterFilter.isActive) f.limiterFilter.deactivate();
      if (f.compressorFilter.isActive) f.compressorFilter.deactivate();
      if (_compressorOn) {
        f.compressorFilter.activate();
        f.compressorFilter.threshold.value = -22;
        f.compressorFilter.ratio.value = 2.5;
        f.compressorFilter.kneeWidth.value = 24;
        f.compressorFilter.attackTime.value = 12; // ms
        f.compressorFilter.releaseTime.value = 350; // ms
      }
      f.limiterFilter.activate();
      f.limiterFilter.threshold.value = -4;
      f.limiterFilter.outputCeiling.value = -1;
    } catch (e) {
      debugPrint('[AudioEngineV2] filtros no disponibles: $e');
    }
  }

  /// Deja de sonar y devuelve SoLoud como lo usa v1 (o lo cierra si lo abrió v2).
  Future<void> release() async {
    if (!_ready) return;
    _ready = false;
    WidgetsBinding.instance.removeObserver(this);
    final s = SoLoud.instance;
    if (!s.isInitialized) return;
    for (final h in _waveHandles) {
      try {
        await s.stop(h);
      } catch (_) {}
    }
    for (final src in [..._waveSources, ..._sources.values]) {
      try {
        await s.disposeSource(src);
      } catch (_) {}
    }
    _waveHandles.clear();
    _waveSources.clear();
    _sources.clear();
    _sounding.clear();
    if (_ownsSoLoud) {
      await s.deinitAsync();
      _ownsSoLoud = false;
      return;
    }
    try {
      final f = s.filters;
      if (f.compressorFilter.isActive) f.compressorFilter.deactivate();
      f.limiterFilter.threshold.value = -3;
      f.limiterFilter.outputCeiling.value = -1;
      s.setGlobalVolume(0.8);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(ensureAlive());
  }

  /// Si Android detuvo el audio nativo, lo reinicia y recarga desde la memoria.
  Future<void> ensureAlive() async {
    if (!_ready || _busy) return;
    if (SoLoud.instance.isInitialized) return;
    _busy = true;
    try {
      await _start();
      debugPrint('[AudioEngineV2] audio reiniciado');
    } catch (e) {
      debugPrint('[AudioEngineV2] no se pudo reiniciar: $e');
    } finally {
      _busy = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Cada cuadro
  // ---------------------------------------------------------------------------

  /// Avanza las curvas de [layers] y pasa las 5 voces a SoLoud.
  void frame(AudioLayers layers, double dt) {
    layers.advance(dt);
    if (!_ready || _waveHandles.length < 5) return;
    final s = SoLoud.instance;
    if (!s.isInitialized) return;
    final v = layers.voices;
    final mute = [muteAdult, muteAdult, muteRelation, muteRelation, muteRelation];
    final fade = Duration(microseconds: (dt.clamp(0.008, 0.05) * 1e6).round());
    try {
      for (var i = 0; i < 5; i++) {
        s.setWaveformFreq(_waveSources[i], v[i].hz);
        final amp = mute[i] ? 0.0 : v[i].amp;
        if ((amp - _lastAmp[i]).abs() > 1e-5) {
          s.fadeVolume(_waveHandles[i], amp, fade);
          _lastAmp[i] = amp;
        }
      }
    } catch (e) {
      debugPrint('[AudioEngineV2] fallo en las voces: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Notas y sonidos
  // ---------------------------------------------------------------------------

  int _activePartials(double now) {
    _sounding.removeWhere((n) => n.end <= now);
    return _sounding.fold(0, (a, n) => a + n.partials);
  }

  /// Nota del niño o del pad, con la polifonía del prototipo.
  void note(NoteCmd n, double now) {
    if (n.family == NoteFamily.marimba ? muteChild : mutePad) return;
    final tone = n.family == NoteFamily.marimba ? childNoteTone(n.midi) : padTone(n.midi);
    final voices = _activePartials(now);
    if (voices > maxPartialVoices) return;
    _sounding.add((end: now + (tone.endS) * 1000, partials: tone.audiblePartials));
    final key = n.family == NoteFamily.marimba ? childKey(n.midi) : padKey(n.midi);
    _play(key, SynthRenderer.volumeFor(n.gain * polyphonyGain(voices)));
  }

  void notes(List<NoteCmd> cmds, double now) {
    for (final n in cmds) {
      note(n, now);
    }
  }

  /// Efectos sonoros de los eventos del motor (frases y canción).
  void events(List<SyncEvent> evs) {
    for (final ev in evs) {
      switch (ev) {
        case PhraseEvent(:final midi, :final gain):
          if (midi.length == 1) {
            _play(glockKey(midi.single), SynthRenderer.volumeFor(gain));
          } else {
            final id = levels.firstWhere((l) => _same(l.phraseMidi, midi), orElse: () => levels.first).id;
            _play(phraseKey(id), SynthRenderer.bakedVolume);
          }
        case SongEvent(:final levelIds):
          unawaited(playSong(levelIds));
        default:
          break;
      }
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Canción con las frases de [levelIds] (se renderiza la primera vez y se guarda).
  Future<void> playSong(List<int> levelIds) async {
    if (!_ready || levelIds.isEmpty) return;
    final key = songKey(levelIds);
    if (!_sources.containsKey(key)) {
      var wav = _wavs[key];
      wav ??= await Isolate.run<Uint8List>(() => SynthV2.wav(songTones(levelIds)));
      _wavs[key] = wav;
      if (!_ready) return;
      _sources[key] = await SoLoud.instance.loadMem(key, wav);
    }
    _play(key, SynthRenderer.bakedVolume);
  }

  /// Acorde de cierre de sesión.
  void playClosing() => _play(closingKey, SynthRenderer.bakedVolume);

  /// Campanita de stick vinculado.
  void playChime() => _play(chimeKey, SynthRenderer.bakedVolume);

  /// Pérdida de stick: todo baja en 1,2 s.
  void fadeOutForLoss() => _fadeGlobal(0.0001, const Duration(milliseconds: 1200));

  /// Stick recuperado: vuelve en 0,6 s.
  void fadeInAfterLoss() => _fadeGlobal(globalVolume, const Duration(milliseconds: 600));

  void _fadeGlobal(double to, Duration d) {
    if (!_ready) return;
    try {
      SoLoud.instance.fadeGlobalVolume(to, d);
    } catch (e) {
      debugPrint('[AudioEngineV2] fallo en el fundido: $e');
    }
  }

  void _play(String key, double volume) {
    if (!_ready) return;
    final src = _sources[key];
    if (src == null) return;
    try {
      SoLoud.instance.play(src, volume: volume);
    } catch (e) {
      debugPrint('[AudioEngineV2] fallo al reproducir $key: $e');
      unawaited(ensureAlive());
    }
  }

  /// Voces de SoLoud sonando (diagnóstico).
  int get voiceCount {
    try {
      return SoLoud.instance.isInitialized ? SoLoud.instance.getVoiceCount() : 0;
    } catch (_) {
      return 0;
    }
  }
}
