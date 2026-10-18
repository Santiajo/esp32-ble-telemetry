/// Ejes del usuario en el marco del sensor (plan v2 §4.1 paso 3, §5.3 y §10.1).
///
/// [g0]: dirección del vector medido por el acelerómetro con el stick en
/// reposo y vertical (el «neutro»). [right] y [up]: hacia dónde se mueve ese
/// vector al inclinar el stick a la derecha y hacia arriba (adelante). Los tres
/// son unitarios y ortogonales.
///
/// Por defecto (§10.1): el stick se sostiene vertical y mover la muñeca hacia
/// los lados mueve el eje X del sensor, así que `right` = X. El eje vertical
/// del stick se supone Y (sin signo: se resuelve con la primera lectura en
/// reposo). El asistente ([AxisWizard]) puede reemplazarlo todo.
library;

import 'dart:math' as math;

import 'vec3.dart';

class AxisMap {
  AxisMap._(this.g0, this.right, this.up);

  final V3 g0, right, up;

  /// Construye un mapa ortonormal a partir del neutro y la dirección «derecha».
  /// [upHint] (opcional) solo fija el signo de `up`. Devuelve `null` si
  /// [rightHint] es casi paralelo a [g0].
  static AxisMap? fromRight(V3 g0, V3 rightHint, {V3? upHint}) {
    final n = g0.normalized();
    if (n == null) return null;
    final h = rightHint.normalized();
    if (h == null) return null;
    final sep = h.angleTo(n);
    if (math.min(sep, math.pi - sep) < _minSeparation) return null;
    final r = h.rejectFrom(n).normalized()!;
    var u = n.cross(r); // unitario: n ⟂ r
    if (upHint != null && u.dot(upHint) < 0) u = -u;
    return AxisMap._(n, r, u);
  }

  /// Mapa por defecto (§10.1) a partir de la gravedad medida en reposo [measured].
  /// `g0` = ±[uprightAxis] según el signo medido; `right` = X del sensor.
  /// Si el stick no estaba vertical, igual usa el eje supuesto (la calibración de
  /// la sesión centra cualquier inclinación de descanso).
  static AxisMap defaultFor(V3 measured, {int uprightAxis = 1, int rightAxis = 0}) {
    final a = V3.axis(uprightAxis);
    final g0 = measured.dot(a) < 0 ? -a : a;
    return fromRight(g0, V3.axis(rightAxis))!;
  }

  /// Inclinación (°) del vector unitario [g] en este marco.
  ({double x, double y}) tiltDeg(V3 g) {
    final c = g.dot(g0);
    return (
      x: math.atan2(g.dot(right), c) * 180 / math.pi,
      y: math.atan2(g.dot(up), c) * 180 / math.pi,
    );
  }

  Map<String, Object> toJson() => {'g0': g0.toJson(), 'right': right.toJson(), 'up': up.toJson()};

  /// Reconstruye y re-ortonormaliza; `null` si los datos no sirven.
  static AxisMap? fromJson(Map<String, Object?> j) {
    try {
      return fromRight(V3.fromJson(j['g0']), V3.fromJson(j['right']), upHint: V3.fromJson(j['up']));
    } catch (_) {
      return null;
    }
  }
}

/// Separación mínima entre ejes para aceptarlos (60°, §5.3).
const double _minSeparation = math.pi / 3;

enum WizardStep { rest, up, right, done, failed }

/// Asistente de ejes (§5.3): reposo → «inclínalo hacia arriba» → «hacia tu derecha».
///
/// Se alimenta con la gravedad estimada del `TiltReader` ([feed]). En cada
/// paso de inclinación guarda la lectura más alejada del neutro; [next]
/// confirma el paso actual.
class AxisWizard {
  WizardStep step = WizardStep.rest;
  String? error;

  V3 _sum = V3.zero;
  int _n = 0;
  V3? _g0;
  V3? _upPeak, _rightPeak;
  double _upAngle = 0, _rightAngle = 0;
  AxisMap? result;

  /// Ángulo mínimo (°) que hay que inclinar en cada paso.
  static const double minTiltDeg = 15;

  void feed(V3 g) {
    switch (step) {
      case WizardStep.rest:
        _sum = _sum + g;
        _n++;
      case WizardStep.up:
        final a = g.angleTo(_g0!);
        if (a > _upAngle) {
          _upAngle = a;
          _upPeak = g;
        }
      case WizardStep.right:
        final a = g.angleTo(_g0!);
        if (a > _rightAngle) {
          _rightAngle = a;
          _rightPeak = g;
        }
      case WizardStep.done:
      case WizardStep.failed:
        break;
    }
  }

  /// Inclinación alcanzada en el paso actual (°), para mostrar progreso.
  double get currentTiltDeg => (step == WizardStep.up ? _upAngle : _rightAngle) * 180 / math.pi;

  /// Confirma el paso actual. Devuelve `false` (con [error]) si falta inclinar más
  /// o si los ejes no quedaron bien separados.
  bool next() {
    switch (step) {
      case WizardStep.rest:
        final g0 = _n == 0 ? null : (_sum * (1 / _n)).normalized();
        if (g0 == null) return _fail('Sin datos del stick.');
        _g0 = g0;
        step = WizardStep.up;
        return true;
      case WizardStep.up:
        if (_upAngle * 180 / math.pi < minTiltDeg) return _fail('Inclínalo un poco más hacia arriba.');
        step = WizardStep.right;
        return true;
      case WizardStep.right:
        if (_rightAngle * 180 / math.pi < minTiltDeg) return _fail('Inclínalo un poco más hacia tu derecha.');
        final up = _upPeak!.rejectFrom(_g0!).normalized()!;
        final right = _rightPeak!.rejectFrom(_g0!).normalized()!;
        if (up.angleTo(right) < _minSeparation) {
          step = WizardStep.failed;
          error = 'Arriba y derecha quedaron casi en la misma dirección. Repite el asistente.';
          return false;
        }
        result = AxisMap.fromRight(_g0!, right, upHint: up);
        step = WizardStep.done;
        error = null;
        return true;
      case WizardStep.done:
      case WizardStep.failed:
        return false;
    }
  }

  /// Error recuperable: el paso sigue abierto para reintentar.
  bool _fail(String msg) {
    error = msg;
    return false;
  }
}
