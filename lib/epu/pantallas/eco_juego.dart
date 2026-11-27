import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../juego/estado_juego.dart';
import '../juego/fuente_sticks.dart';
import '../juego/simulacion_eco.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../util/css.dart';
import '../util/degradados.dart';
import '../widgets/lados_de_cada_uno.dart';
import '../widgets/reloj.dart';

/// Eco · descubrir la melodía (EcoJuego.dc.html).
///
/// Fondo oscuro, sin textos ni botones: el teléfono va dentro del eje.
///
/// Antes de empezar se muestran 5 s «Quién va en cada lado»
/// ([LadosDeCadaUno]): arriba, junto a la cámara, el niño; abajo, el adulto.
/// Recién después arranca la simulación (o, en la app real, la lectura de
/// los sticks).
///
/// Solo hay luces:
/// * dos luces difusas, una por stick (lila 104 px, coral 84 px);
/// * franjas en los bordes que indican hacia dónde ir (del color de quien
///   tiene que moverse);
/// * una franja amarilla más ancha que crece cuando hay que sostener;
/// * la luz verde de acierto.
///
/// Esta pantalla solo dibuja un [EstadoJuegoEco]. Hoy lo mueve
/// [SimulacionEco] (lo mismo que el prototipo). Para el juego real, cambiar
/// la simulación por la lógica que lee los sticks; el dibujo no cambia.
///
/// Las coordenadas del estado son del marco de 390 × 844 del prototipo y se
/// escalan al tamaño real de la pantalla.
class PantallaEcoJuego extends StatefulWidget {
  const PantallaEcoJuego({super.key});

  @override
  State<PantallaEcoJuego> createState() => _PantallaEcoJuegoState();
}

class _PantallaEcoJuegoState extends State<PantallaEcoJuego> {
  final _estado = EstadoJuegoEco();
  SimulacionEco? _sim;
  JuegoEco? _real; // integración: juego con los sticks reales

  /// Para registrar cuánto duró la sesión.
  final _inicio = DateTime.now();

  /// `true` durante los 5 s de «Quién va en cada lado».
  bool _lados = true;

  @override
  void initState() {
    super.initState();
    // Las luces de los sticks aparecen recién cuando empieza el juego.
    _estado.cambiar(lucesVisibles: false);
    // Pantalla completa: sin barra de estado ni de navegación mientras se juega.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sim != null || _real != null) return;
    final global = EpuEstado.leer(context);
    final nivel = NivelEco.de(global.nivel);
    void alTerminar() {
      if (!mounted) return;
      // La pantalla de juego queda debajo del recuerdo: se restauran las
      // barras del sistema aquí y no recién al cerrarla.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      global.marcarCompletado(nivel.id);
      // Integración: el recuerdo se dibuja con lo que de verdad jugaron (con la
      // simulación, la partitura). El juego siempre termina con todos los trozos.
      final pasos = _real?.pasosJugados;
      global.pasosVista = pasos;
      // Cada nivel terminado queda como sesión en «Tu archivo» (menú del Home).
      global.registrarSesion(
        nivel.id,
        minutos: (DateTime.now().difference(_inicio).inSeconds / 60).round(),
        logrados: nivel.trozos,
        pasos: pasos,
      );
      EpuNavegacion.ir(context, Pantalla.recuerdo);
    }

    // Integración: con sticks reales juega el motor; si no, la simulación.
    _real = EpuSticks.crearJuego?.call(nivel, _estado, alTerminar);
    if (_real == null) _sim = SimulacionEco(nivel: nivel, estado: _estado, alTerminar: alTerminar);
  }

  /// Termina «Quién va en cada lado» y arranca el juego.
  void _empezar() {
    if (!mounted) return;
    setState(() => _lados = false);
    _sim?.iniciar();
    _real?.iniciar(); // los sticks se leen recién aquí (CAMBIOS 0.3)
  }

  @override
  void dispose() {
    _sim?.detener();
    _real?.detener();
    _estado.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sin salida: en el prototipo esta pantalla no tiene «Atrás".
    return PopScope(
      canPop: false,
      child: ColoredBox(
        color: EpuColores.noche,
        child: LayoutBuilder(
          builder: (context, k) => Stack(
            children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _estado,
                  builder: (context, _) => _VistaJuego(estado: _estado, tamano: k.biggest),
                ),
              ),
              if (_lados) Positioned.fill(child: LadosDeCadaUno(alTerminar: _empezar)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VistaJuego extends StatelessWidget {
  const _VistaJuego({required this.estado, required this.tamano});

  final EstadoJuegoEco estado;
  final Size tamano;

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    final e = estado;
    final sx = tamano.width / 390, sy = tamano.height / 844;

    // Franjas de pista: `.fade { transition: opacity .5s ease }`.
    Widget franja(Borde b, Color color, bool visible) => Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: quieto ? Duration.zero : const Duration(milliseconds: 500),
              curve: Curves.ease,
              child: _Franja(borde: b, color: color, ancha: false),
            ),
          ),
        );

    // Franja de sostener: crece en 1,4 s lineal (`.grow`) y se va en 0,25 s
    // ease (`.drop`). La clase cambia junto con la opacidad, así que la
    // duración depende de si se enciende o se apaga.
    Widget sostener(Borde b) {
      final on = e.sostener == b;
      final hay = e.sostener != null;
      return Positioned.fill(
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: quieto ? Duration.zero : Duration(milliseconds: hay ? 1400 : 250),
            curve: hay ? Curves.linear : Curves.ease,
            child: _Franja(borde: b, color: EpuColores.luzStick, ancha: true),
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Orden de capas igual al HTML: adulto, niño, ambos, sostener, acierto.
        for (final b in Borde.values) franja(b, EpuColores.lilaAdulto, e.pistas[b] == ColorPista.adulto),
        for (final b in Borde.values) franja(b, EpuColores.coralNino, e.pistas[b] == ColorPista.nino),
        for (final b in Borde.values) franja(b, EpuColores.luzStick, e.pistas[b] == ColorPista.ambos),
        for (final b in Borde.values) sostener(b),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: e.acierto ? 1 : 0,
              duration: quieto ? Duration.zero : const Duration(milliseconds: 500),
              curve: Curves.ease,
              child: const _LuzAcierto(),
            ),
          ),
        ),
        _luz(adulto: true, centro: e.adulto, sx: sx, sy: sy, quieto: quieto),
        _luz(adulto: false, centro: e.nino, sx: sx, sy: sy, quieto: quieto),
      ],
    );
  }

  /// Luz de un stick. Se mueve con `transition: left/top .7s
  /// cubic-bezier(.4,0,.2,1)`; durante el giro, `.23s linear`. Aparece y se
  /// apaga en 0,4 s (ease). Mientras su dueño tiene que elegir, late
  /// (`pulse .9s ease-in-out infinite`: opacidad 1 → .4, escala 1 → .9).
  Widget _luz({required bool adulto, required Offset centro, required double sx, required double sy, required bool quieto}) {
    final lado = (adulto ? 104.0 : 84.0) * sx;
    final palpita = estado.parpadea == (adulto ? Guia.adulto : Guia.nino);
    return AnimatedPositioned(
      left: centro.dx * sx - lado / 2,
      top: centro.dy * sy - lado / 2,
      width: lado,
      height: lado,
      duration: quieto ? Duration.zero : Duration(milliseconds: estado.giro ? 230 : 700),
      curve: estado.giro ? Curves.linear : CurvasEpu.mover,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: estado.lucesVisibles ? 1 : 0,
          duration: quieto ? Duration.zero : const Duration(milliseconds: 400),
          curve: Curves.ease,
          child: palpita && !quieto
              ? Reloj(builder: (context, ms) {
                  final t = (ms % 900) / 900;
                  return Opacity(
                    opacity: latido(t, 1, .4),
                    child: Transform.scale(scale: latido(t, 1, .9), child: _Orbe(adulto: adulto)),
                  );
                })
              : _Orbe(adulto: adulto),
        ),
      ),
    );
  }
}

/// La luz difusa de un stick:
/// `radial-gradient(circle, centro 0, color 34%, color/.55 52%, transparente 74%)`
/// con `filter: blur(1.5px)` (en CSS, el valor de blur ya es la sigma).
class _Orbe extends StatelessWidget {
  const _Orbe({required this.adulto});

  final bool adulto;

  @override
  Widget build(BuildContext context) {
    final base = adulto ? EpuColores.lilaAdulto : EpuColores.coralNino;
    final centro = adulto ? EpuColores.centroLuzAdulto : EpuColores.centroLuzNino;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            radius: .7071, // `circle` llega a la esquina de la caja
            colors: [centro, base, base.withValues(alpha: .55), base.withValues(alpha: 0)],
            stops: const [0, .34, .52, .74],
          ),
        ),
      ),
    );
  }
}

/// Franja de luz en un borde (degradado lineal desde el borde hacia adentro).
///
/// Pista (`.fade`): más difuminada y angosta que en la versión anterior
/// (que iba .9 → .45 → 0 y llegaba al 7,5 % / 16 %). Ahora parte en .6 y se
/// desvanece en cinco tramos, sin borde marcado. El largo no cambia: sigue
/// cubriendo todo el borde.
///
/// | opacidad               | .6 | .34   | .14   | .05   | 0     |
/// |------------------------|----|-------|-------|-------|-------|
/// | bordes de arriba/abajo | 0  | 0,8 % | 2 %   | 3,2 % | 4,4 % |
/// | bordes de los lados    | 0  | 1,8 % | 4,4 % | 7 %   | 9,6 % |
///
/// Sostener (sin cambios): .9 → .45 → 0; .45 en 3,2 % y 0 en 14 % arriba y
/// abajo, .45 en 7 % y 0 en 30 % a los lados.
///
/// Los porcentajes son del alto (arriba/abajo) o del ancho (lados) de la
/// pantalla.
class _Franja extends StatelessWidget {
  const _Franja({required this.borde, required this.color, required this.ancha});

  final Borde borde;
  final Color color;
  final bool ancha;

  @override
  Widget build(BuildContext context) {
    final vertical = borde == Borde.frente || borde == Borde.atras;
    final List<double> stops = switch ((vertical, ancha)) {
      (true, false) => [0, .008, .02, .032, .044],
      (false, false) => [0, .018, .044, .07, .096],
      (true, true) => [0, .032, .14],
      (false, true) => [0, .07, .30],
    };
    final List<double> alfas = ancha ? const [.9, .45, 0] : const [.6, .34, .14, .05, 0];
    final (inicio, fin) = switch (borde) {
      Borde.frente => (Alignment.topCenter, Alignment.bottomCenter),
      Borde.atras => (Alignment.bottomCenter, Alignment.topCenter),
      Borde.izquierda => (Alignment.centerLeft, Alignment.centerRight),
      Borde.derecha => (Alignment.centerRight, Alignment.centerLeft),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: inicio,
          end: fin,
          colors: [for (final a in alfas) color.withValues(alpha: a)],
          stops: stops,
        ),
      ),
    );
  }
}

/// Luz verde de acierto:
/// `radial-gradient(ellipse 95% 80% at 50% 50%, verde/.7 0, verde/.4 45%, verde/.16 100%)`.
/// La elipse mide 95 % del ancho y 80 % del alto; fuera de ella queda el
/// último color (.16).
class _LuzAcierto extends StatelessWidget {
  const _LuzAcierto();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, k) {
        final w = k.maxWidth, h = k.maxHeight;
        final corto = k.biggest.shortestSide;
        const v = EpuColores.verdeAcierto;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              // Radio base = lado corto; se estira a 95 % del ancho y 80 % del alto.
              radius: 1,
              colors: [v.withValues(alpha: .7), v.withValues(alpha: .4), v.withValues(alpha: .16)],
              stops: const [0, .45, 1],
              transform: EstirarDegradado(.95 * w / corto, .8 * h / corto),
            ),
          ),
        );
      });
}
