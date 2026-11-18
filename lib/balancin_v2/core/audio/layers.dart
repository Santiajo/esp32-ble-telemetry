/// Audio en tres capas de la mecánica v2 (plan v2 §4.6; `audioUpdate`, `vInit`,
/// `detune`, `loopStart` y `vSilence` del prototipo).
///
///   1. Voz del adulto: seno en la altura del adulto + 2.º armónico (0,22).
///   2. Tono de relación: dos senos en 2·fa y 2·fa + desafinación (batido) y
///      una quinta (3·fa) solo cuando la desafinación es 0.
///   3. Notas del niño (marimba), una por celda nueva del plano. Si la nota nueva
///      queda a más de un paso de la anterior, se recorre la escala hasta ella
///      con notas de paso rápidas y más suaves (§12.4), en vez de saltar.
/// Más el pad que repite cada 420 ms las notas de las frases ganadas.
///
/// §15 (para jugar sin vista, apagado por defecto): el niño puede usar la
/// escala del adulto una octava arriba ([SyncParams.sharedScale]), el lado puede
/// cambiar el timbre ([SyncParams.sideTimbre]) y la quinta puede aparecer de a
/// poco al acercarse ([SyncParams.fifthRamp]).
///
/// Dart puro. Las voces continuas son valores que se acercan a su objetivo con
/// la misma curva que `setTargetAtTime` de Web Audio; el motor de plataforma
/// los lee en cada cuadro ([voices]) y los pasa a SoLoud. Las notas sueltas
/// salen como [NoteCmd].
library;

import 'dart:math' as math;

import '../levels.dart';
import '../params.dart';
import '../sync_engine.dart';
import '../telemetry.dart' show jsRound;
import 'eq.dart';
import 'synth_v2.dart';

/// Valor con objetivo y constante de tiempo, como `AudioParam.setTargetAtTime`.
class Glide {
  Glide(this.value) : target = value;
  double value;
  double target;
  double tau = 0.05; // s

  void setTarget(double v, double tauS) {
    target = v;
    tau = tauS;
  }

  void step(double dt) {
    if (dt <= 0) return;
    value = target + (value - target) * math.exp(-dt / tau);
  }
}

/// [glock] = nota del niño a la derecha con [SyncParams.sideTimbre] (§15).
enum NoteFamily { marimba, pad, glock }

/// Escala del niño: la propia (do4–do6) o, con [SyncParams.sharedScale], la del
/// adulto una octava arriba (do4–sol5): a la misma altura, la misma nota.
List<int> childScaleFor(SyncParams p) => p.sharedScale > 0 ? sharedChildScale : childScale;

const List<int> sharedChildScale = [60, 62, 64, 67, 69, 72, 74, 76, 79];

/// Nota suelta. [gain] es la del prototipo (la polifonía la aplica la plataforma).
/// [at] puede quedar en el futuro (notas de paso): la plataforma la agenda.
class NoteCmd {
  const NoteCmd(this.at, this.midi, this.family, this.gain, {this.passing = false});
  final double at; // ms
  final bool passing;
  final int midi;
  final NoteFamily family;
  final double gain;
  @override
  String toString() => 'note(${family.name} $midi ${gain.toStringAsFixed(3)})';
}

/// Una voz continua lista para la plataforma: frecuencia (Hz) y amplitud final
/// (incluye la EQ en esa frecuencia).
class VoiceLevel {
  const VoiceLevel(this.hz, this.amp);
  final double hz, amp;
}

class AudioLayers {
  static const double padPeriodMs = 420;

  // Voz del adulto
  final Glide adultHz = Glide(130);
  final Glide adultHarmHz = Glide(260);
  final Glide adultGain = Glide(0);

  /// Ganancia del 2.º armónico del adulto (0,22; con [SyncParams.sideTimbre] va de 0,06 a 0,5 según el lado).
  final Glide adultHarmGain = Glide(0.22);
  // Tono de relación
  final Glide rel1Hz = Glide(260);
  final Glide rel2Hz = Glide(260);
  final Glide fifthHz = Glide(390);
  final Glide relGain = Glide(0);
  final Glide fifthGain = Glide(0);
  double df = 0; // desafinación suavizada (Hz)

  /// Desafinación objetivo del último cuadro (Hz). 0 = afinado.
  double detuneTarget = 0;

  // Notas del niño
  String _cell = '';
  double _lastNote = 0;
  int? _lastChildIdx;

  // Pad
  double _nextPad = double.infinity;
  int _padI = 0;

  /// Reinicio de los sticks (inicio de sesión o reanudación): olvida la celda del niño.
  void resetChild() {
    _cell = '';
    _lastNote = 0;
    _lastChildIdx = null;
  }

  /// `loopStart`: el pad empieza a contar desde [now].
  void startPad(double now) {
    _nextPad = now + padPeriodMs;
    _padI = 0;
  }

  void stopPad() => _nextPad = double.infinity;

  /// Dispara el pad si toca. Llamar ANTES de `engine.tick` (en el prototipo es un
  /// `setInterval` que corre antes del cuadro). [progress] = niveles ya ganados.
  List<NoteCmd> firePad(double now, SyncEngine e, List<int> progress) {
    final out = <NoteCmd>[];
    while (_nextPad <= now) {
      _nextPad += padPeriodMs;
      if (!e.running || e.mode != PlayMode.levels || e.state != EngineState.playing) continue;
      final notes = <int>[for (final l in levels) if (progress.contains(l.id)) ...l.phraseMidi];
      if (notes.isEmpty) continue;
      out.add(NoteCmd(now, notes[_padI++ % notes.length], NoteFamily.pad, 0.03 + 0.004 * progress.length));
    }
    return out;
  }

  /// `detune(d, tol)`.
  static double detune(double d, double tol, double maxDetune) {
    if (d <= tol) return 0;
    final t = ((d - tol) / (6 - tol)).clamp(0.0, 1.0);
    return 0.5 + (maxDetune - 0.5) * t;
  }

  /// `audioUpdate`: fija los objetivos de las voces y devuelve las notas del niño.
  /// Llamar después de `engine.tick`, solo si el motor sigue corriendo.
  List<NoteCmd> update(double now, double dt, SyncEngine e) {
    final out = <NoteCmd>[];
    final live = e.state == EngineState.playing || e.state == EngineState.calibrating;
    final aA = e.adultActive, cA = e.childActive, both = aA && cA, tol = e.tol;
    final ai = jsRound((e.adult.pos.y + 6) / 12 * (adultScale.length - 1)).toInt().clamp(0, adultScale.length - 1);
    final fa = midiHz(adultScale[ai]);
    adultHz.setTarget(fa, 0.05);
    adultHarmHz.setTarget(fa * 2, 0.05);
    final aOn = live && aA;
    adultGain.setTarget(aOn ? 0.12 : 0, aOn ? 0.1 : 0.5);
    final side = e.params.sideTimbre > 0;
    adultHarmGain.setTarget(side ? 0.06 + 0.44 * ((e.adult.pos.x + 6) / 12).clamp(0.0, 1.0) : 0.22, 0.1);
    final det = detune(e.d, tol, e.params.maxDetune);
    detuneTarget = det;
    df += (det - df) * math.min(1, dt * 3);
    rel1Hz.setTarget(2 * fa, 0.05);
    rel2Hz.setTarget(2 * fa + df, 0.05);
    fifthHz.setTarget(3 * fa, 0.05);
    final rOn = e.state == EngineState.playing && both;
    relGain.setTarget(rOn ? 0.045 : 0, 0.15);
    fifthGain.setTarget(rOn ? 0.022 * fifthLevel(e.d, tol, det, ramp: e.params.fifthRamp > 0) : 0, 0.2);
    if (live && cA) {
      final c = e.child.pos;
      final cell = '${jsRound(c.x).toInt()},${jsRound(c.y).toInt()}';
      if (cell != _cell && now - _lastNote > 100) {
        _cell = cell;
        _lastNote = now;
        final scale = childScaleFor(e.params);
        final ci = jsRound((c.y + 6) / 12 * (scale.length - 1)).toInt().clamp(0, scale.length - 1);
        final gain = (0.08 + e.child.speed / 45).clamp(0.08, 0.22).toDouble();
        final family = side && c.x > 0 ? NoteFamily.glock : NoteFamily.marimba;
        out.addAll(childRun(now, _lastChildIdx, ci, gain, e.params.runMaxNotes.round(), e.params.runMs, e.params.runGain,
            scale: scale, family: family));
        _lastChildIdx = ci;
      }
    }
    return out;
  }

  /// §12.4: notas para ir de [from] a [to] (índices de [childScale]). Si están a
  /// más de un paso y [maxNotes] > 0, agrega notas de paso intermedias (como
  /// mucho [maxNotes], repartidas parejo) en [runMs] ms en total, con volumen
  /// `gain·runGain`; la nota de llegada suena al final con su volumen normal.
  static List<NoteCmd> childRun(double now, int? from, int to, double gain, int maxNotes, double runMs, double runGain,
      {List<int> scale = childScale, NoteFamily family = NoteFamily.marimba}) {
    if (from != null && from >= scale.length) from = scale.length - 1; // cambió la escala a mitad de juego
    if (from == null || maxNotes <= 0 || (to - from).abs() <= 1) {
      return [NoteCmd(now, scale[to], family, gain)];
    }
    final dir = to > from ? 1 : -1;
    var passing = [for (var i = from + dir; i != to; i += dir) i];
    if (passing.length > maxNotes) {
      final n = passing.length;
      passing = [for (var k = 0; k < maxNotes; k++) passing[((k + 1) * n / (maxNotes + 1)).floor()]];
    }
    final total = passing.length + 1;
    final step = runMs / total;
    return [
      for (var k = 0; k < passing.length; k++)
        NoteCmd(now + k * step, scale[passing[k]], family, gain * runGain, passing: true),
      NoteCmd(now + passing.length * step, scale[to], family, gain),
    ];
  }

  /// Nivel de la quinta (0–1). Prototipo: 1 solo afinado (`det == 0`). Con
  /// [ramp] (§15) sube de a poco entre `2·tol` y `tol`, para oír que se acercan.
  static double fifthLevel(double d, double tol, double det, {required bool ramp}) {
    if (!ramp) return det == 0 ? 1 : 0;
    return ((2 * tol - d) / tol).clamp(0.0, 1.0).toDouble();
  }

  /// `vSilence`: todas las voces continuas a 0 (τ 0,3 s). Al cerrar o perder un stick.
  void silence() {
    adultGain.setTarget(0, 0.3);
    relGain.setTarget(0, 0.3);
    fifthGain.setTarget(0, 0.3);
  }

  /// Voces continuas a 0 de inmediato, para cuando ya nadie va a seguir avanzando las
  /// curvas: al salir de una pantalla, [silence] y un solo paso dejaban ~37 % sonando.
  void mute() {
    for (final g in [adultGain, relGain, fifthGain]) {
      g
        ..value = 0
        ..target = 0;
    }
  }

  /// Avanza las curvas [dt] segundos (la plataforma lo llama en cada cuadro).
  void advance(double dt) {
    for (final g in [adultHz, adultHarmHz, adultGain, adultHarmGain, rel1Hz, rel2Hz, fifthHz, relGain, fifthGain]) {
      g.step(dt);
    }
  }

  /// Las 5 voces continuas: fundamental y armónico del adulto, los dos senos del
  /// batido y la quinta. Amplitudes con la EQ incorporada.
  List<VoiceLevel> get voices => [
        VoiceLevel(adultHz.value, adultGain.value * eqGain(adultHz.value)),
        VoiceLevel(adultHarmHz.value, adultGain.value * adultHarmGain.value * eqGain(adultHarmHz.value)),
        VoiceLevel(rel1Hz.value, relGain.value * eqGain(rel1Hz.value)),
        VoiceLevel(rel2Hz.value, relGain.value * eqGain(rel2Hz.value)),
        VoiceLevel(fifthHz.value, fifthGain.value * eqGain(fifthHz.value)),
      ];
}
