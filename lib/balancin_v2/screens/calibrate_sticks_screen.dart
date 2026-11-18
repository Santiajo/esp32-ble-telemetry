import 'dart:async';

import 'package:flutter/material.dart';

import '../../balancin/core/app_clock.dart';
import '../../balancin/session/board_session.dart' show StickRole;
import '../app_v2.dart';
import '../core/levels.dart';
import '../core/stick_state.dart';
import '../core/sync_engine.dart';
import '../platform/tilt_stick.dart';
import '../widgets/v2_ui.dart';
import 'insert_v2_screen.dart';
import 'stick_check_screen.dart';
import 'sticks_gate_screen.dart';

/// Único camino a un nivel: sticks conectados → calibrar los dos → inserción → juego.
Future<void> openLevel(BuildContext context, V2Services s, int levelIndex) =>
    openWithSticks(context, s, () => CalibrateSticksScreen(s: s, levelIndex: levelIndex));

/// «Calibren los sticks», obligatorio al entrar a cada nivel (plan v2 §19): cada persona
/// sigue los pasos del chequeo, sin lecturas técnicas. Hasta calibrar los dos no se sigue.
class CalibrateSticksScreen extends StatefulWidget {
  const CalibrateSticksScreen({super.key, required this.s, required this.levelIndex});
  final V2Services s;
  final int levelIndex;

  @override
  State<CalibrateSticksScreen> createState() => _CalibrateSticksScreenState();
}

class _CalibrateSticksScreenState extends State<CalibrateSticksScreen> {
  final Map<Role, StickCal> _cal = {};

  static StickRole _sr(Role r) => r == Role.adult ? StickRole.adult : StickRole.child;

  Future<void> _calibrate(Role role) async {
    final s = widget.s;
    final stick = TiltStick(s.hub.ensureLink(_sr(role)), params: s.params);
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
    if (cal != null && mounted) setState(() => _cal[role] = cal);
  }

  void _continue() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => InsertV2Screen(s: widget.s, mode: PlayMode.levels, levelIndex: widget.levelIndex, cals: Map.of(_cal)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final all = Role.values.every(_cal.containsKey);
    final l = levels[widget.levelIndex];
    return Theme(
      data: V2.theme,
      child: Scaffold(
        appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 12), children: [
                Text('Calibren los sticks', textAlign: TextAlign.center, style: V2.h1()),
                const SizedBox(height: 4),
                Text('Antes del nivel ${l.id} · ${l.name}', textAlign: TextAlign.center, style: V2.kicker),
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
                const Text('Tomen cada uno su stick antes de tocar «Calibrar». Sujétenlo siempre de la misma forma.',
                    textAlign: TextAlign.center, style: V2.small),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: V2.primary(all ? 'Continuar' : 'Falta calibrar', all ? _continue : null),
            ),
          ]),
        ),
      ),
    );
  }

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
