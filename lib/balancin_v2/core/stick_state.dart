/// Estado de un stick en el plano de −6 a 6 (plan v2 §4.2, clase `Stick` del prototipo).
///
/// Recibe inclinación en grados (del dedo, de una fuente sintética o del
/// `TiltReader`) y la convierte en un punto del plano según el rango de esa
/// persona. Sin vibración: v2 no ignora lecturas (decisión V3).
///
/// Garantía del límite del plano (§5.2): [raw] y [pos] están siempre en
/// [−[planeLimit], [planeLimit]] y nunca son NaN.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'levels.dart';
import 'params.dart';

const double planeLimit = 6;

class P2 {
  const P2(this.x, this.y);
  final double x, y;
  static const zero = P2(0, 0);

  double axis(bool useY) => useY ? y : x;

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

class TrailPoint {
  const TrailPoint(this.t, this.x, this.y);
  final double t, x, y;
}

/// Centro y medio rango de la inclinación de una persona (°).
class StickCal {
  const StickCal({required this.cx, required this.cy, required this.hr});
  final double cx, cy, hr;

  Map<String, double> toJson() => {'cx': cx, 'cy': cy, 'hr': hr};
}

class Rhythm {
  const Rhythm(this.f, this.amp);
  final double f; // Hz
  final double amp; // medio recorrido en el plano
  static const none = Rhythm(0, 0);
}

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

class StickState {
  StickState(this.role) {
    reset();
  }

  final Role role;

  /// Calibración de esta persona; `null` = rango por defecto. [reset] la conserva.
  StickCal? cal;

  late P2 tilt; // última inclinación recibida (°)
  late P2 raw; // inclinación llevada al plano, con límite
  late P2 pos; // posición suavizada
  late P2 overflow; // cuánto se pasó del plano (0 si está dentro), con signo
  final ListQueue<TrailPoint> history = ListQueue<TrailPoint>();
  late double lastActive;
  late double speed;
  late bool has;

  /// Tiempo con datos y tiempo en el borde (s), para «% del tiempo en el borde».
  double timeWithData = 0;
  double timeAtEdge = 0;

  void reset() {
    tilt = P2.zero;
    raw = P2.zero;
    pos = P2.zero;
    overflow = P2.zero;
    history.clear();
    lastActive = -1e9;
    speed = 0;
    has = false;
  }

  StickCal range(SyncParams p) =>
      cal ?? StickCal(cx: 0, cy: 0, hr: role == Role.adult ? p.rangeA : p.rangeC);

  /// Inclinación en grados. Las lecturas no finitas se descartan.
  void feedTilt(double tx, double ty, SyncParams p) {
    if (!tx.isFinite || !ty.isFinite) return;
    has = true;
    tilt = P2(tx, ty);
    final r = range(p);
    final ux = planeLimit * (tx - r.cx) / r.hr;
    final uy = planeLimit * (ty - r.cy) / r.hr;
    raw = P2(_clamp(ux, -planeLimit, planeLimit), _clamp(uy, -planeLimit, planeLimit));
    overflow = P2(ux - raw.x, uy - raw.y);
  }

  bool get atEdge => overflow.x != 0 || overflow.y != 0;

  double get edgeFraction => timeWithData > 0 ? timeAtEdge / timeWithData : 0;

  void update(double t, double dt, SyncParams p) {
    if (!has) return;
    final px = pos.x, py = pos.y;
    final a = _clamp(p.alpha * 1.6, 0.02, 1);
    pos = P2(
      _clamp(px + (raw.x - px) * a, -planeLimit, planeLimit),
      _clamp(py + (raw.y - py) * a, -planeLimit, planeLimit),
    );
    final step = math.sqrt((pos.x - px) * (pos.x - px) + (pos.y - py) * (pos.y - py));
    speed = speed * 0.7 + step / math.max(dt, 1e-3) * 0.3;
    if (speed > p.onSpeed) lastActive = t;
    history.add(TrailPoint(t, pos.x, pos.y));
    while (history.isNotEmpty && t - history.first.t > 4500) {
      history.removeFirst();
    }
    timeWithData += dt;
    if (atEdge) timeAtEdge += dt;
  }

  bool active(double t) => has && t - lastActive < 2000;

  /// Posición registrada en el instante [t] (la última anterior o igual).
  P2 at(double t) {
    for (var i = history.length - 1; i >= 0; i--) {
      final q = history.elementAt(i); // O(1) en ListQueue
      if (q.t <= t) return P2(q.x, q.y);
    }
    return history.isEmpty ? P2.zero : P2(history.first.x, history.first.y);
  }

  /// Frecuencia dominante por cruces por cero del eje principal (ventana [SyncParams.rhythmWin]).
  Rhythm rhythm(double t, SyncParams p) {
    final w = p.rhythmWin * 1000;
    final h = history.where((q) => t - q.t <= w).toList();
    if (h.length < 12) return Rhythm.none;
    var mx = 0.0, my = 0.0;
    for (final q in h) {
      mx += q.x;
      my += q.y;
    }
    mx /= h.length;
    my /= h.length;
    var vx = 0.0, vy = 0.0;
    for (final q in h) {
      vx += (q.x - mx) * (q.x - mx);
      vy += (q.y - my) * (q.y - my);
    }
    final useY = vy >= vx;
    final m = useY ? my : mx;
    var cr = 0, prev = 0;
    var mn = 1e9, mxv = -1e9;
    for (final q in h) {
      final v = (useY ? q.y : q.x) - m;
      mn = math.min(mn, v);
      mxv = math.max(mxv, v);
      final s = v > 0.25 ? 1 : (v < -0.25 ? -1 : 0);
      if (s != 0 && prev != 0 && s != prev) cr++;
      if (s != 0) prev = s;
    }
    var dur = (h.last.t - h.first.t) / 1000;
    if (dur == 0) dur = 1;
    return Rhythm(cr / 2 / dur, (mxv - mn) / 2);
  }
}
