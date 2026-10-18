import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/stick_state.dart';

/// Plano de sincronía con límite (plan v2 §5.2).
///
/// - El marco de ±6 es visible y todo se dibuja con un margen interior del
///   tamaño del punto más grande: ningún punto ni estela sale del lienzo.
/// - Si la inclinación supera el rango calibrado, el punto queda pegado al marco
///   y aparece una marca del color del rol en el borde, hacia donde se salió.
/// - Un stick sin datos (más de 1 s) se dibuja atenuado en su última posición.
class SyncPlane extends StatelessWidget {
  const SyncPlane({
    super.key,
    required this.adult,
    required this.child,
    required this.now,
    this.target,
    this.tol = 1.2,
    this.adultStale = false,
    this.childStale = false,
  });

  final StickState adult, child;
  final double now;

  /// Dónde debería estar el niño (zona objetivo), o `null` sin objetivo (Libre).
  final P2? target;
  final double tol;
  final bool adultStale, childStale;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _PlanePainter(this),
          child: const SizedBox.expand(),
        ),
      );
}

/// Conversión plano (−6..6) ↔ píxeles, con margen para que nada se salga.
class PlaneGeometry {
  PlaneGeometry(this.size, {this.margin = 22}); // punto (11) + marca de salida (6 + trazo)

  final Size size;
  final double margin;

  double get side => math.min(size.width, size.height);
  Offset get center => Offset(size.width / 2, size.height / 2);

  /// Píxeles por unidad del plano.
  double get k => (side / 2 - margin) / planeLimit;

  Offset toPx(double x, double y) {
    final cx = x.clamp(-planeLimit, planeLimit), cy = y.clamp(-planeLimit, planeLimit);
    return Offset(center.dx + cx * k, center.dy - cy * k);
  }

  Rect get frame => Rect.fromCenter(center: center, width: 2 * planeLimit * k, height: 2 * planeLimit * k);
}

class _PlanePainter extends CustomPainter {
  _PlanePainter(this.w);

  final SyncPlane w;

  static const Color ink = Color(0xFF2B2536);
  static const Color lila = Color(0xFF7B5FCB);
  static const Color coral = Color(0xFFE85E45);

  @override
  void paint(Canvas canvas, Size size) {
    final g = PlaneGeometry(size);
    canvas.clipRect(Offset.zero & size);
    final bg = Paint()..color = Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(g.frame.inflate(g.margin - 2), const Radius.circular(18)), bg);

    // Rejilla y ejes.
    final grid = Paint()
      ..color = ink.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(g.toPx(i.toDouble(), -6), g.toPx(i.toDouble(), 6), grid);
      canvas.drawLine(g.toPx(-6, i.toDouble()), g.toPx(6, i.toDouble()), grid);
    }
    final axes = Paint()
      ..color = ink.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    canvas.drawLine(g.toPx(0, -6), g.toPx(0, 6), axes);
    canvas.drawLine(g.toPx(-6, 0), g.toPx(6, 0), axes);

    // Marco del límite.
    canvas.drawRect(
      g.frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink.withValues(alpha: 0.45),
    );

    _trail(canvas, g, w.adult, lila, w.adultStale);
    _trail(canvas, g, w.child, coral, w.childStale);

    // Zona objetivo y distancia d.
    final t = w.target;
    if (t != null && w.adult.has) {
      final tp = g.toPx(t.x, t.y);
      canvas.drawCircle(tp, w.tol * g.k, Paint()..color = const Color(0xFFB3A2DC).withValues(alpha: 0.22));
      canvas.drawCircle(
        tp,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = lila,
      );
      if (w.child.has) {
        final cp = g.toPx(w.child.pos.x, w.child.pos.y);
        _dashed(canvas, cp, tp, Paint()
          ..color = coral
          ..strokeWidth = 2);
        final tpPainter = TextPainter(
          text: const TextSpan(text: 'd', style: TextStyle(color: coral, fontWeight: FontWeight.w800, fontSize: 13)),
          textDirection: TextDirection.ltr,
        )..layout();
        tpPainter.paint(canvas, Offset((cp.dx + tp.dx) / 2 + 6, (cp.dy + tp.dy) / 2 - 16));
      }
    }

    _dot(canvas, g, w.adult, lila, 11, w.adultStale);
    _dot(canvas, g, w.child, coral, 7.5, w.childStale);
  }

  void _trail(Canvas canvas, PlaneGeometry g, StickState st, Color c, bool stale) {
    if (!st.has || st.history.isEmpty) return;
    final path = Path();
    var first = true;
    for (final q in st.history) {
      if (w.now - q.t > 2000) continue;
      final p = g.toPx(q.x, q.y);
      if (first) {
        path.moveTo(p.dx, p.dy);
        first = false;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = c.withValues(alpha: stale ? 0.12 : 0.35),
    );
  }

  void _dot(Canvas canvas, PlaneGeometry g, StickState st, Color c, double r, bool stale) {
    if (!st.has) return;
    final p = g.toPx(st.pos.x, st.pos.y);
    canvas.drawCircle(p, r, Paint()..color = c.withValues(alpha: stale ? 0.3 : 1));
    if (stale) {
      canvas.drawCircle(
        p,
        r + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = c.withValues(alpha: 0.5),
      );
    }
    // Marca de salida: un arco sobre el marco hacia donde se pasó del rango.
    final o = st.overflow;
    if (o.x == 0 && o.y == 0) return;
    final dir = Offset(o.x, -o.y);
    final len = dir.distance;
    if (len == 0) return;
    final u = dir / len;
    final edge = p + u * (r + 6);
    final angle = math.atan2(u.dy, u.dx);
    canvas.drawArc(
      Rect.fromCircle(center: p, radius: r + 6),
      angle - 0.7,
      1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = c,
    );
    canvas.drawCircle(edge, 2, Paint()..color = c);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final u = d / len;
    for (var s = 0.0; s < len; s += 10) {
      canvas.drawLine(a + u * s, a + u * math.min(s + 5, len), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PlanePainter old) => true;
}
