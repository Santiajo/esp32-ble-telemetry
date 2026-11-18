import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tema/colores.dart';
import '../util/svg.dart';

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

void pintarCalibrar(Canvas c, AnimacionCalibrar a) {
  final verde = trazoSvg(EpuColores.flecha, 3.5);
  dibujarPunteado(c, trazadoSvg('M129 54 L129 18'), const [1, 8], verde);
  c.drawPath(trazadoSvg('M121 22 L129 13 L137 22'), verde);
  dibujarPunteado(c, trazadoSvg('M196 114 L196 84'), const [1, 8], verde);
  c.drawPath(trazadoSvg('M188 88 L196 79 L204 88'), verde);

  // Anillos: `transform-box: fill-box; transform-origin: center` → crecen
  // sobre su centro y el trazo crece con ellos.
  void anillos(double cx, double cy, double r) {
    for (final (s, o) in [(a.anillo1Escala, a.anillo1Opacidad), (a.anillo2Escala, a.anillo2Opacidad)]) {
      if (o > 0) c.drawCircle(Offset(cx, cy), r * s, trazoSvg(EpuColores.luzStick, 3 * s, opacidad: o));
    }
  }

  // Luz (grupo con opacidad): halo .45 + núcleo.
  void luz(double cx, double cy, double rh, double rn) {
    if (a.luzOpacidad <= 0) return;
    c
      ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a.luzOpacidad))
      ..drawCircle(Offset(cx, cy), rh, rellenoSvg(EpuColores.luzStick, opacidad: .45))
      ..drawCircle(Offset(cx, cy), rn, rellenoSvg(EpuColores.luzStick))
      ..restore();
  }

  final mano = rellenoSvg(EpuColores.ilustracionClaro);
  final dedos = trazoSvg(EpuColores.ilustracionLinea, 3);

  rectSvg(c, 105, 62, 48, 174, 24, rellenoSvg(EpuColores.lilaAdulto));
  anillos(129, 86, 13);
  luz(129, 86, 13, 8);
  rectSvg(c, 95, 150, 68, 58, 22, mano);
  c.drawPath(trazadoSvg('M104 166 L140 166 M104 179 L140 179 M104 192 L140 192'), dedos);

  rectSvg(c, 177, 124, 38, 112, 19, rellenoSvg(EpuColores.coralNino));
  rectSvg(c, 169, 168, 54, 46, 18, mano);
  c.drawPath(trazadoSvg('M177 181 L206 181 M177 191 L206 191 M177 201 L206 201'), dedos);
  anillos(196, 143, 12);
  luz(196, 143, 12, 7);
}
