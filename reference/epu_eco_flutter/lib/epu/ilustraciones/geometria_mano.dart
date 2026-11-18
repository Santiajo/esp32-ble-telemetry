import 'dart:math' as math;

/// Geometría de la mano que sostiene el stick.
///
/// Es la traducción exacta de la función `geo(th, ph)` de EcoAntes.dc.html.
/// Este archivo no depende de Flutter a propósito: así se puede probar con
/// `dart test` y comparar número a número con el prototipo.
///
/// La mano y el stick son un modelo 3D muy simple proyectado en 2D:
/// * [th] (θ) inclina el stick hacia la izquierda (−) o la derecha (+),
///   girando en el plano de la pantalla alrededor de la muñeca (14, 60).
/// * [ph] (φ) vuelca el stick hacia adelante (−, hacia arriba en pantalla) o
///   hacia atrás (+), girando en profundidad. Al ir hacia atrás la punta se
///   acerca a la cámara (la luz se agranda) y al ir adelante se aleja (la luz
///   se atenúa).
///
/// Poses que usa el prototipo (tabla POSE): centro (0, 0), izquierda
/// (−16, 0), derecha (16, 0), adelante (0, −35) y atrás (0, 40).
class GeometriaMano {
  GeometriaMano(this.th, this.ph) {
    const D = math.pi / 180;
    final ct = math.cos(th * D), st = math.sin(th * D);
    final cp = math.cos(ph * D), sp = math.sin(ph * D);

    // Proyección de un punto (x, y, z) de la mano, sin redondear.
    (double, double) crudo(double x, double y, double z) {
      final rx = x - 14, ry = y - 60, y1 = ry * cp + z * sp;
      return (14 + rx * ct - y1 * st, 60 + rx * st + y1 * ct);
    }

    // Lo mismo, redondeado como lo escribe el prototipo en el SVG.
    Punto p(double x, double y, double z) {
      final (px, py) = crudo(x, y, z);
      return Punto(_r(px), _r(py));
    }

    // Los cuatro dedos son anillos (elipses) a distintas alturas. Si el stick
    // va hacia atrás se dibujan en orden inverso para que se tapen bien.
    final ys = ph > 0 ? const [56.7, 49.8, 42.9, 36.0] : const [36.0, 42.9, 49.8, 56.7];
    List<Punto> anillo(double y, List<double> angulos) => [
          for (final a in angulos) p(10.5 * math.cos(a * D), y, 10.5 * math.sin(a * D)),
        ];
    const frente = <double>[180, 165, 150, 130, 110, 90, 72, 55];
    const atras = <double>[330, 310, 290, 270, 250, 230, 210, 195];

    for (final y in ys) {
      final fr = anillo(y, frente);
      dedoCompleto.add([...anillo(y, atras), ...fr]); // c1…c4
      dedoFrente.add([...anillo(y, const <double>[174]), ...fr.skip(1)]); // f1…f4
      dedoBlanco.add(fr); // w1…w4
      dedoPunta.add(fr.last); // t1…t4 (punto redondo)
    }

    palma = [p(11.5, 46, 3), p(14, 60, 0)];
    palmaAtras = [p(11, 43, -4), p(14, 60, 0)];
    stick = [p(0, 8, 0), p(0, 64, 0)];
    pulgar = [
      for (final a in const [92.5, 75.0, 60.0, 45.0])
        () {
          final x = 11.7 * math.cos(a * D);
          return p(x, 34.12 + .233 * x, 11.7 * math.sin(a * D));
        }(),
      p(11.5, 36.8, 8),
      p(14.5, 37.5, 7),
      p(17.2, 48.3, 4),
    ];
    borrador = [p(14.3, 40, 6), p(16.7, 53, 3)];

    // La luz de la punta: se mueve con el stick, crece al ir atrás (hasta ×1,6
    // y 3 unidades más abajo) y se atenúa al ir adelante (hasta 30 %).
    final (lx, ly) = crudo(0, 6, 0);
    final arriba = math.max(0, ph) / 40, abajo = math.max(0, -ph) / 35;
    luzX = _r(lx);
    luzY = _r(ly + 3 * arriba);
    luzEscala = _r(1 + .6 * arriba);
    luzOpacidad = _r(1 - .7 * abajo);
  }

  final double th, ph;

  /// Antebrazo: siempre la misma línea (no se mueve con el stick).
  static const antebrazo = [Punto(14, 60), Punto(42.4, 140)];

  final List<List<Punto>> dedoCompleto = [];
  final List<List<Punto>> dedoFrente = [];
  final List<List<Punto>> dedoBlanco = [];
  final List<Punto> dedoPunta = [];
  late final List<Punto> palma, palmaAtras, stick, pulgar, borrador;
  late final double luzX, luzY, luzEscala, luzOpacidad;

  /// El prototipo redondea cada coordenada a 2 decimales al escribir el SVG
  /// (`Math.round(v * 100) / 100`). `Math.round` de JavaScript redondea los
  /// .5 hacia arriba también en negativos; por eso `floor(v + .5)`.
  static double _r(double v) => (v * 100 + .5).floorToDouble() / 100;
}

/// Punto 2D sin depender de `dart:ui`.
class Punto {
  const Punto(this.x, this.y);
  final double x, y;

  @override
  String toString() => '${n(x)} ${n(y)}';
  static String n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// Pose de un stick: inclinación lateral (θ) y vuelco (φ) en grados.
class Pose {
  const Pose(this.th, this.ph);
  final double th, ph;

  static const centro = Pose(0, 0);
  static const izquierda = Pose(-16, 0);
  static const derecha = Pose(16, 0);
  static const adelante = Pose(0, -35);
  static const atras = Pose(0, 40);

  /// Pose intermedia del giro que usan las miniaturas del nivel 5 y 7.
  static const giro = Pose(12, 24);
}
