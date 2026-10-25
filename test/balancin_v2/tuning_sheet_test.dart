// Panel «Ajuste» del banco: todos los parámetros, legible con el tema oscuro de
// la app y con ayuda (?) en cada control.

import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/widgets/tuning_sheet.dart';
import 'package:esp32_ble_telemetry/balancin_v2/widgets/v2_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada parámetro aparece una vez, con ayuda completa y rango que contiene el de fábrica', () {
    final specs = [for (final s in tuneSections) ...s.specs];
    expect(specs.map((t) => t.key).toSet(), SyncParams.keys.toSet());
    expect(specs.length, SyncParams.keys.length, reason: 'sin repetidos');
    final d = SyncParams();
    for (final t in specs) {
      expect(t.what.isNotEmpty && t.why.isNotEmpty && t.how.isNotEmpty, isTrue, reason: t.key);
      if (t.kind == TuneKind.slider) {
        expect(d[t.key], inInclusiveRange(t.min, t.max), reason: t.key);
      }
    }
  });

  test('los valores se leen en palabras', () {
    final mode = tuneSections.first.specs.first;
    expect(mode.format(3), 'Zonas y trazo');
    final tol = [for (final s in tuneSections) ...s.specs].firstWhere((t) => t.key == 'tolScale');
    expect(tol.format(1.25), '1,25 ×');
    final chime = [for (final s in tuneSections) ...s.specs].firstWhere((t) => t.key == 'guideChime');
    expect(chime.format(1), 'Sí');
  });

  testWidgets('se abre con el tema oscuro de la app sin desbordes, y la ayuda explica el control', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = SyncParams();
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => TuningSheet.open(context, p, save: (_) async => saves++),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Ajuste'), findsOneWidget);

    // El texto usa la tinta de la app, no el blanco del tema oscuro.
    final title = tester.widget<Text>(find.text('Medir la sincronía por'));
    expect(title.style?.color, V2.ink);

    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Qué es'), findsOneWidget);
    expect(find.text('Cómo ajustarlo'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Punto'));
    await tester.pumpAndSettle();
    expect(p.matchMode, 0);
    expect(saves, 1);

    await tester.tap(find.text('Sin vista'));
    await tester.pumpAndSettle();
    expect(p.sideOnly, 1);
    expect(p.matchMode, 3);
  });
}
