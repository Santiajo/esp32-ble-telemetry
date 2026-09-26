import 'dart:math' as math;

import 'touch_gesture_reader.dart';

/// Simuladores de movimiento del prototipo ("Niño automático" y demos por URL),
/// más un "Adulto automático" nuevo para probar el stick B real sin segunda persona.
///
/// Todas las curvas devuelven una posición relativa al centro del panel como
/// fracción de su tamaño; se aplican con [TouchGestureReader.feedFraction].
abstract final class SyntheticMotion {
  /// "Niño automático" del tablero: 0.36·sin(1.7t), 0.32·sin(3.4t).
  static ({double fx, double fy}) childAuto(double tSec) =>
      (fx: 0.36 * math.sin(tSec * 1.7), fy: 0.32 * math.sin(tSec * 3.4));

  /// Adulto de las demos: 0.3·sin(0.9·t·sp), 0.25·sin(1.3·t·sp).
  /// `speed` = 1 normal · 7 = "rápido" (registro agudo).
  static ({double fx, double fy}) adult(double tSec, {double speed = 1}) => (
        fx: 0.3 * math.sin(tSec * 0.9 * speed),
        fy: 0.25 * math.sin(tSec * 1.3 * speed),
      );

  /// Niño de las demos: 0.34·sin(1.9t), 0.3·sin(3.8t).
  static ({double fx, double fy}) childDemo(double tSec) =>
      (fx: 0.34 * math.sin(tSec * 1.9), fy: 0.3 * math.sin(tSec * 3.8));

  /// Sacudida: 0.3·sin(34t), 0.05·sin(3t).
  static ({double fx, double fy}) shake(double tSec) =>
      (fx: 0.3 * math.sin(tSec * 34), fy: 0.05 * math.sin(tSec * 3));
}

/// Escenarios de demostración del prototipo (`#demo=…`).
enum DemoScenario { espera, silencio, activo, rapido, latN, latA, oculto }

/// Mueve los lectores según un escenario de demo, igual que `demoDrive()` del prototipo.
/// [now] en ms. [w]/[h] = tamaño del panel en px.
void driveDemo(
  DemoScenario demo,
  double now, {
  required TouchGestureReader adult,
  required TouchGestureReader child,
  double w = 400,
  double h = 600,
}) {
  final t = now / 1000;
  final cyc = t % 16;
  void feedAdult({double speed = 1}) {
    final p = SyntheticMotion.adult(t, speed: speed);
    adult.feedFraction(p.fx, p.fy, now, w, h);
  }

  void feedChild() {
    final p = SyntheticMotion.childDemo(t);
    child.feedFraction(p.fx, p.fy, now, w, h);
  }

  void feedShake(TouchGestureReader r) {
    final p = SyntheticMotion.shake(t);
    r.feedFraction(p.fx, p.fy, now, w, h);
  }

  switch (demo) {
    case DemoScenario.espera:
      feedAdult();
    case DemoScenario.silencio:
      feedChild();
    case DemoScenario.activo:
      feedAdult();
      feedChild();
    case DemoScenario.rapido:
      feedAdult(speed: 7);
      feedChild();
    case DemoScenario.latN:
      feedAdult();
      if (cyc < 3) feedChild();
    case DemoScenario.latA:
      feedChild();
      if (cyc < 3) feedAdult();
    case DemoScenario.oculto:
      if (cyc > 5 && cyc < 6.2) {
        feedShake(adult);
        feedShake(child);
      } else {
        feedAdult();
        feedChild();
      }
  }
}
