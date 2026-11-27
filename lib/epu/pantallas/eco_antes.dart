import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio/sonidos.dart';
import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../ilustraciones/escena_antes.dart';
import '../ilustraciones/preparacion.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../widgets/comunes.dart';
import '../widgets/reloj.dart';

/// Eco · antes del nivel (EcoAntes.dc.html).
///
/// Muestra el movimiento del nivel con las dos manos animadas (sin partitura)
/// y bloquea «Comenzar» durante 4 s con una barra que se llena, para que
/// alcancen a mirar la animación (antes eran 3 s).
///
/// La pantalla «Quién guía» NO tiene este bloqueo (se probó y se descartó).
class PantallaEcoAntes extends StatefulWidget {
  const PantallaEcoAntes({super.key});

  @override
  State<PantallaEcoAntes> createState() => _PantallaEcoAntesState();
}

class _PantallaEcoAntesState extends State<PantallaEcoAntes> with SingleTickerProviderStateMixin {
  late final NivelEco _nivel = NivelEco.de(EpuEstado.leer(context).nivel);
  AnimacionAntes? _anim;
  bool _desbloqueado = false;
  Timer? _desbloqueo;

  late final AnimationController _barra =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..forward();

  @override
  void initState() {
    super.initState();
    _desbloqueo = Timer(const Duration(milliseconds: 4000), () {
      if (mounted) setState(() => _desbloqueado = true);
    });
    EpuSonidos.instancia.precargarNivel(_nivel);
  }

  @override
  void dispose() {
    _desbloqueo?.cancel();
    _barra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    final anim = _anim ??= AnimacionAntes(_nivel, quieta: quieto);
    final n = _nivel;

    final encabezado = Column(
      children: [
        Text('Nivel ${n.id} de 7 · ${n.instrumento}', style: EpuTextos.etiqueta, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        PuntosDificultad(dificultad: n.dificultad, estilo: EpuTextos.miniFuerte),
      ],
    );

    // SVG de 285 px (viewBox 120 × 100) dentro de una zona de 260–388 px.
    final ilustracion = ZonaIlustracion(
      minimo: 260,
      maximo: 388,
      child: DibujoCentrado(
        ancho: 285,
        alto: 285 * 100 / 120,
        child: Reloj(
          activo: !quieto,
          builder: (context, ms) {
            anim.avanzar(ms);
            return LienzoSvg(vbAncho: 120, vbAlto: 100, ancho: 285, pintor: anim.pintar, etiqueta: n.alt);
          },
        ),
      ),
    );

    final textos = Column(
      children: [
        Text(n.nombre, style: EpuTextos.tituloMediano, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(n.peculiaridad, style: EpuTextos.subtitulo, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(n.texto, style: EpuTextos.cuerpo, textAlign: TextAlign.center),
      ],
    );

    return PantallaBase(
      atras: Pantalla.elegirNivel,
      relleno: const EdgeInsets.fromLTRB(22, 66, 22, 28),
      child: ColumnaConBoton(
        separacion: 18,
        arriba: [encabezado, ilustracion, textos],
        boton: _BotonComenzar(
          desbloqueado: _desbloqueado,
          barra: _barra,
          quieto: quieto,
          alTocar: () => EpuNavegacion.ir(context, Pantalla.guia),
        ),
      ),
    );
  }
}

/// «Comenzar»: gris con una barra que se llena en 4 s (lineal); después pasa
/// a oscuro en 0,3 s y recién ahí se puede tocar (`pointer-events: none`
/// mientras está bloqueado).
class _BotonComenzar extends StatelessWidget {
  const _BotonComenzar({
    required this.desbloqueado,
    required this.barra,
    required this.quieto,
    required this.alTocar,
  });

  final bool desbloqueado;
  final Animation<double> barra;
  final bool quieto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    const dur = Duration(milliseconds: 300);
    final fondo = desbloqueado ? EpuColores.tinta : EpuColores.bloqueado;
    return Semantics(
      button: true,
      enabled: desbloqueado,
      child: IgnorePointer(
        ignoring: !desbloqueado,
        child: GestureDetector(
          onTap: alTocar,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.ease,
            constraints: const BoxConstraints(minHeight: 58),
            decoration: BoxDecoration(
              color: fondo,
              border: Border.all(color: fondo, width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16 - 1.5),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!desbloqueado)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: barra,
                        builder: (context, _) => Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            // Sin animaciones: barra completa al 45 %.
                            widthFactor: quieto ? 1 : barra.value,
                            heightFactor: 1,
                            child: Opacity(
                              opacity: quieto ? .45 : 1,
                              child: const ColoredBox(color: EpuColores.bloqueadoBarra),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    child: AnimatedDefaultTextStyle(
                      duration: dur,
                      curve: Curves.ease,
                      style: EpuTextos.botonGrande.copyWith(
                        color: desbloqueado ? EpuColores.blanco : EpuColores.bloqueadoTexto,
                      ),
                      child: const Text('Comenzar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
