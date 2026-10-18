/// Telemetría por nivel, reporte JSON y registro de sesión (plan v2 §4.8).
///
/// Mismas claves que `report()` y `sessionRecord()` del prototipo. Anónima:
/// solo movimiento, sin audio, imagen ni datos de personas o dispositivos.
library;

/// `Math.round` de JavaScript (las mitades redondean hacia +∞).
double jsRound(double v) => (v + 0.5).floorToDouble();

/// `+v.toFixed(d)` de JavaScript.
double toFixedNum(double v, int d) => double.parse(v.toStringAsFixed(d));

class LevelTelemetry {
  LevelTelemetry(this.nivel, this.inicio);

  /// Número de nivel, o `'libre'`.
  final Object nivel;

  /// Segundos desde el inicio de la sesión.
  final double inicio;

  double? primera; // s hasta la primera sincronía
  double juego = 0; // s jugando
  double sinc = 0; // s en sincronía con los dos activos
  double dS = 0; // suma de d
  int dN = 0;
  double lagS = 0; // suma de retrasos medidos
  int lagN = 0;
  int adultoSigue = 0; // mediciones con el adulto detrás
  int pausas = 0;
  int reanud = 0;
  int salidas = 0; // veces que, moviéndose los dos, salieron de la sincronía (§12)
  double? completado; // s para completar

  bool get isFree => nivel == 'libre';

  double get syncPercent => juego > 0 ? sinc / juego * 100 : 0;

  double? get dMean => dN > 0 ? dS / dN : null;

  Map<String, Object?> toReportJson() => {
        'nivel': nivel,
        'tiempo_a_primera_sincronia_s': primera,
        'porcentaje_en_sincronia': juego > 0 ? toFixedNum(sinc / juego * 100, 1) : 0,
        'd_promedio': dN > 0 ? toFixedNum(dS / dN, 2) : null,
        'retraso_promedio_s': lagN > 0 ? toFixedNum(lagS / lagN, 2) : null,
        'porcentaje_adulto_sigue_al_nino': lagN > 0 ? jsRound(adultoSigue / lagN * 100).toInt() : null,
        'pausas': pausas,
        'reanudaciones': reanud,
        'salidas_de_sincronia': salidas,
        'tiempo_para_completar_s': completado,
      };
}

/// Lo que se guarda de cada sesión para «Sesiones pasadas» y el recuerdo.
class SessionRecord {
  const SessionRecord({
    required this.t,
    required this.mode,
    required this.levels,
    required this.dur,
    required this.sync,
    required this.song,
    required this.lead,
    required this.traj,
  });

  /// Fin de la sesión (ms desde epoch).
  final int t;

  /// `'levels'` o `'free'`.
  final String mode;
  final List<int> levels;
  final double dur; // s
  final double sync; // 0–1
  final bool song;

  /// Retraso medio (s); > 0 = el niño siguió al adulto. `null` sin datos.
  final double? lead;

  /// `[adulto x, adulto y, niño x, niño y]` cada 100 ms, ≤ 300 puntos.
  final List<List<double>> traj;

  bool get isFree => mode == 'free';

  Map<String, Object?> toJson() => {
        't': t,
        'mode': mode,
        'levels': levels,
        'dur': dur,
        'sync': sync,
        'song': song,
        'lead': lead,
        'traj': traj,
      };

  factory SessionRecord.fromJson(Map<String, Object?> j) => SessionRecord(
        t: (j['t'] as num).toInt(),
        mode: j['mode'] as String,
        levels: [for (final v in j['levels'] as List) (v as num).toInt()],
        dur: (j['dur'] as num).toDouble(),
        sync: (j['sync'] as num).toDouble(),
        song: j['song'] as bool? ?? false,
        lead: (j['lead'] as num?)?.toDouble(),
        traj: [
          for (final p in j['traj'] as List) [for (final v in p as List) (v as num).toDouble()]
        ],
      );
}
