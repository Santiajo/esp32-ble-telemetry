import 'package:flutter/material.dart';

import '../platform/audio_engine.dart';
import '../platform/stick_hub.dart';
import '../session/board_session.dart';
import '../widgets/hold_button.dart';

/// Pantalla de pérdida de conexión de un stick (`#lost` del prototipo).
///
/// Pausa el juego y apaga suavemente el audio mientras se muestra el estado
/// del stick desconectado con un anillo pulsante. Permite reconectar manteniendo
/// presionado 3 s el [HoldButton] o terminar la sesión con 'end'.
class LostScreen extends StatefulWidget {
  const LostScreen({
    super.key,
    required this.hub,
    required this.role,
    this.session,
    this.onResume,
    this.cause = LossCause.alcance,
    this.audioEngine,
  });

  final StickHub hub;
  final StickRole role;

  /// Sesión de v1 que se reanuda; la mecánica v2 pasa [onResume] en su lugar.
  final BoardSession? session;
  final VoidCallback? onResume;
  final LossCause cause;
  final AudioEngine? audioEngine;

  @override
  State<LostScreen> createState() => _LostScreenState();
}

class _LostScreenState extends State<LostScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  final HoldButtonController _holdController = HoldButtonController();

  bool _waitingForReconnect = false;

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_onHubChanged);

    // Animación de anillo pulsante (1.6 s como en CSS .lost .ring)
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeInOut),
    );
  }

  void _resume() {
    widget.onResume?.call();
    widget.session?.resumeAfterLoss();
  }

  void _onHubChanged() {
    if (!mounted) return;
    if (_waitingForReconnect && widget.hub.isConnected(widget.role)) {
      _waitingForReconnect = false;
      _resume();
      Navigator.of(context).pop('resumed');
    }
  }

  void _onHoldDone() {
    if (widget.hub.isConnected(widget.role)) {
      _resume();
      Navigator.of(context).pop('resumed');
    } else {
      setState(() {
        _waitingForReconnect = true;
      });
      _holdController.setStatus(
        HoldButtonStatus.waiting,
        statusText: 'Buscando el stick…',
      );
    }
  }

  @override
  void dispose() {
    widget.hub.removeListener(_onHubChanged);
    _ringController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdult = widget.role == StickRole.adult;
    final isBattery = widget.cause == LossCause.bateria;

    final String title = isAdult
        ? 'Se perdió el stick grande'
        : 'Se perdió el stick pequeño';

    final String causeLabel = isBattery ? 'Batería agotada' : 'Fuera de alcance';

    final String descText = isBattery
        ? 'El juego quedó en pausa y el sonido se apagó suavemente. Conecta el stick a su cargador un momento y mantén pulsado para volver.'
        : 'El juego quedó en pausa y el sonido se apagó suavemente. Acerca el stick al eje y mantén pulsado para reconectarlo.';

    final String tipsText = isBattery
        ? 'Con diez minutos de carga alcanza para una sesión.'
        : 'Si no reconecta: revisa que la luz del stick encienda al moverlo; si no, necesita carga.';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop('end');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEFECE4),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Figura central con stick y anillo pulsante
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 240),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      alignment: Alignment.center,
                      child: _buildStickWithPulsingRing(isAdult),
                    ),
                    const SizedBox(height: 20),

                    // Chip de causa
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4C3B6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFE85E45),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            causeLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2B2536),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Título y descripción
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2B2536),
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      descText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF4A445A),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Botón Mantener 3 s para reconectar
                    HoldButton(
                      label: 'Mantener 3 s para reconectar',
                      doneLabel: 'Stick reconectado',
                      controller: _holdController,
                      onDone: _onHoldDone,
                    ),
                    const SizedBox(height: 14),

                    // Tips
                    Text(
                      tipsText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF5A536B),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Enlace Terminar y ver el recuerdo
                    TextButton(
                      onPressed: () => Navigator.of(context).pop('end'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF5A536B),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Terminar y ver el recuerdo',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickWithPulsingRing(bool isAdult) {
    final stickWidth = isAdult ? 62.0 : 44.0;
    final stickHeight = isAdult ? 180.0 : 130.0;
    final ringWidth = stickWidth + 40.0;
    final ringHeight = stickHeight + 36.0;

    return SizedBox(
      width: ringWidth + 20,
      height: ringHeight + 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anillo pulsante con trazo discontinuo/animado
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Container(
                    width: ringWidth,
                    height: ringHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFFE85E45),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Stick figura (.stick)
          Container(
            width: stickWidth,
            height: stickHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFCFC9D8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: isAdult ? 18 : 14,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB8B2C4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
