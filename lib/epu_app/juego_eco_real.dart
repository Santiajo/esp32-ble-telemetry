import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../epu/audio/sonidos.dart';
import '../epu/datos/niveles.dart';
import '../epu/juego/estado_juego.dart';
import '../epu/juego/fuente_sticks.dart';
import 'fuente_sticks_ble.dart';
import 'motor_eco.dart';

/// Juego de la pantalla de Joaquín con los sticks reales: lee [FuenteSticks.lecturas],
/// mueve [MotorEco] 50 veces por segundo y toca los sonidos.
class JuegoEcoReal implements JuegoEco {
  JuegoEcoReal({
    required this.fuente,
    required NivelEco nivel,
    required EstadoJuegoEco estado,
    required void Function() alTerminar,
    AjustesEco ajustes = const AjustesEco(),
  }) : motor = MotorEco(
          nivel: nivel,
          estado: estado,
          ajustes: ajustes,
          tocarTrozo: (i) => unawaited(EpuSonidos.instancia.tocarTrozo(nivel, i)),
          tocarMelodia: () => unawaited(EpuSonidos.instancia.tocarMelodia(nivel)),
          alTerminar: alTerminar,
        );

  /// Crea el juego real para los niveles que sabe jugar el motor (1 a 4).
  static JuegoEco? para(FuenteSticks fuente, NivelEco nivel, EstadoJuegoEco estado, void Function() alTerminar) =>
      MotorEco.soporta(nivel) ? JuegoEcoReal(fuente: fuente, nivel: nivel, estado: estado, alTerminar: alTerminar) : null;

  final FuenteSticks fuente;
  final MotorEco motor;

  /// Una lectura más vieja que esto se toma como «sin datos» (stick quieto en el centro).
  static const Duration vencimiento = Duration(milliseconds: 500);

  final Map<Stick, (LecturaStick, DateTime)> _ultima = {};
  late final bool _ninoSimulado = fuente is FuenteSticksBle && (fuente as FuenteSticksBle).unStick;
  final _NinoSimulado _nino = _NinoSimulado();
  StreamSubscription<LecturaStick>? _sub;
  Timer? _reloj;
  final Stopwatch _t = Stopwatch();
  int _n = 0;

  @override
  void iniciar() {
    unawaited(WakelockPlus.enable().catchError((_) {}));
    _sub = fuente.lecturas.listen((l) => _ultima[l.stick] = (l, DateTime.now()));
    _t.start();
    _reloj = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  Vuelco? _vuelco(Stick s) {
    if (s == Stick.pequeno && _ninoSimulado) return _nino.vuelco(motor, _t.elapsedMilliseconds.toDouble());
    final u = _ultima[s];
    if (u == null || DateTime.now().difference(u.$2) > vencimiento) return null;
    return (lateral: u.$1.lateral, frontal: u.$1.frontal);
  }

  void _tick() {
    motor.tick(_t.elapsedMilliseconds.toDouble(), adulto: _vuelco(Stick.grande), nino: _vuelco(Stick.pequeno));
    if (FuenteSticksBle.registrar && ++_n % 50 == 0) {
      // ignore: avoid_print
      print('[EPU] juego paso ${motor.paso} · elegido ${motor.elegido?.name} · objetivo ${motor.objetivo?.name}'
          ' · adulto ${motor.bordeAdulto?.name} · niño ${motor.bordeNino?.name}');
    }
    if (motor.terminado) _reloj?.cancel();
  }

  @override
  void detener() {
    _reloj?.cancel();
    unawaited(_sub?.cancel());
    unawaited(WakelockPlus.disable().catchError((_) {}));
    unawaited(EpuSonidos.instancia.detener());
  }
}

/// Niño de mentira para probar con un solo stick (`EPU_UN_STICK`): si sigue, va al
/// borde que le toca 1,2 s después; si guía, elige un borde 2 s después de
/// volver al centro. Devuelve el vuelco en su propio marco (frente a frente).
class _NinoSimulado {
  /// Tiempos de una persona tranquila (con 0,6 s se sentía que imitaba al instante).
  static const int seguirMs = 1200, elegirMs = 2000;

  int _paso = -1;
  double _desde = 0;
  Borde? _objetivoVisto;
  int _eleccion = 0;

  Vuelco vuelco(MotorEco m, double ahora) {
    if (m.paso != _paso) {
      _paso = m.paso;
      _desde = ahora;
      _objetivoVisto = null;
    }
    final guiaNino = !m.nivel.guiaAdulto;
    Borde? b;
    if (guiaNino) {
      if (m.elegido != null) {
        b = m.elegido;
      } else if (ahora - _desde > elegirMs) {
        final opciones = m.permitidos.toList();
        b = opciones[_eleccion % opciones.length];
      }
    } else if (m.objetivo != null) {
      if (_objetivoVisto != m.objetivo) {
        _objetivoVisto = m.objetivo;
        _desde = ahora;
      }
      if (ahora - _desde > seguirMs) b = m.objetivo;
    }
    if (m.elegido == null && guiaNino && b == null) _eleccion++;
    // Borde de la pantalla → marco del niño, que está enfrente: todo al revés.
    return switch (b) {
      Borde.frente => (lateral: 0.0, frontal: 30.0),
      Borde.atras => (lateral: 0.0, frontal: -30.0),
      Borde.derecha => (lateral: -30.0, frontal: 0.0),
      Borde.izquierda => (lateral: 30.0, frontal: 0.0),
      null => (lateral: 0.0, frontal: 0.0),
    };
  }
}
