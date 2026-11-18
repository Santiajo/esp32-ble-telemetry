import 'package:esp32_ble_telemetry/epu/datos/niveles.dart';
import 'package:esp32_ble_telemetry/epu/juego/estado_juego.dart';
import 'package:esp32_ble_telemetry/epu_app/motor_eco.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lecturas en el marco de cada persona: lateral + = su derecha, frontal − = su adelante.
const centro = (lateral: 0.0, frontal: 0.0);
const adelante = (lateral: 0.0, frontal: -30.0);
const atras = (lateral: 0.0, frontal: 30.0);
const derecha = (lateral: 30.0, frontal: 0.0);
const izquierda = (lateral: -30.0, frontal: 0.0);

class Juego {
  Juego(int nivel, {AjustesEco ajustes = const AjustesEco()}) {
    motor = MotorEco(
      nivel: NivelEco.de(nivel),
      estado: estado,
      ajustes: ajustes,
      tocarTrozo: trozos.add,
      tocarMelodia: () => melodias++,
      alTerminar: () => terminado = true,
    );
  }

  final estado = EstadoJuegoEco();
  late final MotorEco motor;
  final List<int> trozos = [];
  int melodias = 0;
  bool terminado = false;
  double t = 0;

  /// Avanza [ms] en pasos de 20 ms con las mismas lecturas.
  void durante(int ms, {Vuelco? adulto = centro, Vuelco? nino = centro}) {
    for (var x = 0; x < ms; x += 20) {
      t += 20;
      motor.tick(t, adulto: adulto, nino: nino);
    }
  }

  /// Un paso completo: el guía va, el que sigue responde, se sostienen y vuelven.
  void paso({required Vuelco adulto, required Vuelco nino, bool guiaAdulto = true, int sostener = 400}) {
    durante(200);
    if (guiaAdulto) {
      durante(300, adulto: adulto);
    } else {
      durante(300, nino: nino);
    }
    durante(sostener, adulto: adulto, nino: nino);
    durante(1600); // luz verde y vuelven al centro
  }
}

void main() {
  group('DetectorBorde', () {
    test('entra a 20°, se queda hasta bajar de 14°', () {
      final d = DetectorBorde(const AjustesEco());
      expect(d.actualizar(0, -15), isNull);
      expect(d.actualizar(0, -25), Borde.frente);
      expect(d.actualizar(0, -16), Borde.frente);
      expect(d.actualizar(0, -12), isNull);
      expect(d.actualizar(28, 3), Borde.derecha);
      expect(d.actualizar(-22, 0), Borde.izquierda);
      expect(d.actualizar(0, 30), Borde.atras);
    });

    test('no salta de borde por un poco del otro eje', () {
      final d = DetectorBorde(const AjustesEco());
      expect(d.actualizar(0, -25), Borde.frente);
      expect(d.actualizar(27, -25), Borde.frente);
      expect(d.actualizar(32, -25), Borde.derecha);
    });
  });

  test('niveles 1 a 4 los juega el motor; 5 a 7 siguen simulados', () {
    expect([for (var i = 1; i <= 7; i++) MotorEco.soporta(NivelEco.de(i))],
        [true, true, true, true, false, false, false]);
  });

  test('bordes que puede elegir el guía en cada nivel', () {
    Set<Borde> p(int n) => Juego(n).motor.permitidos;
    expect(p(1), {Borde.frente, Borde.atras});
    expect(p(2), Borde.values.toSet());
    expect(p(3), {Borde.izquierda, Borde.derecha});
    expect(p(4), {Borde.frente, Borde.atras});
  });

  group('nivel 1 · Juntos (guía el adulto, frente a frente)', () {
    test('se completa con direcciones libres y toca los trozos en orden', () {
      final j = Juego(1);
      // Mismo borde de la pantalla: para el niño, que está enfrente, es su atrás.
      j.paso(adulto: adelante, nino: atras);
      j.paso(adulto: adelante, nino: atras);
      j.paso(adulto: atras, nino: adelante);
      j.paso(adulto: atras, nino: adelante);
      expect(j.trozos, [0, 1, 2, 3]);
      // Como el prototipo: 0,9 s + 4 destellos de 2 s (el último de 1,6 s) + 0,7 s = 9,2 s.
      j.durante(9000);
      expect(j.melodias, 1);
      expect(j.terminado, isFalse);
      j.durante(300);
      expect(j.terminado, isTrue);
    });

    test('la franja del que sigue es el borde que eligió el guía', () {
      final j = Juego(1);
      j.durante(200);
      expect(j.estado.parpadea, Guia.adulto);
      j.durante(300, adulto: atras);
      expect(j.motor.elegido, Borde.atras);
      expect(j.estado.pistas, {Borde.atras: ColorPista.nino});
      expect(j.estado.parpadea, isNull);
    });

    test('si el niño va al borde equivocado no suena nada', () {
      final j = Juego(1);
      j.durante(200);
      j.durante(300, adulto: adelante);
      j.durante(2000, adulto: adelante, nino: adelante); // su adelante = borde de abajo
      expect(j.trozos, isEmpty);
      j.durante(400, adulto: adelante, nino: atras);
      expect(j.trozos, [0]);
    });

    test('tocar el borde un instante no alcanza: se sostienen 0,3 s juntos', () {
      final j = Juego(1);
      j.durante(200);
      j.durante(300, adulto: adelante);
      j.durante(200, adulto: adelante, nino: atras);
      j.durante(200, adulto: adelante);
      expect(j.trozos, isEmpty);
      j.durante(320, adulto: adelante, nino: atras);
      expect(j.trozos, [0]);
    });

    test('izquierda o derecha no cuentan como elección en «Juntos»', () {
      final j = Juego(1);
      j.durante(200);
      j.durante(600, adulto: derecha);
      expect(j.motor.elegido, isNull);
      expect(j.estado.parpadea, Guia.adulto);
    });

    test('entre trozos el guía tiene que volver al centro', () {
      final j = Juego(1);
      j.durante(200);
      j.durante(300, adulto: adelante);
      j.durante(400, adulto: adelante, nino: atras);
      expect(j.trozos, [0]);
      j.durante(1600, adulto: adelante, nino: atras); // se quedan en el borde
      j.durante(600, adulto: adelante, nino: atras);
      expect(j.trozos, [0]);
      expect(j.motor.elegido, isNull); // quedarse en el borde no elige el trozo siguiente
      j.paso(adulto: adelante, nino: atras);
      expect(j.trozos, [0, 1]);
    });

    test('un tambaleo del guía no borra la elección; irse más de 1 s sí', () {
      final j = Juego(1);
      j.durante(200);
      j.durante(300, adulto: adelante);
      j.durante(500); // vuelve al centro medio segundo
      expect(j.motor.elegido, Borde.frente);
      j.durante(400, adulto: adelante, nino: atras);
      expect(j.trozos, [0]);

      j.durante(1600);
      j.durante(200);
      j.durante(300, adulto: atras);
      j.durante(1200); // se fue más de 1 s
      expect(j.motor.elegido, isNull);
      expect(j.estado.parpadea, Guia.adulto);
    });
  });

  test('nivel 2 · Quietos (guía el niño): hay que sostener 1,4 s', () {
    final j = Juego(2);
    j.durante(200);
    j.durante(300, nino: izquierda); // izquierda del niño = derecha de la pantalla
    expect(j.motor.elegido, Borde.derecha);
    expect(j.estado.pistas, {Borde.derecha: ColorPista.adulto});
    j.durante(600, adulto: derecha, nino: izquierda);
    expect(j.estado.sostener, Borde.derecha);
    expect(j.trozos, isEmpty);
    j.durante(900, adulto: derecha, nino: izquierda);
    expect(j.trozos, [0]);
  });

  test('nivel 3 · Lados contrarios: el adulto va al borde opuesto al del niño', () {
    final j = Juego(3);
    j.durante(200);
    j.durante(300, nino: derecha); // derecha del niño = izquierda de la pantalla
    expect(j.motor.elegido, Borde.izquierda);
    expect(j.motor.objetivo, Borde.derecha);
    j.durante(400, adulto: derecha, nino: derecha);
    expect(j.trozos, [0]);
  });

  test('nivel 4 · Sube y baja: completo, con el niño al revés del adulto', () {
    final j = Juego(4);
    // Borde contrario de la pantalla: el niño, que está enfrente, va a su adelante.
    for (var i = 0; i < 5; i++) {
      final arriba = i.isEven;
      j.paso(adulto: arriba ? adelante : atras, nino: arriba ? adelante : atras);
    }
    expect(j.trozos, [0, 1, 2, 3, 4]);
    j.durante(12000);
    expect(j.terminado, isTrue);
  });

  test('lado a lado (ninoEnfrente: false), «Juntos» es el mismo adelante', () {
    final j = Juego(1, ajustes: const AjustesEco(ninoEnfrente: false));
    j.paso(adulto: adelante, nino: adelante);
    expect(j.trozos, [0]);
  });

  test('las luces van al borde de cada stick y se apagan al acertar', () {
    final j = Juego(1);
    j.durante(200);
    j.durante(300, adulto: adelante);
    expect(j.estado.adulto, EstadoJuegoEco.enBorde(Borde.frente, true));
    j.durante(400, adulto: adelante, nino: atras);
    expect(j.estado.acierto, isTrue);
    expect(j.estado.lucesVisibles, isFalse);
    j.durante(1600);
    expect(j.estado.acierto, isFalse);
    expect(j.estado.lucesVisibles, isTrue);
  });
}
