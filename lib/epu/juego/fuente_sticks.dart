import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext;

import '../datos/niveles.dart';
import 'estado_juego.dart';

/// Los dos sticks.
enum Stick {
  /// Stick grande, lila: lo usa el adulto.
  grande,

  /// Stick pequeño, coral: lo usa el niño.
  pequeno,
}

/// Punto de conexión entre la app y los sticks (Bluetooth).
///
/// El prototipo no tiene Bluetooth: simula los tiempos de cada paso. Las
/// pantallas de este paquete solo hablan con esta clase, así que para la app
/// real basta con escribir una implementación que use el BLE de los sticks
/// (XIAO ESP32-C3 + ICM-42688-P) y asignarla en [EpuSticks.fuente].
///
/// Qué pide cada pantalla:
/// * «Conecta los dos sticks» → [conectar]: un evento por stick cuando queda
///   conectado. La pantalla hace parpadear la luz de cada stick mientras
///   tanto y la deja fija cuando llega su evento (con el tono de conexión).
/// * «Calibren los sticks» → [calibrar]: termina cuando los dos sticks
///   tienen su posición de reposo. La barra del botón dura 3 s fijos, como
///   en el prototipo; si la calibración real tarda más, el botón queda lleno
///   hasta que termine.
/// * «Pérdida de stick» → [reconectar].
/// * Juego → [lecturas]: la lógica del juego convierte el vuelco de cada
///   stick en posiciones de luz y bordes (ver `estado_juego.dart`). Esa
///   lógica no existe en el prototipo (allí todo es simulado con
///   `SimulacionEco`).
///
/// Para avisar que un stick se perdió en medio del juego, la capa de
/// Bluetooth llama a `EpuNavegacion.mostrarPerdida(...)`.
abstract class FuenteSticks {
  /// Empieza a conectar los dos sticks. Emite cada stick cuando queda
  /// conectado y se cierra cuando están los dos.
  Stream<Stick> conectar();

  /// Calibra los dos sticks (cada persona los sostiene derechos y quietos).
  Future<void> calibrar();

  /// Vuelve a conectar un stick perdido.
  Future<void> reconectar(Stick stick);

  /// Lecturas de movimiento de los sticks durante el juego.
  Stream<LecturaStick> get lecturas;

  /// Pide los permisos de Bluetooth («Conceder permisos»). Agregado al integrar
  /// en la app (18-11-2026). Devuelve si se concedieron.
  Future<bool> pedirPermisos();
}

/// Vuelco de un stick, en grados, respecto de su posición calibrada.
class LecturaStick {
  const LecturaStick({required this.stick, required this.lateral, required this.frontal});

  final Stick stick;

  /// Inclinación hacia la izquierda (−) o la derecha (+).
  final double lateral;

  /// Vuelco hacia adelante (−) o hacia atrás (+).
  final double frontal;
}

/// Los tiempos del prototipo, sin Bluetooth.
class FuenteSticksSimulada implements FuenteSticks {
  @override
  Stream<Stick> conectar() async* {
    // Prep4.dc.html: el stick grande a los 1,7 s y el pequeño a los 2,6 s.
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    yield Stick.grande;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    yield Stick.pequeno;
  }

  @override
  Future<void> calibrar() => Future<void>.delayed(const Duration(milliseconds: 3000));

  @override
  Future<void> reconectar(Stick stick) =>
      Future<void>.delayed(const Duration(milliseconds: 2400));

  @override
  Stream<LecturaStick> get lecturas => const Stream.empty();

  @override
  Future<bool> pedirPermisos() async => true;
}

/// Dónde se elige la fuente de los sticks.
class EpuSticks {
  EpuSticks._();

  /// Cambiar por la implementación con Bluetooth en `main()`.
  static FuenteSticks fuente = FuenteSticksSimulada();

  /// Mantener pulsado el logo del Home (integración: abre el banco de pruebas).
  static void Function(BuildContext context)? alMantenerLogo;

  /// Juego con los sticks reales (integración). Si no está o devuelve `null`
  /// para un nivel, la pantalla de juego usa `SimulacionEco`.
  static JuegoEco? Function(NivelEco nivel, EstadoJuegoEco estado, void Function() alTerminar)? crearJuego;
}

/// Lo que mueve la pantalla de juego: la simulación o el juego real.
abstract class JuegoEco {
  void iniciar();
  void detener();
}
