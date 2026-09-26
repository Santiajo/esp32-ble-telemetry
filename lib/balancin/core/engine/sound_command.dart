/// Comandos de sonido que emite el motor. El motor no toca audio:
/// la capa de plataforma (AudioEngine) los interpreta. Así el motor es testeable.
library;

/// Familias tímbricas (plan §4.7).
enum TimbreFamily { marimba, mixta, glock, oculto }

sealed class SoundCommand {
  const SoundCommand();
}

/// Nota del niño, cuantizada al campo.
final class NoteOn extends SoundCommand {
  const NoteOn({
    required this.index,
    required this.midi,
    required this.family,
    required this.gain,
    required this.hidden,
    required this.fieldLo,
    required this.fieldCount,
  });

  /// Índice en la escala de 25 alturas (0–24).
  final int index;
  final int midi;
  final TimbreFamily family;

  /// Ganancia lineal de la nota (0–0,3).
  final double gain;

  /// Sonó con timbre oculto activo.
  final bool hidden;

  /// Campo vigente al emitir la nota (para destellos en UI y para tests).
  final int fieldLo;
  final int fieldCount;

  @override
  String toString() => 'NoteOn(idx=$index, midi=$midi, $family, gain=${gain.toStringAsFixed(3)})';
}

/// Resonancia de apertura del campo (entrada en ESPERA): MIDI 48, 55, 60.
final class OpeningSound extends SoundCommand {
  const OpeningSound();
}

/// Resonancia del campo abierto al detenerse el niño (entrada en LAT_N).
final class FieldResonance extends SoundCommand {
  const FieldResonance({required this.lo, required this.count, required this.family});
  final int lo;
  final int count;
  final TimbreFamily family;
}

/// Resonancia final al cerrar la sesión: MIDI 48, 52, 55.
final class FinalSound extends SoundCommand {
  const FinalSound();
}

/// Rampa lineal de la ganancia del bus (pérdida de stick / reanudación).
final class BusFade extends SoundCommand {
  const BusFade({required this.to, required this.seconds, this.from});

  /// Si no es null, la ganancia salta primero a este valor.
  final double? from;
  final double to;
  final double seconds;
}
