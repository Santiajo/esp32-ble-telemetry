import 'package:flutter/widgets.dart';

import '../navegacion/rutas.dart';
import '../tema/textos.dart';
import 'comunes.dart';

/// Esqueleto común de las 4 pantallas de preparación.
///
/// CSS de las cuatro:
/// ```
/// padding: 66px 18px 20px; flex column; gap 14px
///   <ol> pasos (34 px)
///   <div flex:1; flex column; gap 16px>
///     ilustración (flex: 1; min-height 250 px, 220 en «Conecta»)
///     título h2 26 px + párrafo 15 px (centrados)
///     botón
/// ```
class PasoPreparacion extends StatelessWidget {
  const PasoPreparacion({
    super.key,
    required this.paso,
    required this.atras,
    required this.ilustracion,
    required this.titulo,
    required this.texto,
    required this.boton,
    this.minimoIlustracion = 250,
    this.encima,
  });

  final int paso;
  final Pantalla atras;
  final Widget ilustracion;
  final double minimoIlustracion;

  /// El h2. Va con el estilo de título ya aplicado (sirve [Text.rich] para
  /// pintar palabras de otro color).
  final Widget titulo;
  final String texto;
  final Widget boton;

  /// Capa por encima de toda la pantalla (el círculo que cubre en
  /// «Quién usa cada stick»).
  final Widget? encima;

  @override
  Widget build(BuildContext context) {
    final cuerpo = Padding(
      padding: const EdgeInsets.fromLTRB(18, 66, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PasosPreparacion(actual: paso),
          const SizedBox(height: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minimoIlustracion),
                    child: ilustracion,
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    DefaultTextStyle(
                      style: EpuTextos.tituloPequeno,
                      textAlign: TextAlign.center,
                      child: titulo,
                    ),
                    const SizedBox(height: 8),
                    Text(texto, style: EpuTextos.cuerpo, textAlign: TextAlign.center),
                  ],
                ),
                const SizedBox(height: 16),
                boton,
              ],
            ),
          ),
        ],
      ),
    );
    return PantallaBase(atras: atras, encima: encima, child: cuerpo);
  }
}
