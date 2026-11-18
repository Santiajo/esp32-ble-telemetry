import 'package:flutter/widgets.dart';

import 'estado/estado_eco.dart';
import 'navegacion/rutas.dart';
import 'tema/colores.dart';
import 'tema/textos.dart';

/// La app del flujo Eco, lista para `runApp`.
///
/// Usa [WidgetsApp] y no `MaterialApp` porque ninguna pantalla usa Material:
/// así no se cuelan estilos, ripples ni el efecto de borde al desplazar que
/// el prototipo no tiene.
class EpuEcoApp extends StatefulWidget {
  const EpuEcoApp({super.key, this.estado, this.inicio = Pantalla.inicio});

  /// Estado inicial. Por defecto, el de demostración (igual al prototipo).
  final EstadoEco? estado;

  /// Pantalla con la que abre (útil para revisar una pantalla suelta).
  final Pantalla inicio;

  @override
  State<EpuEcoApp> createState() => _EpuEcoAppState();
}

class _EpuEcoAppState extends State<EpuEcoApp> {
  late final EstadoEco _estado = widget.estado ?? EstadoEco.demo();

  @override
  void dispose() {
    if (widget.estado == null) _estado.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EpuEstado(
      estado: _estado,
      child: WidgetsApp(
        title: 'Epu',
        color: EpuColores.fondo,
        debugShowCheckedModeBanner: false,
        initialRoute: widget.inicio.name,
        onGenerateRoute: EpuNavegacion.generar,
        navigatorObservers: [EpuNavegacion.registro],
        textStyle: EpuTextos.nunito(16, FontWeight.w600),
        builder: (context, child) => ScrollConfiguration(
          behavior: const _SinBrilloAlBorde(),
          child: child!,
        ),
      ),
    );
  }
}

/// Desplazamiento sin el brillo/estiramiento de Android al llegar al borde.
class _SinBrilloAlBorde extends ScrollBehavior {
  const _SinBrilloAlBorde();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
