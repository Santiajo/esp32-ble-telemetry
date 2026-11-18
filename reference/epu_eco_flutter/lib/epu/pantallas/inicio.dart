import 'package:flutter/widgets.dart';

import '../ilustraciones/logo_epu.dart';
import '../navegacion/rutas.dart';
import '../tema/textos.dart';
import '../widgets/comunes.dart';

/// Inicio (Main.dc.html): logo, lema y «¡Comencemos!».
///
/// CSS: `padding 24 22 28; flex column; gap 14px`. El logo y el botón llevan
/// `margin-top: auto`, así que el espacio libre se reparte en partes iguales
/// arriba del logo y arriba del botón (los dos [Spacer]).
class PantallaInicio extends StatelessWidget {
  const PantallaInicio({super.key});

  @override
  Widget build(BuildContext context) {
    return PantallaBase(
      relleno: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        children: [
          const Spacer(),
          // h1 con line-height 0: mide lo mismo que la imagen (150 px de ancho).
          const LogoEpu.ancho(150),
          const SizedBox(height: 6 + 14), // margin-bottom 6 + gap 14
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              'Un instrumento para sonar juntos',
              style: EpuTextos.lema,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          const Spacer(),
          BotonPrincipal(
            texto: '¡Comencemos!',
            alTocar: () => EpuNavegacion.ir(context, Pantalla.permisos),
          ),
        ],
      ),
    );
  }
}
