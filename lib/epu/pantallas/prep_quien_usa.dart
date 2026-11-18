import 'dart:async';

import 'package:flutter/widgets.dart';

import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../widgets/comunes.dart';
import '../widgets/preparacion.dart';

/// Preparación 4 · Quién usa cada stick (Prep5.dc.html).
///
/// Animación de entrada (todo desde que se abre la pantalla):
/// | qué                   | CSS                                              |
/// |-----------------------|--------------------------------------------------|
/// | stick del niño        | `kin .5s ease-out .1s`: aparece (opacidad 0 → 1) |
/// | stick del adulto      | `rise .7s cubic-bezier(.2,.8,.2,1) .8s`: sube 46 px y crece de .9 a 1 mientras aparece |
/// | los dos se separan    | `kmv / pmv 1s cubic-bezier(.4,0,.2,1) 1.5s`: niño +66 px, adulto −66 px |
/// | etiqueta del adulto   | `tag .45s ease-out 2.6s`: sube 6 px y aparece    |
///
/// Al tocar «Comenzar», un círculo del color del fondo crece desde el centro
/// y tapa la pantalla (`cover .6s cubic-bezier(.65,0,.35,1)`); a los 650 ms
/// se pasa a la bienvenida, que empieza con el fondo liso.
class PantallaQuienUsa extends StatefulWidget {
  const PantallaQuienUsa({super.key});

  @override
  State<PantallaQuienUsa> createState() => _PantallaQuienUsaState();
}

class _PantallaQuienUsaState extends State<PantallaQuienUsa> with TickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3050);

  late final AnimationController _entrada = AnimationController(vsync: this, duration: _total)..forward();
  late final AnimationController _cortina =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  late final _ninoAparece = tramoCss(_entrada,
      total: _total, retraso: const Duration(milliseconds: 100), duracion: const Duration(milliseconds: 500), curva: Curves.easeOut);
  late final _adultoSube = tramoCss(_entrada,
      total: _total, retraso: const Duration(milliseconds: 800), duracion: const Duration(milliseconds: 700), curva: CurvasEpu.pop);
  late final _separan = tramoCss(_entrada,
      total: _total, retraso: const Duration(milliseconds: 1500), duracion: const Duration(milliseconds: 1000), curva: CurvasEpu.mover);
  late final _etiqueta = tramoCss(_entrada,
      total: _total, retraso: const Duration(milliseconds: 2600), duracion: const Duration(milliseconds: 450), curva: Curves.easeOut);

  bool _cubriendo = false;
  Timer? _siguiente;

  void _comenzar() {
    if (_cubriendo) return;
    setState(() => _cubriendo = true);
    _cortina.forward(from: 0);
    _siguiente = Timer(const Duration(milliseconds: 650), () {
      if (mounted) EpuNavegacion.ir(context, Pantalla.bienvenida);
    });
  }

  @override
  void dispose() {
    _siguiente?.cancel();
    _entrada.dispose();
    _cortina.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    return PasoPreparacion(
      paso: 4,
      atras: Pantalla.conectar,
      ilustracion: DibujoCentrado(
        ancho: 300,
        alto: 290,
        child: SizedBox(
          width: 300,
          height: 290,
          child: Semantics(
            image: true,
            label: 'El stick naranjo del niño y el stick lila del padre, uno al lado del otro',
            child: AnimatedBuilder(
              animation: _entrada,
              builder: (context, _) => _dibujo(quieto),
            ),
          ),
        ),
      ),
      titulo: const Text.rich(TextSpan(children: [
        TextSpan(text: 'El stick pequeño es del '),
        TextSpan(text: 'niño,', style: TextStyle(color: EpuColores.coralNino)),
        TextSpan(text: '\u00A0el grande, del '), // &nbsp; como en el original
        TextSpan(text: 'adulto', style: TextStyle(color: EpuColores.lilaAdulto)),
      ])),
      texto: 'Cada stick se ajusta al gesto de quien lo usa: un gesto pequeño del adulto llega tan lejos como uno amplio del niño.',
      boton: BotonPrincipal(texto: 'Comenzar', alTocar: _comenzar),
      encima: _cubriendo ? _Cortina(animacion: _cortina, quieto: quieto) : null,
    );
  }

  Widget _dibujo(bool quieto) {
    final sep = quieto ? 1.0 : _separan.value;
    final nino = quieto ? 1.0 : _ninoAparece.value;
    final sube = quieto ? 1.0 : _adultoSube.value;
    final tag = quieto ? 1.0 : _etiqueta.value;

    // Cada stick va en una columna de 120 px, apoyada abajo a 90 px del borde
    // izquierdo; el adulto debajo (z-index 1) y el niño encima (z-index 2).
    Widget columna({required Widget stick, required Widget etiqueta}) => SizedBox(
          width: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [stick, const SizedBox(height: 16), etiqueta],
          ),
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 90,
          bottom: 0,
          child: Transform.translate(
            offset: Offset(-66 * sep, 0),
            child: columna(
              stick: Opacity(
                opacity: sube,
                child: Transform.translate(
                  offset: Offset(0, 46 * (1 - sube)),
                  child: Transform.scale(
                    scale: mezclar(.9, 1, sube),
                    child: const _Stick(ancho: 54, alto: 216, color: EpuColores.lilaAdulto, halo: 30, nucleo: 18, borde: 12),
                  ),
                ),
              ),
              etiqueta: Opacity(
                opacity: tag,
                child: Transform.translate(
                  offset: Offset(0, 6 * (1 - tag)),
                  child: const _Etiqueta(texto: 'Stick del padre', color: EpuColores.lilaAdulto),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 90,
          bottom: 0,
          child: Opacity(
            opacity: nino,
            child: Transform.translate(
              offset: Offset(66 * sep, 0),
              child: columna(
                stick: const _Stick(ancho: 42, alto: 135, color: EpuColores.coralNino, halo: 26, nucleo: 15, borde: 8),
                etiqueta: const _Etiqueta(texto: 'Stick del niño', color: EpuColores.coralSuave),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stick con su luz: halo amarillo al 45 % y núcleo amarillo, centrados en
/// la parte de arriba.
class _Stick extends StatelessWidget {
  const _Stick({
    required this.ancho,
    required this.alto,
    required this.color,
    required this.halo,
    required this.nucleo,
    required this.borde,
  });

  final double ancho, alto, halo, nucleo, borde;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final centro = borde + halo / 2;
    return Container(
      width: ancho,
      height: alto,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(ancho / 2)),
      child: Stack(children: [
        Positioned(
          left: borde,
          top: borde,
          child: Container(
            width: halo,
            height: halo,
            decoration: const BoxDecoration(color: Color.fromRGBO(242, 228, 74, .45), shape: BoxShape.circle),
          ),
        ),
        Positioned(
          left: centro - nucleo / 2,
          top: centro - nucleo / 2,
          child: Container(
            width: nucleo,
            height: nucleo,
            decoration: const BoxDecoration(color: EpuColores.luzStick, shape: BoxShape.circle),
          ),
        ),
      ]),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Text(texto, style: EpuTextos.nunito(13, FontWeight.w800), softWrap: false),
      );
}

/// Círculo de 960 px del color del fondo que crece desde el centro.
class _Cortina extends StatelessWidget {
  const _Cortina({required this.animacion, required this.quieto});

  final Animation<double> animacion;
  final bool quieto;

  @override
  Widget build(BuildContext context) {
    final escala = CurvedAnimation(parent: animacion, curve: CurvasEpu.cortina);
    return IgnorePointer(
      child: ClipRect(
        child: OverflowBox(
          maxWidth: 960,
          maxHeight: 960,
          child: AnimatedBuilder(
            animation: escala,
            builder: (context, child) => Transform.scale(scale: quieto ? 1 : escala.value, child: child),
            child: Container(
              width: 960,
              height: 960,
              decoration: BoxDecoration(
                color: EpuColores.fondo,
                shape: BoxShape.circle,
                boxShadow: [sombraCss(0, 0, 48, const Color.fromRGBO(43, 37, 54, .22))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
