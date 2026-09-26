/// Interfaz común de lectura de gesto (plan §4.2).
///
/// El motor no sabe si el gesto viene del dedo, de un simulador o de la IMU.
/// Cada fuente implementa esta interfaz con las mismas semánticas.
abstract interface class GestureReader {
  /// Se movió en los últimos 200 ms.
  bool get moving;

  /// Instante (ms) del último movimiento. Muy negativo si nunca se movió.
  double get lastMove;

  /// Amplitud del gesto en la ventana de 0,8 s (0–1).
  double get amp;

  /// Velocidad normalizada (0–1).
  double get vel01;

  /// Dirección del último movimiento en cada eje: −1, 0 o +1.
  int get dx;
  int get dy;

  /// Sacudida: ≥ 4 inversiones de dirección en 0,6 s.
  bool get shake;

  /// Recalcula las características derivadas para el instante [now] (ms).
  /// El motor la llama una vez por tick.
  void update(double now);

  /// Devuelve cuántas "unidades de recorrido" (articulaciones) se acumularon
  /// y las descuenta. Cada una equivale a una nota del niño.
  int consumeArticulations();

  /// Descarta el recorrido acumulado (sin campo no se articula nada).
  void discardArticulations();

  /// Vuelve al estado inicial (sin historia, quieto).
  void reset();
}
