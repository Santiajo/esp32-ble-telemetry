import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:esp32_ble_telemetry/controllers/esp_device_controller.dart';
import 'package:esp32_ble_telemetry/core/ble/ble_constants.dart';
import 'package:esp32_ble_telemetry/widgets/metric_card.dart';
import 'package:esp32_ble_telemetry/widgets/oscilloscope_painter.dart';
import 'package:esp32_ble_telemetry/widgets/radar_cartesian_painter.dart';
import 'package:esp32_ble_telemetry/widgets/telemetry_console.dart';
import 'package:esp32_ble_telemetry/balancin/screens/audio_test_screen.dart';

/// Pantalla principal telemétrica del sistema dual ESP32 MPU-6050.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final EspDeviceController dispA;
  late final EspDeviceController dispB;

  // Controlador de animación a 60 FPS desacoplado de la llegada de paquetes BLE
  late final AnimationController _tickerController;

  final List<String> _consolaLogs = [];
  static const int _maxLogsConsola = 30;

  StreamSubscription<BluetoothAdapterState>? _subAdapterState;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();

    dispA = EspDeviceController(
      etiqueta: 'A',
      color: const Color(0xFF00FFCC),
      nombreEsperado: BleConstants.nameDispA,
      onLog: _agregarLog,
    );

    dispB = EspDeviceController(
      etiqueta: 'B',
      color: const Color(0xFFFF5722),
      nombreEsperado: BleConstants.nameDispB,
      onLog: _agregarLog,
    );

    // Escuchar cambios de estado en los controladores para gestionar Wakelock
    dispA.addListener(_actualizarWakelock);
    dispB.addListener(_actualizarWakelock);

    // Monitorear estado del adaptador Bluetooth del sistema
    _iniciarMonitoreoAdaptador();

    // Configurar Ticker desacoplado a vsync nativo (60 FPS / 120 FPS)
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _tickerController.addListener(() {
      // Avanzar interpolación cinemática suave para cada placa
      dispA.tickInterpolacion();
      dispB.tickInterpolacion();
    });

    // Inicializar auto-reconexión para dispositivos recordados
    _solicitarPermisosEIniciar();
  }

  Future<void> _iniciarMonitoreoAdaptador() async {
    try {
      final bool soportado = await FlutterBluePlus.isSupported;
      if (!soportado || !mounted) return;

      _subAdapterState = FlutterBluePlus.adapterState.listen(
        (state) {
          if (mounted) {
            setState(() {
              _adapterState = state;
            });
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _solicitarPermisosEIniciar() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    } catch (_) {}

    await dispA.inicializarAutoConexion();
    await dispB.inicializarAutoConexion();
  }

  void _agregarLog(String mensaje) {
    if (!mounted) return;
    setState(() {
      _consolaLogs.add(mensaje);
      if (_consolaLogs.length > _maxLogsConsola) {
        _consolaLogs.removeAt(0);
      }
    });
  }

  void _actualizarWakelock() {
    final bool algunConectado = dispA.conectado || dispB.conectado;
    if (algunConectado) {
      WakelockPlus.enable().catchError((_) {});
    } else {
      WakelockPlus.disable().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _subAdapterState?.cancel();
    _tickerController.dispose();
    dispA.removeListener(_actualizarWakelock);
    dispB.removeListener(_actualizarWakelock);
    dispA.dispose();
    dispB.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _abrirSelectorDispositivo(EspDeviceController controller) async {
    // Si ya está conectado, un toque desconecta
    if (controller.conectado) {
      await controller.desconectar();
      return;
    }

    // Si tiene MAC guardada pero no está conectado, intenta reconectar de inmediato
    if (controller.macGuardada != null &&
        controller.estado == EstadoConexion.sinVincular) {
      await controller.conectarPersistente();
      return;
    }

    // Si no está vinculado, abrir modal de escaneo BLE
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ModalEscaneoBLE(
        controller: controller,
        onSeleccionado: (dev) async {
          Navigator.pop(ctx);
          await controller.adoptarDispositivo(dev);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool algunoConectado = dispA.conectado || dispB.conectado;
    final bool bluetoothApagado = _adapterState == BluetoothAdapterState.off;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: const Text(
          'Estación Telemétrica · ESP32 BLE',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.music_note, color: Colors.tealAccent),
            tooltip: 'Probar audio Balancín',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AudioTestScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Banner de advertencia si el adaptador Bluetooth está apagado
            if (bluetoothApagado)
              Container(
                color: Colors.amber.shade900,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bluetooth_disabled,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Bluetooth desactivado en el dispositivo.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => FlutterBluePlus.turnOn(),
                      child: const Text('ACTIVAR'),
                    ),
                  ],
                ),
              ),

            // Barra superior de chips de estado y botones de acción
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              color: const Color(0xFF141414),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _construirChipEstado(dispA),
                    const SizedBox(width: 8.0),
                    _construirChipEstado(dispB),
                    const SizedBox(width: 16.0),
                    IconButton(
                      tooltip: 'Calibrar Centro (Tara)',
                      icon: const Icon(Icons.filter_center_focus, size: 20),
                      color: Colors.amber,
                      onPressed: algunoConectado
                          ? () {
                              if (dispA.conectado) dispA.calibrarCentro();
                              if (dispB.conectado) dispB.calibrarCentro();
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Reiniciar Posición',
                      icon: const Icon(Icons.refresh, size: 20),
                      color: Colors.redAccent,
                      onPressed: algunoConectado
                          ? () {
                              dispA.reiniciarPosicion();
                              dispB.reiniciarPosicion();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF222222)),

            // Contenido principal responsivo
            Expanded(
              child: AnimatedBuilder(
                animation: _tickerController,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final bool esPantallaAncha = constraints.maxWidth > 700;

                      if (esPantallaAncha) {
                        return _construirLayoutHorizontal();
                      } else {
                        return _construirLayoutVertical();
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirChipEstado(EspDeviceController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        String texto = 'Toca para vincular';
        Color colorEstado = Colors.grey;

        if (controller.conectado) {
          texto = 'Conectado';
          colorEstado = controller.color;
        } else if (controller.estado == EstadoConexion.buscando) {
          texto = 'Buscando...';
          colorEstado = Colors.amber;
        }

        return InkWell(
          onTap: () => _abrirSelectorDispositivo(controller),
          borderRadius: BorderRadius.circular(16.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: controller.conectado ? controller.color : const Color(0xFF333333),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7.0,
                  height: 7.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorEstado,
                  ),
                ),
                const SizedBox(width: 6.0),
                Text(
                  'ESP ${controller.etiqueta} · $texto',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _construirLayoutVertical() {
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        // Plano Cartesiano 2D
        const Text(
          'Plano Cartesiano 2D (Posición X / Y)',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6.0),
        ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: CustomPaint(
              painter: RadarCartesianPainter(
                dispA: dispA,
                dispB: dispB,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14.0),

        // Osciloscopios
        const Text(
          'Análisis Telemétrico en Tiempo Real',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6.0),
        _construirOsciloscopioBox(
          titulo: 'Velocidad Total (m/s)',
          bufferA: dispA.bufferVelocidad,
          bufferB: dispB.bufferVelocidad,
          escala: 15.0,
        ),
        const SizedBox(height: 8.0),
        _construirOsciloscopioBox(
          titulo: 'Aceleración / Impulso (m/s²)',
          bufferA: dispA.bufferAceleracion,
          bufferB: dispB.bufferAceleracion,
          escala: 2.5,
        ),
        const SizedBox(height: 8.0),
        _construirOsciloscopioBox(
          titulo: 'Energía Cinética Sostenida',
          bufferA: dispA.bufferEnergia,
          bufferB: dispB.bufferEnergia,
          escala: 8.0,
        ),
        const SizedBox(height: 14.0),

        // Tarjetas de Métricas
        Row(
          children: [
            Expanded(child: MetricCard(controller: dispA)),
            const SizedBox(width: 8.0),
            Expanded(child: MetricCard(controller: dispB)),
          ],
        ),
        const SizedBox(height: 12.0),

        // Consola de telemetría
        TelemetryConsole(logs: _consolaLogs),
      ],
    );
  }

  Widget _construirLayoutHorizontal() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Panel izquierdo: Plano Cartesiano y Tarjetas
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.all(12.0),
            children: [
              const Text(
                'Plano Cartesiano 2D (Posición X / Y)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6.0),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: CustomPaint(
                    painter: RadarCartesianPainter(
                      dispA: dispA,
                      dispB: dispB,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(child: MetricCard(controller: dispA)),
                  const SizedBox(width: 8.0),
                  Expanded(child: MetricCard(controller: dispB)),
                ],
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF222222)),

        // Panel derecho: Osciloscopios y Consola
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.all(12.0),
            children: [
              const Text(
                'Análisis Telemétrico en Tiempo Real',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6.0),
              _construirOsciloscopioBox(
                titulo: 'Velocidad Total (m/s)',
                bufferA: dispA.bufferVelocidad,
                bufferB: dispB.bufferVelocidad,
                escala: 15.0,
              ),
              const SizedBox(height: 8.0),
              _construirOsciloscopioBox(
                titulo: 'Aceleración / Impulso (m/s²)',
                bufferA: dispA.bufferAceleracion,
                bufferB: dispB.bufferAceleracion,
                escala: 2.5,
              ),
              const SizedBox(height: 8.0),
              _construirOsciloscopioBox(
                titulo: 'Energía Cinética Sostenida',
                bufferA: dispA.bufferEnergia,
                bufferB: dispB.bufferEnergia,
                escala: 8.0,
              ),
              const SizedBox(height: 12.0),
              TelemetryConsole(logs: _consolaLogs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirOsciloscopioBox({
    required String titulo,
    required List<double> bufferA,
    required List<double> bufferB,
    required double escala,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8.0),
              Text(
                'A (Turquesa) | B (Naranja)',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: SizedBox(
              height: 85.0,
              width: double.infinity,
              child: CustomPaint(
                painter: OscilloscopePainter(
                  datosA: bufferA,
                  datosB: bufferB,
                  colorA: dispA.color,
                  colorB: dispB.color,
                  escala: escala,
                  mostrarB: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal de escaneo BLE para emparejar una placa específica.
class _ModalEscaneoBLE extends StatefulWidget {
  final EspDeviceController controller;
  final ValueChanged<BluetoothDevice> onSeleccionado;

  const _ModalEscaneoBLE({
    required this.controller,
    required this.onSeleccionado,
  });

  @override
  State<_ModalEscaneoBLE> createState() => _ModalEscaneoBLEState();
}

class _ModalEscaneoBLEState extends State<_ModalEscaneoBLE> {
  final List<ScanResult> _resultados = [];
  StreamSubscription<List<ScanResult>>? _subScan;
  bool _escaneando = false;

  @override
  void initState() {
    super.initState();
    _iniciarEscaneo();
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
          // Filtrar por dispositivos con nombre o con prefijo ESP32
          if (r.device.platformName.isNotEmpty) {
            _resultados.add(r);
          }
        }
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
    return Container(
      padding: const EdgeInsets.all(16.0),
      height: 380,
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
            'Buscando dispositivos BLE cercanos (esperado: ${widget.controller.nombreEsperado})...',
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
                      final bool coincide =
                          nombre.startsWith(widget.controller.nombreEsperado);

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
