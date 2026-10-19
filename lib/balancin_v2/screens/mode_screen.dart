import 'dart:async';

import 'package:flutter/material.dart';

import '../app_v2.dart';
import '../core/levels.dart';
import '../core/sync_engine.dart';
import '../platform/progress_store.dart';
import '../widgets/v2_ui.dart';
import 'insert_v2_screen.dart';
import 'levels_screen.dart';

/// «¿Cómo quieren jugar?» (`#mode` del prototipo): Libre o Niveles.
class ModeScreen extends StatefulWidget {
  const ModeScreen({super.key, required this.s});
  final V2Services s;

  @override
  State<ModeScreen> createState() => _ModeScreenState();
}

class _ModeScreenState extends State<ModeScreen> {
  List<int> _got = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final g = await ProgressStore.progress();
    if (mounted) setState(() => _got = g);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Theme(
      data: V2.theme,
      child: Scaffold(
        appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('¿Cómo quieren jugar?', textAlign: TextAlign.center, style: V2.h1()),
              const SizedBox(height: 16),
              Expanded(
                child: _card(
                  art: const _FreeArt(),
                  title: 'Libre',
                  text: 'Sin consignas. El sonido se afina cuando encuentran un movimiento en común.',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => InsertV2Screen(s: s, mode: PlayMode.free),
                  )),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _card(
                  art: _LevelsArt(got: _got),
                  title: 'Niveles',
                  text: 'Siete movimientos en pareja. Cada uno suma una parte de la canción.',
                  extra: '${_got.length} de 7 partes de la canción',
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LevelsScreen(s: s)));
                    await _load();
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget art, required String title, required String text, String? extra, required VoidCallback onTap}) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // El dibujo cede espacio al texto en teléfonos bajos.
              Flexible(child: ClipRect(child: SizedBox(height: 96, child: art))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1, color: V2.ink)),
                const SizedBox(height: 6),
                Text(text, style: const TextStyle(fontSize: 14, color: V2.soft, fontWeight: FontWeight.w600)),
                if (extra != null) ...[
                  const SizedBox(height: 8),
                  Text(extra, style: const TextStyle(fontSize: 13, color: V2.mute, fontWeight: FontWeight.w800)),
                ],
              ]),
            ]),
          ),
        ),
      );
}

/// Dos cápsulas inclinadas y una onda punteada (`.mdArt.free`).
class _FreeArt extends StatelessWidget {
  const _FreeArt();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(children: [
          Positioned(
            left: w * 0.06,
            top: 14,
            child: Transform.rotate(
              angle: -14 * 3.14159 / 180,
              child: Container(width: 22, height: 70, decoration: BoxDecoration(color: V2.lila, borderRadius: BorderRadius.circular(999))),
            ),
          ),
          Positioned(
            left: w * 0.24,
            top: 36,
            child: Transform.rotate(
              angle: 18 * 3.14159 / 180,
              child: Container(width: 16, height: 50, decoration: BoxDecoration(color: V2.coral, borderRadius: BorderRadius.circular(999))),
            ),
          ),
          Positioned(left: w * 0.42, top: 30, width: w * 0.52, height: 36, child: CustomPaint(painter: _DashArc())),
        ]);
      });
}

class _DashArc extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x402B2536);
    final path = Path()..addArc(Rect.fromLTWH(0, 0, size.width, size.height * 2), 3.14159, 3.14159);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Siete barras crecientes, encendidas las partes logradas (`.mdArt.lv`).
class _LevelsArt extends StatelessWidget {
  const _LevelsArt({required this.got});
  final List<int> got;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 36),
              child: Container(
                height: 24.0 + i * 12,
                decoration: BoxDecoration(
                  color: got.contains(levels[i].id) ? V2.olive : V2.line,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10), bottom: Radius.circular(5)),
                ),
              ),
            ),
          ),
        ],
      ]);
}
