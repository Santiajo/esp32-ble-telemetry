import 'package:flutter/widgets.dart';

import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import 'reloj.dart';

/// Botón «Jugar» del Home: círculo de 230 px lila con cinco manchas de color
/// que se mueven lento, cada una con su propio ritmo (Home.dc.html, `.gas`).
///
/// Cada mancha es un círculo de 140 % del botón (322 px) con un degradado
/// radial que se desvanece, movido con `translate(x%, y%) scale(s)`. Los
/// porcentajes del translate son del tamaño de la mancha (322 px).
class BotonJugar extends StatelessWidget {
  const BotonJugar({super.key, required this.alTocar});

  final VoidCallback alTocar;

  static const double lado = 230;

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    return Semantics(
      button: true,
      label: 'Jugar',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: alTocar,
        child: SizedBox.square(
          dimension: lado,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(
                child: Reloj(
                  activo: !quieto,
                  builder: (context, ms) => CustomPaint(
                    size: const Size.square(lado),
                    painter: _ManchasPainter(ms / 1000, quietas: quieto),
                  ),
                ),
              ),
              Text(
                'Jugar',
                style: EpuTextos.nunito(32, FontWeight.w900, color: EpuColores.blanco).copyWith(
                  shadows: [sombraTextoCss(0, 1, 10, const Color.fromRGBO(43, 37, 54, .25))],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una mancha: color, dónde termina su degradado, duración y fotogramas
/// (posición, [x %, y %, escala]).
class _Mancha {
  const _Mancha(this.color, this.alfa, this.fin, this.segundos, this.fotogramas);
  final Color color;
  final double alfa, fin, segundos;
  final Fotogramas fotogramas;
}

// Copiado de los @keyframes ga…ge (todos ease-in-out en cada tramo).
const _manchas = [
  _Mancha(Color(0xFFD6CCEE), .95, .55, 9, Fotogramas([
    (0, [-24, -20, 1]),
    (.33, [22, -12, 1.2]),
    (.66, [4, 26, .9]),
    (1, [-24, -20, 1]),
  ])),
  _Mancha(Color(0xFFF4C3B6), .95, .50, 10.5, Fotogramas([
    (0, [24, 18, .9]),
    (.30, [-18, 24, 1.15]),
    (.65, [-8, -26, 1]),
    (1, [24, 18, .9]),
  ])),
  _Mancha(Color(0xFFF2E44A), .7, .46, 13, Fotogramas([
    (0, [10, -26, 1]),
    (.40, [-26, 4, .85]),
    (.75, [20, 20, 1.2]),
    (1, [10, -26, 1]),
  ])),
  _Mancha(Color(0xFFE85E45), .55, .44, 14, Fotogramas([
    (0, [-18, 24, 1.1]),
    (.50, [26, -6, .8]),
    (1, [-18, 24, 1.1]),
  ])),
  _Mancha(Color(0xFF7B5FCB), .8, .52, 10, Fotogramas([
    (0, [0, 0, .8]),
    (.25, [-22, -8, 1.1]),
    (.50, [14, -22, .9]),
    (.75, [18, 16, 1.15]),
    (1, [0, 0, .8]),
  ])),
];

class _ManchasPainter extends CustomPainter {
  _ManchasPainter(this.segundos, {this.quietas = false});
  final double segundos;

  /// Sin animación, CSS deja las manchas sin transform: centradas y a ×1.
  final bool quietas;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = EpuColores.lilaAdulto);
    final lado = size.width * 1.4; // 140 %
    final centro = size.center(Offset.zero);
    for (final m in _manchas) {
      final v = quietas ? const [0.0, 0.0, 1.0] : m.fotogramas.en((segundos % m.segundos) / m.segundos);
      final c = centro + Offset(v[0] / 100 * lado, v[1] / 100 * lado);
      final rect = Rect.fromCenter(center: c, width: lado * v[2], height: lado * v[2]);
      // `radial-gradient(circle, color 0, transparente N%)`: el radio de
      // `circle` llega a la esquina de la caja (lado × √2 / 2), por eso
      // radius .7071 sobre el lado.
      final pintura = Paint()
        ..shader = RadialGradient(
          radius: .7071,
          colors: [m.color.withValues(alpha: m.alfa), m.color.withValues(alpha: 0)],
          stops: [0, m.fin],
        ).createShader(rect);
      canvas.drawOval(rect, pintura);
    }
  }

  @override
  bool shouldRepaint(_ManchasPainter old) => old.segundos != segundos || old.quietas != quietas;
}
