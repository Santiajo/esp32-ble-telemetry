/// Constantes del Balancín.
///
/// Todos los valores salen del prototipo `reference/nuevo-prototipo/index.html`
/// (decisión D1 del plan: el prototipo manda). Ver docs/PLAN_BALANCIN.md §4.
/// Tiempos en milisegundos salvo que el nombre diga otra cosa.
abstract final class BalancinConst {
  // ---------------- Escala ----------------
  static const int numNotes = 25;
  static const int baseMidi = 48; // C3
  static const List<int> pentatonicOffsets = [0, 2, 4, 7, 9]; // C D E G A

  // ---------------- Lectura de gesto (dedo / puntero) ----------------
  static const double historyMs = 1000; // posiciones que se guardan
  static const double ampWindowMs = 800; // ventana de amplitud
  static const double shakeWindowMs = 600; // ventana de sacudida
  static const int shakeInversions = 4; // inversiones mínimas para "sacudida"
  static const double movingWindowMs = 200; // "se movió hace menos de…"
  static const double velEmaKeep = 0.7; // vel = vel*0.7 + instantánea*0.3
  static const double velDecayAfterMs = 80; // sin movimiento por más de esto → decae
  static const double velDecay = 0.85; // factor de decaimiento por tick
  static const double velFloor = 2; // por debajo, vel = 0 (px/s)
  static const double velMaxPxPerS = 900; // vel01 = vel / 900
  static const double ampDiagFactor = 0.55; // amp = rango / (diagonal * 0.55)
  static const double dirThresholdPx = 0.5; // |Δ| mínimo para actualizar dirección
  static const double articulationPx = 42; // una nota del niño cada 42 px

  // ---------------- Máquina de estados ----------------
  static const double latencyHoldMs = 1500; // quieto este tiempo en ACTIVO → latencia
  static const double latencyCloseMs = 20000; // latencia más larga → cierre de sesión

  // ---------------- Campo ----------------
  static const double maxDtS = 0.05; // dt máximo por tick (s)
  static const double fieldMaxWidth = 14;
  static const double widthMin = 1; // ancho objetivo = 1 + 13*amp
  static const double widthSpan = 13;
  static const double widthResponse = 4; // min(1, dt*4)
  static const double centerInitial = 12;
  static const double centerMin = 2; // centro objetivo = 2 + 20*vel01
  static const double centerSpan = 20;
  static const double centerResponse = 0.9; // min(1, dt*0.9)
  static const double shrinkLatN = 0.6; // alturas/s en latencia del niño
  static const double shrinkActive = 1.6; // alturas/s en ACTIVO/LAT_A/ESPERA sin adulto
  static const double shrinkRest = 12; // alturas/s en reposo
  static const double openThreshold = 0.5; // ancho < 0.5 → campo cerrado
  static const double rateKeep = 0.9; // EMA de la velocidad de migración del centro
  static const double marimbaMaxCenter = 8.33;
  static const double mixtaMaxCenter = 16.67;

  // ---------------- Suavizado (pedido del usuario, 28-09-2026; no está en el prototipo) ----------------
  /// Semiancho (en alturas del registro) de la zona donde el timbre se mezcla
  /// con la familia vecina en vez de cambiar de golpe. 0 = cambio brusco (prototipo).
  static const double timbreCrossfadeWidth = 1.5;

  /// Suavizado de la intensidad entre notas consecutivas del niño:
  /// ganancia = anterior*keep + nueva*(1-keep). 0 = sin suavizado (prototipo).
  static const double noteGainSmoothingKeep = 0.5;

  // ---------------- Timbre oculto ----------------
  static const double hiddenDurationMs = 6000;

  // ---------------- Articulación ----------------
  static const double noteGainBase = 0.18; // gain = (0.18 + 0.82*amp) * 0.3
  static const double noteGainSpan = 0.82;
  static const double noteGainScale = 0.3;
  static const double eventWindowMs = 1000; // ventana para eventos/s

  // ---------------- Regímenes ----------------
  static const double regimeShiftRate = 1.2; // alturas/s de migración del centro
  static const int denseMinCount = 8;
  static const int denseMinEvents = 5;
  static const int sparseMaxCount = 3;
  static const int sparseMaxEvents = 2;

  // ---------------- Audio (bus) ----------------
  static const double busGain = 0.8;
  static const double lostFadeS = 1.2;
  static const double resumeFadeS = 0.6;
}
