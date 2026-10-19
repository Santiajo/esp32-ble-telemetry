import 'dart:async';

import 'package:flutter/material.dart';

import '../app_v2.dart';
import '../core/levels.dart';
import '../platform/progress_store.dart';
import '../widgets/v2_ui.dart';
import 'pre_level_screen.dart';

/// «¿Qué van a jugar hoy?» (`#levels` del prototipo): la canción y los siete
/// niveles. Se avanza en orden (un nivel se abre al lograr el anterior) y en
/// esta versión solo se puede jugar el nivel 1 (decisión V4): los demás dicen
/// «Próximamente».
class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key, required this.s});
  final V2Services s;

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
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

  bool _open(Level l) => l.id == 1 || _got.contains(l.id) || _got.contains(l.id - 1);

  @override
  Widget build(BuildContext context) {
    final sug = levels.where((l) => !_got.contains(l.id) && enabledLevelIds.contains(l.id)).firstOrNull?.id;
    return Theme(
      data: V2.theme,
      child: Scaffold(
        appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28), children: [
            Text('¿Qué van a jugar hoy?', textAlign: TextAlign.center, style: V2.h1()),
            const SizedBox(height: 6),
            const Text('Terminen la canción juntos, nivel a nivel.', textAlign: TextAlign.center, style: V2.sub),
            const SizedBox(height: 18),
            Row(children: [
              const Expanded(child: Text('La canción', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: V2.mute))),
              Text('${_got.length} de 7 partes', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: V2.mute)),
            ]),
            const SizedBox(height: 8),
            SongBar(got: _got),
            const SizedBox(height: 14),
            _grid(sug),
          ]),
        ),
      ),
    );
  }

  Widget _grid(int? sug) {
    final rows = <Widget>[];
    for (var i = 0; i < 6; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _card(levels[i], sug)),
          const SizedBox(width: 10),
          Expanded(child: _card(levels[i + 1], sug)),
        ]),
      ));
      rows.add(const SizedBox(height: 10));
    }
    rows.add(_card(levels[6], sug, wide: true));
    return Column(children: rows);
  }

  Widget _card(Level l, int? sug, {bool wide = false}) {
    final enabled = enabledLevelIds.contains(l.id);
    final locked = !_open(l) || !enabled;
    final got = _got.contains(l.id);
    final tag = got
        ? _tag('Lograda', V2.olive, Colors.white)
        : !enabled
            ? _tag('Próximamente', V2.line, V2.soft)
            : l.id == sug
                ? _tag('Sugerido', V2.ink, Colors.white)
                : locked
                    ? _tag('Primero el nivel ${l.id - 1}', V2.line, V2.soft)
                    : null;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('${l.id} · ${l.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.1, color: V2.ink)),
      const SizedBox(height: 4),
      Text(l.text, style: const TextStyle(fontSize: 12.5, color: V2.soft, fontWeight: FontWeight.w600, height: 1.3)),
      const SizedBox(height: 8),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 5, runSpacing: 4, children: [
        for (var k = 1; k <= 3; k++)
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: k <= l.difficulty ? V2.ink : V2.line)),
        Text(' ${l.difficultyName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: V2.mute)),
        ?tag,
      ]),
    ]);
    final body = wide
        ? Row(children: [LevelPictogram(level: l, locked: locked), const SizedBox(width: 14), Expanded(child: text)])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LevelPictogram(level: l, locked: locked),
            const SizedBox(height: 10),
            text,
          ]);
    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: locked
              ? null
              : () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PreLevelScreen(s: widget.s, level: l)));
                  await _load();
                },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: l.id == sug
                ? BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: V2.ink, width: 2.5))
                : null,
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
      );
}
