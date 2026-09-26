import 'package:flutter/material.dart';

import '../platform/audio_engine.dart';
import '../platform/telemetry_exporter.dart';
import '../session/board_session.dart';
import 'board_screen.dart';

/// Pantalla de cierre de sesión (`#closed` del prototipo).
///
/// Muestra los resultados de la sesión recién terminada:
/// - Tarjetas de telemetría agregada (`summaryCards`).
/// - Distribución porcentual entre los 5 regímenes de interacción (`regimeBars`).
/// - Opciones para iniciar una "Nueva sesión" o "Exportar telemetría (JSON)".
class ClosedScreen extends StatelessWidget {
  const ClosedScreen({
    super.key,
    required this.session,
    required this.audioEngine,
  });

  final BoardSession session;
  final AudioEngine audioEngine;

  static const List<Color> _regimeColors = [
    Color(0xFF7B5FCB), // 1: Campo estable (violeta)
    Color(0xFF7A8B34), // 2: Campo en desplazamiento (oliva)
    Color(0xFFE85E45), // 3: Campo ancho, denso (coral)
    Color(0xFFB3A2DC), // 4: Campo estrecho, mínimo (lavanda)
    Color(0xFFF2E44A), // 5: Coincidencias / oculto (amarillo)
  ];

  Future<void> _exportar(BuildContext context) async {
    final report = session.report();
    final shared = await TelemetryExporter.exportJson(report);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? 'Telemetría compartida con éxito'
                : 'JSON de telemetría copiado al portapapeles',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF2B2536),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _nuevaSesion(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BoardScreen(audioEngine: audioEngine),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaryCards = session.summaryCards;
    final regimeBars = session.regimeBars;

    return Scaffold(
      backgroundColor: const Color(0xFFEFECE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEFECE4),
        foregroundColor: const Color(0xFF2B2536),
        elevation: 0,
        title: const Text(
          'Balancín',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Título principal
                  const Text(
                    'Sesión cerrada',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2B2536),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'El instrumento sonó una resonancia final y guardó la telemetría '
                    'de movimiento. No se registró audio, imagen ni datos identificables.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF4A445A),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Grilla de tarjetas de resumen (10 tarjetas)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth > 500 ? 5 : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 88,
                        ),
                        itemCount: summaryCards.length,
                        itemBuilder: (context, index) {
                          final card = summaryCards[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  card.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2B2536),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  card.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A536B),
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Sección: Distribución entre regímenes de relación
                  const Text(
                    'Distribución del tiempo entre regímenes de relación',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2B2536),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Barras de regímenes
                  for (var i = 0; i < regimeBars.length; i++) ...[
                    _RegimeBarRow(
                      name: regimeBars[i].name,
                      percent: regimeBars[i].percent,
                      color: _regimeColors[i % _regimeColors.length],
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),

                  // Nota reflexiva del prototipo
                  const Text(
                    'Descripción de la escena, no puntaje: una sesión calma no es '
                    'peor que una densa, sino distinta. La variedad es en sí misma un '
                    'indicador de exploración.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5A536B),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Botones de acción
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton(
                        onPressed: () => _nuevaSesion(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2B2536),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                          minimumSize: const Size(160, 52),
                        ),
                        child: const Text(
                          'Nueva sesión',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _exportar(context),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF2B2536),
                          side: const BorderSide(
                            color: Color(0x402B2536),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          minimumSize: const Size(180, 52),
                        ),
                        child: const Text(
                          'Exportar telemetría (JSON)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegimeBarRow extends StatelessWidget {
  const _RegimeBarRow({
    required this.name,
    required this.percent,
    required this.color,
  });

  final String name;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clampedPct = percent.clamp(0.0, 100.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2B2536),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fillWidth = constraints.maxWidth * (clampedPct / 100.0);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: fillWidth,
                        color: color,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 55,
          child: Text(
            '${clampedPct.toStringAsFixed(0)} %',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2B2536),
            ),
          ),
        ),
      ],
    );
  }
}
