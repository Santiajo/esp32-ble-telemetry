import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tema/colores.dart';
import '../util/svg.dart';

/// Logo «Epu» dibujado con código, idéntico a `logo-epu.svg`
/// (viewBox −6 −10 218 150).
///
/// Se dibuja en vez de cargar el SVG para no sumar un paquete de SVG: son
/// 3 grupos de trazos de 19 unidades con remates redondos.
class LogoEpu extends StatelessWidget {
  /// Por alto (el Home y la bienvenida lo usan a 34 px).
  const LogoEpu.alto(this.alto, {super.key}) : ancho = null;

  /// Por ancho (el inicio lo usa a 150 px).
  const LogoEpu.ancho(double this.ancho, {super.key}) : alto = null;

  static const double _vbAncho = 218, _vbAlto = 150;

  final double? alto;
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final w = ancho ?? alto! * _vbAncho / _vbAlto;
    final h = alto ?? ancho! * _vbAlto / _vbAncho;
    return Semantics(
      label: 'Epu',
      image: true,
      child: CustomPaint(size: Size(w, h), painter: const _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / LogoEpu._vbAncho)
      ..translate(6, 10); // origen del viewBox en (−6, −10)

    // `transform="translate(tx,ty) rotate(a cx cy)"`
    void grupo(double ty, double grados, double cx, double cy, void Function() dibujar) {
      canvas
        ..save()
        ..translate(0, ty)
        ..translate(cx, cy)
        ..rotate(grados * math.pi / 180)
        ..translate(-cx, -cy);
      dibujar();
      canvas.restore();
    }

    // E · lila
    grupo(-2.8, -1.8, 36, 70, () {
      final p = trazoSvg(EpuColores.logoLila, 19);
      canvas
        ..drawLine(const Offset(15, 17), const Offset(15, 99), p)
        ..drawLine(const Offset(15, 17), const Offset(55, 17), p)
        ..drawLine(const Offset(15, 58), const Offset(48, 58), p)
        ..drawLine(const Offset(15, 99), const Offset(55, 99), p);
    });

    // p · verde
    grupo(-3.4, 1.5, 101, 70, () {
      final p = trazoSvg(EpuColores.logoVerde, 19);
      canvas
        ..drawLine(const Offset(81, 41), const Offset(81, 126), p)
        ..drawPath(trazadoSvg('M101.0,52.0 A20,20 0 1 1 101.0,92.0 A20,20 0 1 1 101.0,52.0 Z'), p);
    });

    // u · coral, con el punto amarillo
    grupo(-1.1, .4, 166, 70, () {
      canvas
        ..drawPath(
          trazadoSvg('M145.0,40.0 L145.0,70 A21,21 0 0 0 187.0,70 L187.0,40.0'),
          trazoSvg(EpuColores.logoCoral, 19),
        )
        ..drawCircle(const Offset(166, 19), 8.7, rellenoSvg(EpuColores.logoAmarillo));
    });

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
