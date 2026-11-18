import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Traducciones de CSS a Flutter que se repiten en todo el paquete.
///
/// La regla de oro: los números (duraciones, retrasos, curvas, tamaños,
/// opacidades) se copian tal cual del prototipo. Lo que cambia entre CSS y
/// Flutter está resuelto aquí, una sola vez.

// ── Curvas ─────────────────────────────────────────────────────────────────
// `cubic-bezier(a,b,c,d)` de CSS es exactamente `Cubic(a,b,c,d)` en Flutter.
// Las palabras clave de CSS también tienen su equivalente exacto:
//   ease        → Curves.ease        (= cubic-bezier(.25,.1,.25,1))
//   ease-in-out → Curves.easeInOut   (= cubic-bezier(.42,0,.58,1))
//   ease-out    → Curves.easeOut     (= cubic-bezier(0,0,.58,1))
//   linear      → Curves.linear
class CurvasEpu {
  CurvasEpu._();

  /// `cubic-bezier(.2,.8,.2,1)`: entradas con rebote suave (pop).
  static const pop = Cubic(.2, .8, .2, 1);

  /// `cubic-bezier(.4,0,.2,1)`: desplazamientos (luces del juego, Prep 4).
  static const mover = Cubic(.4, 0, .2, 1);

  /// `cubic-bezier(.65,0,.35,1)`: cortinas (círculo que cubre, logo que baja).
  static const cortina = Cubic(.65, 0, .35, 1);

  /// `cubic-bezier(.2,.7,.3,1)`: entrada de las flechas de movimiento.
  static const flecha = Cubic(.2, .7, .3, 1);
}

// ── Sombras y desenfoques ──────────────────────────────────────────────────
/// En CSS, el desenfoque de `box-shadow` y `text-shadow` es un *radio* y la
/// desviación estándar real es la mitad. Flutter convierte su `blurRadius` con
/// `sigma = radio × 0,57735 + 0,5`. Esta función devuelve el `blurRadius` de
/// Flutter que da la misma sigma que el radio de CSS.
double radioDesenfoqueCss(double radioCss) {
  if (radioCss <= 0) return 0;
  return math.max(0, (radioCss / 2 - .5) / .57735);
}

/// `box-shadow: x y blur spread color` de CSS.
BoxShadow sombraCss(
  double x,
  double y,
  double blur,
  Color color, {
  double spread = 0,
}) =>
    BoxShadow(
      offset: Offset(x, y),
      blurRadius: radioDesenfoqueCss(blur),
      spreadRadius: spread,
      color: color,
    );

/// `text-shadow: x y blur color` de CSS.
Shadow sombraTextoCss(double x, double y, double blur, Color color) =>
    Shadow(offset: Offset(x, y), blurRadius: radioDesenfoqueCss(blur), color: color);

/// Sombra de los botones «Atrás» (`0 2px 10px rgba(43,37,54,.1)`).
final sombraBotonAtras = sombraCss(0, 2, 10, const Color.fromRGBO(43, 37, 54, .1));

// ── Animaciones con retraso ───────────────────────────────────────────────
/// Una animación CSS `nombre duración curva retraso both` se arma con un solo
/// [AnimationController] de duración `retraso + duración` y este intervalo.
/// Antes del retraso vale 0 (el estado `from`, porque el fill es `both`) y al
/// terminar se queda en 1 (el estado `to`).
Animation<double> tramoCss(
  Animation<double> padre, {
  required Duration total,
  Duration retraso = Duration.zero,
  required Duration duracion,
  Curve curva = Curves.ease,
}) {
  final t = total.inMicroseconds;
  final a = retraso.inMicroseconds / t;
  final b = (retraso + duracion).inMicroseconds / t;
  return CurvedAnimation(parent: padre, curve: Interval(a, math.min(1, b), curve: curva));
}

/// Interpola entre dos valores.
double mezclar(double a, double b, double t) => a + (b - a) * t;

/// Fotogramas clave de CSS con la misma curva en cada tramo.
///
/// CSS aplica `animation-timing-function` *a cada tramo* entre dos
/// fotogramas, no a la animación completa. Por ejemplo
/// `@keyframes ga { 0%,100% {…} 33% {…} 66% {…} }` con `ease-in-out` hace
/// ease-in-out de 0 a 33 %, otra vez de 33 a 66 % y otra de 66 a 100 %.
class Fotogramas {
  const Fotogramas(this.puntos, {this.curva = Curves.easeInOut});

  /// Lista de (posición 0–1, valores). Deben venir ordenados y empezar en 0
  /// y terminar en 1.
  final List<(double, List<double>)> puntos;
  final Curve curva;

  List<double> en(double t) {
    t = t.clamp(0.0, 1.0);
    for (var i = 0; i < puntos.length - 1; i++) {
      final (t0, v0) = puntos[i];
      final (t1, v1) = puntos[i + 1];
      if (t <= t1) {
        final u = t1 == t0 ? 1.0 : curva.transform((t - t0) / (t1 - t0));
        return [for (var k = 0; k < v0.length; k++) mezclar(v0[k], v1[k], u)];
      }
    }
    return puntos.last.$2;
  }
}

/// Latido de ida y vuelta (`0%,100% {a} 50% {b}`) con ease-in-out en cada mitad.
double latido(double t, double extremo, double medio) {
  final u = t < .5 ? t * 2 : (1 - t) * 2;
  return mezclar(extremo, medio, Curves.easeInOut.transform(u));
}

/// `prefers-reduced-motion: reduce` del prototipo. En Android corresponde a
/// «Quitar animaciones» en Accesibilidad.
bool sinMovimiento(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
