import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../balancin/core/app_clock.dart';
import '../core/audio/layers.dart';
import '../core/levels.dart';
import '../core/stick_state.dart';
import '../core/sync_engine.dart';
import '../core/synthetic_source.dart';
import '../platform/audio_engine_v2.dart';
import '../platform/voice_prompts.dart';

/// Prueba de audio de la mecánica v2 (plan v2, fase 3).
///
/// Corre el motor real del nivel 1 o del modo Libre con dos paneles táctiles
/// (izquierda = adulto, derecha = niño; arrastrar = inclinar) o con la fuente
/// sintética, y suena por el motor de audio v2: voz del adulto, tono de
/// relación, notas del niño, pad, frases y voz de consignas. Sirve para
/// validar en el teléfono que la ondulación se oye y desaparece al coincidir,
/// que no hay clics ni crujidos y que la respuesta es inmediata.
class AudioTestV2Screen extends StatefulWidget {
  const AudioTestV2Screen({super.key});

  @override
  State<AudioTestV2Screen> createState() => _AudioTestV2ScreenState();
}

class _AudioTestV2ScreenState extends State<AudioTestV2Screen> with SingleTickerProviderStateMixin {
  static const double tiltRange = 60; // el ancho de un panel = ±60° (como el prototipo)
  static const Color lila = Color(0xFF9F8AD9);
  static const Color coral = Color(0xFFE85E45);
  static const Color olive = Color(0xFF7A8B34);
  static const Color ink = Color(0xFF2B2536);

  final AudioEngineV2 _audio = AudioEngineV2();
  final VoicePrompts _voice = VoicePrompts();
  final AudioLayers _layers = AudioLayers();
  late final SyncEngine _engine;
  late final Ticker _ticker;

  String? _error;
  PlayMode _mode = PlayMode.levels;
  SynthQuality? _synth; // null = dedo
  final List<int> _progress = [];
  final List<String> _log = [];
  double _lastUi = 0;

  @override
  void initState() {
    super.initState();
    _engine = SyncEngine(isLevelEnabled: enabledLevelIds.contains);
    _engine.drive = (now) {
      final q = _synth;
      if (q != null) synthDrive(_engine, q, now);
    };
    _ticker = createTicker((_) => _frame());
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await Future.wait([_audio.init(), _voice.init()]);
      if (!mounted) return;
      _restart();
      _ticker.start();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_voice.stop());
    unawaited(_audio.release());
    super.dispose();
  }

  void _restart() {
    final now = AppClock.nowMs();
    _layers
      ..resetChild()
      ..startPad(now);
    _handle(_engine.start(mode: _mode, now: now), now);
  }

  void _frame() {
    final now = AppClock.nowMs();
    _audio.notes(_layers.firePad(now, _engine, _progress), now);
    _handle(_engine.tick(now), now);
    if (_engine.running) _audio.notes(_layers.update(now, _engine.lastDt, _engine), now);
    _audio.frame(_layers, _engine.lastDt > 0 ? _engine.lastDt : 1 / 60);
    if (now - _lastUi > 66) {
      _lastUi = now;
      setState(() {});
    }
  }

  void _handle(List<SyncEvent> evs, double now) {
    _audio.events(evs);
    for (final ev in evs) {
      switch (ev) {
        case SayEvent(:final text):
          unawaited(_voice.say(text));
          _addLog('voz: $text');
        case LevelCompletedEvent(:final levelId):
          if (!_progress.contains(levelId)) _progress.add(levelId);
          _addLog('nivel $levelId logrado');
        case SessionClosedEvent():
          _layers
            ..silence()
            ..stopPad();
          _audio.playClosing();
          _addLog('sesión cerrada');
        default:
          break;
      }
    }
  }

  void _addLog(String s) {
    _log.insert(0, s);
    if (_log.length > 6) _log.removeLast();
  }

  void _feed(Role role, Offset local, Size size) {
    if (_synth != null) return;
    final fx = (local.dx / size.width).clamp(0.0, 1.0);
    final fy = (local.dy / size.height).clamp(0.0, 1.0);
    _engine.stick(role).feedTilt((fx - 0.5) * 2 * tiltRange, -(fy - 0.5) * 2 * tiltRange, _engine.params);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFECE4),
      appBar: AppBar(
        title: const Text('Prueba de audio v2'),
        backgroundColor: const Color(0xFFEFECE4),
        foregroundColor: ink,
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No se pudo iniciar el audio:\n$_error')))
          : !_audio.isReady
              ? const Center(child: Text('Preparando sonidos…'))
              : _body(),
    );
  }

  Widget _body() {
    final e = _engine;
    final det = AudioLayers.detune(e.d, e.tol, e.params.maxDetune);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          SegmentedButton<PlayMode>(
            segments: const [
              ButtonSegment(value: PlayMode.levels, label: Text('Nivel 1')),
              ButtonSegment(value: PlayMode.free, label: Text('Libre')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              _mode = s.first;
              _restart();
            },
          ),
          DropdownButton<SynthQuality?>(
            value: _synth,
            items: [
              const DropdownMenuItem(value: null, child: Text('Fuente: dedo')),
              for (final q in SynthQuality.values)
                DropdownMenuItem(value: q, child: Text('Sintética · ${synthQualityNames[q]}')),
            ],
            onChanged: (q) => setState(() => _synth = q),
          ),
        ]),
        const SizedBox(height: 8),
        _status(e, det),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: Row(children: [
            Expanded(child: _panel(Role.adult, 'Stick grande · adulto', lila)),
            const SizedBox(width: 10),
            Expanded(child: _panel(Role.child, 'Stick pequeño · niño', coral)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _btn('Reiniciar sesión', _restart),
          _btn('Frase nivel 1', () => _audio.events([PhraseEvent(0, levelById(1).phraseMidi, 0.24, 0.17)])),
          _btn('Canción (ganadas)', () => unawaited(_audio.playSong(_progress.isEmpty ? [1] : (List.of(_progress)..sort())))),
          _btn('Canción completa', () => unawaited(_audio.playSong([for (final l in levels) l.id]))),
          _btn('Cierre', _audio.playClosing),
          _btn('Campanita', _audio.playChime),
          _btn('Consigna', () => unawaited(_voice.say('Nivel 1. Juntos. Suban y bajen los sticks al mismo tiempo. Guía el adulto, luego el niño.'))),
          _btn('Perder stick', () {
            _engine.pause();
            _layers.silence();
            _audio.fadeOutForLoss();
          }),
          _btn('Recuperar', () {
            final now = AppClock.nowMs();
            _audio.fadeInAfterLoss();
            _layers.resetChild();
            _handle(_engine.resume(now), now);
          }),
          _btn(_voice.enabled ? 'Voz: activada' : 'Voz: desactivada', () => setState(() => _voice.enabled = !_voice.enabled)),
          _btn('Borrar progreso (${_progress.length})', () => setState(_progress.clear)),
        ]),
        const SizedBox(height: 12),
        Text(_log.join('\n'), style: const TextStyle(fontSize: 12, color: Color(0xFF5A536B))),
      ],
    );
  }

  Widget _status(SyncEngine e, double det) {
    final sync = e.inSync && e.bothActive;
    final txt = [
      '${e.state.name} · d = ${e.d.toStringAsFixed(2)} (tol ${e.tol.toStringAsFixed(2)})',
      det == 0 ? 'afinado' : 'ondula ${det.toStringAsFixed(1)} Hz',
      if (e.level != null) 'progreso ${(e.progFraction * 100).round()} % · guía ${roleNames[e.guide]}',
      'voces ${_audio.voiceCount} · render ${_audio.renderTimeMs} ms · TTS ${_voice.language ?? 'sin idioma'}',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sync ? const Color(0xFFF3F5E8) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sync ? olive : const Color(0x402B2536), width: 1.5),
      ),
      child: Text(txt.join('\n'), style: const TextStyle(fontWeight: FontWeight.w700, color: ink, height: 1.4)),
    );
  }

  Widget _panel(Role role, String title, Color color) {
    final st = _engine.stick(role);
    final active = role == Role.adult ? _engine.adultActive : _engine.childActive;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      // Punto según la posición en el plano (−6..6), siempre dentro del panel.
      final px = (st.pos.x / planeLimit / 2 + 0.5) * size.width;
      final py = (-st.pos.y / planeLimit / 2 + 0.5) * size.height;
      return GestureDetector(
        onPanStart: (d) => _feed(role, d.localPosition, size),
        onPanUpdate: (d) => _feed(role, d.localPosition, size),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? color : const Color(0x262B2536), width: 2),
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('$title\n${active ? 'Activo' : 'Quieto'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink)),
            ),
            if (st.has)
              Positioned(
                left: px.clamp(9.0, size.width - 9) - 9,
                top: py.clamp(9.0, size.height - 9) - 9,
                child: Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
          ]),
        ),
      );
    });
  }

  Widget _btn(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          side: const BorderSide(color: Color(0x402B2536), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}
