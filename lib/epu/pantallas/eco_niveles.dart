import 'package:flutter/widgets.dart';

import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../ilustraciones/geometria_mano.dart';
import '../ilustraciones/manos.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../widgets/comunes.dart';

/// Eco · elegir nivel (EcoNiveles.dc.html).
///
/// Grilla de 2 columnas con los niveles 1 a 6 y el 7 a lo ancho. Cada
/// tarjeta muestra la pose de las manos de ese nivel (sin animación), el
/// nombre, instrumento, peculiaridad, dificultad y si ya se completó.
///
/// Toda la pantalla se desplaza; el botón «Atrás» queda fijo arriba
/// (`position: sticky; top: 14px`).
class PantallaEcoNiveles extends StatelessWidget {
  const PantallaEcoNiveles({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = EpuEstado.of(context);

    void elegir(int id) {
      estado.nivel = id;
      EpuNavegacion.ir(context, Pantalla.antes);
    }

    Widget tarjeta(int id) => _TarjetaNivel(
          nivel: NivelEco.de(id),
          completado: estado.completado(id),
          alTocar: () => elegir(id),
        );

    // Fila de dos tarjetas con la misma altura (en CSS grid las celdas de una
    // fila se estiran a la más alta).
    Widget fila(int a, int b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: tarjeta(a)), const SizedBox(width: 10), Expanded(child: tarjeta(b))],
          ),
        );

    return PantallaBase(
      atras: Pantalla.home,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 66, 22, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '¿Qué melodía van a descubrir?',
                style: EpuTextos.tituloGrande,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            fila(1, 2),
            const SizedBox(height: 10),
            fila(3, 4),
            const SizedBox(height: 10),
            fila(5, 6),
            const SizedBox(height: 10),
            _TarjetaNivel(nivel: NivelEco.de(7), completado: estado.completado(7), ancha: true, alTocar: () => elegir(7)),
          ],
        ),
      ),
    );
  }
}

class _TarjetaNivel extends StatelessWidget {
  const _TarjetaNivel({
    required this.nivel,
    required this.completado,
    required this.alTocar,
    this.ancha = false,
  });

  final NivelEco nivel;
  final bool completado;
  final VoidCallback alTocar;

  /// La del nivel 7 ocupa las dos columnas y pone el dibujo a la izquierda.
  final bool ancha;

  @override
  Widget build(BuildContext context) {
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${nivel.id} · ${nivel.nombre}', style: EpuTextos.tarjetaTitulo),
        const SizedBox(height: 4),
        Text('${nivel.instrumento} · ${nivel.peculiaridad}', style: EpuTextos.mini),
        const SizedBox(height: 4 + 4), // gap 4 + margin-top 4
        PuntosDificultad(dificultad: nivel.dificultad, estilo: EpuTextos.miniDificultad),
      ],
    );
    final dibujo = MiniaturaNivel(nivel: nivel);

    return Semantics(
      button: true,
      label: '${nivel.id} · ${nivel.nombre}, ${nivel.instrumento} · ${nivel.peculiaridad}, '
          '${nivel.dificultadTexto}, ${completado ? 'completado' : 'sin completar'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: alTocar,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: EpuColores.blanco, borderRadius: BorderRadius.circular(22)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ancha
                  ? Row(children: [dibujo, const SizedBox(width: 14), Flexible(child: textos)])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [dibujo, const SizedBox(height: 10), textos],
                    ),
              // Insignia arriba a la derecha (top 12 / right 12 de la tarjeta).
              Positioned(top: 12 - 14, right: 12 - 14, child: _Insignia(completado: completado)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Círculo de 26 px: teal con check si está completado, solo borde si no.
class _Insignia extends StatelessWidget {
  const _Insignia({required this.completado});

  final bool completado;

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completado ? EpuColores.teal : null,
          border: completado ? null : Border.all(color: EpuColores.pendienteBorde, width: 2),
        ),
        child: completado ? const IconoCheck.tarjeta() : null,
      );
}

/// Miniatura de 84 × 70 px con la pose congelada de cada nivel.
class MiniaturaNivel extends StatelessWidget {
  const MiniaturaNivel({super.key, required this.nivel});

  final NivelEco nivel;

  @override
  Widget build(BuildContext context) =>
      ClipRect(child: CustomPaint(size: const Size(84, 70), painter: _MiniaturaPainter(nivel.miniatura)));
}

class _MiniaturaPainter extends CustomPainter {
  _MiniaturaPainter(this.m);
  final Miniatura m;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 120);

    void flecha(FlechaMiniatura f, Offset en) => f.giro
        ? dibujarGiro(canvas, en: en, opacidad: f.opacidad, miniatura: true)
        : dibujarFlecha(canvas, en: en, grados: f.grados, opacidad: f.opacidad, miniatura: true);
    flecha(m.flechaAdulto, PosicionesFlecha.adulto);
    flecha(m.flechaNino, PosicionesFlecha.nino);

    final luz = LuzMano(anilloOpacidad: m.anillo ? 1 : 0);
    dibujarMano(canvas, GeometriaMano(m.adulto.th, m.adulto.ph), EstiloMano.adulto.engrosado(1.4), luz);
    dibujarMano(canvas, GeometriaMano(m.nino.th, m.nino.ph), EstiloMano.nino.engrosado(1.8), luz);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniaturaPainter old) => old.m != m;
}
