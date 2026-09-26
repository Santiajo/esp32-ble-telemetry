import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/audio/light_envelope.dart';
import '../core/constants.dart';
import '../core/engine/sound_command.dart';
import '../core/scale.dart';
import '../platform/audio_engine.dart';

/// Pantalla de prueba para el motor de audio SoLoud y síntesis aditiva en memoria.
class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key, this.audioEngine});

  final AudioEngine? audioEngine;

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen>
    with SingleTickerProviderStateMixin {
  late final AudioEngine _audioEngine;
  late final LightEnvelope _lightEnvelope;
  late final Ticker _ticker;

  bool _loading = true;
  String? _error;

  TimbreFamily _selectedFamily = TimbreFamily.marimba;
  double _gain = 0.3;

  double _currentLightLevel = 0.0;
  int _voiceCount = 0;

  final List<Timer> _rafagaTimers = [];

  static const List<String> _pitchNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  @override
  void initState() {
    super.initState();
    _audioEngine = widget.audioEngine ?? AudioEngine();
    _lightEnvelope = LightEnvelope();

    _ticker = createTicker(_onTick);
    if (_audioEngine.isInitialized) {
      _loading = false;
      _ticker.start();
    } else {
      _iniciarAudio();
    }
  }

  Future<void> _iniciarAudio() async {
    try {
      await _audioEngine.init(bufferSize: AudioEngine.defaultBufferSize);
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _ticker.start();
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

  void _onTick(Duration elapsed) {
    if (!mounted || _loading) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final lvl = _lightEnvelope.level(nowMs, busGain: _audioEngine.currentBusGain);
    final voices = _audioEngine.voiceCount;

    if ((lvl - _currentLightLevel).abs() > 0.005 || voices != _voiceCount) {
      setState(() {
        _currentLightLevel = lvl;
        _voiceCount = voices;
      });
    }
  }

  void _dispatch(List<SoundCommand> cmds) {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    _lightEnvelope.onCommands(cmds, nowMs);
    _audioEngine.handle(cmds);
  }

  void _tocarNota(int index) {
    final cmd = NoteOn(
      index: index,
      midi: kNotes[index],
      family: _selectedFamily,
      gain: _gain,
      hidden: _selectedFamily == TimbreFamily.oculto,
      fieldLo: 0,
      fieldCount: 25,
    );
    _dispatch([cmd]);
  }

  void _dispararRafaga() {
    for (final t in _rafagaTimers) {
      t.cancel();
    }
    _rafagaTimers.clear();

    for (var i = 0; i < 24; i++) {
      final delayMs = (i * (1000 / 24)).round();
      final timer = Timer(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        _tocarNota(i);
      });
      _rafagaTimers.add(timer);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final t in _rafagaTimers) {
      t.cancel();
    }
    _rafagaTimers.clear();
    if (widget.audioEngine == null) {
      _audioEngine.dispose();
    }
    super.dispose();
  }

  String _notaTexto(int index) {
    final midi = kNotes[index];
    final pitch = _pitchNames[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$pitch$octave\n#$index ($midi)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        title: const Text(
          'Balancín · Motor de Audio (Fase 3)',
          style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                'Voces: $_voiceCount / 64',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.0,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.tealAccent),
                  SizedBox(height: 16),
                  Text(
                    'Renderizando 103 sonidos en Isolate\ne inicializando SoLoud...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'Error al iniciar audio: $_error',
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tiempos de render y carga + Indicador de Luz reactiva
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(color: const Color(0xFF222222)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'RENDIMIENTO INICIAL',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10.0,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Render Isolate: ${_audioEngine.renderTimeMs} ms',
                                      style: const TextStyle(
                                        color: Colors.tealAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.0,
                                      ),
                                    ),
                                    Text(
                                      'Carga SoLoud: ${_audioEngine.loadTimeMs} ms',
                                      style: const TextStyle(
                                        color: Colors.lightBlueAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Círculo reactivo de Luz
                              Column(
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.amber.withValues(
                                        alpha: (0.15 + 0.85 * _currentLightLevel).clamp(0.0, 1.0),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.amber.withValues(
                                            alpha: (_currentLightLevel * 0.9).clamp(0.0, 1.0),
                                          ),
                                          blurRadius: 10 + 25 * _currentLightLevel,
                                          spreadRadius: 2 + 8 * _currentLightLevel,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${(_currentLightLevel * 100).toInt()}%',
                                        style: TextStyle(
                                          color: _currentLightLevel > 0.4
                                              ? Colors.black
                                              : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Luz',
                                    style: TextStyle(color: Colors.white54, fontSize: 10.0),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Controles de Familia tímbrica y Ganancia
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(color: const Color(0xFF222222)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Familia:',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.0,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SegmentedButton<TimbreFamily>(
                                      segments: const [
                                        ButtonSegment(
                                          value: TimbreFamily.marimba,
                                          label: Text('Marimba', style: TextStyle(fontSize: 10)),
                                        ),
                                        ButtonSegment(
                                          value: TimbreFamily.mixta,
                                          label: Text('Mixta', style: TextStyle(fontSize: 10)),
                                        ),
                                        ButtonSegment(
                                          value: TimbreFamily.glock,
                                          label: Text('Glock', style: TextStyle(fontSize: 10)),
                                        ),
                                        ButtonSegment(
                                          value: TimbreFamily.oculto,
                                          label: Text('Oculto', style: TextStyle(fontSize: 10)),
                                        ),
                                      ],
                                      selected: {_selectedFamily},
                                      onSelectionChanged: (val) {
                                        setState(() {
                                          _selectedFamily = val.first;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'Ganancia nota: ${_gain.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.0,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _gain,
                                      min: 0.0,
                                      max: 0.3,
                                      divisions: 30,
                                      activeColor: Colors.tealAccent,
                                      onChanged: (v) => setState(() => _gain = v),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Grilla 5x5 de teclas pentatónicas con Listener (cero latencia)
                        const Text(
                          'TECLADO PENTATÓNICO (25 ALTURAS · C3 A A7)',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10.0,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AspectRatio(
                          aspectRatio: 1.0,
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 6.0,
                              mainAxisSpacing: 6.0,
                            ),
                            itemCount: BalancinConst.numNotes,
                            itemBuilder: (context, index) {
                              return Listener(
                                onPointerDown: (_) => _tocarNota(index),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1E),
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _notaTexto(index),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Botones de acciones y sonidos de sistema
                        const Text(
                          'ACCIONES Y SONIDOS DE SISTEMA',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10.0,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF222222),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _dispatch([const OpeningSound()]),
                              child: const Text('Apertura'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF222222),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _dispatch([const FinalSound()]),
                              child: const Text('Final'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF222222),
                                foregroundColor: Colors.tealAccent,
                              ),
                              onPressed: () => _dispatch([
                                FieldResonance(
                                  lo: 5,
                                  count: 12,
                                  family: _selectedFamily,
                                ),
                              ]),
                              child: const Text('Resonancia de campo'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF222222),
                                foregroundColor: Colors.amberAccent,
                              ),
                              onPressed: () => _audioEngine.playChime(),
                              child: const Text('Campanita'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade900,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _dispararRafaga,
                              child: const Text('Ráfaga (24 notas / 1s)'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                              onPressed: () =>
                                  _dispatch([const BusFade(to: 0.0, seconds: 1.2)]),
                              child: const Text('Fade out (1.2s)'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.greenAccent,
                                side: const BorderSide(color: Colors.greenAccent),
                              ),
                              onPressed: () => _dispatch([
                                const BusFade(
                                  from: 0.0,
                                  to: BalancinConst.busGain,
                                  seconds: 0.6,
                                ),
                              ]),
                              child: const Text('Fade in (0.6s)'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
