import 'package:flutter/widgets.dart';

import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../ilustraciones/geometria_mano.dart';
import '../ilustraciones/manos.dart';
import '../ilustraciones/preparacion.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../widgets/comunes.dart';
import '../widgets/reloj.dart';

/// Eco · quién guía (EcoGuia.dc.html).
///
/// Las dos manos quietas con las etiquetas «Guía» y «Sigue». La luz del
/// stick de quien guía parpadea (`bl`: opacidad 1 → .35 → 1) y su anillo
/// late (`hr`: escala .8 → 1.25 → .8), los dos cada 1,1 s, ease-in-out.
/// El dibujo entra con `pop .5s cubic-bezier(.2,.8,.2,1) .1s` (sube 10 px y
/// crece de .96 a 1 mientras aparece).
class PantallaEcoGuia extends StatefulWidget {
  const PantallaEcoGuia({super.key});

  @override
  State<PantallaEcoGuia> createState() => _PantallaEcoGuiaState();
}

class _PantallaEcoGuiaState extends State<PantallaEcoGuia> with SingleTickerProviderStateMixin {
  late final AnimationController _entrada =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  late final Animation<double> _pop = tramoCss(_entrada,
      total: const Duration(milliseconds: 600),
      retraso: const Duration(milliseconds: 100),
      duracion: const Duration(milliseconds: 500),
      curva: CurvasEpu.pop);

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    final n = NivelEco.de(EpuEstado.of(context).nivel);
    final adulto = n.guiaAdulto;

    final dibujo = ZonaIlustracion(
      minimo: 260,
      maximo: 388,
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) {
          final p = quieto ? 1.0 : _pop.value;
          return Opacity(
            opacity: p.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - p)),
              child: Transform.scale(scale: mezclar(.96, 1, p), child: child),
            ),
          );
        },
        child: DibujoCentrado(
          ancho: 285,
          alto: 285 * 100 / 120,
          child: Reloj(
            activo: !quieto,
            builder: (context, ms) => LienzoSvg(
              vbAncho: 120,
              vbAlto: 100,
              ancho: 285,
              etiqueta: adulto
                  ? 'Guía el adulto: la luz de su stick lila parpadea. El niño sigue.'
                  : 'Guía el niño: la luz de su stick naranjo parpadea. El adulto sigue.',
              pintor: (c) => _pintarGuia(c, adulto: adulto, ms: ms, quieto: quieto),
            ),
          ),
        ),
      ),
    );

    final textos = Column(
      children: [
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Guía el '),
            TextSpan(
              text: adulto ? 'adulto' : 'niño',
              style: TextStyle(color: adulto ? EpuColores.lilaAdulto : EpuColores.coralNino),
            ),
          ]),
          style: EpuTextos.tituloGuia,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(n.textoGuia, style: EpuTextos.cuerpo, textAlign: TextAlign.center),
      ],
    );

    return PantallaBase(
      atras: Pantalla.antes,
      relleno: const EdgeInsets.fromLTRB(22, 66, 22, 28),
      child: ColumnaConBoton(
        separacion: 18,
        arriba: [
          Text('Nivel ${n.id} de 7 · ${n.peculiaridad}', style: EpuTextos.etiqueta, textAlign: TextAlign.center),
          dibujo,
          textos,
        ],
        // La nota lleva `margin: auto 0 -6px`: va pegada al botón (18 − 6).
        boton: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'En el juego, la luz del que guía parpadea hasta que elige.',
              style: EpuTextos.detalle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18 - 6),
            BotonPrincipal(
              texto: 'Empezar nivel',
              alTocar: () => EpuNavegacion.ir(context, Pantalla.calibrar),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinta la escena de «Quién guía» en el viewBox 120 × 100.
void _pintarGuia(Canvas c, {required bool adulto, required double ms, required bool quieto}) {
  final t = (ms % 1100) / 1100;
  final escalaAnillo = quieto ? 1.0 : latido(t, .8, 1.25);
  final parpadeo = quieto ? 1.0 : latido(t, 1, .35);

  // Etiquetas: la oscura «Guía» sobre quien guía y la blanca «Sigue» sobre el otro.
  const enAdulto = Offset(30, 6), enNino = Offset(88, 27);
  _etiqueta(c, adulto ? enAdulto : enNino, 'Guía', oscura: true);
  _etiqueta(c, adulto ? enNino : enAdulto, 'Sigue', oscura: false);

  final quieta = GeometriaMano(0, 0);
  dibujarMano(c, quieta, EstiloMano.adulto,
      LuzMano(anilloOpacidad: adulto ? .9 : 0, anilloEscala: escalaAnillo, opacidad: adulto ? parpadeo : 1));
  dibujarMano(c, quieta, EstiloMano.nino,
      LuzMano(anilloOpacidad: adulto ? 0 : .9, anilloEscala: escalaAnillo, opacidad: adulto ? 1 : parpadeo));
}

/// Píldora de 21 × 9 con texto de 5 unidades (800), centrada en [en].
void _etiqueta(Canvas c, Offset en, String texto, {required bool oscura}) {
  final rect = RRect.fromRectAndRadius(Rect.fromLTWH(en.dx - 10.5, en.dy - 5, 21, 9), const Radius.circular(4.5));
  if (oscura) {
    c.drawRRect(rect, Paint()..color = EpuColores.tinta);
  } else {
    c
      ..drawRRect(rect, Paint()..color = EpuColores.blanco)
      ..drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = EpuColores.tinta.withValues(alpha: .25),
      );
  }
  // `<text x="0" y="1.8" text-anchor="middle">`: 1,8 es la línea base.
  final tp = TextPainter(
    text: TextSpan(
      text: texto,
      style: TextStyle(
        fontFamily: EpuTextos.familia,
        fontSize: 5,
        fontWeight: FontWeight.w800,
        color: oscura ? EpuColores.blanco : EpuColores.tinta,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  tp.paint(c, Offset(en.dx - tp.width / 2, en.dy + 1.8 - base));
}
