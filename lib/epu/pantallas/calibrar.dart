import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ilustraciones/preparacion.dart';
import '../juego/fuente_sticks.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../widgets/boton_estado.dart';
import '../widgets/comunes.dart';
import '../widgets/reloj.dart';

/// Calibrar sticks (Calibrar.dc.html, modo eco).
///
/// | estado      | botón                        | ilustración                      |
/// |-------------|------------------------------|----------------------------------|
/// | inicial     | «Calibrar» oscuro            | quieta                           |
/// | calibrando  | «Calibrando… no se muevan», blanco con borde teal y barra de 3 s | dos anillos amarillos se expanden (×2,8, 1,3 s, ease-out, el segundo con 0,65 s de retraso) y la luz parpadea (0,7 s) |
/// | listo       | «Sticks calibrados» teal con check | quieta                       |
///
/// 1,2 s después de calibrar pasa al juego.
class PantallaCalibrar extends StatefulWidget {
  const PantallaCalibrar({super.key});

  @override
  State<PantallaCalibrar> createState() => _PantallaCalibrarState();
}

enum _Fase { inicial, calibrando, listo }

class _PantallaCalibrarState extends State<PantallaCalibrar> {
  _Fase _fase = _Fase.inicial;
  Timer? _siguiente;

  Future<void> _calibrar() async {
    if (_fase != _Fase.inicial) return;
    setState(() => _fase = _Fase.calibrando);
    await EpuSticks.fuente.calibrar();
    if (!mounted) return;
    setState(() => _fase = _Fase.listo);
    _siguiente = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) EpuNavegacion.ir(context, Pantalla.juego);
    });
  }

  @override
  void dispose() {
    _siguiente?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    final f = _fase;

    Widget lienzo(AnimacionCalibrar a) => LienzoSvg(
          // EPU-24: las manos de los niveles (antes, rectángulos en un viewBox de 320 × 260).
          vbAncho: 120,
          vbAlto: 110,
          ancho: 285,
          pintor: (c) => pintarCalibrarManos(c, a),
          etiqueta: 'El adulto y el niño sostienen sus sticks derechos, con una flecha hacia arriba sobre cada luz',
        );

    final ilustracion = ZonaIlustracion(
      minimo: 260,
      maximo: 388,
      child: DibujoCentrado(
        ancho: 285,
        alto: 285 * 110 / 120,
        child: f != _Fase.calibrando
            ? lienzo(const AnimacionCalibrar())
            : quieto
                ? lienzo(const AnimacionCalibrar(anillo1Opacidad: .5, anillo2Opacidad: .5))
                : Reloj(builder: (context, ms) => lienzo(_animacion(ms))),
      ),
    );

    final textos = Column(
      children: [
        Text('Calibren los sticks', style: EpuTextos.tituloMediano, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Cada uno sostiene su stick, con la luz al frente tuyo', style: EpuTextos.cuerpo, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Quédense quietos hasta que termine.', style: EpuTextos.detalle, textAlign: TextAlign.center),
      ],
    );

    return PantallaBase(
      atras: Pantalla.guia,
      relleno: const EdgeInsets.fromLTRB(22, 66, 22, 28),
      child: ColumnaConBoton(
        separacion: 18,
        arriba: [ilustracion, textos],
        boton: BotonEstado(
          etiqueta: switch (f) {
            _Fase.inicial => 'Calibrar',
            _Fase.calibrando => 'Calibrando… no se muevan',
            _Fase.listo => 'Sticks calibrados',
          },
          estiloTexto: EpuTextos.botonGrande,
          colorTexto: f == _Fase.calibrando ? EpuColores.tealOscuro : EpuColores.blanco,
          fondo: switch (f) {
            _Fase.inicial => EpuColores.tinta,
            _Fase.calibrando => EpuColores.blanco,
            _Fase.listo => EpuColores.teal,
          },
          borde: f == _Fase.inicial ? EpuColores.tinta : EpuColores.teal,
          rellenoColor: f == _Fase.calibrando ? EpuColores.rellenoCalibrar : null,
          icono: f == _Fase.listo ? const CheckEnCirculo() : null,
          alTocar: _calibrar,
        ),
      ),
    );
  }

  /// `@keyframes ring { 0% {opacity .9; scale 1} 100% {opacity 0; scale 2.8} }`
  /// (1,3 s ease-out infinito, el segundo con `animation-delay: .65s`) y
  /// `@keyframes blink { 0%,100% {opacity 1} 50% {opacity .3} }` (0,7 s).
  AnimacionCalibrar _animacion(double ms) {
    (double, double) anillo(double t) {
      if (t < 0) return (1, 0); // antes de su retraso no se ve
      final p = Curves.easeOut.transform((t % 1300) / 1300);
      return (mezclar(1, 2.8, p), mezclar(.9, 0, p));
    }

    final (e1, o1) = anillo(ms);
    final (e2, o2) = anillo(ms - 650);
    return AnimacionCalibrar(
      anillo1Escala: e1,
      anillo1Opacidad: o1,
      anillo2Escala: e2,
      anillo2Opacidad: o2,
      luzOpacidad: latido((ms % 700) / 700, 1, .3),
    );
  }
}
