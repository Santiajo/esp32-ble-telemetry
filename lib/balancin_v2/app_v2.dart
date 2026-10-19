import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../balancin/platform/stick_hub.dart';
import '../balancin/screens/onboarding/onboarding_screen.dart';
import 'core/params.dart';
import 'platform/audio_engine_v2.dart';
import 'platform/bench_store.dart';
import 'platform/progress_store.dart';
import 'platform/voice_prompts.dart';
import 'screens/home_v2.dart';
import 'screens/levels_screen.dart';
import 'widgets/v2_ui.dart';

/// Lo que comparten todas las pantallas del flujo v2: un solo dueño de las
/// conexiones a los sticks, un solo motor de audio, la voz y los parámetros
/// (los del banco: lo que se afina ahí vale para el juego).
class V2Services {
  V2Services({required this.hub, required this.audio, required this.voice, required this.params});

  final StickHub hub;
  final AudioEngineV2 audio;
  final VoicePrompts voice;
  final SyncParams params;

  /// Vuelve a leer los parámetros guardados por el banco (al volver de él).
  Future<void> reloadParams() async {
    final p = await BenchStore.loadParams();
    for (final k in SyncParams.keys) {
      params[k] = p[k];
    }
    voice.enabled = await BenchStore.loadVoice();
  }

  /// Preparación (5 pasos de v1, con vinculación real de los sticks). Al terminar,
  /// como en el prototipo, va a la lista de niveles.
  void openOnboarding(BuildContext context, {bool replace = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => OnboardingScreen(
        hub: hub,
        onChime: audio.playChime,
        onFinished: (ctx) async {
          await ProgressStore.setOnboarded();
          if (!ctx.mounted) return;
          Navigator.of(ctx).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => HomeV2(s: this)),
            (_) => false,
          );
          Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => LevelsScreen(s: this)));
        },
      ),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }
}

/// Entrada de la app v2 (plan v2 §7, fase 6). Sin inicio de sesión con Google
/// (decisión V2): la primera vez abre la preparación; después, el inicio.
class BalancinV2Root extends StatefulWidget {
  const BalancinV2Root({super.key});

  @override
  State<BalancinV2Root> createState() => _BalancinV2RootState();
}

class _BalancinV2RootState extends State<BalancinV2Root> {
  V2Services? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final params = await BenchStore.loadParams();
      final voice = VoicePrompts(enabled: await BenchStore.loadVoice());
      final s = V2Services(hub: StickHub(), audio: AudioEngineV2(), voice: voice, params: params);
      await Future.wait([s.audio.init(), voice.init()]);
      unawaited(_reconnect(s.hub));
      final onboarded = await ProgressStore.onboarded();
      if (!mounted) return;
      setState(() => _s = s);
      if (!onboarded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) s.openOnboarding(context, replace: true);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Reconecta los sticks vinculados si ya hay permiso (no lo pide aquí: lo pide la preparación).
  Future<void> _reconnect(StickHub hub) async {
    try {
      if (!Platform.isAndroid || await Permission.bluetoothConnect.isGranted) await hub.reconnectSaved();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s != null) return HomeV2(s: s);
    return Theme(
      data: V2.theme,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _Brand(),
              const SizedBox(height: 18),
              Text(_error == null ? 'Preparando sonidos…' : 'No se pudo iniciar el audio:\n$_error',
                  textAlign: TextAlign.center, style: V2.sub),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Las cuatro formas de la marca (`.brand`): cuadrado lila, círculos coral y amarillo, triángulo oliva.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: V2.lila, borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 12),
        Container(width: 34, height: 34, decoration: const BoxDecoration(color: V2.coral, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Container(width: 34, height: 34, decoration: const BoxDecoration(color: V2.yellow, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        ClipPath(clipper: _Tri(), child: Container(width: 34, height: 34, color: V2.olive)),
      ]);
}

class _Tri extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width / 2, s.height * 0.04)
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
