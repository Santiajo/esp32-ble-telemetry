// Pruebas del dibujo del recuerdo («huella») y del archivo del Home.
//
// Los valores esperados se sacaron corriendo `huella()` de
// EcoHuella.dc.html. Si alguien cambia el orden en que se piden los números
// al generador, estas pruebas fallan (y el dibujo deja de ser igual al
// prototipo).
//
// Correr con: flutter test

import 'package:epu_eco/epu/datos/niveles.dart';
import 'package:epu_eco/epu/estado/estado_eco.dart';
import 'package:epu_eco/epu/ilustraciones/huella_datos.dart';
import 'package:flutter_test/flutter_test.dart';

DatosHuella datos(int id) {
  final n = NivelEco.de(id);
  return DatosHuella.de(id, n.pasos, n.guiaAdulto);
}

void main() {
  group('Huella igual al prototipo', () {
    test('cantidad de hilos y luces por nivel', () {
      expect([for (var i = 1; i <= 7; i++) datos(i).hilos.length], [28, 28, 28, 35, 20, 42, 39]);
      expect([for (var i = 1; i <= 7; i++) datos(i).flores.length], [4, 4, 4, 5, 5, 6, 6]);
    });

    test('nivel 1: primer hilo y última luz', () {
      final h = datos(1).hilos.first, f = datos(1).flores.last;
      expect(h.angulo, closeTo(-100.69414548934165, 1e-12));
      expect(h.lejos, closeTo(0.7434773244445572, 1e-12));
      expect(h.curva, closeTo(0.05375980609271663, 1e-12));
      expect(h.ancho, closeTo(9.30353666762986, 1e-12));
      expect(f.y, closeTo(-0.7, 1e-12));
      expect(f.fase, closeTo(3.814799972180184, 1e-12));
    });

    test('nivel 5 (giros): primer hilo y última luz', () {
      final h = datos(5).hilos.first, f = datos(5).flores.last;
      expect(h.giro, isTrue);
      expect(h.lejos, closeTo(0.6107049078730423, 1e-12));
      expect(h.ancho, closeTo(6.895996768211944, 1e-12));
      expect(f.x, closeTo(0.3535533905932737, 1e-12));
      expect(f.fase, closeTo(1.8282226658101302, 1e-12));
    });

    test('nivel 7: primer hilo y última luz (la guía el niño)', () {
      final h = datos(7).hilos.first, f = datos(7).flores.last;
      expect(h.angulo, closeTo(-98.85901842539153, 1e-12));
      expect(h.ancho, closeTo(11.124756673409024, 1e-12));
      expect(f.x, closeTo(-0.7, 1e-12));
      expect(f.fase, closeTo(6.141634328761899, 1e-12));
    });
  });

  group('Archivo', () {
    final hoy = DateTime(2026, 11, 17);
    test('fechas', () {
      expect(fechaArchivo(hoy, hoy: hoy), 'Hoy');
      expect(fechaArchivo(DateTime(2026, 11, 16), hoy: hoy), 'Ayer');
      expect(fechaArchivo(DateTime(2026, 11, 15), hoy: hoy), 'Domingo, 15 nov');
      expect(fechaArchivo(DateTime(2026, 10, 30), hoy: hoy), 'Viernes, 30 oct');
    });

    test('guardar y registrar ponen lo nuevo primero', () {
      final e = EstadoEco.demo(hoy: hoy)
        ..guardarRecuerdo(5, fecha: hoy)
        ..registrarSesion(5, minutos: 0, logrados: 5, fecha: hoy);
      expect(e.recuerdos.first.nivel, 5);
      expect(e.sesiones.first.nivel, 5);
      expect(e.sesiones.first.minutos, 1); // mínimo 1 minuto
    });
  });
}
