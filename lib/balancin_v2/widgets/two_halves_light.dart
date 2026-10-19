import 'package:flutter/material.dart';

import '../core/light_model.dart';

/// Luz en dos mitades (plan v2 §4.7; `#ejeView` del prototipo): sobre fondo
/// noche, un degradado desde arriba (adulto) y otro desde abajo (niño), cada uno
/// del 42 % de la altura, sólido en su primer 22 %. Es lo que se ve desde los
/// bordes del teléfono puesto en el eje.
class TwoHalvesLight extends StatelessWidget {
  const TwoHalvesLight({super.key, required this.frame});

  final LightFrame frame;

  static const Color night = Color(0xFF1D1927);

  static Color _c(Rgb c, [double a = 1]) => Color.fromARGB((a * 255).round(), c.r, c.g, c.b);

  Widget _half(Rgb c, double opacity, {required bool top}) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [_c(c), _c(c), _c(c, 0)],
              stops: const [0, 0.22, 1],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: night,
        child: LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight * 0.42;
          return Stack(children: [
            Positioned(left: 0, right: 0, top: 0, height: h, child: _half(frame.top, frame.topOpacity, top: true)),
            Positioned(left: 0, right: 0, bottom: 0, height: h, child: _half(frame.bottom, frame.bottomOpacity, top: false)),
          ]);
        }),
      );
}
