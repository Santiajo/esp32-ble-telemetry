import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../balancin/core/app_clock.dart';
import '../../balancin/screens/lost_screen.dart';
import '../../balancin/session/board_session.dart' show LossCause, StickRole;
import '../../balancin/session/loss_monitor.dart';
import '../app_v2.dart';
import '../core/audio/layers.dart';
import '../core/levels.dart';
import '../core/light_model.dart';
import '../core/sync_engine.dart';
import '../platform/progress_store.dart';
import '../platform/tilt_stick.dart';
import '../widgets/two_halves_light.dart';
import 'final_screen.dart';

/// Dentro del eje (`#ejeView` del prototipo): solo luz en dos mitades.
///
/// Calibra el rango de cada persona al empezar (6 s, «muévanse libremente»),
/// juega el nivel o el modo Libre con los dos sticks reales y, al terminar
/// (nivel logrado, 30 s sin juego o «terminar»), guarda la sesión y pasa al
/// final. Si se pierde un stick, abre la pantalla de pérdida y la sesión sigue
/// al volver. Para terminar a mano: mantener 2 s la esquina superior derecha.
class PlayEjeScreen extends StatefulWidget {
  const PlayEjeScreen({super.key, required this.s, required this.mode, this.levelIndex = 0});
  final V2Services s;
  final PlayMode mode;
  final int levelIndex;

  @override
  State<PlayEjeScreen> createState() => _PlayEjeScreenState();
}

class _PlayEjeScreenState extends State<PlayEjeScreen> with TickerProviderStateMixin {
  late final SyncEngine _e;
  final AudioLayers _layers = AudioLayers();
  final Map<Role, TiltStick> _sticks = {};
  late final Ticker _ticker;
  late final AnimationController _flash = AnimationController(vsync: this);
  StreamSubscription<LossEvent>? _lossSub;
  List<int> _progress = [];
  bool _lostOpen = false;
  bool _closing = false;
  Timer? _exitHold;

  static StickRole _sr(Role r) => r == Role.adult ? StickRole.adult : StickRole.child;

  @override
  void initState() {
    super.initState();
    final s = widget.s;
    _e = SyncEngine(params: s.params, closeOnIdle: true, isLevelEnabled: enabledLevelIds.contains);
    for (final r in Role.values) {
      _sticks[r] = TiltStick(s.hub.ensureLink(_sr(r)), params: s.params);
      s.hub.arm(_sr(r));
    }
    _e.drive = (now) {
      for (final r in Role.values) {
        final st = _sticks[r]!;
        if (!st.stale(now)) _e.stick(r).feedTilt(st.reader.tiltX, st.reader.tiltY, _e.params);
      }
    };
    _lossSub = s.hub.lossEvents.listen(_onLoss);
    _ticker = createTicker((_) => _frame());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(WakelockPlus.enable());
    unawaited(_start());
  }

  Future<void> _start() async {
    _progress = await ProgressStore.progress();
    if (!mounted) return;
    final now = AppClock.nowMs();
    _layers
      ..resetChild()
      ..startPad(now);
    _handle(_e.start(mode: widget.mode, levelIndex: widget.levelIndex, calibrate: true, now: now), now);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _flash.dispose();
    _exitHold?.cancel();
    unawaited(_lossSub?.cancel());
    for (final r in Role.values) {
      widget.s.hub.disarm(_sr(r));
      _sticks[r]?.dispose();
    }
    _layers.silence();
    widget.s.audio.frame(_layers, 0.3);
    unawaited(widget.s.voice.stop());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void _frame() {
    final now = AppClock.nowMs();
    final a = widget.s.audio;
    a.notes(_layers.firePad(now, _e, _progress), now);
    _handle(_e.tick(now), now);
    if (_e.running) a.notes(_layers.update(now, _e.lastDt, _e), now);
    a.frame(_layers, _e.lastDt > 0 ? _e.lastDt : 1 / 60);
    if (mounted) setState(() {});
  }

  void _handle(List<SyncEvent> evs, double now) {
    final s = widget.s;
    s.audio.events(evs);
    for (final ev in evs) {
      switch (ev) {
        case SayEvent(:final text):
          unawaited(s.voice.say(text));
        case FlashEvent(:final long):
          _flash
            ..duration = Duration(milliseconds: long ? 4000 : 1600)
            ..forward(from: 0);
        case LevelCompletedEvent(:final levelId):
          if (!_progress.contains(levelId)) _progress.add(levelId);
          unawaited(ProgressStore.addProgress(levelId));
        case SessionClosedEvent(:final record):
          unawaited(_finish(record.levels, ev));
        default:
          break;
      }
    }
  }

  Future<void> _finish(List<int> fresh, SessionClosedEvent ev) async {
    if (_closing) return;
    _closing = true;
    _layers
      ..silence()
      ..stopPad();
    widget.s.audio.playClosing();
    await ProgressStore.addSession(ev.record);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => FinalScreen(s: widget.s, record: ev.record, fresh: fresh),
    ));
  }

  // ---------------------------------------------------------------------------
  // Pérdida de un stick
  // ---------------------------------------------------------------------------

  Future<void> _onLoss(LossEvent ev) async {
    if (!ev.lost || _lostOpen || _closing || !_e.running || !mounted) return;
    _lostOpen = true;
    final s = widget.s;
    _e.pause();
    _layers.silence();
    s.audio.fadeOutForLoss();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    var resumed = false;
    final res = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => LostScreen(
        hub: s.hub,
        role: ev.role,
        cause: LossCause.alcance,
        onResume: () => resumed = true,
      ),
    ));
    _lostOpen = false;
    if (!mounted) return;
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    final now = AppClock.nowMs();
    if (resumed || res == 'resumed') {
      s.audio.fadeInAfterLoss();
      _layers
        ..resetChild()
        ..startPad(now);
      _handle(_e.resume(now), now);
    } else {
      s.audio.fadeInAfterLoss();
      _handle(_e.close(now), now);
    }
  }

  // Esquina superior derecha: mantener 2 s para terminar.
  void _holdStart() {
    _exitHold?.cancel();
    _exitHold = Timer(const Duration(seconds: 2), () {
      final now = AppClock.nowMs();
      _handle(_e.close(now), now);
    });
  }

  void _holdEnd() => _exitHold?.cancel();

  @override
  Widget build(BuildContext context) {
    final now = AppClock.nowMs();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handle(_e.close(AppClock.nowMs()), AppClock.nowMs());
      },
      child: Scaffold(
        backgroundColor: TwoHalvesLight.night,
        body: Stack(children: [
          Positioned.fill(child: TwoHalvesLight(frame: lightFrame(_e, now))),
          // Destello al lograr el nivel (`#flash`): sube al 90 % en el primer 15 % y se apaga.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _flash,
                builder: (_, _) {
                  final t = _flash.value;
                  final o = !_flash.isAnimating && t == 0 ? 0.0 : (t < 0.15 ? t / 0.15 * 0.9 : 0.9 * (1 - (t - 0.15) / 0.85));
                  return Opacity(
                    opacity: o.clamp(0.0, 1.0),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(colors: [Color(0x598FA33E), Color(0xE68FA33E)]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            width: 96,
            height: 96,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _holdStart(),
              onTapUp: (_) => _holdEnd(),
              onTapCancel: _holdEnd,
              child: const Align(
                alignment: Alignment(0.4, -0.4),
                child: Icon(Icons.close, color: Color(0x14FFFFFF), size: 18),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
