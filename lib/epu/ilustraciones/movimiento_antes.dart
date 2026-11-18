import '../datos/niveles.dart';

/// Movimiento de los sticks en «Antes del nivel», sin nada de Flutter (se
/// puede probar con `dart test` contra el JavaScript del prototipo).
///
/// Reproduce las dos cadenas de `setTimeout` de EcoAntes.dc.html:
/// * `tick()`: cambia de fase según la tabla `PH` del nivel. Arranca a los
///   600 ms, así que la primera fase dura 600 ms más que su valor.
/// * `step()`: corre al abrir y luego cada 33 ms; acerca cada ángulo un 22 %
///   a su objetivo y lo deja exacto cuando le falta menos de 0,2°.
///
/// [avanzar] recibe los milisegundos desde que se abrió la pantalla y
/// ejecuta todos los cambios de fase y pasos de 33 ms que tocan hasta ahí,
/// así el resultado no depende de los cuadros por segundo del teléfono.
class MovimientoAntes {
  MovimientoAntes(this.fases, {this.quieta = false, this.alCambiarFase}) {
    if (quieta) cur = objetivo(0); // prefers-reduced-motion: primera pose fija
    _finFase = 600.0 + fases[0].ms;
  }

  final List<FaseAntes> fases;

  /// «Quitar animaciones»: no cambia de fase ni se mueve.
  final bool quieta;

  /// Se llama en cada cambio de fase con el instante exacto del cambio.
  final void Function(int fase, double inicio)? alCambiarFase;

  /// Ángulos actuales [θ adulto, φ adulto, θ niño, φ niño].
  List<double> cur = [0, 0, 0, 0];

  int fase = 0;
  int _faseAnterior = 0;
  double _inicioFase = 0;
  late double _finFase;
  double _proximoPaso = 0;

  void avanzar(double ms) {
    if (quieta) return;
    while (ms >= _finFase) {
      final inicio = _finFase;
      _faseAnterior = fase;
      fase = (fase + 1) % fases.length;
      _inicioFase = inicio;
      _finFase = inicio + fases[fase].ms;
      alCambiarFase?.call(fase, inicio);
    }
    while (_proximoPaso <= ms) {
      // Si en este cuadro hubo un cambio de fase, los pasos anteriores a ese
      // cambio usan el objetivo de la fase anterior.
      final g = objetivo(_proximoPaso >= _inicioFase ? fase : _faseAnterior);
      cur = [
        for (var i = 0; i < 4; i++)
          () {
            final d = g[i] - cur[i];
            if (d == 0) return cur[i];
            return d.abs() < .2 ? g[i] : cur[i] + d * .22;
          }(),
      ];
      _proximoPaso += 33;
    }
  }

  /// Ángulos objetivo de una fase (tabla `POSE`).
  List<double> objetivo(int f) {
    final a = poseDe(fases[f].adulto), c = poseDe(fases[f].nino);
    return [a.th, a.ph, c.th, c.ph];
  }
}
