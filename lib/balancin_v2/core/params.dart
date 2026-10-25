/// Parámetros ajustables de la mecánica v2 (plan v2 §4.5 y §12).
///
/// Valores por defecto = `P_DEF` del prototipo, sin `vibMs` (v2 no vibra), más
/// la fusión de sensores (§4.1) y los cambios del usuario del 18-10-2026 (§12):
/// salir de la sincronía cuesta, la sincronía mira también la velocidad, la
/// frase se arma durante el nivel y las notas del niño recorren la escala en
/// vez de saltar. [SyncParams.prototype] apaga esos cambios (paridad).
///
/// §15 agrega opciones para jugar sin ver el plano (todas apagadas por
/// defecto); [SyncParams.blind] las enciende juntas.
///
/// Son mutables para el panel de ajuste del banco; se persisten con
/// [toJson] / [SyncParams.fromJson].
library;

class SyncParams {
  SyncParams();

  /// Comportamiento exacto del prototipo: sin los cambios del §12.
  factory SyncParams.prototype() => SyncParams()
    ..slipDrain = 0
    ..velWeight = 0
    ..syncLagMs = 0
    ..calMode = 0
    ..phraseSteps = 0
    ..runMaxNotes = 0;

  /// §15 · para jugar sin vista: zonas + trazo, solo el lado en «Espejo» e
  /// «Iguales», el borde no cuenta, campanita de guía, sonidos que ubican y
  /// valores más permisivos.
  factory SyncParams.blind() => SyncParams()
    ..matchMode = 3
    ..sideOnly = 1
    ..edgeNoSync = 1
    ..guideChime = 1
    ..sharedScale = 1
    ..sideTimbre = 1
    ..fifthRamp = 1
    ..tolScale = 1.3
    ..slipDrain = 0.4
    ..velWeight = 0
    ..minA = 25;

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

  /// Decaimiento del progreso por inactividad (s de progreso por s).
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

  // ---- §12.1 · salir de la sincronía cuesta ----

  /// Margen (s) fuera de la zona, moviéndose los dos, antes de empezar a perder progreso.
  double slipGrace = 0.4;

  /// Pérdida de progreso fuera de la zona tras el margen (s de progreso por s). 0 = como el prototipo.
  double slipDrain = 1;

  // ---- §12.2 · la sincronía mira la velocidad ----

  /// Peso (s) de la diferencia de velocidad en `d`: `d += velWeight·|Δv|` (u/s). 0 = solo posición.
  double velWeight = 0.06;

  // ---- §12.5 · tolerancia de retraso ----

  /// Desfase máximo (ms) entre los dos que se perdona: `d` compara al niño con el
  /// adulto corrido hasta ±syncLagMs y se queda con el mejor calce. A alta
  /// velocidad un retraso mínimo (de la persona o del Bluetooth) separa mucho los
  /// puntos; esto lo absorbe. 0 = comparar en el mismo instante (prototipo).
  double syncLagMs = 150;

  // ---- §12.6 · calibración robusta ----

  /// 1 = el centro es el medio del recorrido mientras el stick se mueve, con rango
  /// por eje (no depende de cómo estaba el stick en el primer segundo).
  /// 0 = como el prototipo: centro = promedio del primer segundo, un rango para ambos ejes.
  double calMode = 1;

  // ---- §13 · niveles 2 y 3 ----

  /// 1 = al lograr un nivel se sigue solo al siguiente habilitado (prototipo);
  /// 0 = se pasa al final después de cada nivel.
  double autoNext = 1;

  // ---- §12.3 · la frase se arma durante el nivel ----

  /// 1 = suena una nota de la frase en cada cuarto del nivel (y «cae» si se pierde). 0 = apagado.
  double phraseSteps = 1;

  // ---- §12.4 · escala de paso en las notas del niño ----

  /// Máximo de notas de paso entre dos notas lejanas. 0 = saltar directo (prototipo).
  double runMaxNotes = 6;

  /// Duración total (ms) de la escala de paso.
  double runMs = 120;

  /// Volumen de las notas de paso respecto de la nota de llegada (0–1).
  double runGain = 0.6;

  // ---- §15 · jugar sin vista ----

  /// Cómo se mide la sincronía en las relaciones de posición (Juntos, Espejo,
  /// Iguales, Sube y baja, Libre): 0 = punto (prototipo), 1 = zonas, 2 = trazo,
  /// 3 = zonas y trazo a la vez.
  double matchMode = 0;

  /// Franjas por eje en el modo zonas (3 = arriba, medio, abajo).
  double zoneCount = 3;

  /// Ventana (ms) del trazo: se compara la dirección del movimiento en este tiempo.
  double traceWinMs = 1500;

  /// Parecido mínimo del trazo (−1 a 1) para contar como sincronía.
  double traceMin = 0.6;

  /// 1 = en «Espejo» e «Iguales» solo cuenta el lado (x); la altura queda libre.
  double sideOnly = 0;

  /// 1 = si los dos están pegados al borde en el mismo eje que se mide, no cuenta.
  double edgeNoSync = 0;

  /// 1 = suena la campanita cuando cambia quién guía.
  double guideChime = 0;

  /// 1 = el niño usa la escala del adulto una octava arriba: a la misma altura, misma nota.
  double sharedScale = 0;

  /// 1 = el lado cambia el timbre (niño: marimba a la izquierda, glock a la
  /// derecha; adulto: más brillante a la derecha).
  double sideTimbre = 0;

  /// 1 = la quinta aparece de a poco al acercarse (de 2·tol a tol), no de golpe.
  double fifthRamp = 0;

  static const List<String> keys = [
    'tolScale', 'alpha', 'rangeA', 'rangeC', 'minA', 'minC', 'onSpeed', 'hyst', //
    'secScale', 'idleAfter', 'decay', 'maxDetune', 'followLag', 'rhythmWin', 'endAfter',
    'kAccel', 'accelGate',
    'slipGrace', 'slipDrain', 'velWeight', 'syncLagMs', 'calMode', 'autoNext', 'phraseSteps', 'runMaxNotes', 'runMs', 'runGain',
    'matchMode', 'zoneCount', 'traceWinMs', 'traceMin', 'sideOnly', 'edgeNoSync', 'guideChime', 'sharedScale', 'sideTimbre',
    'fifthRamp',
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
        'slipGrace' => slipGrace,
        'slipDrain' => slipDrain,
        'velWeight' => velWeight,
        'syncLagMs' => syncLagMs,
        'calMode' => calMode,
        'autoNext' => autoNext,
        'phraseSteps' => phraseSteps,
        'runMaxNotes' => runMaxNotes,
        'runMs' => runMs,
        'runGain' => runGain,
        'matchMode' => matchMode,
        'zoneCount' => zoneCount,
        'traceWinMs' => traceWinMs,
        'traceMin' => traceMin,
        'sideOnly' => sideOnly,
        'edgeNoSync' => edgeNoSync,
        'guideChime' => guideChime,
        'sharedScale' => sharedScale,
        'sideTimbre' => sideTimbre,
        'fifthRamp' => fifthRamp,
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
      case 'slipGrace':
        slipGrace = v;
      case 'slipDrain':
        slipDrain = v;
      case 'velWeight':
        velWeight = v;
      case 'syncLagMs':
        syncLagMs = v;
      case 'calMode':
        calMode = v;
      case 'autoNext':
        autoNext = v;
      case 'phraseSteps':
        phraseSteps = v;
      case 'runMaxNotes':
        runMaxNotes = v;
      case 'runMs':
        runMs = v;
      case 'runGain':
        runGain = v;
      case 'matchMode':
        matchMode = v;
      case 'zoneCount':
        zoneCount = v;
      case 'traceWinMs':
        traceWinMs = v;
      case 'traceMin':
        traceMin = v;
      case 'sideOnly':
        sideOnly = v;
      case 'edgeNoSync':
        edgeNoSync = v;
      case 'guideChime':
        guideChime = v;
      case 'sharedScale':
        sharedScale = v;
      case 'sideTimbre':
        sideTimbre = v;
      case 'fifthRamp':
        fifthRamp = v;
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

  void resetToDefaults() => setAll(SyncParams());

  /// Copia todos los valores de [o] (para los botones de valores del banco).
  void setAll(SyncParams o) {
    for (final k in keys) {
      this[k] = o[k];
    }
  }

  /// Modo de medición (§15) como enteros.
  bool get usesZones => matchMode.round() == 1 || matchMode.round() == 3;
  bool get usesTrace => matchMode.round() >= 2;
}
