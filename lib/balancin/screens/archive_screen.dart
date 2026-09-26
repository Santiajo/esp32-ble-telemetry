import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/archive_location.dart';
import '../platform/session_archive.dart';

/// Pantalla de archivo local de sesiones ("Sesiones guardadas").
///
/// Permite al investigador listar, exportar o eliminar las sesiones
/// registradas de forma privada y sin datos personales.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  SessionArchive? _archive;
  List<ArchivedSession>? _sessions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initArchive();
  }

  Future<void> _initArchive() async {
    _archive = await openDefaultArchive();
    await _cargarSesiones();
  }

  Future<void> _cargarSesiones() async {
    if (!mounted || _archive == null) return;
    setState(() => _loading = true);
    final list = await _archive!.list();
    if (mounted) {
      setState(() {
        _sessions = list;
        _loading = false;
      });
    }
  }

  Future<void> _compartirSesion(ArchivedSession s) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(s.file.path)],
        text: 'Telemetría Balancín · Sesión ${s.id}',
      ),
    );
  }

  Future<void> _exportarTodas() async {
    if (_sessions == null || _sessions!.isEmpty) return;
    final files = _sessions!.map((s) => XFile(s.file.path)).toList();
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        text: 'Archivo de telemetría Balancín (${files.length} sesiones)',
      ),
    );
  }

  Future<void> _borrarTodas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A29),
        title: const Text('Borrar todas las sesiones', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Estás seguro de que deseas eliminar permanentemente todas las sesiones guardadas? Esta acción no se puede deshacer.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE85E45),
              foregroundColor: Colors.white,
            ),
            child: const Text('Borrar todas'),
          ),
        ],
      ),
    );

    if (confirmar == true && _archive != null) {
      await _archive!.deleteAll();
      await _cargarSesiones();
    }
  }

  Future<void> _borrarUna(ArchivedSession s) async {
    if (_archive != null) {
      await _archive!.delete(s);
      await _cargarSesiones();
    }
  }

  String _formatFecha(DateTime dtUtc) {
    final local = dtUtc.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _formatDuracion(double s) {
    final mins = (s / 60).round();
    if (mins >= 1) return '$mins min';
    return '${s.round()} s';
  }

  @override
  Widget build(BuildContext context) {
    final hasSessions = _sessions != null && _sessions!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFEFECE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEFECE4),
        foregroundColor: const Color(0xFF2B2536),
        elevation: 0,
        title: const Text(
          'Sesiones guardadas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (hasSessions) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Exportar todas',
              onPressed: _exportarTodas,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFE85E45)),
              tooltip: 'Borrar todas',
              onPressed: _borrarTodas,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2B2536)),
                ),
              )
            : !hasSessions
                ? _buildEmptyState()
                : _buildSessionList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 40,
                color: Color(0xFF5A536B),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aún no hay sesiones guardadas.\nActiva «Sesión de estudio» en el inicio.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5A536B),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _sessions!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final s = _sessions![index];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatFecha(s.start),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF2B2536),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFECE4),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.id,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF5A536B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatDuracion(s.durationS)} de juego · ${s.childEvents} notas del niño',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF5A536B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Color(0xFF2B2536)),
                    tooltip: 'Compartir',
                    onPressed: () => _compartirSesion(s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFF5A536B), size: 20),
                    tooltip: 'Eliminar',
                    onPressed: () => _borrarUna(s),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
