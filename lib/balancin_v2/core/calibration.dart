/// Calibración del rango de cada persona (plan v2 §4.3; `startCal`/`finishCal` del prototipo).
///
/// Durante [durationMs] se guardan las inclinaciones crudas (°). Centro =
/// promedio del primer segundo; medio rango = mayor distancia entre los
/// percentiles 5/95 y el centro, con un mínimo por rol. Sin datos suficientes
/// la persona queda sin calibrar (rango por defecto).
library;

import 'levels.dart';
import 'params.dart';
import 'stick_state.dart';

class Calibration {
  static const double durationMs = 6000;

  final Map<Role, List<TrailPoint>> _samples = {Role.adult: [], Role.child: []};

  /// [tRel] = ms desde que empezó la calibración.
  void add(Role role, double tRel, P2 tilt) => _samples[role]!.add(TrailPoint(tRel, tilt.x, tilt.y));

  int count(Role role) => _samples[role]!.length;

  /// Devuelve la calibración de [role], o `null` si no hubo datos suficientes.
  StickCal? result(Role role, SyncParams p) {
    final s = _samples[role]!;
    final first = s.where((q) => q.t < 1000).toList();
    final rest = s.where((q) => q.t >= 1000).toList();
    if (first.length < 3 || rest.length < 10) return null;
    double mean(Iterable<double> v) => v.fold(0.0, (a, b) => a + b) / v.length;
    final cx = mean(first.map((q) => q.x));
    final cy = mean(first.map((q) => q.y));
    double pc(List<double> arr, double q) {
      final i = (q * arr.length).floor();
      return arr[i < arr.length - 1 ? i : arr.length - 1];
    }

    final xs = rest.map((q) => q.x).toList()..sort();
    final ys = rest.map((q) => q.y).toList()..sort();
    var hr = (pc(xs, 0.95) - cx).abs();
    for (final v in [(pc(xs, 0.05) - cx).abs(), (pc(ys, 0.95) - cy).abs(), (pc(ys, 0.05) - cy).abs()]) {
      if (v > hr) hr = v;
    }
    final min = role == Role.adult ? p.minA : p.minC;
    return StickCal(cx: cx, cy: cy, hr: hr > min ? hr : min);
  }
}
