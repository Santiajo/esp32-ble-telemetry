/// Parámetros ajustables de la mecánica v2 (plan v2 §4.5).
///
/// Valores por defecto = `P_DEF` del prototipo, sin `vibMs` (v2 no vibra) y con
/// los dos parámetros de la fusión de sensores (§4.1). Son mutables para el
/// panel de ajuste del banco; se persisten con [toJson]/[SyncParams.fromJson].
library;

class SyncParams {
  SyncParams();

  /// Multiplica la tolerancia de cada nivel.
  double tolScale = 1;

  /// Suavizado de posición α (se aplica como `α·1,6`).
  double alpha = 0.2;

  /// Medio rango por defecto (°) del adulto y del niño, sin calibrar.
  double rangeA = 30;
  double rangeC = 45;

  /// Medio rango mínimo (°) tras calibrar.
  double minA = 15;
  double minC = 25;

  /// Velocidad en el plano (u/s) sobre la que una persona cuenta como activa.
  double onSpeed = 2.5;

  /// Histéresis de la sincronía: se mantiene mientras `d ≤ hyst·tol`.
  double hyst = 1.25;

  /// Multiplica los segundos por nivel.
  double secScale = 1;

  /// Inactividad (s) antes de que el progreso empiece a decaer.
  double idleAfter = 3;

  /// Decaimiento del progreso (s de progreso por s).
  double decay = 0.5;

  /// Desafinación máxima del tono de relación (Hz).
  double maxDetune = 4;

  /// Retraso máximo (s) que se tolera en «Sígueme».
  double followLag = 0.8;

  /// Ventana (s) para medir el ritmo.
  double rhythmWin = 3;

  /// Inactividad (s) tras la que se cierra la sesión en el flujo de usuario.
  double endAfter = 30;

  /// Fusión de sensores (§4.1): peso de la corrección del acelerómetro por muestra.
  double kAccel = 0.02;

  /// Fusión de sensores (§4.1): desvío máximo de |a| respecto del reposo (g) para corregir.
  double accelGate = 0.15;

  static const List<String> keys = [
    'tolScale', 'alpha', 'rangeA', 'rangeC', 'minA', 'minC', 'onSpeed', 'hyst', //
    'secScale', 'idleAfter', 'decay', 'maxDetune', 'followLag', 'rhythmWin', 'endAfter',
    'kAccel', 'accelGate',
  ];

  double operator [](String k) => switch (k) {
        'tolScale' => tolScale,
        'alpha' => alpha,
        'rangeA' => rangeA,
        'rangeC' => rangeC,
        'minA' => minA,
        'minC' => minC,
        'onSpeed' => onSpeed,
        'hyst' => hyst,
        'secScale' => secScale,
        'idleAfter' => idleAfter,
        'decay' => decay,
        'maxDetune' => maxDetune,
        'followLag' => followLag,
        'rhythmWin' => rhythmWin,
        'endAfter' => endAfter,
        'kAccel' => kAccel,
        'accelGate' => accelGate,
        _ => throw ArgumentError.value(k, 'k', 'parámetro desconocido'),
      };

  void operator []=(String k, double v) {
    switch (k) {
      case 'tolScale':
        tolScale = v;
      case 'alpha':
        alpha = v;
      case 'rangeA':
        rangeA = v;
      case 'rangeC':
        rangeC = v;
      case 'minA':
        minA = v;
      case 'minC':
        minC = v;
      case 'onSpeed':
        onSpeed = v;
      case 'hyst':
        hyst = v;
      case 'secScale':
        secScale = v;
      case 'idleAfter':
        idleAfter = v;
      case 'decay':
        decay = v;
      case 'maxDetune':
        maxDetune = v;
      case 'followLag':
        followLag = v;
      case 'rhythmWin':
        rhythmWin = v;
      case 'endAfter':
        endAfter = v;
      case 'kAccel':
        kAccel = v;
      case 'accelGate':
        accelGate = v;
      default:
        throw ArgumentError.value(k, 'k', 'parámetro desconocido');
    }
  }

  Map<String, double> toJson() => {for (final k in keys) k: this[k]};

  /// Ignora claves desconocidas y valores no numéricos (datos guardados de otra versión).
  factory SyncParams.fromJson(Map<String, Object?> json) {
    final p = SyncParams();
    for (final k in keys) {
      final v = json[k];
      if (v is num && v.isFinite) p[k] = v.toDouble();
    }
    return p;
  }

  SyncParams copy() => SyncParams.fromJson(toJson());

  void resetToDefaults() {
    final d = SyncParams();
    for (final k in keys) {
      this[k] = d[k];
    }
  }
}
