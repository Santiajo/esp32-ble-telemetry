import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../balancin/core/app_clock.dart';
import '../../balancin/platform/ble_stick_link.dart';
import '../../balancin/platform/stick_hub.dart';
import '../../balancin/session/board_session.dart' show StickRole;
import '../../widgets/ble_scan_modal.dart';
import '../core/audio/layers.dart';
import '../core/levels.dart';
import '../core/light_model.dart';
import '../core/params.dart';
import '../core/stick_state.dart';
import '../core/sync_engine.dart';
import '../core/synthetic_source.dart';
import '../core/telemetry.dart';
import '../platform/audio_engine_v2.dart';
import '../platform/bench_store.dart';
import '../platform/share_file.dart';
import '../platform/tilt_stick.dart';
import '../platform/voice_prompts.dart';
import '../widgets/sync_plane.dart';
import '../widgets/two_halves_light.dart';

enum BenchSource { finger, synthetic, stick }

const Map<BenchSource, String> _sourceNames = {
  BenchSource.finger: 'Dedo',
  BenchSource.synthetic: 'Sintética',
  BenchSource.stick: 'Stick',
};

/// Banco de prueba del equipo, mecánica v2 (plan v2 §5; `#banco` del prototipo).
///
/// Plano limitado con los dos puntos, la zona objetivo y `d`; medidores de
/// sincronía, progreso, guía y ritmo; una fuente por rol (dedo, sintética o el
/// stick real con su lector de inclinación); sonido v2 completo; telemetría por
/// nivel exportable; ajuste en vivo de los parámetros; modo eje (solo luz) y
/// grabación de trazas de los sticks.
class BenchScreen extends StatefulWidget {
  const BenchScreen({super.key, required this.hub});

  /// Dueño de las conexiones BLE (el mismo de la app v1).
  final StickHub hub;

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> with SingleTickerProviderStateMixin {
  static const Color lila = Color(0xFF9F8AD9);
  static const Color coral = Color(0xFFE85E45);
  static const Color olive = Color(0xFF7A8B34);
  static const Color ink = Color(0xFF2B2536);
  static const Color soft = Color(0xFF5A536B);
  static const Color paper = Color(0xFFEFECE4);
  static const double tiltRange = 60; // el ancho de un panel = ±60°

  static final ThemeData _theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ink, brightness: Brightness.light),
    scaffoldBackgroundColor: paper,
  );

  final AudioEngineV2 _audio = AudioEngineV2();
  final VoicePrompts _voice = VoicePrompts();
  final AudioLayers _layers = AudioLayers();
  late final Ticker _ticker;
  SyncParams? _params;
  SyncEngine? _engine;
  String? _error;

  PlayMode _mode = PlayMode.levels;
  final Map<Role, BenchSource> _src = {Role.adult: BenchSource.finger, Role.child: BenchSource.finger};
  SynthQuality _quality = SynthQuality.cycle;
  final Map<Role, TiltStick> _sticks = {};
  final Map<Role, int?> _pointer = {Role.adult: null, Role.child: null};
  final List<int> _progress = [];
  final List<String> _log = [];
  bool _eje = false;
  bool _closed = false;
  String _closedText = '';
  Map<String, Object?>? _lastReport;
  double _lastUi = 0;

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _frame());
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final params = await BenchStore.loadParams();
      _voice.enabled = await BenchStore.loadVoice();
      final e = SyncEngine(params: params, isLevelEnabled: enabledLevelIds.contains);
      e.drive = _drive;
      _params = params;
      _engine = e;
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
    for (final s in _sticks.values) {
      s.dispose();
    }
    unawaited(_voice.stop());
    unawaited(_audio.release());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Motor
  // ---------------------------------------------------------------------------

  SyncEngine get _e => _engine!;

  void _restart() {
    final now = AppClock.nowMs();
    _closed = false;
    _layers
      ..resetChild()
      ..startPad(now);
    _handle(_e.start(mode: _mode, now: now), now);
  }

  /// Fuentes que no son el dedo: sintética y stick (`synthDrive` del prototipo).
  void _drive(double now) {
    final synth = {for (final r in Role.values) if (_src[r] == BenchSource.synthetic) r};
    if (synth.isNotEmpty) synthDrive(_e, _quality, now, roles: synth);
    for (final r in Role.values) {
      if (_src[r] != BenchSource.stick) continue;
      final s = _sticks[r];
      if (s == null || s.stale(now)) continue;
      _e.stick(r).feedTilt(s.reader.tiltX, s.reader.tiltY, _e.params);
    }
  }

  void _frame() {
    final e = _engine;
    if (e == null) return;
    final now = AppClock.nowMs();
    _audio.notes(_layers.firePad(now, e, _progress), now);
    _handle(e.tick(now), now);
    if (e.running) _audio.notes(_layers.update(now, e.lastDt, e), now);
    _audio.frame(_layers, e.lastDt > 0 ? e.lastDt : 1 / 60);
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
        case PhraseStepEvent(:final step, :final up):
          _addLog(up ? 'frase: nota $step de 4' : 'frase: se cayó la nota $step');
        case GuideChangedEvent(:final guide):
          _addLog('ahora guía ${roleNames[guide]}');
        case CalibrationDoneEvent(:final adult, :final child):
          String f(StickCal? c) => c == null ? 'sin datos (rango por defecto)' : 'centro ${c.cx.toStringAsFixed(0)}°/${c.cy.toStringAsFixed(0)}° · medio rango ${c.hr.toStringAsFixed(0)}°';
          _addLog('calibrado · adulto ${f(adult)} · niño ${f(child)}');
        case SessionClosedEvent(:final record, :final byIdle):
          _layers
            ..silence()
            ..stopPad();
          _audio.playClosing();
          _lastReport = _e.report();
          _closed = true;
          _closedText = byIdle
              ? 'Sesión cerrada: 30 s sin juego.'
              : record.levels.isNotEmpty
                  ? '¡Nivel ${record.levels.last} logrado! En la app aquí se pasa al final.'
                  : 'Sesión terminada.';
          _eje = false;
        default:
          break;
      }
    }
  }

  void _addLog(String s) {
    _log.insert(0, s);
    if (_log.length > 30) _log.removeLast();
  }

  // ---------------------------------------------------------------------------
  // Fuentes
  // ---------------------------------------------------------------------------

  StickRole _stickRole(Role r) => r == Role.adult ? StickRole.adult : StickRole.child;

  Future<void> _setSource(Role role, BenchSource src) async {
    if (src == BenchSource.stick) {
      final ok = await _useStick(role);
      if (!ok) return;
    }
    setState(() => _src[role] = src);
  }

  /// Permisos, Bluetooth encendido, enlace (reconexión a la MAC guardada o
  /// escaneo) y lector de inclinación. Mismo recorrido que el tablero de v1.
  Future<bool> _useStick(Role role) async {
    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      if (!scan.isGranted || !connect.isGranted) {
        _snack('Se necesitan los permisos de Bluetooth para usar el stick.');
        return false;
      }
    }
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      if (!mounted) return false;
      final on = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth apagado'),
          content: const Text('¿Lo enciendo para conectar el stick?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Encender')),
          ],
        ),
      );
      if (on != true) return false;
      await FlutterBluePlus.turnOn();
    }
    final sr = _stickRole(role);
    final link = widget.hub.ensureLink(sr);
    if (!await widget.hub.hasSavedStick(sr) && mounted) await _scan(link);
    _sticks[role] ??= TiltStick(link, params: _params);
    return true;
  }

  Future<void> _scan(BleStickLink link) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => BleScanModal(
        controller: link.controller,
        preferredNames: link.acceptedNames,
        onSeleccionado: (dev) async {
          Navigator.pop(ctx);
          await link.adopt(dev);
        },
      ),
    );
  }

  Future<void> _toggleRecording(Role role) async {
    final s = _sticks[role];
    if (s == null) return;
    final now = AppClock.nowMs();
    if (!s.recording) {
      s.startRecording(now);
      _addLog('grabando traza del stick ${role == Role.adult ? 'A' : 'B'}');
      return;
    }
    final name = role == Role.adult ? 'A' : 'B';
    final when = DateTime.now();
    final text = s.stopRecording(role: name, when: when);
    final stamp = '${when.year}${_two(when.month)}${_two(when.day)}-${_two(when.hour)}${_two(when.minute)}';
    final ok = await shareTextFile('stick_${name.toLowerCase()}_$stamp.trace', text, text: 'Traza del stick $name');
    if (!ok) _snack('No se pudo compartir; la traza quedó copiada al portapapeles.');
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _feedFinger(Role role, Offset local, Size size) {
    if (_src[role] != BenchSource.finger) return;
    final fx = (local.dx / size.width).clamp(0.0, 1.0);
    final fy = (local.dy / size.height).clamp(0.0, 1.0);
    _e.stick(role).feedTilt((fx - 0.5) * 2 * tiltRange, -(fy - 0.5) * 2 * tiltRange, _e.params);
  }

  bool _stale(Role r, double now) => _src[r] == BenchSource.stick && (_sticks[r]?.stale(now) ?? true);

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    return Theme(
      data: _theme,
      child: Scaffold(
        appBar: _eje ? null : AppBar(title: const Text('Banco de prueba v2'), backgroundColor: paper, foregroundColor: ink),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No se pudo iniciar:\n$_error')))
            : (e == null || !_audio.isReady)
                ? const Center(child: Text('Preparando sonidos…'))
                : _eje
                    ? _ejeView(e)
                    : SafeArea(child: _body(e)),
      ),
    );
  }

  Widget _ejeView(SyncEngine e) {
    final now = AppClock.nowMs();
    return Stack(children: [
      Positioned.fill(child: TwoHalvesLight(frame: lightFrame(e, now))),
      Positioned(
        top: 24,
        left: 12,
        child: SafeArea(
          child: TextButton(
            onPressed: () => setState(() => _eje = false),
            child: const Text('Salir del modo eje', style: TextStyle(color: Colors.white38)),
          ),
        ),
      ),
    ]);
  }

  Widget _body(SyncEngine e) {
    final now = AppClock.nowMs();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pill(e),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth.clamp(0.0, MediaQuery.of(context).size.height * 0.38);
          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(children: [
                SyncPlane(
                  adult: e.adult,
                  child: e.child,
                  now: now,
                  target: e.target(now),
                  tol: e.tol,
                  adultStale: _stale(Role.adult, now),
                  childStale: _stale(Role.child, now),
                ),
                if (_closed) _closedBanner(),
              ]),
            ),
          );
        }),
        const SizedBox(height: 4),
        _meters(e, now),
        const SizedBox(height: 6),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _panel(Role.adult, 'Adulto · stick grande', lila, now)),
            const SizedBox(width: 8),
            Expanded(child: _panel(Role.child, 'Niño · stick pequeño', coral, now)),
          ]),
        ),
        const SizedBox(height: 6),
        _controls(e),
      ]),
    );
  }

  Widget _pill(SyncEngine e) {
    const names = {
      EngineState.idle: 'Listo',
      EngineState.calibrating: 'Calibrando',
      EngineState.playing: 'Jugando',
      EngineState.levelComplete: 'Nivel logrado',
      EngineState.songComplete: 'Canción completa',
    };
    final l = e.level;
    final desc = e.calibrating
        ? 'Muévanse libremente: se mide el rango de cada persona (${(e.calibrationElapsed(AppClock.nowMs()) / 1000).toStringAsFixed(0)} de 6 s).'
        : l == null
            ? 'Libre: el tono de relación busca el movimiento en común más cercano.'
            : 'Nivel ${l.id} · ${l.name}: ${l.text}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${names[e.state]}  ', style: const TextStyle(fontWeight: FontWeight.w900)),
          TextSpan(text: desc),
        ]),
        style: const TextStyle(fontSize: 12.5, color: ink, fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _closedBanner() => Center(
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_closedText,
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(onPressed: () => setState(_restart), child: const Text('Otra vez')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _openTelemetry,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                child: const Text('Telemetría'),
              ),
            ]),
          ]),
        ),
      );

  Widget _meters(SyncEngine e, double now) {
    final both = e.bothActive;
    final syncTxt = e.inSync ? (both ? 'En sincronía' : 'Sincronía sin actividad') : 'Fuera de sincronía';
    final ra = e.adult.rhythm(now, e.params), rc = e.child.rhythm(now, e.params);
    final ll = e.lastLeadLag;
    final lead = ll == null
        ? 'Quién va adelante: sin datos'
        : ll.lag > 0.05
            ? 'Adelante: adulto (${ll.lag.toStringAsFixed(1)} s)'
            : ll.lag < -0.05
                ? 'Adelante: niño (${(-ll.lag).toStringAsFixed(1)} s)'
                : 'Van a la par';
    String edge(Role r) => '${(e.stick(r).edgeFraction * 100).round()} %';
    const small = TextStyle(fontSize: 12, color: soft, fontWeight: FontWeight.w700);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('d = ${e.d.toStringAsFixed(2)} · tolerancia ${e.tol.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: e.inSync && both ? olive : const Color(0xFFDCD8CF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(syncTxt,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: e.inSync && both ? Colors.white : ink)),
        ),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: e.progFraction,
          minHeight: 7,
          color: olive,
          backgroundColor: const Color(0xFFDCD8CF),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        '${e.level == null ? 'Libre' : 'Nivel ${e.level!.id} · guía ${roleNames[e.guide]}'} · '
        'ritmo ${ra.f.toStringAsFixed(2)} / ${rc.f.toStringAsFixed(2)} Hz · $lead',
        style: small,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text('En el borde: adulto ${edge(Role.adult)} · niño ${edge(Role.child)}', style: small),
    ]);
  }

  Widget _panel(Role role, String title, Color color, double now) {
    final src = _src[role]!;
    final active = role == Role.adult ? _engine!.adultActive : _engine!.childActive;
    final header = Row(children: [
      Expanded(
        child: Text('$title\n${active ? 'activo' : 'quieto'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink, height: 1.25)),
      ),
      DropdownButton<BenchSource>(
        value: src,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink),
        items: [for (final s in BenchSource.values) DropdownMenuItem(value: s, child: Text(_sourceNames[s]!))],
        onChanged: (s) {
          if (s != null) unawaited(_setSource(role, s));
        },
      ),
    ]);
    final Widget content = switch (src) {
      BenchSource.finger => _fingerArea(role, color),
      BenchSource.synthetic => Center(
          child: Text('Fuente sintética\n${synthQualityNames[_quality]}',
              textAlign: TextAlign.center, style: const TextStyle(color: soft, fontWeight: FontWeight.w700))),
      BenchSource.stick => _stickInfo(role, now),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? color : const Color(0x262B2536), width: active ? 3 : 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 4),
        Expanded(child: content),
      ]),
    );
  }

  /// Zona táctil: arrastrar = inclinar (el ancho = ±60°). Un dedo por panel a la vez.
  Widget _fingerArea(Role role, Color color) => LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (ev) {
            if (_pointer[role] != null) return;
            _pointer[role] = ev.pointer;
            _feedFinger(role, ev.localPosition, size);
          },
          onPointerMove: (ev) {
            if (ev.pointer == _pointer[role]) _feedFinger(role, ev.localPosition, size);
          },
          onPointerUp: (ev) {
            if (ev.pointer == _pointer[role]) _pointer[role] = null;
          },
          onPointerCancel: (ev) {
            if (ev.pointer == _pointer[role]) _pointer[role] = null;
          },
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Text('arrastra para inclinar', style: TextStyle(fontSize: 11, color: soft)),
          ),
        );
      });

  Widget _stickInfo(Role role, double now) {
    final s = _sticks[role];
    if (s == null) return const Center(child: Text('Sin stick'));
    final r = s.reader;
    final b = r.biasDps;
    final st = _e.stick(role);
    final lines = [
      s.statusText(now),
      'inclinación ${r.tiltX.toStringAsFixed(1)}° / ${r.tiltY.toStringAsFixed(1)}°',
      if (st.cal != null) 'calibrado: medio rango ${st.cal!.hr.toStringAsFixed(0)}°' else 'sin calibrar: rango ${st.range(_e.params).hr.toStringAsFixed(0)}°',
      '|a| ${r.accelMagG.toStringAsFixed(2)} g · ${r.correcting ? 'corrige con gravedad' : 'solo giroscopio'}',
      'bias ${b.x.toStringAsFixed(1)} / ${b.y.toStringAsFixed(1)} / ${b.z.toStringAsFixed(1)} °/s',
      'en el borde ${(st.edgeFraction * 100).round()} %${st.atEdge ? ' · AHORA' : ''}',
      if (s.recording) 'grabando ${s.recordedSeconds(now).toStringAsFixed(0)} s (${s.recordedSamples})',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          child: Text(lines.join('\n'), style: const TextStyle(fontSize: 11, color: ink, height: 1.35, fontWeight: FontWeight.w600)),
        ),
      ),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _mini(s.recording ? 'Detener y compartir' : 'Grabar traza', () => unawaited(_toggleRecording(role))),
        _mini('Vincular otro', () => unawaited(_scan(s.link))),
        _mini('Recalibrar giro', () => r.resetCalibration()),
      ]),
    ]);
  }

  Widget _controls(SyncEngine e) {
    final anySynth = _src.values.contains(BenchSource.synthetic);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SegmentedButton<PlayMode>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: PlayMode.free, label: Text('Libre')),
            ButtonSegment(value: PlayMode.levels, label: Text('Nivel 1')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            _mode = s.first;
            if (_closed) {
              _restart();
            } else {
              _handle(e.switchTo(mode: _mode, now: AppClock.nowMs()), AppClock.nowMs());
            }
          },
        ),
        const SizedBox(width: 8),
        if (anySynth)
          Expanded(
            child: DropdownButton<SynthQuality>(
              isExpanded: true,
              value: _quality,
              items: [
                for (final q in SynthQuality.values) DropdownMenuItem(value: q, child: Text('Sintética · ${synthQualityNames[q]}')),
              ],
              onChanged: (q) => setState(() => _quality = q ?? _quality),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _mini('Calibrar rango', () => _handle(e.recalibrate(AppClock.nowMs()), AppClock.nowMs())),
        _mini('Reiniciar', () => setState(_restart)),
        _mini('Terminar', () => _handle(e.close(AppClock.nowMs()), AppClock.nowMs())),
        _mini('Modo eje', () => setState(() => _eje = true)),
        _mini('Telemetría', _openTelemetry),
        _mini('Ajuste', _openTuning),
        _mini(_voice.enabled ? 'Voz: sí' : 'Voz: no', () {
          setState(() => _voice.enabled = !_voice.enabled);
          unawaited(BenchStore.saveVoice(_voice.enabled));
        }),
        _mini('Registro', _openLog),
      ]),
    ]);
  }

  Widget _mini(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: const BorderSide(color: Color(0x402B2536), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );

  // ---------------------------------------------------------------------------
  // Hojas: telemetría, ajuste, registro
  // ---------------------------------------------------------------------------

  void _openTelemetry() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paper,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final rows = _e.levelTelemetry;
        String lead(LevelTelemetry lt) => lt.lagN == 0
            ? '–'
            : lt.adultoSigue / lt.lagN > 0.5
                ? 'el niño (${(lt.adultoSigue / lt.lagN * 100).round()} %)'
                : 'el adulto';
        String s1(double? v) => v == null ? '–' : '${v.toStringAsFixed(1)} s';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Telemetría por nivel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                FilledButton(
                  onPressed: () async {
                    final rep = _closed ? (_lastReport ?? _e.report()) : _e.report();
                    final ok = await shareTextFile('balancin-v2-telemetria.json', const JsonEncoder.withIndent('  ').convert(rep),
                        mimeType: 'application/json', text: 'Telemetría Balancín v2');
                    if (!ok) _snack('No se pudo compartir; el JSON quedó copiado al portapapeles.');
                  },
                  child: const Text('Compartir JSON'),
                ),
              ]),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(fontWeight: FontWeight.w900, color: ink, fontSize: 12),
                  dataTextStyle: const TextStyle(color: ink, fontSize: 12),
                  columnSpacing: 14,
                  columns: const [
                    DataColumn(label: Text('Nivel')),
                    DataColumn(label: Text('1ª sincronía')),
                    DataColumn(label: Text('En sincronía')),
                    DataColumn(label: Text('d prom.')),
                    DataColumn(label: Text('Quién guía')),
                    DataColumn(label: Text('Pausas')),
                    DataColumn(label: Text('Completado')),
                  ],
                  rows: [
                    for (final lt in rows)
                      DataRow(cells: [
                        DataCell(Text(lt.isFree ? 'Libre' : '${lt.nivel}')),
                        DataCell(Text(s1(lt.primera))),
                        DataCell(Text('${lt.syncPercent.round()} %')),
                        DataCell(Text(lt.dMean?.toStringAsFixed(2) ?? '–')),
                        DataCell(Text(lead(lt))),
                        DataCell(Text('${lt.pausas} / ${lt.reanud}')),
                        DataCell(Text(s1(lt.completado))),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sesión: ${e2(_e.total)} s · ${e2(_e.syncT)} s en sincronía · niveles logrados ${_e.levelsDone.isEmpty ? '–' : _e.levelsDone.join(', ')}',
                style: const TextStyle(fontSize: 12, color: soft),
              ),
            ]),
          ),
        );
      }),
    );
  }

  static String e2(double v) => v.toStringAsFixed(1);

  static const List<(String, String, double, double, double, String, int)> _tune = [
    ('tolScale', 'Tolerancia (× nivel)', 0.5, 1.5, 0.05, '×', 2),
    ('alpha', 'Suavizado de posición α', 0.05, 0.6, 0.01, '', 2),
    ('rangeA', 'Rango por defecto · adulto', 10, 60, 1, '°', 0),
    ('rangeC', 'Rango por defecto · niño', 15, 80, 1, '°', 0),
    ('onSpeed', 'Umbral de actividad', 0.5, 6, 0.1, ' u/s', 1),
    ('maxDetune', 'Desafinación máxima', 1, 8, 0.1, ' Hz', 1),
    ('secScale', 'Segundos por nivel (×)', 0.25, 2, 0.05, '×', 2),
    ('idleAfter', 'Inactividad antes de decaer', 1, 8, 0.5, ' s', 1),
    ('kAccel', 'Stick: corrección con gravedad', 0.005, 0.1, 0.005, '', 3),
    ('accelGate', 'Stick: compuerta de |a|', 0.05, 0.5, 0.01, ' g', 2),
    // §12: cambios del 18-10-2026 (guía: docs/GUIA_AJUSTE_V2.md)
    ('slipGrace', 'Margen al salir de la zona', 0, 1.5, 0.05, ' s', 2),
    ('slipDrain', 'Pérdida al salir (× velocidad)', 0, 3, 0.1, '×', 1),
    ('velWeight', 'Peso de la velocidad en d', 0, 0.3, 0.01, ' s', 2),
    ('hyst', 'Histéresis de la sincronía', 1, 2, 0.05, '×', 2),
    ('phraseSteps', 'Frase nota a nota (0 / 1)', 0, 1, 1, '', 0),
    ('runMaxNotes', 'Notas de paso (máximo)', 0, 10, 1, '', 0),
    ('runMs', 'Duración de la escala de paso', 40, 300, 10, ' ms', 0),
    ('runGain', 'Volumen de las notas de paso', 0.2, 1, 0.05, '×', 2),
  ];

  void _openTuning() {
    final p = _params!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paper,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Ajuste   ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(p.toJson())));
                    _snack('Valores copiados.');
                  },
                  child: const Text('Copiar valores'),
                ),
                TextButton(
                  onPressed: () {
                    p.resetToDefaults();
                    unawaited(BenchStore.saveParams(p));
                    setSheet(() {});
                  },
                  child: const Text('Valores iniciales'),
                ),
                TextButton(
                  onPressed: () {
                    final proto = SyncParams.prototype();
                    for (final k in SyncParams.keys) {
                      p[k] = proto[k];
                    }
                    unawaited(BenchStore.saveParams(p));
                    setSheet(() {});
                  },
                  child: const Text('Como el prototipo'),
                ),
              ]),
              for (final (k, label, min, max, step, unit, dec) in _tune)
                Row(children: [
                  SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  Expanded(
                    child: Slider(
                      value: p[k].clamp(min, max).toDouble(),
                      min: min,
                      max: max,
                      divisions: ((max - min) / step).round(),
                      onChanged: (v) {
                        p[k] = v;
                        setSheet(() {});
                      },
                      onChangeEnd: (_) => unawaited(BenchStore.saveParams(p)),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('${p[k].toStringAsFixed(dec)}$unit',
                        textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ]),
            ]),
          ),
        );
      }),
    );
  }

  void _openLog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: paper,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(_log.isEmpty ? 'Sin eventos todavía.' : _log.join('\n'),
                style: const TextStyle(fontSize: 12, color: ink, height: 1.4)),
          ),
        ),
      ),
    );
  }
}
