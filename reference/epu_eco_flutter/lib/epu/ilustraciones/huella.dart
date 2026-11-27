import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../datos/niveles.dart';
import '../tema/colores.dart';
import 'huella_datos.dart';

/// Dibujo del recuerdo («huella»): hilos lila (adulto) y coral (niño) que
/// salen del centro hacia donde se movió cada stick, y luces amarillas donde
/// se encontraron.
///
/// Se usa en dos tamaños:
/// * «Eco · el recuerdo»: todo el ancho disponible (346 px en el marco de
///   390), cuadrado.
/// * Miniaturas de «Tu archivo» (menú del Home): 80 px (EcoHuella.dc.html).
///
/// **Es estático.** El prototipo tiene el código de una animación (los hilos
/// crecen y se mecen), pero la versión aprobada la deja quieta: se dibuja el
/// cuadro final, que equivale a `t = 60 s` (todo ya creció, `e = 1`) y fija
/// el vaivén en `sin(60 × velocidad + fase)`. No hay fondo propio: va directo
/// sobre el fondo de la pantalla.
///
/// [resaltado]: trozo que está sonando al «Escuchar la melodía» (−1 =
/// ninguno). Ese trozo pasa a peso 1,6 (más opaco, su luz ×1,35) y los demás
/// a 0,3. El cambio es instantáneo, igual que en el prototipo.
class DibujoHuella extends StatelessWidget {
  const DibujoHuella({super.key, required this.nivel, this.resaltado = -1, this.lado, this.etiqueta});

  final NivelEco nivel;
  final int resaltado;

  /// Lado en px. `null` = todo el ancho disponible.
  final double? lado;

  /// Descripción accesible (`aria-label`).
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    final datos = DatosHuella.de(nivel.id, nivel.pasos, nivel.guiaAdulto);
    final pintura = CustomPaint(painter: PintorHuella(datos, resaltado));
    final cuadro = lado == null
        ? AspectRatio(aspectRatio: 1, child: pintura)
        : SizedBox.square(dimension: lado, child: pintura);
    return Semantics(image: true, label: etiqueta, child: cuadro);
  }
}

class PintorHuella extends CustomPainter {
  PintorHuella(this.datos, this.resaltado);

  final DatosHuella datos;
  final int resaltado;

  /// Instante fijo del dibujo estático (segundos).
  static const double _t = 60;

  static const _adulto = (179, 162, 220), _nino = (232, 94, 69);

  double _peso(int trozo) => resaltado < 0 ? 1 : (resaltado == trozo ? 1.6 : .3);

  @override
  void paint(Canvas canvas, Size size) {
    // El prototipo dibuja en píxeles del canvas y escala grosores y luces
    // por W / 346. Aquí W es el ancho lógico: el resultado es el mismo.
    final w = size.width, r = w / 2, cx = w / 2, cy = size.height / 2, k346 = w / 346;

    for (final h in datos.hilos) {
      final vaiven = math.sin(_t * h.velocidad + h.fase);
      final (cr, cg, cb) = h.adulto ? _adulto : _nino;
      final pincel = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = h.ancho * k346
        ..isAntiAlias = true
        ..color = Color.fromRGBO(cr, cg, cb, math.min(.9, h.alfa * _peso(h.trozo)));
      final p = Path();
      if (h.giro) {
        // Espiral: 60 pasos, del radio r0 hasta 85 % del largo.
        const pasos = 60;
        final a0 = h.fase;
        for (var s = 0; s <= pasos; s++) {
          final u = s / pasos;
          final a = a0 + h.sentido * u * h.vueltas * 6.283;
          final rr = r * (h.r0 + (h.lejos * .85 - h.r0) * u) * (1 + .03 * vaiven * u);
          final x = cx + math.cos(a) * rr, y = cy + math.sin(a) * rr;
          s == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
        }
      } else {
        // Curva cuadrática del centro hacia la dirección, con el punto de
        // control corrido hacia un lado (la «curva» de cada hilo).
        final a = (h.angulo + vaiven * 4) * math.pi / 180, ux = math.cos(a), uy = math.sin(a);
        final l0 = r * h.r0, l1 = r * h.lejos, k = h.curva * r * .35 * (1 + .15 * vaiven);
        final mx = cx + ux * (l0 + l1) / 2 - uy * k, my = cy + uy * (l0 + l1) / 2 + ux * k;
        p
          ..moveTo(cx + ux * l0, cy + uy * l0)
          ..quadraticBezierTo(mx, my, cx + ux * l1, cy + uy * l1);
      }
      canvas.drawPath(p, pincel);
    }

    // Luces de encuentro: halo (r 13, opacidad .45) y núcleo (r 7,5), con
    // un leve latido fijo (1 + .08 · sin(t · .6 + fase)).
    for (final f in datos.flores) {
      final lat = 1 + .08 * math.sin(_t * .6 + f.fase);
      final op = math.min(1.0, _peso(f.trozo));
      final k = k346 * lat * (resaltado == f.trozo ? 1.35 : 1);
      final c = Offset(cx + f.x * r, cy + f.y * r);
      canvas
        ..drawCircle(c, 13 * k, Paint()..color = EpuColores.luzStick.withValues(alpha: .45 * op))
        ..drawCircle(c, 7.5 * k, Paint()..color = EpuColores.luzStick.withValues(alpha: op));
    }
  }

  @override
  bool shouldRepaint(PintorHuella old) => old.datos != datos || old.resaltado != resaltado;
}
