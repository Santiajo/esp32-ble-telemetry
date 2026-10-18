/// Trazas grabadas de un stick (plan v2, fase 2): convierten pruebas reales en tests.
///
/// Formato de texto, una muestra por línea:
///   `<llegada_ms>\t<línea v2>`
/// donde `llegada_ms` es la hora de llegada en el reloj del teléfono (con
/// decimales) y la línea v2 es la que envió el firmware, sin cambios. Las
/// líneas que empiezan con `#` son comentarios (rol, MAC abreviada, fecha).
library;

import '../../../balancin/core/ble/imu_frame_parser.dart';

class TraceSample {
  const TraceSample(this.arrivalMs, this.sample);
  final double arrivalMs;
  final ImuSample sample;
}

abstract final class ImuTrace {
  static String encodeLine(double arrivalMs, ImuSample s) => '${arrivalMs.toStringAsFixed(1)}\t$s';

  static String encode(Iterable<TraceSample> samples, {List<String> comments = const []}) {
    final b = StringBuffer();
    for (final c in comments) {
      b.writeln('# $c');
    }
    for (final t in samples) {
      b.writeln(encodeLine(t.arrivalMs, t.sample));
    }
    return b.toString();
  }

  /// Ignora comentarios, líneas vacías y líneas dañadas.
  static List<TraceSample> decode(String text) {
    final out = <TraceSample>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final at = double.tryParse(line.substring(0, tab));
      final s = ImuFrameParser.parse(line.substring(tab + 1));
      if (at == null || s == null) continue;
      out.add(TraceSample(at, s));
    }
    return out;
  }
}
