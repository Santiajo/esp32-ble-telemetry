import 'package:flutter/material.dart';

import '../../platform/audio_engine.dart';
import '../../platform/stick_hub.dart';
import '../../platform/telemetry_exporter.dart';
import '../../session/board_session.dart';
import '../../session/session_memory.dart';
import '../closed_screen.dart';
import 'insert_screen.dart';

/// Pantalla del Recuerdo (#resumen del prototipo web).
///
/// Presenta la experiencia vivida a la familia en un lenguaje amable,
/// sin puntajes ni juicios:
/// - Marca con las 4 formas geométricas.
/// - Título y subtítulo calculados por [SessionMemory].
/// - Cinta proporcional de regímenes de juego y su leyenda.
/// - Tres tarjetas destacadas (pausas/regresos, coincidencias, alturas recorridas).
/// - Nota filosófica de la experiencia.
/// - Opciones: "Jugar otra vez", "Guardar este recuerdo" y enlace discreto a "Detalle técnico".
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({
    super.key,
    required this.report,
    required this.audioEngine,
    required this.hub,
    this.session,
  });

  final Map<String, Object> report;
  final AudioEngine audioEngine;
  final StickHub hub;
  final BoardSession? session;

  Future<void> _exportarRecuerdo(BuildContext context) async {
    final shared = await TelemetryExporter.exportJson(report);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? 'Recuerdo de telemetría compartido con éxito'
                : 'JSON de telemetría copiado al portapapeles',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF2B2536),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mem = SessionMemory.fromReport(report);

    return Scaffold(
      backgroundColor: const Color(0xFFEFECE4),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Marca de 4 formas
                  _buildBrandHeader(),
                  const SizedBox(height: 18),

                  // Título principal
                  Text(
                    mem.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2B2536),
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtítulo
                  Text(
                    mem.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A445A),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Cinta de regímenes (.ribbon)
                  _buildRibbon(mem),
                  const SizedBox(height: 14),

                  // Leyenda de la cinta (.legend)
                  if (mem.legend.isNotEmpty) ...[
                    _buildLegend(mem),
                    const SizedBox(height: 22),
                  ] else
                    const SizedBox(height: 10),

                  // 3 Tarjetas del recuerdo (.hl .c)
                  for (final card in mem.cards) ...[
                    _buildCard(card),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),

                  // Nota final (SessionMemory.note)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      SessionMemory.note,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5A536B),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Botones de acción
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => InsertScreen(
                            audioEngine: audioEngine,
                            hub: hub,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B2536),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Jugar otra vez',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  OutlinedButton(
                    onPressed: () => _exportarRecuerdo(context),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2B2536),
                      side: const BorderSide(color: Color(0x402B2536), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Guardar este recuerdo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Enlace muy discreto: Detalle técnico
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ClosedScreen(
                              report: report,
                              session: session,
                              audioEngine: audioEngine,
                              hub: hub,
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Detalle técnico',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5A536B),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFB3A2DC),
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Color(0xFFE85E45),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Color(0xFFF2E44A),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        ClipPath(
          clipper: _TriangleClipper(),
          child: Container(
            width: 16,
            height: 16,
            color: const Color(0xFF7A8B34),
          ),
        ),
      ],
    );
  }

  Widget _buildRibbon(SessionMemory mem) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          for (final seg in mem.segments)
            Flexible(
              flex: (seg.fraction * 1000).round().clamp(1, 1000),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Color(seg.color),
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend(SessionMemory mem) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final seg in mem.segments)
          if (seg.regimeIndex >= 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(seg.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    seg.legend,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2B2536),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildCard(MemoryCard card) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildToneIcon(card.tone),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2B2536),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  card.body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A445A),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToneIcon(String tone) {
    switch (tone) {
      case 'lav':
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFB3A2DC),
            borderRadius: BorderRadius.circular(14),
          ),
        );
      case 'yel':
        return Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFF2E44A),
            shape: BoxShape.circle,
          ),
        );
      case 'oli':
        return ClipPath(
          clipper: _TriangleClipper(),
          child: Container(
            width: 48,
            height: 48,
            color: const Color(0xFF7A8B34),
          ),
        );
      case 'cor':
      default:
        return Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFE85E45),
            shape: BoxShape.circle,
          ),
        );
    }
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.04);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
