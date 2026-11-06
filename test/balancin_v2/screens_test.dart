// Fase 6: pantallas del flujo del prototipo (sin sticks ni audio reales).

import 'dart:convert';

import 'package:esp32_ble_telemetry/balancin/platform/stick_hub.dart';
import 'package:esp32_ble_telemetry/balancin/session/board_session.dart' show StickRole;
import 'package:esp32_ble_telemetry/balancin_v2/app_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/levels.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/params.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/stick_state.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/sync_engine.dart' show PlayMode;
import 'package:esp32_ble_telemetry/balancin_v2/core/telemetry.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/axis_map.dart';
import 'package:esp32_ble_telemetry/balancin_v2/core/tilt/vec3.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/axis_store.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/bias_store.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/cal_store.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/audio_engine_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/progress_store.dart';
import 'package:esp32_ble_telemetry/balancin_v2/platform/voice_prompts.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/calibrate_sticks_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/final_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/home_v2.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/levels_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/mode_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/play_eje_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/pre_level_screen.dart';
import 'package:esp32_ble_telemetry/balancin_v2/screens/sticks_gate_screen.dart';
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
    testWidgets('sin progreso: el 1 es el sugerido y ninguno está bloqueado', (tester) async {
      await pumpPage(tester, LevelsScreen(s: services()));
      expect(find.text('¿Qué van a jugar hoy?'), findsOneWidget);
      expect(find.text('0 de 7 partes'), findsOneWidget);
      expect(find.text('1 · Juntos'), findsOneWidget);
      expect(find.text('Sugerido'), findsOneWidget);
      expect(find.text('Próximamente'), findsNothing);
      expect(find.textContaining('Primero el nivel'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('se puede entrar a cualquier nivel sin haber logrado los anteriores', (tester) async {
      await pumpPage(tester, LevelsScreen(s: services()));
      await tester.ensureVisible(find.text('7 · La canción'));
      await tester.pump();
      await tester.tap(find.text('7 · La canción'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nivel 7 de 7 · Difícil'), findsOneWidget);
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

  testWidgets('con el 1 logrado, el 2 pasa a ser el sugerido y se entra a su previa', (tester) async {
    SharedPreferences.setMockInitialValues({ProgressStore.progressKey: jsonEncode([1])});
    await pumpPage(tester, LevelsScreen(s: services()));
    expect(find.text('Sugerido'), findsOneWidget);
    await tester.tap(find.text('2 · Espejo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nivel 2 de 7 · Fácil'), findsOneWidget);
    expect(find.text('Guía el niño, luego el adulto'), findsOneWidget);
  });

  group('sticks antes de jugar', () {
    testWidgets('sin sticks no se llega a la partida: pasa por «Conecten los sticks»', (tester) async {
      await pumpPage(tester, PreLevelScreen(s: services(), level: levels.first));
      await tester.tap(find.text('Insertar el teléfono y comenzar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Conecten los sticks'), findsOneWidget);
      expect(find.text('Coloca el celular en el eje'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Libre también pasa por el control', (tester) async {
      await pumpPage(tester, ModeScreen(s: services()));
      await tester.tap(find.text('Libre'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Conecten los sticks'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    Future<void> gate(WidgetTester tester, Set<StickRole> ready, {Size size = const Size(400, 900)}) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(MaterialApp(
        home: SticksGateScreen(s: services(), mode: PlayMode.free, isReady: ready.contains),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    FilledButton continueButton(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton));

    testWidgets('con un solo stick el botón sigue apagado', (tester) async {
      await gate(tester, {StickRole.adult});
      expect(find.text('Esperando los sticks'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);
      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Conectar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('con los dos se puede continuar, sin desbordes en un teléfono angosto', (tester) async {
      await gate(tester, StickRole.values.toSet(), size: const Size(360, 640));
      expect(find.text('Continuar'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    test('un stick sin enlace no está listo', () {
      expect(stickReady(StickHub(), StickRole.adult), isFalse);
    });
  });

  group('calibrar los sticks', () {
    testWidgets('desde el inicio se llega, y sin sticks pide conectarlos primero', (tester) async {
      await pumpPage(tester, HomeV2(s: services()));
      await tester.tap(find.text('Calibrar los sticks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Conecten los sticks'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('con los sticks listos, el control sigue a la calibración', (tester) async {
      final s = services();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(MaterialApp(
        home: SticksGateScreen(s: s, mode: PlayMode.free, isReady: (_) => true, next: () => CalibrateSticksScreen(s: s)),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Calibrar los sticks'), findsOneWidget);
      expect(find.text('Sin calibrar'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la pantalla explica que hay que inclinar y cabe en un teléfono angosto', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(MaterialApp(home: CalibrateSticksScreen(s: services())));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('hay que inclinar la punta'), findsOneWidget);
      expect(find.text('Calibrar'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    test('la calibración se guarda y se lee por MAC', () async {
      SharedPreferences.setMockInitialValues({});
      await CalStore.save('aa:bb:cc:dd:ee:ff', const StickCal(cx: 2, cy: -7, hr: 0, hrX: 30, hrY: 35));
      final c = await CalStore.load('AA:BB:CC:DD:EE:FF');
      expect((c!.cx, c.cy, c.hrX, c.hrY), (2, -7, 30, 35));
      expect(await CalStore.load('11:22:33:44:55:66'), isNull);
      expect(await CalStore.load(null), isNull);
    });
  });

  test('aviso del final: quién no se calibró', () {
    expect(calibrationNote(adult: true, child: true), isNull);
    expect(calibrationNote(adult: true, child: false), startsWith('El stick del niño no se movió'));
    expect(calibrationNote(adult: false, child: true), startsWith('El stick del adulto no se movió'));
    expect(calibrationNote(adult: false, child: false), startsWith('Los dos sticks'));
  });

  testWidgets('el final muestra el aviso de calibración', (tester) async {
    await pumpPage(tester, FinalScreen(s: services(), record: rec(), fresh: const [1], calNote: 'No se calibró.'));
    await tester.scrollUntilVisible(find.text('No se calibró.'), 200);
    expect(find.text('No se calibró.'), findsOneWidget);
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

  test('error del giroscopio por stick: se guarda y se lee por MAC', () async {
    SharedPreferences.setMockInitialValues({});
    await BiasStore.save('aa:bb:cc:dd:ee:ff', const V3(41.6, -0.2, 0.3), 1.16);
    final back = await BiasStore.load('AA:BB:CC:DD:EE:FF');
    expect(back, isNotNull);
    expect(back!.bias.x, 41.6);
    expect(back.restMag, 1.16);
    expect(await BiasStore.load('11:22:33:44:55:66'), isNull);
    expect(await BiasStore.load(null), isNull);
    await BiasStore.save('aa:bb:cc:dd:ee:ff', V3.zero, 0); // |a| imposible: se descarta al leer
    expect(await BiasStore.load('aa:bb:cc:dd:ee:ff'), isNull);
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
