import 'package:flutter/material.dart';

/// Consola de recepción BLE para mensajes de depuración y tramas crudas.
class TelemetryConsole extends StatelessWidget {
  final List<String> logs;

  const TelemetryConsole({
    super.key,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      padding: const EdgeInsets.all(8.0),
      height: 110.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Consola de Recepción BLE (Raw Data)',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4.0),
          Expanded(
            child: ListView.builder(
              reverse: true, // El último mensaje abajo
              itemCount: logs.length,
              itemBuilder: (context, index) {
                // Invertido para reverse
                final mensaje = logs[logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.0),
                  child: Text(
                    '> $mensaje',
                    style: const TextStyle(
                      color: Color(0xFF00FFCC),
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
