import 'dart:convert';

import 'package:esp32_ble_telemetry/epu/estado/estado_eco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recuerdos, sesiones y niveles completados sobreviven a cerrar la app', () {
    final e = EstadoEco(nivel: 1)
      ..marcarCompletado(1)
      ..registrarSesion(1, minutos: 3, logrados: 4, pasos: ['S:F', 'S:F', 'S:B', 'S:B'], fecha: DateTime(2026, 11, 26))
      ..pasosVista = ['S:F', 'S:F', 'S:B', 'S:B']
      ..guardarRecuerdo(1, fecha: DateTime(2026, 11, 26, 10));
    final texto = jsonEncode(e.archivoJson());
    final otra = EstadoEco.desdeArchivo((jsonDecode(texto) as Map).cast<String, Object?>());
    expect(otra.completado(1), isTrue);
    expect(otra.sesiones.single.minutos, 3);
    expect(otra.sesiones.single.logrados, 4);
    expect(otra.sesiones.single.pasos, ['S:F', 'S:F', 'S:B', 'S:B']);
    expect(otra.recuerdos.single.pasos, ['S:F', 'S:F', 'S:B', 'S:B']);
    expect(otra.recuerdos.single.fecha, DateTime(2026, 11, 26, 10));
  });

  test('del guardado antiguo (hasta dev.12) se rescatan los niveles completados', () {
    final antiguo = {
      'completados': [1, 2],
      'sesiones': [
        {'inicio': '2026-11-20T10:00:00.000', 'niveles': [1, 2]},
      ],
    };
    final e = EstadoEco.desdeArchivo(antiguo);
    expect(e.completado(2), isTrue);
    expect(e.sesiones, isEmpty);
  });

  test('sin nada guardado arranca vacío', () {
    final e = EstadoEco.desdeArchivo(null);
    expect(e.recuerdos, isEmpty);
    expect(e.sesiones, isEmpty);
  });
}
