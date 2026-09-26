/// Protocolo BLE v2 del stick (plan §3):
///   `v2,<t_ms>,<ax>,<ay>,<az>,<gx>,<gy>,<gz>`
/// Enteros crudos del MPU6050: acelerómetro ±8 g, giroscopio ±1000 °/s.
library;

class ImuSample {
  const ImuSample({
    required this.tMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  /// `time.ticks_ms()` del ESP32 (módulo 2^30). Usar [ImuFrameParser.ticksDiff].
  final int tMs;
  final int ax, ay, az;
  final int gx, gy, gz;

  /// Aceleración en g.
  double get axG => ax / ImuFrameParser.accelLsbPerG;
  double get ayG => ay / ImuFrameParser.accelLsbPerG;
  double get azG => az / ImuFrameParser.accelLsbPerG;

  /// Velocidad angular en °/s (sin corregir el bias).
  double get gxDps => gx / ImuFrameParser.gyroLsbPerDps;
  double get gyDps => gy / ImuFrameParser.gyroLsbPerDps;
  double get gzDps => gz / ImuFrameParser.gyroLsbPerDps;

  @override
  String toString() => 'v2,$tMs,$ax,$ay,$az,$gx,$gy,$gz';
}

abstract final class ImuFrameParser {
  static const double accelLsbPerG = 4096; // ±8 g
  static const double gyroLsbPerDps = 32.8; // ±1000 °/s
  static const int ticksPeriod = 1 << 30; // MicroPython ticks_ms en ESP32

  /// Parsea una línea v2 (sin el '\n'). Devuelve null si no es una línea v2
  /// válida: prefijo distinto, cantidad de campos distinta de 8 (p. ej. una
  /// línea mezclada tras perder un trozo BLE) o algún campo no numérico.
  static ImuSample? parse(String line) {
    final p = line.trim().split(',');
    if (p.length != 8 || p[0] != 'v2') return null;
    final v = List<int?>.generate(7, (i) => int.tryParse(p[i + 1]));
    if (v.any((e) => e == null)) return null;
    final t = v[0]!;
    if (t < 0 || t >= ticksPeriod) return null;
    for (var i = 1; i < 7; i++) {
      if (v[i]! < -32768 || v[i]! > 32767) return null;
    }
    return ImuSample(
      tMs: t,
      ax: v[1]!,
      ay: v[2]!,
      az: v[3]!,
      gx: v[4]!,
      gy: v[5]!,
      gz: v[6]!,
    );
  }

  /// `true` si la línea parece del protocolo v2 (para enrutar entre v2 y el formato legado).
  static bool isV2(String line) => line.trimLeft().startsWith('v2,');

  /// Diferencia `a - b` en ms con vuelta de reloj, como `time.ticks_diff` de MicroPython.
  static int ticksDiff(int a, int b) {
    const half = ticksPeriod ~/ 2;
    return ((a - b + half) % ticksPeriod) - half;
  }
}
