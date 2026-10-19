/// Fuente sintética de movimiento (plan v2 §5.1; `synthDrive` del prototipo).
///
/// Dos sinusoides más un error según la calidad pedida: en sincronía, cerca,
/// lejos, o un ciclo que pasa por lejos → cerca → sync → sync cada 5 s.
/// Se adapta a la relación y a quién guía en ese momento.
library;

import 'dart:math' as math;

import 'levels.dart';
import 'stick_state.dart';
import 'sync_engine.dart';

enum SynthQuality { sync, cerca, lejos, cycle }

const Map<SynthQuality, String> synthQualityNames = {
  SynthQuality.sync: 'en sincronía',
  SynthQuality.cerca: 'cerca',
  SynthQuality.lejos: 'lejos',
  SynthQuality.cycle: 'ciclo',
};

const List<SynthQuality> _cycle = [SynthQuality.lejos, SynthQuality.cerca, SynthQuality.sync, SynthQuality.sync];

/// Calidad efectiva en el instante [now] (resuelve el ciclo).
SynthQuality effectiveQuality(SynthQuality q, double now) =>
    q == SynthQuality.cycle ? _cycle[(now / 1000 / 5).floor() % 4] : q;

/// Lleva un punto del plano a la inclinación que lo produce y se la da al stick (`feedPlane`).
void feedPlane(StickState st, double x, double y, SyncEngine e) {
  final r = st.range(e.params);
  st.feedTilt(
    r.cx + x.clamp(-planeLimit, planeLimit) / planeLimit * r.hrX,
    r.cy + y.clamp(-planeLimit, planeLimit) / planeLimit * r.hrY,
    e.params,
  );
}

/// Alimenta a uno o a los dos sticks. [roles] limita qué sticks mueve la fuente
/// (en el banco cada rol elige su fuente).
void synthDrive(SyncEngine e, SynthQuality quality, double now, {Set<Role> roles = const {Role.adult, Role.child}}) {
  final s = now / 1000;
  final q = effectiveQuality(quality, now);
  final err = q == SynthQuality.sync ? 0.25 : (q == SynthQuality.cerca ? 1.7 : 4.2);
  final ex = err * math.sin(s * 0.83 + 1), ey = err * math.cos(s * 0.71);
  P2 base(double u) => P2(3.6 * math.sin(u * 1.05), 4.4 * math.sin(u * 1.6 + 0.5));
  var a = base(s);
  P2 c;
  switch (e.relation) {
    case Relation.together:
      c = P2(3 * math.sin(s * 0.7), a.y + ey);
    case Relation.seesaw:
      c = P2(3 * math.sin(s * 0.7), -a.y + ey);
    case Relation.mirror:
      c = P2(-a.x + ex, a.y + ey);
    case Relation.same:
      c = P2(a.x + ex, a.y + ey);
    case Relation.pulse:
      final fr = q == SynthQuality.sync ? 1.0 : (q == SynthQuality.cerca ? 1.15 : 1.7);
      a = P2(1, 4 * math.sin(2 * math.pi * 0.8 * s));
      c = P2(-1, 4 * math.sin(2 * math.pi * 0.8 * fr * s + 0.4));
    case Relation.follow:
      final g = base(s - 0.5);
      if (e.guide == Role.child) {
        c = a;
        a = P2(g.x + ex, g.y + ey);
      } else {
        c = P2(g.x + ex, g.y + ey);
      }
    case Relation.free:
    case Relation.song:
      c = P2(a.x * 0.9 + ex, a.y + ey);
  }
  if (roles.contains(Role.adult)) feedPlane(e.adult, a.x, a.y, e);
  if (roles.contains(Role.child)) feedPlane(e.child, c.x, c.y, e);
}
