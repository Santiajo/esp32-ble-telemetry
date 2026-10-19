import 'package:flutter/material.dart';

import '../app_v2.dart';
import '../core/levels.dart';
import '../core/sync_engine.dart';
import '../widgets/v2_ui.dart';
import 'insert_v2_screen.dart';

/// Antes de cada nivel (`#pre` del prototipo): dibujo, consigna, quién guía y
/// «Insertar el teléfono y comenzar».
class PreLevelScreen extends StatelessWidget {
  const PreLevelScreen({super.key, required this.s, required this.level});
  final V2Services s;
  final Level level;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Theme(
      data: V2.theme,
      child: Scaffold(
        appBar: AppBar(backgroundColor: V2.paper, foregroundColor: V2.ink, elevation: 0),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 220, maxHeight: h * 0.46),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    alignment: Alignment.center,
                    child: LayoutBuilder(
                      builder: (context, c) => LevelPictogram(level: level, width: (c.maxWidth * 0.82).clamp(0, 320).toDouble()),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Nivel ${level.id} de 7 · ${level.difficultyName}', style: V2.kicker),
              const SizedBox(height: 4),
              Text(level.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: V2.ink)),
              const SizedBox(height: 6),
              Text(level.text, style: const TextStyle(fontSize: 15, color: V2.soft)),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: GuideChip(level: level)),
              const Spacer(),
              V2.primary(
                'Insertar el teléfono y comenzar',
                () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => InsertV2Screen(s: s, mode: PlayMode.levels, levelIndex: level.id - 1),
                )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
