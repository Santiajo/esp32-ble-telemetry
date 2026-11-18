import 'dart:math' as math;
import 'dart:ui';

/// Lector mínimo del atributo `d` de los trazados SVG.
///
/// Las ilustraciones del prototipo son SVG en línea. En vez de agregar un
/// paquete de SVG, los trazados se copian tal cual desde el HTML y se leen con
/// esta función, así el dibujo queda idéntico y se puede comparar línea a
/// línea con el original. Soporta los comandos que usa el prototipo:
/// M, L, H, V, A y Z (mayúsculas y minúsculas).
Path trazadoSvg(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0, x0 = 0.0, y0 = 0.0;
  double n() => double.parse(tokens[i++]);
  bool esNumero() => i < tokens.length && !RegExp(r'^[A-Za-z]$').hasMatch(tokens[i]);

  while (i < tokens.length) {
    if (!esNumero()) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.moveTo(x, y);
        x0 = x;
        y0 = y;
        cmd = rel ? 'l' : 'L'; // números siguientes = lineTo implícito
      case 'L':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
      case 'H':
        x = (rel ? x : 0) + n();
        path.lineTo(x, y);
      case 'V':
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final grande = n() != 0, horario = n() != 0;
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        // En SVG, sweep-flag 1 es sentido horario en la pantalla (y hacia
        // abajo), igual que `clockwise: true` de Flutter.
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot,
          largeArc: grande,
          clockwise: horario,
        );
      case 'Z':
        path.close();
        x = x0;
        y = y0;
    }
  }
  return path;
}

/// Trazado de un círculo completo, empezando en el punto de la derecha y
/// girando en sentido horario: el mismo punto de partida que usa SVG para
/// `<circle>` (importa para los trazos punteados).
Path circuloSvg(double cx, double cy, double r) => Path()
  ..addArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), 0, math.pi)
  ..addArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), math.pi, math.pi);

/// Pincel de trazo con las propiedades de SVG.
Paint trazoSvg(
  Color color,
  double ancho, {
  StrokeCap fin = StrokeCap.round,
  StrokeJoin union = StrokeJoin.round,
  double opacidad = 1,
}) =>
    Paint()
      ..color = color.withValues(alpha: color.a * opacidad)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ancho
      ..strokeCap = fin
      ..strokeJoin = union
      ..isAntiAlias = true;

/// Pincel de relleno.
Paint rellenoSvg(Color color, {double opacidad = 1}) => Paint()
  ..color = color.withValues(alpha: color.a * opacidad)
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

/// Dibuja [path] con `stroke-dasharray` (patrón de raya y espacio).
///
/// Comportamiento medido en Chrome, que es lo que muestra el prototipo:
/// * una raya de largo 0 con remate redondo se dibuja como un punto
///   (así se ve el anillo punteado de «Sin interrupciones»);
/// * una raya que empieza justo en el final del trazado no se dibuja.
void dibujarPunteado(Canvas canvas, Path path, List<double> patron, Paint pincel) {
  for (final metrica in path.computeMetrics()) {
    var pos = 0.0;
    var k = 0;
    while (pos < metrica.length - 1e-6) {
      final largo = patron[k % patron.length];
      final fin = math.min(pos + largo, metrica.length);
      if (largo <= 0) {
        if (pincel.strokeCap == StrokeCap.round) {
          final t = metrica.getTangentForOffset(pos);
          if (t != null) {
            canvas.drawCircle(
              t.position,
              pincel.strokeWidth / 2,
              Paint()
                ..color = pincel.color
                ..isAntiAlias = true,
            );
          }
        }
      } else {
        canvas.drawPath(metrica.extractPath(pos, fin), pincel);
      }
      pos += largo + patron[(k + 1) % patron.length];
      k += 2;
    }
  }
}
