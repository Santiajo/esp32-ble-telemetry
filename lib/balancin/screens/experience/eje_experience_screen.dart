import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../platform/audio_engine.dart';
import '../../platform/stick_hub.dart';
import '../../session/board_session.dart';
import '../../session/loss_monitor.dart';
import '../../widgets/eje_light_view.dart';
import '../lost_screen.dart';
import 'memory_screen.dart';

/// Modo Eje para el usuario final (Criterio 10).
///
/// Pantalla completa sin interfaz visual salvo las franjas de luz del eje.
/// El teléfono va inserto en el cuerpo del objeto.
///
/// - Oculta barras del sistema (modo inmersivo).
/// - Administra la sesión y el ciclo del motor a 60 FPS con un Ticker.
/// - Conecta el stick BLE si está disponible; de lo contrario usa modo automático.
/// - Requiere mantener pulsada la esquina de salida durante 2 segundos para terminar.
/// - Al cerrarse la sesión (por fin o inactividad), avanza al recuerdo ([MemoryScreen]).
class EjeExperienceScreen extends StatefulWidget {
  const EjeExperienceScreen({
    super.key,
    required this.audioEngine,
    required this.hub,
  });

  final AudioEngine audioEngine;
  final StickHub hub;

  @override
  State<EjeExperienceScreen> createState() => _EjeExperienceScreenState();
}

class _EjeExperienceScreenState extends State<EjeExperienceScreen>
    with SingleTickerProviderStateMixin {
  late final BoardSession _session;
  late final Ticker _ticker;
  StreamSubscription<LossEvent>? _lossSub;
  bool _navigatedToLost = false;
  bool _navigatedToMemory = false;

  @override
  void initState() {
    super.initState();
    _session = BoardSession(onSound: widget.audioEngine.handle);

    // Fuentes: Stick BLE si está conectado en el hub; si no, simulación automática
    if (widget.hub.isConnected(StickRole.child)) {
      final link = widget.hub.ensureLink(StickRole.child);
      _session.attachReader(StickRole.child, link.reader);
      widget.hub.arm(StickRole.child);
    } else {
      _session.setAutoChild(true);
    }

    if (widget.hub.isConnected(StickRole.adult)) {
      final link = widget.hub.ensureLink(StickRole.adult);
      _session.attachReader(StickRole.adult, link.reader);
      widget.hub.arm(StickRole.adult);
    } else {
      _session.setAutoAdult(true);
    }

    _session.start();
    _session.setEjeMode(true);

    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _ticker = createTicker(_onTick)..start();

    // Monitoreo de desconexiones BLE de sticks armados
    _lossSub = widget.hub.lossEvents.listen((ev) {
      if (ev.lost && _session.isExternal(ev.role) && _session.running) {
        if (!_navigatedToLost && mounted) {
          _navigatedToLost = true;
          _session.loseStick(ev.role, LossCause.alcance);

          // Mostrar barras del sistema durante LostScreen si se requiere
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );

          Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => LostScreen(
                hub: widget.hub,
                role: ev.role,
                session: _session,
                cause: LossCause.alcance,
                audioEngine: widget.audioEngine,
              ),
            ),
          ).then((res) {
            _navigatedToLost = false;
            if (mounted) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            }
            if (res == 'end') {
              _session.end();
            }
          });
        }
      }
    });
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    _session.tick();

    if (_session.closed && !_navigatedToMemory) {
      _navigatedToMemory = true;
      _irAMemory();
      return;
    }

    setState(() {});
  }

  void _irAMemory() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MemoryScreen(
          report: _session.report(),
          audioEngine: widget.audioEngine,
          hub: widget.hub,
          session: _session,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _lossSub?.cancel();

    widget.hub.disarm(StickRole.child);
    widget.hub.disarm(StickRole.adult);
    _session.attachReader(StickRole.child, null);
    _session.attachReader(StickRole.adult, null);

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    WakelockPlus.disable();

    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1D1927),
      body: EjeLightView(
        session: _session,
        onExit: _session.end,
        enableTouchHalves: false,
        exitHoldDuration: const Duration(seconds: 2),
      ),
    );
  }
}
