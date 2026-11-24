import 'dart:async';

import 'package:esp32_ble_telemetry/epu/datos/niveles.dart';
import 'package:esp32_ble_telemetry/epu/juego/estado_juego.dart';
import 'package:esp32_ble_telemetry/epu/juego/fuente_sticks.dart';
import 'package:esp32_ble_telemetry/epu_app/juego_eco_real.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fuente extends FuenteSticksSimulada {
  final ctrl = StreamController<LecturaStick>.broadcast(sync: true);
  @override
  Stream<LecturaStick> get lecturas => ctrl.stream;
  void mandar(Stick s) => ctrl.add(LecturaStick(stick: s, lateral: 0, frontal: 0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime ahora;
  late _Fuente fuente;
  late List<Stick> perdidos;
  late JuegoEcoReal juego;

  setUp(() {
    ahora = DateTime(2026, 11, 23, 12);
    fuente = _Fuente();
    perdidos = [];
    juego = JuegoEcoReal(
      fuente: fuente,
      nivel: niveles.first,
      estado: EstadoJuegoEco(),
      alTerminar: () {},
      alPerderStick: perdidos.add,
      reloj: () => ahora,
    )..iniciar();
  });
  tearDown(() => juego.detener());

  void avanzar(int ms) {
    ahora = ahora.add(Duration(milliseconds: ms));
    juego.pasoParaPruebas();
  }

  test('con datos de los dos sticks no avisa nada', () {
    for (var i = 0; i < 100; i++) {
      fuente
        ..mandar(Stick.grande)
        ..mandar(Stick.pequeno);
      avanzar(50);
    }
    expect(perdidos, isEmpty);
  });

  test('un stick 2 s sin datos abre «Se perdió un stick» una sola vez', () {
    for (var i = 0; i < 20; i++) {
      fuente
        ..mandar(Stick.grande)
        ..mandar(Stick.pequeno);
      avanzar(50);
    }
    for (var i = 0; i < 60; i++) {
      fuente.mandar(Stick.grande);
      avanzar(50);
    }
    expect(perdidos, [Stick.pequeno]);
  });

  test('un stick que nunca mandó datos también cuenta como perdido', () {
    for (var i = 0; i < 30; i++) {
      fuente.mandar(Stick.pequeno);
      avanzar(100);
    }
    expect(perdidos, [Stick.grande]);
  });
}
