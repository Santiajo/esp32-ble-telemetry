import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reloj de animación: cuenta los milisegundos desde que el widget aparece y
/// reconstruye [builder] en cada cuadro.
///
/// Sirve para las animaciones CSS `infinite` con varios ritmos a la vez (los
/// colores del botón «Jugar») y para las que el prototipo hace con
/// `setTimeout` en cadena (las manos de «Antes del nivel»): en vez de un
/// [AnimationController] por cosa, todo se calcula a partir del tiempo.
class Reloj extends StatefulWidget {
  const Reloj({super.key, required this.builder, this.activo = true});

  final Widget Function(BuildContext context, double ms) builder;

  /// `false` congela el tiempo en 0 (para «Quitar animaciones»).
  final bool activo;

  @override
  State<Reloj> createState() => _RelojState();
}

class _RelojState extends State<Reloj> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((t) => setState(() => _ms = t.inMicroseconds / 1000));
  double _ms = 0;

  @override
  void initState() {
    super.initState();
    if (widget.activo) _ticker.start();
  }

  @override
  void didUpdateWidget(Reloj anterior) {
    super.didUpdateWidget(anterior);
    if (widget.activo && !_ticker.isActive) _ticker.start();
    if (!widget.activo && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.activo ? _ms : 0);
}
