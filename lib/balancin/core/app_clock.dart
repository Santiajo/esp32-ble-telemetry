/// Reloj monotónico único de la app (ms).
///
/// El motor, los lectores de gesto y la llegada de muestras BLE deben usar la
/// MISMA base de tiempo: un stick conectado en el onboarding sigue alimentando
/// su lector cuando empieza la sesión, y `lastMove` debe ser comparable con el
/// `now` del motor.
abstract final class AppClock {
  static final Stopwatch _sw = Stopwatch()..start();

  /// Milisegundos desde que arrancó la app.
  static double nowMs() => _sw.elapsedMicroseconds / 1000.0;
}
