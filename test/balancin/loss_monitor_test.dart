import 'package:esp32_ble_telemetry/balancin/session/board_session.dart';
import 'package:esp32_ble_telemetry/balancin/session/loss_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un stick armado que se desconecta genera UNA pérdida', () {
    final m = LossMonitor()..arm(StickRole.child);
    expect(m.update(StickRole.child, connected: true), isNull);
    final ev = m.update(StickRole.child, connected: false);
    expect(ev, isNotNull);
    expect(ev!.role, StickRole.child);
    expect(ev.lost, isTrue);
    expect(m.isLost(StickRole.child), isTrue);
    // Sigue desconectado: no se repite.
    expect(m.update(StickRole.child, connected: false), isNull);
  });

  test('al reconectarse tras una pérdida genera una recuperación', () {
    final m = LossMonitor()..arm(StickRole.child);
    m.update(StickRole.child, connected: true);
    m.update(StickRole.child, connected: false);
    final ev = m.update(StickRole.child, connected: true);
    expect(ev, isNotNull);
    expect(ev!.lost, isFalse);
    expect(m.isLost(StickRole.child), isFalse);
  });

  test('un stick no armado no interrumpe el juego', () {
    final m = LossMonitor();
    m.update(StickRole.adult, connected: true);
    expect(m.update(StickRole.adult, connected: false), isNull);
    expect(m.lostRoles, isEmpty);
  });

  test('un stick que nunca estuvo conectado no se "pierde"', () {
    final m = LossMonitor()..arm(StickRole.child);
    expect(m.update(StickRole.child, connected: false), isNull);
  });

  test('disarm olvida la pérdida pendiente', () {
    final m = LossMonitor()..arm(StickRole.child);
    m.update(StickRole.child, connected: true);
    m.update(StickRole.child, connected: false);
    m.disarm(StickRole.child);
    expect(m.isLost(StickRole.child), isFalse);
    expect(m.update(StickRole.child, connected: true), isNull);
  });

  test('los roles son independientes', () {
    final m = LossMonitor()
      ..arm(StickRole.adult)
      ..arm(StickRole.child);
    m.update(StickRole.adult, connected: true);
    m.update(StickRole.child, connected: true);
    final ev = m.update(StickRole.adult, connected: false);
    expect(ev!.role, StickRole.adult);
    expect(m.isLost(StickRole.child), isFalse);
  });
}
