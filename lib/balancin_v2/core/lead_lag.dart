/// Quién guía a quién (plan v2 §4.4; `leadLag` del prototipo).
///
/// Correlación cruzada entre adulto y niño en una ventana de 4 s, sobre el eje
/// de mayor varianza del adulto, con retrasos de −1 a +1 s en pasos de 0,1 s.
/// `lag > 0`: el niño va detrás (guía el adulto).
library;

import 'dart:math' as math;

import 'stick_state.dart';

class LeadLag {
  const LeadLag(this.lag, this.r);
  final double lag; // s
  final double r; // correlación
}

LeadLag? leadLag(StickState a, StickState c, double t) {
  if (a.history.length < 2 || t - a.history.first.t < 3800) return null;
  const n = 40;
  final pa = <P2>[], pc = <P2>[];
  for (var i = 0; i < n; i++) {
    final tt = t - 4000 + i * 100;
    pa.add(a.at(tt));
    pc.add(c.at(tt));
  }
  double mean(Iterable<double> v) => v.fold(0.0, (s, x) => s + x) / v.length;
  final mxa = mean(pa.map((p) => p.x)), mya = mean(pa.map((p) => p.y));
  final vx = mean(pa.map((p) => p.x * p.x)) - mxa * mxa;
  final vy = mean(pa.map((p) => p.y * p.y)) - mya * mya;
  final useY = vy >= vx;
  final as = [for (final p in pa) p.axis(useY)];
  final cs = [for (final p in pc) p.axis(useY)];
  final ma = mean(as), mc = mean(cs);
  var best = 0.0;
  var bl = 0;
  for (var k = -10; k <= 10; k++) {
    var s = 0.0, sa = 0.0, sc = 0.0;
    for (var i = 0; i < n; i++) {
      final j = i + k;
      if (j < 0 || j >= n) continue;
      final x = as[i] - ma, y = cs[j] - mc;
      s += x * y;
      sa += x * x;
      sc += y * y;
    }
    final r = (sa != 0 && sc != 0) ? s / math.sqrt(sa * sc) : 0.0;
    if (r.abs() > best.abs()) {
      best = r;
      bl = k;
    }
  }
  return best.abs() < 0.3 ? null : LeadLag(bl / 10, best);
}
