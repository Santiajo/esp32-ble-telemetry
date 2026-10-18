import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../controllers/esp_device_controller.dart';
import '../core/ble/imu_frame_parser.dart';
import '../../core/ble/ble_constants.dart';
import '../core/gesture/imu_gesture_reader.dart';
import '../session/board_session.dart';

/// Enlace entre un stick BLE real y el tablero (fase 5).
///
/// Reutiliza el [EspDeviceController] de la estación (conexión, reconexión con
/// backoff, MAC recordada) y le cuelga un [ImuGestureReader] que recibe cada
/// muestra v2 con la hora de llegada en el reloj de la sesión.
///
/// Uso en el tablero:
/// ```dart
/// final link = BleStickLink(role: StickRole.child, clock: () => session.nowMs);
/// await link.start();                              // reconecta a la MAC guardada
/// session.attachReader(StickRole.child, link.reader);
/// ...
/// session.attachReader(StickRole.child, null);     // volver al dedo
/// link.dispose();
/// ```
///
/// La MAC se guarda con la misma clave que la estación ("A"/"B"), así que un
/// stick ya vinculado en el diagnóstico BLE se reconecta solo.
class BleStickLink extends ChangeNotifier {
  BleStickLink({
    required this.role,
    required this.clock,
    ImuTuning? tuning,
    void Function(String mensaje)? onLog,
  }) : reader = ImuGestureReader(tuning: tuning) {
    controller = EspDeviceController(
      etiqueta: role == StickRole.adult ? 'A' : 'B',
      color: role == StickRole.adult ? const Color(0xFFB3A2DC) : const Color(0xFFE85E45),
      nombreEsperado: role == StickRole.adult ? BleConstants.nameStickA : BleConstants.nameStickB,
      onLog: onLog,
    );
    controller.onImuSample = (s) {
      final t = clock();
      reader.addSample(s, t);
      for (final l in List.of(sampleListeners)) {
        l(s, t);
      }
    };
    controller.addListener(notifyListeners);
  }

  final StickRole role;

  /// Reloj de la sesión (ms). Debe ser el mismo que usa el motor.
  final double Function() clock;

  /// Lector de gesto del stick: se conecta con `session.attachReader(role, reader)`.
  final ImuGestureReader reader;

  late final EspDeviceController controller;

  /// Otros consumidores de cada muestra v2 con su hora de llegada (la mecánica v2
  /// cuelga aquí su lector de inclinación y el grabador de trazas).
  final List<void Function(ImuSample sample, double arrivalMs)> sampleListeners = [];

  bool _disposed = false;

  EstadoConexion get estado => controller.estado;
  bool get connected => controller.conectado;
  String? get savedMac => controller.macGuardada;

  /// Nombres de dispositivo aceptados para este rol (para filtrar el escaneo).
  List<String> get acceptedNames =>
      role == StickRole.adult ? BleConstants.namesForA : BleConstants.namesForB;

  /// Reconecta a la MAC guardada, si existe.
  Future<void> start() => controller.inicializarAutoConexion();

  /// Vincula un dispositivo elegido en el escaneo y guarda su MAC.
  Future<void> adopt(BluetoothDevice device) => controller.adoptarDispositivo(device);

  Future<void> disconnect() => controller.desconectar();

  /// Pide volver a calibrar el giroscopio (el stick debe quedar quieto ~0,5 s).
  void recalibrate() {
    reader.resetCalibration();
    notifyListeners();
  }

  /// La conexión está abierta pero no llegan muestras v2 hace más de 1 s.
  bool get silent => connected && clock() - reader.lastArrivalMs > 1000;

  /// Texto de estado para la UI.
  String get statusText {
    if (estado == EstadoConexion.sinVincular) return 'Sin vincular';
    if (estado == EstadoConexion.buscando) return 'Buscando stick…';
    if (reader.lastSample == null) return 'Conectado · esperando datos';
    if (silent) return 'Conectado · sin datos v2 (¿firmware antiguo?)';
    if (!reader.calibrated) return 'Calibrando: deja el stick quieto';
    return 'Conectado · ${reader.sampleRateHz.toStringAsFixed(0)} Hz';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.onImuSample = null;
    sampleListeners.clear();
    controller.removeListener(notifyListeners);
    controller.dispose();
    super.dispose();
  }
}
