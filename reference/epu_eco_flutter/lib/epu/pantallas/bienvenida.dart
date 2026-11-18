import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ilustraciones/logo_epu.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../util/css.dart';
import 'home.dart';

/// Bienvenida · logo Epu (Bienvenida.dc.html).
///
/// Debajo ya está dibujado el Home; encima, una capa del color del fondo y
/// el logo. Línea de tiempo (ms desde que se abre):
/// ```
///    100 –  700  pop:  el logo aparece en el centro y crece de ×2,2 a ×3
///                      (cubic-bezier(.2,.8,.2,1))
///   1400 – 2250  land: baja de ×3 a ×1 hasta su lugar en el Home
///                      (cubic-bezier(.65,0,.35,1))
///   1850 – 2450  out:  la capa de fondo se desvanece (ease-in-out)
///   2500         hide: el logo de la bienvenida se oculta (queda el del Home)
///   2600         pasa al Home
/// ```
/// Con «Quitar animaciones»: el logo se ve grande en el centro, se oculta al
/// segundo y la capa se desvanece en 0,3 s lineal.
class PantallaBienvenida extends StatefulWidget {
  const PantallaBienvenida({super.key});

  @override
  State<PantallaBienvenida> createState() => _PantallaBienvenidaState();
}

class _PantallaBienvenidaState extends State<PantallaBienvenida> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  Timer? _siguiente;

  @override
  void initState() {
    super.initState();
    _siguiente = Timer(const Duration(milliseconds: 2600), () {
      // Desde el Home no se vuelve a la preparación: se limpia la pila.
      if (mounted) EpuNavegacion.empezarEn(context, Pantalla.home);
    });
  }

  @override
  void dispose() {
    _siguiente?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    return ColoredBox(
      color: EpuColores.fondo,
      child: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: PantallaHome())),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final ms = _c.value * 2600;
                return Stack(children: [
                  _capa(ms, quieto),
                  _logo(ms, quieto),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Capa del color del fondo que tapa el Home (`.iris`).
  Widget _capa(double ms, bool quieto) {
    final (inicio, dur, curva) = quieto ? (1000.0, 300.0, Curves.linear) : (1850.0, 600.0, Curves.easeInOut);
    final p = ((ms - inicio) / dur).clamp(0.0, 1.0);
    final opacidad = 1 - curva.transform(p);
    if (opacidad <= 0) return const SizedBox.shrink();
    return Positioned.fill(child: Opacity(opacity: opacidad, child: const ColoredBox(color: EpuColores.fondo)));
  }

  /// El logo (`.logo`): 34 px de alto, a 26 px del borde superior.
  Widget _logo(double ms, bool quieto) {
    if (ms >= (quieto ? 1000 : 2500)) return const SizedBox.shrink();

    double opacidad = 1, escala = 3, bajada = 1; // bajada 1 = en el centro
    if (!quieto) {
      if (ms < 1400) {
        final p = CurvasEpu.pop.transform(((ms - 100) / 600).clamp(0.0, 1.0));
        opacidad = p;
        escala = mezclar(2.2, 3, p);
      } else {
        final q = CurvasEpu.cortina.transform(((ms - 1400) / 850).clamp(0.0, 1.0));
        escala = mezclar(3, 1, q);
        bajada = 1 - q;
      }
    }

    return SafeArea(
      child: LayoutBuilder(builder: (context, k) {
        // En el marco de 844 px del prototipo el desplazamiento es 379 px:
        // del centro del logo (26 + 17 = 43 px) al centro de la pantalla.
        final alCentro = k.maxHeight / 2 - (26 + 17);
        return Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            top: 26,
            child: Center(
              child: Opacity(
                opacity: opacidad.clamp(0.0, 1.0),
                // `transform: translateY(…) scale(…)` con origen en el centro.
                child: Transform.translate(
                  offset: Offset(0, alCentro * bajada),
                  child: Transform.scale(scale: escala, child: const LogoEpu.alto(34)),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}
