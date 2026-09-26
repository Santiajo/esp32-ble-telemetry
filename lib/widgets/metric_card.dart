import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:esp32_ble_telemetry/controllers/esp_device_controller.dart';

/// Tarjeta que muestra las métricas telemétricas en tiempo real de una placa ESP32.
class MetricCard extends StatelessWidget {
  final EspDeviceController controller;

  const MetricCard({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final f = controller.fisica;
    final double velTotal = math.sqrt(f.velX * f.velX + f.velY * f.velY);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8.0),
        border: Border(
          left: BorderSide(
            color: controller.color,
            width: 4.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'ESP ${controller.etiqueta}',
                style: TextStyle(
                  color: controller.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                ),
              ),
              const Spacer(),
              Container(
                width: 8.0,
                height: 8.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: controller.conectado
                      ? controller.color
                      : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            'Acel: X ${f.accX.toStringAsFixed(2)} | Y ${f.accY.toStringAsFixed(2)} m/s²',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.0,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 3.0),
          Text(
            'Vel Total: ${velTotal.toStringAsFixed(2)} m/s',
            style: TextStyle(
              color: controller.color,
              fontSize: 13.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 3.0),
          Text(
            'Pos: X ${f.posX.toStringAsFixed(1)} | Y ${f.posY.toStringAsFixed(1)} cm',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12.0,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
