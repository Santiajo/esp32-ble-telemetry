import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../balancin/platform/stick_hub.dart';
import '../../balancin/session/board_session.dart' show StickRole;
import '../app_v2.dart';
import '../platform/ble_permissions.dart';
import '../widgets/v2_ui.dart';

/// El stick está conectado y mandando datos (conectado sin datos no sirve para jugar).
bool stickReady(StickHub hub, StickRole role) {
  final l = hub.link(role);
  return l != null && l.connected && l.reader.lastSample != null && !l.silent;
}

/// Lleva a [page] con los dos sticks listos; si falta alguno, pasa antes por
/// [SticksGateScreen].
Future<void> openWithSticks(BuildContext context, V2Services s, Widget Function() page) {
  final ready = StickRole.values.every((r) => stickReady(s.hub, r));
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ready ? page() : SticksGateScreen(s: s, next: page),
  ));
}

/// «Conecten los sticks»: no deja seguir hasta que los dos estén conectados y
/// mandando datos.
class SticksGateScreen extends StatefulWidget {
  const SticksGateScreen({super.key, required this.s, required this.next, this.isReady});

  final V2Services s;

  /// Reemplaza a [stickReady] en las pruebas.
  final bool Function(StickRole role)? isReady;

  /// A dónde seguir con los dos sticks listos.
  final Widget Function() next;

  @override
  State<SticksGateScreen> createState() => _SticksGateScreenState();
}

class _SticksGateScreenState extends State<SticksGateScreen> {
  StickHub get _hub => widget.s.hub;
  Timer? _refresh;
  final Map<StickRole, String> _error = {};
  final Set<StickRole> _busy = {};
  final Map<StickRole, int> _slowTicks = {};
  final Set<StickRole> _retried = {};

  bool _ready(StickRole r) => widget.isReady?.call(r) ?? stickReady(_hub, r);

  @override
  void initState() {
    super.initState();
    _hub.addListener(_changed);
    // Los datos no avisan por el hub: se revisan seguido.
    _refresh = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
    unawaited(_reconnect());
  }

  /// Reconecta los sticks ya vinculados, si hay permiso (lo pide el botón «Conectar»).
  Future<void> _reconnect() async {
    try {
      if (!Platform.isAndroid || await Permission.bluetoothConnect.isGranted) await _hub.reconnectSaved();
    } catch (_) {}
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Una conexión lenta llega tarde a todo: se reconecta sola, una vez por stick.
  void _tick() {
    for (final r in StickRole.values) {
      final l = _hub.link(r);
      final slow = l?.slow ?? false;
      _slowTicks[r] = slow ? (_slowTicks[r] ?? 0) + 1 : 0;
      if (l != null && _slowTicks[r]! >= 8 && _retried.add(r)) unawaited(l.controller.reconectar());
    }
    _changed();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _hub.removeListener(_changed);
    super.dispose();
  }

  Future<bool> _bluetoothOn() async {
    if (!await ensureBlePermissions()) return false;
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return true;
    try {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .firstWhere((st) => st == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _connect(StickRole role) async {
    setState(() {
      _busy.add(role);
      _error.remove(role);
    });
    String? error;
    if (await _bluetoothOn()) {
      error = switch (await _hub.pair(role)) {
        PairOutcome.paired => null,
        PairOutcome.notFound =>
          'No apareció. Enciéndelo, acércalo y cierra Balancín en otros teléfonos: el stick se conecta a uno solo. '
              'En teléfonos antiguos, enciende también la ubicación.',
        PairOutcome.connectFailed => 'Apareció, pero no conectó. Apágalo, enciéndelo y prueba otra vez.',
        PairOutcome.bluetoothOff => 'Enciende el Bluetooth del teléfono.',
      };
    } else {
      error = 'Hacen falta el Bluetooth encendido y sus permisos.';
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(role);
      if (error != null) _error[role] = error;
    });
  }

  String _status(StickRole r) {
    if (_hub.link(r)?.slow ?? false) return 'Conexión lenta. Acércalo al teléfono.';
    if (_ready(r)) return 'Listo';
    if (_busy.contains(r) || _hub.isPairing(r)) return 'Buscando…';
    final e = _error[r];
    if (e != null) return e;
    final l = _hub.link(r);
    if (l == null) return 'Sin conectar';
    return l.connected ? 'Conectado, sin datos. Apágalo y enciéndelo.' : 'Buscando… enciéndelo y acércalo al teléfono.';
  }

  void _continue() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => widget.next()));
  }

  @override
  Widget build(BuildContext context) {
    final all = StickRole.values.every(_ready);
    return Theme(
      data: V2.theme,
      child: Scaffold(
        appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Conecten los sticks', textAlign: TextAlign.center, style: V2.h1()),
              const SizedBox(height: 6),
              const Text('Para jugar hacen falta los dos, encendidos y cerca del teléfono.', textAlign: TextAlign.center, style: V2.sub),
              const SizedBox(height: 18),
              _row(StickRole.adult, 'Stick grande · adulto', V2.lilaInk),
              const SizedBox(height: 10),
              _row(StickRole.child, 'Stick pequeño · niño', V2.coral),
              const Spacer(),
              V2.primary(all ? 'Continuar' : 'Esperando los sticks', all ? _continue : null),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(StickRole role, String name, Color color) {
    final ready = _ready(role);
    final busy = _busy.contains(role) || _hub.isPairing(role);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: V2.ink)),
            const SizedBox(height: 2),
            Text(_status(role), style: V2.small),
          ]),
        ),
        const SizedBox(width: 8),
        if (ready)
          const Icon(Icons.check_circle, color: V2.olive)
        else
          SizedBox(
            width: 104,
            child: V2.secondary('Conectar', busy ? null : () => unawaited(_connect(role)), height: 42),
          ),
      ]),
    );
  }
}
