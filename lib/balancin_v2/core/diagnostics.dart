/// Datos de una prueba con usuarios (plan v2 §17): lo que el video no muestra.
///
/// Un archivo JSON con la versión, los parámetros, el resultado y las trazas
/// crudas de los sticks ([ImuTrace]), para reproducir aquí lo que pasó en el
/// teléfono. Solo trae movimiento: ni audio, ni imagen, ni nombres.
library;

import 'dart:convert';

import 'params.dart';

/// Versión de la app; una prueba comprueba que coincide con `pubspec.yaml`.
const String appVersion = '2.0.0-dev.21';

String diagnosticJson({
  required String kind,
  required DateTime when,
  required SyncParams params,
  required Map<String, Object?> data,
  required Map<String, String> traces,
}) =>
    jsonEncode({
      'tipo': kind,
      'version': appVersion,
      'fecha': when.toIso8601String(),
      'parametros': params.toJson(),
      'datos': data,
      'trazas': traces,
    });

/// `20261105-2157`, para los nombres de archivo.
String diagnosticStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
}
