import 'dart:async';

import 'package:flutter/material.dart';

import '../core/tilt/axis_map.dart';
import '../platform/tilt_stick.dart';
import 'v2_ui.dart';

/// Asistente de ejes de un stick (plan v2 §5.3): reposo → «inclínalo hacia
/// arriba» → «hacia tu derecha». Desde los niveles 2 y 3 importa el sentido
/// lateral («Espejo», «Iguales»), y una placa sin forma de stick se puede tomar
/// girada. El resultado se guarda por MAC y vale para el banco y el juego.
class AxisWizardSheet extends StatefulWidget {
  const AxisWizardSheet({super.key, required this.stick, required this.who});

  final TiltStick stick;

  /// «adulto» o «niño», para los textos.
  final String who;

  static Future<void> open(BuildContext context, TiltStick stick, String who) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: V2.paper,
        builder: (_) => AxisWizardSheet(stick: stick, who: who),
      );

  @override
  State<AxisWizardSheet> createState() => _AxisWizardSheetState();
}

class _AxisWizardSheetState extends State<AxisWizardSheet> {
  AxisWizard _w = AxisWizard();
  Timer? _timer;
  int _restSamples = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final g = widget.stick.reader.gravity;
      if (g == null || !widget.stick.connected) return;
      _w.feed(g);
      if (_w.step == WizardStep.rest) _restSamples++;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_w.next()) {
      setState(() {});
      return;
    }
    if (_w.step == WizardStep.done && _w.result != null) await widget.stick.saveAxes(_w.result!);
    if (mounted) setState(() {});
  }

  void _restart() => setState(() {
        _w = AxisWizard();
        _restSamples = 0;
      });

  @override
  Widget build(BuildContext context) {
    final (title, text) = switch (_w.step) {
      WizardStep.rest => ('Paso 1 de 3 · Descanso', 'Sostén el stick del ${widget.who} como al jugar, quieto, y toca «Listo».'),
      WizardStep.up => ('Paso 2 de 3 · Arriba', 'Inclínalo hacia arriba (hacia adelante), vuelve al descanso y toca «Listo».'),
      WizardStep.right => ('Paso 3 de 3 · Derecha', 'Inclínalo hacia la derecha de quien lo sostiene, vuelve y toca «Listo».'),
      WizardStep.done => ('Listo', 'Ejes guardados para este stick. Valen para el banco y para el juego.'),
      WizardStep.failed => ('No se pudo', _w.error ?? 'Repite el asistente.'),
    };
    final tilting = _w.step == WizardStep.up || _w.step == WizardStep.right;
    final progress = tilting ? (_w.currentTiltDeg / AxisWizard.minTiltDeg).clamp(0.0, 1.0) : (_restSamples / 60).clamp(0.0, 1.0);
    final canNext = switch (_w.step) {
      WizardStep.rest => _restSamples >= 60, // ~1 s de datos
      WizardStep.up || WizardStep.right => true,
      _ => false,
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ejes del stick del ${widget.who}', style: V2.h2),
          const SizedBox(height: 4),
          Text(title, style: V2.kicker),
          const SizedBox(height: 10),
          Text(text, style: V2.sub),
          if (_w.step != WizardStep.done && _w.step != WizardStep.failed && _w.error != null) ...[
            const SizedBox(height: 8),
            Text(_w.error!, style: const TextStyle(color: V2.coral, fontWeight: FontWeight.w800)),
          ],
          if (!widget.stick.connected) ...[
            const SizedBox(height: 8),
            const Text('El stick no está conectado.', style: TextStyle(color: V2.coral, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 14),
          if (_w.step != WizardStep.done && _w.step != WizardStep.failed) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 8, color: V2.olive, backgroundColor: V2.line),
            ),
            if (tilting) ...[
              const SizedBox(height: 4),
              Text('${_w.currentTiltDeg.toStringAsFixed(0)}° (mínimo ${AxisWizard.minTiltDeg.toStringAsFixed(0)}°)', style: V2.small),
            ],
            const SizedBox(height: 14),
          ],
          Row(children: [
            if (_w.step == WizardStep.done || _w.step == WizardStep.failed) ...[
              Expanded(child: V2.secondary('Repetir', _restart, height: 48)),
              const SizedBox(width: 10),
              Expanded(child: V2.primary('Cerrar', () => Navigator.pop(context), height: 48)),
            ] else ...[
              Expanded(
                child: V2.secondary('Ejes de fábrica', () async {
                  await widget.stick.resetAxes();
                  if (context.mounted) Navigator.pop(context);
                }, height: 48),
              ),
              const SizedBox(width: 10),
              Expanded(child: V2.primary('Listo', canNext ? _next : null, height: 48)),
            ],
          ]),
        ]),
      ),
    );
  }
}
