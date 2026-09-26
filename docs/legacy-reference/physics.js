// ==========================================
// MÓDULO DE FÍSICA: TARA DINÁMICA Y DESPEGUE DE BORDES
// Versión corregida: sin deadlock del filtro anti-picos,
// fricción/resorte independientes de la frecuencia de muestreo,
// ZUPT tolerante al jitter de BLE.
// ==========================================

class PhysicsEngine {
    constructor() {
        this.RAW_TO_MS2 = 9.81 / 16384.0;

        // --- PARÁMETROS DE SENSIBILIDAD Y FILTRADO ---
        this.ALPHA = 0.35;          // EMA: Suavidad del filtro para ruido eléctrico
        this.GRAVEDAD_ALPHA = 0.02; // Filtro Pasa-Altos (Punto de referencia dinámico)
        this.DEADZONE = 0.08;       // Zona muerta para ignorar temblores en reposo (bajada: responde a empujes suaves)
        this.GANANCIA_ACC = 0.85;   // Agilidad (subida de 0.5: el punto ya no se siente "pesado")
        this.MAX_VELOCIDAD = 3.5;   // Límite de velocidad terminal (m/s)

        this.MAX_ACCEL = 35.0;
        this.MAX_DELTA_ACC = 15.0;
        this.MAX_RECHAZOS = 3;      // Tras N rechazos seguidos, aceptar el nuevo nivel (evita bloqueo permanente)

        // --- PARÁMETROS ANTIDESLIZAMIENTO Y RETORNO ---
        this.FRICCION = 0.95;       // Fricción por "frame" de referencia (60 Hz)
        this.FUERZA_RETORNO = 0.03; // Resorte hacia el centro por frame de referencia
        this.TIMEOUT_ZUPT = 300;    // ms sin movimiento para frenar (300 tolera el jitter de BLE)
        this.FRENADO_ZUPT = 0.55;   // Frenado suave en reposo (antes: vel=0 de golpe → paradas bruscas)

        // --- LÍMITES DEL CUADRADO (CANVAS) ---
        this.LIMITE_POSICION = 58.0;

        // Estado del sistema
        this.accX = 0; this.accY = 0;
        this.velX = 0; this.velY = 0;
        this.posX = 0; this.posY = 0;

        // Memoria de Calibración y Gravedad Dinámica
        this.offsetX = 0; this.offsetY = 0;
        this.gravedadX = 0; this.gravedadY = 0;
        this.ultimaAccX = 0; this.ultimaAccY = 0;
        this.rechazosConsecutivos = 0;
        this.ultimoTiempoIntegracion = performance.now();
        this.ultimoTiempoMovimiento = performance.now();
    }

    calibrar(rawX, rawY) {
        this.offsetX = rawX * this.RAW_TO_MS2;
        this.offsetY = rawY * this.RAW_TO_MS2;
        this.gravedadX = 0;
        this.gravedadY = 0;
        this.ultimaAccX = 0;
        this.ultimaAccY = 0;
        this.rechazosConsecutivos = 0;
        this.resetPosicion();
        console.log("Centro calibrado. Punto de referencia dinámico reiniciado.");
    }

    resetPosicion() {
        this.velX = 0; this.velY = 0;
        this.posX = 0; this.posY = 0;
    }

    procesarLectura(rawX, rawY) {
        // Convertir a m/s² y restar calibración estática (Tara manual del botón)
        let ax_total = (rawX * this.RAW_TO_MS2) - this.offsetX;
        let ay_total = (rawY * this.RAW_TO_MS2) - this.offsetY;

        // Filtro de valores absurdos (fallo de lectura I2C)
        if (Math.abs(ax_total) > this.MAX_ACCEL || Math.abs(ay_total) > this.MAX_ACCEL) return;

        // FILTRO ANTI-PICOS CORREGIDO:
        // El código anterior rechazaba lecturas sin actualizar la referencia,
        // por lo que un cambio real de orientación (>15 m/s²) bloqueaba el
        // sistema PARA SIEMPRE: todas las lecturas posteriores se descartaban
        // y el punto quedaba "muerto" hasta recargar la página.
        // Ahora, si varias lecturas consecutivas son rechazadas, asumimos que
        // el cambio es real (no un pico eléctrico) y adoptamos el nuevo nivel.
        const esPico = Math.abs(ax_total - this.ultimaAccX) > this.MAX_DELTA_ACC ||
                       Math.abs(ay_total - this.ultimaAccY) > this.MAX_DELTA_ACC;

        if (esPico) {
            this.rechazosConsecutivos++;
            if (this.rechazosConsecutivos < this.MAX_RECHAZOS) {
                return; // Pico aislado: descartar
            }
            // Cambio sostenido: aceptar la nueva referencia y continuar
        }
        this.rechazosConsecutivos = 0;

        this.ultimaAccX = ax_total;
        this.ultimaAccY = ay_total;

        // FILTRO PASA-ALTOS (Punto de Referencia Dinámico)
        // Estima la inclinación continua de la muñeca y la absorbe lentamente
        this.gravedadX = (1 - this.GRAVEDAD_ALPHA) * this.gravedadX + (this.GRAVEDAD_ALPHA * ax_total);
        this.gravedadY = (1 - this.GRAVEDAD_ALPHA) * this.gravedadY + (this.GRAVEDAD_ALPHA * ay_total);

        // Restar inclinación acumulada para quedar SOLO con empuje lineal puro
        let ax_limpia = ax_total - this.gravedadX;
        let ay_limpia = ay_total - this.gravedadY;

        // Filtro EMA sobre la aceleración limpia
        this.accX = (this.ALPHA * ax_limpia) + ((1 - this.ALPHA) * this.accX);
        this.accY = (this.ALPHA * ay_limpia) + ((1 - this.ALPHA) * this.accY);

        this.integrarFisica();
    }

    integrarFisica() {
        const ahora = performance.now();
        const dt = (ahora - this.ultimoTiempoIntegracion) / 1000.0;
        this.ultimoTiempoIntegracion = ahora;

        // Ignorar huecos grandes (pestaña en segundo plano, reconexión BLE)
        if (dt > 0.5 || dt <= 0) return;

        let ax = this.accX;
        let ay = this.accY;

        // Evaluar zona muerta
        let enReposoX = Math.abs(ax) < this.DEADZONE;
        let enReposoY = Math.abs(ay) < this.DEADZONE;

        if (enReposoX) ax = 0;
        if (enReposoY) ay = 0;

        if (!enReposoX || !enReposoY) {
            this.ultimoTiempoMovimiento = ahora;
        }

        const tiempoSinMoverse = ahora - this.ultimoTiempoMovimiento;

        // Integración de velocidad usando aceleración filtrada
        this.velX += (ax * this.GANANCIA_ACC) * dt;
        this.velY += (ay * this.GANANCIA_ACC) * dt;

        // Límite de velocidad terminal
        this.velX = Math.max(Math.min(this.velX, this.MAX_VELOCIDAD), -this.MAX_VELOCIDAD);
        this.velY = Math.max(Math.min(this.velY, this.MAX_VELOCIDAD), -this.MAX_VELOCIDAD);

        // FRICCIÓN CORREGIDA: antes se aplicaba 0.95 por PAQUETE recibido,
        // así que el frenado dependía de la frecuencia de envío del ESP32
        // (a 100 Hz frenaba el doble de rápido que a 50 Hz).
        // Ahora se normaliza al tiempo real transcurrido (referencia 60 Hz).
        const factorFriccion = Math.pow(this.FRICCION, dt * 60);
        this.velX *= factorFriccion;
        this.velY *= factorFriccion;

        // Algoritmo ZUPT (Reposo absoluto) + Efecto resorte para volver al centro
        // FRENADO SUAVE: en vez de anular la velocidad de golpe (parada brusca),
        // se aplica un frenado exponencial fuerte; se ve como una desaceleración natural.
        if (tiempoSinMoverse > this.TIMEOUT_ZUPT) {
            const factorFrenado = Math.pow(this.FRENADO_ZUPT, dt * 60);
            this.velX *= factorFrenado;
            this.velY *= factorFrenado;
            if (Math.abs(this.velX) < 0.01) this.velX = 0;
            if (Math.abs(this.velY) < 0.01) this.velY = 0;

            // Resorte hacia el centro, también normalizado en el tiempo
            const factorRetorno = 1 - Math.pow(1 - this.FUERZA_RETORNO, dt * 60);
            this.posX -= this.posX * factorRetorno;
            this.posY -= this.posY * factorRetorno;

            if (Math.abs(this.posX) < 0.1) this.posX = 0;
            if (Math.abs(this.posY) < 0.1) this.posY = 0;
        }

        // Integración de posición usando velocidad actual
        if (this.velX !== 0 || this.velY !== 0) {
            this.posX += (this.velX * dt) * 100;
            this.posY += (this.velY * dt) * 100;
        }

        // Límites del cuadrado:
        // Si el punto toca una pared, solo se anula la velocidad que lo empuja
        // contra ella, permitiendo despegarse al instante en sentido contrario.
        if (this.posX >= this.LIMITE_POSICION) {
            this.posX = this.LIMITE_POSICION;
            if (this.velX > 0) this.velX = 0;
        } else if (this.posX <= -this.LIMITE_POSICION) {
            this.posX = -this.LIMITE_POSICION;
            if (this.velX < 0) this.velX = 0;
        }

        if (this.posY >= this.LIMITE_POSICION) {
            this.posY = this.LIMITE_POSICION;
            if (this.velY > 0) this.velY = 0;
        } else if (this.posY <= -this.LIMITE_POSICION) {
            this.posY = -this.LIMITE_POSICION;
            if (this.velY < 0) this.velY = 0;
        }
    }
}
