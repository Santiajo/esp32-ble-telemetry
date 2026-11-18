import 'package:flutter/widgets.dart';

import '../ilustraciones/preparacion.dart';
import '../navegacion/rutas.dart';
import '../widgets/comunes.dart';
import '../widgets/preparacion.dart';

/// Preparación 1 · Permisos (Prep1.dc.html).
///
/// «Conceder permisos» es donde la app real pide Bluetooth y el acceso a
/// No Molestar (en Android, `ACCESS_NOTIFICATION_POLICY`). En el prototipo
/// solo avanza.
class PantallaPermisos extends StatelessWidget {
  const PantallaPermisos({super.key});

  @override
  Widget build(BuildContext context) {
    return PasoPreparacion(
      paso: 1,
      atras: Pantalla.inicio,
      // `flex: 1; min-height: 250px; padding: 24px`; SVG de 310 px.
      ilustracion: const DibujoCentrado(
        ancho: 310,
        alto: 310 * 260 / 320,
        relleno: EdgeInsets.all(24),
        child: LienzoSvg(
          vbAncho: 320,
          vbAlto: 260,
          ancho: 310,
          pintor: pintarPermisos,
          etiqueta: 'Los dos sticks, lila y naranjo, enviándose señal',
        ),
      ),
      titulo: const Text('Activa Bluetooth y No Molestar'),
      texto: 'Así el teléfono se conecta con los sticks y nada interrumpe el juego.',
      boton: BotonPrincipal(
        texto: 'Conceder permisos',
        alTocar: () => EpuNavegacion.ir(context, Pantalla.sinAvisos),
      ),
    );
  }
}
