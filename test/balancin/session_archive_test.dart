import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:esp32_ble_telemetry/balancin/core/telemetry/session_metrics.dart';
import 'package:esp32_ble_telemetry/balancin/platform/session_archive.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> reportAt(DateTime start, {double total = 60, int events = 10}) {
  final m = SessionMetrics()
    ..total = total
    ..events = events;
  return buildSessionReport(m, start);
}

void main() {
  late Directory tmp;
  late SessionArchive archive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('balancin_archive_test');
    archive = SessionArchive(Directory('${tmp.path}/${SessionArchive.folderName}'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('ID aleatorio de 8 caracteres hexadecimales', () {
    final id = SessionArchive.newSessionId(math.Random(7));
    expect(id, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(SessionArchive.newSessionId(), isNot(SessionArchive.newSessionId()));
  });

  test('nombre de archivo con hora UTC de inicio e ID', () {
    final name = SessionArchive.fileNameFor(DateTime.utc(2026, 9, 26, 15, 42, 10), '3fa9c01b');
    expect(name, 'balancin_20260926-154210_3fa9c01b.json');
  });

  test('guarda el reporte con id_sesion y sin identificadores', () async {
    final s = await archive.save(reportAt(DateTime.utc(2026, 9, 26, 10)), id: 'abcdef01');
    expect(await s.file.exists(), isTrue);
    final data = jsonDecode(await s.file.readAsString()) as Map<String, dynamic>;
    expect(data['id_sesion'], 'abcdef01');
    expect(data['eventos_nino'], 10);
    final flat = jsonEncode(data).toLowerCase();
    for (final banned in ['mac', 'device', 'dispositivo', 'email', 'nombre', 'audio_', 'imagen_']) {
      expect(flat.contains(banned), isFalse, reason: 'no debe incluir "$banned"');
    }
  });

  test('lista de la más reciente a la más antigua e ignora archivos ajenos', () async {
    await archive.save(reportAt(DateTime.utc(2026, 9, 25, 10)), id: '00000001');
    await archive.save(reportAt(DateTime.utc(2026, 9, 26, 10), total: 120, events: 50), id: '00000002');
    await File('${archive.dir.path}/otra_cosa.txt').writeAsString('x');
    await File('${archive.dir.path}/balancin_roto.json').writeAsString('{no es json');

    final list = await archive.list();
    expect(list.map((s) => s.id), ['00000002', '00000001']);
    expect(list.first.durationS, 120);
    expect(list.first.childEvents, 50);
  });

  test('lista vacía si todavía no hay carpeta', () async {
    expect(await archive.list(), isEmpty);
  });

  test('borrar una y borrar todas', () async {
    final a = await archive.save(reportAt(DateTime.utc(2026, 9, 25)), id: 'aaaaaaaa');
    await archive.save(reportAt(DateTime.utc(2026, 9, 26)), id: 'bbbbbbbb');
    await archive.delete(a);
    expect((await archive.list()).map((s) => s.id), ['bbbbbbbb']);
    await archive.deleteAll();
    expect(await archive.list(), isEmpty);
  });
}
