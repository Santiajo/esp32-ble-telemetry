import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/dashboard_screen.dart';
import '../platform/audio_engine.dart';
import '../platform/stick_hub.dart';
import 'audio_test_screen.dart';
import 'board_screen.dart';
import 'experience/insert_screen.dart';
import 'onboarding/onboarding_screen.dart';

/// Pantalla de inicio de la aplicación Balancín.
///
/// Inicializa el motor [AudioEngine] y el controlador central [StickHub] una única
/// vez al arrancar, reconecta sticks guardados si hay permisos y provee acceso a:
/// 1. "Comenzar" (Onboarding o directo a BoardScreen si ya fue completado)
/// 2. "Tablero de validación" (`BoardScreen`)
/// 3. "Prueba de audio" (`AudioTestScreen`)
/// 4. "Diagnóstico BLE" (`DashboardScreen`)
/// 5. Enlace "Repetir onboarding"
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AudioEngine _audioEngine;
  late final StickHub _hub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _audioEngine = AudioEngine();
    _hub = StickHub();
    _iniciarMotor();
    _reconnectIfPermitted();
  }

  Future<void> _iniciarMotor() async {
    try {
      await _audioEngine.init(bufferSize: AudioEngine.defaultBufferSize);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _reconnectIfPermitted() async {
    try {
      if (Platform.isAndroid) {
        if (await Permission.bluetoothConnect.isGranted) {
          await _hub.reconnectSaved();
        }
      } else {
        await _hub.reconnectSaved();
      }
    } catch (_) {
      // Ignorar fallos de reconexión inicial
    }
  }

  Future<void> _onComenzar() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('balancin_onboarding_done') ?? false;

    if (!mounted) return;

    if (done) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InsertScreen(
            audioEngine: _audioEngine,
            hub: _hub,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OnboardingScreen(
            audioEngine: _audioEngine,
            hub: _hub,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _hub.dispose();
    _audioEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFECE4),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: _loading
                  ? _buildLoadingView()
                  : _error != null
                      ? _buildErrorView()
                      : _buildMainView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildBrandDots(size: 20),
        const SizedBox(height: 32),
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2B2536)),
          strokeWidth: 3,
        ),
        const SizedBox(height: 24),
        const Text(
          'Preparando sonidos…',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2B2536),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sintetizando 103 notas y respuestas en memoria',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF5A536B),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 54, color: Color(0xFFE85E45)),
        const SizedBox(height: 16),
        const Text(
          'Error al iniciar audio',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2B2536),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF5A536B)),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _iniciarMotor();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2B2536),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Reintentar'),
        ),
      ],
    );
  }

  Widget _buildMainView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(child: _buildBrandDots(size: 26)),
        const SizedBox(height: 20),
        const Text(
          'Balancín',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2B2536),
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Instrumento sonoro de balanceo compartido:\nadulto + niño (2–5 años)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5A536B),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 20),

        // Píldora de estado de audio
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF7A8B34),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Audio listo · render: ${_audioEngine.renderTimeMs} ms · carga: ${_audioEngine.loadTimeMs} ms',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2B2536),
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Botón 0: Comenzar (Onboarding o juego)
        ElevatedButton(
          onPressed: _onComenzar,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2B2536),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Comenzar',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Botón 1: Tablero de validación
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BoardScreen(
                  audioEngine: _audioEngine,
                  hub: _hub,
                ),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF2B2536),
            side: const BorderSide(color: Color(0x402B2536), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'Tablero de validación',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Botón 2: Prueba de audio
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AudioTestScreen(audioEngine: _audioEngine),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF2B2536),
            side: const BorderSide(color: Color(0x402B2536), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'Prueba de audio',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Botón 3: Diagnóstico BLE
        OutlinedButton(
          onPressed: () {
            // Liberar conexiones del hub antes de abrir diagnóstico
            _hub.releaseAll();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DashboardScreen(),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF2B2536),
            side: const BorderSide(color: Color(0x402B2536), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'Diagnóstico BLE',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Enlace chico: Repetir onboarding
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OnboardingScreen(
                    audioEngine: _audioEngine,
                    hub: _hub,
                  ),
                ),
              );
            },
            child: const Text(
              'Repetir onboarding',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5A536B),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildBrandDots({required double size}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFB3A2DC),
            borderRadius: BorderRadius.circular(size * 0.4),
          ),
        ),
        SizedBox(width: size * 0.45),
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFFE85E45),
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: size * 0.45),
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFFF2E44A),
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: size * 0.45),
        ClipPath(
          clipper: _TriangleClipper(),
          child: Container(
            width: size,
            height: size,
            color: const Color(0xFF7A8B34),
          ),
        ),
      ],
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
