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

/// Centro y medio rango de la inclinación de una persona (°). El rango puede
/// ser distinto en horizontal ([hrX]) y en vertical ([hrY]); [hr] es el mayor.
class StickCal {
  const StickCal({required this.cx, required this.cy, required double hr, double? hrX, double? hrY})
      : hrX = hrX ?? hr,
        hrY = hrY ?? hr;
  final double cx, cy, hrX, hrY;

  double get hr => hrX > hrY ? hrX : hrY;

  Map<String, double> toJson() => {'cx': cx, 'cy': cy, 'hrX': hrX, 'hrY': hrY};
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
  late P2 vel; // velocidad suavizada en el plano (u/s), para la sincronía con velocidad (§12.2)
  final ListQueue<TrailPoint> history = ListQueue<TrailPoint>();
  late double lastActive;
  late double speed;
  late bool has;

  /// Tiempo con datos y tiempo en el borde (s), para «% del tiempo en el borde».
  double timeWithData = 0;
  double timeAtEdge = 0;

  /// §19: cuánto se corrió el rango (°) por pasarse del borde, y la última inclinación.
  double _shiftX = 0, _shiftY = 0;
  double _lastTx = 0, _lastTy = 0;

  /// Lo corrido se devuelve al mover el stick, nunca estando quieto: el punto no deriva.
  static const double followRecover = 0.25;

  /// El rango se corre como mucho la mitad de su largo.
  static const double followMax = 0.5;

  void reset() {
    tilt = P2.zero;
    raw = P2.zero;
    pos = P2.zero;
    overflow = P2.zero;
    vel = P2.zero;
    history.clear();
    clearFollow();
    lastActive = -1e9;
    speed = 0;
    has = false;
  }

  StickCal range(SyncParams p) =>
      cal ?? StickCal(cx: 0, cy: 0, hr: role == Role.adult ? p.rangeA : p.rangeC);

  /// Inclinación en grados. Las lecturas no finitas se descartan.
  void feedTilt(double tx, double ty, SyncParams p) {
    if (!tx.isFinite || !ty.isFinite) return;
    final r = range(p);
    if (p.edgeFollow > 0 && has) {
      _shiftX = _follow(_shiftX, tx - r.cx, r.hrX, (tx - _lastTx).abs());
      _shiftY = _follow(_shiftY, ty - r.cy, r.hrY, (ty - _lastTy).abs());
    }
    has = true;
    tilt = P2(tx, ty);
    _lastTx = tx;
    _lastTy = ty;
    final ux = planeLimit * (tx - r.cx) / r.hrX;
    final uy = planeLimit * (ty - r.cy) / r.hrY;
    final sx = planeLimit * _shiftX / r.hrX, sy = planeLimit * _shiftY / r.hrY;
    raw = P2(_clamp(ux - sx, -planeLimit, planeLimit), _clamp(uy - sy, -planeLimit, planeLimit));
    // El desborde se mide contra el rango calibrado: la marca y el % en el borde no cambian.
    overflow = P2(raw.x.abs() < planeLimit ? 0 : ux - raw.x, raw.y.abs() < planeLimit ? 0 : uy - raw.y);
  }

  /// [off] = inclinación respecto del centro (°), [hr] = medio rango, [moved] = lo que se
  /// movió el stick desde la lectura anterior (°).
  static double _follow(double shift, double off, double hr, double moved) {
    final over = off - shift;
    if (over > hr) {
      shift = off - hr;
    } else if (over < -hr) {
      shift = off + hr;
    } else {
      final back = moved * followRecover;
      shift = shift.abs() <= back ? 0 : shift - back * shift.sign;
    }
    return _clamp(shift, -hr * followMax, hr * followMax);
  }

  /// Vuelve al rango calibrado, sin corrimiento.
  void clearFollow() {
    _shiftX = 0;
    _shiftY = 0;
  }

  bool get atEdge => overflow.x != 0 || overflow.y != 0;

  double get edgeFraction => timeWithData > 0 ? timeAtEdge / timeWithData : 0;

  /// Vuelve a contar el % en el borde desde cero (tras calibrar).
  void resetEdgeStats() {
    timeWithData = 0;
    timeAtEdge = 0;
  }

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
    final idt = 1 / math.max(dt, 1e-3);
    vel = P2(vel.x * 0.7 + (pos.x - px) * idt * 0.3, vel.y * 0.7 + (pos.y - py) * idt * 0.3);
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
