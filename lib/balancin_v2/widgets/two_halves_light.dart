import 'package:flutter/material.dart';

import '../core/light_model.dart';

/// Luz en dos mitades (plan v2 §4.7): arriba el adulto, abajo el niño, sobre
/// negro. Lo que se ve desde los bordes del teléfono puesto en el eje.
class TwoHalvesLight extends StatelessWidget {
  const TwoHalvesLight({super.key, required this.frame});

  final LightFrame frame;

  static Color _c(Rgb c, double opacity) =>
      Color.fromARGB((opacity.clamp(0.0, 1.0) * 255).round(), c.r, c.g, c.b);

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Column(children: [
          Expanded(child: ColoredBox(color: _c(frame.top, frame.topOpacity), child: const SizedBox.expand())),
          Expanded(child: ColoredBox(color: _c(frame.bottom, frame.bottomOpacity), child: const SizedBox.expand())),
        ]),
      );
}
