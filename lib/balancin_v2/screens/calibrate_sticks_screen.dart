import 'dart:async';

import 'package:flutter/material.dart';

import '../../balancin/core/app_clock.dart';
import '../../balancin/session/board_session.dart' show StickRole;
import '../app_v2.dart';
import '../core/levels.dart';
import '../core/stick_state.dart';
import '../platform/cal_store.dart';
import '../platform/tilt_stick.dart';
import '../widgets/v2_ui.dart';
import 'stick_check_screen.dart';
import 'sticks_gate_screen.dart';

/// Abre la calibración con los dos sticks conectados.
Future<void> openCalibration(BuildContext context, V2Services s) => openWithSticks(context, s, () => CalibrateSticksScreen(s: s));

/// «Calibrar los sticks», para usuarios (plan v2 §18): lleva a cada persona por los
/// pasos del chequeo, sin lecturas técnicas. Guarda los ejes y el rango de cada stick.
class CalibrateSticksScreen extends StatefulWidget {
  const CalibrateSticksScreen({super.key, required this.s});
  final V2Services s;

  @override
  State<CalibrateSticksScreen> createState() => _CalibrateSticksScreenState();
}

class _CalibrateSticksScreenState extends State<CalibrateSticksScreen> {
  final Map<Role, StickCal> _cal = {};

  static StickRole _sr(Role r) => r == Role.adult ? StickRole.adult : StickRole.child;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    for (final r in Role.values) {
      final c = await CalStore.load(widget.s.hub.link(_sr(r))?.savedMac);
      if (c != null) _cal[r] = c;
    }
    if (mounted) setState(() {});
  }

  Future<void> _calibrate(Role role) async {
    final s = widget.s;
    final link = s.hub.ensureLink(_sr(role));
    final stick = TiltStick(link, params: s.params);
    s.hub.hold();
    final cal = await Navigator.of(context).push<StickCal>(MaterialPageRoute(
      builder: (_) => StickCheckScreen(
        role: role,
        params: s.params,
        forUsers: true,
        title: role == Role.adult ? 'Stick del adulto' : 'Stick del niño',
        read: () => stick.snapshot(AppClock.nowMs()),
        saveAxes: (axes) => unawaited(stick.saveAxes(axes)),
      ),
    ));
    stick.dispose();
    s.hub.unhold();
    if (cal == null) return;
    await CalStore.save(link.savedMac, cal);
    if (mounted) setState(() => _cal[role] = cal);
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: V2.theme,
        child: Scaffold(
          appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28), children: [
              Text('Calibrar los sticks', textAlign: TextAlign.center, style: V2.h1()),
              const SizedBox(height: 8),
              const Text(
                'Cada persona sostiene su stick como al jugar y sigue los pasos. '
                'El juego mide la inclinación, no la altura: hay que inclinar la punta, sin levantar el brazo.',
                textAlign: TextAlign.center,
                style: V2.sub,
              ),
              const SizedBox(height: 18),
              _row(Role.adult, 'Stick grande · adulto', V2.lilaInk),
              const SizedBox(height: 10),
              _row(Role.child, 'Stick pequeño · niño', V2.coral),
              const SizedBox(height: 14),
              const Text('Sujeten el stick siempre de la misma forma. Si lo giran en la mano, calibren de nuevo.',
                  textAlign: TextAlign.center, style: V2.small),
            ]),
          ),
        ),
      );

  Widget _row(Role role, String name, Color color) {
    final done = _cal.containsKey(role);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: V2.ink)),
            const SizedBox(height: 2),
            Text(done ? 'Calibrado' : 'Sin calibrar', style: V2.small),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: V2.secondary(done ? 'Repetir' : 'Calibrar', () => unawaited(_calibrate(role)), height: 42),
        ),
      ]),
    );
  }
}
