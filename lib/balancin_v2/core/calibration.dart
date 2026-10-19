/// Calibración del rango de cada persona (plan v2 §4.3 y §12.6).
///
/// Durante [durationMs] se guardan las inclinaciones crudas (°) de cada stick.
///
/// **Robusta (por defecto, `calMode` 1):** solo cuentan las muestras en que el
/// stick se está moviendo. El centro de cada eje es el medio entre los
/// percentiles 5 y 95, y el medio rango de cada eje es la mitad de esa
/// distancia, con un mínimo por rol. No depende de cómo estaba el stick en el
/// primer segundo: en la prueba del 18-10-2026, un stick apoyado o en otra
/// postura al empezar dejaba el centro corrido y el punto pegado al borde.
///
/// **Prototipo (`calMode` 0):** centro = promedio del primer segundo; medio
/// rango = mayor distancia entre los percentiles 5/95 y el centro (un solo
/// valor para los dos ejes).
///
/// Sin datos suficientes la persona queda sin calibrar (rango por defecto).
library;

import 'levels.dart';
import 'params.dart';
import 'stick_state.dart';

class _Sample {
  const _Sample(this.t, this.x, this.y, this.moving);
  final double t, x, y;
  final bool moving;
}

class Calibration {
  static const double durationMs = 6000;

  /// Muestras en movimiento necesarias para la calibración robusta (~0,5 s a 60 fps).
  static const int minMovingSamples = 30;

  final Map<Role, List<_Sample>> _samples = {Role.adult: [], Role.child: []};

  /// [tRel] = ms desde que empezó la calibración. [moving] = el stick se está moviendo.
  void add(Role role, double tRel, P2 tilt, {bool moving = true}) =>
      _samples[role]!.add(_Sample(tRel, tilt.x, tilt.y, moving));

  int count(Role role) => _samples[role]!.length;

  int movingCount(Role role) => _samples[role]!.where((q) => q.moving).length;

  /// Devuelve la calibración de [role], o `null` si no hubo datos suficientes.
  StickCal? result(Role role, SyncParams p) => p.calMode >= 1 ? _robust(role, p) : _prototype(role, p);

  static double _pc(List<double> arr, double q) {
    final i = (q * arr.length).floor();
    return arr[i < arr.length - 1 ? i : arr.length - 1];
  }

  StickCal? _robust(Role role, SyncParams p) {
    final s = _samples[role]!.where((q) => q.moving).toList();
    if (s.length < minMovingSamples) return null;
    final xs = s.map((q) => q.x).toList()..sort();
    final ys = s.map((q) => q.y).toList()..sort();
    final x5 = _pc(xs, 0.05), x95 = _pc(xs, 0.95), y5 = _pc(ys, 0.05), y95 = _pc(ys, 0.95);
    final min = role == Role.adult ? p.minA : p.minC;
    double half(double a, double b) {
      final h = (b - a) / 2;
      return h > min ? h : min;
    }

    return StickCal(cx: (x5 + x95) / 2, cy: (y5 + y95) / 2, hr: 0, hrX: half(x5, x95), hrY: half(y5, y95));
  }

  StickCal? _prototype(Role role, SyncParams p) {
    final s = _samples[role]!;
    final first = s.where((q) => q.t < 1000).toList();
    final rest = s.where((q) => q.t >= 1000).toList();
    if (first.length < 3 || rest.length < 10) return null;
    double mean(Iterable<double> v) => v.fold(0.0, (a, b) => a + b) / v.length;
    final cx = mean(first.map((q) => q.x));
    final cy = mean(first.map((q) => q.y));
    final xs = rest.map((q) => q.x).toList()..sort();
    final ys = rest.map((q) => q.y).toList()..sort();
    var hr = (_pc(xs, 0.95) - cx).abs();
    for (final v in [(_pc(xs, 0.05) - cx).abs(), (_pc(ys, 0.95) - cy).abs(), (_pc(ys, 0.05) - cy).abs()]) {
      if (v > hr) hr = v;
    }
    final min = role == Role.adult ? p.minA : p.minC;
    return StickCal(cx: cx, cy: cy, hr: hr > min ? hr : min);
  }
}
