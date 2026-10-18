/// Vector 3D mínimo para la fusión de sensores (marco del MPU6050).
library;

import 'dart:math' as math;

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;

  static const zero = V3(0, 0, 0);
  static const ex = V3(1, 0, 0);
  static const ey = V3(0, 1, 0);
  static const ez = V3(0, 0, 1);

  /// Eje del sensor por índice: 0 = X, 1 = Y, 2 = Z.
  static V3 axis(int i) => i == 0 ? ex : (i == 1 ? ey : ez);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  V3 operator -() => V3(-x, -y, -z);

  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  /// Vector unitario; `null` si el largo es casi cero o no finito.
  V3? normalized() {
    final l = length;
    if (!l.isFinite || l < 1e-9) return null;
    return V3(x / l, y / l, z / l);
  }

  /// Componente perpendicular a [n] (unitario).
  V3 rejectFrom(V3 n) => this - n * dot(n);

  /// Rota este vector un ángulo [angle] (rad) alrededor del eje unitario [k] (Rodrigues).
  V3 rotate(V3 k, double angle) {
    final c = math.cos(angle), s = math.sin(angle);
    return this * c + k.cross(this) * s + k * (k.dot(this) * (1 - c));
  }

  /// Ángulo entre dos vectores (rad).
  double angleTo(V3 o) {
    final c = dot(o) / (length * o.length);
    return math.acos(c.clamp(-1.0, 1.0));
  }

  List<double> toJson() => [x, y, z];

  static V3 fromJson(Object? j) {
    final l = j as List;
    return V3((l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble());
  }

  @override
  String toString() => '(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)}, ${z.toStringAsFixed(4)})';
}
