import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../app_v2.dart';
import '../core/sync_engine.dart';
import '../core/telemetry.dart';
import '../platform/progress_store.dart';
import '../widgets/v2_ui.dart';
import 'insert_v2_screen.dart';

/// El recuerdo (`#final` del prototipo): título según lo logrado, duración y
/// sincronía, la canción con la parte nueva marcada, el dibujo de lo que
/// hicieron los sticks y quién guió. «Escuchar la canción» (o «Jugar otra vez»
/// en Libre) y «Guardar el recuerdo» como imagen. Plan v2 §10.2.
class FinalScreen extends StatefulWidget {
  const FinalScreen({super.key, required this.s, required this.record, required this.fresh, this.fromHistory = false});
  final V2Services s;
  final SessionRecord record;

  /// Niveles logrados en esta sesión (con anillo en la barra).
  final List<int> fresh;

  /// Abierto desde «Sesiones pasadas».
  final bool fromHistory;

  @override
  State<FinalScreen> createState() => _FinalScreenState();
}

class _FinalScreenState extends State<FinalScreen> {
  final GlobalKey _memoKey = GlobalKey();
  List<int> _got = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final g = await ProgressStore.progress();
    if (mounted) setState(() => _got = g);
  }

  SessionRecord get r => widget.record;

  String get _title {
    if (r.song) return 'Terminaron la canción.';
    if (r.isFree) return 'Sonaron juntos.';
    if (r.levels.isNotEmpty) {
      return r.levels.length == 1 ? 'Sumaron una parte de la canción.' : 'Sumaron ${r.levels.length} partes de la canción.';
    }
    return 'Hoy fue de práctica.';
  }

  String get _sub {
    final mins = (r.dur / 60).round();
    final dur = mins >= 1 ? '$mins min' : '${r.dur.round()} s';
    return '$dur · ${(r.sync * 100).round()} % del tiempo en sincronía';
  }

  String get _lead {
    final l = r.lead;
    if (l == null) return '';
    if (l < -0.05) return 'Esta vez el adulto siguió más al niño.';
    if (l > 0.05) return 'Esta vez el niño siguió más al adulto.';
    return 'Se guiaron por turnos.';
  }

  void _home() => Navigator.of(context).popUntil((route) => route.isFirst);

  void _primary() {
    if (r.isFree) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => InsertV2Screen(s: widget.s, mode: PlayMode.free),
      ));
      return;
    }
    final ids = _got.isEmpty ? [1] : (List.of(_got)..sort());
    unawaited(widget.s.audio.playSong(ids));
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _memoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      final name = 'balancin-recuerdo-${DateTime.now().millisecondsSinceEpoch}';
      try {
        final ok = await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);
        if (ok) {
          await Gal.putImageBytes(bytes, album: 'Balancín', name: name);
          messenger.showSnackBar(const SnackBar(content: Text('Recuerdo guardado en la galería')));
          return;
        }
      } catch (_) {}
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: '$name.png')],
        fileNameOverrides: ['$name.png'],
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar el recuerdo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: Theme(
        data: V2.theme,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: V2.paper,
            foregroundColor: V2.ink,
            elevation: 0,
            leading: BackButton(onPressed: _home),
          ),
          body: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 16), children: [
                Text(_title, textAlign: TextAlign.center, style: V2.h1()),
                const SizedBox(height: 6),
                Text(_sub, textAlign: TextAlign.center, style: V2.sub),
                const SizedBox(height: 16),
                if (!r.isFree) ...[
                  Row(children: [
                    const Expanded(child: Text('La canción', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: V2.mute))),
                    Text('${_got.length} de 7 partes', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: V2.mute)),
                  ]),
                  const SizedBox(height: 8),
                  SongBar(got: _got, fresh: widget.fresh),
                  const SizedBox(height: 16),
                ],
                RepaintBoundary(
                  key: _memoKey,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    child: Column(children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.min(400, w)),
                        child: MemoDrawing(traj: r.traj),
                      ),
                      const SizedBox(height: 10),
                      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _Legend(color: V2.lilaInk, label: 'Adulto'),
                        SizedBox(width: 14),
                        _Legend(color: V2.coral, label: 'Niño'),
                      ]),
                    ]),
                  ),
                ),
                if (_lead.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(_lead, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: V2.soft, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
            Container(
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x1A2B2536), offset: Offset(0, -1))]),
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              child: SafeArea(
                top: false,
                child: Row(children: [
                  Expanded(child: V2.primary(r.isFree ? 'Jugar otra vez' : 'Escuchar la canción', _primary, height: 56)),
                  const SizedBox(width: 10),
                  Expanded(child: V2.secondary('Guardar el recuerdo', _save)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 18, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: V2.soft)),
      ]);
}
