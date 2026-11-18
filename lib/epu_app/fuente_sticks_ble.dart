import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../balancin/platform/stick_hub.dart';
import '../balancin/session/board_session.dart' show StickRole;
import '../balancin_v2/core/tilt/axis_map.dart';
import '../balancin_v2/core/tilt/vec3.dart';
import '../balancin_v2/platform/ble_permissions.dart';
import '../balancin_v2/platform/tilt_stick.dart';
import '../epu/juego/fuente_sticks.dart';

/// [FuenteSticks] con los sticks reales (XIAO ESP32-C3 + ICM-42688-P, protocolo v2).
///
/// Las pantallas de Joaquín (`lib/epu`) solo hablan con [FuenteSticks]. Por debajo
/// se reutiliza lo que ya está probado con sticks reales:
/// * [StickHub]: vinculación por nombre (`Epu-Adulto` / `Epu-Niño`), MAC guardada y
///   reconexión;
/// * [TiltStick]: inclinación contra la gravedad (filtro del acelerómetro y el
///   giroscopio) con los ejes de cada placa.
///
/// Convenciones de [LecturaStick]: `lateral` + = derecha; `frontal` − = adelante
/// (hacia el borde superior de la pantalla), + = atrás. Ambas en grados respecto
/// del cero que toma [calibrar].
class FuenteSticksBle implements FuenteSticks {
  FuenteSticksBle(this.hub, {this.unStick = false, this.alConectarLosDos});

  final StickHub hub;

  /// Pruebas con un solo stick: el del niño se da por conectado y queda quieto
  /// al centro. Se activa con `--dart-define=EPU_UN_STICK=true`.
  final bool unStick;

  /// Se llama cuando los dos sticks quedaron conectados por primera vez.
  final VoidCallback? alConectarLosDos;

  /// Tiempo que dura «Calibrando…» como mínimo (la barra del botón es de 3 s).
  static const Duration duracionCalibrar = Duration(seconds: 3);

  /// Ventana en la que se promedia la postura de reposo (al final de la calibración).
  static const Duration ventanaCero = Duration(milliseconds: 1200);

  /// Cada cuánto se emiten [lecturas] (50 por segundo).
  static const Duration periodoLecturas = Duration(milliseconds: 20);

  final Map<Stick, TiltStick> _tilt = {};
  final Map<Stick, ({double x, double y})> _cero = {};

  static StickRole _rol(Stick s) => s == Stick.grande ? StickRole.adult : StickRole.child;

  bool _simulado(Stick s) => unStick && s == Stick.pequeno;

  TiltStick _ts(Stick s) => _tilt[s] ??= TiltStick(hub.ensureLink(_rol(s)), ejesFijos: ejesEpu);

  /// Ejes de los sticks Epu: el firmware (`AXES` en firmware/epu_stick/main.py) ya
  /// rota el sensor para mandar derecho = +Z, derecha = +X, adelante = +Y. Fijos:
  /// no dependen de cómo estaba el stick al conectarlo ni de ejes guardados.
  static final AxisMap ejesEpu = AxisMap.fromRight(const V3(0, 0, 1), const V3(1, 0, 0))!;

  bool conectado(Stick s) => _simulado(s) || hub.isConnected(_rol(s));

  /// Inclinación actual sin el cero: (derecha +, adelante +).
  ({double x, double y})? _crudo(Stick s) {
    if (_simulado(s)) return (x: 0, y: 0);
    final r = _ts(s).reader;
    if (!hub.isConnected(_rol(s)) || !r.hasTilt) return null;
    return (x: r.tiltX, y: r.tiltY);
  }

  @override
  Future<bool> pedirPermisos() => ensureBlePermissions();

  @override
  Stream<Stick> conectar() {
    final c = StreamController<Stick>();
    var vivo = true;

    Future<void> uno(Stick s) async {
      if (_simulado(s)) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      } else {
        // Uno a la vez: dos escaneos simultáneos se cortan entre sí.
        while (vivo && !hub.isConnected(_rol(s))) {
          final r = await hub.pair(_rol(s));
          if (r != PairOutcome.paired && vivo) await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (!vivo) return;
      _ts(s);
      c.add(s);
    }

    c.onListen = () async {
      await pedirPermisos();
      await uno(Stick.grande);
      await uno(Stick.pequeno);
      if (!vivo) return;
      alConectarLosDos?.call();
      await c.close();
    };
    c.onCancel = () => vivo = false;
    return c.stream;
  }

  @override
  Future<void> calibrar() async {
    final inicio = DateTime.now();
    // Espera a que los dos manden inclinación (como mucho 10 s; si no, cero en 0).
    while (Stick.values.any((s) => _crudo(s) == null) &&
        DateTime.now().difference(inicio) < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // Lo que falte para los 3 s, y en el último tramo se promedia la postura.
    final resto = duracionCalibrar - DateTime.now().difference(inicio) - ventanaCero;
    if (resto > Duration.zero) await Future<void>.delayed(resto);
    final suma = {for (final s in Stick.values) s: (x: 0.0, y: 0.0, n: 0)};
    final fin = DateTime.now().add(ventanaCero);
    while (DateTime.now().isBefore(fin)) {
      for (final s in Stick.values) {
        final v = _crudo(s);
        if (v == null) continue;
        final a = suma[s]!;
        suma[s] = (x: a.x + v.x, y: a.y + v.y, n: a.n + 1);
      }
      await Future<void>.delayed(periodoLecturas);
    }
    for (final s in Stick.values) {
      final a = suma[s]!;
      _cero[s] = a.n == 0 ? (x: 0, y: 0) : (x: a.x / a.n, y: a.y / a.n);
    }
    _registro('cero ${_cero.map((k, v) => MapEntry(k.name, '${v.x.toStringAsFixed(1)}/${v.y.toStringAsFixed(1)}'))}');
  }

  @override
  Future<void> reconectar(Stick stick) async {
    if (_simulado(stick)) return;
    while (!hub.isConnected(_rol(stick))) {
      final r = await hub.pair(_rol(stick));
      if (r != PairOutcome.paired) await Future<void>.delayed(const Duration(seconds: 1));
    }
    _ts(stick);
  }

  /// Vuelco respecto del cero de [calibrar], o null si el stick no manda datos.
  LecturaStick? lectura(Stick s) {
    final v = _crudo(s);
    if (v == null) return null;
    final c = _cero[s] ?? (x: 0.0, y: 0.0);
    return LecturaStick(stick: s, lateral: v.x - c.x, frontal: -(v.y - c.y));
  }

  @override
  Stream<LecturaStick> get lecturas {
    late StreamController<LecturaStick> c;
    Timer? t;
    var n = 0;
    c = StreamController<LecturaStick>.broadcast(
      onListen: () => t = Timer.periodic(periodoLecturas, (_) {
        for (final s in Stick.values) {
          final l = lectura(s);
          if (l != null) c.add(l);
        }
        if (registrar && ++n % 50 == 0) {
          _registro(Stick.values.map((s) {
            final l = lectura(s);
            return l == null ? '${s.name} —' : '${s.name} lat ${l.lateral.toStringAsFixed(1)} fro ${l.frontal.toStringAsFixed(1)}';
          }).join(' · '));
        }
      }),
      onCancel: () => t?.cancel(),
    );
    return c.stream;
  }

  /// Escribe en el registro del teléfono (`adb logcat`) con `--dart-define=EPU_REGISTRO=true`.
  static const bool registrar = bool.fromEnvironment('EPU_REGISTRO');

  static void _registro(String m) {
    // ignore: avoid_print
    if (registrar) print('[EPU] $m');
  }

  /// Ángulo del vuelco (°) desde la vertical, para quien lo necesite (motor).
  static double magnitud(LecturaStick l) =>
      math.sqrt(l.lateral * l.lateral + l.frontal * l.frontal);
}
