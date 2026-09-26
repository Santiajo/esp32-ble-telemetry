import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'session_archive.dart';

/// Abre la instancia por defecto de [SessionArchive] en el almacenamiento
/// de documentos de la aplicación.
Future<SessionArchive> openDefaultArchive() async {
  final appDir = await getApplicationDocumentsDirectory();
  final targetDir = Directory('${appDir.path}${Platform.pathSeparator}${SessionArchive.folderName}');
  return SessionArchive(targetDir);
}
