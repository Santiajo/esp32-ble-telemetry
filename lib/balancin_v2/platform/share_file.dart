import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Comparte un archivo de texto (telemetría JSON o traza de un stick). Si el
/// teléfono no puede abrir el diálogo de compartir, lo copia al portapapeles.
///
/// Antes guarda una copia en la carpeta de la app en el almacenamiento externo
/// (`Android/data/<app>/files/registros/`), que se puede bajar con
/// `adb pull` sin compartir nada (18-11-2026).
Future<bool> shareTextFile(String name, String content, {String mimeType = 'text/plain', String? text}) async {
  await saveLocalCopy(name, content);
  final file = XFile.fromData(Uint8List.fromList(utf8.encode(content)), mimeType: mimeType, name: name);
  try {
    final r = await SharePlus.instance.share(ShareParams(text: text ?? name, files: [file], fileNameOverrides: [name]));
    return r.status != ShareResultStatus.unavailable;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: content));
    return false;
  }
}

/// Guarda [content] en `registros/[name]` dentro de la carpeta externa de la app.
/// Devuelve la ruta, o null si no se pudo (sin almacenamiento externo, en tests…).
Future<String?> saveLocalCopy(String name, String content) async {
  try {
    final base = await getExternalStorageDirectory();
    if (base == null) return null;
    final dir = Directory('${base.path}/registros');
    await dir.create(recursive: true);
    final f = File('${dir.path}/$name');
    await f.writeAsString(content, flush: true);
    return f.path;
  } catch (_) {
    return null;
  }
}
