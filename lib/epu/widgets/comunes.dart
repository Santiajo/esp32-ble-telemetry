import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../util/svg.dart';

/// Base de todas las pantallas claras: fondo, márgenes, botón «Atrás».
///
/// * El prototipo se diseñó en un marco de 390 × 844 sin barra de estado.
///   Aquí el contenido va dentro de [SafeArea] para que el botón «Atrás»
///   (a 14 px del borde) no quede debajo de la barra de estado de Android.
/// * [atras] es la pantalla a la que lleva «Atrás». El botón «volver» del
///   sistema hace lo mismo, para que las dos salidas coincidan.
class PantallaBase extends StatelessWidget {
  const PantallaBase({
    super.key,
    required this.child,
    this.atras,
    this.relleno = EdgeInsets.zero,
    this.fondo = EpuColores.fondo,
    this.bloquearVolver = false,
    this.encima,
  });

  final Widget child;

  /// Capa por encima de todo, botón «Atrás» y barra de estado incluidos (el
  /// círculo que cubre la pantalla al terminar la preparación).
  final Widget? encima;
  final Pantalla? atras;
  final EdgeInsets relleno;
  final Color fondo;

  /// `true` en pantallas donde el prototipo no tiene salida (el juego).
  final bool bloquearVolver;

  @override
  Widget build(BuildContext context) {
    final destino = atras;
    return PopScope(
      canPop: destino == null && !bloquearVolver,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho && destino != null) EpuNavegacion.volverA(context, destino);
      },
      child: ColoredBox(
        color: fondo,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(child: Padding(padding: relleno, child: child)),
                    if (destino != null)
                      Positioned(
                        top: 14,
                        left: 14,
                        child: BotonAtras(alTocar: () => EpuNavegacion.volverA(context, destino)),
                      ),
                  ],
                ),
              ),
            ),
            if (encima != null) Positioned.fill(child: encima!),
          ],
        ),
      ),
    );
  }
}

/// Botón «Atrás»: píldora blanca de 40 px de alto con chevrón.
///
/// CSS: `height 40; padding 0 14px 0 12px; border-radius 999px; gap 7px;
/// font 13px 800; box-shadow 0 2px 10px rgba(43,37,54,.1)`.
class BotonAtras extends StatelessWidget {
  const BotonAtras({super.key, required this.alTocar});

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Atrás',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: alTocar,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 14),
          decoration: BoxDecoration(
            color: EpuColores.blanco,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [sombraBotonAtras],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CustomPaint(size: Size(10.5, 10.5), painter: _Chevron()),
              const SizedBox(width: 7),
              Text('Atrás', style: EpuTextos.botonAtras),
            ],
          ),
        ),
      ),
    );
  }
}

/// El chevrón del prototipo no es un ícono: es un cuadrado de 8 px con borde
/// izquierdo e inferior de 2,5 px (10,5 px en total), girado 45° y corrido
/// 2 px a la derecha (`transform: translateX(2px) rotate(45deg)`).
class _Chevron extends CustomPainter {
  const _Chevron();

  @override
  void paint(Canvas canvas, Size size) {
    final p = rellenoSvg(EpuColores.tinta);
    canvas
      ..save()
      ..translate(2 + 5.25, 5.25)
      ..rotate(math.pi / 4)
      ..translate(-5.25, -5.25)
      ..drawRect(const Rect.fromLTWH(0, 0, 2.5, 10.5), p)
      ..drawRect(const Rect.fromLTWH(0, 8, 10.5, 2.5), p)
      ..restore();
  }

  @override
  bool shouldRepaint(_Chevron oldDelegate) => false;
}

/// Botón principal oscuro (`min-height 58; padding 12 20; radius 16;
/// fondo y borde 1,5 px #2B2536; texto 17 px 800 blanco`).
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({super.key, required this.texto, required this.alTocar});

  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: alTocar,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EpuColores.tinta,
            border: Border.all(color: EpuColores.tinta, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(texto, style: EpuTextos.botonGrande, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Indicador de pasos de la preparación (círculos de 34 px y conectores de
/// 32 × 4 px). [actual] va de 1 a [total].
class PasosPreparacion extends StatelessWidget {
  const PasosPreparacion({super.key, required this.actual, this.total = 4});

  final int actual;
  final int total;

  @override
  Widget build(BuildContext context) {
    final hijos = <Widget>[];
    for (var i = 1; i <= total; i++) {
      if (i > 1) {
        hijos.add(Container(
          width: 32,
          height: 4,
          color: i <= actual ? EpuColores.teal : EpuColores.linea,
        ));
      }
      hijos.add(_Paso(numero: i, estado: i < actual ? _EstadoPaso.hecho : (i == actual ? _EstadoPaso.actual : _EstadoPaso.pendiente)));
    }
    return Semantics(
      label: 'Paso $actual de $total',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 34,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: hijos),
        ),
      ),
    );
  }
}

enum _EstadoPaso { hecho, actual, pendiente }

class _Paso extends StatelessWidget {
  const _Paso({required this.numero, required this.estado});

  final int numero;
  final _EstadoPaso estado;

  @override
  Widget build(BuildContext context) {
    switch (estado) {
      case _EstadoPaso.hecho:
        return Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(color: EpuColores.teal, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const IconoCheck(tamano: 18, viewBox: 20, color: EpuColores.blanco, trazo: 2.8,
              puntos: [Offset(5, 10.5), Offset(8.5, 14), Offset(15, 7)]),
        );
      case _EstadoPaso.actual:
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: EpuColores.blanco,
            shape: BoxShape.circle,
            border: Border.all(color: EpuColores.teal, width: 3),
          ),
          alignment: Alignment.center,
          child: Text('$numero', style: EpuTextos.pasoNumero.copyWith(color: EpuColores.teal)),
        );
      case _EstadoPaso.pendiente:
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: EpuColores.pendienteBorde, width: 2),
          ),
          alignment: Alignment.center,
          child: Text('$numero', style: EpuTextos.pasoNumero.copyWith(color: EpuColores.pendienteTexto)),
        );
    }
  }
}

/// Ticket dibujado como en el SVG del prototipo (polilínea con remates
/// redondos). [viewBox] es el lado del viewBox original (20 o 22).
class IconoCheck extends StatelessWidget {
  const IconoCheck({
    super.key,
    required this.tamano,
    required this.viewBox,
    required this.color,
    required this.trazo,
    required this.puntos,
  });

  /// Check de los botones con estado: viewBox 22, trazo 2,6.
  const IconoCheck.boton({super.key, this.color = EpuColores.teal})
      : tamano = 22,
        viewBox = 22,
        trazo = 2.6,
        puntos = const [Offset(6.5, 11.5), Offset(9.8, 14.6), Offset(15.6, 8)];

  /// Check de la tarjeta de nivel completado: viewBox 20 a 15 px.
  const IconoCheck.tarjeta({super.key})
      : tamano = 15,
        viewBox = 20,
        color = EpuColores.blanco,
        trazo = 2.8,
        puntos = const [Offset(5, 10.5), Offset(8.5, 14), Offset(15, 7)];

  final double tamano;
  final double viewBox;
  final Color color;
  final double trazo;
  final List<Offset> puntos;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(tamano),
        painter: _CheckPainter(viewBox, color, trazo, puntos),
      );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.viewBox, this.color, this.trazo, this.puntos);

  final double viewBox;
  final Color color;
  final double trazo;
  final List<Offset> puntos;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / viewBox;
    final path = Path()..moveTo(puntos.first.dx, puntos.first.dy);
    for (final p in puntos.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas
      ..save()
      ..scale(s)
      ..drawPath(path, trazoSvg(color, trazo))
      ..restore();
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

/// Check dentro de un círculo blanco de 22 px: aparece en los botones con
/// estado cuando terminan («Sticks conectados», «Sticks calibrados»).
class CheckEnCirculo extends StatelessWidget {
  const CheckEnCirculo({super.key, this.color = EpuColores.teal});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(color: EpuColores.blanco, shape: BoxShape.circle),
        child: IconoCheck.boton(color: color),
      );
}

/// Tres puntos de dificultad + palabra («Fácil», «Media», «Difícil»).
class PuntosDificultad extends StatelessWidget {
  const PuntosDificultad({super.key, required this.dificultad, required this.estilo});

  final int dificultad;
  final TextStyle estilo;

  static const palabras = ['', 'Fácil', 'Media', 'Difícil'];

  @override
  Widget build(BuildContext context) {
    Widget punto(bool lleno) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lleno ? EpuColores.tinta : EpuColores.linea,
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        punto(true),
        const SizedBox(width: 5),
        punto(dificultad >= 2),
        const SizedBox(width: 5),
        punto(dificultad >= 3),
        const SizedBox(width: 5 + 3), // gap 5 + margin-left 3 del texto
        Text(palabras[dificultad], style: estilo),
      ],
    );
  }
}

/// Centra un dibujo de tamaño fijo aunque no quepa, como `display: grid;
/// place-items: center; overflow: hidden` en CSS: si el dibujo es más grande
/// que el espacio, se sale por igual a ambos lados y se recorta.
class DibujoCentrado extends StatelessWidget {
  const DibujoCentrado({
    super.key,
    required this.ancho,
    required this.alto,
    required this.child,
    this.relleno = EdgeInsets.zero,
  });

  final double ancho;
  final double alto;
  final EdgeInsets relleno;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: Padding(
          padding: relleno,
          child: OverflowBox(
            minWidth: ancho,
            maxWidth: ancho,
            minHeight: alto,
            maxHeight: alto,
            child: SizedBox(width: ancho, height: alto, child: child),
          ),
        ),
      );
}

/// Zona de ilustración con `flex: 1; min-height; max-height` de CSS.
///
/// Va dentro de un [Column] y crece hasta [maximo]. Si sobra espacio, queda
/// al final de la columna (en el prototipo lo toma el `margin-top: auto` del
/// botón). Ojo: Flutter reparte el espacio entre `Flexible` y `Spacer` en
/// partes iguales; CSS no. Por eso las pantallas que usan esto ponen el botón
/// fuera de la columna interna (ver [ColumnaConBoton]).
class ZonaIlustracion extends StatelessWidget {
  const ZonaIlustracion({
    super.key,
    required this.child,
    this.minimo = 0,
    this.maximo = double.infinity,
  });

  final double minimo;
  final double maximo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Flexible(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minimo, maxHeight: maximo),
          child: SizedBox(width: double.infinity, height: double.infinity, child: child),
        ),
      );
}

/// Columna con el botón al fondo, como `margin-top: auto` en CSS.
///
/// [arriba] se apila desde arriba con [separacion] entre elementos; lo que
/// sobre de espacio queda entre [arriba] y [boton].
class ColumnaConBoton extends StatelessWidget {
  const ColumnaConBoton({
    super.key,
    required this.arriba,
    required this.boton,
    required this.separacion,
  });

  final List<Widget> arriba;
  final Widget boton;
  final double separacion;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _conSeparacion(arriba, separacion),
            ),
          ),
          SizedBox(height: separacion),
          boton,
        ],
      );
}

List<Widget> _conSeparacion(List<Widget> hijos, double sep) => [
      for (var i = 0; i < hijos.length; i++) ...[
        if (i > 0) SizedBox(height: sep),
        hijos[i],
      ],
    ];

/// `gap` de CSS para columnas.
List<Widget> conSeparacion(List<Widget> hijos, double sep) => _conSeparacion(hijos, sep);
