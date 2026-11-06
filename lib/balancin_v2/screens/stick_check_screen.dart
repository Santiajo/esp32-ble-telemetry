import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/diagnostics.dart';
import '../core/levels.dart';
import '../core/params.dart';
import '../core/stick_check.dart';
import '../core/stick_state.dart';
import '../core/tilt/axis_map.dart';
import '../widgets/sync_plane.dart';
import '../widgets/v2_ui.dart';

/// Chequeo guiado de un stick, desde el banco (plan v2 §17). Lleva a quien sostiene
/// el stick por [StickCheck] y termina con una lista de lo que anda y lo que no.
/// Devuelve la calibración medida, si la hubo.
///
/// Pensada para grabar la pantalla: las lecturas del sensor quedan a la vista y el
/// resultado trae las mediciones. «Compartir datos» manda además la traza cruda.
class StickCheckScreen extends StatefulWidget {
  const StickCheckScreen({super.key, required this.role, required this.params, required this.read, required this.saveAxes, this.startTrace, this.stopTrace, this.share, this.forUsers = false, this.title});

  final Role role;
  final SyncParams params;

  /// Lectura actual del stick.
  final StickSnapshot Function() read;

  /// Aplica y guarda los ejes medidos.
  final void Function(AxisMap axes) saveAxes;

  /// Empieza a grabar la traza cruda, y la termina devolviendo su texto.
  final VoidCallback? startTrace;
  final String Function()? stopTrace;

  /// Comparte el archivo de datos (JSON).
  final Future<void> Function(String json)? share;

  /// Para usuarios: sin lecturas técnicas.
  final bool forUsers;
  final String? title;

  @override
  State<StickCheckScreen> createState() => _StickCheckScreenState();
}

class _StickCheckScreenState extends State<StickCheckScreen> with SingleTickerProviderStateMixin {
  late StickCheck _c = _newCheck();
  late final Ticker _ticker;
  final StickState _none = StickState(Role.child);
  double _now = 0;
  StickSnapshot? _snap;
  bool _tracing = false;
  String _trace = '';

  StickCheck _newCheck() => StickCheck(role: widget.role, params: widget.params, onAxes: widget.saveAxes);

  String get _who => widget.role == Role.adult ? 'adulto' : 'niño';

  void _beginTrace() {
    widget.startTrace?.call();
    _tracing = widget.startTrace != null;
    _trace = '';
  }

  void _endTrace() {
    if (!_tracing) return;
    _tracing = false;
    _trace = widget.stopTrace?.call() ?? '';
  }

  @override
  void initState() {
    super.initState();
    _beginTrace();
    _ticker = createTicker((t) {
      _now = t.inMicroseconds / 1000;
      final s = widget.read();
      _snap = s;
      _c.tick(_now, s);
      if (_c.step == CheckStep.done) _endTrace();
      setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _endTrace();
    super.dispose();
  }

  void _repeat() => setState(() {
        _c = _newCheck();
        _beginTrace();
      });

  void _share() => unawaited(widget.share!(diagnosticJson(
        kind: 'chequeo',
        when: DateTime.now(),
        params: widget.params,
        data: _c.toJson(),
        traces: {widget.role.name: _trace},
      )));

  @override
  Widget build(BuildContext context) => Theme(
        data: V2.theme,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title ?? 'Chequeo del stick del $_who', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            backgroundColor: V2.paper,
            foregroundColor: V2.ink,
            elevation: 0,
          ),
          body: SafeArea(child: _c.step == CheckStep.done ? _result() : _running()),
        ),
      );

  Widget _running() {
    final showPlane = _c.step == CheckStep.range || _c.step == CheckStep.reach;
    final index = CheckStep.values.indexOf(_c.step) + 1;
    final hint = _c.hint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Paso $index de 6', style: V2.kicker),
        const SizedBox(height: 4),
        Text(_c.title, style: V2.h2),
        const SizedBox(height: 6),
        Text(_c.instruction, style: V2.sub),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _c.progress, minHeight: 8, color: V2.olive, backgroundColor: V2.line),
        ),
        const SizedBox(height: 12),
        if (hint != null) Text(hint, style: const TextStyle(fontSize: 15, color: V2.coral, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Expanded(
          child: showPlane
              ? Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SyncPlane(
                      adult: widget.role == Role.adult ? _c.plane : _none,
                      child: widget.role == Role.child ? _c.plane : _none,
                      now: _now,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_c.step == CheckStep.reach) ...[
          const SizedBox(height: 10),
          _edges(),
        ],
        if (!widget.forUsers) ...[
          const SizedBox(height: 10),
          _live(),
        ],
      ]),
    );
  }

  /// Lecturas del momento, para que queden en la grabación de pantalla.
  Widget _live() {
    final s = _snap;
    final text = s == null || !s.live
        ? 'Sin datos del stick · $appVersion'
        : 'adelante ${s.tiltY.round()}° · lado ${s.tiltX.round()}° · fuerza ${s.accelMagG.toStringAsFixed(2)} g\n'
            '${s.hz.round()} datos/s · ${(_c.elapsedMs / 1000).toStringAsFixed(1)} s en este paso · $appVersion';
    return Text(text, textAlign: TextAlign.center, style: V2.small);
  }

  Widget _edges() {
    final r = _c.reached;
    Widget chip(String label, bool on) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: on ? V2.olive : V2.line, borderRadius: BorderRadius.circular(10)),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? Colors.white : V2.soft)),
          ),
        );
    return Row(children: [chip('Arriba', r.top), chip('Abajo', r.bottom), chip('Izquierda', r.left), chip('Derecha', r.right)]);
  }

  Widget _result() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 4, 22, 12), children: [
            Text(_c.title, style: V2.h2),
            const SizedBox(height: 12),
            for (final f in _c.findings) _finding(f),
            if (!widget.forUsers) ...[
              const SizedBox(height: 4),
              Text([..._c.dataLines, 'Versión $appVersion'].join('\n'), style: V2.small),
            ],
          ]),
        ),
        if (widget.share != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: V2.secondary('Compartir datos', _share, height: 46),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Row(children: [
            Expanded(child: V2.secondary('Repetir', _repeat, height: 50)),
            const SizedBox(width: 10),
            Expanded(child: V2.primary(widget.forUsers ? 'Listo' : 'Volver al banco', () => Navigator.pop(context, _c.cal), height: 50)),
          ]),
        ),
      ]);

  Widget _finding(CheckFinding f) {
    final (icon, color) = switch (f.grade) {
      CheckGrade.ok => (Icons.check_circle, V2.olive),
      CheckGrade.warn => (Icons.info, V2.mute),
      CheckGrade.fail => (Icons.error, V2.coral),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: V2.ink)),
            const SizedBox(height: 2),
            Text(f.detail, style: const TextStyle(fontSize: 13.5, color: V2.soft, fontWeight: FontWeight.w600, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}
