/// Luz en dos mitades (plan v2 §4.7; `lightUpdate` del prototipo).
///
/// Arriba el adulto (lila), abajo el niño (coral). Las dos se funden hacia
/// oliva a medida que `d` baja, y laten cuando están en sincronía.
library;

import 'dart:math' as math;

import 'levels.dart';
import 'stick_state.dart';
import 'sync_engine.dart';

class Rgb {
  const Rgb(this.r, this.g, this.b);
  final int r, g, b;

  @override
  bool operator ==(Object other) => other is Rgb && other.r == r && other.g == g && other.b == b;
  @override
  int get hashCode => Object.hash(r, g, b);
  @override
  String toString() => 'rgb($r,$g,$b)';
}

const Rgb lightAdult = Rgb(179, 162, 220);
const Rgb lightChild = Rgb(232, 94, 69);
const Rgb lightOlive = Rgb(143, 163, 62);

int _jsRound(double v) => (v + 0.5).floor();

Rgb mixRgb(Rgb p, Rgb q, double t) => Rgb(
      _jsRound(p.r + (q.r - p.r) * t),
      _jsRound(p.g + (q.g - p.g) * t),
      _jsRound(p.b + (q.b - p.b) * t),
    );

class LightFrame {
  const LightFrame({required this.top, required this.bottom, required this.topOpacity, required this.bottomOpacity, required this.blend});

  final Rgb top, bottom;
  final double topOpacity, bottomOpacity;

  /// 0 = colores propios · 1 = las dos en oliva.
  final double blend;
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

LightFrame lightFrame(SyncEngine e, double now) {
  final both = e.bothActive, tol = e.tol;
  final playing = e.state == EngineState.playing;
  final songDone = e.state == EngineState.songComplete;
  final s = playing && both ? _clamp01(1 - e.d / (2 * tol)) : (songDone ? 1.0 : 0.0);
  var beat = 1.0;
  if (e.inSync && both && playing) {
    var f = 1.0;
    if (e.relation == Relation.pulse) {
      f = e.adult.rhythm(now, e.params).f;
      if (f == 0) f = 1;
    }
    beat = 0.72 + 0.28 * math.sin(2 * math.pi * f * now / 1000);
  }
  if (e.calibrating) beat = 0.65 + 0.25 * math.sin(now / 400);
  double lvl(StickState st, bool act) {
    if (act) return (0.5 + st.speed / 14).clamp(0.5, 1.0).toDouble();
    return songDone ? 0.8 : 0.14;
  }

  return LightFrame(
    top: mixRgb(lightAdult, lightOlive, s),
    bottom: mixRgb(lightChild, lightOlive, s),
    topOpacity: lvl(e.adult, e.adultActive) * beat,
    bottomOpacity: lvl(e.child, e.childActive) * beat,
    blend: s,
  );
}
