import 'package:flutter/material.dart';

/// CustomPainter para un osciloscopio de ondas en tiempo real.
///
/// Port directo de la clase `WaveGraph` de `reference/legacy-web/app.js`:
/// - Línea central de referencia
/// - Curvas Bézier cuadráticas continuas para graficar datos de A y B superpuestos
/// - Escala configurable por métrica
class OscilloscopePainter extends CustomPainter {
  final List<double> datosA;
  final List<double> datosB;
  final Color colorA;
  final Color colorB;
  final double escala;
  final bool mostrarB;

  OscilloscopePainter({
    required this.datosA,
    required this.datosB,
    required this.colorA,
    required this.colorB,
    required this.escala,
    this.mostrarB = true,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fondo oscuro
    final Paint paintFondo = Paint()..color = const Color(0xFF0F0F0F);
    canvas.drawRect(Offset.zero & size, paintFondo);

    final double centroY = size.height * 0.75; // Línea base en 75% de altura para métricas positivas

    // Línea central / base
    final Paint paintEje = Paint()
      ..color = const Color(0xFF222222)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, centroY), Offset(size.width, centroY), paintEje);

    // Trazar onda B (Naranja) si está habilitada
    if (mostrarB && datosB.isNotEmpty) {
      _trazarOnda(canvas, size, datosB, colorB, centroY);
    }

    // Trazar onda A (Turquesa)
    if (datosA.isNotEmpty) {
      _trazarOnda(canvas, size, datosA, colorA, centroY);
    }
  }

  void _trazarOnda(
    Canvas canvas,
    Size size,
    List<double> datos,
    Color color,
    double centroY,
  ) {
    if (datos.length < 2) return;

    final Paint paintOnda = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final Path path = Path();
    final double pasoX = size.width / (datos.length - 1);

    for (int i = 0; i < datos.length; i++) {
      final double x = i * pasoX;
      final double y = (centroY - (datos[i] * escala)).clamp(4.0, size.height - 4.0);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final double prevX = (i - 1) * pasoX;
        final double prevY =
            (centroY - (datos[i - 1] * escala)).clamp(4.0, size.height - 4.0);
        final double midX = (prevX + x) / 2.0;
        final double midY = (prevY + y) / 2.0;
        path.quadraticBezierTo(prevX, prevY, midX, midY);
      }
    }

    canvas.drawPath(path, paintOnda);
  }

  @override
  bool shouldRepaint(covariant OscilloscopePainter oldDelegate) => true;
}
