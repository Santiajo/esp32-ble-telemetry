import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Utilidad para exportar y compartir el reporte de telemetría de una sesión.
class TelemetryExporter {
  const TelemetryExporter._();

  /// Exporta el mapa [report] a JSON con indentación y lo comparte como archivo
  /// 'balancin-telemetria.json' usando [SharePlus.instance.share].
  ///
  /// Si la plataforma no admite el diálogo de compartir, copia el JSON al portapapeles.
  static Future<bool> exportJson(Map<String, Object> report) async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(report);
    final bytes = utf8.encode(jsonStr);
    final file = XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType: 'application/json',
      name: 'balancin-telemetria.json',
    );

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: 'Telemetría de sesión Balancín',
          files: [file],
          fileNameOverrides: ['balancin-telemetria.json'],
        ),
      );
      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed;
    } catch (_) {
      // Fallback seguro: copiar texto al portapapeles
      await Clipboard.setData(ClipboardData(text: jsonStr));
      return false;
    }
  }
}
