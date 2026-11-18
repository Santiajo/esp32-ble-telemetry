import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio/sonidos.dart';
import '../ilustraciones/preparacion.dart';
import '../juego/fuente_sticks.dart';
import '../navegacion/rutas.dart';
import '../tema/colores.dart';
import '../tema/textos.dart';
import '../widgets/boton_estado.dart';
import '../widgets/comunes.dart';
import '../widgets/preparacion.dart';

/// Preparación 3 · Conecta los dos sticks (Prep4.dc.html).
///
/// Estados del botón:
/// | estado     | texto              | fondo    | borde    | texto     |
/// |------------|--------------------|----------|----------|-----------|
/// | inicial    | «Conectar sticks»  | #2B2536  | #2B2536  | blanco    |
/// | conectando | «Conectando…»      | blanco   | #0D9488  | #0B6F66   | + brillo que late
/// | listo      | «Sticks conectados»| #0D9488  | #0D9488  | blanco    | + check
///
/// Mientras conecta, la luz de cada stick parpadea cada 250 ms; cuando ese
/// stick queda conectado suena el tono y la luz queda fija. 1,5 s después de
/// conectar los dos, pasa sola a la siguiente pantalla.
class PantallaConectar extends StatefulWidget {
  const PantallaConectar({super.key});

  @override
  State<PantallaConectar> createState() => _PantallaConectarState();
}

enum _Fase { inicial, conectando, listo }

class _PantallaConectarState extends State<PantallaConectar> {
  _Fase _fase = _Fase.inicial;
  bool _luz1 = false, _luz2 = false; // encendida / apagada en este cuadro
  bool _listo1 = false, _listo2 = false; // stick ya conectado
  Timer? _parpadeo, _siguiente;
  StreamSubscription<Stick>? _sub;

  void _conectar() {
    if (_fase != _Fase.inicial) return;
    setState(() {
      _fase = _Fase.conectando;
      _luz1 = _luz2 = true;
    });
    _parpadeo = Timer.periodic(const Duration(milliseconds: 250), (_) {
      setState(() {
        _luz1 = _listo1 ? true : !_luz1;
        _luz2 = _listo2 ? true : !_luz2;
      });
    });
    _sub = EpuSticks.fuente.conectar().listen((stick) {
      EpuSonidos.instancia.tonoConexion();
      setState(() {
        if (stick == Stick.grande) {
          _listo1 = _luz1 = true;
        } else {
          _listo2 = _luz2 = true;
        }
        if (_listo1 && _listo2) {
          _parpadeo?.cancel();
          _fase = _Fase.listo;
          _siguiente = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) EpuNavegacion.ir(context, Pantalla.quienUsa);
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _parpadeo?.cancel();
    _siguiente?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _fase;
    return PasoPreparacion(
      paso: 3,
      atras: Pantalla.sinAvisos,
      minimoIlustracion: 220,
      // `padding: 8px 24px`; SVG de 290 px.
      ilustracion: DibujoCentrado(
        ancho: 290,
        alto: 290 * 260 / 320,
        relleno: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: LienzoSvg(
          vbAncho: 320,
          vbAlto: 260,
          ancho: 290,
          pintor: (c) => pintarConectar(c, luz1: _luz1, luz2: _luz2),
          etiqueta: 'Los dos sticks, lila y naranjo, con su luz de conexión',
        ),
      ),
      titulo: const Text('Conecta los dos sticks'),
      texto: 'Toca el botón. La luz de cada stick parpadea mientras se conecta y queda fija al terminar.',
      boton: BotonEstado(
        etiqueta: switch (f) {
          _Fase.inicial => 'Conectar sticks',
          _Fase.conectando => 'Conectando…',
          _Fase.listo => 'Sticks conectados',
        },
        estiloTexto: EpuTextos.botonEstado,
        colorTexto: f == _Fase.conectando ? EpuColores.tealOscuro : EpuColores.blanco,
        fondo: switch (f) {
          _Fase.inicial => EpuColores.tinta,
          _Fase.conectando => EpuColores.blanco,
          _Fase.listo => EpuColores.teal,
        },
        borde: f == _Fase.inicial ? EpuColores.tinta : EpuColores.teal,
        altoMinimo: 62,
        respiracion: f == _Fase.conectando ? Respiracion.teal : null,
        icono: f == _Fase.listo ? const CheckEnCirculo() : null,
        alTocar: _conectar,
      ),
    );
  }
}
