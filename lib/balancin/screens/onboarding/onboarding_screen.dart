import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../platform/audio_engine.dart';
import '../../platform/stick_hub.dart';
import '../../session/board_session.dart';
import '../../widgets/hold_button.dart';
import '../experience/insert_screen.dart';

/// Pantalla de Onboarding en 5 pasos (#prep del prototipo web).
///
/// Guía a los usuarios a través de:
/// 1. Permisos Bluetooth y No Molestar
/// 2. No Molestar y bloqueo de notificaciones (informativo)
/// 3. Inserción del celular en el eje
/// 4. Vinculación de los dos sticks (HoldButton 3 s)
/// 5. Entrega de sticks y comienzo de la sesión
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.audioEngine,
    required this.hub,
    this.onChime,
    this.onFinished,
  });

  /// Motor de audio de v1 (campanita). La mecánica v2 pasa [onChime] en su lugar.
  final AudioEngine? audioEngine;
  final StickHub hub;

  /// Campanita de stick vinculado (si no, la de [audioEngine]).
  final VoidCallback? onChime;

  /// Qué hacer al tocar «Comenzar». Si es null, va a la inserción de v1.
  final void Function(BuildContext context)? onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0; // 0 a 4 (pasos 1 a 5)

  // Estado del paso 4 (vinculación)
  final HoldButtonController _adultHoldController = HoldButtonController();
  final HoldButtonController _childHoldController = HoldButtonController();

  Future<PairOutcome>? _adultPairFuture;
  Future<PairOutcome>? _childPairFuture;

  bool _adultPaired = false;
  bool _childPaired = false;

  bool _adultLedLit = false;
  bool _childLedLit = false;

  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _checkInitialConnections();
    widget.hub.addListener(_onHubChanged);
  }

  /// Un stick puede conectarse en segundo plano (reconexión automática a la MAC
  /// guardada) sin pasar por "mantener pulsado": se marca como vinculado igual.
  void _onHubChanged() {
    if (!mounted) return;
    var changed = false;
    if (!_adultPaired && widget.hub.isConnected(StickRole.adult)) {
      _adultPaired = true;
      _adultLedLit = true;
      _adultHoldController.setStatus(HoldButtonStatus.done);
      changed = true;
    }
    if (!_childPaired && widget.hub.isConnected(StickRole.child)) {
      _childPaired = true;
      _childLedLit = true;
      _childHoldController.setStatus(HoldButtonStatus.done);
      changed = true;
    }
    if (changed) {
      setState(() {});
      _checkBothPairedAutoAdvance();
    }
  }

  void _checkInitialConnections() {
    if (widget.hub.isConnected(StickRole.adult)) {
      _adultPaired = true;
      _adultLedLit = true;
      _adultHoldController.setStatus(HoldButtonStatus.done);
    }
    if (widget.hub.isConnected(StickRole.child)) {
      _childPaired = true;
      _childLedLit = true;
      _childHoldController.setStatus(HoldButtonStatus.done);
    }
  }

  @override
  void dispose() {
    widget.hub.removeListener(_onHubChanged);
    _autoAdvanceTimer?.cancel();
    _adultHoldController.dispose();
    _childHoldController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (!mounted) return;
    setState(() {
      _currentStep = step.clamp(0, 4);
    });
  }

  // ---------------------------------------------------------------------------
  // Paso 1: Permisos
  // ---------------------------------------------------------------------------
  Future<void> _concederPermisosPaso1() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (mounted) {
        final activar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1A29),
            title: const Text('Bluetooth apagado', style: TextStyle(color: Colors.white)),
            content: const Text(
              'El adaptador Bluetooth está apagado. ¿Deseas activarlo para buscar los sticks?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2E44A),
                  foregroundColor: const Color(0xFF2B2536),
                ),
                child: const Text('Activar'),
              ),
            ],
          ),
        );

        if (activar == true) {
          await FlutterBluePlus.turnOn();
        }
      }
    }

    _goToStep(1);
  }

  // ---------------------------------------------------------------------------
  // Paso 4: Vinculación con HoldButton
  // ---------------------------------------------------------------------------
  void _onPressStartPair(StickRole role) {
    if (widget.hub.isPairing(role)) return;

    final future = widget.hub.pair(role);
    if (role == StickRole.adult) {
      _adultPairFuture = future;
    } else {
      _childPairFuture = future;
    }
  }

  Future<void> _onHoldDonePair(StickRole role) async {
    final controller =
        role == StickRole.adult ? _adultHoldController : _childHoldController;
    var future =
        role == StickRole.adult ? _adultPairFuture : _childPairFuture;

    if (future == null) {
      future = widget.hub.pair(role);
      if (role == StickRole.adult) {
        _adultPairFuture = future;
      } else {
        _childPairFuture = future;
      }
    }

    controller.setStatus(
      HoldButtonStatus.waiting,
      statusText: 'Buscando stick…',
    );

    final outcome = await future;
    if (!mounted) return;

    switch (outcome) {
      case PairOutcome.paired:
        controller.setStatus(HoldButtonStatus.done);
        if (widget.onChime != null) {
          widget.onChime!();
        } else {
          widget.audioEngine?.playChime();
        }
        setState(() {
          if (role == StickRole.adult) {
            _adultPaired = true;
            _adultLedLit = true;
          } else {
            _childPaired = true;
            _childLedLit = true;
          }
        });

        _checkBothPairedAutoAdvance();
        break;

      case PairOutcome.notFound:
        controller.setStatus(
          HoldButtonStatus.error,
          statusText: 'No lo encontramos: enciéndelo y muévelo cerca del teléfono',
        );
        break;

      case PairOutcome.connectFailed:
        controller.setStatus(
          HoldButtonStatus.error,
          statusText: 'Lo encontramos pero no conectó: intenta de nuevo',
        );
        break;

      case PairOutcome.bluetoothOff:
        controller.setStatus(
          HoldButtonStatus.error,
          statusText: 'Bluetooth apagado: actívalo para continuar',
        );
        break;
    }
  }

  void _checkBothPairedAutoAdvance() {
    if (_adultPaired && _childPaired) {
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted && _currentStep == 3) {
          _goToStep(4);
        }
      });
    }
  }

  void _reintentarVinculacion(StickRole role) {
    setState(() {
      if (role == StickRole.adult) {
        _adultPaired = false;
        _adultLedLit = false;
        _adultHoldController.reset();
        _adultPairFuture = null;
      } else {
        _childPaired = false;
        _childLedLit = false;
        _childHoldController.reset();
        _childPairFuture = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Paso 5: Finalizar Onboarding e ir al tablero
  // ---------------------------------------------------------------------------
  Future<void> _comenzarJuego() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('balancin_onboarding_done', true);

    if (!mounted) return;

    final onFinished = widget.onFinished;
    if (onFinished != null) {
      onFinished(context);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => InsertScreen(
          audioEngine: widget.audioEngine!,
          hub: widget.hub,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFECE4),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  // Encabezado común: marca + barra de progreso
                  _buildHeader(),
                  const SizedBox(height: 10),

                  // Texto de simulación sutil
                  const Text(
                    'Tablero de simulación para validación, no la interfaz del producto: en el objeto real la pantalla va oculta dentro del eje.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF5A536B),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Paso activo
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildCurrentStepContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Cuatro formas de marca
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFFB3A2DC),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Color(0xFFE85E45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Color(0xFFF2E44A),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            ClipPath(
              clipper: _TriangleClipper(),
              child: Container(
                width: 16,
                height: 16,
                color: const Color(0xFF7A8B34),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Barra de 5 segmentos (.prog li)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final isDone = index < _currentStep;
            final isCur = index == _currentStep;

            final Color segColor;
            if (isDone) {
              segColor = const Color(0xFF7A8B34);
            } else if (isCur) {
              segColor = const Color(0xFF2B2536);
            } else {
              segColor = const Color(0xFFDCD8CF);
            }

            return Container(
              width: 24,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: segColor,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      case 4:
        return _buildStep5();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Paso 1: Permisos
  // ---------------------------------------------------------------------------
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFigureCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Teléfono con badges
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 112,
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B2536),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 38,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5A536B),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -24,
                    top: 22,
                    child: _buildBadge('BT', const Color(0xFFB3A2DC)),
                  ),
                  Positioned(
                    right: -24,
                    top: 86,
                    child: _buildBadge('zz', const Color(0xFFF2E44A)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Wrap(
                spacing: 8,
                children: [
                  _Chip('Bluetooth', Color(0xFFB3A2DC)),
                  _Chip('No molestar', Color(0xFFF2E44A)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStepText(
          k: 'Paso 1 de 5',
          h2: 'Permisos de Bluetooth y No Molestar',
          p: 'El teléfono necesita hablar con los dos sticks y silenciarse mientras dure el juego.',
        ),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'Conceder permisos',
          onPressed: _concederPermisosPaso1,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 2: No Molestar (Informativo)
  // ---------------------------------------------------------------------------
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFigureCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 112,
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2536),
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF2E44A),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 18,
                        top: -8,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF2B2536),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _Chip('Sin sonido', Color(0xFFF2E44A)),
                  _Chip('Sin vibración', Color(0xFFF2E44A)),
                  _Chip('Sin notificaciones', Color(0xFFF2E44A)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStepText(
          k: 'Paso 2 de 5 · activado',
          h2: 'No Molestar y bloqueo de notificaciones',
          p: 'Durante el juego el teléfono no suena ni vibra. Quedó activado al conceder los permisos.',
        ),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'Continuar',
          onPressed: () => _goToStep(2),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 3: Insertar en el eje (Informativo)
  // ---------------------------------------------------------------------------
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFigureCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flecha apuntando hacia abajo
              const Icon(Icons.arrow_downward_rounded, size: 36, color: Color(0xFF2B2536)),
              const SizedBox(height: 8),
              // Figura del eje con ranura y luz
              Container(
                width: 220,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFB3A2DC),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 0,
                      child: Container(
                        width: 140,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B2536),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFF2E44A),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x8CF2E44A),
                              blurRadius: 18,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Wrap(
                spacing: 8,
                children: [
                  _Chip('Pantalla hacia adentro', Color(0xFFB3A2DC)),
                  _Chip('Solo sonido y luz', Color(0xFFF2E44A)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStepText(
          k: 'Paso 3 de 5',
          h2: 'Inserta el celular en el eje',
          p: 'Pantalla hacia el interior. Desde aquí la única salida es el sonido y una luz difusa de refuerzo.',
        ),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'Ya está en el eje',
          onPressed: () => _goToStep(3),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 4: Vinculación con HoldButton
  // ---------------------------------------------------------------------------
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFigureCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Stick grande
                  _buildStickGraphic(
                    width: 58,
                    height: 170,
                    color: const Color(0xFFB3A2DC),
                    ledLit: _adultLedLit,
                  ),
                  const SizedBox(width: 44),
                  // Stick pequeño
                  _buildStickGraphic(
                    width: 42,
                    height: 118,
                    color: const Color(0xFFE85E45),
                    ledLit: _childLedLit,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Wrap(
                spacing: 8,
                children: [
                  _Chip('Stick grande', Color(0xFFB3A2DC)),
                  _Chip('Stick pequeño', Color(0xFFF4C3B6)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStepText(
          k: 'Paso 4 de 5',
          h2: 'Vincula los dos sticks',
          p: 'Mantén pulsado tres segundos cada botón. El LED del stick parpadea mientras se vincula y queda fijo al terminar.',
        ),
        const SizedBox(height: 18),

        // Botón stick grande
        HoldButton(
          label: 'Mantener · stick grande',
          doneLabel: 'Stick grande vinculado',
          controller: _adultHoldController,
          onLedChange: (lit) => setState(() => _adultLedLit = lit),
          onPressStart: () => _onPressStartPair(StickRole.adult),
          onDone: () => _onHoldDonePair(StickRole.adult),
        ),
        if (_adultPaired)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _reintentarVinculacion(StickRole.adult),
              child: const Text('Volver a vincular', style: TextStyle(fontSize: 12, color: Color(0xFF5A536B))),
            ),
          ),
        const SizedBox(height: 12),

        // Botón stick pequeño
        HoldButton(
          label: 'Mantener · stick pequeño',
          doneLabel: 'Stick pequeño vinculado',
          controller: _childHoldController,
          onLedChange: (lit) => setState(() => _childLedLit = lit),
          onPressStart: () => _onPressStartPair(StickRole.child),
          onDone: () => _onHoldDonePair(StickRole.child),
        ),
        if (_childPaired)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _reintentarVinculacion(StickRole.child),
              child: const Text('Volver a vincular', style: TextStyle(fontSize: 12, color: Color(0xFF5A536B))),
            ),
          ),
        const SizedBox(height: 12),

        // Enlace alternativo para saltar el stick grande que aún no existe
        if (_childPaired && !_adultPaired)
          Center(
            child: TextButton(
              onPressed: () => _goToStep(4),
              child: const Text(
                'Continuar sin el stick grande (la app lo simulará)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5B35B8),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 5: Entrega y Comenzar
  // ---------------------------------------------------------------------------
  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFigureCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildStickGraphic(
                    width: 58,
                    height: 170,
                    color: const Color(0xFFB3A2DC),
                    ledLit: true,
                  ),
                  const SizedBox(width: 44),
                  _buildStickGraphic(
                    width: 42,
                    height: 118,
                    color: const Color(0xFFE85E45),
                    ledLit: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      'Grande\nadulto',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF2B2536)),
                    ),
                  ),
                  SizedBox(width: 32),
                  SizedBox(
                    width: 70,
                    child: Text(
                      'Pequeño\nniño',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF2B2536)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStepText(
          k: 'Paso 5 de 5',
          h2: 'Entrega el stick pequeño al niño y conserva el grande',
          p: 'La asimetría de tamaño indica a quién va cada uno; no hay nada más que explicar.',
        ),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'Comenzar',
          onPressed: _comenzarJuego,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Componentes gráficos auxiliares
  // ---------------------------------------------------------------------------
  Widget _buildFigureCard({required Widget child}) {
    return Container(
      width: double.infinity,
      // Como .fig del prototipo: altura MÍNIMA de 250 px; crece si el contenido
      // (figura + chips) no cabe, en vez de desbordar en pantallas angostas.
      constraints: const BoxConstraints(minHeight: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildStepText({
    required String k,
    required String h2,
    required String p,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF5B35B8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          h2,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2B2536),
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          p,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF4A445A),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2B2536),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Color(0xFF2B2536),
        ),
      ),
    );
  }

  Widget _buildStickGraphic({
    required double width,
    required double height,
    required Color color,
    required bool ledLit,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 14,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ledLit
                    ? const Color(0xFFF2E44A)
                    : const Color(0x402B2536),
                boxShadow: ledLit
                    ? const [
                        BoxShadow(
                          color: Color(0xB2F2E44A),
                          blurRadius: 14,
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.bgColor);
  final String label;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF2B2536),
        ),
      ),
    );
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.04);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
