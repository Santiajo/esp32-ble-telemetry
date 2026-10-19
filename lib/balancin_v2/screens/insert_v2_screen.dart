import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_v2.dart';
import '../core/levels.dart';
import '../core/sync_engine.dart';
import '../widgets/v2_ui.dart';
import 'play_eje_screen.dart';

/// «Coloca el celular en el eje» (`#insert` del prototipo): animación del
/// teléfono entrando al eje, barra de 6 s y transición circular («iris») al juego.
class InsertV2Screen extends StatefulWidget {
  const InsertV2Screen({super.key, required this.s, required this.mode, this.levelIndex = 0});
  final V2Services s;
  final PlayMode mode;
  final int levelIndex;

  @override
  State<InsertV2Screen> createState() => _InsertV2ScreenState();
}

class _InsertV2ScreenState extends State<InsertV2Screen> with TickerProviderStateMixin {
  static const Duration wait = Duration(seconds: 6);
  late final AnimationController _scene = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _bar = AnimationController(vsync: this, duration: wait)..forward();
  late final AnimationController _iris = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _bar.addStatusListener((st) {
      if (st == AnimationStatus.completed) unawaited(_go());
    });
  }

  Future<void> _go() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    await _iris.forward();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => PlayEjeScreen(s: widget.s, mode: widget.mode, levelIndex: widget.levelIndex),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _scene.dispose();
    _bar.dispose();
    _iris.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.mode == PlayMode.levels ? levels[widget.levelIndex] : null;
    return Theme(
      data: V2.theme,
      child: Stack(children: [
        Scaffold(
          appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.44),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    alignment: Alignment.center,
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: AnimatedBuilder(animation: _scene, builder: (_, _) => _Scene(t: _scene.value)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Coloca el celular en el eje',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.1, color: V2.ink)),
                const SizedBox(height: 6),
                const SizedBox(
                  width: 300,
                  child: Text('Pantalla hacia adentro. Solo los bordes quedan a la vista.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: V2.soft)),
                ),
                const SizedBox(height: 8),
                Text(l == null ? 'Modo libre' : 'Nivel ${l.id} · ${l.name}', style: V2.kicker),
                const SizedBox(height: 16),
                SizedBox(
                  width: 300,
                  child: AnimatedBuilder(
                    animation: _bar,
                    builder: (_, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: _bar.value, minHeight: 8, color: V2.ink, backgroundColor: V2.line),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        // Iris: un círculo oscuro que crece desde el centro hasta cubrir todo.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _iris,
            builder: (context, _) {
              final v = Curves.easeInOutCubic.transform(_iris.value);
              if (v == 0) return const SizedBox.shrink();
              final size = MediaQuery.of(context).size;
              final r = v * 0.8 * math.sqrt(size.width * size.width + size.height * size.height);
              return ClipPath(clipper: _Circle(r), child: Container(color: V2.night));
            },
          ),
        ),
      ]),
    );
  }
}

class _Circle extends CustomClipper<Path> {
  _Circle(this.r);
  final double r;
  @override
  Path getClip(Size s) => Path()..addOval(Rect.fromCircle(center: s.center(Offset.zero), radius: r));
  @override
  bool shouldReclip(covariant _Circle old) => old.r != r;
}

/// Escena 300×300: el teléfono baja 130 px al eje y se encienden las dos luces (`.insscene`).
class _Scene extends StatelessWidget {
  const _Scene({required this.t});
  final double t; // 0–1 del ciclo de 2,6 s

  @override
  Widget build(BuildContext context) {
    // ins: quieto hasta el 15 %, baja hasta el 55 %, queda abajo. lt: aparece entre 55 % y 75 %.
    final down = Curves.easeInOut.transform(((t - 0.15) / 0.40).clamp(0.0, 1.0));
    final light = ((t - 0.55) / 0.20).clamp(0.0, 1.0);
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(children: [
        Positioned(
          left: 10,
          bottom: 40,
          child: Container(
            width: 280,
            height: 124,
            decoration: BoxDecoration(color: const Color(0xFFD9D5CE), borderRadius: BorderRadius.circular(48)),
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 42,
                top: -10,
                child: Container(width: 196, height: 72, decoration: BoxDecoration(color: V2.ink, borderRadius: BorderRadius.circular(16))),
              ),
              Positioned(
                left: 22,
                bottom: 16,
                child: Opacity(
                  opacity: light,
                  child: Container(width: 60, height: 22, decoration: BoxDecoration(color: V2.lila, borderRadius: BorderRadius.circular(11))),
                ),
              ),
              Positioned(
                right: 22,
                bottom: 16,
                child: Opacity(
                  opacity: light,
                  child: Container(width: 60, height: 22, decoration: BoxDecoration(color: V2.coral, borderRadius: BorderRadius.circular(11))),
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 62,
          top: 130 * down,
          child: Container(width: 176, height: 56, decoration: BoxDecoration(color: V2.mute, borderRadius: BorderRadius.circular(14))),
        ),
      ]),
    );
  }
}
