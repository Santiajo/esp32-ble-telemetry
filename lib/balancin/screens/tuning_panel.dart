import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/gesture/imu_gesture_reader.dart';
import '../platform/ble_stick_link.dart';

/// Panel de ajuste de umbrales del sensor IMU en vivo (fase 5).
///
/// Modifica directamente los campos de [ImuTuning] en el lector conectado,
/// muestra las lecturas en tiempo real y permite copiar o restaurar los valores.
class TuningPanel extends StatefulWidget {
  const TuningPanel({
    super.key,
    required this.link,
  });

  final BleStickLink link;

  @override
  State<TuningPanel> createState() => _TuningPanelState();
}

class _TuningPanelState extends State<TuningPanel> {
  ImuTuning get _tuning => widget.link.reader.tuning;
  ImuGestureReader get _reader => widget.link.reader;

  /// Las lecturas del stick cambian a 100 Hz sin notificar: se redibuja a ~15 Hz
  /// para que los valores en vivo no queden congelados mientras se mueve el stick.
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    _refresco = Timer.periodic(const Duration(milliseconds: 66), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  void _restaurarValores() {
    setState(() {
      final d = ImuTuning();
      _tuning.onDps = d.onDps;
      _tuning.offDps = d.offDps;
      _tuning.omegaMaxDps = d.omegaMaxDps;
      _tuning.ampFullDeg = d.ampFullDeg;
      _tuning.articulationDeg = d.articulationDeg;
      _tuning.shakeMinDps = d.shakeMinDps;
      _tuning.stillStdDps = d.stillStdDps;
    });
  }

  Future<void> _copiarValores() async {
    final t = _tuning;
    final texto =
        'onDps=${t.onDps.toStringAsFixed(1)}, '
        'offDps=${t.offDps.toStringAsFixed(1)}, '
        'omegaMaxDps=${t.omegaMaxDps.toStringAsFixed(0)}, '
        'ampFullDeg=${t.ampFullDeg.toStringAsFixed(0)}, '
        'articulationDeg=${t.articulationDeg.toStringAsFixed(0)}, '
        'shakeMinDps=${t.shakeMinDps.toStringAsFixed(0)}, '
        'stillStdDps=${t.stillStdDps.toStringAsFixed(1)}';

    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Valores IMU copiados al portapapeles',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Color(0xFF2B2536),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.link,
      builder: (context, _) {
        final t = _tuning;
        final bias = _reader.biasDps;
        final maxOff = math.max(2.0, math.min(60.0, t.onDps - 1.0));

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1A29),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Encabezado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.link.connected
                                  ? const Color(0xFF7A8B34)
                                  : const Color(0xFFE85E45),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ajuste IMU · ${widget.link.role.name.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text(
                    widget.link.statusText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.link.connected
                          ? const Color(0xFFF2E44A)
                          : Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Caja de lecturas en tiempo real
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF12101A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF332B45)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LECTURAS EN VIVO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildLiveBar(
                          'ω (${_reader.omegaDps.toStringAsFixed(0)} °/s)',
                          (_reader.omegaDps / t.omegaMaxDps).clamp(0.0, 1.0),
                          const Color(0xFFF2E44A),
                        ),
                        const SizedBox(height: 6),
                        _buildLiveBar(
                          'vel01 (${(_reader.vel01 * 100).toStringAsFixed(0)} %)',
                          _reader.vel01,
                          const Color(0xFFB3A2DC),
                        ),
                        const SizedBox(height: 6),
                        _buildLiveBar(
                          'amp (${(_reader.amp * 100).toStringAsFixed(0)} %)',
                          _reader.amp,
                          const Color(0xFFE85E45),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildPill(
                              _reader.active ? 'ACTIVO' : 'QUIETO',
                              _reader.active ? const Color(0xFF7A8B34) : Colors.white24,
                            ),
                            _buildPill(
                              _reader.shake ? '¡SHAKE!' : 'NO SHAKE',
                              _reader.shake ? const Color(0xFFF2E44A) : Colors.white24,
                              textColor: _reader.shake ? const Color(0xFF2B2536) : Colors.white70,
                            ),
                            _buildPill(
                              'Eje ${_reader.dominantAxis == 0 ? "X" : _reader.dominantAxis == 1 ? "Y" : "Z"}',
                              const Color(0xFF5B35B8),
                            ),
                            _buildPill(
                              'dx: ${_reader.dx >= 0 ? "+${_reader.dx}" : _reader.dx} dy: ${_reader.dy >= 0 ? "+${_reader.dy}" : _reader.dy}',
                              Colors.white24,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Bias: (${bias.x.toStringAsFixed(1)}, ${bias.y.toStringAsFixed(1)}, ${bias.z.toStringAsFixed(1)}) °/s',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.white60,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sliders de tuning
                  _buildSlider(
                    label: 'onDps (°/s)',
                    desc: 'Umbral superior para empezar a contar movimiento',
                    value: t.onDps,
                    min: 5,
                    max: 80,
                    divisions: 75,
                    onChanged: (v) {
                      setState(() {
                        t.onDps = v;
                        if (t.offDps >= t.onDps) {
                          t.offDps = math.max(2.0, t.onDps - 1.0);
                        }
                      });
                    },
                  ),
                  _buildSlider(
                    label: 'offDps (°/s)',
                    desc: 'Umbral inferior para volver a reposo (< onDps)',
                    value: t.offDps.clamp(2.0, maxOff),
                    min: 2,
                    max: maxOff,
                    divisions: math.max(1, (maxOff - 2).round()),
                    onChanged: (v) {
                      setState(() {
                        t.offDps = v;
                      });
                    },
                  ),
                  _buildSlider(
                    label: 'omegaMaxDps (°/s)',
                    desc: 'Velocidad angular para vel01 = 1 (registro máximo)',
                    value: t.omegaMaxDps,
                    min: 100,
                    max: 1000,
                    divisions: 90,
                    onChanged: (v) => setState(() => t.omegaMaxDps = v),
                  ),
                  _buildSlider(
                    label: 'ampFullDeg (°)',
                    desc: 'Excursión angular en 0,8 s para amp = 1',
                    value: t.ampFullDeg,
                    min: 20,
                    max: 180,
                    divisions: 32,
                    onChanged: (v) => setState(() => t.ampFullDeg = v),
                  ),
                  _buildSlider(
                    label: 'articulationDeg (°)',
                    desc: 'Recorrido angular por cada nota (densidad rítmica)',
                    value: t.articulationDeg,
                    min: 5,
                    max: 90,
                    divisions: 85,
                    onChanged: (v) => setState(() => t.articulationDeg = v),
                  ),
                  _buildSlider(
                    label: 'shakeMinDps (°/s)',
                    desc: '|ω| mínima del eje dominante para detectar sacudida',
                    value: t.shakeMinDps,
                    min: 20,
                    max: 300,
                    divisions: 28,
                    onChanged: (v) => setState(() => t.shakeMinDps = v),
                  ),
                  _buildSlider(
                    label: 'stillStdDps (°/s)',
                    desc: 'Desviación estándar máxima para considerar quieto',
                    value: t.stillStdDps,
                    min: 1,
                    max: 10,
                    divisions: 18,
                    onChanged: (v) => setState(() => t.stillStdDps = v),
                  ),
                  const SizedBox(height: 16),

                  // Botones de acción inferiores
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restaurarValores,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Restaurar valores'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _copiarValores,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copiar valores'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF2E44A),
                            foregroundColor: const Color(0xFF2B2536),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            textStyle: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlider({
    required String label,
    required String desc,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF2E44A),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Text(
            desc,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFB3A2DC),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFFF2E44A),
              overlayColor: const Color(0xFFF2E44A).withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveBar(String label, double fraction, Color color) {
    final clamped = fraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        const SizedBox(height: 3),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(3),
          ),
          clipBehavior: Clip.antiAlias,
          child: FractionallySizedBox(
            widthFactor: clamped,
            alignment: Alignment.centerLeft,
            child: Container(color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildPill(String text, Color bg, {Color textColor = Colors.white}) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}
