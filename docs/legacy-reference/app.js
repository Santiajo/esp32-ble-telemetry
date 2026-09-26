// ==========================================
// CONTROLADOR PRINCIPAL - VERSIÓN DUAL (2 DISPOSITIVOS ESP32)
// Dispositivo A = Turquesa | Dispositivo B = Naranja
// ==========================================

// 1. CLASE PARA RENDERIZAR ONDAS TIPO OSCILOSCOPIO
class WaveGraph {
    constructor(canvasId, maxMuestras = 200, colorA = "#00ffcc", colorB = "#ff5722") {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.maxMuestras = maxMuestras;
        this.colorA = colorA;
        this.colorB = colorB;

        this.datosA = new Array(maxMuestras).fill(0);
        this.datosB = new Array(maxMuestras).fill(0);

        this.ajustarResolucion();
        window.addEventListener('resize', () => this.ajustarResolucion());
    }

    ajustarResolucion() {
        this.canvas.width = this.canvas.parentElement.clientWidth - 30;
        this.width = this.canvas.width;
        this.height = this.canvas.height;
    }

    agregarMuestra(valA, valB = null) {
        this.datosA.shift();
        this.datosA.push(valA);
        if (valB !== null) {
            this.datosB.shift();
            this.datosB.push(valB);
        }
    }

    dibujar(escala = 1.0, mostrarB = true) {
        this.ctx.clearRect(0, 0, this.width, this.height);

        const centroY = this.height / 2;
        this.ctx.strokeStyle = "#1f1f1f";
        this.ctx.lineWidth = 1;
        this.ctx.beginPath();
        this.ctx.moveTo(0, centroY);
        this.ctx.lineTo(this.width, centroY);
        this.ctx.stroke();

        if (mostrarB) {
            this.trazarOnda(this.datosB, this.colorB, escala, centroY);
        }
        this.trazarOnda(this.datosA, this.colorA, escala, centroY);
    }

    trazarOnda(datos, color, escala, centroY) {
        this.ctx.strokeStyle = color;
        this.ctx.lineWidth = 2.5;
        this.ctx.lineCap = "round";
        this.ctx.lineJoin = "round";
        this.ctx.beginPath();

        const pasoX = this.width / (this.maxMuestras - 1);

        for (let i = 0; i < datos.length; i++) {
            const x = i * pasoX;
            const y = centroY - (datos[i] * escala);

            if (i === 0) {
                this.ctx.moveTo(x, y);
            } else {
                const prevX = (i - 1) * pasoX;
                const prevY = centroY - (datos[i - 1] * escala);
                const midX = (prevX + x) / 2;
                const midY = (prevY + y) / 2;
                this.ctx.quadraticCurveTo(prevX, prevY, midX, midY);
            }
        }
        this.ctx.stroke();
    }
}

// 2. CLASE DISPOSITIVO: agrupa BLE + física + estado visual de cada ESP32
const SUAVIZADO_VISUAL = 0.18; // Interpolación visual: más alto = más reactivo, más bajo = más suave

class Dispositivo {
    constructor(etiqueta, color) {
        this.etiqueta = etiqueta;   // "A" o "B"
        this.color = color;
        this.conectado = false;
        this.fisica = new PhysicsEngine();
        this.ultimoRawX = 0;
        this.ultimoRawY = 0;
        this.visualX = 0;           // Posición dibujada (persigue a la física)
        this.visualY = 0;

        this.ble = new BLEManager(
            (rawX, rawY, lineaRaw) => {
                this.ultimoRawX = rawX;
                this.ultimoRawY = rawY;
                this.fisica.procesarLectura(rawX, rawY);
                logConsola(`[${this.etiqueta}] ${lineaRaw}`);
            },
            (conectado) => {
                this.conectado = conectado;
                actualizarEstadoUI();
            },
            (mensaje) => logConsola(`[${this.etiqueta}] ${mensaje}`)
        );
    }
}

const dispA = new Dispositivo('A', '#00ffcc');  // Turquesa
const dispB = new Dispositivo('B', '#ff5722');  // Naranja
const dispositivos = [dispA, dispB];

// Nombres esperados de cada placa (deben coincidir con NOMBRE_BLE del firmware)
dispA.nombreEsperado = 'ESP32-MPU-A';
dispB.nombreEsperado = 'ESP32-MPU-B';

// 3. GRÁFICOS: cada onda compara Dispositivo A (turquesa) vs B (naranja)
const grafVelocidad   = new WaveGraph('canvas-velocidad', 180, dispA.color, dispB.color);
const grafAceleracion = new WaveGraph('canvas-aceleracion', 180, dispA.color, dispB.color);
const grafEnergia     = new WaveGraph('canvas-energia', 180, dispA.color, dispB.color);

// Elementos DOM
const chipA = document.getElementById('chip-a');
const chipB = document.getElementById('chip-b');
const btnCalibrar = document.getElementById('btn-calibrar');
const btnReset = document.getElementById('btn-reset');
const consola = document.getElementById('consola');
const canvas = document.getElementById('plano2d');
const ctx = canvas.getContext('2d');
const ESCALA_PIXELES = 4;

// ---- WAKE LOCK: evita que Android apague la pantalla y corte el BLE ----
let wakeLock = null;
async function solicitarWakeLock() {
    try {
        if ('wakeLock' in navigator) {
            wakeLock = await navigator.wakeLock.request('screen');
        }
    } catch (e) {
        console.warn("WakeLock no disponible:", e.message);
    }
}
function liberarWakeLock() {
    if (wakeLock) { wakeLock.release().catch(() => {}); wakeLock = null; }
}
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && dispositivos.some(d => d.conectado)) {
        solicitarWakeLock();
    }
});

// 4. BUCLE DE RENDERIZADO (60 FPS)
function dibujarPunto(d, centroX, centroY) {
    // Interpolación: el punto visual persigue suavemente a la posición física
    d.visualX += (d.fisica.posX - d.visualX) * SUAVIZADO_VISUAL;
    d.visualY += (d.fisica.posY - d.visualY) * SUAVIZADO_VISUAL;
    if (Math.abs(d.fisica.posX - d.visualX) < 0.05) d.visualX = d.fisica.posX;
    if (Math.abs(d.fisica.posY - d.visualY) < 0.05) d.visualY = d.fisica.posY;

    const renderX = centroX + (d.visualX * ESCALA_PIXELES);
    const renderY = centroY - (d.visualY * ESCALA_PIXELES);

    // Halo
    ctx.beginPath();
    ctx.arc(renderX, renderY, 14, 0, Math.PI * 2);
    ctx.fillStyle = d.color + "26"; // ~15% alpha
    ctx.fill();

    // Punto sólido
    ctx.beginPath();
    ctx.arc(renderX, renderY, 6, 0, Math.PI * 2);
    ctx.fillStyle = d.color;
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.stroke();

    // Etiqueta A / B junto al punto
    ctx.fillStyle = d.color;
    ctx.font = "bold 12px monospace";
    ctx.fillText(d.etiqueta, renderX + 10, renderY - 10);
}

function actualizarMetricas(d, prefijo) {
    const f = d.fisica;
    document.getElementById(`${prefijo}-acc-x`).textContent = f.accX.toFixed(2);
    document.getElementById(`${prefijo}-acc-y`).textContent = f.accY.toFixed(2);
    const velTotal = Math.sqrt(f.velX * f.velX + f.velY * f.velY);
    document.getElementById(`${prefijo}-vel-total`).textContent = velTotal.toFixed(2);
    document.getElementById(`${prefijo}-pos-x`).textContent = f.posX.toFixed(1);
    document.getElementById(`${prefijo}-pos-y`).textContent = f.posY.toFixed(1);
    return velTotal;
}

function bucleRenderizado() {
    // ---- A. PLANO CARTESIANO 2D ----
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const centroX = canvas.width / 2;
    const centroY = canvas.height / 2;

    ctx.strokeStyle = '#181818';
    ctx.lineWidth = 1;
    for (let i = 0; i <= canvas.width; i += 24) {
        ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, canvas.height); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(canvas.width, i); ctx.stroke();
    }

    ctx.strokeStyle = '#00ffcc33';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(0, centroY); ctx.lineTo(canvas.width, centroY); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(centroX, 0); ctx.lineTo(centroX, canvas.height); ctx.stroke();

    // Dibujar solo los dispositivos conectados
    for (const d of dispositivos) {
        if (d.conectado) dibujarPunto(d, centroX, centroY);
    }

    // ---- B. MÉTRICAS Y GRÁFICOS (ambos dispositivos) ----
    const velTotalA = actualizarMetricas(dispA, 'a');
    const velTotalB = actualizarMetricas(dispB, 'b');

    // Velocidad total: A vs B
    grafVelocidad.agregarMuestra(velTotalA, velTotalB);
    grafVelocidad.dibujar(15.0, true);

    // Magnitud de aceleración: A vs B
    const accMagA = Math.sqrt(dispA.fisica.accX ** 2 + dispA.fisica.accY ** 2);
    const accMagB = Math.sqrt(dispB.fisica.accX ** 2 + dispB.fisica.accY ** 2);
    grafAceleracion.agregarMuestra(accMagA, accMagB);
    grafAceleracion.dibujar(2.5, true);

    // Energía cinética: A vs B
    grafEnergia.agregarMuestra(velTotalA * velTotalA * 2.0, velTotalB * velTotalB * 2.0);
    grafEnergia.dibujar(8.0, true);

    requestAnimationFrame(bucleRenderizado);
}

// 5. AUTO-CONEXIÓN E INDICADORES DE ESTADO
// Estados posibles de cada chip:
//   sin-vincular → primera vez: requiere un toque (exigencia de seguridad de Chrome)
//   buscando     → intentando conectar / reconectar en segundo plano
//   conectado    → recibiendo telemetría
function estadoDe(d) {
    if (d.conectado) return 'conectado';
    if (d.ble.buscando) return 'buscando';
    if (d.ble.dispositivo) return 'buscando'; // vinculado pero aún sin enlace
    return 'sin-vincular';
}

const TEXTOS_ESTADO = {
    'sin-vincular': 'Toca para vincular',
    'buscando': 'Buscando...',
    'conectado': 'Conectado'
};

function pintarChip(chip, d) {
    const estado = estadoDe(d);
    chip.className = `chip-estado st-${estado}`;
    chip.innerHTML = `<span class="chip-dot" style="--c:${d.color}"></span>ESP ${d.etiqueta} · ${TEXTOS_ESTADO[estado]}`;
    chip.title = estado === 'conectado'
        ? `Recibiendo datos de ${d.nombreEsperado}. Toca para desconectar.`
        : `Esperado: ${d.nombreEsperado}`;
}

function actualizarEstadoUI() {
    pintarChip(chipA, dispA);
    pintarChip(chipB, dispB);

    const alguno = dispositivos.some(d => d.conectado);
    btnCalibrar.disabled = !alguno;
    btnReset.disabled = !alguno;

    if (alguno) {
        solicitarWakeLock();
    } else {
        liberarWakeLock();
    }
}

// AUTO-CONEXIÓN AL CARGAR: recupera los dispositivos ya autorizados en visitas
// anteriores (getDevices) y se conecta solo, sin tocar nada.
// El primer emparejamiento de cada placa sí requiere un toque en el chip.
async function initAutoConexion() {
    // MODO APP NATIVA (APK con Capacitor): el BLE nativo escanea y conecta
    // solo, sin selector ni toques. window.BLE_NATIVO lo define native-bundle.js
    if (window.BLE_NATIVO) {
        logConsola("Modo APP: buscando placas ESP32 automáticamente...");
        for (const d of dispositivos) d.ble.conectarPersistente();
        actualizarEstadoUI();
        return;
    }
    if (!navigator.bluetooth) {
        logConsola("Este navegador no soporta Web Bluetooth (usa Chrome en Android o PC).");
        return;
    }
    if (!navigator.bluetooth.getDevices) {
        logConsola("Auto-conexión no disponible en este Chrome. Toca cada indicador para conectar.");
        return;
    }

    let conocidos = [];
    try {
        conocidos = await navigator.bluetooth.getDevices();
    } catch (e) {
        logConsola("No se pudo recuperar dispositivos vinculados: " + e.message);
        return;
    }

    // 1ª pasada: asignar por nombre exacto esperado (ESP32-MPU-A / ESP32-MPU-B)
    const usados = new Set();
    for (const d of dispositivos) {
        const dev = conocidos.find(x => x.name && x.name.startsWith(d.nombreEsperado) && !usados.has(x.id));
        if (dev) {
            usados.add(dev.id);
            d.ble.adoptarDispositivo(dev);
        }
    }
    // 2ª pasada: dispositivos ESP32* restantes a espacios libres (por si no renombraron el firmware)
    for (const d of dispositivos) {
        if (d.ble.dispositivo) continue;
        const dev = conocidos.find(x => x.name && x.name.startsWith('ESP32') && !usados.has(x.id));
        if (dev) {
            usados.add(dev.id);
            d.ble.adoptarDispositivo(dev);
        }
    }

    for (const d of dispositivos) {
        if (d.ble.dispositivo) {
            logConsola(`[${d.etiqueta}] Dispositivo recordado (${d.ble.dispositivo.name}). Conectando automáticamente...`);
            d.ble.conectarPersistente();
        } else {
            logConsola(`[${d.etiqueta}] Sin vincular. Toca el indicador "ESP ${d.etiqueta}" para emparejar la primera vez.`);
        }
    }
    actualizarEstadoUI();
}

async function manejarClickChip(d) {
    if (d.conectado) {
        d.ble.desconectar();       // Toque estando conectado = desconectar
    } else if (d.ble.dispositivo) {
        d.ble.conectarPersistente(); // Forzar reintento inmediato
    } else {
        await d.ble.vincular();      // Primer emparejamiento (gesto del usuario)
    }
    actualizarEstadoUI();
}

chipA.addEventListener('click', () => manejarClickChip(dispA));
chipB.addEventListener('click', () => manejarClickChip(dispB));

// Refresco periódico de los chips (estados 'buscando' cambian sin evento)
setInterval(actualizarEstadoUI, 1000);

function logConsola(texto) {
    const div = document.createElement('div');
    div.className = 'consola-linea';
    div.textContent = `> ${texto}`;
    consola.appendChild(div);
    consola.scrollTop = consola.scrollHeight;
    if (consola.children.length > 25) consola.removeChild(consola.firstChild);
}

btnCalibrar.addEventListener('click', () => {
    for (const d of dispositivos) {
        if (d.conectado) {
            d.fisica.calibrar(d.ultimoRawX, d.ultimoRawY);
            logConsola(`[${d.etiqueta}] Centro recalibrado y tara aplicada.`);
        }
    }
});

btnReset.addEventListener('click', () => {
    for (const d of dispositivos) {
        d.fisica.resetPosicion();
        d.visualX = 0;
        d.visualY = 0;
    }
    logConsola("Posiciones y velocidades reiniciadas a (0,0).");
});

// Iniciar
actualizarEstadoUI();
initAutoConexion();
requestAnimationFrame(bucleRenderizado);
