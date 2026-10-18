import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Comparte un archivo de texto (telemetría JSON o traza de un stick). Si el
/// teléfono no puede abrir el diálogo de compartir, lo copia al portapapeles.
Future<bool> shareTextFile(String name, String content, {String mimeType = 'text/plain', String? text}) async {
  final file = XFile.fromData(Uint8List.fromList(utf8.encode(content)), mimeType: mimeType, name: name);
  try {
    final r = await SharePlus.instance.share(ShareParams(text: text ?? name, files: [file], fileNameOverrides: [name]));
    return r.status != ShareResultStatus.unavailable;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: content));
    return false;
  }
}
