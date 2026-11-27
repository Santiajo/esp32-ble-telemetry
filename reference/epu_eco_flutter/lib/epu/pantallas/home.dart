import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../datos/niveles.dart';
import '../estado/estado_eco.dart';
import '../ilustraciones/huella.dart';
import '../ilustraciones/logo_epu.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../util/css.dart';
import '../widgets/boton_jugar.dart';

/// Home (Home.dc.html).
///
/// Solo el logo y el botón «Jugar» (lleva a «Eco · elegir nivel»). Las
/// sesiones pasadas y el enlace «Repasar la preparación» se quitaron del
/// Home: los recuerdos y las sesiones ahora viven en el menú hamburguesa
/// «Tu archivo» ([_MenuArchivo]), y la preparación ya no tiene entrada desde
/// aquí (queda pendiente decidir si necesita una).
class PantallaHome extends StatefulWidget {
  const PantallaHome({super.key, this.menuInicial});

  /// Abre el menú de entrada en una pestaña (para revisar la vista, como la
  /// propiedad `menu` del prototipo). `null` = cerrado.
  final PestanaArchivo? menuInicial;

  @override
  State<PantallaHome> createState() => _PantallaHomeState();
}

enum PestanaArchivo { recuerdos, sesiones }

class _PantallaHomeState extends State<PantallaHome> {
  late bool _abierto = widget.menuInicial != null;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con el menú abierto, «volver» del sistema lo cierra.
      canPop: !_abierto,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho && _abierto) setState(() => _abierto = false);
      },
      child: ColoredBox(
        color: EpuColores.fondo,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        // `padding: 24px 22px 28px; gap 18px; align-items: center`
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                        child: Column(
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 2), child: LogoEpu.alto(34)),
                            const SizedBox(height: 18),
                            // Zona del botón: `min-height: 573px`, botón centrado.
                            SizedBox(
                              height: 573,
                              child: Center(
                                child: BotonJugar(alTocar: () => EpuNavegacion.ir(context, Pantalla.elegirNivel)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _BotonHamburguesa(alTocar: () => setState(() => _abierto = true)),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: _MenuArchivo(
                abierto: _abierto,
                pestanaInicial: widget.menuInicial ?? PestanaArchivo.recuerdos,
                alCerrar: () => setState(() => _abierto = false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón del menú: círculo blanco de 44 px, sombra `0 2px 10px .1`, tres
/// barras de 18 × 2,5 (radio 2) separadas 4 px.
class _BotonHamburguesa extends StatelessWidget {
  const _BotonHamburguesa({required this.alTocar});
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    Widget barra() => Container(
          width: 18,
          height: 2.5,
          decoration: BoxDecoration(color: EpuColores.tinta, borderRadius: BorderRadius.circular(2)),
        );
    return Semantics(
      button: true,
      label: 'Abrir el menú: recuerdos y sesiones',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: alTocar,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: EpuColores.blanco, shape: BoxShape.circle, boxShadow: [sombraBotonAtras]),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [barra(), const SizedBox(height: 4), barra(), const SizedBox(height: 4), barra()],
          ),
        ),
      ),
    );
  }
}

/// Menú «Tu archivo»: recuerdos guardados y sesiones jugadas, agrupados por
/// nivel.
///
/// Animaciones (CSS del prototipo):
/// * Abrir: velo `fi .25s ease` (de transparente a rgba(43,37,54,.35)) y
///   panel `si .35s cubic-bezier(.2,.8,.2,1)` (entra desde −100 %).
/// * Cerrar: velo `fo .22s ease` y panel `so .22s ease-in`; recién al
///   terminar se quita la capa.
/// * Con «Quitar animaciones», abre y cierra de golpe.
///
/// Se cierra con la X, tocando el velo o con «volver» del sistema.
class _MenuArchivo extends StatefulWidget {
  const _MenuArchivo({required this.abierto, required this.pestanaInicial, required this.alCerrar});

  final bool abierto;
  final PestanaArchivo pestanaInicial;
  final VoidCallback alCerrar;

  @override
  State<_MenuArchivo> createState() => _MenuArchivoState();
}

class _MenuArchivoState extends State<_MenuArchivo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _cerrando = false;
  late PestanaArchivo _pestana = widget.pestanaInicial;

  /// Grupos desplegados («Ver N más»), por pestaña y nivel.
  final Set<String> _desplegados = {};

  @override
  void initState() {
    super.initState();
    if (widget.abierto) _c.value = 1;
  }

  @override
  void didUpdateWidget(_MenuArchivo old) {
    super.didUpdateWidget(old);
    if (widget.abierto == old.abierto) return;
    final quieto = sinMovimiento(context);
    if (widget.abierto) {
      _cerrando = false;
      _c.duration = Duration(milliseconds: quieto ? 0 : 350);
      _c.forward(from: 0);
    } else {
      _cerrando = true;
      _c.duration = Duration(milliseconds: quieto ? 0 : 220);
      _c.reverse(from: 1).whenComplete(() {
        if (mounted) setState(() => _cerrando = false);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.abierto && !_cerrando && _c.value == 0) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, panel) {
        final ms = _c.value * (_cerrando ? 220 : 350);
        // Al abrir: velo en 250 ms ease, panel en 350 ms con rebote suave.
        // Al cerrar (el controlador va de 1 a 0): los dos en 220 ms.
        final double velo, entrada;
        if (_cerrando) {
          velo = 1 - Curves.ease.transform(1 - _c.value);
          entrada = 1 - Curves.easeIn.transform(1 - _c.value);
        } else {
          velo = Curves.ease.transform((ms / 250).clamp(0.0, 1.0));
          entrada = CurvasEpu.pop.transform(_c.value);
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.alCerrar,
                child: ColoredBox(color: Color.fromRGBO(43, 37, 54, .35 * velo)),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 330,
              child: FractionalTranslation(translation: Offset(entrada - 1, 0), child: panel),
            ),
          ],
        );
      },
      child: _panel(context),
    );
  }

  Widget _panel(BuildContext context) {
    final estado = EpuEstado.of(context);
    final enRec = _pestana == PestanaArchivo.recuerdos;

    // Agrupa por nivel (1 → 7), conservando el orden de cada lista (lo más
    // nuevo primero).
    final grupos = <Widget>[];
    for (var id = 1; id <= 7; id++) {
      final n = NivelEco.de(id);
      final items = enRec
          ? estado.recuerdos.where((r) => r.nivel == id).toList()
          : estado.sesiones.where((s) => s.nivel == id).toList();
      if (items.isEmpty) continue;
      final clave = '${_pestana.name}$id';
      grupos.add(_Grupo(
        nivel: n,
        cantidad: items.length,
        desplegado: _desplegados.contains(clave),
        alAlternar: () => setState(() => _desplegados.contains(clave) ? _desplegados.remove(clave) : _desplegados.add(clave)),
        recuerdos: enRec ? items.cast<RecuerdoGuardado>() : null,
        sesiones: enRec ? null : items.cast<SesionNivel>(),
        alAbrir: () {
          // Se abre «Eco · el recuerdo» de ese nivel, ya guardado.
          estado.nivel = id;
          widget.alCerrar();
          EpuNavegacion.ir(context, Pantalla.recuerdo, argumentos: ArgumentosRecuerdo.desdeArchivo);
        },
      ));
    }

    return Semantics(
      label: 'Archivo de recuerdos y sesiones',
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: EpuColores.fondo,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
          // `box-shadow: 8px 0 30px rgba(43,37,54,.18)`
          boxShadow: [sombraCss(8, 0, 30, const Color.fromRGBO(43, 37, 54, .18))],
        ),
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera: logo a la izquierda (30 px) y la X a la derecha.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [const LogoEpu.alto(30), _BotonCerrar(alTocar: widget.alCerrar)],
                ),
                const SizedBox(height: 10),
                Text('Tu archivo', style: EpuTextos.tituloPequeno),
                const SizedBox(height: 14),
                _Pestanas(
                  actual: _pestana,
                  alElegir: (p) => setState(() => _pestana = p),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    // `.lista { scrollbar-width: none }`
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                      children: grupos.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 28, 8, 0),
                                child: Text(
                                  enRec
                                      ? 'Todavía no guardan recuerdos. Al terminar una melodía, toquen el marcador para guardarlo.'
                                      : 'Todavía no hay sesiones. Aparecen solas cuando terminan una melodía.',
                                  style: EpuTextos.nunito(14, FontWeight.w700, color: EpuColores.textoSecundario),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ]
                          : grupos,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// X para cerrar: círculo blanco de 40 px con dos barras de 18 × 2,5 en cruz.
class _BotonCerrar extends StatelessWidget {
  const _BotonCerrar({required this.alTocar});
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    Widget barra(double grados) => Transform.rotate(
          angle: grados * math.pi / 180,
          child: Container(
            width: 18,
            height: 2.5,
            decoration: BoxDecoration(color: EpuColores.tinta, borderRadius: BorderRadius.circular(2)),
          ),
        );
    return Semantics(
      button: true,
      label: 'Cerrar el menú',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: alTocar,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: EpuColores.blanco, shape: BoxShape.circle, boxShadow: [sombraBotonAtras]),
          child: Stack(alignment: Alignment.center, children: [barra(45), barra(-45)]),
        ),
      ),
    );
  }
}

/// Pestañas «Recuerdos» / «Sesiones» (sin contador): píldora blanca con
/// `padding 4; gap 4`; cada pestaña `min-height 40; 14px 800`. La elegida
/// va en tinta con texto blanco (transición .25 s).
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.actual, required this.alElegir});

  final PestanaArchivo actual;
  final ValueChanged<PestanaArchivo> alElegir;

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    Widget pestana(PestanaArchivo p, String texto) {
      final on = actual == p;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            onTap: () => alElegir(p),
            child: AnimatedContainer(
              duration: quieto ? Duration.zero : const Duration(milliseconds: 250),
              curve: Curves.ease,
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? EpuColores.tinta : const Color(0x002B2536),
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedDefaultTextStyle(
                duration: quieto ? Duration.zero : const Duration(milliseconds: 250),
                curve: Curves.ease,
                style: EpuTextos.nunito(14, FontWeight.w800, color: on ? EpuColores.blanco : EpuColores.tinta),
                child: Text(texto),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: EpuColores.blanco, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          pestana(PestanaArchivo.recuerdos, 'Recuerdos'),
          const SizedBox(width: 4),
          pestana(PestanaArchivo.sesiones, 'Sesiones'),
        ],
      ),
    );
  }
}

/// Un nivel dentro de «Tu archivo»: título «Nivel N - nombre», instrumento,
/// cantidad y hasta [maximo] elementos; con más, «Ver N más» / «Ver menos».
class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.nivel,
    required this.cantidad,
    required this.desplegado,
    required this.alAlternar,
    required this.alAbrir,
    this.recuerdos,
    this.sesiones,
  });

  /// Elementos visibles por nivel antes del botón «Ver N más».
  static const maximo = 3;

  final NivelEco nivel;
  final int cantidad;
  final bool desplegado;
  final VoidCallback alAlternar;
  final VoidCallback alAbrir;
  final List<RecuerdoGuardado>? recuerdos;
  final List<SesionNivel>? sesiones;

  @override
  Widget build(BuildContext context) {
    final n = nivel;
    final extra = cantidad - maximo;
    final cuantos = desplegado ? cantidad : math.min(cantidad, maximo);

    final cabecera = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Nivel ${n.id} - ${n.nombre} '),
              TextSpan(
                text: n.instrumento,
                style: EpuTextos.nunito(12, FontWeight.w700, color: EpuColores.textoSecundario),
              ),
            ]),
            style: EpuTextos.nunito(15, FontWeight.w900),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minWidth: 22),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(color: EpuColores.blanco, borderRadius: BorderRadius.circular(999)),
          child: Text('$cantidad', style: EpuTextos.miniFuerte, textAlign: TextAlign.center),
        ),
      ],
    );

    final Widget cuerpo;
    if (recuerdos != null) {
      // Tarjetas de 92 px: dibujo de 80 px y la fecha (11px 800).
      cuerpo = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in recuerdos!.take(cuantos))
            Semantics(
              button: true,
              label: 'Recuerdo del nivel ${n.id}, ${n.nombre}, ${fechaArchivo(r.fecha)}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: alAbrir,
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  decoration: BoxDecoration(color: EpuColores.blanco, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      DibujoHuella(nivel: n, lado: 80),
                      const SizedBox(height: 4),
                      Text(
                        fechaArchivo(r.fecha),
                        textAlign: TextAlign.center,
                        style: EpuTextos.nunito(11, FontWeight.w800, color: EpuColores.textoSecundario, alto: 1.15),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      // Filas: fecha, «X min · ok de N trozos», barra de progreso y chevrón.
      cuerpo = Column(
        children: [
          for (final (i, s) in sesiones!.take(cuantos).indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            _FilaSesion(sesion: s, nivel: n, alTocar: alAbrir),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cabecera,
          const SizedBox(height: 8),
          cuerpo,
          if (extra > 0) ...[
            const SizedBox(height: 8),
            _BotonVerMas(texto: desplegado ? 'Ver menos' : 'Ver $extra más', abierto: desplegado, alTocar: alAlternar),
          ],
        ],
      ),
    );
  }
}

class _FilaSesion extends StatelessWidget {
  const _FilaSesion({required this.sesion, required this.nivel, required this.alTocar});

  final SesionNivel sesion;
  final NivelEco nivel;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final s = sesion, tot = nivel.trozos;
    final fecha = fechaArchivo(s.fecha);
    return Semantics(
      button: true,
      label: 'Sesión del nivel ${nivel.id}, $fecha, ${s.logrados} de $tot trozos',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: alTocar,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(color: EpuColores.blanco, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(fecha, style: EpuTextos.nunito(13, FontWeight.w800)),
                        const SizedBox(width: 8),
                        Text('${s.minutos} min · ${s.logrados} de $tot trozos',
                            style: EpuTextos.nunito(13, FontWeight.w700, color: EpuColores.textoSecundario)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Barra: 6 px, fondo #dcd8cf, relleno teal = logrados / trozos.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            const Positioned.fill(child: ColoredBox(color: EpuColores.linea)),
                            FractionallySizedBox(
                              widthFactor: (s.logrados / tot).clamp(0.0, 1.0),
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: EpuColores.teal, borderRadius: BorderRadius.circular(3)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Chevrón: caja 8 × 8 con borde derecho y superior de 2,5 girada 45°.
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: _Chevron(lado: 8, grados: 45, color: EpuColores.textoSecundario, arriba: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Ver N más» / «Ver menos»: `min-height 40; borde 1.5 rgba(43,37,54,.15);
/// radio 14; 13px 800`. El chevrón gira de abajo (45°, −2 px) a arriba
/// (−135°, +2 px) en .25 s ease.
class _BotonVerMas extends StatelessWidget {
  const _BotonVerMas({required this.texto, required this.abierto, required this.alTocar});

  final String texto;
  final bool abierto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final quieto = sinMovimiento(context);
    return Semantics(
      button: true,
      expanded: abierto,
      child: GestureDetector(
        onTap: alTocar,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color.fromRGBO(43, 37, 54, .15), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(texto, style: EpuTextos.nunito(13, FontWeight.w800)),
              const SizedBox(width: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(end: abierto ? 1 : 0),
                duration: quieto ? Duration.zero : const Duration(milliseconds: 250),
                curve: Curves.ease,
                builder: (context, p, _) => Transform.translate(
                  offset: Offset(0, mezclar(-2, 2, p)),
                  child: _Chevron(lado: 7, grados: mezclar(45, -135, p), color: EpuColores.tinta, arriba: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chevrón hecho como en CSS: caja con dos bordes de 2,5 px, girada.
/// [arriba]: bordes derecho y superior; si no, derecho e inferior.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.lado, required this.grados, required this.color, required this.arriba});

  final double lado, grados;
  final Color color;
  final bool arriba;

  @override
  Widget build(BuildContext context) {
    final borde = BorderSide(color: color, width: 2.5);
    return Transform.rotate(
      angle: grados * math.pi / 180,
      child: Container(
        width: lado,
        height: lado,
        decoration: BoxDecoration(
          border: Border(right: borde, top: arriba ? borde : BorderSide.none, bottom: arriba ? BorderSide.none : borde),
        ),
      ),
    );
  }
}
