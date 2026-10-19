import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../balancin/screens/home_screen.dart';
import '../app_v2.dart';
import '../core/telemetry.dart';
import '../platform/progress_store.dart';
import '../widgets/v2_ui.dart';
import 'audio_test_v2_screen.dart';
import 'bench_screen.dart';
import 'final_screen.dart';
import 'mode_screen.dart';

/// Inicio (`#home` del prototipo): «Jugar», sesiones pasadas, idea para hoy y
/// repasar la preparación. Abajo, las herramientas del equipo (banco, prueba de
/// audio y la app v1), que no son parte del flujo de las familias.
class HomeV2 extends StatefulWidget {
  const HomeV2({super.key, required this.s});
  final V2Services s;

  @override
  State<HomeV2> createState() => _HomeV2State();
}

class _HomeV2State extends State<HomeV2> {
  static const tips = [
    'Cuando el sonido deja de ondular, van juntos.',
    'Adulto: los gestos pequeños bastan; tu stick se ajusta a tu rango.',
    'En «Espejo», pónganse frente a frente.',
    'En «Sígueme», dejen que el niño invente primero.',
    'Lo logrado no se pierde: pueden volver otro día.',
  ];

  List<SessionRecord> _sessions = [];
  int _tip = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final s = await ProgressStore.sessions();
    if (mounted) setState(() => _sessions = s);
  }

  Future<void> _go(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    await _load();
  }

  /// La app v1 usa su propio motor de audio y sus propias conexiones: se sueltan
  /// los de v2 mientras está abierta y se recuperan al volver.
  Future<void> _openV1() async {
    final s = widget.s;
    s.hub.releaseAll();
    await s.audio.release();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
    await s.audio.init();
    await s.hub.reconnectSaved();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Theme(
      data: V2.theme,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            return ListView(padding: const EdgeInsets.fromLTRB(22, 24, 22, 28), children: [
              SizedBox(
                height: math.max(360, c.maxHeight * 0.75 - 60),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  PlaySphere(onTap: () => _go(ModeScreen(s: s))),
                  const SizedBox(height: 44),
                  const Text('Elijan un nivel y coloquen el celular en el eje', style: TextStyle(fontSize: 14, color: V2.soft, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 18),
              const Text('Sesiones pasadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: V2.ink)),
              const SizedBox(height: 10),
              if (_sessions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: const Text('Su primera sesión aparecerá aquí.', textAlign: TextAlign.center, style: V2.small),
                )
              else
                for (final r in _sessions.take(6)) ...[
                  _SessionRow(r: r, onTap: () => _go(FinalScreen(s: s, record: r, fresh: const [], fromHistory: true))),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                decoration: BoxDecoration(color: V2.yellow, borderRadius: BorderRadius.circular(22)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('IDEA PARA HOY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.3, color: V2.ink)),
                  const SizedBox(height: 6),
                  Text(tips[_tip], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3, color: V2.ink)),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: V2.ink),
                    onPressed: () => setState(() => _tip = (_tip + 1) % tips.length),
                    child: const Text('Otra idea', style: TextStyle(fontSize: 13, decoration: TextDecoration.underline, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Center(child: V2.link('Repasar la preparación', () => s.openOnboarding(context))),
              const SizedBox(height: 22),
              const Divider(color: V2.line),
              const SizedBox(height: 8),
              const Text('Herramientas del equipo', style: V2.kicker),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _tool('Banco de prueba', () async {
                  await _go(BenchScreen(hub: s.hub, audio: s.audio));
                  await s.reloadParams();
                }),
                _tool('Prueba de audio', () => _go(AudioTestV2Screen(audio: s.audio))),
                _tool('App v1 (tablero, diagnóstico BLE)', _openV1),
              ]),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _tool(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: V2.mute,
          side: const BorderSide(color: Color(0x332B2536)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
      );
}

/// Fila de «Sesiones pasadas» (`.hbS`).
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.r, required this.onTap});
  final SessionRecord r;
  final VoidCallback onTap;

  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];

  static String day(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    final s = '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final pct = (r.sync * 100).round();
    final lab = r.isFree
        ? 'Libre · $pct % juntos'
        : r.song
            ? 'Canción completa'
            : r.levels.isNotEmpty
                ? '${r.levels.length} ${r.levels.length == 1 ? 'parte' : 'partes'}'
                : 'Práctica';
    final mins = math.max(1, (r.dur / 60).round());
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('${day(r.t)} · $lab',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: V2.ink)),
              ),
              Text('$mins min', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: V2.mute)),
            ]),
            const SizedBox(height: 7),
            if (r.isFree)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: r.sync, minHeight: 8, color: V2.olive, backgroundColor: V2.paper),
              )
            else
              SongBar(got: r.levels, height: 8),
          ]),
        ),
      ),
    );
  }
}

/// Botón «Jugar»: esfera lila con cinco manchas de color que se mueven despacio (`.hbPlay`).
class PlaySphere extends StatefulWidget {
  const PlaySphere({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  State<PlaySphere> createState() => _PlaySphereState();
}

class _PlaySphereState extends State<PlaySphere> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = math.min(230.0, MediaQuery.of(context).size.width * 0.62);
    return Semantics(
      button: true,
      label: 'Jugar',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            ClipOval(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(size: Size.square(size), painter: _GasPainter(_c.value * 60)),
              ),
            ),
            const Text('Jugar',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, shadows: [
                  Shadow(color: Color(0x402B2536), blurRadius: 10, offset: Offset(0, 1)),
                ])),
          ]),
        ),
      ),
    );
  }
}

class _GasPainter extends CustomPainter {
  _GasPainter(this.t);
  final double t; // s

  // (color, alcance del degradado, período s, fase)
  static const _gas = [
    (Color(0xF2D6CCEE), 0.55, 9.0, 0.0),
    (Color(0xF2F4C3B6), 0.50, 10.5, 1.3),
    (Color(0xB3F2E44A), 0.46, 13.0, 2.1),
    (Color(0x8CE85E45), 0.44, 14.0, 3.7),
    (Color(0xCC7B5FCB), 0.52, 10.0, 0.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = V2.lila);
    final w = size.width;
    for (final (col, reach, period, ph) in _gas) {
      final a = 2 * math.pi * t / period + ph;
      final center = Offset(w / 2 + w * 0.24 * math.sin(a), w / 2 + w * 0.22 * math.cos(a * 0.8 + ph));
      final scale = 1 + 0.15 * math.sin(a * 1.3);
      final r = w * 1.4 / 2 * scale;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)], stops: [0, reach])
              .createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GasPainter old) => old.t != t;
}
