# Balancín · Prototipo funcional 0.9.0

Instrumento sonoro de balanceo compartido para díadas adulto–niño.
Implementación en Android del prototipo de simulación y de la *Especificación funcional v0.1* (Joaquín Muñoz Quiroz, Escuela de Diseño UDP).

---

## Contenido del paquete

| Archivo | Qué es |
|---|---|
| `balancin-0.9.0.apk` | La app para Android, lista para instalar. |
| `firmware/main.py` | Programa de los sticks (MicroPython, ESP32 + MPU6050). El mismo archivo sirve para ambos sticks. |
| `docs/GUIA_SONIDOS.md` | Qué gesto produce qué sonido, con 14 recetas para reproducir cada textura. |
| `docs/STICK_A.md` | Cómo armar y vincular el stick del adulto. |
| `docs/PLAN_BALANCIN.md` | Plan técnico completo y registro de decisiones. |
| `LEEME.md` | Este archivo. |

La guía de pruebas para usuarios no técnicos es una página web que se comparte por enlace aparte.

---

## 1. Instalar la app

1. Copia `balancin-0.9.0.apk` al teléfono Android (por Drive, WhatsApp o cable) y ábrelo.
2. Si Android lo pide, permite «Instalar apps desconocidas». Si aparece «Play Protect no reconoce esta app», elige «Más detalles» → «Instalar de todas formas». Es normal en una app que no está en la tienda.
3. Al abrir Balancín, acepta los permisos de Bluetooth.

## 2. Preparar los sticks

Cada stick es una ESP32 DevKit V1 con un MPU6050 (SDA → 21, SCL → 22, VCC → 3V3, GND → GND).

1. Instala [Thonny](https://thonny.org) y conecta la ESP32 por USB. En Herramientas → Opciones → Intérprete elige «MicroPython (ESP32)». Si la placa no tiene MicroPython, instálalo desde ese mismo menú.
2. Abre `firmware/main.py` y ajusta la línea `STICK_ROLE`:
   - `'A'` para el stick **grande (adulto)**, que se anunciará como `ESP32-BAL-A`;
   - `'B'` para el stick **pequeño (niño)**, que se anunciará como `ESP32-BAL-B`.
3. Guárdalo en la placa con Archivo → Guardar como → Dispositivo MicroPython, con el nombre `main.py`.
4. Reinicia con Ctrl+D. La luz azul parpadea mientras espera al teléfono y queda fija al conectarse.

## 3. Primer uso

1. Inicio → **«Comenzar»**. Un recorrido de 5 pasos pide los permisos y vincula los sticks: se mantiene pulsado 3 segundos el botón de cada stick.
2. **«Solo luz»** es la experiencia de la díada: el teléfono se inserta en el eje, la pantalla queda negra con una luz que sigue al sonido y, al terminar, aparece un «recuerdo» que se puede guardar como imagen.
3. **«Tablero»** muestra en vivo el campo, el estado del sistema y las métricas. Sirve para observar y validar. Dentro de una partida se alterna manteniendo 2 segundos la esquina superior izquierda; la esquina superior derecha termina la partida.
4. Sin sticks también se puede probar: en el «Tablero de validación» cada mitad de la pantalla funciona como un stick (con el dedo o en modo «Automático»).

## 4. Qué implementa

| Especificación | Estado |
|---|---|
| A abre el campo, B articula dentro de él; ninguno suena solo (§3) | ✅ |
| Máquina de estados: reposo, espera, silencio, juego activo, latencias (§4) | ✅ |
| Transiciones al silencio siempre graduales; reanudación sin corte | ✅ |
| Escala pentatónica; timbres marimba, mixta y glockenspiel según el registro | ✅ |
| Timbres ocultos por coincidencia de sacudidas (§3.4) | ✅ |
| Cinco regímenes de relación, clasificados sin puntaje (§5) | ✅ |
| Roles fijados al stick, intercambio sin configuración (§7) | ✅ |
| Sin interfaz durante el juego; luz que sigue a la amplitud (§9) | ✅ |
| Telemetría anónima por sesión, con ID aleatorio y exportación manual (§8, §10) | ✅ |
| Pérdida y reconexión de un stick sin perder la sesión | ✅ |
| Latencia gesto → sonido | Sin retraso perceptible en las pruebas (buffer de audio de ~12 ms; BLE a 100 Hz) |

**Telemetría y ética.** No se registra nada fuera de una **sesión de estudio**, un interruptor del inicio que viene **apagado**. Cada sesión se guarda en el teléfono con un ID aleatorio, sin audio, imagen ni datos de personas o dispositivos, y nunca se envía a la red. El investigador la exporta desde «Sesiones guardadas».

## 5. Decisiones para validar con el autor

1. **El recuerdo sugiere el timbre oculto.** Cuando no hubo coincidencias, una tarjeta dice «Sacudir los dos sticks a la vez abre un sonido distinto», como en el prototipo. La especificación (§3.4) pide que no haya pistas. Existe una alternativa sin pista lista para activar.
2. **La luz se vuelve amarilla con el timbre oculto**, como en el prototipo. El criterio 10 dice que la luz no debe codificar estados.
3. **Sonido más suave que el prototipo.** Tiene un ataque de 12 ms sin «clic», agudos redondeados y un cambio de timbre gradual entre familias. La voz original del prototipo sigue disponible.
4. **Valores del prototipo que difieren de la propuesta de la especificación:** 25 alturas en 5 octavas (en lugar de 15), 1,5 s de quietud antes de la latencia (en lugar de 0,5–1 s) y cierre de la sesión tras 20 s de latencia.

## 6. Pendiente

- **Relación de fase entre A y B en la telemetría** (§6, §8). Se calculará con las marcas de tiempo de ambos sticks.
- **Valores de sensibilidad propios del rol del adulto,** guardados por stick, tras probar con adultos sentados.
- **Pruebas con díadas reales** (criterios 12–14): legibilidad sin instrucciones y reanudación tras la latencia.
