import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../audio/sonidos.dart';
import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../ilustraciones/huella.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../widgets/comunes.dart';

/// Eco · el recuerdo (EcoFinal.dc.html).
///
/// De arriba hacia abajo:
/// * «Nivel N · nombre · instrumento» y «La descubrieron juntos», con
///   «juntos» pintado con un degradado lila ↔ coral que se desplaza lento
///   ([_PalabraJuntos]).
/// * El dibujo del recuerdo ([DibujoHuella]): estático, sin fondo, pegado
///   arriba del área central para usar mejor el espacio.
/// * Leyenda: Adulto (lila), Niño (coral) y «Se encontraron» (amarillo).
/// * Resumen de quién guió.
/// * «Escuchar la melodía» y «Siguiente nivel» (o «Elegir nivel» en el 7).
///
/// Arriba a la derecha va el marcador para guardar el recuerdo en
/// «Tu archivo» ([_Marcador]). Si la pantalla se abrió desde el archivo, el
/// marcador ya aparece guardado ([desdeArchivo]).
///
/// Cambios respecto de la versión anterior del paquete: se reemplazaron los
/// destellos por el dibujo, se quitó «X segundos · N trozos» (el
/// instrumento pasó al encabezado) y se sumó el marcador.
class PantallaEcoFinal extends StatefulWidget {
  const PantallaEcoFinal({super.key, this.desdeArchivo = false});

  /// `true` cuando se abre tocando un recuerdo o una sesión de «Tu archivo».
  final bool desdeArchivo;

  @override
  State<PantallaEcoFinal> createState() => _PantallaEcoFinalState();
}

class _PantallaEcoFinalState extends State<PantallaEcoFinal> {
  late final NivelEco _n = NivelEco.de(EpuEstado.leer(context).nivel);

  int _sonando = -1;
  final List<Timer> _timers = [];

  /// Se guardó en esta visita (dispara la animación del marcador).
  bool _guardadoAhora = false;

  bool get _guardado => _guardadoAhora || widget.desdeArchivo;

  void _guardar() {
    if (_guardado) return;
    EpuEstado.leer(context).guardarRecuerdo(_n.id);
    setState(() => _guardadoAhora = true);
  }

  /// Toca la melodía completa y resalta en el dibujo el trozo que suena
  /// (2 s por trozo).
  void _escuchar() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    EpuSonidos.instancia.tocarMelodia(_n);
    for (var i = 0; i < _n.trozos; i++) {
      _timers.add(Timer(Duration(milliseconds: i * 2000), () => setState(() => _sonando = i)));
    }
    _timers.add(Timer(Duration(milliseconds: _n.trozos * 2000), () => setState(() => _sonando = -1)));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    final guioAdulto = n.guiaAdulto;
    final dos = n.ultimoTrozoNino;
    final estado = EpuEstado.leer(context);

    final resumen = (dos
            ? 'Guió el adulto y el último trozo lo eligió el niño.'
            : guioAdulto
                ? 'Guió el adulto y el niño lo siguió.'
                : 'Guió el niño y el adulto lo siguió.') +
        ' Cada trozo sonó cuando acertaron juntos.';

    final encabezado = Column(
      children: [
        Text('Nivel ${n.id} · ${n.nombre} · ${n.instrumento}', style: EpuTextos.etiqueta, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'La descubrieron '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: _PalabraJuntos(estilo: EpuTextos.tituloGrande),
            ),
          ]),
          style: EpuTextos.tituloGrande,
          textAlign: TextAlign.center,
        ),
      ],
    );

    // Leyenda: `gap 6px 14px; 12.5px 800`. El punto amarillo lleva un aro
    // `box-shadow: 0 0 0 2.5px rgba(242,228,74,.45)`.
    Widget item(Color c, String texto, {bool aro = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                boxShadow: aro ? [BoxShadow(color: c.withValues(alpha: .45), spreadRadius: 2.5)] : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(texto, style: EpuTextos.leyenda),
          ],
        );
    final leyenda = Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        item(EpuColores.lilaAdulto, guioAdulto ? 'Adulto · guió' : 'Adulto'),
        item(EpuColores.coralNino, guioAdulto ? (dos ? 'Niño · guió el último' : 'Niño') : 'Niño · guió'),
        item(EpuColores.luzStick, 'Se encontraron', aro: true),
      ],
    );

    // Área central: `justify-content: flex-start; gap 14`. El dibujo ocupa
    // todo el ancho (346 px en el marco de 390) y es cuadrado; en pantallas
    // bajas se achica para que quepan la leyenda y el resumen.
    final centro = LayoutBuilder(builder: (context, k) {
      final lado = math.min(k.maxWidth, math.max(160.0, k.maxHeight - 110));
      return Column(
        children: [
          DibujoHuella(
            nivel: n,
            lado: lado,
            resaltado: _sonando,
            etiqueta: 'Recuerdo de la melodía: trazos lila y coral que salen del centro hacia donde se movió '
                'cada stick, con ${n.trozos} luces amarillas donde se encontraron',
          ),
          const SizedBox(height: 14 - 4), // `margin-top: -4px` de la leyenda
          leyenda,
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(resumen, style: EpuTextos.cuerpo, textAlign: TextAlign.center),
          ),
        ],
      );
    });

    final siguiente = n.id < 7;
    final botones = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _BotonDoble(texto: 'Escuchar la melodía', oscuro: false, alTocar: _escuchar),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BotonDoble(
              texto: siguiente ? 'Siguiente nivel' : 'Elegir nivel',
              oscuro: true,
              alTocar: () {
                if (siguiente) {
                  estado.nivel = n.id + 1;
                  EpuNavegacion.ir(context, Pantalla.antes);
                } else {
                  EpuNavegacion.volverA(context, Pantalla.elegirNivel);
                }
              },
            ),
          ),
        ],
      ),
    );

    return PantallaBase(
      atras: Pantalla.elegirNivel,
      relleno: const EdgeInsets.fromLTRB(22, 66, 22, 28),
      accion: _Marcador(guardado: _guardado, animar: _guardadoAhora, alTocar: _guardar),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          encabezado,
          const SizedBox(height: 18),
          Expanded(child: centro),
          const SizedBox(height: 18),
          botones,
        ],
      ),
    );
  }
}

/// «juntos» con los colores del adulto y del niño mezclándose.
///
/// CSS: `background: linear-gradient(90deg, lila 0%, coral 50%, lila 100%);
/// background-size: 200% 100%; background-clip: text;
/// animation: jt 10s linear infinite` (`background-position` 0 % → 200 %).
///
/// Con `background-size: 200%` el degradado mide el doble de la palabra y
/// se repite; ir de 0 % a 200 % lo corre exactamente un largo completo
/// (2 × ancho) hacia la izquierda, así el ciclo empalma sin salto. Con
/// «Quitar animaciones» queda quieto en la posición inicial (lila a la
/// izquierda, coral en el borde derecho).
class _PalabraJuntos extends StatefulWidget {
  const _PalabraJuntos({required this.estilo});

  final TextStyle estilo;

  @override
  State<_PalabraJuntos> createState() => _PalabraJuntosState();
}

class _PalabraJuntosState extends State<_PalabraJuntos> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sinMovimiento(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) {
            final largo = 2 * b.width, x0 = -largo * _c.value;
            return ui.Gradient.linear(
              Offset(x0, 0),
              Offset(x0 + largo, 0),
              const [EpuColores.lilaAdulto, EpuColores.coralNino, EpuColores.lilaAdulto],
              const [0, .5, 1],
              TileMode.repeated,
            );
          },
          child: child,
        ),
        child: Text('juntos', style: widget.estilo.copyWith(color: EpuColores.blanco)),
      );
}

/// Marcador para guardar el recuerdo (arriba a la derecha).
///
/// * Círculo blanco de 44 px con sombra `0 2px 10px rgba(43,37,54,.1)` y
///   el ícono de marcador vacío (`M5.5 3.5 L14.5 3.5 L14.5 16.5 L10 13
///   L5.5 16.5 Z`, trazo 2,2) en tinta.
/// * Guardado: fondo teal (transición .3 s) e ícono blanco relleno. Al
///   guardarlo hace un «pop» (`flagpop .45s cubic-bezier(.2,.8,.2,1)`:
///   escala 1 → 1,22 al 40 % → 1).
/// * No hay texto de confirmación: el estado del botón basta.
class _Marcador extends StatelessWidget {
  const _Marcador({required this.guardado, required this.animar, required this.alTocar});

  final bool guardado;

  /// Solo se anima cuando se guarda en esta visita (no al abrir desde el archivo).
  final bool animar;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    final circulo = AnimatedContainer(
      duration: quieto ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.ease,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: guardado ? EpuColores.teal : EpuColores.blanco,
        shape: BoxShape.circle,
        boxShadow: [sombraCss(0, 2, 10, const Color.fromRGBO(43, 37, 54, .1))],
      ),
      alignment: Alignment.center,
      child: CustomPaint(size: const Size.square(20), painter: _IconoMarcador(guardado)),
    );
    return Semantics(
      button: true,
      toggled: guardado,
      label: guardado ? 'Recuerdo guardado' : 'Guardar el recuerdo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: guardado ? null : alTocar,
        behavior: HitTestBehavior.opaque,
        child: TweenAnimationBuilder<double>(
          // Arranca en 0 y corre una vez cuando [animar] pasa a true.
          tween: Tween(begin: 0, end: animar && !quieto ? 1 : 0),
          duration: Duration(milliseconds: animar && !quieto ? 450 : 0),
          builder: (context, p, child) {
            // En CSS la curva se aplica a cada tramo entre fotogramas:
            // 0 → 40 %: 1 → 1,22; 40 → 100 %: 1,22 → 1.
            final s = p < .4
                ? mezclar(1, 1.22, CurvasEpu.pop.transform(p / .4))
                : mezclar(1.22, 1, CurvasEpu.pop.transform(((p - .4) / .6).clamp(0.0, 1.0)));
            return Transform.scale(scale: animar ? s : 1, child: child);
          },
          child: circulo,
        ),
      ),
    );
  }
}

class _IconoMarcador extends CustomPainter {
  const _IconoMarcador(this.guardado);
  final bool guardado;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(5.5, 3.5)
      ..lineTo(14.5, 3.5)
      ..lineTo(14.5, 16.5)
      ..lineTo(10, 13)
      ..lineTo(5.5, 16.5)
      ..close();
    final color = guardado ? EpuColores.blanco : EpuColores.tinta;
    if (guardado) canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_IconoMarcador old) => old.guardado != guardado;
}

/// Botones del recuerdo: `min-height 56; padding 10 12; radio 16;
/// 15 px 800, line-height 1.15`. Claro: blanco con borde al 25 %.
class _BotonDoble extends StatelessWidget {
  const _BotonDoble({required this.texto, required this.oscuro, required this.alTocar});

  final String texto;
  final bool oscuro;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: alTocar,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: oscuro ? EpuColores.tinta : EpuColores.blanco,
              border: Border.all(
                color: oscuro ? EpuColores.tinta : const Color.fromRGBO(43, 37, 54, .25),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: EpuTextos.botonMediano.copyWith(color: oscuro ? EpuColores.blanco : EpuColores.tinta),
            ),
          ),
        ),
      );
}
