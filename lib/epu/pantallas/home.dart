
import 'package:flutter/widgets.dart';

import '../ilustraciones/logo_epu.dart';
import '../juego/fuente_sticks.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../widgets/boton_jugar.dart';

/// Home (Home.dc.html): logo, botón «Jugar» y el enlace para repasar la
/// preparación. Las sesiones pasadas se quitaron del Home (EPU-23, 21-11-2026).
/// Toda la pantalla se desplaza.
///
/// En «App completa · Eco», «Jugar» lleva a «Eco · elegir nivel».
class PantallaHome extends StatelessWidget {
  const PantallaHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EpuColores.fondo,
      child: SafeArea(
        child: SingleChildScrollView(
          // `padding: 24px 22px 28px; gap 18px; align-items: center`
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
          child: Column(
            children: [
              // Integración: mantener pulsado el logo abre las herramientas del equipo
              // (banco de pruebas). No se ve ni cambia nada para las familias.
              GestureDetector(
                onLongPress: () => EpuSticks.alMantenerLogo?.call(context),
                child: const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: LogoEpu.alto(34),
                ),
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
              // EPU-23 (21-11): el Home ya no muestra las sesiones pasadas (pasan al menú
              // «Tu archivo», EPU-21). «Repasar la preparación» se mantiene (acordado con
              // Joaquín el 23-11) para rehacer el onboarding y volver a vincular sticks.
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
