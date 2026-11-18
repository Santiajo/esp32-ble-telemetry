import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../audio/sonidos.dart';
import '../juego/fuente_sticks.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../util/svg.dart';
import '../widgets/boton_estado.dart';
import '../widgets/comunes.dart';
import '../widgets/reloj.dart';

/// Qué stick se perdió.
typedef StickPerdido = Stick;

/// Por qué se perdió.
enum CausaPerdida {
  fueraDeAlcance('Fuera de alcance', 'Acerca el stick al teléfono y toca el botón.'),
  bateriaAgotada('Batería agotada', 'Carga el stick unos minutos y toca el botón.');

  const CausaPerdida(this.titulo, this.texto);
  final String titulo, texto;
}

/// Pérdida de stick (Perdida.dc.html).
///
/// El stick perdido se ve gris dentro de un anillo punteado coral que late
/// (`ring 1.6s ease-in-out infinite`: opacidad .35 ↔ 1, escala .97 ↔ 1).
///
/// | estado      | botón                                   |
/// |-------------|-----------------------------------------|
/// | inicial     | blanco, borde 25 %, luz gris, «Reconectar stick pequeño» |
/// | conectando  | tinte del stick, borde del color del stick, brillo que late, luz que parpadea cada 250 ms, «Conectando…» |
/// | listo       | color del stick, check, «Stick pequeño conectado»; el stick se pinta (.4 s) |
///
/// 1,5 s después de reconectar vuelve a «Antes del nivel».
class PantallaPerdida extends StatefulWidget {
  const PantallaPerdida({
    super.key,
    this.stick = Stick.pequeno,
    this.causa = CausaPerdida.fueraDeAlcance,
  });

  final Stick stick;
  final CausaPerdida causa;

  @override
  State<PantallaPerdida> createState() => _PantallaPerdidaState();
}

enum _Fase { inicial, conectando, listo }

class _PantallaPerdidaState extends State<PantallaPerdida> {
  _Fase _fase = _Fase.inicial;
  bool _luz = false;
  Timer? _parpadeo, _siguiente;

  bool get _grande => widget.stick == Stick.grande;

  Future<void> _reconectar() async {
    if (_fase != _Fase.inicial) return;
    setState(() {
      _fase = _Fase.conectando;
      _luz = true;
    });
    _parpadeo = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() => _luz = !_luz));
    await EpuSticks.fuente.reconectar(widget.stick);
    if (!mounted) return;
    _parpadeo?.cancel();
    EpuSonidos.instancia.tonoConexion();
    setState(() {
      _fase = _Fase.listo;
      _luz = true;
    });
    _siguiente = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) EpuNavegacion.volverA(context, Pantalla.antes);
    });
  }

  @override
  void dispose() {
    _parpadeo?.cancel();
    _siguiente?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    final f = _fase;
    final nombre = _grande ? 'grande' : 'pequeño';
    final colorStick = _grande ? EpuColores.lilaAdulto : EpuColores.coralNino;
    final tinte = _grande ? EpuColores.tinteAdulto : EpuColores.tinteNino;

    final stick = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.ease,
      width: _grande ? 62 : 44,
      height: _grande ? 220 : 150,
      decoration: BoxDecoration(
        color: f == _Fase.listo ? colorStick : EpuColores.stickSinSenal,
        borderRadius: BorderRadius.circular(999),
      ),
    );

    // Anillo punteado alrededor del stick (padding 26 px).
    final anillo = Reloj(
      activo: !quieto,
      builder: (context, ms) {
        final t = (ms % 1600) / 1600;
        return CustomPaint(
          painter: _AnilloPunteado(
            opacidad: quieto ? 1 : latido(t, .35, 1),
            escala: quieto ? 1 : latido(t, .97, 1),
          ),
          child: Padding(padding: const EdgeInsets.all(26), child: stick),
        );
      },
    );

    final textos = Column(
      children: [
        if (f != _Fase.listo)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
            decoration: BoxDecoration(color: EpuColores.coralSuave, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: EpuColores.coralNino, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(widget.causa.titulo, style: EpuTextos.nunito(13, FontWeight.w800)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text('Se perdió el stick $nombre', style: EpuTextos.tituloAviso, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(widget.causa.texto, style: EpuTextos.cuerpo, textAlign: TextAlign.center),
        ),
      ],
    );

    final boton = BotonEstado(
      etiqueta: switch (f) {
        _Fase.inicial => 'Reconectar stick $nombre',
        _Fase.conectando => 'Conectando…',
        _Fase.listo => 'Stick $nombre conectado',
      },
      estiloTexto: EpuTextos.botonMediano,
      colorTexto: EpuColores.tinta,
      transicionTexto: false,
      fondo: switch (f) {
        _Fase.inicial => EpuColores.blanco,
        _Fase.conectando => tinte,
        _Fase.listo => colorStick,
      },
      borde: f == _Fase.inicial ? const Color.fromRGBO(43, 37, 54, .25) : colorStick,
      altoMinimo: 60,
      anchoMaximo: 320,
      relleno: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      respiracion: f == _Fase.conectando ? (_grande ? Respiracion.adulto : Respiracion.nino) : null,
      icono: f == _Fase.listo
          ? const CheckEnCirculo(color: EpuColores.tinta)
          : Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _luz ? EpuColores.luzStick : EpuColores.luzApagada,
              ),
            ),
      alTocar: _reconectar,
    );

    return PantallaBase(
      relleno: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // `min-height 240; max-height 338; padding 24; overflow hidden`.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 240, maxHeight: 338),
            child: ClipRect(
              // heightFactor 1: la caja mide lo que su contenido (entre 240 y 338).
              child: Padding(padding: const EdgeInsets.all(24), child: Center(heightFactor: 1, child: anillo)),
            ),
          ),
          const SizedBox(height: 16),
          textos,
          const SizedBox(height: 16),
          Align(child: boton),
        ],
      ),
    );
  }
}

/// Borde `2.5px dashed #E85E45` con `border-radius: 999px`.
///
/// Chrome dibuja las rayas de ese borde de unos 6 px con espacios de 4 px
/// (medido en la captura del prototipo) y las ajusta para que entren
/// parejas en el contorno. Aquí se hace lo mismo.
class _AnilloPunteado extends CustomPainter {
  _AnilloPunteado({required this.opacidad, required this.escala});

  final double opacidad, escala;

  @override
  void paint(Canvas canvas, Size size) {
    const ancho = 2.5;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(escala)
      ..translate(-size.width / 2, -size.height / 2);
    final r = Rect.fromLTWH(0, 0, size.width, size.height).deflate(ancho / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(r.width, r.height) / 2)));
    final largo = path.computeMetrics().fold<double>(0, (s, m) => s + m.length);
    final cantidad = math.max(1, (largo / 10).round());
    final periodo = largo / cantidad;
    dibujarPunteado(
      canvas,
      path,
      [periodo * .6, periodo * .4],
      trazoSvg(EpuColores.coralNino, ancho, fin: StrokeCap.butt, opacidad: opacidad),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnilloPunteado old) => old.opacidad != opacidad || old.escala != escala;
}
