# Plan de mutación: estación BLE → Balancín

> Documento vivo. Lo leen **Claude** (arquitectura, núcleo en Dart puro, revisión) y **Antigravity** (integración, UI, build y pruebas en el dispositivo).
> Fuentes: `reference/nuevo-prototipo/index.html` (prototipo) y `reference/nuevo-prototipo/Balancin_Especificacion_Funcional_v0.1.pdf` (especificación).
> Versión 1 · 26-09-2026

---

## 0. Decisiones tomadas

| # | Decisión | Consecuencia |
|---|---|---|
| D1 | **El prototipo manda** en valores y comportamiento; la especificación funciona como **criterio de aceptación**. | Las constantes de §4 salen del `index.html` tal cual. Las diferencias conocidas están en §4.8. |
| D2 | Se puede **modificar el firmware**. Hoy solo existe el **stick B** (niño). | Fase 1 = firmware v2 del stick B. El stick A se **simula** en pantalla hasta que exista. |
| D3 | Orden de pantallas: primero el **tablero de validación** (campo interactivo + métricas + sonido), después el **onboarding sin Google** y al final la **experiencia vacía** (modo eje). | El login con Google queda fuera de alcance por ahora. |
| D4 | Motor de audio: **`flutter_soloud`** (v5.1.x, pub.dev). | Ver §5. |
| D5 | Plataforma: solo Android (se mantiene). | — |

## 1. Reglas de trabajo entre agentes

1. **Un archivo, un dueño por vez.** Nunca editan el mismo archivo Claude y Antigravity en la misma fase.
2. **Cada fase termina así:** `flutter analyze` sin errores → `flutter test` en verde → Claude revisa lo que quedó en disco → **commit** (`feat(balancin): fase N …`).
3. **Dart puro = Claude.** Todo lo de `lib/balancin/core/` no importa Flutter: tiempo inyectado, sin plugins y 100 % testeable.
4. **Plataforma y UI = Antigravity**, con prompts que entrega Claude.
5. Si Antigravity necesita cambiar algo de `core/`, **lo propone y no lo edita**.
6. Rama de trabajo: `balancin`. `main` queda como la estación BLE que ya funciona.

## 2. Qué se conserva, qué se adapta y qué es nuevo

| Pieza actual | Destino |
|---|---|
| `controllers/esp_device_controller.dart` (conexión, backoff, MAC, framing) | **Se conserva.** Se agrega un parser v2 (§3) sin romper el formato legado `rawX,rawY`. Se añade `requestConnectionPriority(high)` al conectar, para bajar la latencia. |
| `services/storage_service.dart` | **Se conserva.** Cumple el requisito de "identidad estable por dispositivo": el rol sigue a la MAC del stick. |
| `core/ble/ble_constants.dart` | **Se conserva** (mismos UUID NUS). Se agregan los nombres `ESP32-BAL-A` y `ESP32-BAL-B` y se aceptan los antiguos `ESP32-MPU-*`. |
| Permisos, wakelock, monitoreo del adaptador BT, Ticker 60 FPS | **Se conserva** el patrón. El Ticker ahora mueve el motor (`engine.tick`), además de pintar. |
| `core/physics/physics_engine.dart` | **Se mantiene solo para la pantalla de diagnóstico.** No se usa para gestos: integra posición (deriva) y su rechazo de lecturas mayores a 35 m/s² descartaría las sacudidas (§4.5). |
| `screens/dashboard_screen.dart` + radar, osciloscopios y consola | Pasan a **"Diagnóstico BLE"**, accesible desde el tablero. No se borran. |
| — | **Nuevo:** `lib/balancin/` (§6). |

## 3. Protocolo BLE v2 (firmware)

- Servicio NUS igual (`6e400001-…`, TX notify `6e400003-…`).
- Nombre anunciado: `ESP32-BAL-B` (luego `ESP32-BAL-A`).
- **Muestreo 100 Hz**. Una línea de texto por muestra, terminada en `\n`:

```
v2,<t_ms>,<ax>,<ay>,<az>,<gx>,<gy>,<gz>
```

  - `t_ms`: `time.ticks_ms()` del ESP. En MicroPython **da la vuelta cada 2^30 ms** (unos 12 días), así que la app debe calcular diferencias módulo 2^30. Sirve para medir jitter y, más adelante, alinear A con B.
  - Una línea mide como máximo 56 bytes. Si el MTU es chico, el firmware la parte en trozos y la app la reúne por `\n`. **El parser debe exigir exactamente 8 campos**: si se descarta un trozo, la línea mezclada resultante se ignora.
- Firmware: **MicroPython** en `firmware/balancin_stick/main.py` (se carga con Thonny). El original está en `firmware/legacy/main.py`.
- **Frecuencia adaptativa:** 100 Hz si la línea cabe en un solo paquete (MTU ≥ 59); si no, 50 Hz. El firmware antiguo documentó desconexiones por encima de ~66 Hz con líneas cortas y MTU por defecto. **La app debe pedir un MTU alto al conectar.**
- **LED GPIO2** (el prototipo lo usa en el onboarding y en la pantalla de pérdida): parpadea = esperando teléfono · fijo = conectado · parpadeo rápido = MPU6050 no encontrado.
- `LEGACY_OUTPUT = True` envía `rawX,rawY` a ±2 g y 50 Hz, para probar con la app antigua.
  - `ax..gz`: enteros crudos int16 del MPU6050.
- Configuración del MPU6050: **acelerómetro ±8 g** (4096 LSB/g), porque un niño sacudiendo supera ±2 g; **giroscopio ±1000 °/s** (32.8 LSB/(°/s)); DLPF de 44 Hz.
- Tamaño aproximado de la línea: 45 bytes. Se pide MTU ≥ 64 (Android con flutter_blue_plus ya negocia uno mayor).
- **Compatibilidad:** el parser de la app detecta el formato por el prefijo. Una línea `v2,…` va al lector IMU; dos campos van a la ruta legada (diagnóstico).
- Se evaluará pasar a binario **solo si** la latencia medida lo exige.

## 4. Especificación ejecutable (portada del prototipo)

Todo lo que sigue replica `index.html`. Unidades: tiempo en ms salvo que se indique otra cosa.

### 4.1 Escala
- 25 alturas pentatónicas: `NOTES[i] = 48 + 12*floor(i/5) + [0,2,4,7,9][i%5]` (MIDI; C3 hacia arriba, 5 octavas).
- `hz(m) = 440 * 2^((m-69)/12)`.

### 4.2 Lector de gesto (`GestureReader`): la interfaz común
El motor **no sabe** si el gesto viene del dedo, de un simulador o de la IMU. Cada fuente implementa:

| Campo | Significado | Uso |
|---|---|---|
| `moving` | Se movió en los últimos 200 ms | Transiciones de estado |
| `lastMove` | Instante del último movimiento | Entrar en latencia (1500 ms) |
| `amp` (0–1) | Amplitud del gesto en 0,8 s | A: ancho del campo · B: intensidad |
| `vel01` (0–1) | Velocidad normalizada | A: registro |
| `dx`, `dy` (−1/0/+1) | Dirección del último movimiento | B: paso melódico `step = -dy + dx` (0 → 1) |
| `shake` | ≥ 4 inversiones de dirección en 0,6 s | Timbre oculto |
| `consumeArticulations()` | Nº de "unidades de recorrido" acumuladas desde la última llamada | B: una nota por unidad |

**`TouchGestureReader`** (port 1:1 de la clase `Stick`):
- Guarda 1 s de posiciones.
- `vel = vel*0.7 + (d/dt*1000)*0.3` (px/s). Si pasan más de 80 ms sin moverse, `vel *= 0.85`; por debajo de 2, `vel = 0`. Luego `vel01 = clamp(vel/900)`.
- `amp = clamp(hypot(rangoX, rangoY) / (hypot(w,h)*0.55))` en 0,8 s.
- `dx`/`dy` = signo si `|Δ| > 0.5`.
- Una articulación cada **42 px** de recorrido.
- `shake` = ≥ 4 inversiones de signo en X dentro de 0,6 s.

**`ImuGestureReader`** (nuevo; propuesta inicial que se ajusta en la fase 5 con el stick real):
- Bias del giroscopio: promedio de 1 s en reposo al conectar (y se re-estima en reposo prolongado). **Obligatorio.** El stick B real marca en reposo `gx ≈ 1360 LSB ≈ 41,6 °/s`, más que el umbral `on`. Sin restar el bias, el stick parecería moverse siempre. La estimación debe hacerse solo cuando la varianza del giro sea baja (stick realmente quieto), no simplemente "al conectar".
- `ω = |giro|` en °/s, con EMA.
- `moving`: histéresis de dos niveles sobre ω (`on ≈ 25 °/s`, `off ≈ 12 °/s`) para no parpadear con gestos pequeños del adulto (criterio 8).
- `vel01 = clamp(ω / ω_max)`, con `ω_max ≈ 400 °/s`.
- `amp`: excursión angular del eje dominante, integrando el giro en la ventana de 0,8 s. `amp = clamp(excursión / 90°)`.
- Eje dominante = el de mayor energía del giro en la ventana. `dx` = signo de ese eje; `dy` = signo del segundo eje.
- Articulación: una cada **~25° de recorrido angular** acumulado. Así la densidad rítmica crece con la velocidad, igual que los 42 px del dedo.
- `shake`: ≥ 4 cambios de signo del eje dominante en 0,6 s con `|ω| > umbral`, o `|acc|` alto (±8 g lo permite).
- Todos los umbrales son constantes con nombre, visibles en el panel de ajuste (fase 5).

**`AutoGestureReader`** (simuladores del prototipo):
- "Niño automático": `x = w/2 + 0.36w·sin(1.7t)`, `y = h/2 + 0.32h·sin(3.4t)`.
- "Adulto automático" (nuevo, para probar B real sin segunda persona): usa la curva de la demo, `0.3·sin(0.9t)`, `0.25·sin(1.3t)`, con un control de velocidad.

### 4.3 Máquina de estados
Estados: `REPOSO`, `ESPERA` (solo A), `SILENCIO` (solo B), `ACTIVO`, `LAT_N` (se detuvo B), `LAT_A` (se detuvo A). `A` y `C` son `moving` del adulto y del niño.

```
REPOSO  : A&&C→ACTIVO · A→ESPERA · C→SILENCIO
ESPERA  : A&&C→ACTIVO · !A→REPOSO
SILENCIO: A&&C→ACTIVO · !C→REPOSO
ACTIVO  : (!C && now-B.lastMove>1500)→LAT_N · si no, (!A && now-A.lastMove>1500)→LAT_A
LAT_N/LAT_A: A&&C→ACTIVO · (now-latStart>20000)→cerrar sesión
```

Efectos de `setState`:
- Al salir de una latencia se registra su duración; si el destino es `ACTIVO`, cuenta como reanudación.
- Al entrar en una latencia: `latStart = now` y se suma una latencia.
- `ESPERA` → `playOpening()`.
- `LAT_N` → `playFieldResonance(lo, count)`.

### 4.4 Campo `F` (por tick, `dt` en s, tope 0,05)
```
si A && estado ∈ {ACTIVO, ESPERA, LAT_N}:
    width  += (1 + 13*A.amp - width) * min(1, dt*4)
    center += (2 + 20*A.vel01 - center) * min(1, dt*0.9)
si no, LAT_N:                  width -= 0.6*dt
si no, ACTIVO|LAT_A|ESPERA:    width -= 1.6*dt
si no:                         width -= 12*dt
width = clamp(width, 0, 14)
count = width < 0.5 ? 0 : round(width)
lo    = clamp(round(center - count/2), 0, 25 - count)
rate  = rate*0.9 + (|Δcenter|/dt)*0.1
```
- Familia tímbrica: `oculto` si hay timbre oculto activo; si no, `center < 8.33` → marimba, `< 16.67` → mixta, y en otro caso glock.

### 4.5 Timbre oculto y articulación
- Si `ACTIVO && A.shake && B.shake && now >= hiddenUntil`: `hiddenUntil = now + 6000` y se suma un timbre oculto a las métricas.
- Si `estado ∈ {ACTIVO, LAT_A} && count > 0`: por cada articulación, `pos = (pos + step) mod count`, `idx = lo + pos`, y se emite la nota `NOTES[idx]` con la familia actual y `gain = (0.18 + 0.82*B.amp) * 0.3`.
- En cualquier otro caso se descartan las articulaciones pendientes. **Así B solo nunca suena** (criterio 1).

### 4.6 Regímenes y métricas
- `evs` = notas emitidas en el último segundo.
- Clasificación, solo en `ACTIVO` y en este orden:
  1. timbre oculto activo → 4
  2. `rate > 1.2` → 1
  3. `count >= 8 && evs >= 5` → 2
  4. `count <= 3 && evs <= 2` → 3
  5. en otro caso → 0
- Métricas: `total`, `active`, `fieldOpen` (A activo y `count > 0`), `latN`, `latDur[]`, `resum`, `events`, `variation` (Σ|Δcenter|), `hidden`, `swaps`, `reg[5]`.
- El reporte JSON usa **las mismas claves** que `report()` del prototipo (`duracion_total_s`, `juego_activo_s`, `campo_abierto_s`, `latencias{…}`, `reanudaciones`, `eventos_nino`, `variacion_campo_alturas`, `timbres_ocultos`, `intercambios_stick`, `regimenes[]`).

### 4.7 Sonido
- Familias como listas de parciales `[ratio, ganancia, duración relativa]`:
  - `marimba`: sine, decay 0,8 · `[1,1,1] [4,.3,.25] [9,.15,.12]`
  - `mixta`: sine, decay 1,1 · `[1,1,1] [3,.3,.5] [5.4,.18,.4]`
  - `glock`: sine, decay 1,6 · `[1,1,1] [2.76,.45,.9] [5.4,.25,.7] [8.9,.12,.5]`
  - `oculto`: triangle, decay 2,2 · `[1,.7,1] [1.5,.45,.9] [2,.35,.8] [3,.2,.6]`
  - `LOW` (sistema): sine, decay 3 · `[1,1,1] [2,.25,.6] [3,.1,.4]`
- Envolvente por parcial: ataque exponencial de 4 ms hasta `gain*g`, y caída exponencial hasta 0,0001 en `decay*d`.
- Sonidos de sistema:
  - **Apertura:** MIDI 48, 55, 60 con LOW; ganancias .22, .17, .12; decay 3; separación 60 ms.
  - **Resonancia de campo:** desde `lo` con paso `max(1, floor(n/6))`; ganancia .13; decay 2,4; separación 70 ms.
  - **Final:** MIDI 48, 52, 55; ganancia .2; decay 5; separación 120 ms.
- Bus: ganancia 0,8, luego limitador/compresor (umbral −16 dB, ratio 3).
- Pérdida de stick: el bus baja en 1,2 s; al reanudar sube en 0,6 s y el motor vuelve a `REPOSO` conservando la telemetría.
- **Luz:** `lvl = clamp(rms*6, 0, 1)`. Se calcula con un **modelo de envolvente en Dart** (suma de las envolventes vivas), no leyendo el audio.

### 4.8 Diferencias conocidas prototipo ↔ especificación (se mantiene el prototipo; se vigilan en las pruebas)

| Tema | Prototipo | Especificación |
|---|---|---|
| Alturas | 25 (5 octavas) | 15 (3 octavas) |
| `t_hold` | 1,5 s | 0,5–1 s |
| Latencia larga | Cierra la sesión a los 20 s | No lo menciona |
| Resonancia de apertura | Se repite en cada REPOSO → ESPERA | "Una vez por apertura del campo" |
| Interdependencia | Parcialmente vía estado (`ACTIVO`/`LAT_A`) | "No codificar como compuerta" |
| `t_join` | No existe | ≈ 1 s |

## 5. Motor de audio: `flutter_soloud`

**Por qué:** es un motor C++ (SoLoud + miniaudio) vía FFI. La documentación oficial de Flutter lo recomienda para efectos de sonido de baja latencia. Permite reproducir la misma fuente muchas veces a la vez (un handle por voz), cargar desde memoria, usar efectos (limitador, reverb) y hacer `playClocked` para programar con precisión. Versión 5.1.2, publicada en septiembre de 2026, con 160 pub points.

**Alternativa descartada:** `flutter_pcm_sound` (síntesis PCM propia). Da control total, pero habría que escribir la mezcla de voces y la polifonía a mano, y su última versión es de octubre de 2025. Queda como plan B si SoLoud no llega a la latencia objetivo.

**Estrategia:**
1. `SynthRenderer` (Dart puro, Claude) renderiza cada nota con la receta de §4.7 a **WAV PCM 16-bit mono de 44,1 kHz en memoria** al iniciar la app: 25 notas × 4 familias más 6 sonidos de sistema. Son unos 15 MB de RAM; si sobra, se baja a 22,05 kHz o se recortan las colas.
2. `AudioEngine` (Antigravity) hace `SoLoud.init` con `bufferSize` bajo, `loadMem` de cada WAV, y `play(source, volume: gain)` por nota. Agrega el filtro limitador al bus y hace el fade global en la pérdida de stick.
3. Se mide la latencia: tap en el panel → sonido (grabación con otro teléfono, o un loopback de audio). **Meta: ≤ 30 ms de extremo a extremo**, según la especificación.

**Detalles decididos al implementar la fase 3:**
- `SoLoud.init(bufferSize: …)`: el valor por defecto de 2048 frames equivale a unos 46 ms y **rompe la meta**. Se empieza en 512 y se prueba 256; si hay crujidos se sube.
- Mono, 44,1 kHz. Parciales por sobre 0,45·sr se omiten (sin aliasing). Triángulo del timbre oculto: banda limitada hasta el 9.º armónico.
- **Precarga:** 100 notas de juego (4 familias × 25) más apertura, final y campanita, renderizadas en un `Isolate`. Son unos 13 MB en WAV.
- **Resonancias de campo (decay 2,4 s): se renderizan bajo demanda** en un `Isolate` y se cachean. Suenan después de 1,5 s de quietud, así que no son sensibles a la latencia. Precargarlas costaría más de 20 MB adicionales.
- Los WAV se guardan a escala 0,5 (sin saturación); `SynthRenderer.volumeFor(gain)` y `bakedVolume` compensan al reproducir.
- La luz se calcula con `LightEnvelope` (modelo de envolventes en Dart), no leyendo el audio.

## 6. Arquitectura de carpetas nueva

```
lib/balancin/
  core/                       ← Dart puro (Claude). Sin imports de Flutter.
    constants.dart            (todo §4 como constantes con nombre)
    scale.dart                (NOTES, hz)
    gesture/gesture_reader.dart        (interfaz §4.2)
    gesture/touch_gesture_reader.dart
    gesture/imu_gesture_reader.dart
    gesture/auto_gesture_reader.dart
    engine/balancin_engine.dart        (tick(now, a, b) → List<SoundCommand>)
    engine/field.dart
    engine/sound_command.dart          (NoteOn, Opening, FieldResonance, Final, BusFade)
    telemetry/session_metrics.dart
    telemetry/session_report.dart      (JSON §4.6)
    audio/synth_renderer.dart          (WAV en memoria)
    audio/light_envelope.dart
    ble/imu_frame_parser.dart          (línea v2 → ImuSample)
  platform/                   ← Antigravity
    audio_engine.dart         (flutter_soloud)
    ble_stick_source.dart     (EspDeviceController → ImuGestureReader)
    telemetry_exporter.dart   (guardar/compartir JSON)
  screens/                    ← Antigravity
    board_screen.dart         (tablero de validación)
    tuning_panel.dart         (ajuste de umbrales IMU en vivo)
    closed_screen.dart        (cierre + regímenes + exportar)
    onboarding/…              (5 pasos, sin Google)
    insert_screen.dart, eje_screen.dart, lost_screen.dart, resumen_screen.dart
test/balancin/                ← Claude
```

El motor es **determinista**: recibe `now` y los lectores. Así los tests reproducen los criterios de aceptación sin dispositivo.

## 7. Fases

### Fase 0 · Preparación (tú, 5 min)
- [ ] Commit del estado actual en `main`. El `git status` mostró unos 88 archivos "modificados" que son solo finales de línea (CRLF). Se puede fijar `core.autocrlf` antes de commitear.
- [ ] Crear la rama `balancin`.
- **Hecho cuando:** `git log` muestra el commit y la rama existe.

### Fase 1 · Firmware v2 del stick B (Claude escribe, tú cargas con Thonny)
- Claude entrega `firmware/balancin_stick/main.py` (MicroPython: módulo `bluetooth` con NUS y MPU6050 por `machine.I2C`, sin librerías externas) con `STICK_ROLE = 'B'`.
- Tú lo cargas con Thonny. Antes, respaldas el `main.py` viejo del ESP en `firmware/legacy/`.
- **Hecho cuando:** nRF Connect (o la pantalla de diagnóstico) muestra líneas `v2,…` a ~100 Hz y el giro responde al mover el stick.

### Fase 2 · Núcleo en Dart puro (Claude)
- `constants`, `scale`, `TouchGestureReader`, `AutoGestureReader`, `BalancinEngine`, `field`, métricas y reporte, más `imu_frame_parser`.
- Tests: criterios 1, 2, 3, 4, 5, 6, 7 y 9 de la especificación con gestos sintéticos, y paridad numérica con el prototipo en escenarios de las demos (`espera`, `silencio`, `activo`, `latN`, `latA`, `oculto`).
- **Hecho cuando:** `flutter test` está en verde (lo corre Antigravity y Claude revisa).

### Fase 3 · Audio (Claude: `SynthRenderer`; Antigravity: `AudioEngine`)
- Agregar `flutter_soloud` y una pantalla temporal "piano pentatónico" con 25 teclas × familia.
- **Hecho cuando:** las notas suenan en el teléfono sin cortes con más de 20 voces simultáneas, y la latencia medida está anotada en este documento.

### Fase 4 · Tablero de validación con dedos (Antigravity, prompt de Claude)
- Port de la pantalla `#session`:
  - píldora de estado;
  - banda de 25 columnas con la ventana del campo y destellos;
  - texto del campo;
  - LED;
  - dos paneles táctiles (multitouch, uno por mitad);
  - tarjetas de telemetría;
  - botones "Intercambiar sticks", "Niño automático", "Modo eje" y "Terminar".
- Más la pantalla de cierre (`#closed`) con barras de regímenes y "Exportar JSON".
- **Hecho cuando:** en el teléfono se comporta como `index.html#session`, incluidas las demos.

### Fase 5 · Stick B real: el primer hito físico
- Claude: `ImuGestureReader`, más tests con grabaciones reales (se graban trazas `v2` del stick a un archivo desde la app).
- Antigravity: `BleStickSource` y un **selector de fuente por rol** en el tablero. Configuración de este hito: **A = dedo o "Adulto automático"**, **B = stick BLE real**. Además, el panel de ajuste con los umbrales en vivo y la visualización de `moving`, `amp`, `vel01`, `shake` y articulaciones.
- **Hecho cuando:**
  - B real solo → silencio absoluto (criterio 1);
  - con A simulado → las notas de B caen dentro del campo (3, 4);
  - mover B más rápido → más notas por segundo;
  - B quieto por 1,5 s → LAT_N con resonancia (5, 6);
  - sacudir B mientras A simulado sacude → timbre oculto.

### Fase 6 · Onboarding sin Google (Antigravity)
- 5 pasos del prototipo:
  1. Permisos de Bluetooth y No Molestar (requiere acceso a la política de notificaciones; si el usuario lo rechaza se continúa igual).
  2. Confirmación de No Molestar.
  3. Insertar en el eje.
  4. **Vincular sticks.** "Mantener 3 s" dispara un escaneo real y adopta el stick por nombre: `…-A` → grande, `…-B` → pequeño.
  5. Entregar los sticks.
- Pantalla de pérdida de stick conectada a la desconexión real del `EspDeviceController`.
- **Hecho cuando:** una instalación limpia llega al tablero con B vinculado sin tocar la pantalla de diagnóstico.

### Fase 7 · Stick A real
- Flashear el segundo ESP con `STICK_ROLE 'A'`.
- Validar el criterio 8 (gesto pequeño sentado no parpadea) y ajustar la histéresis.
- Alinear relojes A/B con `t_ms`.

### Fase 8 · Experiencia vacía
- Modo eje: pantalla negra con dos franjas de luz y destellos.
- Pantalla de inserción con autoinicio a los 6 s.
- Pantalla de recuerdo (cinta de regímenes y 3 tarjetas).
- Sin tablero en el flujo de usuario final.
- **Hecho cuando:** se cumplen los criterios 10 y 11 y el flujo completo funciona sin mirar la pantalla.

## 8. Criterios de aceptación → dónde se prueban

| # | Criterio (resumen) | Test automático | Prueba en banco |
|---|---|---|---|
| 1 | B solo no suena | Fase 2 | Fase 5 |
| 2 | A solo: una resonancia y silencio | Fase 2 | Fase 4 (dedo), 7 |
| 3 | Notas de B dentro del campo | Fase 2 | Fase 5 |
| 4 | Solo alturas pentatónicas | Fase 2 | — |
| 5 | Transiciones al silencio graduales | Fase 2 (envolventes) | Fase 3–5 (oído) |
| 6 | Retomar antes de agotarse = sin corte | Fase 2 | Fase 5 |
| 7 | Intercambiar sticks sin configurar | Fase 2 (swap) | Fase 7 |
| 8 | Gesto pequeño de A estable | — | Fase 7 |
| 9 | Régimen 2 (mismo patrón, otras alturas) | Fase 2 | Fase 7 |
| 10 | Nada en pantalla, luz sin estado | — | Fase 8 |
| 11 | Telemetría sin identificadores | Fase 2 (claves del JSON) | Fase 8 |
| 12–14 | Pruebas con díadas | — | Fuera de este plan |

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| Latencia de extremo a extremo > 30 ms | Prioridad de conexión BLE alta, 100 Hz, buffer de SoLoud mínimo estable, medir en la fase 3. Plan B: `flutter_pcm_sound` o protocolo binario. |
| Umbrales IMU mal calibrados (parpadeo o insensibilidad) | Panel de ajuste en vivo más grabación de trazas para tests (fase 5). |
| Saturación en sacudidas | Acelerómetro a ±8 g y detección de shake principalmente por giroscopio. |
| RAM de los samples | Bajar la frecuencia de muestreo o recortar colas. |
| Permiso de No Molestar (Android) | Opcional; el juego funciona sin él. |
| CRLF / archivos fantasma en git | Configurar `.gitattributes` en la fase 0. |

## 10. Registro

| Fecha | Fase | Nota |
|---|---|---|
| 26-09-2026 | — | Plan v1. Audio: flutter_soloud 5.1.2. |
| 26-09-2026 | 0 | Commit en `main` y rama `balancin` creada. |
| 26-09-2026 | 1 | Firmware pasa a MicroPython (el usuario ya trabajaba con Thonny). `main.py` escrito. |
| 26-09-2026 | 1 | Firmware v2 corriendo en el stick B: MPU en 0x68, 1 g ≈ 4096 LSB, bucle exacto a 100 Hz. Bias de giroscopio X ≈ 41,6 °/s. Falta la verificación BLE con nRF Connect. |
| 26-09-2026 | 2 | Núcleo Dart escrito en `lib/balancin/core/` más 2 archivos de test en `test/balancin/`. Expectativas validadas contra una réplica en Python del motor. Pendiente: `flutter analyze` y `flutter test` en Antigravity. |
| 26-09-2026 | 2 | ✅ Tests en verde (Antigravity), commit en `balancin`. Núcleo verificado sin cambios (hash idéntico). |
| 26-09-2026 | 3 | Claude escribió `core/audio/synth_renderer.dart`, `core/audio/light_envelope.dart` y `test/balancin/audio_core_test.dart`. Siguiente: `AudioEngine` (flutter_soloud) y la pantalla de prueba de audio en Antigravity. |
| 26-09-2026 | 3 | ✅ Antigravity: `platform/audio_engine.dart` (buffer 512, limitador activo) y `screens/audio_test_screen.dart`. En el teléfono: carga de 2–3 s, sin crujidos, sin retraso perceptible, la luz funciona. Commit `3d7e465`. |
| 26-09-2026 | 1 | ✅ BLE: MTU negociado 185, así que el stick envía a 100 Hz. La app antigua no muestra datos porque no entiende `v2` (se resuelve en la fase 5). |
| 26-09-2026 | 4 | Claude escribió `session/board_session.dart` (controlador del tablero: sides, auto, demos, destellos, luz del eje, tarjetas, pérdida, cierre) y `test/balancin/board_session_test.dart`. Incluye "Adulto automático". Siguiente: UI en Antigravity. |
| 26-09-2026 | 4 | ✅ Antigravity: `home_screen.dart`, `board_screen.dart` (CustomPainter 25 columnas, paneles multitoque con Listener, controles y modo eje), `closed_screen.dart` (tarjetas, regímenes y exportación JSON con share_plus) y `telemetry_exporter.dart`. 53/53 tests en verde, 0 issues de análisis, verificado en moto g34 5G. |
