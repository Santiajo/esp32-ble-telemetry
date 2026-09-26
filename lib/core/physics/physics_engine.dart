import 'dart:math' as math;

/// Motor cinemático y de filtrado para telemetría MPU-6050.
///
/// Port directo y fiel de `reference/legacy-web/physics.js`:
/// - Escala de acelerómetro: $\pm 2g$ ($16384\text{ LSB} = 1g = 9.81\text{ m/s}^2$)
/// - Filtro anti-picos adaptativo contra fallas I2C y saltos bruscos
/// - Filtro pasa-altos para absorber la inclinación estática / gravedad
/// - Filtro EMA (Media Móvil Exponencial) para atenuar ruido eléctrico
/// - Integración continua ($\Delta t$) con zona muerta, fricción normalizada en el tiempo,
///   detección de reposo (ZUPT) con resorte al centro y límites de área en $\pm 58\text{ cm}$.
class PhysicsEngine {
  static const double rawToMs2 = 9.81 / 16384.0;

  // --- Parámetros de sensibilidad y filtrado ---
  static const double alpha = 0.35; // EMA: Suavidad del filtro para ruido eléctrico
  static const double gravedadAlpha = 0.02; // Filtro Pasa-Altos (punto dinámico de gravedad)
  static const double deadzone = 0.08; // Zona muerta (m/s²) para ignorar temblores en reposo
  static const double gananciaAcc = 0.85; // Agilidad de respuesta
  static const double maxVelocidad = 3.5; // Límite de velocidad terminal (m/s)

  static const double maxAccel = 35.0; // Rechazo de fallas I2C
  static const double maxDeltaAcc = 15.0; // Umbral de pico brusco
  static const int maxRechazos = 3; // N rechazos consecutivos antes de adoptar nivel

  // --- Parámetros antideslizamiento y retorno ---
  static const double friccion = 0.95; // Fricción base normalizada a 60 Hz
  static const double fuerzaRetorno = 0.03; // Resorte hacia el centro normalizado a 60 Hz
  static const int timeoutZupt = 300; // ms sin movimiento para entrar en ZUPT
  static const double frenadoZupt = 0.55; // Frenado suave exponencial en reposo

  // --- Límites del plano cartesiano (cm) ---
  static const double limitePosicion = 58.0;

  // --- Estado dinámico ---
  double accX = 0.0;
  double accY = 0.0;
  double velX = 0.0;
  double velY = 0.0;
  double posX = 0.0;
  double posY = 0.0;

  // --- Calibración y memoria ---
  double offsetX = 0.0;
  double offsetY = 0.0;
  double gravedadX = 0.0;
  double gravedadY = 0.0;
  double ultimaAccX = 0.0;
  double ultimaAccY = 0.0;
  int rechazosConsecutivos = 0;

  final Stopwatch _stopwatch = Stopwatch()..start();
  double _ultimoTiempoIntegracionMs = 0.0;
  double _ultimoTiempoMovimientoMs = 0.0;

  PhysicsEngine() {
    final ahoraMs = _stopwatch.elapsedMicroseconds / 1000.0;
    _ultimoTiempoIntegracionMs = ahoraMs;
    _ultimoTiempoMovimientoMs = ahoraMs;
  }

  /// Calibra el centro estático (Tara manual) con las lecturas actuales en reposo.
  void calibrar(int rawX, int rawY) {
    offsetX = rawX * rawToMs2;
    offsetY = rawY * rawToMs2;
    gravedadX = 0.0;
    gravedadY = 0.0;
    ultimaAccX = 0.0;
    ultimaAccY = 0.0;
    rechazosConsecutivos = 0;
    resetPosicion();
  }

  /// Restablece velocidad y posición a (0, 0).
  void resetPosicion() {
    velX = 0.0;
    velY = 0.0;
    posX = 0.0;
    posY = 0.0;
  }

  /// Procesa una lectura cruda entrante del sensor MPU6050.
  void procesarLectura(int rawX, int rawY) {
    // Convertir a m/s² y restar calibración estática (Tara)
    final double axTotal = (rawX * rawToMs2) - offsetX;
    final double ayTotal = (rawY * rawToMs2) - offsetY;

    // Filtro de valores absurdos (fallo de lectura I2C)
    if (axTotal.abs() > maxAccel || ayTotal.abs() > maxAccel) {
      return;
    }

    // Filtro anti-picos adaptativo
    final bool esPico = (axTotal - ultimaAccX).abs() > maxDeltaAcc ||
        (ayTotal - ultimaAccY).abs() > maxDeltaAcc;

    if (esPico) {
      rechazosConsecutivos++;
      if (rechazosConsecutivos < maxRechazos) {
        return; // Pico aislado: descartar
      }
      // Cambio sostenido tras N rechazos: aceptar nuevo nivel
    }
    rechazosConsecutivos = 0;

    ultimaAccX = axTotal;
    ultimaAccY = ayTotal;

    // Filtro pasa-altos (punto dinámico de gravedad)
    gravedadX = ((1.0 - gravedadAlpha) * gravedadX) + (gravedadAlpha * axTotal);
    gravedadY = ((1.0 - gravedadAlpha) * gravedadY) + (gravedadAlpha * ayTotal);

    // Restar componente de inclinación acumulada (gravedad estática)
    final double axLimpia = axTotal - gravedadX;
    final double ayLimpia = ayTotal - gravedadY;

    // Filtro EMA sobre la aceleración lineal limpia
    accX = (alpha * axLimpia) + ((1.0 - alpha) * accX);
    accY = (alpha * ayLimpia) + ((1.0 - alpha) * accY);

    integrarFisica();
  }

  /// Ejecuta la integración numérica cinemática en función de dt.
  void integrarFisica() {
    final double ahoraMs = _stopwatch.elapsedMicroseconds / 1000.0;
    final double dt = (ahoraMs - _ultimoTiempoIntegracionMs) / 1000.0;
    _ultimoTiempoIntegracionMs = ahoraMs;

    // Ignorar saltos anormales (ej. app en segundo plano o retraso BLE grande)
    if (dt > 0.5 || dt <= 0.0) {
      return;
    }

    double ax = accX;
    double ay = accY;

    // Zona muerta
    final bool enReposoX = ax.abs() < deadzone;
    final bool enReposoY = ay.abs() < deadzone;

    if (enReposoX) ax = 0.0;
    if (enReposoY) ay = 0.0;

    if (!enReposoX || !enReposoY) {
      _ultimoTiempoMovimientoMs = ahoraMs;
    }

    final double tiempoSinMoverse = ahoraMs - _ultimoTiempoMovimientoMs;

    // Integración de velocidad usando aceleración filtrada
    velX += (ax * gananciaAcc) * dt;
    velY += (ay * gananciaAcc) * dt;

    // Límite de velocidad terminal
    velX = velX.clamp(-maxVelocidad, maxVelocidad);
    velY = velY.clamp(-maxVelocidad, maxVelocidad);

    // Fricción normalizada en el tiempo a 60 Hz
    final double factorFriccion = math.pow(friccion, dt * 60.0).toDouble();
    velX *= factorFriccion;
    velY *= factorFriccion;

    // Algoritmo ZUPT (Zero Velocity Update) + Resorte para retorno al centro
    if (tiempoSinMoverse > timeoutZupt) {
      final double factorFrenado = math.pow(frenadoZupt, dt * 60.0).toDouble();
      velX *= factorFrenado;
      velY *= factorFrenado;

      if (velX.abs() < 0.01) velX = 0.0;
      if (velY.abs() < 0.01) velY = 0.0;

      final double factorRetorno =
          1.0 - math.pow(1.0 - fuerzaRetorno, dt * 60.0).toDouble();
      posX -= posX * factorRetorno;
      posY -= posY * factorRetorno;

      if (posX.abs() < 0.1) posX = 0.0;
      if (posY.abs() < 0.1) posY = 0.0;
    }

    // Integración de posición en cm (1 m = 100 cm)
    if (velX != 0.0 || velY != 0.0) {
      posX += (velX * dt) * 100.0;
      posY += (velY * dt) * 100.0;
    }

    // Límites del plano cartesiano:
    // Al tocar una pared solo se anula la velocidad en el sentido del impacto
    if (posX >= limitePosicion) {
      posX = limitePosicion;
      if (velX > 0.0) velX = 0.0;
    } else if (posX <= -limitePosicion) {
      posX = -limitePosicion;
      if (velX < 0.0) velX = 0.0;
    }

    if (posY >= limitePosicion) {
      posY = limitePosicion;
      if (velY > 0.0) velY = 0.0;
    } else if (posY <= -limitePosicion) {
      posY = -limitePosicion;
      if (velY < 0.0) velY = 0.0;
    }
  }
}
