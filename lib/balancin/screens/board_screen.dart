import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/constants.dart';
import '../core/gesture/synthetic_motion.dart';
import '../platform/audio_engine.dart';
import '../session/board_session.dart';
import 'closed_screen.dart';

/// Pantalla principal del Tablero de Validación (`#session` del prototipo).
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.audioEngine,
  });

  final AudioEngine audioEngine;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  late final BoardSession _session;
  late final Ticker _ticker;

  bool _navigatedToClosed = false;
  bool _isLeftTouching = false;
  bool _isRightTouching = false;

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
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    _session.tick();

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
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final isScrollingBlocked = _isLeftTouching || _isRightTouching;

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
                              320,
                              MediaQuery.of(context).size.height * 0.42,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _TouchPanelWidget(
                                    side: PanelSide.left,
                                    session: _session,
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

  /// Barra de controles: Intercambiar, Niño auto, Adulto auto, Modo eje, Terminar, Demos.
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
              onPressed: () => _session.setAutoChild(!_session.autoChild),
              style: _controlButtonStyle(active: _session.autoChild),
              child: Text(
                'Niño automático: ${_session.autoChild ? 'encendido' : 'apagado'}',
              ),
            ),

            // Adulto automático
            OutlinedButton(
              onPressed: () => _session.setAutoAdult(!_session.autoAdult),
              style: _controlButtonStyle(active: _session.autoAdult),
              child: Text(
                'Adulto automático: ${_session.autoAdult ? 'encendido' : 'apagado'}',
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
/// Recibe eventos crudos con [Listener] para responder con latencia cero
/// y rastrear un puntero único de inicio a fin.
class _TouchPanelWidget extends StatefulWidget {
  const _TouchPanelWidget({
    required this.side,
    required this.session,
    required this.onPointerActiveChange,
  });

  final PanelSide side;
  final BoardSession session;
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
    final dot = widget.session.dotFor(widget.side);

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
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_activePointerId == null) {
              _activePointerId = e.pointer;
              widget.onPointerActiveChange(true);
              widget.session.feedPanel(widget.side, e.localPosition.dx, e.localPosition.dy);
            }
          },
          onPointerMove: (e) {
            if (e.pointer == _activePointerId) {
              widget.session.feedPanel(widget.side, e.localPosition.dx, e.localPosition.dy);
            }
          },
          onPointerUp: (e) {
            if (e.pointer == _activePointerId) {
              _activePointerId = null;
              widget.onPointerActiveChange(false);
            }
          },
          onPointerCancel: (e) {
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
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                // Textos descriptivos
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2B2536),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          copy.body,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF3A3449),
                            height: 1.2,
                          ),
                        ),
                      ],
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
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        copy.mapping,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3A3449),
                          height: 1.2,
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
            ),
          ),
        );
      },
    );
  }
}

/// Overlay de pantalla completa para el Modo Eje.
///
/// Refleja la luz difusa en el interior del objeto físico:
/// - Franjas difusas superior e inferior moduladas por [EjeGlow].
/// - Destellos radiales efímeros de notas ([EjeFlash]).
/// - Dos mitades de pantalla transparentes con entrada multitoque.
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
                        if (_leftPointer == null) {
                          _leftPointer = e.pointer;
                          widget.session.setPanelSize(PanelSide.left, w / 2, h);
                          widget.session.feedPanel(PanelSide.left, e.localPosition.dx, e.localPosition.dy);
                        }
                      },
                      onPointerMove: (e) {
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
                        if (_rightPointer == null) {
                          _rightPointer = e.pointer;
                          widget.session.setPanelSize(PanelSide.right, w / 2, h);
                          widget.session.feedPanel(PanelSide.right, e.localPosition.dx, e.localPosition.dy);
                        }
                      },
                      onPointerMove: (e) {
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
