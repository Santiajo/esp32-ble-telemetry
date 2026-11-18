import 'package:flutter/widgets.dart';

import '../util/css.dart';

/// Botón que cambia de estado (Conectar sticks, Calibrar, Reconectar stick).
///
/// * Fondo, borde y color de texto cambian con
///   `transition: background .3s, border-color .3s, color .3s` (ease).
/// * [respiracion]: brillo que late alrededor del botón mientras trabaja
///   (`@keyframes breath`, 1,4 s ease-in-out infinito).
/// * [rellenoColor]: barra que se llena de izquierda a derecha en
///   [rellenoDuracion] (`@keyframes fill`, lineal), recortada por el borde
///   redondeado (`overflow: hidden`).
class BotonEstado extends StatefulWidget {
  const BotonEstado({
    super.key,
    required this.etiqueta,
    required this.estiloTexto,
    required this.colorTexto,
    required this.fondo,
    required this.borde,
    required this.alTocar,
    this.altoMinimo = 58,
    this.anchoMaximo = double.infinity,
    this.relleno = const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
    this.icono,
    this.respiracion,
    this.rellenoColor,
    this.rellenoDuracion = const Duration(seconds: 3),
    this.transicionTexto = true,
  });

  final String etiqueta;
  final TextStyle estiloTexto;
  final Color colorTexto;
  final Color fondo;
  final Color borde;
  final VoidCallback alTocar;
  final double altoMinimo;
  final double anchoMaximo;
  final EdgeInsets relleno;

  /// Ícono a la izquierda del texto (check o luz), separado 10 px (`gap`).
  final Widget? icono;

  /// Colores del brillo que late; `null` = sin brillo.
  final Respiracion? respiracion;

  /// Color de la barra de 3 s; `null` = sin barra.
  final Color? rellenoColor;
  final Duration rellenoDuracion;

  /// El botón de «Pérdida de stick» no anima el color del texto.
  final bool transicionTexto;

  @override
  State<BotonEstado> createState() => _BotonEstadoState();
}

/// Brillo del botón: dos sombras que crecen y se intensifican.
///
/// `0%,100% { box-shadow: 0 0 0 0 c(a0), 0 0 4px 0 c(b0) }`
/// `50%     { box-shadow: 0 0 0 6px c(a1), 0 0 22px 6px c(b1) }`
class Respiracion {
  const Respiracion(this.r, this.g, this.b, this.a0, this.a1, this.b0, this.b1);

  /// «Conectando…» (teal).
  static const teal = Respiracion(13, 148, 136, .12, .26, .15, .3);

  /// Reconectando el stick grande (lila).
  static const adulto = Respiracion(179, 162, 220, .15, .4, .2, .45);

  /// Reconectando el stick pequeño (coral).
  static const nino = Respiracion(232, 94, 69, .12, .28, .15, .32);

  final int r, g, b;
  final double a0, a1, b0, b1;

  List<BoxShadow> en(double t) {
    final u = latido(t, 0, 1);
    return [
      sombraCss(0, 0, 0, Color.fromRGBO(r, g, b, mezclar(a0, a1, u)), spread: 6 * u),
      sombraCss(0, 0, mezclar(4, 22, u), Color.fromRGBO(r, g, b, mezclar(b0, b1, u)), spread: 6 * u),
    ];
  }
}

class _BotonEstadoState extends State<BotonEstado> with TickerProviderStateMixin {
  late final AnimationController _latido =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _barra =
      AnimationController(vsync: this, duration: widget.rellenoDuracion);

  @override
  void initState() {
    super.initState();
    _sincronizar(null);
  }

  @override
  void didUpdateWidget(BotonEstado anterior) {
    super.didUpdateWidget(anterior);
    _sincronizar(anterior);
  }

  void _sincronizar(BotonEstado? anterior) {
    if (widget.respiracion != null && !_latido.isAnimating) {
      _latido.repeat();
    } else if (widget.respiracion == null && _latido.isAnimating) {
      _latido
        ..stop()
        ..value = 0;
    }
    // La barra arranca desde 0 cada vez que aparece (como el `<span>` que
    // el prototipo agrega al pasar a «Calibrando…»).
    if (widget.rellenoColor != null && anterior?.rellenoColor == null) {
      _barra.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _latido.dispose();
    _barra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    const radio = BorderRadius.all(Radius.circular(16));
    const dur = Duration(milliseconds: 300);

    final contenido = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icono != null) ...[widget.icono!, const SizedBox(width: 10)],
        Flexible(
          child: widget.transicionTexto
              ? AnimatedDefaultTextStyle(
                  duration: dur,
                  curve: Curves.ease,
                  style: widget.estiloTexto.copyWith(color: widget.colorTexto),
                  textAlign: TextAlign.center,
                  child: Text(widget.etiqueta),
                )
              : Text(widget.etiqueta,
                  style: widget.estiloTexto.copyWith(color: widget.colorTexto),
                  textAlign: TextAlign.center),
        ),
      ],
    );

    final caja = AnimatedContainer(
      duration: dur,
      curve: Curves.ease,
      constraints: BoxConstraints(minHeight: widget.altoMinimo, maxWidth: widget.anchoMaximo),
      decoration: BoxDecoration(
        color: widget.fondo,
        border: Border.all(color: widget.borde, width: 1.5),
        borderRadius: radio,
      ),
      child: ClipRRect(
        // Recorta la barra por dentro del borde (radio interior 14,5).
        borderRadius: const BorderRadius.all(Radius.circular(16 - 1.5)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.rellenoColor != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _barra,
                  builder: (context, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _barra.value,
                      heightFactor: 1,
                      child: ColoredBox(color: widget.rellenoColor!),
                    ),
                  ),
                ),
              ),
            Padding(padding: widget.relleno, child: contenido),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      liveRegion: true, // aria-live="polite"
      child: GestureDetector(
        onTap: widget.alTocar,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _latido,
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radio,
              // Con «Quitar animaciones» el prototipo quita la animación y,
              // con ella, el brillo (el botón no tiene sombra propia).
              boxShadow: widget.respiracion == null || quieto ? null : widget.respiracion!.en(_latido.value),
            ),
            child: child,
          ),
          child: caja,
        ),
      ),
    );
  }
}
