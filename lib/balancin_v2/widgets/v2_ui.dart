import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/levels.dart';

/// Paleta y piezas visuales compartidas del flujo v2 (CSS del prototipo).
abstract final class V2 {
  static const Color paper = Color(0xFFEFECE4);
  static const Color ink = Color(0xFF2B2536);
  static const Color soft = Color(0xFF4A445A);
  static const Color mute = Color(0xFF5A536B);
  static const Color lila = Color(0xFFB3A2DC);
  static const Color lilaInk = Color(0xFF9F8AD9);
  static const Color coral = Color(0xFFE85E45);
  static const Color coralSoft = Color(0xFFF4C3B6);
  static const Color yellow = Color(0xFFF2E44A);
  static const Color olive = Color(0xFF7A8B34);
  static const Color line = Color(0xFFDCD8CF);
  static const Color night = Color(0xFF1D1927);

  static final ThemeData theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ink, brightness: Brightness.light),
    scaffoldBackgroundColor: paper,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.6, height: 1.05, color: ink),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink),
      bodyMedium: TextStyle(fontSize: 15, color: soft, fontWeight: FontWeight.w600),
    ),
  );

  static TextStyle h1([double size = 32]) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -0.6, height: 1.05, color: ink);
  static const TextStyle h2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink);
  static const TextStyle sub = TextStyle(fontSize: 15, color: soft, fontWeight: FontWeight.w600);
  static const TextStyle small = TextStyle(fontSize: 13, color: mute, fontWeight: FontWeight.w700);
  static const TextStyle kicker = TextStyle(fontSize: 13, color: mute, fontWeight: FontWeight.w800);

  /// Botón principal oscuro (`button.primary`).
  static Widget primary(String label, VoidCallback? onTap, {double height = 58}) => SizedBox(
        height: height,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      );

  /// Botón blanco con borde (`button`).
  static Widget secondary(String label, VoidCallback? onTap, {double height = 56}) => SizedBox(
        height: height,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: ink,
            side: const BorderSide(color: Color(0x402B2536), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      );

  /// Enlace subrayado (`.link`).
  static Widget link(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(fontSize: 14, color: mute, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
      );
}

/// Barra de la canción: 7 partes, las logradas en oliva y las recién logradas con anillo.
class SongBar extends StatelessWidget {
  const SongBar({super.key, required this.got, this.fresh = const [], this.height = 10});

  final List<int> got;
  final List<int> fresh;
  final double height;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _seg(levels[i].id)),
        ],
      ]);

  Widget _seg(int id) {
    final on = got.contains(id) || fresh.contains(id);
    final isNew = fresh.contains(id);
    final bar = Container(
      height: height,
      decoration: BoxDecoration(color: on ? V2.olive : V2.line, borderRadius: BorderRadius.circular(height / 2)),
    );
    if (!isNew) return bar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: V2.olive, width: 2),
      ),
      child: bar,
    );
  }
}

/// Pictograma de un nivel (`pict()` del prototipo, viewBox 120×100): stick grande
/// lila, stick pequeño coral y flechas del color de cada uno. Sin figuras humanas.
class LevelPictogram extends StatelessWidget {
  const LevelPictogram({super.key, required this.level, this.width = 84, this.locked = false});

  final Level level;
  final double width;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final w = SizedBox(width: width, height: width * 100 / 120, child: CustomPaint(painter: _PictPainter(level)));
    if (!locked) return w;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: w,
    );
  }
}

class _PictPainter extends CustomPainter {
  _PictPainter(this.level);
  final Level level;

  static const Color ca = Color(0xFF9F8AD9), cc = Color(0xFFE85E45), co = Color(0xFF7A8B34);
  static const Color ck = Color(0x472B2536);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 120, size.height / 100);
    if (level.relation == Relation.song) {
      _note(canvas);
      return;
    }
    _sticks(canvas);
    switch (level.relation) {
      case Relation.together:
        _line(canvas, 18, 70, 18, 32, ca, dbl: true);
        _line(canvas, 104, 84, 104, 52, cc, dbl: true);
      case Relation.seesaw:
        _line(canvas, 18, 68, 18, 30, ca);
        _line(canvas, 104, 54, 104, 88, cc);
      case Relation.mirror:
        _dash(canvas, const Offset(62, 10), const Offset(62, 94), Paint()
          ..color = ck
          ..strokeWidth = 2, 3, 5);
        _arc(canvas, 26, 20, 40, 6, 54, 18, ca);
        _arc(canvas, 72, 42, 84, 30, 98, 42, cc);
      case Relation.same:
        _arc(canvas, 54, 18, 40, 6, 26, 20, ca);
        _arc(canvas, 72, 42, 84, 30, 98, 42, cc);
      case Relation.pulse:
        _arc(canvas, 26, 20, 40, 6, 54, 18, ca, dbl: true);
        _arc(canvas, 72, 42, 84, 30, 98, 42, cc, dbl: true);
        final m = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = V2.ink;
        canvas.drawPath(Path()..moveTo(62, 14)..lineTo(55, 40)..lineTo(69, 40)..close(), m);
        canvas.drawLine(const Offset(62, 36), const Offset(66, 17), m);
      case Relation.follow:
        final childGuides = level.guides.first == Role.child;
        _wave(canvas, 20, 16, ca, dashed: childGuides);
        _wave(canvas, 66, 36, cc, dashed: !childGuides);
      default:
        break;
    }
  }

  void _sticks(Canvas c) {
    final a = Paint()..color = const Color(0xFFB3A2DC), k = Paint()..color = cc;
    c.drawRRect(RRect.fromLTRBR(35, 44, 45, 90, const Radius.circular(5)), a);
    c.drawRRect(RRect.fromLTRBR(30, 26, 50, 52, const Radius.circular(10)), a);
    c.drawRRect(RRect.fromLTRBR(80.5, 60, 87.5, 90, const Radius.circular(3.5)), k);
    c.drawRRect(RRect.fromLTRBR(77, 49, 91, 67, const Radius.circular(7)), k);
  }

  Paint _stroke(Color col) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..color = col;

  void _head(Canvas c, double x, double y, double ang, Color col) {
    const s = 7.0;
    c.drawPath(
      Path()
        ..moveTo(x, y)
        ..lineTo(x - s * math.cos(ang - 0.45), y - s * math.sin(ang - 0.45))
        ..lineTo(x - s * math.cos(ang + 0.45), y - s * math.sin(ang + 0.45))
        ..close(),
      Paint()..color = col,
    );
  }

  void _line(Canvas c, double x1, double y1, double x2, double y2, Color col, {bool dbl = false}) {
    c.drawLine(Offset(x1, y1), Offset(x2, y2), _stroke(col));
    _head(c, x2, y2, math.atan2(y2 - y1, x2 - x1), col);
    if (dbl) _head(c, x1, y1, math.atan2(y1 - y2, x1 - x2), col);
  }

  void _arc(Canvas c, double x1, double y1, double cx, double cy, double x2, double y2, Color col, {bool dbl = false}) {
    c.drawPath(Path()..moveTo(x1, y1)..quadraticBezierTo(cx, cy, x2, y2), _stroke(col));
    _head(c, x2, y2, math.atan2(y2 - cy, x2 - cx), col);
    if (dbl) _head(c, x1, y1, math.atan2(y1 - cy, x1 - cx), col);
  }

  void _wave(Canvas c, double x, double y, Color col, {bool dashed = false}) {
    // M x y q6 −9 12 0 t12 0 t10 0
    final path = Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + 6, y - 9, x + 12, y)
      ..quadraticBezierTo(x + 18, y + 9, x + 24, y)
      ..quadraticBezierTo(x + 30, y - 9, x + 34, y);
    if (dashed) {
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 9) {
          c.drawPath(m.extractPath(d, math.min(d + 4, m.length)), _stroke(col));
        }
      }
    } else {
      c.drawPath(path, _stroke(col));
    }
    _head(c, x + 34, y, 0, col);
  }

  void _dash(Canvas c, Offset a, Offset b, Paint p, double on, double off) {
    final d = b - a, len = d.distance, u = d / len;
    for (var s = 0.0; s < len; s += on + off) {
      c.drawLine(a + u * s, a + u * math.min(s + on, len), p);
    }
  }

  void _note(Canvas c) {
    final p = Paint()..color = co;
    c.save();
    c.translate(52, 72);
    c.rotate(-20 * math.pi / 180);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 30, height: 21), p);
    c.restore();
    c.drawRRect(RRect.fromLTRBR(63, 18, 67.5, 70, const Radius.circular(2)), p);
    c.drawPath(
      Path()
        ..moveTo(67.5, 18)
        ..cubicTo(74, 26, 86, 30, 84, 46)
        ..cubicTo(82, 38, 76, 34, 67.5, 32)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _PictPainter old) => old.level.id != level.id;
}

/// El recuerdo: las trayectorias de los dos sobre el plano (`memoSVG` del prototipo).
class MemoDrawing extends StatelessWidget {
  const MemoDrawing({super.key, required this.traj});

  /// `[adulto x, adulto y, niño x, niño y]` por punto.
  final List<List<double>> traj;

  @override
  Widget build(BuildContext context) => AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _MemoPainter(traj)));
}

class _MemoPainter extends CustomPainter {
  _MemoPainter(this.traj);
  final List<List<double>> traj;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 13.2;
    Offset at(double x, double y) => Offset((x + 6.6) * k, (-y + 6.6) * k);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(k)), Paint()..color = Colors.white);
    final grid = Paint()
      ..color = V2.paper
      ..strokeWidth = 0.05 * k;
    for (var i = -6; i <= 6; i += 2) {
      canvas.drawLine(at(i.toDouble(), -6), at(i.toDouble(), 6), grid);
      canvas.drawLine(at(-6, i.toDouble()), at(6, i.toDouble()), grid);
    }
    void poly(int ix, int iy, Color col, double w) {
      if (traj.isEmpty) return;
      final path = Path()..moveTo(at(traj.first[ix], traj.first[iy]).dx, at(traj.first[ix], traj.first[iy]).dy);
      for (final p in traj.skip(1)) {
        final o = at(p[ix], p[iy]);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * k
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = col.withValues(alpha: 0.9),
      );
    }

    poly(0, 1, V2.lilaInk, 0.16);
    poly(2, 3, V2.coral, 0.11);
  }

  @override
  bool shouldRepaint(covariant _MemoPainter old) => old.traj != traj;
}

/// Cápsula de quién guía (`.guide`).
class GuideChip extends StatelessWidget {
  const GuideChip({super.key, required this.level});
  final Level level;

  @override
  Widget build(BuildContext context) {
    final song = level.isSong;
    final first = level.guides.first;
    final bg = song ? Colors.white : (first == Role.child ? V2.coralSoft : V2.lila);
    final dot = song
        ? Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [V2.lila, V2.lila, V2.coral, V2.coral], stops: [0, .5, .5, 1]),
            ),
          )
        : Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: first == Role.child ? V2.coral : V2.ink),
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        dot,
        const SizedBox(width: 8),
        Flexible(child: Text(level.guideText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: V2.ink))),
      ]),
    );
  }
}
