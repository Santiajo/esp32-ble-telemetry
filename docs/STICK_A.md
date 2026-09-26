# Balancín · Cómo incorporar el stick A (fase 7)

> Pasos para sumar el segundo stick (grande, adulto) cuando exista el hardware.
> Todo el software necesario ya soporta dos sticks: el firmware, el controlador BLE,
> `BleStickLink` y el selector de fuente del tablero. Lo que falta es hardware,
> vinculación, ajuste y dos piezas de código indicadas en el paso 6.

---

## Paso 1 · Hardware

- Una segunda **ESP32 DevKit V1** con **MPU6050**, cableada igual que el stick B:
  **SDA → 21 · SCL → 22 · VCC → 3V3 · GND → GND**.
- La especificación pide un **cuerpo distinto** (más grande, más pesado, otra textura), sin botones ni luces a la vista.
- El LED azul de la placa (GPIO2) se usa en el onboarding. Si queda oculto por el cuerpo, no importa: la app no depende de él.

## Paso 2 · Firmware

1. Conecta la placa nueva a Thonny, igual que el stick B (guía de la fase 1). Si no tiene MicroPython, instálalo desde Thonny.
2. Abre `firmware/balancin_stick/main.py` y cambia **una sola línea**:
   ```python
   STICK_ROLE = 'A'
   ```
3. Guárdalo en el dispositivo como `main.py` y reinicia con Ctrl+D.
4. **Verifica en la consola:**
   - `[MPU] OK en dirección 0x68`
   - `[BLE] Anunciando como ESP32-BAL-A`
   - Líneas `v2,…` con el stick quieto. Anota el valor de `gx`, `gy` y `gz` en reposo: es el bias de este sensor (el del B era ~41,6 °/s en X). La app lo resta sola, pero conviene tenerlo registrado.
5. Con nRF Connect, confirma que el MTU negociado es 185 (o cualquier valor ≥ 59) para que envíe a 100 Hz.

## Paso 3 · Vinculación en la app

1. Tablero → selector del **Adulto** → **"Stick"**.
2. Si ya había una MAC guardada para "A" (por ejemplo, de la estación BLE antigua), la app intentará reconectar a esa placa. En ese caso usa **"Vincular otro stick"** en el panel.
3. En el modal de escaneo, `ESP32-BAL-A` aparece primero y resaltado: selecciónalo. La MAC queda guardada con la clave `A`.
4. Deja el stick **quieto ~1 s** hasta que el panel diga "Conectado · ~100 Hz".
5. Selecciona también el Niño = "Stick" (el B). Los dos quedan conectados al mismo tiempo.

> Los roles siguen a la **MAC** de cada placa, no a la persona: intercambiar los sticks físicamente cambia los roles sin configurar nada (criterio 7).

## Paso 4 · Pruebas de banco con los dos sticks

| # | Prueba | Resultado esperado | Criterio |
|---|---|---|---|
| 1 | Solo A en movimiento (B quieto) | Una resonancia grave y después silencio, aunque A siga | 2 |
| 2 | Solo B en movimiento | Silencio absoluto | 1 |
| 3 | Ambos | Juego activo; todas las notas dentro del campo (banda) | 3, 4 |
| 4 | **Adulto sentado, gesto pequeño y lento con A** durante 1 minuto | El campo se mantiene abierto; el borde "moving" del panel A **no parpadea** | 8 |
| 5 | B repite un patrón fijo; A acelera de a poco | Mismo ritmo, alturas que suben de forma continua | 9 |
| 6 | Intercambiar los sticks de mano | Los roles siguen al stick | 7 |
| 7 | Ambos sacuden fuerte a la vez | Timbre oculto (campana) | §4 de la guía |
| 8 | Detener B 1,5 s / detener A 1,5 s / retomar | Latencias con decaimiento gradual y reanudación sin corte | 5, 6 |
| 9 | 10 minutos de juego continuo | Sin desconexiones; ambos paneles cerca de 100 Hz | Estabilidad BLE |

## Paso 5 · Ajuste del stick A

El rol A pide **baja demanda energética**: gestos pequeños, sentado. Cada stick tiene su propio `ImuTuning`, así que se ajustan por separado en "Ajuste IMU".

Punto de partida sugerido para A (a validar con adultos reales):

| Parámetro | B (actual) | A (propuesta inicial) | Por qué |
|---|---|---|---|
| `onDps` / `offDps` | 25 / 12 | **15 / 8** | que un gesto sentado y lento cuente como movimiento |
| `ampFullDeg` | 90° | **60°** | que ±30° ya abra el campo completo |
| `omegaMaxDps` | 400 | **250** | que el registro agudo se alcance sin gestos bruscos |
| `shakeMinDps` | 80 | 80 | igual: la sacudida debe ser intencional |

Cuando los valores estén validados, pásalos con "Copiar valores" a Claude para dejarlos por defecto en el código (ver paso 6).

## Paso 6 · Código pendiente de la fase 7 (Claude)

1. **Tuning por rol persistente:** valores por defecto distintos para A y B, y guardado de los ajustes por stick (shared_preferences). Hoy se pierden al cerrar el tablero.
2. **Relación de fase entre A y B:** la especificación (§6 y §8) pide registrarla en telemetría como métrica descriptiva. El prototipo web no la calcula, así que el motor actual tampoco. Se implementará con las marcas de tiempo `t_ms` de ambos sticks: alineación de relojes, fase instantánea de la oscilación dominante de cada uno y desfase continuo. Se agregará al reporte JSON sin alterar el sonido.
3. **Presupuesto BLE con dos sticks:** verificar que las dos conexiones a 100 Hz no pierdan paquetes. Si pierden, el firmware ya baja solo a 50 Hz cuando el MTU es chico; si igual falla, se agrega una opción de frecuencia en `main.py`.
4. **Pérdida de stick real:** la pantalla de pérdida (fase 6) debe reaccionar a la desconexión de **cualquiera** de los dos sticks.

## Paso 7 · Cierre

- `flutter analyze` y `flutter test` en verde.
- Registrar en `docs/PLAN_BALANCIN.md` (sección 10): bias del stick A, MTU, valores de ajuste finales y resultados de las 9 pruebas.
- Commit: `feat(balancin): fase 7 - stick A real`.
