import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../estado/estado_eco.dart';
import '../ilustraciones/logo_epu.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../widgets/boton_jugar.dart';

/// Home (Home.dc.html): logo, botón «Jugar», sesiones pasadas y el enlace
/// para repasar la preparación. Toda la pantalla se desplaza.
///
/// En «App completa · Eco», «Jugar» lleva a «Eco · elegir nivel» y cada
/// sesión pasada abre «Eco · el recuerdo».
class PantallaHome extends StatelessWidget {
  const PantallaHome({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = EpuEstado.of(context);
    return ColoredBox(
      color: EpuColores.fondo,
      child: SafeArea(
        child: SingleChildScrollView(
          // `padding: 24px 22px 28px; gap 18px; align-items: center`
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: LogoEpu.alto(34),
              ),
              const SizedBox(height: 18),
              // Zona del botón: `min-height: 573px`, botón centrado.
              SizedBox(
                height: 573,
                child: Center(
                  child: BotonJugar(
                    alTocar: () => EpuNavegacion.ir(context, Pantalla.elegirNivel),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Sesiones pasadas', style: EpuTextos.tituloSeccion),
                    const SizedBox(height: 10),
                    for (var i = 0; i < estado.sesiones.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _TarjetaSesion(
                        sesion: estado.sesiones[i],
                        alTocar: () => EpuNavegacion.ir(context, Pantalla.recuerdo),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => EpuNavegacion.ir(context, Pantalla.permisos),
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      'Repasar la preparación',
                      style: EpuTextos.nunito(14, FontWeight.w700, color: EpuColores.textoSecundario)
                          .copyWith(decoration: TextDecoration.underline, decorationColor: EpuColores.textoSecundario),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de una sesión: título, minutos, 7 barritas (una por nivel) y el
/// botón de compartir.
class _TarjetaSesion extends StatelessWidget {
  const _TarjetaSesion({required this.sesion, required this.alTocar});

  final SesionPasada sesion;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(color: EpuColores.blanco, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: alTocar,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sesion.titulo,
                          style: EpuTextos.nunito(13, FontWeight.w800),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${sesion.minutos} min',
                          style: EpuTextos.nunito(13, FontWeight.w700, color: EpuColores.textoSecundario)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      for (var i = 0; i < sesion.partes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: sesion.partes[i] ? EpuColores.teal : EpuColores.linea,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Compartir: en el prototipo no hace nada todavía.
          Semantics(
            button: true,
            label: 'Compartir sesión',
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: EpuColores.fondo, shape: BoxShape.circle),
              child: const CustomPaint(painter: _IconoCompartir()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ícono de compartir hecho con tres `<span>` en el prototipo: una bandeja
/// sin tapa, un palito y una punta de flecha (cuadrado con dos bordes girado).
class _IconoCompartir extends CustomPainter {
  const _IconoCompartir();

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()..color = EpuColores.tinta;
    // Bandeja: caja 16 × 10 en (12, 20), bordes de 2 px a los lados y abajo,
    // esquinas inferiores de 3 px.
    final exterior = RRect.fromLTRBAndCorners(12, 20, 28, 30,
        bottomLeft: const Radius.circular(3), bottomRight: const Radius.circular(3));
    final interior = RRect.fromLTRBAndCorners(14, 20, 26, 28,
        bottomLeft: const Radius.circular(1), bottomRight: const Radius.circular(1));
    canvas.drawDRRect(exterior, interior, tinta);
    // Palito: 2 × 13 en (19, 10), radio 1.
    canvas.drawRRect(RRect.fromLTRBR(19, 10, 21, 23, const Radius.circular(1)), tinta);
    // Punta: caja 8 × 8 en (16, 11) con borde izquierdo y superior de 2 px,
    // girada 45° sobre su centro (20, 15).
    canvas
      ..save()
      ..translate(20, 15)
      ..rotate(math.pi / 4)
      ..translate(-4, -4)
      ..drawRect(const Rect.fromLTWH(0, 0, 8, 2), tinta)
      ..drawRect(const Rect.fromLTWH(0, 0, 2, 8), tinta)
      ..restore();
  }

  @override
  bool shouldRepaint(_IconoCompartir oldDelegate) => false;
}
