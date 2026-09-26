// ==========================================
// MÓDULO DE COMUNICACIÓN BLUETOOTH LE
// Versión con auto-conexión persistente:
// - vincular(): primer emparejamiento (requiere toque del usuario, exigencia de Chrome)
// - conectarPersistente(): reintenta en bucle hasta conectar (para auto-conexión)
// - Reconexión automática indefinida tras caídas
// ==========================================

class BLEManager {
    constructor(onDataCallback, onStatusChangeCallback, onLogCallback, namePrefix = 'ESP32') {
        this.SERVICIO_UUID = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
        this.CARACTERISTICA_TX = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

        this.MAX_REINTENTOS_GATT = 2;   // Intentos rápidos por ciclo (el 1ro suele fallar)
        this.MAX_BUFFER = 2048;

        this.namePrefix = namePrefix;
        this.dispositivo = null;
        this.caracteristica = null;
        this.buffer = "";
        this.decodificador = new TextDecoder('utf-8');

        this.buscando = false;          // Hay un bucle de conexión en curso
        this.desconexionManual = false;

        this.onData = onDataCallback;
        this.onStatusChange = onStatusChangeCallback;
        this.onLog = onLogCallback || ((msg) => console.log(msg));
    }

    soportado() {
        return !!(navigator.bluetooth);
    }

    estaConectado() {
        return !!(this.dispositivo && this.dispositivo.gatt.connected);
    }

    // Adopta un dispositivo ya autorizado (obtenido de getDevices() o requestDevice())
    adoptarDispositivo(device) {
        this.dispositivo = device;
        device.addEventListener('gattserverdisconnected', () => this.manejarDesconexion());
    }

    // PRIMER EMPAREJAMIENTO: abre el selector de Chrome. Solo puede llamarse
    // desde un gesto del usuario (click/tap) — restricción de seguridad del navegador.
    async vincular() {
        if (!this.soportado()) {
            this.onLog("ERROR: Este navegador no soporta Web Bluetooth. Usa Chrome en Android o PC.");
            return false;
        }
        try {
            const device = await navigator.bluetooth.requestDevice({
                filters: [{ namePrefix: 'ESP32' }],
                optionalServices: [this.SERVICIO_UUID]
            });
            this.adoptarDispositivo(device);
            this.onLog(`Vinculado: ${device.name || '(sin nombre)'}`);
            return await this.conectarPersistente();
        } catch (error) {
            if (error.name === 'NotFoundError') {
                this.onLog("Selección cancelada.");
            } else {
                this.onLog(`Error BLE: ${error.message}`);
            }
            return false;
        }
    }

    // BUCLE DE CONEXIÓN PERSISTENTE: reintenta hasta conectar o hasta
    // que el usuario desconecte manualmente. Espera progresiva (máx 10 s).
    async conectarPersistente() {
        if (this.buscando || !this.dispositivo) return false;
        this.buscando = true;
        this.desconexionManual = false;

        let espera = 2000;
        let primerCiclo = true;

        while (!this.desconexionManual) {
            const ok = await this.conectarGATT();
            if (ok) {
                this.buscando = false;
                return true;
            }
            if (primerCiclo) {
                this.onLog(`No responde aún. Se seguirá buscando en segundo plano...`);
                primerCiclo = false;
            }
            await new Promise(r => setTimeout(r, espera));
            espera = Math.min(espera * 1.5, 10000);
        }
        this.buscando = false;
        return false;
    }

    async conectarGATT() {
        for (let intento = 1; intento <= this.MAX_REINTENTOS_GATT; intento++) {
            if (this.desconexionManual) return false;
            try {
                const servidor = await this.dispositivo.gatt.connect();
                const servicio = await servidor.getPrimaryService(this.SERVICIO_UUID);
                this.caracteristica = await servicio.getCharacteristic(this.CARACTERISTICA_TX);

                await this.caracteristica.startNotifications();
                this.caracteristica.addEventListener('characteristicvaluechanged', (e) => this.procesarStream(e));

                this.buffer = "";
                this.onStatusChange(true);
                return true;

            } catch (error) {
                try { this.dispositivo.gatt.disconnect(); } catch (_) {}
                if (intento < this.MAX_REINTENTOS_GATT) {
                    await new Promise(r => setTimeout(r, 600));
                }
            }
        }
        return false;
    }

    manejarDesconexion() {
        this.onStatusChange(false);
        if (this.desconexionManual) return;
        this.onLog("Conexión perdida. Reconectando automáticamente...");
        this.conectarPersistente().then(ok => {
            if (ok) this.onLog("Reconexión exitosa.");
        });
    }

    desconectar() {
        this.desconexionManual = true;
        if (this.estaConectado()) {
            this.dispositivo.gatt.disconnect();
        }
    }

    procesarStream(event) {
        this.buffer += this.decodificador.decode(event.target.value, { stream: true });

        if (this.buffer.length > this.MAX_BUFFER) {
            this.buffer = this.buffer.slice(-256);
        }

        let indiceSalto;
        while ((indiceSalto = this.buffer.indexOf('\n')) !== -1) {
            const linea = this.buffer.substring(0, indiceSalto).trim();
            this.buffer = this.buffer.substring(indiceSalto + 1);

            if (linea.length === 0) continue;

            const partes = linea.split(',');
            if (partes.length >= 2) {
                const rawX = parseInt(partes[0], 10);
                const rawY = parseInt(partes[1], 10);
                if (!isNaN(rawX) && !isNaN(rawY)) {
                    this.onData(rawX, rawY, linea);
                }
            }
        }
    }
}
