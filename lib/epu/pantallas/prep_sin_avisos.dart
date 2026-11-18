import 'package:flutter/widgets.dart';

import '../ilustraciones/preparacion.dart';
import '../navegacion/rutas.dart';
import '../widgets/comunes.dart';
import '../widgets/preparacion.dart';

/// Preparación 2 · Sin interrupciones (Prep2.dc.html).
///
/// La app real activa aquí el modo No Molestar mientras dure el juego.
class PantallaSinAvisos extends StatelessWidget {
  const PantallaSinAvisos({super.key});

  @override
  Widget build(BuildContext context) {
    return PasoPreparacion(
      paso: 2,
      atras: Pantalla.permisos,
      // `flex: 1; min-height 250; padding 20px 24px`; SVG de 300 px.
      ilustracion: const DibujoCentrado(
        ancho: 300,
        alto: 300 * 280 / 320,
        relleno: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: LienzoSvg(
          vbAncho: 320,
          vbAlto: 280,
          ancho: 300,
          pintor: pintarSinAvisos,
          etiqueta: 'Los dos sticks jugando dentro de un círculo; los avisos quedan afuera',
        ),
      ),
      titulo: const Text('Sin interrupciones'),
      texto: 'Mientras juegan, el teléfono no suena, no vibra ni muestra avisos.',
      boton: BotonPrincipal(
        texto: 'Continuar',
        alTocar: () => EpuNavegacion.ir(context, Pantalla.conectar),
      ),
    );
  }
}
