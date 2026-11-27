import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';

/// «Quién va en cada lado»: los primeros 5 s de la pantalla de juego
/// (EcoJuego.dc.html, capa `.lados`; en el canvas, tablero EcoLados).
///
/// El teléfono va dentro del eje, entre los dos:
/// * **Arriba, del lado de la cámara: el niño.** Mitad coral con «Niño» en
///   grande, girado 180° para que el niño lo lea derecho desde su lado.
/// * **Abajo: el adulto.** Mitad lila con «Adulto».
///
/// Cada mitad es un degradado desde su borde: color sólido hasta el 22 % y
/// transparente en el centro de la pantalla (`linear-gradient(to bottom,
/// coral 0%, coral 22%, transparente 100%)`).
///
/// Animación (5 s en total, igual al prototipo):
/// * **0 → 28 % (1,4 s):** cada color se abre como un círculo difuminado
///   desde el centro de su borde. En CSS es una máscara
///   `radial-gradient(circle closest-side, negro 55 %, transparente 100 %)`
///   que crece de 0 a 1600 × 1600 px (en el marco de 390), con
///   `cubic-bezier(.65,0,.35,1)`, la misma curva de la cortina de la
///   bienvenida.
/// * **28 → 72 % (2,2 s):** queda completo.
/// * **72 → 100 % (1,4 s):** se desvanece (opacidad 1 → 0, ease-in-out) sin
///   cambiar de forma.
/// * **Nombres:** aparecen del 15 al 30 % (opacidad 0 → 1, escala .88 → 1)
///   y se van del 66 al 80 %, con `ease` en cada tramo.
///
/// Con «Quitar animaciones» se ve completo y quieto durante los 5 s.
///
/// [fija] lo deja completo y quieto (para revisarlo, como el tablero del
/// canvas). [alTerminar] se llama a los 5 s; ahí arranca el juego.
class LadosDeCadaUno extends StatefulWidget {
  const LadosDeCadaUno({super.key, this.alTerminar, this.fija = false});

  static const duracion = Duration(milliseconds: 5000);

  final VoidCallback? alTerminar;
  final bool fija;

  @override
  State<LadosDeCadaUno> createState() => _LadosDeCadaUnoState();
}

class _LadosDeCadaUnoState extends State<LadosDeCadaUno> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: LadosDeCadaUno.duracion);

  @override
  void initState() {
    super.initState();
    if (widget.fija) {
      _c.value = .5; // momento en que todo está completo
    } else {
      _c.forward().whenComplete(() => widget.alTerminar?.call());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _curvaApertura = Cubic(.65, 0, .35, 1);

  /// Diámetro de la máscara (en px del marco de 390) en el instante [t] (0–1).
  static double diametro(double t) {
    if (t >= .28) return 1600;
    return 1600 * _curvaApertura.transform(t / .28);
  }

  /// Opacidad del color en el instante [t].
  static double opacidadColor(double t) {
    if (t <= .72) return 1;
    return 1 - Curves.easeInOut.transform(((t - .72) / .28).clamp(0.0, 1.0));
  }

  /// Opacidad y escala de los nombres en el instante [t].
  static (double, double) nombres(double t) {
    double tramo(double a, double b) => Curves.ease.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
    if (t <= .15) return (0, .88);
    if (t < .30) { final p = tramo(.15, .30); return (p, mezclar(.88, 1, p)); }
    if (t <= .66) return (1, 1);
    if (t < .80) { final p = tramo(.66, .80); return (1 - p, mezclar(1, .88, p)); }
    return (0, .88);
  }

  @override
  Widget build(BuildContext context) {
    final quieto = widget.fija || sinMovimiento(context);
    return Semantics(
      liveRegion: true,
      label: 'Quién va en cada lado: arriba, junto a la cámara, el niño; abajo, el adulto',
      excludeSemantics: true,
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, k) {
          final escala = k.maxWidth / 390;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = quieto ? .5 : _c.value;
              final d = diametro(t) * escala, op = opacidadColor(t);
              final (opN, escN) = nombres(t);
              Widget mitad({required bool arriba}) {
                final color = arriba ? EpuColores.coralNino : EpuColores.lilaAdulto;
                final relleno = DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: arriba ? Alignment.topCenter : Alignment.bottomCenter,
                      end: arriba ? Alignment.bottomCenter : Alignment.topCenter,
                      colors: [color, color, color.withValues(alpha: 0)],
                      stops: const [0, .22, 1],
                    ),
                  ),
                );
                // Máscara: círculo centrado en el medio del borde, núcleo
                // opaco hasta el 55 % del radio y borde difuminado.
                final mascara = ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) {
                    final radio = math.max(d / 2, .01);
                    return RadialGradient(
                      center: arriba ? Alignment.topCenter : Alignment.bottomCenter,
                      radius: radio / r.shortestSide,
                      colors: const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                      stops: const [0, .55, 1],
                    ).createShader(r);
                  },
                  child: relleno,
                );
                final texto = Text(
                  arriba ? 'Niño' : 'Adulto',
                  style: EpuTextos.nunito(64, FontWeight.w900, alto: 1, espaciadoEm: -.02, color: EpuColores.blanco)
                      .copyWith(shadows: [sombraTextoCss(0, 2, 18, const Color.fromRGBO(29, 25, 39, .35))]),
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(opacity: op, child: mascara),
                    Center(
                      child: Opacity(
                        opacity: opN,
                        child: Transform.scale(
                          scale: escN,
                          child: arriba ? RotatedBox(quarterTurns: 2, child: texto) : texto,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(child: mitad(arriba: true)),
                  Expanded(child: mitad(arriba: false)),
                ],
              );
            },
          );
        }),
      ),
    );
  }
}
