import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_ble_telemetry/core/physics/physics_engine.dart';

void main() {
  group('PhysicsEngine Unit Tests', () {
    late PhysicsEngine engine;

    setUp(() {
      engine = PhysicsEngine();
    });

    test('conversión de LSB a m/s2 es exacta con factor 9.81 / 16384', () {
      expect(PhysicsEngine.rawToMs2, closeTo(9.81 / 16384.0, 0.000001));
    });

    test('calibración de centro (Tara) descuenta el offset en lecturas posteriores', () {
      // 16384 raw = 1g = 9.81 m/s²
      engine.calibrar(16384, 0);
      expect(engine.offsetX, closeTo(9.81, 0.001));
      expect(engine.offsetY, closeTo(0.0, 0.001));

      // Si vuelve a leer 16384, el valor neto axTotal es 0
      engine.procesarLectura(16384, 0);
      expect(engine.ultimaAccX, closeTo(0.0, 0.001));
    });

    test('filtro descarta lecturas absurdas > 35 m/s²', () {
      // Valor crudo muy grande (~100 m/s²)
      engine.procesarLectura(16384 * 10, 0);
      expect(engine.ultimaAccX, equals(0.0));
      expect(engine.accX, equals(0.0));
    });

    test('filtro anti-picos descarta pico aislado pero se adapta tras 3 rechazos consecutivos', () {
      // Paso 1: Establecer lectura base en reposo
      engine.procesarLectura(0, 0);
      expect(engine.ultimaAccX, equals(0.0));

      // Paso 2: Pico repentino mayor a MAX_DELTA_ACC (15 m/s²), ej: 20 m/s² (33400 raw)
      const rawPico = 33400; // ~ 20.0 m/s²
      engine.procesarLectura(rawPico, 0);
      expect(engine.rechazosConsecutivos, equals(1));
      expect(engine.ultimaAccX, equals(0.0)); // No actualiza con el pico 1

      engine.procesarLectura(rawPico, 0);
      expect(engine.rechazosConsecutivos, equals(2));
      expect(engine.ultimaAccX, equals(0.0)); // No actualiza con el pico 2

      // Paso 3: Al 3er rechazo, acepta el nuevo nivel sostenido
      engine.procesarLectura(rawPico, 0);
      expect(engine.rechazosConsecutivos, equals(0));
      expect(engine.ultimaAccX, closeTo(20.0, 0.2));
    });

    test('resetPosicion reinicia velocidades y coordenadas a cero', () {
      engine.posX = 25.0;
      engine.posY = -30.0;
      engine.velX = 1.5;
      engine.velY = -2.0;

      engine.resetPosicion();

      expect(engine.posX, equals(0.0));
      expect(engine.posY, equals(0.0));
      expect(engine.velX, equals(0.0));
      expect(engine.velY, equals(0.0));
    });

    test('límites espaciales impiden superar +/- 58 cm', () {
      engine.posX = 57.0;
      engine.velX = 3.0; // empujando hacia afuera
      // Simula integración manual
      engine.posX += 10.0; // se pasaría a 67
      engine.integrarFisica();

      expect(engine.posX, lessThanOrEqualTo(PhysicsEngine.limitePosicion));
      expect(engine.velX, equals(0.0)); // Velocidad que empuja al borde se anula
    });
  });
}
