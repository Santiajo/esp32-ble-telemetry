import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/ble/imu_frame_parser.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/tilt_reader.dart';
import 'package:esp32_ble_telemetry/epu_app/fuente_sticks_ble.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que manda el firmware Epu (ya rotado): derecho = +Z, derecha = +X, adelante = +Y.
/// [derecha] y [adelante] en grados; devuelve (tiltX, tiltY) del lector tras 1,5 s quieto.
({double x, double y}) leer({double derecha = 0, double adelante = 0, TiltReader? r, int desde = 0}) {
  final reader = r ?? TiltReader(axes: FuenteSticksBle.ejesEpu);
  final d = derecha * math.pi / 180, a = adelante * math.pi / 180;
  // Gravedad medida: se corre hacia el eje del lado al que se inclina la punta.
  final gx = math.sin(d) * math.cos(a), gy = math.sin(a), gz = math.cos(d) * math.cos(a);
  for (var i = 0; i < 150; i++) {
    final t = desde + i * 10;
    reader.addSample(
      ImuSample(tMs: t, ax: (gx * 4096).round(), ay: (gy * 4096).round(), az: (gz * 4096).round(), gx: 0, gy: 0, gz: 0),
      t.toDouble(),
    );
  }
  return (x: reader.tiltX, y: reader.tiltY);
}

void main() {
  test('derecho marca 0°', () {
    final v = leer();
    expect(v.x, closeTo(0, 1));
    expect(v.y, closeTo(0, 1));
  });

  test('cada lado da su signo (antes izquierda y atrás salían como derecha y adelante)', () {
    expect(leer(derecha: 30).x, closeTo(30, 2));
    expect(leer(derecha: -30).x, closeTo(-30, 2));
    expect(leer(adelante: 30).y, closeTo(30, 2));
    expect(leer(adelante: -30).y, closeTo(-30, 2));
  });

  test('conectar el stick acostado o boca abajo no da vuelta la vertical', () {
    final r = TiltReader(axes: FuenteSticksBle.ejesEpu);
    leer(adelante: 170, r: r); // primeras lecturas casi boca abajo
    final v = leer(r: r, desde: 2000); // después, derecho
    expect(v.x, closeTo(0, 2));
    expect(v.y, closeTo(0, 2));
    expect(leer(derecha: -25, r: r, desde: 4000).x, closeTo(-25, 2));
  });
}
