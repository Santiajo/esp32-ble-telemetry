import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/ble/ble_constants.dart';
import '../../services/storage_service.dart';
import '../core/app_clock.dart';
import '../session/board_session.dart';
import '../session/loss_monitor.dart';
import 'ble_stick_link.dart';

/// Resultado de una vinculación por "mantener pulsado".
enum PairOutcome {
  /// Encontrado, vinculado (MAC guardada) y conectado.
  paired,

  /// Ningún stick con el nombre del rol apareció en el escaneo.
  notFound,

  /// Se encontró, pero no se logró conectar a tiempo.
  connectFailed,

  /// El Bluetooth del teléfono está apagado.
  bluetoothOff,
}

/// Dueño único de las conexiones a los sticks durante toda la vida de la app.
///
/// Se crea una vez (en HomeScreen, junto al AudioEngine) y se comparte con el
/// onboarding, el tablero y la pantalla de pérdida, para que una conexión
/// abierta en el onboarding siga viva durante el juego.
///
/// - [link] / [ensureLink]: el [BleStickLink] de cada rol (uno por rol).
/// - [pair]: escanea por el nombre del rol (`ESP32-BAL-A/B`), vincula y conecta.
/// - [arm] / [disarm] + [lossEvents]: avisa cuando un stick EN USO se desconecta
///   y cuando vuelve (pantalla de pérdida).
///
/// Los permisos BLE y el encendido del adaptador se piden desde la UI (necesitan
/// un BuildContext); [pair] solo verifica que el adaptador esté encendido.
class StickHub extends ChangeNotifier {
  StickHub({double Function()? clock}) : clock = clock ?? AppClock.nowMs;

  final double Function() clock;
  final Map<StickRole, BleStickLink> _links = {};
  final LossMonitor _loss = LossMonitor();
  final StreamController<LossEvent> _lossEvents = StreamController<LossEvent>.broadcast();
  final Set<StickRole> _pairing = {};
  bool _disposed = false;

  /// Pérdidas y recuperaciones de sticks armados.
  Stream<LossEvent> get lossEvents => _lossEvents.stream;

  BleStickLink? link(StickRole role) => _links[role];
  bool isConnected(StickRole role) => _links[role]?.connected ?? false;
  bool isLost(StickRole role) => _loss.isLost(role);
  bool isPairing(StickRole role) => _pairing.contains(role);

  /// Nombres BLE aceptados para el rol.
  static List<String> namesFor(StickRole role) =>
      role == StickRole.adult ? BleConstants.namesForA : BleConstants.namesForB;

  /// Clave de almacenamiento de la MAC (la misma que usa la estación BLE).
  static String keyFor(StickRole role) => role == StickRole.adult ? 'A' : 'B';

  /// ¿Hay un stick vinculado (MAC guardada) para el rol?
  Future<bool> hasSavedStick(StickRole role) async {
    final mac = await StorageService.obtenerMac(keyFor(role));
    return mac != null && mac.isNotEmpty;
  }

  BleStickLink _create(StickRole role) {
    final l = BleStickLink(role: role, clock: clock);
    l.addListener(() => _onLinkChanged(role));
    _links[role] = l;
    return l;
  }

  void _onLinkChanged(StickRole role) {
    final l = _links[role];
    if (l == null) return;
    final ev = _loss.update(role, connected: l.connected);
    if (ev != null && !_lossEvents.isClosed) _lossEvents.add(ev);
    if (!_disposed) notifyListeners();
  }

  /// Devuelve el enlace del rol, creándolo si hace falta. Si hay una MAC
  /// guardada, inicia la reconexión automática en segundo plano (no espera a
  /// que conecte: la conexión puede tardar o no llegar nunca si el stick está apagado).
  BleStickLink ensureLink(StickRole role) {
    final existing = _links[role];
    if (existing != null) return existing;
    final l = _create(role);
    unawaited(l.start());
    notifyListeners();
    return l;
  }

  /// Crea los enlaces de los roles que ya tienen un stick vinculado
  /// (reconexión automática al abrir la app).
  Future<void> reconnectSaved() async {
    for (final role in StickRole.values) {
      if (await hasSavedStick(role)) ensureLink(role);
    }
  }

  /// Vinculación del onboarding ("mantener pulsado").
  ///
  /// 1. Si el stick del rol ya está conectado → [PairOutcome.paired] sin escanear.
  /// 2. Si hay una MAC guardada, primero espera hasta [knownTimeout] a que la
  ///    reconexión automática lo conecte: un ESP32 conectado deja de anunciarse,
  ///    así que escanear en paralelo compite con esa reconexión y además gasta
  ///    el cupo de Android (~5 escaneos cada 30 s; si se supera, el escaneo
  ///    devuelve vacío en silencio hasta reiniciar el Bluetooth).
  /// 3. Si no conectó (stick nuevo o cambiado), escanea por el nombre del rol
  ///    durante [scanTimeout], guarda la MAC del primero que aparezca y espera
  ///    hasta [connectTimeout] a que conecte. Si la reconexión automática gana
  ///    la carrera durante el escaneo, también cuenta como vinculado.
  Future<PairOutcome> pair(
    StickRole role, {
    Duration knownTimeout = const Duration(seconds: 6),
    Duration scanTimeout = const Duration(seconds: 12),
    Duration connectTimeout = const Duration(seconds: 15),
  }) async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      return PairOutcome.bluetoothOff;
    }
    if (isConnected(role)) return PairOutcome.paired;
    if (_pairing.contains(role)) {
      // Ya hay una vinculación en curso para este rol: se espera su resultado.
      final deadline = clock() + (knownTimeout + scanTimeout + connectTimeout).inMilliseconds;
      while (_pairing.contains(role) && clock() < deadline && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return isConnected(role) ? PairOutcome.paired : PairOutcome.notFound;
    }
    _pairing.add(role);
    notifyListeners();
    try {
      // 2) Stick conocido: dar tiempo a la reconexión automática.
      if (await hasSavedStick(role)) {
        ensureLink(role);
        if (await _waitConnected(role, knownTimeout)) return PairOutcome.paired;
      }

      // 3) Escaneo por nombre.
      final names = namesFor(role);
      BluetoothDevice? found;
      final sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          if (names.contains(name)) {
            found ??= r.device;
          }
        }
      });
      try {
        if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
        await FlutterBluePlus.startScan(withNames: names, timeout: scanTimeout);
        final deadline = clock() + scanTimeout.inMilliseconds;
        while (found == null &&
            !isConnected(role) &&
            clock() < deadline &&
            FlutterBluePlus.isScanningNow &&
            !_disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } finally {
        await sub.cancel();
        if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      }

      if (isConnected(role)) return PairOutcome.paired;
      final device = found;
      if (device == null) return PairOutcome.notFound;

      final l = _links[role] ?? _create(role);
      // adopt() guarda la MAC y entra al bucle de conexión (que puede no
      // terminar nunca): no se espera, se observa el estado.
      unawaited(l.adopt(device));
      return await _waitConnected(role, connectTimeout)
          ? PairOutcome.paired
          : PairOutcome.connectFailed;
    } finally {
      _pairing.remove(role);
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> _waitConnected(StickRole role, Duration timeout) async {
    final deadline = clock() + timeout.inMilliseconds;
    while (!isConnected(role) && clock() < deadline && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return isConnected(role);
  }

  /// La sesión empieza a depender del stick de [role]: su desconexión dispara
  /// una pérdida en [lossEvents].
  void arm(StickRole role) {
    _loss.arm(role);
    _loss.update(role, connected: isConnected(role));
  }

  /// La sesión deja de depender del stick de [role].
  void disarm(StickRole role) {
    _loss.disarm(role);
    notifyListeners();
  }

  /// Cierra la conexión del rol y olvida su enlace (la MAC queda guardada).
  void release(StickRole role) {
    _loss.disarm(role);
    final l = _links.remove(role);
    l?.dispose();
    if (!_disposed) notifyListeners();
  }

  /// Cierra todas las conexiones (p. ej. antes de abrir el Diagnóstico BLE,
  /// que usa sus propios controladores sobre las mismas placas).
  void releaseAll() {
    for (final role in _links.keys.toList()) {
      release(role);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    releaseAll();
    _disposed = true;
    _lossEvents.close();
    super.dispose();
  }
}
