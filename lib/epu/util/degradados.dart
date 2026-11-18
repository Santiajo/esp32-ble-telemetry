import 'package:flutter/widgets.dart';

/// Estira un degradado radial en un eje para convertir el círculo de Flutter
/// en la elipse de CSS (`radial-gradient(ellipse …)`).
///
/// Flutter mide el radio de [RadialGradient] sobre el lado más corto de la
/// caja y siempre dibuja un círculo. Con este transform el círculo se escala
/// por [sx] y [sy] alrededor del centro de la caja.
class EstirarDegradado extends GradientTransform {
  const EstirarDegradado(this.sx, this.sy);

  final double sx, sy;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.translationValues(c.dx, c.dy, 0)
      ..multiply(Matrix4.diagonal3Values(sx, sy, 1))
      ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0));
  }
}

/// Para `radial-gradient(ellipse at center, …)` sin tamaño (`farthest-corner`):
/// la elipse pasa por las esquinas y tiene la proporción de la caja.
/// Se usa con `RadialGradient(radius: .7071, transform: …)`.
GradientTransform elipseHastaEsquinas(Size caja) {
  final corto = caja.shortestSide;
  return EstirarDegradado(caja.width / corto, caja.height / corto);
}
