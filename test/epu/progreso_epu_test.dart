import 'package:esp32_ble_telemetry/epu_app/progreso_epu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final miercoles = DateTime(2026, 11, 18, 17, 0);

  test('niveles seguidos van a la misma sesión; tras 30 min empieza otra', () {
    final p = ProgresoEpu()
      ..terminarNivel(1, miercoles)
      ..terminarNivel(2, miercoles.add(const Duration(minutes: 3)))
      ..terminarNivel(1, miercoles.add(const Duration(minutes: 6)))
      ..terminarNivel(4, miercoles.add(const Duration(minutes: 50)));
    expect(p.sesiones, hasLength(2));
    expect(p.sesiones.first.niveles, {4});
    expect(p.sesiones.last.niveles, {1, 2});
    expect(p.completados, {1, 2, 4});
  });

  test('el Home muestra título, minutos y las 7 barritas', () {
    final p = ProgresoEpu()
      ..terminarNivel(1, miercoles)
      ..terminarNivel(3, miercoles.add(const Duration(minutes: 9)));
    final s = p.sesionesParaHome(miercoles.add(const Duration(minutes: 10))).single;
    expect(s.titulo, 'Hoy · 2 partes');
    expect(s.minutos, 9);
    expect(s.partes, [true, false, true, false, false, false, false]);
  });

  test('un solo nivel cuenta 1 minuto y «1 parte»', () {
    final p = ProgresoEpu()..terminarNivel(2, miercoles);
    final s = p.sesionesParaHome(miercoles).single;
    expect(s.titulo, 'Hoy · 1 parte');
    expect(s.minutos, 1);
  });

  test('títulos de día como el prototipo', () {
    expect(ProgresoEpu.tituloDia(miercoles, miercoles), 'Hoy');
    expect(ProgresoEpu.tituloDia(DateTime(2026, 11, 17, 23), miercoles), 'Ayer');
    expect(ProgresoEpu.tituloDia(DateTime(2026, 10, 30), miercoles), 'Viernes, 30 oct');
  });

  test('se guarda y se recupera igual; datos rotos no rompen la app', () {
    final p = ProgresoEpu()
      ..terminarNivel(1, miercoles)
      ..terminarNivel(4, miercoles.add(const Duration(hours: 2)));
    final q = ProgresoEpu.fromJson(p.toJson());
    expect(q.completados, {1, 4});
    expect(q.sesiones.map((s) => s.niveles), [
      {4},
      {1},
    ]);
    expect(ProgresoEpu.fromJson('esto no es json').completados, isEmpty);
    expect(ProgresoEpu.fromJson(null).sesiones, isEmpty);
  });

  test('guarda como mucho 20 sesiones', () {
    final p = ProgresoEpu();
    for (var i = 0; i < 25; i++) {
      p.terminarNivel(1, miercoles.add(Duration(hours: i)));
    }
    expect(p.sesiones, hasLength(ProgresoEpu.maxSesiones));
  });
}
