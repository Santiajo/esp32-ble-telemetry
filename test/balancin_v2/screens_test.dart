// Fase 6: pantallas del flujo del prototipo (sin sticks ni audio reales).

import 'dart:convert';

import 'package:esp32_ble_telemetry/balancin/platform/stick_hub.dart';
import 'package:esp32_ble_telemetry/balancin_v2/app_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/telemetry.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/axis_map.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/vec3.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/axis_store.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/audio_engine_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/progress_store.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/voice_prompts.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/final_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/home_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/levels_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/mode_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/pre_level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

V2Services services() => V2Services(hub: StickHub(), audio: AudioEngineV2(), voice: VoicePrompts(), params: SyncParams());

SessionRecord rec({String mode = 'levels', List<int> levels = const [1], bool song = false, double? lead = -0.2}) => SessionRecord(
      t: DateTime.now().millisecondsSinceEpoch,
      mode: mode,
      levels: levels,
      dur: 95,
      sync: 0.46,
      song: song,
      lead: lead,
      traj: [
        for (var i = 0; i < 50; i++) [i / 10 - 2.5, 2.0, i / 10 - 2.4, 1.8]
      ],
    );

Future<void> pumpPage(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('niveles', () {
    testWidgets('sin progreso: el 1 es el sugerido y los demás «Próximamente»', (tester) async {
      await pumpPage(tester, LevelsScreen(s: services()));
      expect(find.text('¿Qué van a jugar hoy?'), findsOneWidget);
      expect(find.text('0 de 7 partes'), findsOneWidget);
      expect(find.text('1 · Juntos'), findsOneWidget);
      expect(find.text('Sugerido'), findsOneWidget);
      expect(find.text('Próximamente'), findsNWidgets(4), reason: 'del 4 al 7');
      expect(find.text('Primero el nivel 1'), findsOneWidget);
      expect(find.text('Primero el nivel 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el nivel 1 logrado dice «Lograda»', (tester) async {
      SharedPreferences.setMockInitialValues({ProgressStore.progressKey: jsonEncode([1])});
      await pumpPage(tester, LevelsScreen(s: services()));
      expect(find.text('Lograda'), findsOneWidget);
      expect(find.text('1 de 7 partes'), findsOneWidget);
    });
  });

  testWidgets('antes del nivel: consigna, guía y botón', (tester) async {
    await pumpPage(tester, PreLevelScreen(s: services(), level: levels.first));
    expect(find.text('Nivel 1 de 7 · Fácil'), findsOneWidget);
    expect(find.text('Juntos'), findsOneWidget);
    expect(find.text('Guía el adulto, luego el niño'), findsOneWidget);
    expect(find.text('Insertar el teléfono y comenzar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modo: Libre y Niveles', (tester) async {
    await pumpPage(tester, ModeScreen(s: services()));
    expect(find.text('¿Cómo quieren jugar?'), findsOneWidget);
    expect(find.text('Libre'), findsOneWidget);
    expect(find.text('Niveles'), findsOneWidget);
    expect(find.text('0 de 7 partes de la canción'), findsOneWidget);
  });

  group('final', () {
    testWidgets('nivel logrado: título, canción y botones', (tester) async {
      await pumpPage(tester, FinalScreen(s: services(), record: rec(), fresh: const [1]));
      expect(find.text('Sumaron una parte de la canción.'), findsOneWidget);
      expect(find.text('2 min · 46 % del tiempo en sincronía'), findsOneWidget);
      expect(find.text('Esta vez el adulto siguió más al niño.'), findsOneWidget);
      expect(find.text('Escuchar la canción'), findsOneWidget);
      expect(find.text('Guardar el recuerdo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Libre: «Sonaron juntos» y «Jugar otra vez», sin barra de la canción', (tester) async {
      await pumpPage(tester, FinalScreen(s: services(), record: rec(mode: 'free', levels: const []), fresh: const []));
      expect(find.text('Sonaron juntos.'), findsOneWidget);
      expect(find.text('Jugar otra vez'), findsOneWidget);
      expect(find.text('La canción'), findsNothing);
    });

    testWidgets('sin niveles: «Hoy fue de práctica»', (tester) async {
      await pumpPage(tester, FinalScreen(s: services(), record: rec(levels: const [], lead: null), fresh: const []));
      expect(find.text('Hoy fue de práctica.'), findsOneWidget);
    });
  });

  testWidgets('inicio: Jugar, sesión guardada e idea para hoy', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ProgressStore.addSession(rec());
    await pumpPage(tester, HomeV2(s: services()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Jugar'), findsOneWidget);
    expect(find.text('Hoy · 1 parte'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Herramientas del equipo'), 200);
    expect(find.text('IDEA PARA HOY'), findsOneWidget);
    expect(find.text('Herramientas del equipo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ninguna pantalla se desborda en un teléfono angosto (360 × 740)', (tester) async {
    SharedPreferences.setMockInitialValues({ProgressStore.progressKey: jsonEncode([1])});
    await ProgressStore.addSession(rec());
    final pages = <String, Widget Function()>{
      'inicio': () => HomeV2(s: services()),
      'modo': () => ModeScreen(s: services()),
      'niveles': () => LevelsScreen(s: services()),
      'antes del nivel': () => PreLevelScreen(s: services(), level: levels.first),
      'final': () => FinalScreen(s: services(), record: rec(), fresh: const [1]),
      'final libre': () => FinalScreen(s: services(), record: rec(mode: 'free', levels: const []), fresh: const []),
    };
    for (final e in pages.entries) {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      await tester.pumpWidget(MaterialApp(home: e.value()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: e.key);
    }
  });

  testWidgets('con el 1 logrado, el 2 se abre y se puede entrar a su previa', (tester) async {
    SharedPreferences.setMockInitialValues({ProgressStore.progressKey: jsonEncode([1])});
    await pumpPage(tester, LevelsScreen(s: services()));
    expect(find.text('Sugerido'), findsOneWidget);
    expect(find.text('Primero el nivel 1'), findsNothing);
    expect(find.text('Primero el nivel 2'), findsOneWidget, reason: 'el 3 sigue esperando al 2');
    await tester.tap(find.text('2 · Espejo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nivel 2 de 7 · Fácil'), findsOneWidget);
    expect(find.text('Guía el niño, luego el adulto'), findsOneWidget);
  });

  test('ejes por stick: se guardan y se leen por MAC', () async {
    SharedPreferences.setMockInitialValues({});
    final m = AxisMap.fromRight(V3.ez, V3.ey)!;
    await AxisStore.save('aa:bb:cc:dd:ee:ff', m);
    final back = await AxisStore.load('AA:BB:CC:DD:EE:FF');
    expect(back, isNotNull);
    expect(back!.right.angleTo(m.right), lessThan(1e-9));
    expect(await AxisStore.load('11:22:33:44:55:66'), isNull);
    expect(await AxisStore.load(null), isNull);
    await AxisStore.clear('aa:bb:cc:dd:ee:ff');
    expect(await AxisStore.load('aa:bb:cc:dd:ee:ff'), isNull);
  });

  test('progreso y sesiones: guardar y leer', () async {
    SharedPreferences.setMockInitialValues({});
    await ProgressStore.addProgress(1);
    await ProgressStore.addProgress(1);
    expect(await ProgressStore.progress(), [1]);
    await ProgressStore.addSession(rec(levels: const [1]));
    await ProgressStore.addSession(SessionRecord(t: 1, mode: 'free', levels: const [], dur: 1, sync: 0, song: false, lead: null, traj: const []));
    expect((await ProgressStore.sessions()).length, 1, reason: 'las de 2 s o menos no se guardan');
    expect(await ProgressStore.onboarded(), isFalse);
    await ProgressStore.setOnboarded();
    expect(await ProgressStore.onboarded(), isTrue);
  });
}
