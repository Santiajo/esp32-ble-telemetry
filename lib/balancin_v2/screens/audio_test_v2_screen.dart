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
/// (izquierda = adulto, derecha = niño; arrastrar = inclinar, un dedo en cada
/// panel a la vez) o con la fuente sintética, y suena por el motor de audio v2:
/// voz del adulto, tono de relación, notas del niño, pad, frases y voz de
/// consignas. Cada capa se puede silenciar para aislar un sonido.
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
  static const Color paper = Color(0xFFEFECE4);

  static final ThemeData _theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ink, brightness: Brightness.light),
    scaffoldBackgroundColor: paper,
  );

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
  final Map<Role, int?> _pointer = {Role.adult: null, Role.child: null};
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
    if (now - _lastUi > 33) {
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
          _addLog('sesión cerrada · «Reiniciar» para otra');
        default:
          break;
      }
    }
  }

  void _addLog(String s) {
    _log.insert(0, s);
    if (_log.length > 4) _log.removeLast();
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
    // La app usa un tema oscuro; esta pantalla sigue la paleta clara del prototipo.
    return Theme(
      data: _theme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Prueba de audio v2'), backgroundColor: paper, foregroundColor: ink),
        body: SafeArea(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No se pudo iniciar el audio:\n$_error')))
              : !_audio.isReady
                  ? const Center(child: Text('Preparando sonidos…'))
                  : _body(),
        ),
      ),
    );
  }

  Widget _body() {
    final e = _engine;
    final det = AudioLayers.detune(e.d, e.tol, e.params.maxDetune);
    // Sin scroll en la zona de los paneles: reciben los arrastres completos.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SegmentedButton<PlayMode>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButton<SynthQuality?>(
              isExpanded: true,
              value: _synth,
              items: [
                const DropdownMenuItem(value: null, child: Text('Fuente: dedo')),
                for (final q in SynthQuality.values)
                  DropdownMenuItem(value: q, child: Text('Sintética · ${synthQualityNames[q]}')),
              ],
              onChanged: (q) => setState(() => _synth = q),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        _status(e, det),
        const SizedBox(height: 8),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _panel(Role.adult, 'Adulto', lila)),
            const SizedBox(width: 8),
            Expanded(child: _panel(Role.child, 'Niño', coral)),
          ]),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          _toggle('Voz adulto', !_audio.muteAdult, (v) => _audio.muteAdult = !v),
          _toggle('Tono relación', !_audio.muteRelation, (v) => _audio.muteRelation = !v),
          _toggle('Notas niño', !_audio.muteChild, (v) => _audio.muteChild = !v),
          _toggle('Pad', !_audio.mutePad, (v) => _audio.mutePad = !v),
          _toggle('Compresor', _audio.compressorOn, (v) => _audio.compressorOn = v),
          _toggle('Consignas', _voice.enabled, (v) => _voice.enabled = v),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 128,
          child: SingleChildScrollView(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              _btn('Reiniciar', _restart),
              _btn('Frase', () => _audio.events([PhraseEvent(0, levelById(1).phraseMidi, 0.24, 0.17)])),
              _btn('Canción ganada', () => unawaited(_audio.playSong(_progress.isEmpty ? [1] : (List.of(_progress)..sort())))),
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
              _btn('Borrar progreso (${_progress.length})', () => setState(_progress.clear)),
              SizedBox(
                width: double.infinity,
                child: Text(_log.join('\n'), style: const TextStyle(fontSize: 11, color: Color(0xFF5A536B))),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _status(SyncEngine e, double det) {
    final sync = e.inSync && e.bothActive;
    final lines = [
      '${e.state.name} · d = ${e.d.toStringAsFixed(2)} (tol ${e.tol.toStringAsFixed(2)}) · ${det == 0 ? 'afinado' : 'ondula ${det.toStringAsFixed(1)} Hz'}',
      if (e.level != null) 'progreso ${(e.progFraction * 100).round()} % · guía ${roleNames[e.guide]}',
      'voces ${_audio.voiceCount} · render ${_audio.renderTimeMs} ms · TTS ${_voice.language ?? 'sin idioma'}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: sync ? const Color(0xFFF3F5E8) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sync ? olive : const Color(0x402B2536), width: 1.5),
      ),
      child: Text(lines.join('\n'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink, height: 1.35)),
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
      // Listener (no GestureDetector): no compite con otros gestos y admite un dedo por panel a la vez.
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (ev) {
          if (_pointer[role] != null) return;
          _pointer[role] = ev.pointer;
          _feed(role, ev.localPosition, size);
        },
        onPointerMove: (ev) {
          if (ev.pointer == _pointer[role]) _feed(role, ev.localPosition, size);
        },
        onPointerUp: (ev) {
          if (ev.pointer == _pointer[role]) _pointer[role] = null;
        },
        onPointerCancel: (ev) {
          if (ev.pointer == _pointer[role]) _pointer[role] = null;
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? color : const Color(0x262B2536), width: active ? 3 : 1.5),
          ),
          child: Stack(children: [
            Center(child: Container(width: size.width, height: 1, color: const Color(0x142B2536))),
            Center(child: Container(width: 1, height: size.height, color: const Color(0x142B2536))),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('$title · ${active ? 'activo' : 'quieto'}\narrastra para inclinar',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink)),
            ),
            if (st.has)
              Positioned(
                left: px.clamp(11.0, size.width - 11) - 11,
                top: py.clamp(11.0, size.height - 11) - 11,
                child: Container(width: 22, height: 22, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
          ]),
        ),
      );
    });
  }

  Widget _toggle(String label, bool on, void Function(bool) set) => FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        selected: on,
        visualDensity: VisualDensity.compact,
        onSelected: (v) => setState(() => set(v)),
      );

  Widget _btn(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: const BorderSide(color: Color(0x402B2536), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      );
}
