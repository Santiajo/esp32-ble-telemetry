// Pruebas de que el dibujo y el movimiento de las manos son idénticos al
// prototipo. Los valores esperados se sacaron corriendo el JavaScript de
// EcoAntes.dc.html (función `geo` y las cadenas `tick` / `step`).
//
// Correr con: flutter test

import 'package:esp32_ble_telemetry/epu/datos/niveles.dart';
import 'package:esp32_ble_telemetry/epu/ilustraciones/geometria_mano.dart';
import 'package:esp32_ble_telemetry/epu/ilustraciones/movimiento_antes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Escribe una polilínea como el atributo `d` del prototipo.
String d(List<Punto> pts) => [for (var i = 0; i < pts.length; i++) '${i == 0 ? 'M' : 'L'}${pts[i]}'].join(' ');

void main() {
  group('Geometría de la mano (geo)', () {
    final casos = <(double, double, String, String, double, double, double, double)>[
      // θ, φ, stick, pulgar, luz x, luz y, escala, opacidad
      (0, 0, 'M0 8 L0 64', 'M-0.51 34 L3.03 34.83 L5.85 35.48 L8.27 36.05 L11.5 36.8 L14.5 37.5 L17.2 48.3', 0, 6, 1, 1),
      (16, 0, 'M14.88 6.16 L-0.56 59.99', 'M7.22 31.01 L10.39 32.78 L12.92 34.19 L15.1 35.4 L17.99 37.01 L20.68 38.51 L20.3 49.64', 15.43, 4.23, 1, 1),
      (-16, 0, 'M-13.79 13.87 L1.64 67.7', 'M-7.11 39.01 L-3.49 38.83 L-0.59 38.68 L1.89 38.55 L5.2 38.39 L8.28 38.23 L13.85 47.87', -14.34, 11.95, 1, 1),
      (0, -35, 'M0 17.4 L0 63.28', 'M-0.51 32 L3.03 32.9 L5.85 34.11 L8.27 35.63 L11.5 36.41 L14.5 37.55 L17.2 48.12', 0, 15.77, 1, .3),
      (0, 40, 'M0 20.17 L0 63.06', 'M-0.51 47.6 L3.03 47.98 L5.85 47.73 L8.27 46.97 L11.5 47.37 L14.5 47.26 L17.2 53.61', 0, 21.63, 1.6, 1),
      (12, 24, 'M10.18 10.62 L-0.45 60.66', 'M3.76 38.4 L7.09 39.72 L9.83 40.43 L12.25 40.7 L15.28 41.93 L18.17 42.78 L19.01 51.8', 10.56, 10.64, 1.36, 1),
    ];
    for (final (th, ph, stick, pulgar, lx, ly, ls, lo) in casos) {
      test('pose ($th, $ph)', () {
        final g = GeometriaMano(th, ph);
        expect(d(g.stick), stick);
        expect(d(g.pulgar), pulgar);
        expect(g.luzX, lx);
        expect(g.luzY, ly);
        expect(g.luzEscala, ls);
        expect(g.luzOpacidad, lo);
      });
    }

    test('primer dedo en reposo', () {
      expect(
        d(GeometriaMano(0, 0).dedoCompleto.first),
        'M9.09 36 L6.75 36 L3.59 36 L0 36 L-3.59 36 L-6.75 36 L-9.09 36 L-10.14 36 L-10.5 36 '
        'L-10.14 36 L-9.09 36 L-6.75 36 L-3.59 36 L0 36 L3.24 36 L6.02 36',
      );
    });
  });

  group('Movimiento de «Antes del nivel» (tick + step)', () {
    // Ángulos [θa, φa, θn, φn] en el instante t (ms), según el prototipo.
    List<String> en(int nivel, int ms) {
      final m = MovimientoAntes(NivelEco.de(nivel).fases);
      for (var t = 0; t <= ms; t += 47) {
        m.avanzar(t.toDouble());
      }
      return [for (final v in m.cur) v.toStringAsFixed(6)];
    }

    test('nivel 1 al abrir', () => expect(en(1, 0), ['0.000000', '-7.700000', '0.000000', '-7.700000']));
    test('nivel 1 a los 423 ms', () => expect(en(1, 423), ['0.000000', '-33.615484', '0.000000', '-33.615484']));
    test('nivel 1 a los 1833 ms', () => expect(en(1, 1833), ['0.000000', '-12.955270', '0.000000', '-12.955270']));
    test('nivel 4 a los 2773 ms', () => expect(en(4, 2773), ['0.000000', '40.000000', '0.000000', '-35.000000']));
    test('nivel 5 a los 2773 ms', () => expect(en(5, 2773), ['-7.193157', '-17.467353', '-7.193157', '-17.467353']));
  });
}
