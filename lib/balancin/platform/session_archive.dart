import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Una sesión guardada en el archivo local.
class ArchivedSession {
  const ArchivedSession({
    required this.file,
    required this.id,
    required this.start,
    required this.durationS,
    required this.childEvents,
  });

  final File file;

  /// ID aleatorio de la sesión (sin vínculo con el teléfono ni con personas).
  final String id;
  final DateTime start;
  final double durationS;
  final int childEvents;

  String get fileName => file.uri.pathSegments.last;
}

/// Archivo local de telemetría (especificación §8 y §10).
///
/// - Un archivo JSON por sesión, con un **ID aleatorio** (8 caracteres
///   hexadecimales de `Random.secure`) sin vínculo con la cuenta ni el teléfono.
/// - Contenido = el reporte de `BalancinEngine.report()` + `id_sesion`.
///   Sin audio, imagen, MAC, nombres ni identificadores de dispositivo.
/// - Todo queda en el almacenamiento privado de la app; nunca se envía a la
///   red. El investigador lo exporta a mano desde la pantalla "Sesiones guardadas".
/// - Solo se guarda cuando hay una sesión de estudio activa (la UI decide
///   si llama a [save]; ver el interruptor "Sesión de estudio" del inicio).
///
/// No depende de Flutter: recibe el directorio ya resuelto (en la app,
/// `getApplicationDocumentsDirectory()/balancin_sesiones`; en tests, un
/// directorio temporal).
class SessionArchive {
  SessionArchive(this.dir);

  final Directory dir;

  static const String folderName = 'balancin_sesiones';
  static const String _prefix = 'balancin_';

  /// ID aleatorio de 8 caracteres hexadecimales.
  static String newSessionId([math.Random? random]) {
    final r = random ?? math.Random.secure();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `balancin_20260926-154210_3fa9c01b.json` (hora UTC de inicio + ID).
  static String fileNameFor(DateTime startUtc, String id) {
    final t = startUtc.toUtc();
    final stamp = '${t.year}${_two(t.month)}${_two(t.day)}-'
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
    return '$_prefix${stamp}_$id.json';
  }

  /// Guarda el reporte de una sesión y devuelve la entrada creada.
  Future<ArchivedSession> save(
    Map<String, Object> report, {
    String? id,
    math.Random? random,
  }) async {
    final sessionId = id ?? newSessionId(random);
    final start = DateTime.tryParse('${report['inicio']}')?.toUtc() ?? DateTime.now().toUtc();
    final content = <String, Object>{'id_sesion': sessionId, ...report};
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${fileNameFor(start, sessionId)}');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(content));
    return ArchivedSession(
      file: file,
      id: sessionId,
      start: start,
      durationS: (report['duracion_total_s'] as num?)?.toDouble() ?? 0,
      childEvents: (report['eventos_nino'] as num?)?.toInt() ?? 0,
    );
  }

  /// Sesiones guardadas, de la más reciente a la más antigua. Ignora archivos
  /// ajenos o dañados.
  Future<List<ArchivedSession>> list() async {
    if (!await dir.exists()) return const [];
    final out = <ArchivedSession>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (!name.startsWith(_prefix) || !name.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await e.readAsString());
        if (data is! Map<String, dynamic>) continue;
        final id = data['id_sesion'];
        final start = DateTime.tryParse('${data['inicio']}');
        if (id is! String || start == null) continue;
        out.add(ArchivedSession(
          file: e,
          id: id,
          start: start.toUtc(),
          durationS: (data['duracion_total_s'] as num?)?.toDouble() ?? 0,
          childEvents: (data['eventos_nino'] as num?)?.toInt() ?? 0,
        ));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  Future<void> delete(ArchivedSession s) async {
    if (await s.file.exists()) await s.file.delete();
  }

  Future<void> deleteAll() async {
    for (final s in await list()) {
      await delete(s);
    }
  }
}
