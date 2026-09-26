import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../widgets/ble_scan_modal.dart';
import '../core/constants.dart';
import '../core/gesture/synthetic_motion.dart';
import '../platform/audio_engine.dart';
import '../platform/ble_stick_link.dart';
import '../platform/stick_hub.dart';
import '../session/board_session.dart';
import '../session/loss_monitor.dart';
import 'closed_screen.dart';
import 'lost_screen.dart';
import 'tuning_panel.dart';

/// Fuente de control para cada rol de stick.
enum StickSource { dedo, auto, stick }

/// Pantalla principal del Tablero de Validación (`#session` del prototipo).
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.audioEngine,
    required this.hub,
    this.initialSources,
  });

  final AudioEngine audioEngine;
  final StickHub hub;
  final Map<StickRole, StickSource>? initialSources;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  late final BoardSession _session;
  late final Ticker _ticker;
  StreamSubscription<LossEvent>? _lossSub;

  bool _navigatedToClosed = false;
  bool _navigatedToLost = false;
  bool _isLeftTouching = false;
  bool _isRightTouching = false;

  final Map<StickRole, StickSource> _sources = {
    StickRole.adult: StickSource.dedo,
    StickRole.child: StickSource.dedo,
  };

  double _lastTeleUpdate = 0;
  List<({String value, String label})> _cachedTelemetry = [];

  @override
  void initState() {
    super.initState();
    _session = BoardSession(onSound: widget.audioEngine.handle);
    _session.start();

    _cachedTelemetry = _session.telemetryCards;
    _ticker = createTicker(_onTick)..start();

    WakelockPlus.enable();

    // Monitoreo de pérdidas de sticks armados
    _lossSub = widget.hub.lossEvents.listen((ev) {
      if (ev.lost && _session.isExternal(ev.role) && _session.running) {
        if (!_navigatedToLost && mounted) {
          _navigatedToLost = true;
          _session.loseStick(ev.role, LossCause.alcance);
          Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => LostScreen(
                hub: widget.hub,
                role: ev.role,
                session: _session,
                cause: LossCause.alcance,
                audioEngine: widget.audioEngine,
              ),
            ),
          ).then((res) {
            _navigatedToLost = false;
            if (res == 'end') {
              _session.end();
            }
          });
        }
      }
    });

    // Aplicar fuentes iniciales (ej. desde el onboarding)
    if (widget.initialSources != null) {
      for (final entry in widget.initialSources!.entries) {
        final role = entry.key;
        final src = entry.value;
        _sources[role] = src;
        if (src == StickSource.auto) {
          if (role == StickRole.adult) {
            _session.setAutoAdult(true);
          } else {
            _session.setAutoChild(true);
          }
        } else if (src == StickSource.stick) {
          final link = widget.hub.ensureLink(role);
          _session.attachReader(role, link.reader);
          widget.hub.arm(role);
        }
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    _session.tick();

    // Sincronizar estado de las fuentes si los toggles globales cambiaron
    if (_session.autoAdult && _sources[StickRole.adult] == StickSource.dedo) {
      _sources[StickRole.adult] = StickSource.auto;
    } else if (!_session.autoAdult && _sources[StickRole.adult] == StickSource.auto) {
      _sources[StickRole.adult] = StickSource.dedo;
    }

    if (_session.autoChild && _sources[StickRole.child] == StickSource.dedo) {
      _sources[StickRole.child] = StickSource.auto;
    } else if (!_session.autoChild && _sources[StickRole.child] == StickSource.auto) {
      _sources[StickRole.child] = StickSource.dedo;
    }

    final now = _session.nowMs;
    if (now - _lastTeleUpdate >= 250) {
      _lastTeleUpdate = now;
      _cachedTelemetry = _session.telemetryCards;
    }

    if (_session.closed && !_navigatedToClosed) {
      _navigatedToClosed = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ClosedScreen(
            session: _session,
            audioEngine: widget.audioEngine,
            hub: widget.hub,
          ),
        ),
      );
    }
  }

  Future<void> _onSourceSelected(StickRole role, StickSource source) async {
    if (_sources[role] == source) return;

    if (_sources[role] == StickSource.stick) {
      _session.attachReader(role, null);
      widget.hub.disarm(role);
    }

    if (source == StickSource.auto) {
      if (role == StickRole.adult) {
        _session.setAutoAdult(true);
      } else {
        _session.setAutoChild(true);
      }
      setState(() => _sources[role] = StickSource.auto);
      return;
    }

    if (source == StickSource.dedo) {
      if (role == StickRole.adult) {
        _session.setAutoAdult(false);
      } else {
        _session.setAutoChild(false);
      }
      setState(() => _sources[role] = StickSource.dedo);
      return;
    }

    // Fuente: Stick real
    if (source == StickSource.stick) {
      if (role == StickRole.adult) {
        _session.setAutoAdult(false);
      } else {
        _session.setAutoChild(false);
      }

      // 1. Permisos Bluetooth
      if (Platform.isAndroid) {
        final scan = await Permission.bluetoothScan.request();
        final connect = await Permission.bluetoothConnect.request();
        if (!scan.isGranted || !connect.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Se requieren permisos de Bluetooth para conectar el stick'),
              ),
            );
          }
          return;
        }
      }

      // 2. Verificar que el adaptador esté encendido
      final state = await FlutterBluePlus.adapterState.first;
      if (state == BluetoothAdapterState.off) {
        if (mounted) {
          final activar = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1A29),
              title: const Text('Bluetooth desactivado', style: TextStyle(color: Colors.white)),
              content: const Text(
                'El adaptador Bluetooth está apagado. ¿Deseas activarlo?',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF2E44A),
                    foregroundColor: const Color(0xFF2B2536),
                  ),
                  child: const Text('Activar'),
                ),
              ],
            ),
          );

          if (activar == true) {
            await FlutterBluePlus.turnOn();
          } else {
            return;
          }
        }
      }

      // 3. Obtener o crear BleStickLink en el StickHub
      final link = widget.hub.ensureLink(role);

      // 4. Si no tiene MAC guardada, abrir modal de escaneo BLE
      final hasSaved = await widget.hub.hasSavedStick(role);
      if (!hasSaved && mounted) {
        await _abrirVinculacion(link);
      }

      _session.attachReader(role, link.reader);
      widget.hub.arm(role);
      setState(() => _sources[role] = StickSource.stick);
    }
  }

  Future<void> _abrirVinculacion(BleStickLink link) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => BleScanModal(
        controller: link.controller,
        preferredNames: link.acceptedNames,
        onSeleccionado: (dev) async {
          Navigator.pop(ctx);
          await link.adopt(dev);
        },
      ),
    );
  }

  void _abrirAjusteImu() {
    final link = widget.hub.link(StickRole.child) ?? widget.hub.link(StickRole.adult);
    if (link == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TuningPanel(link: link),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _lossSub?.cancel();
    WakelockPlus.disable();
    for (final role in StickRole.values) {
      if (_sources[role] == StickSource.stick) {
        widget.hub.disarm(role);
        _session.attachReader(role, null);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeLinks = [
      widget.hub.link(StickRole.adult),
      widget.hub.link(StickRole.child),
    ].whereType<BleStickLink>();

    final mergeList = <Listenable>[
      _session,
      widget.hub,
      ...activeLinks,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(mergeList),
      builder: (context, _) {
        final isScrollingBlocked = _isLeftTouching || _isRightTouching;

        final leftRole = _session.sides[PanelSide.left]!;
        final rightRole = _session.sides[PanelSide.right]!;

        return Scaffold(
          backgroundColor: const Color(0xFFEFECE4),
          body: Stack(
            children: [
              // Vista principal del tablero
              SafeArea(
                child: SingleChildScrollView(
                  physics: isScrollingBlocked
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // a) Píldora de estado superior
                          _buildStatePill(),
                          const SizedBox(height: 12),

                          // b) Tarjeta "Eje" (Banda de 25 columnas, campo, LED)
                          _buildAxisCard(),
                          const SizedBox(height: 14),

                          // c) Dos paneles táctiles lado a lado (al menos 40% de altura)
                          SizedBox(
                            height: math.max(
                              380,
                              MediaQuery.of(context).size.height * 0.44,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _TouchPanelWidget(
                                    side: PanelSide.left,
                                    session: _session,
                                    source: _sources[leftRole]!,
                                    link: widget.hub.link(leftRole),
                                    onSourceSelected: (s) => _onSourceSelected(leftRole, s),
                                    onRebind: () => widget.hub.link(leftRole) != null
                                        ? _abrirVinculacion(widget.hub.link(leftRole)!)
                                        : null,
                                    onPointerActiveChange: (active) {
                                      setState(() => _isLeftTouching = active);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _TouchPanelWidget(
                                    side: PanelSide.right,
                                    session: _session,
                                    source: _sources[rightRole]!,
                                    link: widget.hub.link(rightRole),
                                    onSourceSelected: (s) => _onSourceSelected(rightRole, s),
                                    onRebind: () => widget.hub.link(rightRole) != null
                                        ? _abrirVinculacion(widget.hub.link(rightRole)!)
                                        : null,
                                    onPointerActiveChange: (active) {
                                      setState(() => _isRightTouching = active);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // d) Controles
                          _buildControlsBar(),
                          const SizedBox(height: 16),

                          // e) Tarjetas de telemetría en vivo
                          _buildTelemetryCards(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Modo Eje (Overlay completo cuando sesión está en ejeMode)
              if (_session.ejeMode)
                Positioned.fill(
                  child: _EjeModeOverlay(
                    session: _session,
                    onExit: () => _session.setEjeMode(false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Píldora oscura (#2B2536) con el estado en vivo y su descripción.
  Widget _buildStatePill() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2536),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          Text(
            _session.stateName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFFF2E44A),
            ),
          ),
          Text(
            _session.stateDesc,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta blanca "Eje": banda de 25 columnas, campo abierto, LED difuso.
  Widget _buildAxisCard() {
    final activeCols = <int>{};
    final flashes = <int, bool?>{};
    for (var i = 0; i < BalancinConst.numNotes; i++) {
      if (_session.columnOn(i)) activeCols.add(i);
      final f = _session.columnFlash(i);
      if (f != null) flashes[i] = f;
    }

    final hiddenText = _session.hiddenText;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banda de 25 columnas con CustomPainter
          SizedBox(
            height: 80,
            child: CustomPaint(
              painter: BandPainter(
                fieldLo: _session.field.lo,
                fieldCount: _session.field.count,
                hiddenActive: _session.hiddenActive,
                flashes: flashes,
                activeCols: activeCols,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Etiquetas de registro
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'grave · marimba',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A536B),
                ),
              ),
              Text(
                'agudo · glockenspiel',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A536B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Texto descriptivo del campo
          Text(
            _session.fieldText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2B2536),
              height: 1.25,
            ),
          ),

          // Badge de timbre oculto (si está activo)
          if (hiddenText != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2E44A),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Text(
                  hiddenText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B2536),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Fila del LED
          _buildLedRow(_session.lightLevel),
        ],
      ),
    );
  }

  /// Fila con el indicador LED difuso y su leyenda.
  Widget _buildLedRow(double lightLevel) {
    final opacity = (0.15 + 0.85 * lightLevel).clamp(0.0, 1.0);
    final glowRadius = 6.0 + 40.0 * lightLevel;
    final spreadRadius = 2.0 + 14.0 * lightLevel;
    final glowOpacity = (lightLevel * 0.7).clamp(0.0, 1.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF2E44A).withValues(alpha: opacity),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE9D64A).withValues(alpha: glowOpacity),
                blurRadius: glowRadius,
                spreadRadius: spreadRadius,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Luz difusa de refuerzo: sigue la amplitud del sonido, sin información propia.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF5A536B),
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  /// Barra de controles: Intercambiar, Niño auto, Adulto auto, Modo eje, Terminar, Demos, Ajuste IMU.
  Widget _buildControlsBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Intercambiar sticks
            OutlinedButton(
              onPressed: _session.swapSides,
              style: _controlButtonStyle(),
              child: const Text('Intercambiar sticks'),
            ),

            // Niño automático
            OutlinedButton(
              onPressed: () {
                final nuevo = !_session.autoChild;
                _session.setAutoChild(nuevo);
                if (nuevo && _sources[StickRole.child] != StickSource.stick) {
                  _sources[StickRole.child] = StickSource.auto;
                } else if (!nuevo && _sources[StickRole.child] == StickSource.auto) {
                  _sources[StickRole.child] = StickSource.dedo;
                }
              },
              style: _controlButtonStyle(active: _session.autoChild),
              child: Text(
                'Niño automático: ${_session.autoChild ? 'encendido' : 'apagado'}',
              ),
            ),

            // Adulto automático
            OutlinedButton(
              onPressed: () {
                final nuevo = !_session.autoAdult;
                _session.setAutoAdult(nuevo);
                if (nuevo && _sources[StickRole.adult] != StickSource.stick) {
                  _sources[StickRole.adult] = StickSource.auto;
                } else if (!nuevo && _sources[StickRole.adult] == StickSource.auto) {
                  _sources[StickRole.adult] = StickSource.dedo;
                }
              },
              style: _controlButtonStyle(active: _session.autoAdult),
              child: Text(
                'Adulto automático: ${_session.autoAdult ? 'encendido' : 'apagado'}',
              ),
            ),

            // Botón Ajuste IMU (visible si algún rol es Stick)
            if (widget.hub.link(StickRole.child) != null ||
                widget.hub.link(StickRole.adult) != null)
              ElevatedButton.icon(
                onPressed: _abrirAjusteImu,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Ajuste IMU'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B35B8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),

            // Selector de Demo
            PopupMenuButton<DemoScenario?>(
              onSelected: _session.setDemo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                decoration: BoxDecoration(
                  color: _session.demo != null ? const Color(0xFF2B2536) : Colors.white,
                  border: Border.all(color: const Color(0x402B2536), width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _session.demo == null
                          ? 'Demo: apagada'
                          : 'Demo: ${_session.demo!.name}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _session.demo != null
                            ? Colors.white
                            : const Color(0xFF2B2536),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: _session.demo != null
                          ? Colors.white
                          : const Color(0xFF2B2536),
                    ),
                  ],
                ),
              ),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: null,
                  child: Text('Demo: apagada'),
                ),
                for (final d in DemoScenario.values)
                  PopupMenuItem(
                    value: d,
                    child: Text('Demo: ${d.name}'),
                  ),
              ],
            ),

            // Modo eje: solo luz
            OutlinedButton(
              onPressed: () => _session.setEjeMode(true),
              style: _controlButtonStyle(),
              child: const Text('Modo eje: solo luz'),
            ),

            // Terminar sesión
            ElevatedButton(
              onPressed: _session.end,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B2536),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                elevation: 0,
              ),
              child: const Text(
                'Terminar sesión',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),

        // Slider de velocidad si el Adulto automático está activo
        if (_session.autoAdult) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Velocidad adulto:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B2536),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _session.autoAdultSpeed,
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: '${_session.autoAdultSpeed.round()}x',
                    activeColor: const Color(0xFF5B35B8),
                    onChanged: (v) => _session.setAutoAdult(true, speed: v),
                  ),
                ),
                Text(
                  '${_session.autoAdultSpeed.toStringAsFixed(0)}x',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B2536),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  ButtonStyle _controlButtonStyle({bool active = false}) {
    return OutlinedButton.styleFrom(
      backgroundColor: active ? const Color(0xFF2B2536) : Colors.white,
      foregroundColor: active ? Colors.white : const Color(0xFF2B2536),
      side: const BorderSide(color: Color(0x402B2536), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
  }

  /// Tarjetas de telemetría en vivo (6 tarjetas).
  Widget _buildTelemetryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 600 ? 6 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 80,
          ),
          itemCount: _cachedTelemetry.length,
          itemBuilder: (context, index) {
            final card = _cachedTelemetry[index];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    card.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2B2536),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A536B),
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// CustomPainter para la banda de 25 notas y la ventana de campo abierto.
class BandPainter extends CustomPainter {
  const BandPainter({
    required this.fieldLo,
    required this.fieldCount,
    required this.hiddenActive,
    required this.flashes,
    required this.activeCols,
  });

  final int fieldLo;
  final int fieldCount;
  final bool hiddenActive;
  final Map<int, bool?> flashes;
  final Set<int> activeCols;

  @override
  void paint(Canvas canvas, Size size) {
    const numCols = 25;
    const gap = 3.0;
    final totalGaps = (numCols - 1) * gap;
    final colWidth = (size.width - totalGaps) / numCols;
    const radius = Radius.circular(5.0);

    for (var i = 0; i < numCols; i++) {
      final x = i * (colWidth + gap);
      final rect = Rect.fromLTWH(x, 0, colWidth, size.height);
      final rrect = RRect.fromRectAndRadius(rect, radius);

      Color color;
      final flash = flashes[i];
      if (flash != null) {
        color = flash ? const Color(0xFFF2E44A) : const Color(0xFFE85E45);
      } else if (activeCols.contains(i)) {
        color = const Color(0xFF7B5FCB);
      } else {
        color = const Color(0xFFEFECE4);
      }

      final paint = Paint()..color = color;
      canvas.drawRRect(rrect, paint);
    }

    // Ventana indicadora de campo abierto
    if (fieldCount > 0) {
      final startX = fieldLo * (colWidth + gap) - 1.5;
      final endX = (fieldLo + fieldCount) * (colWidth + gap) - gap + 1.5;
      final winRect = Rect.fromLTRB(startX, 0, endX, size.height);
      final winRRect = RRect.fromRectAndRadius(winRect, const Radius.circular(8.0));
      final strokePaint = Paint()
        ..color = hiddenActive ? const Color(0xFFE9D64A) : const Color(0xFF2B2536)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(winRRect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant BandPainter oldDelegate) => true;
}

/// Panel interactivo de un stick (izquierdo o derecho).
///
/// Soporta 3 fuentes:
/// - "Dedo": captura toques con [Listener] para latencia cero.
/// - "Automático": genera movimiento sintético.
/// - "Stick": conectado al sensor BLE real ([BleStickLink]), muestra telemetría
///   en vivo, estado del enlace, calibración y botones de configuración.
class _TouchPanelWidget extends StatefulWidget {
  const _TouchPanelWidget({
    required this.side,
    required this.session,
    required this.source,
    required this.onSourceSelected,
    this.link,
    this.onRebind,
    required this.onPointerActiveChange,
  });

  final PanelSide side;
  final BoardSession session;
  final StickSource source;
  final ValueChanged<StickSource> onSourceSelected;
  final BleStickLink? link;
  final VoidCallback? onRebind;
  final ValueChanged<bool> onPointerActiveChange;

  @override
  State<_TouchPanelWidget> createState() => _TouchPanelWidgetState();
}

class _TouchPanelWidgetState extends State<_TouchPanelWidget> {
  int? _activePointerId;

  @override
  Widget build(BuildContext context) {
    final role = widget.session.sides[widget.side]!;
    final isAdult = role == StickRole.adult;
    final isMoving = widget.session.panelMoving(widget.side);
    final copy = kPanelTexts[role]!;
    final isStick = widget.source == StickSource.stick && widget.link != null;

    final bgColor = isAdult ? const Color(0xFFB3A2DC) : const Color(0xFFF4C3B6);
    final borderColor = isAdult ? const Color(0xFF5B35B8) : const Color(0xFFE85E45);
    final dotColor = isAdult ? const Color(0xFF5B35B8) : const Color(0xFFE85E45);
    final dotSize = isAdult ? 48.0 : 32.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        widget.session.setPanelSize(
          widget.side,
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return Listener(
          behavior: isStick ? HitTestBehavior.deferToChild : HitTestBehavior.opaque,
          onPointerDown: isStick
              ? null
              : (e) {
                  if (_activePointerId == null) {
                    _activePointerId = e.pointer;
                    widget.onPointerActiveChange(true);
                    widget.session.feedPanel(widget.side, e.localPosition.dx, e.localPosition.dy);
                  }
                },
          onPointerMove: isStick
              ? null
              : (e) {
                  if (e.pointer == _activePointerId) {
                    widget.session.feedPanel(widget.side, e.localPosition.dx, e.localPosition.dy);
                  }
                },
          onPointerUp: isStick
              ? null
              : (e) {
                  if (e.pointer == _activePointerId) {
                    _activePointerId = null;
                    widget.onPointerActiveChange(false);
                  }
                },
          onPointerCancel: isStick
              ? null
              : (e) {
                  if (e.pointer == _activePointerId) {
                    _activePointerId = null;
                    widget.onPointerActiveChange(false);
                  }
                },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(22),
              border: isMoving
                  ? Border.all(color: borderColor, width: 4.0)
                  : Border.all(color: Colors.transparent, width: 4.0),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera: Título y Selector segmentado de fuente
                Text(
                  copy.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2B2536),
                  ),
                ),
                const SizedBox(height: 6),
                _buildSourceSelector(),
                const SizedBox(height: 8),

                // Contenido central del panel
                Expanded(
                  child: isStick
                      ? _buildStickTelemetry(widget.link!)
                      : _buildTouchArea(copy, dotSize, dotColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Selector segmentado de fuente: Dedo · Automático · Stick
  Widget _buildSourceSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          _buildSourceOption('Dedo', StickSource.dedo),
          _buildSourceOption('Auto', StickSource.auto),
          _buildSourceOption('Stick', StickSource.stick),
        ],
      ),
    );
  }

  Widget _buildSourceOption(String label, StickSource src) {
    final selected = widget.source == src;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSourceSelected(src),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2B2536) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF2B2536),
            ),
          ),
        ),
      ),
    );
  }

  /// Vista normal táctil (Dedo o Automático)
  Widget _buildTouchArea(
    ({String body, String mapping, String title}) copy,
    double dotSize,
    Color dotColor,
  ) {
    final dot = widget.session.dotFor(widget.side);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              copy.body,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF3A3449),
                height: 1.2,
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Color(0x402B2536),
                    width: 1.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                copy.mapping,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3449),
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),

        // Punto táctil visual
        if (dot != null)
          Positioned(
            left: dot.x - dotSize / 2,
            top: dot.y - dotSize / 2,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                border: Border.all(color: Colors.white, width: 2.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Vista de telemetría en vivo cuando la fuente es "Stick"
  Widget _buildStickTelemetry(BleStickLink link) {
    final reader = link.reader;
    final bias = reader.biasDps;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Estado de conexión grande
          Text(
            link.statusText,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2B2536),
            ),
          ),
          const SizedBox(height: 6),

          // Barras en vivo: ω, vel01, amp
          _buildMiniBar('ω', '${reader.omegaDps.toStringAsFixed(0)} °/s', (reader.omegaDps / reader.tuning.omegaMaxDps).clamp(0.0, 1.0)),
          const SizedBox(height: 4),
          _buildMiniBar('vel', '${(reader.vel01 * 100).toStringAsFixed(0)} %', reader.vel01),
          const SizedBox(height: 4),
          _buildMiniBar('amp', '${(reader.amp * 100).toStringAsFixed(0)} %', reader.amp),
          const SizedBox(height: 6),

          // Chips indicadores
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildMiniChip(
                reader.active ? 'ACTIVO' : 'QUIETO',
                reader.active ? const Color(0xFF7A8B34) : Colors.black12,
                textColor: reader.active ? Colors.white : const Color(0xFF2B2536),
              ),
              _buildMiniChip(
                reader.shake ? 'SHAKE' : 'CALMO',
                reader.shake ? const Color(0xFFF2E44A) : Colors.black12,
                textColor: const Color(0xFF2B2536),
              ),
              _buildMiniChip(
                'Eje ${reader.dominantAxis == 0 ? "X" : reader.dominantAxis == 1 ? "Y" : "Z"}',
                const Color(0xFF5B35B8),
                textColor: Colors.white,
              ),
              _buildMiniChip(
                'dx:${reader.dx >= 0 ? "+${reader.dx}" : reader.dx} dy:${reader.dy >= 0 ? "+${reader.dy}" : reader.dy}',
                Colors.black12,
                textColor: const Color(0xFF2B2536),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Bias
          Text(
            'Bias: (${bias.x.toStringAsFixed(1)}, ${bias.y.toStringAsFixed(1)}, ${bias.z.toStringAsFixed(1)}) °/s',
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: Color(0xFF3A3449),
            ),
          ),
          const SizedBox(height: 8),

          // Botones de acción del stick
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: link.recalibrate,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.6),
                    foregroundColor: const Color(0xFF2B2536),
                    side: const BorderSide(color: Color(0x332B2536)),
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Recalibrar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onRebind,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.6),
                    foregroundColor: const Color(0xFF2B2536),
                    side: const BorderSide(color: Color(0x332B2536)),
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Vincular', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBar(String label, String valueText, double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF3A3449)),
          ),
        ),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            clipBehavior: Clip.antiAlias,
            child: FractionallySizedBox(
              widthFactor: clamped,
              alignment: Alignment.centerLeft,
              child: Container(color: const Color(0xFF2B2536)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF2B2536)),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniChip(String text, Color bg, {Color textColor = Colors.white}) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: textColor),
      ),
    );
  }
}

/// Overlay de pantalla completa para el Modo Eje.
///
/// Refleja la luz difusa en el interior del objeto físico:
/// - Franjas difusas superior e inferior moduladas por [EjeGlow].
/// - Destellos radiales efímeros de notas ([EjeFlash]).
/// - Dos mitades de pantalla transparentes con entrada multitoque (omitida si el rol es Stick).
class _EjeModeOverlay extends StatefulWidget {
  const _EjeModeOverlay({
    required this.session,
    required this.onExit,
  });

  final BoardSession session;
  final VoidCallback onExit;

  @override
  State<_EjeModeOverlay> createState() => _EjeModeOverlayState();
}

class _EjeModeOverlayState extends State<_EjeModeOverlay> {
  int? _leftPointer;
  int? _rightPointer;

  @override
  Widget build(BuildContext context) {
    final glow = widget.session.ejeGlow;
    final nowMs = widget.session.nowMs;
    final glowColor = glow.hidden ? const Color(0xFFF2E44A) : const Color(0xFF7B5FCB);

    final leftRole = widget.session.sides[PanelSide.left]!;
    final rightRole = widget.session.sides[PanelSide.right]!;
    final leftIsExternal = widget.session.isExternal(leftRole);
    final rightIsExternal = widget.session.isExternal(rightRole);

    return Scaffold(
      backgroundColor: const Color(0xFF1D1927),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Franja superior
          final topH = h * 0.40 * glow.topScale.clamp(0.0, 1.5);
          // Franja inferior
          final bottomH = h * 0.40 * glow.bottomScale.clamp(0.0, 1.5);

          return Stack(
            children: [
              // Franja de luz superior
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: math.max(0, topH),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0)),
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0) * 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Franja de luz inferior
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: math.max(0, bottomH),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0)),
                        glowColor.withValues(alpha: glow.opacity.clamp(0.0, 1.0) * 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Destellos de notas (EjeFlashes)
              for (final flash in widget.session.ejeFlashes) ...[
                _buildEjeFlash(flash, nowMs, w, h),
              ],

              // Dos mitades transparentes para captura de toques multidedo en Modo Eje
              Row(
                children: [
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (leftIsExternal) return;
                        if (_leftPointer == null) {
                          _leftPointer = e.pointer;
                          widget.session.setPanelSize(PanelSide.left, w / 2, h);
                          widget.session.feedPanel(PanelSide.left, e.localPosition.dx, e.localPosition.dy);
                        }
                      },
                      onPointerMove: (e) {
                        if (leftIsExternal) return;
                        if (e.pointer == _leftPointer) {
                          widget.session.feedPanel(PanelSide.left, e.localPosition.dx, e.localPosition.dy);
                        }
                      },
                      onPointerUp: (e) {
                        if (e.pointer == _leftPointer) _leftPointer = null;
                      },
                      onPointerCancel: (e) {
                        if (e.pointer == _leftPointer) _leftPointer = null;
                      },
                    ),
                  ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (rightIsExternal) return;
                        if (_rightPointer == null) {
                          _rightPointer = e.pointer;
                          widget.session.setPanelSize(PanelSide.right, w / 2, h);
                          widget.session.feedPanel(PanelSide.right, e.localPosition.dx, e.localPosition.dy);
                        }
                      },
                      onPointerMove: (e) {
                        if (rightIsExternal) return;
                        if (e.pointer == _rightPointer) {
                          widget.session.feedPanel(PanelSide.right, e.localPosition.dx, e.localPosition.dy);
                        }
                      },
                      onPointerUp: (e) {
                        if (e.pointer == _rightPointer) _rightPointer = null;
                      },
                      onPointerCancel: (e) {
                        if (e.pointer == _rightPointer) _rightPointer = null;
                      },
                    ),
                  ),
                ],
              ),

              // Botón discreto para salir del Modo Eje
              Positioned(
                top: 40,
                right: 20,
                child: TextButton.icon(
                  onPressed: widget.onExit,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  label: const Text(
                    'Salir',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEjeFlash(EjeFlash flash, double nowMs, double w, double h) {
    final age = (nowMs - flash.bornMs) / BoardSession.ejeFlashMs;
    if (age < 0 || age > 1.0) return const SizedBox.shrink();

    final opacity = (1.0 - age).clamp(0.0, 1.0);
    final size = math.min(w, h) * (0.25 + 0.45 * age);
    final color = flash.hidden ? const Color(0xFFF2E44A) : const Color(0xFFE85E45);

    return Positioned(
      left: flash.x * w - size / 2,
      top: flash.y * h - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: opacity * 0.45),
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 0.72],
            ),
          ),
        ),
      ),
    );
  }
}
