import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../session/board_session.dart';

/// Vista de la luz del modo eje (#ejeView del prototipo web).
///
/// Modela lo que el usuario u observador ve en el eje:
/// - Franjas de luz superior e inferior moduladas por [EjeGlow] (registro y nivel).
/// - Destellos radiales efímeros producidos por notas [EjeFlash].
/// - Dos mitades de pantalla para captura de gestos táctiles (activas solo si [enableTouchHalves] es true).
/// - Botón o esquina discreta de salida: si [exitHoldDuration] no es nulo, requiere
///   mantener presionado durante ese lapso para evitar salidas accidentales.
class EjeLightView extends StatefulWidget {
  const EjeLightView({
    super.key,
    required this.session,
    required this.onExit,
    this.enableTouchHalves = true,
    this.exitHoldDuration,
  });

  final BoardSession session;
  final VoidCallback onExit;
  final bool enableTouchHalves;

  /// Duración requerida de pulsación sostenida para salir. Si es null, un toque simple basta.
  final Duration? exitHoldDuration;

  @override
  State<EjeLightView> createState() => _EjeLightViewState();
}

class _EjeLightViewState extends State<EjeLightView> {
  int? _leftPointer;
  int? _rightPointer;

  // Estado para la salida sostenida (exitHoldDuration)
  Timer? _holdTimer;
  Timer? _progressTimer;
  double _holdProgress = 0.0;
  DateTime? _holdStartTime;

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    if (_holdProgress != 0.0) {
      setState(() {
        _holdProgress = 0.0;
      });
    }
  }

  void _onExitPointerDown(PointerDownEvent event) {
    final dur = widget.exitHoldDuration;
    if (dur == null) {
      widget.onExit();
      return;
    }

    _cancelHold();
    _holdStartTime = DateTime.now();
    _holdProgress = 0.0;

    _holdTimer = Timer(dur, () {
      _cancelHold();
      widget.onExit();
    });

    final totalMs = dur.inMilliseconds.toDouble();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _holdStartTime == null) return;
      final elapsed = DateTime.now().difference(_holdStartTime!).inMilliseconds;
      setState(() {
        _holdProgress = (elapsed / totalMs).clamp(0.0, 1.0);
      });
    });
    setState(() {});
  }

  void _onExitPointerUp(PointerUpEvent event) {
    if (widget.exitHoldDuration != null) {
      _cancelHold();
    }
  }

  void _onExitPointerCancel(PointerCancelEvent event) {
    if (widget.exitHoldDuration != null) {
      _cancelHold();
    }
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.session.ejeGlow;
    final nowMs = widget.session.nowMs;
    final glowColor = glow.hidden ? const Color(0xFFF2E44A) : const Color(0xFF7B5FCB);

    final leftRole = widget.session.sides[PanelSide.left]!;
    final rightRole = widget.session.sides[PanelSide.right]!;
    final leftIsExternal = widget.session.isExternal(leftRole);
    final rightIsExternal = widget.session.isExternal(rightRole);

    return Scaffold(
      backgroundColor: const Color(0xFF1D1927),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Franja superior
          final topH = h * 0.40 * glow.topScale.clamp(0.0, 1.5);
          // Franja inferior
          final bottomH = h * 0.40 * glow.bottomScale.clamp(0.0, 1.5);

          return Stack(
            children: [
              // Franja de luz superior
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: math.max(0, topH),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0)),
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0) * 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Franja de luz inferior
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: math.max(0, bottomH),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0)),
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0) * 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Destellos de notas (EjeFlashes)
              for (final flash in widget.session.ejeFlashes) ...[
                _buildEjeFlash(flash, nowMs, w, h),
              ],

              // Dos mitades transparentes para captura de toques (solo si enableTouchHalves)
              if (widget.enableTouchHalves)
                Row(
                  children: [
                    Expanded(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) {
                          if (leftIsExternal) return;
                          if (_leftPointer == null) {
                            _leftPointer = e.pointer;
                            widget.session.setPanelSize(PanelSide.left, w / 2, h);
                            widget.session.feedPanel(
                              PanelSide.left,
                              e.localPosition.dx,
                              e.localPosition.dy,
                            );
                          }
                        },
                        onPointerMove: (e) {
                          if (leftIsExternal) return;
                          if (e.pointer == _leftPointer) {
                            widget.session.feedPanel(
                              PanelSide.left,
                              e.localPosition.dx,
                              e.localPosition.dy,
                            );
                          }
                        },
                        onPointerUp: (e) {
                          if (e.pointer == _leftPointer) _leftPointer = null;
                        },
                        onPointerCancel: (e) {
                          if (e.pointer == _leftPointer) _leftPointer = null;
                        },
                      ),
                    ),
                    Expanded(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) {
                          if (rightIsExternal) return;
                          if (_rightPointer == null) {
                            _rightPointer = e.pointer;
                            widget.session.setPanelSize(PanelSide.right, w / 2, h);
                            widget.session.feedPanel(
                              PanelSide.right,
                              e.localPosition.dx,
                              e.localPosition.dy,
                            );
                          }
                        },
                        onPointerMove: (e) {
                          if (rightIsExternal) return;
                          if (e.pointer == _rightPointer) {
                            widget.session.feedPanel(
                              PanelSide.right,
                              e.localPosition.dx,
                              e.localPosition.dy,
                            );
                          }
                        },
                        onPointerUp: (e) {
                          if (e.pointer == _rightPointer) _rightPointer = null;
                        },
                        onPointerCancel: (e) {
                          if (e.pointer == _rightPointer) _rightPointer = null;
                        },
                      ),
                    ),
                  ],
                ),

              // Botón o esquina de salida
              _buildExitWidget(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExitWidget() {
    final hold = widget.exitHoldDuration != null;

    if (!hold) {
      return Positioned(
        top: 40,
        right: 20,
        child: TextButton.icon(
          onPressed: widget.onExit,
          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
          label: const Text(
            'Salir',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
    }

    // Salida discreta por pulsación sostenida (2 s en la esquina)
    return Positioned(
      top: 24,
      right: 20,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onExitPointerDown,
        onPointerUp: _onExitPointerUp,
        onPointerCancel: _onExitPointerCancel,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _holdProgress > 0 ? 0.22 : 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: _holdProgress > 0 ? 0.35 : 0.12),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_holdProgress > 0)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: _holdProgress,
                    strokeWidth: 3.5,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF2E44A)),
                    backgroundColor: Colors.white12,
                  ),
                ),
              Icon(
                Icons.close,
                color: Colors.white.withValues(alpha: _holdProgress > 0 ? 0.9 : 0.4),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEjeFlash(EjeFlash flash, double nowMs, double w, double h) {
    final age = (nowMs - flash.bornMs) / BoardSession.ejeFlashMs;
    if (age < 0 || age > 1.0) return const SizedBox.shrink();

    final opacity = (1.0 - age).clamp(0.0, 1.0);
    final size = math.min(w, h) * (0.25 + 0.45 * age);
    final color = flash.hidden ? const Color(0xFFF2E44A) : const Color(0xFFE85E45);

    return Positioned(
      left: flash.x * w - size / 2,
      top: flash.y * h - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: opacity * 0.45),
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 0.72],
            ),
          ),
        ),
      ),
    );
  }
}
