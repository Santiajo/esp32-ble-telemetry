import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Estado de un [HoldButton].
enum HoldButtonStatus {
  idle,
  holding,
  waiting,
  done,
  error,
}

/// Controlador opcional para manipular el estado de un [HoldButton].
class HoldButtonController extends ChangeNotifier {
  HoldButtonStatus? _status;
  String? _statusText;

  HoldButtonStatus? get status => _status;
  String? get statusText => _statusText;

  void setStatus(HoldButtonStatus status, {String? statusText}) {
    _status = status;
    _statusText = statusText;
    notifyListeners();
  }

  void reset() {
    _status = HoldButtonStatus.idle;
    _statusText = null;
    notifyListeners();
  }
}

/// Botón "Mantener pulsado 3 s" con barra de progreso y LED parpadeante,
/// equivalente a la función `hold()` del prototipo web (#prep, #lost).
///
/// Si se suelta antes de 3 s, la barra vuelve a 0 y el LED se apaga.
/// Al completarse, pasa a estado `done` (LED encendido fijo, barra verde,
/// y texto [doneLabel]).
///
/// Utiliza [Listener] (`onPointerDown`, `onPointerUp`, `onPointerCancel`) para
/// garantizar un control de interacción de puntero de bajo nivel.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.doneLabel,
    this.onPressStart,
    this.onDone,
    this.onCancel,
    this.status,
    this.statusText,
    this.controller,
    this.onLedChange,
    this.holdDuration = const Duration(milliseconds: 3000),
    this.minHeight = 58.0,
  });

  /// Texto normal del botón (ej. "Mantener · stick grande").
  final String label;

  /// Texto al completar la pulsación (ej. "Stick grande vinculado").
  final String doneLabel;

  /// Llamado inmediatamente cuando el puntero toca el botón.
  final VoidCallback? onPressStart;

  /// Llamado cuando se completan los 3 s de mantenimiento.
  final VoidCallback? onDone;

  /// Llamado cuando se suelta el botón antes de completarlo.
  final VoidCallback? onCancel;

  /// Estado externo opcional que sobrescribe el estado interno.
  final HoldButtonStatus? status;

  /// Texto secundario o descriptivo (ej. mensajes de error o espera).
  final String? statusText;

  /// Controlador externo opcional.
  final HoldButtonController? controller;

  /// Notifica cambios en el LED para sincronizar elementos visuales externos (ej. sticks).
  final ValueChanged<bool>? onLedChange;

  /// Duración requerida de pulsación sostenida. Por defecto 3 s.
  final Duration holdDuration;

  /// Altura mínima del botón.
  final double minHeight;

  @override
  State<HoldButton> createState() => HoldButtonState();
}

class HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  bool _ledOn = false;
  bool _isHolding = false;
  DateTime? _lastTick;
  int _elapsedMs = 0;
  Timer? _progressTimer;
  Timer? _blinkTimer;

  HoldButtonStatus _internalStatus = HoldButtonStatus.idle;

  HoldButtonStatus get currentStatus {
    if (widget.controller?.status != null) {
      return widget.controller!.status!;
    }
    if (widget.status != null) {
      return widget.status!;
    }
    return _internalStatus;
  }

  String? get currentStatusText {
    return widget.controller?.statusText ?? widget.statusText;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _syncStatus();
  }

  @override
  void didUpdateWidget(covariant HoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
    _syncStatus();
  }

  void _onControllerChanged() {
    if (mounted) setState(() => _syncStatus());
  }

  void _syncStatus() {
    final s = currentStatus;
    if (s == HoldButtonStatus.done) {
      _progress = 1.0;
      _setLed(true);
    } else if (s == HoldButtonStatus.idle) {
      if (!_isHolding) {
        _progress = 0.0;
        _setLed(false);
      }
    } else if (s == HoldButtonStatus.error) {
      _cancelTimers();
      _isHolding = false;
      _progress = 0.0;
      _setLed(false);
    }
  }

  void reset() {
    _cancelTimers();
    _isHolding = false;
    _progress = 0.0;
    _setLed(false);
    _internalStatus = HoldButtonStatus.idle;
    widget.controller?.reset();
    if (mounted) setState(() {});
  }

  void _setLed(bool on) {
    if (_ledOn == on) return;
    _ledOn = on;
    final cb = widget.onLedChange;
    if (cb == null) return;
    // _setLed también se llama desde initState/didUpdateWidget (durante el build
    // del padre). Avisar al padre en ese momento dispara "setState() called during
    // build": en esa fase se difiere el aviso al final del frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(_ledOn);
      });
    } else {
      cb(on);
    }
  }

  void _cancelTimers() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _blinkTimer?.cancel();
    _blinkTimer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    final status = currentStatus;
    if (status == HoldButtonStatus.done || status == HoldButtonStatus.waiting) {
      return;
    }

    if (status == HoldButtonStatus.error) {
      reset();
    }

    _isHolding = true;
    _lastTick = DateTime.now();
    _elapsedMs = 0;
    _internalStatus = HoldButtonStatus.holding;
    _progress = 0.0;
    _setLed(false);

    widget.onPressStart?.call();

    // Timer de parpadeo de LED a 125 ms (como en el prototipo)
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 125), (_) {
      if (mounted && _isHolding) {
        setState(() {
          _setLed(!_ledOn);
        });
      }
    });

    // Timer de actualización de la barra de progreso a ~60 FPS
    final totalMs = widget.holdDuration.inMilliseconds.toDouble();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_isHolding) return;
      final now = DateTime.now();
      final realDt = _lastTick != null ? now.difference(_lastTick!).inMilliseconds : 16;
      _lastTick = now;
      final dt = realDt > 0 ? realDt : 16;
      _elapsedMs += dt;

      final p = (_elapsedMs / totalMs).clamp(0.0, 1.0);
      setState(() {
        _progress = p;
      });

      if (p >= 1.0) {
        _onCompleted();
      }
    });

    setState(() {});
  }

  void _onCompleted() {
    _cancelTimers();
    _isHolding = false;
    _progress = 1.0;
    _setLed(true);
    _internalStatus = HoldButtonStatus.done;
    widget.controller?.setStatus(HoldButtonStatus.done);
    widget.onDone?.call();
    setState(() {});
  }

  void _onPointerUpOrCancel([PointerEvent? event]) {
    if (!_isHolding) return;
    _cancelTimers();
    _isHolding = false;

    if (_progress < 1.0) {
      _progress = 0.0;
      _setLed(false);
      _internalStatus = HoldButtonStatus.idle;
      widget.onCancel?.call();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    widget.controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = currentStatus;
    final isDone = status == HoldButtonStatus.done;
    final isError = status == HoldButtonStatus.error;
    final isWaiting = status == HoldButtonStatus.waiting;

    final Color bgColor;
    final Border border;

    if (isDone) {
      bgColor = const Color(0xFFF3F5E8);
      border = Border.all(color: const Color(0x807A8B34), width: 1.5);
    } else if (isError) {
      bgColor = const Color(0xFFFDF2F0);
      border = Border.all(color: const Color(0x80E85E45), width: 1.5);
    } else if (isWaiting) {
      bgColor = const Color(0xFFF8F7F4);
      border = Border.all(color: const Color(0x805B35B8), width: 1.5);
    } else {
      bgColor = Colors.white;
      border = Border.all(color: const Color(0x402B2536), width: 1.5);
    }

    final String displayLabel;
    final Color labelColor;

    if (isDone) {
      displayLabel = widget.doneLabel;
      labelColor = const Color(0xFF5C6A25);
    } else if (isError) {
      displayLabel = currentStatusText ?? widget.label;
      labelColor = const Color(0xFFE85E45);
    } else if (isWaiting) {
      displayLabel = currentStatusText ?? 'Buscando stick…';
      labelColor = const Color(0xFF5B35B8);
    } else {
      displayLabel = widget.label;
      labelColor = const Color(0xFF2B2536);
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: Container(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Contenido principal
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  // LED indicador circular
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _ledOn
                          ? const Color(0xFFF2E44A)
                          : const Color(0xFFE2DED6),
                      boxShadow: _ledOn
                          ? const [
                              BoxShadow(
                                color: Color(0xB2F2E44A),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Etiqueta del botón
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: labelColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (isError && currentStatusText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Toca para reintentar',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: labelColor.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isWaiting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5B35B8)),
                      ),
                    ),
                ],
              ),
            ),

            // Barra inferior de progreso
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 7,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _progress,
                child: Container(
                  color: isDone
                      ? const Color(0xFF7A8B34)
                      : const Color(0xFFB3A2DC),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
