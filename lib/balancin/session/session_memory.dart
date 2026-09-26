import '../core/telemetry/session_metrics.dart';

/// Un tramo de la cinta del recuerdo: fracción del tiempo en un régimen.
class MemorySegment {
  const MemorySegment({
    required this.regimeIndex,
    required this.name,
    required this.color,
    required this.fraction,
  });

  /// Índice del régimen (0–4) o -1 para la cinta vacía.
  final int regimeIndex;
  final String name;

  /// Color ARGB.
  final int color;

  /// 0–1 del ancho de la cinta.
  final double fraction;

  /// Texto de la leyenda: "Explorando · 12%".
  String get legend => '$name · ${(fraction * 100).round()}%';
}

/// Tarjeta del recuerdo.
class MemoryCard {
  const MemoryCard({required this.tone, required this.title, required this.body});

  /// 'lav' (lavanda #B3A2DC) · 'yel' (amarillo #F2E44A) · 'oli' (oliva #7A8B34), como el CSS del prototipo.
  final String tone;
  final String title;
  final String body;
}

/// Pantalla de "recuerdo" para la familia (`renderResumen()` del prototipo).
///
/// Traduce el reporte de telemetría a un lenguaje amable, sin puntajes. Dart puro.
class SessionMemory {
  SessionMemory._({
    required this.title,
    required this.subtitle,
    required this.segments,
    required this.cards,
  });

  /// Construye el recuerdo desde `BalancinEngine.report()` / `buildSessionReport`.
  ///
  /// [hintHiddenTimbre]: el prototipo sugiere en la tarjeta amarilla que
  /// "sacudir los dos sticks a la vez abre un sonido distinto". La
  /// especificación (§3.4) pide que no haya ningún indicio de los timbres
  /// ocultos. Por defecto se sigue al prototipo (decisión D1); con `false` la
  /// tarjeta no da pistas. Pendiente de validar con el autor.
  factory SessionMemory.fromReport(Map<String, Object> r, {bool hintHiddenTimbre = true}) {
    final total = (r['duracion_total_s']! as num).toDouble();
    final events = r['eventos_nino']! as int;
    final lat = r['latencias']! as Map<String, Object>;
    final pauses = lat['cantidad']! as int;
    final returns = r['reanudaciones']! as int;
    final hidden = r['timbres_ocultos']! as int;
    final variation = (r['variacion_campo_alturas']! as num).toDouble();
    final regs = (r['regimenes']! as List).cast<Map<String, Object>>();

    final mins = (total / 60).round();
    final dur = mins >= 1 ? '$mins min' : '${total.round()} s';

    final title = events > 0 ? '¡Sonaron juntos!' : 'Hoy quedó en silencio';
    final subtitle = events > 0
        ? '$dur de juego · $events notas del niño'
        : 'Faltó que los dos sticks se movieran a la vez. La próxima será.';

    final secs = [for (final g in regs) (g['segundos']! as num).toDouble()];
    final tot = secs.fold<double>(0, (a, b) => a + b);
    final segments = <MemorySegment>[];
    if (tot > 0) {
      for (var i = 0; i < secs.length && i < kRegimeFriendly.length; i++) {
        if (secs[i] <= 0) continue;
        segments.add(MemorySegment(
          regimeIndex: i,
          name: kRegimeFriendly[i].name,
          color: kRegimeFriendly[i].color,
          fraction: secs[i] / tot,
        ));
      }
    }
    if (segments.isEmpty) {
      segments.add(const MemorySegment(regimeIndex: -1, name: '', color: 0xFFEFECE4, fraction: 1));
    }

    String plural(int n, String one, String many) => n == 1 ? one : many;

    final cards = <MemoryCard>[
      MemoryCard(
        tone: 'lav',
        title: '$pauses ${plural(pauses, 'pausa', 'pausas')}, $returns ${plural(returns, 'regreso', 'regresos')}',
        body: 'Se detuvieron y volvieron a encontrarse.',
      ),
      MemoryCard(
        tone: 'yel',
        title: hidden > 0
            ? '$hidden ${plural(hidden, 'vez', 'veces')} sacudieron a la vez'
            : 'Ninguna coincidencia todavía',
        body: hidden > 0
            ? 'Solo pasa cuando los dos lo hacen juntos.'
            : (hintHiddenTimbre
                ? 'Sacudir los dos sticks a la vez abre un sonido distinto.'
                : 'Hay sonidos que solo aparecen cuando los dos se buscan.'),
      ),
      MemoryCard(
        tone: 'oli',
        title: '${variation.round()} alturas recorridas',
        body: 'De lo grave a lo agudo y de vuelta, guiados por el adulto.',
      ),
    ];

    return SessionMemory._(title: title, subtitle: subtitle, segments: segments, cards: cards);
  }

  final String title;
  final String subtitle;

  /// Cinta proporcional al tiempo en cada régimen (solo los que ocurrieron).
  final List<MemorySegment> segments;

  /// Leyenda de la cinta (vacía si no hubo juego activo).
  List<String> get legend => [for (final s in segments) if (s.regimeIndex >= 0) s.legend];

  /// Tres tarjetas: pausas/regresos, coincidencias, alturas recorridas.
  final List<MemoryCard> cards;

  /// Nota final (igual en todas las sesiones).
  static const String note =
      'No hay puntaje: una tarde calma vale tanto como una intensa. Lo que cambia es el paisaje que sonaron.';
}
