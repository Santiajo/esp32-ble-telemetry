import 'package:flutter/material.dart';
import 'package:esp32_ble_telemetry/controllers/esp_device_controller.dart';

/// CustomPainter para el Plano Cartesiano 2D de telemetría inercial.
///
/// Port directo del canvas 2D de `reference/legacy-web/app.js`:
/// - Cuadrícula técnica en pasos de 24 px
/// - Ejes de coordenadas centrales coloreados
/// - Escala fija de 4.0 px/cm
/// - Renderizado de halo difuso, núcleo circular y etiqueta para ESP A y ESP B.
class RadarCartesianPainter extends CustomPainter {
  final EspDeviceController dispA;
  final EspDeviceController dispB;
  static const double escalaPixeles = 4.0;

  RadarCartesianPainter({
    required this.dispA,
    required this.dispB,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fondo oscuro técnico
    final Rect rectFondo = Offset.zero & size;
    final Paint paintFondo = Paint()..color = const Color(0xFF0D0D0D);
    canvas.drawRect(rectFondo, paintFondo);

    final double centroX = size.width / 2.0;
    final double centroY = size.height / 2.0;

    // Cuadrícula sutil
    final Paint paintGrid = Paint()
      ..color = const Color(0xFF181818)
      ..strokeWidth = 1.0;

    for (double x = 0; x <= size.width; x += 24.0) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
    }
    for (double y = 0; y <= size.height; y += 24.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    // Ejes cartesianos principales
    final Paint paintEjes = Paint()
      ..color = const Color(0x3300FFCC)
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(0, centroY), Offset(size.width, centroY), paintEjes);
    canvas.drawLine(Offset(centroX, 0), Offset(centroX, size.height), paintEjes);

    // Dibujar punto para ESP B (si está conectado)
    if (dispB.conectado) {
      _dibujarPunto(canvas, dispB, centroX, centroY);
    }

    // Dibujar punto para ESP A (si está conectado)
    if (dispA.conectado) {
      _dibujarPunto(canvas, dispA, centroX, centroY);
    }
  }

  void _dibujarPunto(
    Canvas canvas,
    EspDeviceController d,
    double centroX,
    double centroY,
  ) {
    final double renderX = centroX + (d.visualX * escalaPixeles);
    final double renderY = centroY - (d.visualY * escalaPixeles);

    // Halo exterior difuso (15% de opacidad)
    final Paint paintHalo = Paint()
      ..color = d.color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(renderX, renderY), 14.0, paintHalo);

    // Núcleo circular sólido
    final Paint paintNucleo = Paint()
      ..color = d.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(renderX, renderY), 6.0, paintNucleo);

    // Borde blanco del núcleo
    final Paint paintBorde = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(renderX, renderY), 6.0, paintBorde);

    // Etiqueta de texto (A o B)
    final TextSpan span = TextSpan(
      text: d.etiqueta,
      style: TextStyle(
        color: d.color,
        fontSize: 12.0,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(renderX + 10.0, renderY - 14.0));
  }

  @override
  bool shouldRepaint(covariant RadarCartesianPainter oldDelegate) => true;
}
