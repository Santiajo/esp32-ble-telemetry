import 'dart:math' as math;

/// Datos del dibujo del recuerdo («huella»), sin nada de Flutter para que se
/// pueda probar con `dart run` contra el prototipo.
///
/// Copia exacta de `huella()` en EcoFinal.dc.html y EcoHuella.dc.html:
/// * Por cada trozo de la partitura salen hilos desde el centro hacia donde
///   se volcó cada stick (4 del adulto, 3 del niño; 2 y 2 en los giros, que
///   son espirales).
/// * En cada trozo hay una luz amarilla donde se encontraron.
///
/// Los números «al azar» salen de un generador con semilla (`id × 977`,
/// Park–Miller: `semilla × 16807 mod 2147483647`), así cada nivel siempre
/// dibuja lo mismo y queda idéntico al prototipo. **El orden en que se piden
/// los números importa**: si se cambia el orden de los campos, el dibujo
/// cambia. Por eso se respeta el orden del objeto JS, incluidas las
/// «nieblas», que ya no se dibujan pero todavía consumen números.
///
/// En la app real, los pasos podrían salir de las lecturas de los sticks en
/// vez de la partitura; el resto del dibujo no cambia.

/// Un trazo que sale del centro.
class HiloHuella {
  HiloHuella({
    required this.trozo,
    required this.adulto,
    required this.giro,
    required this.sentido,
    required this.angulo,
    required this.lejos,
    required this.curva,
    required this.ancho,
    required this.alfa,
    required this.fase,
    required this.velocidad,
    required this.r0,
    required this.vueltas,
    required this.retraso,
  });

  final int trozo;
  final bool adulto;

  /// Los giros se dibujan como espirales; el resto, como curvas cuadráticas.
  final bool giro;

  /// 1 = giro hacia un lado (`+`), −1 = hacia el otro (`-`).
  final int sentido;

  /// Grados (0 = derecha, −90 = arriba/adelante).
  final double angulo;

  /// Largo del hilo, en fracciones del radio.
  final double lejos;
  final double curva;

  /// Grosor base del trazo (para un dibujo de 346 px; se escala).
  final double ancho;
  final double alfa;
  final double fase;
  final double velocidad;

  /// Dónde empieza el hilo, en fracciones del radio.
  final double r0;
  final double vueltas;
  final double retraso;
}

/// Luz amarilla de un encuentro. [x] e [y] en fracciones del radio.
class FlorHuella {
  FlorHuella(this.trozo, this.x, this.y, this.fase);
  final int trozo;
  final double x, y, fase;
}

class DatosHuella {
  DatosHuella._(this.hilos, this.flores, this.trozos);

  final List<HiloHuella> hilos;
  final List<FlorHuella> flores;
  final int trozos;

  static final _cache = <String, DatosHuella>{};

  /// [pasos]: la partitura del nivel (`S:F`, `G:+`…). [guiaAdulto]: quién
  /// guía. El resultado se guarda: es el mismo cada vez.
  factory DatosHuella.de(int id, List<String> pasos, bool guiaAdulto) =>
      _cache.putIfAbsent('$id|${pasos.join(',')}|$guiaAdulto', () => _crear(id, pasos, guiaAdulto));

  static DatosHuella _crear(int id, List<String> pasos, bool gA) {
    const ang = {'F': -90.0, 'R': 0.0, 'B': 90.0, 'L': 180.0};
    const opuesta = {'F': 'B', 'B': 'F', 'L': 'R', 'R': 'L'};
    var semilla = id * 977;
    double rnd() {
      semilla = (semilla * 16807) % 2147483647;
      return semilla / 2147483647;
    }

    final hilos = <HiloHuella>[], flores = <FlorHuella>[];
    for (var i = 0; i < pasos.length; i++) {
      final sp = pasos[i];
      final tipo = sp[0], d = sp.substring(2);
      // Q = el último trozo del nivel 7, que guía el niño.
      final l = tipo == 'Q' ? false : gA;
      final dirG = ang[d], dirF = tipo == 'O' ? ang[opuesta[d]] : ang[d];
      final giro = tipo == 'G', quieto = tipo == 'H', eco = tipo == 'E', sg = d == '-' ? -1 : 1;
      for (final (adulto, a, guia) in [(l, dirG, true), (!l, giro ? null : dirF, false)]) {
        final nH = giro ? 2 : (adulto ? 4 : 3);
        for (var k = 0; k < nH; k++) {
          // Mismo orden que el objeto del prototipo.
          final angulo = a == null ? 0.0 : a + (rnd() - .5) * (quieto ? 18 : 40) + (adulto ? 9 : -9);
          final lejos = math.min(.9, (quieto ? .7 : .6) + rnd() * .28 - (eco && !guia ? .08 : 0));
          final curva = (rnd() - .5) * .9 + (adulto ? .3 : -.3);
          final ancho = (adulto ? 9 : 6.5) + rnd() * 3;
          final alfa = (quieto ? .5 : .38) + rnd() * .12;
          final fase = rnd() * 6.283;
          final vel = .18 + rnd() * .22;
          final r0 = .04 + rnd() * .1;
          final vueltas = giro ? (guia ? 1.1 : .8) * (.85 + rnd() * .3) : 0.0;
          hilos.add(HiloHuella(
            trozo: i,
            adulto: adulto,
            giro: giro,
            sentido: sg,
            angulo: angulo,
            lejos: lejos,
            curva: curva,
            ancho: ancho,
            alfa: alfa,
            fase: fase,
            velocidad: vel,
            r0: r0,
            vueltas: vueltas,
            retraso: guia ? 0 : (eco ? .45 : .2),
          ));
        }
      }
      final a = (giro ? -90 + sg * 225 : dirG!) * math.pi / 180, r = giro ? .5 : .7;
      // «Nieblas»: ya no se dibujan, pero consumen números como en el
      // prototipo (si se sacan, cambia todo lo que viene después).
      for (var k = 0; k < 2; k++) {
        if (giro) rnd();
        rnd();
      }
      flores.add(FlorHuella(i, math.cos(a) * r, math.sin(a) * r, rnd() * 6.283));
    }
    return DatosHuella._(hilos, flores, pasos.length);
  }
}
