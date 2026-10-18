// Fase 4: plano limitado del banco (plan v2 §5.2).

import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/stick_state.dart';
import 'package:esp32_ble_telemetry/balancin_v2/widgets/sync_plane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometría', () {
    test('el marco de ±6 y los puntos quedan dentro del lienzo con margen', () {
      for (final size in [const Size(300, 300), const Size(360, 220), const Size(120, 400)]) {
        final g = PlaneGeometry(size);
        final canvas = Offset.zero & size;
        expect(canvas.contains(g.frame.topLeft), isTrue);
        expect(canvas.contains(g.frame.bottomRight), isTrue);
        for (final p in [g.toPx(6, 6), g.toPx(-6, -6), g.toPx(100, -100), g.toPx(double.maxFinite, 0)]) {
          // El punto más grande (radio 11) y su marca de salida (radio 17 + trazo) caben.
          expect(p.dx - 19, greaterThanOrEqualTo(0), reason: '$size');
          expect(p.dy - 19, greaterThanOrEqualTo(0), reason: '$size');
          expect(p.dx + 19, lessThanOrEqualTo(size.width), reason: '$size');
          expect(p.dy + 19, lessThanOrEqualTo(size.height), reason: '$size');
        }
      }
    });

    test('arriba en el plano es arriba en la pantalla; el centro es el centro', () {
      final g = PlaneGeometry(const Size(300, 300));
      expect(g.toPx(0, 0), const Offset(150, 150));
      expect(g.toPx(0, 3).dy, lessThan(150));
      expect(g.toPx(3, 0).dx, greaterThan(150));
    });
  });

  testWidgets('se dibuja con puntos en el borde, datos viejos y zona objetivo', (tester) async {
    final p = SyncParams();
    final a = StickState(Role.adult), c = StickState(Role.child);
    var t = 0.0;
    for (var i = 0; i < 60; i++) {
      a.feedTilt(200, 10, p); // muy pasado de rango: queda en el borde
      c.feedTilt(-20, -90, p);
      a.update(t += 16, 0.016, p);
      c.update(t, 0.016, p);
    }
    expect(a.atEdge && c.atEdge, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: SyncPlane(adult: a, child: c, now: t, target: P2(c.pos.x, a.pos.y), tol: 1.2, childStale: true),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(SyncPlane), findsOneWidget);
  });
}
