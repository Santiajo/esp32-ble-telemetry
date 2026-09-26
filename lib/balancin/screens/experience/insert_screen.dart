import 'dart:async';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../platform/audio_engine.dart';
import '../../platform/stick_hub.dart';
import '../../session/board_session.dart';
import '../board_screen.dart';

/// Pantalla de inserción en el eje (#insert del prototipo web).
///
/// Muestra al usuario cómo insertar el teléfono en el objeto físico, con una
/// cuenta regresiva de 6 segundos que inicia la experiencia automáticamente.
class InsertScreen extends StatefulWidget {
  const InsertScreen({
    super.key,
    required this.audioEngine,
    required this.hub,
  });

  final AudioEngine audioEngine;
  final StickHub hub;

  @override
  State<InsertScreen> createState() => _InsertScreenState();
}

class _InsertScreenState extends State<InsertScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Timer? _countdownTimer;
  int _secondsLeft = 6;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
      });
      if (_secondsLeft <= 0) {
        _irAEje();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _irAEje() async {
    if (_navigated) return;
    _navigated = true;
    _countdownTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final playView = prefs.getString('balancin_play_view') ?? 'eje';
    final startInEje = playView == 'eje';

    final childSource = widget.hub.isConnected(StickRole.child)
        ? StickSource.stick
        : StickSource.auto;
    final adultSource = widget.hub.isConnected(StickRole.adult)
        ? StickSource.stick
        : StickSource.auto;

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BoardScreen(
          audioEngine: widget.audioEngine,
          hub: widget.hub,
          userMode: true,
          startInEje: startInEje,
          initialSources: {
            StickRole.child: childSource,
            StickRole.adult: adultSource,
          },
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
                  _buildHeaderBrand(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildFigureCard(),
                          const SizedBox(height: 20),
                          const Text(
                            'Inserta el celular en el eje',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2B2536),
                              letterSpacing: -0.5,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Pantalla hacia adentro. Desde aquí la única salida es el sonido y una luz difusa.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF4A445A),
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Empieza sola en $_secondsLeft s',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5B35B8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _irAEje,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2B2536),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Ya está adentro',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildHeaderBrand() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }

  Widget _buildFigureCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          final t = _animController.value;

          // Animación de inserción:
          // 0.0–0.15: teléfono arriba (y = 0)
          // 0.15–0.55: teléfono baja al eje (y = 0 -> 100)
          // 0.55–1.0: teléfono se queda adentro (y = 100)
          double phoneY = 0.0;
          if (t <= 0.15) {
            phoneY = 0.0;
          } else if (t <= 0.55) {
            final p = (t - 0.15) / 0.40;
            phoneY = Curves.easeInOut.transform(p) * 105.0;
          } else {
            phoneY = 105.0;
          }

          // Luz difusa que enciende al entrar:
          // 0.0–0.55: opacidad 0
          // 0.55–0.75: opacidad sube a 0.9
          // 0.75–1.0: opacidad se mantiene en 0.9
          double lightOpacity = 0.0;
          if (t <= 0.55) {
            lightOpacity = 0.0;
          } else if (t <= 0.75) {
            lightOpacity = ((t - 0.55) / 0.20) * 0.9;
          } else {
            lightOpacity = 0.9;
          }

          return SizedBox(
            width: 280,
            height: 230,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // Figura del eje (cilindro horizontal en la parte inferior)
                Positioned(
                  bottom: 12,
                  child: Container(
                    width: 260,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB3A2DC),
                      borderRadius: BorderRadius.circular(44),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ranura del eje
                        Positioned(
                          top: 0,
                          child: Container(
                            width: 176,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2B2536),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        // Luz en la parte inferior del eje
                        Positioned(
                          bottom: 14,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFF2E44A),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x99F2E44A),
                                  blurRadius: 20,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Teléfono deslizándose hacia adentro
                Positioned(
                  top: phoneY + 10,
                  child: Container(
                    width: 160,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A536B),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            width: 14,
                            height: 14,
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

                // Destellos laterales de luz difusa (#7B5FCB)
                if (lightOpacity > 0.0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 48,
                    child: Opacity(
                      opacity: lightOpacity.clamp(0.0, 1.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 72,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const RadialGradient(
                                colors: [
                                  Color(0xFF7B5FCB),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 72,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const RadialGradient(
                                colors: [
                                  Color(0xFF7B5FCB),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
