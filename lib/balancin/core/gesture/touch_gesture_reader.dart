import 'dart:collection';
import 'dart:math' as math;

import '../constants.dart';
import 'gesture_reader.dart';

class _Sample {
  const _Sample(this.t, this.x, this.y);
  final double t;
  final double x;
  final double y;
}

int _sgn(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

/// Lectura de gesto a partir de posiciones 2D (dedo, ratón o simulador).
///
/// Port 1:1 de la clase `Stick` del prototipo:
///   vel    velocidad suavizada (px/s)        → adulto: registro del campo
///   amp    amplitud del gesto en 0,8 s (0–1) → adulto: ancho · niño: intensidad
///   dx/dy  dirección del último movimiento   → niño: recorrido melódico
///   acc    distancia acumulada               → niño: una nota cada 42 px
///   moving se movió en los últimos 200 ms
///   shake  ≥ 4 inversiones de dirección en X en 0,6 s
///
/// Nota de paridad: igual que en el prototipo, el decaimiento de `vel`
/// ocurre por llamada a [update] (depende de la tasa de ticks, ~60 Hz).
class TouchGestureReader implements GestureReader {
  TouchGestureReader() {
    reset();
  }

  final ListQueue<_Sample> _s = ListQueue<_Sample>();

  double _vel = 0;
  double _amp = 0;
  int _dx = 0;
  int _dy = 0;
  double _lastMove = -1e9;
  bool _moving = false;
  bool _shake = false;
  double _acc = 0;

  /// Última posición recibida (para dibujar el punto en el panel). Null si no hay.
  double? x;
  double? y;

  /// Tamaño del panel de la última muestra (px).
  double w = 1;
  double h = 1;

  /// Velocidad cruda suavizada en px/s (útil para depurar).
  double get velPxPerS => _vel;

  @override
  bool get moving => _moving;
  @override
  double get lastMove => _lastMove;
  @override
  double get amp => _amp;
  @override
  double get vel01 =>
      (_vel / BalancinConst.velMaxPxPerS).clamp(0.0, 1.0).toDouble();
  @override
  int get dx => _dx;
  @override
  int get dy => _dy;
  @override
  bool get shake => _shake;

  @override
  void reset() {
    _s.clear();
    _vel = 0;
    _amp = 0;
    _dx = 0;
    _dy = 0;
    _lastMove = -1e9;
    _moving = false;
    _shake = false;
    _acc = 0;
    x = null;
    y = null;
    w = 1;
    h = 1;
  }

  /// Registra una posición [px],[py] (px dentro del panel) en el instante [t] (ms)
  /// para un panel de tamaño [panelW]×[panelH].
  void feed(double px, double py, double t, double panelW, double panelH) {
    w = panelW;
    h = panelH;
    if (_s.isNotEmpty) {
      final p = _s.last;
      final ddx = px - p.x;
      final ddy = py - p.y;
      final dt = math.max(1.0, t - p.t);
      final d = math.sqrt(ddx * ddx + ddy * ddy);
      if (d > 0) {
        _vel = _vel * BalancinConst.velEmaKeep +
            (d / dt * 1000) * (1 - BalancinConst.velEmaKeep);
        if (ddx.abs() > BalancinConst.dirThresholdPx) _dx = _sgn(ddx);
        if (ddy.abs() > BalancinConst.dirThresholdPx) _dy = _sgn(ddy);
        _lastMove = t;
        _acc += d;
      }
    }
    x = px;
    y = py;
    _s.add(_Sample(t, px, py));
  }

  /// Igual que [feed], pero con coordenadas relativas al centro del panel
  /// expresadas como fracción del tamaño (−0,5…0,5). Así se escriben los simuladores del prototipo.
  void feedFraction(double fx, double fy, double t, double panelW, double panelH) {
    feed(panelW / 2 + panelW * fx, panelH / 2 + panelH * fy, t, panelW, panelH);
  }

  @override
  void update(double t) {
    while (_s.isNotEmpty && t - _s.first.t > BalancinConst.historyMs) {
      _s.removeFirst();
    }
    if (t - _lastMove > BalancinConst.velDecayAfterMs) _vel *= BalancinConst.velDecay;
    if (_vel < BalancinConst.velFloor) _vel = 0;

    // Amplitud: diagonal del rectángulo recorrido en 0,8 s, relativa al panel.
    double a = 1e9, b = -1e9, c = 1e9, d = -1e9;
    var n = 0;
    for (final q in _s) {
      if (t - q.t > BalancinConst.ampWindowMs) continue;
      n++;
      a = math.min(a, q.x);
      b = math.max(b, q.x);
      c = math.min(c, q.y);
      d = math.max(d, q.y);
    }
    if (n > 1) {
      final range = math.sqrt((b - a) * (b - a) + (d - c) * (d - c));
      final diag = math.sqrt(w * w + h * h) * BalancinConst.ampDiagFactor;
      _amp = (range / diag).clamp(0.0, 1.0).toDouble();
    } else {
      _amp = 0;
    }

    _moving = t - _lastMove < BalancinConst.movingWindowMs;

    // Sacudida: inversiones de signo del desplazamiento en X dentro de 0,6 s.
    var inv = 0;
    var last = 0;
    _Sample? prev;
    for (final q in _s) {
      final p = prev;
      prev = q;
      if (p == null) continue;
      if (t - q.t > BalancinConst.shakeWindowMs) continue;
      final sx = _sgn(q.x - p.x);
      if (sx != 0 && last != 0 && sx != last) inv++;
      if (sx != 0) last = sx;
    }
    _shake = inv >= BalancinConst.shakeInversions;
  }

  @override
  int consumeArticulations() {
    var n = 0;
    while (_acc >= BalancinConst.articulationPx) {
      _acc -= BalancinConst.articulationPx;
      n++;
    }
    return n;
  }

  @override
  void discardArticulations() {
    _acc = 0;
  }
}
