import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio/sonidos.dart';
import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../util/degradados.dart';
import '../widgets/comunes.dart';

/// Eco · el recuerdo (EcoFinal.dc.html).
///
/// Un destello por trozo, del color de quien guió (en el nivel 7 el último
/// es coral porque lo eligió el niño). Los destellos entran uno tras otro
/// (`in .5s ease-out`, retraso .15 s + .15 s por destello: aparecen desde
/// ×0,4). «Escuchar la melodía» la toca completa y agranda cada destello
/// (×1,35, transición .35 s ease) mientras suena su trozo (2 s cada uno).
class PantallaEcoFinal extends StatefulWidget {
  const PantallaEcoFinal({super.key});

  @override
  State<PantallaEcoFinal> createState() => _PantallaEcoFinalState();
}

class _PantallaEcoFinalState extends State<PantallaEcoFinal> with SingleTickerProviderStateMixin {
  late final NivelEco _n = NivelEco.de(EpuEstado.leer(context).nivel);
  late final Duration _total = Duration(milliseconds: 150 + 150 * (_n.trozos - 1) + 500);
  late final AnimationController _entrada = AnimationController(vsync: this, duration: _total)..forward();

  int _sonando = -1;
  final List<Timer> _timers = [];

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
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    final quieto = sinMovimiento(context);
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
        Text('Nivel ${n.id} · ${n.nombre}', style: EpuTextos.etiqueta, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('La descubrieron juntos', style: EpuTextos.tituloGrande, textAlign: TextAlign.center),
      ],
    );

    Widget punto(Color c) => Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

    final centro = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          image: true,
          label: 'Recuerdo de la melodía: ${n.trozos} destellos de color, uno por cada trozo, del color de quien guió',
          child: SizedBox(
            height: 190,
            child: AnimatedBuilder(
              animation: _entrada,
              builder: (context, _) => _Destellos(
                nivel: n,
                sonando: _sonando,
                entrada: (i) {
                  if (quieto) return 1;
                  final inicio = 150 + 150 * i, ms = _entrada.value * _total.inMilliseconds;
                  return Curves.easeOut.transform(((ms - inicio) / 500).clamp(0.0, 1.0));
                },
                quieto: quieto,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            punto(guioAdulto ? EpuColores.lilaAdulto : EpuColores.coralNino),
            const SizedBox(width: 6),
            Text(guioAdulto ? 'Guió el adulto' : 'Guió el niño', style: EpuTextos.leyenda),
            if (dos) ...[
              const SizedBox(width: 16),
              punto(EpuColores.coralNino),
              const SizedBox(width: 6),
              Text('Último trozo: el niño', style: EpuTextos.leyenda),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text('${n.instrumento} · ${n.trozos * 2} segundos · ${n.trozos} trozos',
            style: EpuTextos.subtitulo, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(resumen, style: EpuTextos.cuerpo, textAlign: TextAlign.center),
        ),
      ],
    );

    final siguiente = n.id < 7;
    final botones = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _BotonDoble(
              texto: 'Escuchar la melodía',
              oscuro: false,
              alTocar: _escuchar,
            ),
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

/// Fila de destellos encimados (`margin: 0 -7px`) sobre un brillo verde.
class _Destellos extends StatelessWidget {
  const _Destellos({
    required this.nivel,
    required this.sonando,
    required this.entrada,
    required this.quieto,
  });

  final NivelEco nivel;
  final int sonando;
  final double Function(int i) entrada;
  final bool quieto;

  @override
  Widget build(BuildContext context) {
    final n = nivel.trozos;
    final lado = n > 5 ? 64.0 : 74.0;
    return LayoutBuilder(builder: (context, k) {
      final w = k.maxWidth;
      // Cada destello ocupa (lado − 14) en la fila y la fila va centrada.
      final x0 = (w - n * (lado - 14)) / 2;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Brillo de fondo: `left/right 10; top 35; alto 120; radio 60;
          // radial-gradient(ellipse at center, verde .3 0, .12 50%, 0 75%)`.
          Positioned(
            left: 10,
            right: 10,
            top: 35,
            height: 120,
            child: LayoutBuilder(
              builder: (context, kb) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(60),
                  gradient: RadialGradient(
                    radius: .7071,
                    colors: const [
                      Color.fromRGBO(34, 160, 84, .3),
                      Color.fromRGBO(34, 160, 84, .12),
                      Color.fromRGBO(34, 160, 84, 0),
                    ],
                    stops: const [0, .5, .75],
                    transform: elipseHastaEsquinas(kb.biggest),
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < n; i++)
            Positioned(
              left: x0 + i * (lado - 14) - 7,
              top: (190 - lado) / 2,
              width: lado,
              height: lado,
              child: _Destello(
                adulto: nivel.guiaAdulto && !(nivel.ultimoTrozoNino && i == n - 1),
                grande: sonando == i,
                entrada: entrada(i),
                quieto: quieto,
              ),
            ),
        ],
      );
    });
  }
}

class _Destello extends StatelessWidget {
  const _Destello({required this.adulto, required this.grande, required this.entrada, required this.quieto});

  final bool adulto;
  final bool grande;
  final double entrada;
  final bool quieto;

  @override
  Widget build(BuildContext context) {
    // `radial-gradient(circle, color 0, color 30%, transparente 70%)`.
    final c = adulto ? const Color.fromRGBO(179, 162, 220, .95) : const Color.fromRGBO(232, 94, 69, .9);
    final circulo = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          radius: .7071,
          colors: [c, c, c.withValues(alpha: 0)],
          stops: const [0, .3, .7],
        ),
      ),
    );
    // La escala propia (1 o 1,35) cambia con transición de .35 s ease; la
    // entrada parte desde ×0,4 y llega a esa escala.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: grande ? 1.35 : 1),
      duration: quieto ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.ease,
      builder: (context, escala, child) => Opacity(
        opacity: entrada,
        child: Transform.scale(scale: mezclar(.4, escala, entrada), child: child),
      ),
      child: circulo,
    );
  }
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
