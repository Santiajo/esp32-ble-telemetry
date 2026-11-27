import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tema/colores.dart';
import '../util/svg.dart';
import 'geometria_mano.dart';
import 'manos.dart';

/// Ilustraciones de la preparación y de «Calibrar», copiadas del SVG en línea
/// de cada pantalla. Coordenadas en el viewBox original; el widget escala.

/// Lienzo con viewBox: dibuja [pintor] en coordenadas del SVG y lo escala al
/// [ancho] en pantalla (la altura sale de la proporción, como `height: auto`).
class LienzoSvg extends StatelessWidget {
  const LienzoSvg({
    super.key,
    required this.vbAncho,
    required this.vbAlto,
    required this.ancho,
    required this.pintor,
    this.etiqueta,
  });

  final double vbAncho, vbAlto, ancho;
  final void Function(Canvas canvas) pintor;

  /// `aria-label` del SVG.
  final String? etiqueta;

  double get alto => ancho * vbAlto / vbAncho;

  @override
  Widget build(BuildContext context) => Semantics(
        label: etiqueta,
        image: etiqueta != null,
        child: CustomPaint(
          size: Size(ancho, alto),
          painter: _PintorSvg(vbAncho, pintor),
        ),
      );
}

class _PintorSvg extends CustomPainter {
  _PintorSvg(this.vbAncho, this.pintor);
  final double vbAncho;
  final void Function(Canvas) pintor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / vbAncho);
    pintor(canvas);
    canvas.restore();
  }

  // Las ilustraciones animadas se reconstruyen en cada cuadro con un pintor
  // nuevo; repintar siempre es lo correcto y es barato (pocas figuras).
  @override
  bool shouldRepaint(_PintorSvg old) => true;
}

/// `<rect x y width height rx>`.
void rectSvg(Canvas c, double x, double y, double w, double h, double rx, Paint p) =>
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rx)), p);

/// `<circle>` relleno de la luz amarilla.
void luzSvg(Canvas c, double cx, double cy, double r, {double opacidad = 1, Color color = EpuColores.luzStick}) =>
    c.drawCircle(Offset(cx, cy), r, rellenoSvg(color, opacidad: opacidad));

// ── Prep1 · «Activa Bluetooth y No Molestar» (viewBox 320 × 260) ───────────
void pintarPermisos(Canvas c) {
  c.drawPath(trazadoSvg('M48 238 L272 238'), trazoSvg(EpuColores.ilustracionClaro, 6));
  final senal = trazoSvg(EpuColores.flecha, 7);
  for (final d in const [
    'M112 61.4 A40 40 0 0 1 129.6 82.3',
    'M120 47.5 A56 56 0 0 1 144.6 76.8',
    'M190.4 142.3 A40 40 0 0 1 208 121.4',
    'M175.4 136.8 A56 56 0 0 1 200 107.5',
  ]) {
    c.drawPath(trazadoSvg(d), senal);
  }
  rectSvg(c, 74, 92, 36, 144, 18, rellenoSvg(EpuColores.lilaAdulto));
  luzSvg(c, 92, 109, 10, opacidad: .45);
  luzSvg(c, 92, 109, 6);
  rectSvg(c, 214, 146, 28, 90, 14, rellenoSvg(EpuColores.coralNino));
  luzSvg(c, 228, 160, 9, opacidad: .45);
  luzSvg(c, 228, 160, 5);
}

// ── Prep2 · «Sin interrupciones» (viewBox 320 × 280) ───────────────────────
void pintarSinAvisos(Canvas c) {
  // Cuatro avisos (burbujas) afuera del círculo, cada uno girado.
  void burbuja(double grados, double cx, double cy, String forma, String lineas) {
    c
      ..save()
      ..translate(cx, cy)
      ..rotate(grados * math.pi / 180)
      ..translate(-cx, -cy);
    final f = trazadoSvg(forma);
    c
      ..drawPath(f, rellenoSvg(EpuColores.ilustracionClaro))
      ..drawPath(f, trazoSvg(EpuColores.ilustracionClaro, 2))
      ..drawPath(trazadoSvg(lineas), trazoSvg(EpuColores.ilustracionLinea, 3))
      ..restore();
  }

  burbuja(-8, 37, 49, 'M26 34 L48 34 A12 12 0 0 1 60 46 L60 52 A12 12 0 0 1 48 64 L30 64 L18 74 L20 62 A12 12 0 0 1 14 52 L14 46 A12 12 0 0 1 26 34 Z',
      'M24 45 L48 45 M24 53 L40 53');
  burbuja(7, 281, 39, 'M270 24 L292 24 A12 12 0 0 1 304 36 L304 42 A12 12 0 0 1 298 52 L300 64 L288 54 L270 54 A12 12 0 0 1 258 42 L258 36 A12 12 0 0 1 270 24 Z',
      'M268 35 L292 35 M268 43 L284 43');
  burbuja(-6, 293, 229, 'M282 214 L304 214 A12 12 0 0 1 316 226 L316 232 A12 12 0 0 1 310 242 L312 254 L300 244 L282 244 A12 12 0 0 1 270 232 L270 226 A12 12 0 0 1 282 214 Z',
      'M280 225 L304 225 M280 233 L296 233');
  burbuja(9, 27, 237, 'M16 222 L38 222 A12 12 0 0 1 50 234 L50 240 A12 12 0 0 1 38 252 L20 252 L8 262 L10 250 A12 12 0 0 1 4 240 L4 234 A12 12 0 0 1 16 222 Z',
      'M14 233 L38 233 M14 241 L30 241');

  // El círculo blanco donde juegan, con su borde de puntos verdes.
  c.drawCircle(const Offset(160, 150), 112, rellenoSvg(EpuColores.blanco));
  dibujarPunteado(c, circuloSvg(160, 150, 121), const [0, 13], trazoSvg(EpuColores.flecha, 4));

  rectSvg(c, 120, 112, 30, 114, 15, rellenoSvg(EpuColores.lilaAdulto));
  luzSvg(c, 135, 127, 9, opacidad: .45);
  luzSvg(c, 135, 127, 5);
  rectSvg(c, 172, 152, 24, 74, 12, rellenoSvg(EpuColores.coralNino));
  luzSvg(c, 184, 164, 8, opacidad: .45);
  luzSvg(c, 184, 164, 4.5);
}

// ── Prep4 · «Conecta los dos sticks» (viewBox 320 × 260) ───────────────────
/// [luz1] / [luz2]: encendida (amarilla con halo) o apagada (tono del stick).
void pintarConectar(Canvas c, {required bool luz1, required bool luz2}) {
  c.drawPath(trazadoSvg('M64 238 L256 238'), trazoSvg(EpuColores.ilustracionClaro, 6));
  rectSvg(c, 105, 42, 48, 194, 24, rellenoSvg(EpuColores.lilaAdulto));
  luzSvg(c, 129, 65, 13, opacidad: luz1 ? .45 : 0);
  luzSvg(c, 129, 65, 8, color: luz1 ? EpuColores.luzStick : EpuColores.luzApagadaAdulto);
  rectSvg(c, 177, 114, 38, 122, 19, rellenoSvg(EpuColores.coralNino));
  luzSvg(c, 196, 133, 12, opacidad: luz2 ? .45 : 0);
  luzSvg(c, 196, 133, 7, color: luz2 ? EpuColores.luzStick : EpuColores.luzApagadaNino);
}

// ── Calibrar (viewBox 320 × 260) ───────────────────────────────────────────
/// Valores animados de «Calibrando…»: dos anillos que se expanden desfasados
/// y la luz que parpadea. Con todo en 0 / 1 queda la imagen quieta.
class AnimacionCalibrar {
  const AnimacionCalibrar({
    this.anillo1Escala = 1,
    this.anillo1Opacidad = 0,
    this.anillo2Escala = 1,
    this.anillo2Opacidad = 0,
    this.luzOpacidad = 1,
  });

  final double anillo1Escala, anillo1Opacidad, anillo2Escala, anillo2Opacidad, luzOpacidad;
}

/// «Calibrar» (modo eco): las mismas manos de «Quién guía» y de las
/// pantallas de nivel, quietas, con una flecha verde punteada hacia arriba
/// sobre cada stick.
///
/// SVG: `viewBox="0 -10 120 110"`, 285 px de ancho. [LienzoSvg] no maneja
/// el −10 del viewBox, así que se corre todo 10 unidades hacia abajo; el
/// lienzo se pide con `vbAlto: 110`.
///
/// Flechas (trazo 1,4, remates redondos, `stroke-dasharray=".4 3.2"`):
/// * adulto: `M30 11 L30 -4.5` y punta `M27 -2.8 L30 -6 L33 -2.8`;
/// * niño: `M88 31 L88 18.5` y punta `M85 20.2 L88 17 L91 20.2`.
///
/// Mientras calibra, en la luz de cada stick se expanden dos anillos (r 8,5,
/// trazo 1,8) y la luz parpadea; ver [AnimacionCalibrar].
void pintarCalibrar(Canvas c, AnimacionCalibrar a) {
  c
    ..save()
    ..translate(0, 10);
  final verde = trazoSvg(EpuColores.flecha, 1.4);
  dibujarPunteado(c, trazadoSvg('M30 11 L30 -4.5'), const [.4, 3.2], verde);
  c.drawPath(trazadoSvg('M27 -2.8 L30 -6 L33 -2.8'), verde);
  dibujarPunteado(c, trazadoSvg('M88 31 L88 18.5'), const [.4, 3.2], verde);
  c.drawPath(trazadoSvg('M85 20.2 L88 17 L91 20.2'), verde);

  final luz = LuzMano(
    anilloOpacidad: a.anillo1Opacidad,
    anilloEscala: a.anillo1Escala,
    anillo2Opacidad: a.anillo2Opacidad,
    anillo2Escala: a.anillo2Escala,
    opacidad: a.luzOpacidad,
  );
  final quieta = GeometriaMano(0, 0);
  dibujarMano(c, quieta, EstiloMano.adulto, luz);
  dibujarMano(c, quieta, EstiloMano.nino, luz);
  c.restore();
}
