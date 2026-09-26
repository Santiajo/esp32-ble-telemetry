import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controllers/esp_device_controller.dart';

/// Modal de escaneo BLE para emparejar un dispositivo ESP / Balancín.
///
/// Si se provee [preferredNames], los dispositivos cuyo nombre comience con alguno
/// de ellos se ordenan al inicio y se resaltan con la etiqueta "RECOMENDADO".
class BleScanModal extends StatefulWidget {
  const BleScanModal({
    super.key,
    required this.controller,
    required this.onSeleccionado,
    this.preferredNames,
  });

  final EspDeviceController controller;
  final ValueChanged<BluetoothDevice> onSeleccionado;
  final List<String>? preferredNames;

  @override
  State<BleScanModal> createState() => _BleScanModalState();
}

class _BleScanModalState extends State<BleScanModal> {
  final List<ScanResult> _resultados = [];
  StreamSubscription<List<ScanResult>>? _subScan;
  bool _escaneando = false;

  @override
  void initState() {
    super.initState();
    _iniciarEscaneo();
  }

  bool _esPreferido(String nombre) {
    final prefs = widget.preferredNames;
    if (prefs != null && prefs.isNotEmpty) {
      return prefs.any((p) => nombre.startsWith(p));
    }
    return nombre.startsWith(widget.controller.nombreEsperado);
  }

  Future<void> _iniciarEscaneo() async {
    setState(() {
      _escaneando = true;
      _resultados.clear();
    });

    _subScan = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _resultados.clear();
        for (final r in results) {
          // Filtrar por dispositivos con nombre visible
          if (r.device.platformName.isNotEmpty) {
            _resultados.add(r);
          }
        }
        // Ordenar: recomendados primero, luego por mejor RSSI
        _resultados.sort((a, b) {
          final aPref = _esPreferido(a.device.platformName);
          final bPref = _esPreferido(b.device.platformName);
          if (aPref && !bPref) return -1;
          if (!aPref && bPref) return 1;
          return b.rssi.compareTo(a.rssi);
        });
      });
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _escaneando = false;
      });
    }
  }

  @override
  void dispose() {
    _subScan?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String esperado = widget.preferredNames != null && widget.preferredNames!.isNotEmpty
        ? widget.preferredNames!.join(' / ')
        : widget.controller.nombreEsperado;

    return Container(
      padding: const EdgeInsets.all(16.0),
      height: 380,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Vincular ESP ${widget.controller.etiqueta}',
                style: TextStyle(
                  color: widget.controller.color,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_escaneando)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: _iniciarEscaneo,
                ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            'Buscando dispositivos BLE cercanos (esperado: $esperado)...',
            style: const TextStyle(color: Colors.white54, fontSize: 12.0),
          ),
          const Divider(color: Color(0xFF333333)),
          Expanded(
            child: _resultados.isEmpty
                ? Center(
                    child: Text(
                      _escaneando
                          ? 'Escaneando señales BLE...'
                          : 'No se encontraron dispositivos cercanos.',
                      style: const TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: _resultados.length,
                    itemBuilder: (context, index) {
                      final r = _resultados[index];
                      final String nombre = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'Dispositivo Desconocido';
                      final bool coincide = _esPreferido(nombre);

                      return ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          color: coincide
                              ? widget.controller.color
                              : Colors.white60,
                        ),
                        title: Text(
                          nombre,
                          style: TextStyle(
                            color: coincide ? Colors.white : Colors.white70,
                            fontWeight:
                                coincide ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          'MAC: ${r.device.remoteId.str} | RSSI: ${r.rssi} dBm',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                        trailing: coincide
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.controller.color
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'RECOMENDADO',
                                  style: TextStyle(
                                    color: widget.controller.color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () => widget.onSeleccionado(r.device),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
