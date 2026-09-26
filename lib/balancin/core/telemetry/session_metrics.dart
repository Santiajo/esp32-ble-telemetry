/// Telemetría de sesión (plan §4.6). Solo métricas de movimiento:
/// sin audio, sin imagen, sin identificadores de dispositivo, cuenta o persona.
library;

/// Nombres de los 5 regímenes de relación, en el orden del prototipo (`REG`).
const List<String> kRegimeNames = [
  'Campo estable, articulación regular',
  'Campo en desplazamiento',
  'Campo ancho, articulación densa',
  'Campo estrecho, articulación mínima',
  'Coincidencias: timbres ocultos',
];

/// Nombres amables para el "recuerdo" del usuario final (`FR` del prototipo), con su color.
const List<({String name, int color})> kRegimeFriendly = [
  (name: 'En su ritmo', color: 0xFFB3A2DC),
  (name: 'Explorando', color: 0xFF7A8B34),
  (name: 'A todo ritmo', color: 0xFFE85E45),
  (name: 'Tranquilos', color: 0xFF7B5FCB),
  (name: '¡Coincidieron!', color: 0xFFF2E44A),
];

class SessionMetrics {
  /// Segundos de sesión (todos los estados).
  double total = 0;

  /// Segundos en ACTIVO.
  double active = 0;

  /// Segundos con el adulto moviéndose y el campo abierto (permanencia del adulto).
  double fieldOpen = 0;

  /// Número de latencias.
  int latN = 0;

  /// Duración de cada latencia (s).
  final List<double> latDur = [];

  /// Latencias que terminaron volviendo a ACTIVO.
  int resum = 0;

  /// Notas emitidas por el niño.
  int events = 0;

  /// Σ|Δcentro| (alturas recorridas por el registro).
  double variation = 0;

  /// Timbres ocultos hallados.
  int hidden = 0;

  /// Intercambios de stick (solo tablero).
  int swaps = 0;

  /// Segundos por régimen (índices de [kRegimeNames]).
  final List<double> reg = List<double>.filled(5, 0);
}

double _r1(double v) => (v * 10).round() / 10;

/// Reporte JSON con las mismas claves que `report()` del prototipo.
Map<String, Object> buildSessionReport(SessionMetrics m, DateTime start) {
  final regTotal = m.reg.fold<double>(0, (a, b) => a + b);
  final tot = regTotal == 0 ? 1.0 : regTotal;
  final latMean = m.latDur.isEmpty
      ? 0.0
      : _r1(m.latDur.fold<double>(0, (a, b) => a + b) / m.latDur.length);
  return {
    'proyecto': 'Balancín · prototipo Flutter',
    'nota': 'Solo métricas de movimiento. Sin audio, imagen ni datos identificables.',
    'inicio': start.toUtc().toIso8601String(),
    'duracion_total_s': _r1(m.total),
    'juego_activo_s': _r1(m.active),
    'campo_abierto_s': _r1(m.fieldOpen),
    'latencias': {
      'cantidad': m.latN,
      'duracion_media_s': latMean,
      'duraciones_s': [for (final v in m.latDur) _r1(v)],
    },
    'reanudaciones': m.resum,
    'eventos_nino': m.events,
    'variacion_campo_alturas': _r1(m.variation),
    'timbres_ocultos': m.hidden,
    'intercambios_stick': m.swaps,
    'regimenes': [
      for (var i = 0; i < kRegimeNames.length; i++)
        {
          'regimen': kRegimeNames[i],
          'segundos': _r1(m.reg[i]),
          'porcentaje': _r1(m.reg[i] / tot * 100),
        },
    ],
  };
}
