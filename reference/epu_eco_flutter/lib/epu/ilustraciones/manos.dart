import 'dart:math' as math;
import 'dart:ui';

import '../tema/colores.dart';
import '../util/svg.dart';
import 'geometria_mano.dart';

/// Dibujo de las dos manos con sus sticks, el que usan «Antes del nivel»,
/// «Quién guía» y las miniaturas de «Elegir nivel».
///
/// Todas las medidas están en las unidades del SVG original
/// (`viewBox="0 0 120 100"`). Quien llama escala el canvas al tamaño en
/// pantalla: 285 px de ancho en las pantallas grandes (×2,375) y 84 px en las
/// miniaturas (×0,7).

/// Grosor de los contornos de cada mano.
class EstiloMano {
  const EstiloMano._(this.colorStick, this.brazo, this.dedo, this.pulgar, this.grupoX, this.grupoY, this.escala);

  /// Mano del adulto: `translate(30 15)`, contornos 20,8 / 8,8 / 11,2.
  static const adulto = EstiloMano._(EpuColores.lilaAdulto, 20.8, 8.8, 11.2, 30, 15, 1);

  /// Mano del niño: `translate(88 36) scale(.74)`, contornos 22 / 10 / 12,4
  /// (más gruesos para que al achicarse se vean parejos con los del adulto).
  static const nino = EstiloMano._(EpuColores.coralNino, 22, 10, 12.4, 88, 36, .74);

  final Color colorStick;
  final double brazo, dedo, pulgar;
  final double grupoX, grupoY, escala;

  /// Las miniaturas engrosan solo el contorno oscuro (+1,4 el adulto, +1,8 el
  /// niño) para que se lea a 84 px. Los rellenos blancos no cambian.
  EstiloMano engrosado(double extra) =>
      EstiloMano._(colorStick, brazo + extra, dedo + extra, pulgar + extra, grupoX, grupoY, escala);
}

/// Estado de la luz de la punta en un cuadro.
class LuzMano {
  const LuzMano({
    this.anilloOpacidad = 0,
    this.anilloEscala = 1,
    this.anillo2Opacidad = 0,
    this.anillo2Escala = 1,
    this.opacidad,
  });

  /// Anillo amarillo alrededor de la luz (`opacity` del círculo r 8,5).
  final double anilloOpacidad;

  /// Escala del anillo (animación `hr`: .8 → 1.25 → .8).
  final double anilloEscala;

  /// Segundo anillo: solo lo usa «Calibrar», donde dos anillos se expanden
  /// desfasados mientras calibra.
  final double anillo2Opacidad, anillo2Escala;

  /// Opacidad de la luz. Si es `null` se usa la de la geometría (se atenúa al
  /// volcar hacia adelante). «Quién guía» la reemplaza por el parpadeo `bl`.
  final double? opacidad;
}

Path _linea(List<Punto> pts) {
  final p = Path()..moveTo(pts.first.x, pts.first.y);
  for (final q in pts.skip(1)) {
    p.lineTo(q.x, q.y);
  }
  return p;
}

/// Dibuja una mano con su stick, en el mismo orden de capas que el SVG.
void dibujarMano(Canvas canvas, GeometriaMano g, EstiloMano e, LuzMano luz) {
  const tinta = EpuColores.tinta, blanco = EpuColores.blanco;
  canvas
    ..save()
    ..translate(e.grupoX, e.grupoY)
    ..scale(e.escala);

  final brazo = _linea(GeometriaMano.antebrazo);
  final palmaAtras = _linea(g.palmaAtras);
  final palma = _linea(g.palma);

  // 1. Contorno del brazo y la palma.
  for (final p in [brazo, palmaAtras, palma]) {
    canvas.drawPath(p, trazoSvg(tinta, e.brazo));
  }
  // 2. Dedos completos (detrás del stick): contorno y relleno blanco.
  for (final d in g.dedoCompleto) {
    final p = _linea(d);
    canvas
      ..drawPath(p, trazoSvg(tinta, e.dedo))
      ..drawPath(p, trazoSvg(blanco, 5));
  }
  // 3. Relleno blanco del brazo y la palma.
  for (final p in [brazo, palmaAtras, palma]) {
    canvas.drawPath(p, trazoSvg(blanco, 17));
  }
  // 4. El stick.
  canvas.drawPath(_linea(g.stick), trazoSvg(e.colorStick, 16));

  // 5. La luz de la punta.
  canvas
    ..save()
    ..translate(g.luzX, g.luzY);
  // `transform-box: fill-box; transform-origin: center` → cada anillo
  // escala sobre su centro, que es (0, 0). El trazo también se escala.
  for (final (op, esc) in [(luz.anilloOpacidad, luz.anilloEscala), (luz.anillo2Opacidad, luz.anillo2Escala)]) {
    if (op > 0) {
      canvas.drawCircle(Offset.zero, 8.5 * esc, trazoSvg(EpuColores.luzStick, 1.8 * esc, opacidad: op));
    }
  }
  final op = (luz.opacidad ?? g.luzOpacidad).clamp(0.0, 1.0);
  if (op > 0) {
    // El grupo de la luz tiene opacidad propia: se compone primero y después
    // se aplica la opacidad (por eso saveLayer y no dos colores sueltos).
    canvas
      ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, op))
      ..scale(g.luzEscala)
      ..drawCircle(Offset.zero, 5, rellenoSvg(EpuColores.luzStick, opacidad: .45))
      ..drawCircle(Offset.zero, 3, rellenoSvg(EpuColores.luzStick))
      ..restore();
  }
  canvas.restore();

  // 6. Dedos por delante del stick: contorno (remate recto), punta redonda,
  //    relleno blanco y otra vez la punta en blanco.
  for (var i = 0; i < 4; i++) {
    final t = Offset(g.dedoPunta[i].x, g.dedoPunta[i].y);
    canvas
      ..drawPath(_linea(g.dedoFrente[i]), trazoSvg(tinta, e.dedo, fin: StrokeCap.butt))
      ..drawCircle(t, e.dedo / 2, rellenoSvg(tinta))
      ..drawPath(_linea(g.dedoBlanco[i]), trazoSvg(blanco, 5, fin: StrokeCap.butt))
      ..drawCircle(t, 2.5, rellenoSvg(blanco));
  }
  // 7. Pulgar y la línea blanca que separa el índice.
  final pulgar = _linea(g.pulgar);
  canvas
    ..drawPath(pulgar, trazoSvg(tinta, e.pulgar))
    ..drawPath(pulgar, trazoSvg(blanco, 7.4))
    ..drawPath(_linea(g.borrador), trazoSvg(blanco, 9))
    ..restore();
}

/// Dirección de una flecha de movimiento. El ángulo es el `rotate()` del SVG
/// (la flecha base apunta hacia arriba = adelante).
enum Direccion {
  adelante(0, Offset(0, -1)),
  derecha(90, Offset(1, 0)),
  atras(180, Offset(0, 1)),
  izquierda(270, Offset(-1, 0));

  const Direccion(this.grados, this.vector);
  final double grados;

  /// Hacia dónde se mueve la flecha al entrar (en unidades del SVG).
  final Offset vector;

  /// Letra que usa el prototipo (F, R, B, L).
  static Direccion? desdeLetra(String letra) => switch (letra) {
        'F' => adelante,
        'R' => derecha,
        'B' => atras,
        'L' => izquierda,
        _ => null,
      };
}

/// Flecha recta de movimiento.
///
/// * Antes del nivel: `M0 4 L0 -4.5 M-3.6 -1 L0 -4.5 L3.6 -1`, trazo 2,4.
/// * Miniaturas: `M0 4.5 L0 -5 M-4 -1 L0 -5 L4 -1`, trazo 3.
void dibujarFlecha(
  Canvas canvas, {
  required Offset en,
  required double grados,
  required double opacidad,
  Offset desplazamiento = Offset.zero,
  bool miniatura = false,
}) {
  if (opacidad <= 0) return;
  final path = miniatura
      ? trazadoSvg('M0 4.5 L0 -5 M-4 -1 L0 -5 L4 -1')
      : trazadoSvg('M0 4 L0 -4.5 M-3.6 -1 L0 -4.5 L3.6 -1');
  canvas
    ..save()
    ..translate(en.dx, en.dy)
    ..translate(desplazamiento.dx, desplazamiento.dy)
    ..rotate(grados * math.pi / 180)
    ..drawPath(path, trazoSvg(EpuColores.flecha, miniatura ? 3 : 2.4, opacidad: opacidad))
    ..restore();
}

/// Flecha de giro (arco con punta sólida). Gira sobre su centro (0, 0).
///
/// * Antes del nivel: trazo 1,9 y punta con borde 1.
/// * Miniaturas: trazo 2,3 y punta con borde 1,2.
void dibujarGiro(
  Canvas canvas, {
  required Offset en,
  required double opacidad,
  double radianes = 0,
  bool miniatura = false,
}) {
  if (opacidad <= 0) return;
  final arco = trazadoSvg('M-3.52 -2.47 A4.3 4.3 0 1 1 1.11 4.15');
  final punta = trazadoSvg('M-1.79 4.93 L1.76 6.57 L0.46 1.74 Z');
  canvas
    ..save()
    ..translate(en.dx, en.dy)
    ..rotate(radianes)
    // Con opacidad de grupo para que el arco y la punta no se sumen donde se
    // tocan (en el SVG la opacidad es del grupo <g>).
    ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacidad))
    ..drawPath(arco, trazoSvg(EpuColores.flecha, miniatura ? 2.3 : 1.9))
    ..drawPath(punta, rellenoSvg(EpuColores.flecha))
    ..drawPath(punta, trazoSvg(EpuColores.flecha, miniatura ? 1.2 : 1))
    ..restore()
    ..restore();
}

/// Dónde va cada flecha dentro del viewBox 120 × 100.
class PosicionesFlecha {
  PosicionesFlecha._();
  static const adulto = Offset(30, 6.5);
  static const nino = Offset(88, 27.5);

  /// En «Antes del nivel» el giro del adulto va 1 unidad más abajo.
  static const giroAdultoAntes = Offset(30, 7.5);
}
