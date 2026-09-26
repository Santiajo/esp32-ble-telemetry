import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esp32_ble_telemetry/core/ble/ble_constants.dart';
import 'package:esp32_ble_telemetry/core/physics/physics_engine.dart';
import 'package:esp32_ble_telemetry/services/storage_service.dart';

enum EstadoConexion {
  sinVincular,
  buscando,
  conectado,
}

/// Controlador independiente para una placa ESP32 (A o B).
///
/// Gestiona la conexión BLE, reconexión activa resiliente con backoff exponencial,
/// el stream de datos con buffer UTF-8, el motor de física y los buffers de telemetría.
class EspDeviceController extends ChangeNotifier {
  final String etiqueta; // "A" o "B"
  final Color color; // Turquesa para A, Naranja para B
  final String nombreEsperado;

  EstadoConexion _estado = EstadoConexion.sinVincular;
  EstadoConexion get estado => _estado;
  bool get conectado => _estado == EstadoConexion.conectado;

  BluetoothDevice? _dispositivo;
  BluetoothDevice? get dispositivo => _dispositivo;

  final PhysicsEngine fisica = PhysicsEngine();

  // Posición visual suavizada para renderizado a 60 FPS
  double visualX = 0.0;
  double visualY = 0.0;
  static const double suavizadoVisual = 0.18;

  int ultimoRawX = 0;
  int ultimoRawY = 0;
  String ultimaLineaRaw = '';

  // Buffers circulares para osciloscopio (180 muestras de histórico)
  static const int maxMuestras = 180;
  final List<double> bufferVelocidad = List.filled(maxMuestras, 0.0, growable: true);
  final List<double> bufferAceleracion = List.filled(maxMuestras, 0.0, growable: true);
  final List<double> bufferEnergia = List.filled(maxMuestras, 0.0, growable: true);

  bool _desconexionManual = false;
  bool _enBucleReconexion = false;
  String? _macGuardada;
  String? get macGuardada => _macGuardada;

  StreamSubscription<BluetoothConnectionState>? _subConexion;
  StreamSubscription<List<int>>? _subNotificaciones;
  String _bufferStream = '';

  // Callback opcional para escribir líneas en la consola telemétrica
  void Function(String mensaje)? onLog;

  EspDeviceController({
    required this.etiqueta,
    required this.color,
    required this.nombreEsperado,
    this.onLog,
  });

  /// Inicializa cargando la dirección MAC previa e inicia auto-reconexión si existe.
  Future<void> inicializarAutoConexion() async {
    _macGuardada = await StorageService.obtenerMac(etiqueta);
    if (_macGuardada != null && _macGuardada!.isNotEmpty) {
      _log('MAC recordada: $_macGuardada. Conectando automáticamente...');
      _dispositivo = BluetoothDevice.fromId(_macGuardada!);
      await conectarPersistente();
    } else {
      _log('Sin vincular. Toca el indicador para emparejar la placa $etiqueta.');
    }
  }

  /// Vincula un nuevo dispositivo seleccionado y guarda su MAC.
  Future<void> adoptarDispositivo(BluetoothDevice dev) async {
    _dispositivo = dev;
    _macGuardada = dev.remoteId.str;
    await StorageService.guardarMac(etiqueta, _macGuardada!);
    _log('Dispositivo vinculado: ${dev.platformName.isNotEmpty ? dev.platformName : _macGuardada}');
    await conectarPersistente();
  }

  /// Bucle de conexión persistente con retroceso exponencial (2s a 10s).
  Future<bool> conectarPersistente() async {
    if (_enBucleReconexion || _dispositivo == null) return false;
    _enBucleReconexion = true;
    _desconexionManual = false;
    _actualizarEstado(EstadoConexion.buscando);

    double esperaSegundos = 2.0;
    bool primerCiclo = true;

    while (!_desconexionManual) {
      final bool exito = await _intentarConexionGatt();
      if (exito) {
        _enBucleReconexion = false;
        return true;
      }

      if (primerCiclo) {
        _log('ESP $etiqueta no responde aún. Reintentando en segundo plano...');
        primerCiclo = false;
      }

      await Future.delayed(Duration(milliseconds: (esperaSegundos * 1000).toInt()));
      if (_desconexionManual) break;

      esperaSegundos = math.min(esperaSegundos * 1.5, 10.0);
    }

    _enBucleReconexion = false;
    return false;
  }

  /// Intento atómico de conexión GATT, descubrimiento de servicios NUS y subscripción a TX.
  Future<bool> _intentarConexionGatt() async {
    if (_dispositivo == null || _desconexionManual) return false;

    try {
      // Timeout acotado para liberar la ranura GATT rápidamente si el ESP está apagado
      await _dispositivo!.connect(
        license: License.nonprofit,
        timeout: const Duration(milliseconds: 3500),
        autoConnect: false,
      );

      // Suscribirse a cambios en el estado de conexión
      await _subConexion?.cancel();
      _subConexion = _dispositivo!.connectionState.listen((connectionState) {
        if (connectionState == BluetoothConnectionState.disconnected) {
          _manejarDesconexionInvoluntaria();
        }
      });

      // Descubrir servicios GATT
      final services = await _dispositivo!.discoverServices();
      BluetoothCharacteristic? charTx;

      for (final service in services) {
        if (service.uuid == BleConstants.serviceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid == BleConstants.txCharUuid) {
              charTx = char;
              break;
            }
          }
        }
      }

      if (charTx == null) {
        _log('Error: Servicio NUS o Característica TX no encontrada en ESP $etiqueta.');
        await _dispositivo!.disconnect();
        return false;
      }

      // Habilitar notificaciones en TX
      await charTx.setNotifyValue(true);
      await _subNotificaciones?.cancel();
      _subNotificaciones = charTx.onValueReceived.listen(_procesarChunkBytes);

      _bufferStream = '';
      _actualizarEstado(EstadoConexion.conectado);
      _log('¡Conexión establecida con ESP $etiqueta!');
      return true;
    } catch (_) {
      try {
        await _dispositivo?.disconnect();
      } catch (_) {}
      return false;
    }
  }

  void _manejarDesconexionInvoluntaria() {
    _actualizarEstado(EstadoConexion.buscando);
    if (_desconexionManual) return;
    _log('Conexión perdida con ESP $etiqueta. Reconectando automáticamente...');
    conectarPersistente();
  }

  /// Desconexión manual iniciada por el usuario al tocar el chip.
  Future<void> desconectar() async {
    _desconexionManual = true;
    _enBucleReconexion = false;
    await _subNotificaciones?.cancel();
    _subNotificaciones = null;
    await _subConexion?.cancel();
    _subConexion = null;

    try {
      await _dispositivo?.disconnect();
    } catch (_) {}

    _actualizarEstado(
      _macGuardada != null ? EstadoConexion.sinVincular : EstadoConexion.sinVincular,
    );
    _log('Desconectado de ESP $etiqueta manualmente.');
  }

  /// Procesa fragmentos de bytes BLE recibidos por notificación UART.
  void _procesarChunkBytes(List<int> bytes) {
    if (bytes.isEmpty) return;

    final String texto = utf8.decode(bytes, allowMalformed: true);
    _bufferStream += texto;

    if (_bufferStream.length > 2048) {
      _bufferStream = _bufferStream.substring(_bufferStream.length - 256);
    }

    int salto;
    while ((salto = _bufferStream.indexOf('\n')) != -1) {
      final String linea = _bufferStream.substring(0, salto).trim();
      _bufferStream = _bufferStream.substring(salto + 1);

      if (linea.isEmpty) continue;

      final partes = linea.split(',');
      if (partes.length >= 2) {
        final int? rx = int.tryParse(partes[0].trim());
        final int? ry = int.tryParse(partes[1].trim());

        if (rx != null && ry != null) {
          ultimoRawX = rx;
          ultimoRawY = ry;
          ultimaLineaRaw = linea;

          // Procesar física en memoria sin disparar setState/repintado
          fisica.procesarLectura(rx, ry);
          _log('[$etiqueta] $linea');
        }
      }
    }
  }

  /// Calibra el centro estático con las lecturas actuales.
  void calibrarCentro() {
    fisica.calibrar(ultimoRawX, ultimoRawY);
    _log('[$etiqueta] Centro recalibrado y tara aplicada.');
  }

  /// Restablece velocidad y posición a (0, 0).
  void reiniciarPosicion() {
    fisica.resetPosicion();
    visualX = 0.0;
    visualY = 0.0;
    _log('[$etiqueta] Posición reiniciada a (0, 0).');
  }

  /// Avanza la interpolación visual suave (invocado por el Ticker vsync a 60 FPS).
  void tickInterpolacion() {
    visualX += (fisica.posX - visualX) * suavizadoVisual;
    visualY += (fisica.posY - visualY) * suavizadoVisual;

    if ((fisica.posX - visualX).abs() < 0.05) visualX = fisica.posX;
    if ((fisica.posY - visualY).abs() < 0.05) visualY = fisica.posY;

    // Calcular métricas actuales
    final double velTotal = math.sqrt(fisica.velX * fisica.velX + fisica.velY * fisica.velY);
    final double accMag = math.sqrt(fisica.accX * fisica.accX + fisica.accY * fisica.accY);
    final double energia = velTotal * velTotal * 2.0;

    // Agregar al buffer del osciloscopio
    bufferVelocidad.removeAt(0);
    bufferVelocidad.add(velTotal);

    bufferAceleracion.removeAt(0);
    bufferAceleracion.add(accMag);

    bufferEnergia.removeAt(0);
    bufferEnergia.add(energia);
  }

  void _actualizarEstado(EstadoConexion nuevo) {
    if (_estado != nuevo) {
      _estado = nuevo;
      notifyListeners();
    }
  }

  void _log(String mensaje) {
    onLog?.call(mensaje);
  }

  @override
  void dispose() {
    _desconexionManual = true;
    _subNotificaciones?.cancel();
    _subConexion?.cancel();
    _dispositivo?.disconnect();
    super.dispose();
  }
}
