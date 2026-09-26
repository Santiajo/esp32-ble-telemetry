import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/dashboard_screen.dart';
import '../platform/audio_engine.dart';
import '../platform/stick_hub.dart';
import 'archive_screen.dart';
import 'audio_test_screen.dart';
import 'board_screen.dart';
import 'experience/insert_screen.dart';
import 'onboarding/onboarding_screen.dart';

/// Pantalla de inicio de la aplicación Balancín.
///
/// Inicializa el motor [AudioEngine] y el controlador central [StickHub] una única
/// vez al arrancar, reconecta sticks guardados si hay permisos y provee acceso a:
/// 1. "Comenzar" (Onboarding o directo a BoardScreen si ya fue completado)
/// 2. Configuración de vista durante el juego ("Solo luz" / "Tablero")
/// 3. Modo estudio y sesiones archivadas
/// 4. "Tablero de validación" (`BoardScreen`)
/// 5. "Prueba de audio" (`AudioTestScreen`)
/// 6. "Diagnóstico BLE" (`DashboardScreen`)
/// 7. Enlace "Repetir onboarding"
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
  String _playView = 'eje';
  bool _studyMode = false;

  @override
  void initState() {
    super.initState();
    _audioEngine = AudioEngine();
    _hub = StickHub();
    _iniciarMotor();
    _reconnectIfPermitted();
    _cargarPreferencias();
  }

  Future<void> _cargarPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _playView = prefs.getString('balancin_play_view') ?? 'eje';
        _studyMode = prefs.getBool('balancin_study_mode') ?? false;
      });
    }
  }

  Future<void> _setPlayView(String view) async {
    setState(() => _playView = view);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('balancin_play_view', view);
  }

  Future<void> _setStudyMode(bool value) async {
    setState(() => _studyMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('balancin_study_mode', value);
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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(child: _buildBrandDots(size: 26)),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),

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
          const SizedBox(height: 20),

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
          const SizedBox(height: 14),

          // Selector "Durante el juego mostrar": "Solo luz" | "Tablero"
          _buildPlayViewSelector(),
          const SizedBox(height: 10),

          // Interruptor "Sesión de estudio"
          _buildStudyModeSwitch(),
          const SizedBox(height: 10),

          // Botón "Sesiones guardadas"
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ArchiveScreen(),
                ),
              );
            },
            icon: const Icon(Icons.folder_outlined, size: 20),
            label: const Text('Sesiones guardadas'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2B2536),
              side: const BorderSide(color: Color(0x402B2536), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 16),

          const Divider(color: Color(0x202B2536), height: 1),
          const SizedBox(height: 16),

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
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPlayViewSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Durante el juego mostrar',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B2536),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEFECE4),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setPlayView('eje'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _playView == 'eje' ? const Color(0xFF2B2536) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Solo luz',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _playView == 'eje' ? Colors.white : const Color(0xFF5A536B),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setPlayView('tablero'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _playView == 'tablero' ? const Color(0xFF2B2536) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Tablero',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _playView == 'tablero' ? Colors.white : const Color(0xFF5A536B),
                        ),
                      ),
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

  Widget _buildStudyModeSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sesión de estudio',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B2536),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Guarda la telemetría de cada partida en este teléfono. Sin audio, imagen ni datos personales.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5A536B),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: _studyMode,
            activeTrackColor: const Color(0xFF5B35B8),
            onChanged: _setStudyMode,
          ),
        ],
      ),
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
