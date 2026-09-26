import 'board_session.dart';

/// Evento de pérdida o recuperación de un stick.
class LossEvent {
  const LossEvent(this.role, {required this.lost});
  final StickRole role;

  /// true = se perdió; false = se recuperó.
  final bool lost;

  @override
  String toString() => 'LossEvent(${role.name}, ${lost ? 'perdido' : 'recuperado'})';
}

/// Detecta cuándo un stick EN USO se desconecta y cuándo vuelve (Dart puro).
///
/// Solo los roles "armados" (los que la sesión está usando) generan pérdidas:
/// desconectar un stick que nadie usa no interrumpe el juego.
/// Una pérdida se reporta una sola vez hasta que el stick se recupera.
class LossMonitor {
  final Set<StickRole> _armed = {};
  final Map<StickRole, bool> _connected = {};
  final Set<StickRole> _lost = {};

  /// La sesión empieza a depender de este stick.
  void arm(StickRole role) => _armed.add(role);

  /// La sesión deja de depender de este stick (olvida una pérdida pendiente).
  void disarm(StickRole role) {
    _armed.remove(role);
    _lost.remove(role);
  }

  bool isArmed(StickRole role) => _armed.contains(role);
  bool isLost(StickRole role) => _lost.contains(role);
  Set<StickRole> get lostRoles => Set.unmodifiable(_lost);

  /// Informa el estado de conexión actual de [role]. Devuelve un evento si
  /// hubo pérdida (conectado → desconectado estando armado) o recuperación
  /// (vuelve a conectarse tras una pérdida); si no, null.
  LossEvent? update(StickRole role, {required bool connected}) {
    final was = _connected[role] ?? false;
    _connected[role] = connected;
    if (_armed.contains(role) && was && !connected && !_lost.contains(role)) {
      _lost.add(role);
      return LossEvent(role, lost: true);
    }
    if (connected && _lost.remove(role)) {
      return LossEvent(role, lost: false);
    }
    return null;
  }
}
