import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_ble_telemetry/balancin/widgets/hold_button.dart';

void main() {
  testWidgets('HoldButton: se cancela si se suelta antes de 3 s',
      (WidgetTester tester) async {
    bool doneCalled = false;
    bool startCalled = false;
    bool cancelCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HoldButton(
              label: 'Mantener pulsado',
              doneLabel: 'Completado',
              onPressStart: () => startCalled = true,
              onDone: () => doneCalled = true,
              onCancel: () => cancelCalled = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mantener pulsado'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Mantener pulsado')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(startCalled, isTrue);
    expect(doneCalled, isFalse);

    // Mantenemos 1.5 s y soltamos
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pump();

    expect(cancelCalled, isTrue);
    expect(doneCalled, isFalse);
    expect(find.text('Mantener pulsado'), findsOneWidget);
  });

  testWidgets('HoldButton: completa tras 3 s continuos y muestra doneLabel',
      (WidgetTester tester) async {
    bool doneCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HoldButton(
              label: 'Mantener pulsado',
              doneLabel: 'Completado con éxito',
              onDone: () => doneCalled = true,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(find.text('Mantener pulsado')));
    await tester.pump();

    // Avanzar 3.1 segundos
    await tester.pump(const Duration(milliseconds: 3100));
    await gesture.up();
    await tester.pump();

    expect(doneCalled, isTrue);
    expect(find.text('Completado con éxito'), findsOneWidget);
  });
}
