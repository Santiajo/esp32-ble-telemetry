# Plan · Balancín mecánica v2 (niveles de movimientos coordinados)

> Documento vivo. Lo leen **Claude** (núcleo en Dart puro, arquitectura, revisión) y **Antigravity** (plataforma, UI, build y pruebas en el teléfono), con las mismas reglas de trabajo de `docs/PLAN_BALANCIN.md` §1.
> Fuente: `reference/mecanica-v2/index.html` (prototipo HTML «mecánica v2»).
> Rama: `mecanica-v2` (sale de `balancin` en `6d26705`, entregable 0.9.0).
> Versión 1 · 17-10-2026

---

## 0. Decisiones tomadas

| # | Decisión | Consecuencia |
|---|---|---|
| V1 | **El prototipo v2 manda.** La especificación v0.1 deja de ser criterio de aceptación donde se contradigan (consignas, progreso, luz que codifica sincronía, el niño suena solo). | Las constantes de §4 salen de `index.html` tal cual. |
| V2 | **Sin inicio de sesión con Google** por ahora. | La app arranca en la preparación (primera vez) o en el inicio. Todo se guarda solo en el teléfono. |
| V3 | **Sin vibración** en v2. | No se toca el hardware. Se elimina la vibración del motor y el filtro «ignorar lecturas mientras vibra». |
| V4 | **Prioridad: nivel 1 «Juntos» y modo Libre, perfectos.** | Los niveles 2–7 se definen en el catálogo, pero se muestran como «Próximamente» y no se pueden abrir. |
| V5 | **Se conserva el banco de prueba** (plano con los dos puntos) y el plano **tiene límite**: el punto nunca sale del área visible. | Ver §5. |
| V6 | **El firmware no cambia.** La línea `v2` ya trae el acelerómetro y el giroscopio que se necesitan para medir la inclinación. | La fusión de sensores se hace en la app (es ajustable y testeable). |

## 1. Qué se conserva, qué se adapta y qué es nuevo

| Pieza actual (0.9.0) | Destino en v2 |
|---|---|
| `firmware/balancin_stick/main.py` | **Sin cambios.** |
| `controllers/esp_device_controller.dart`, `platform/stick_hub.dart`, `platform/ble_stick_link.dart`, `core/ble/imu_frame_parser.dart` | **Se conservan.** `BleStickLink` pasa a alimentar un `TiltReader` en vez de (o además de) el `ImuGestureReader`. |
| `session/loss_monitor.dart`, `screens/lost_screen.dart` | **Se conservan.** La causa siempre es «Fuera de alcance» (la batería no se mide). Los textos se ajustan al prototipo. |
| `screens/onboarding/onboarding_screen.dart`, `widgets/hold_button.dart` | **Se conservan.** Al terminar, la preparación lleva a la lista de niveles. |
| `screens/experience/insert_screen.dart` | **Se adapta:** muestra el nivel elegido y termina con la transición circular («iris»). |
| `platform/audio_engine.dart` (flutter_soloud) | **Se amplía:** voces continuas, nueva cadena de mezcla y nuevas familias (§4.6). |
| `core/audio/synth_renderer.dart` | **Se amplía** con las familias v2 (`marimba2`, `glock2`, `pad`, `low`). Las de v1 quedan para la rama `balancin`. |
| `platform/session_archive.dart`, `platform/telemetry_exporter.dart` | **Se reutilizan** con el esquema JSON nuevo (§4.8). |
| `core/engine/balancin_engine.dart`, `core/gesture/imu_gesture_reader.dart`, `session/board_session.dart`, `session/session_memory.dart` y sus pantallas | **No se usan en v2.** Quedan en el código mientras dure la transición y se borran al cerrar la fase 6. |
| `core/gesture/imu_gesture_reader.dart` → estimación del bias en reposo | **Se reutiliza la lógica** dentro del `TiltReader`. |
| — | **Nuevo:** `lib/balancin_v2/` (§6). |

## 2. El sensor y el firmware (lo que hay que saber para v2)

**MPU6050.** Es una IMU de 6 ejes: acelerómetro de 3 ejes y giroscopio de 3 ejes, de 16 bits, por I²C (dirección 0x68). **No tiene magnetómetro.** Configuración del firmware:

| Registro | Valor | Efecto |
|---|---|---|
| `PWR_MGMT_1` | 0x01 | Reloj tomado del PLL del giroscopio X, más estable que el oscilador interno. |
| `CONFIG` | 0x03 | Filtro pasa-bajos digital (DLPF) de ~44 Hz. |
| `SMPLRT_DIV` | 9 | 1 kHz / 10 = 100 Hz. |
| `GYRO_CONFIG` | 0x10 | ±1000 °/s → 32,8 LSB por °/s. |
| `ACCEL_CONFIG` | 0x10 | ±8 g → 4096 LSB por g. |

**Qué se puede medir y qué no:**
- **La inclinación (cabeceo y alabeo) sí es absoluta:** en reposo el acelerómetro mide la gravedad, y su dirección dice cuánto está inclinado el stick. No deriva con el tiempo. Es exactamente lo que necesita v2.
- **El giro alrededor de la vertical (guiñada) no es absoluto:** sin magnetómetro solo se puede integrar el giroscopio, y deriva. v2 no lo usa.
- **Durante el movimiento** el acelerómetro suma la aceleración del gesto a la gravedad, así que la inclinación «salta». Por eso se fusiona con el giroscopio (§4.1).
- **Bias del giroscopio:** stick B ≈ 41,6 °/s en X (grande), stick A ≈ (−3,4, +6,0, +0,9) °/s. Se estima en reposo, como ya hace `ImuGestureReader`.
- **Escala del acelerómetro:** el stick A marca 1,08 g en reposo. No importa, porque se usa la **dirección** del vector (normalizado), no su largo.

**Firmware (MicroPython, `firmware/balancin_stick/main.py`):**
- Lee los 14 bytes de una vez (acelerómetro, temperatura y giroscopio). La temperatura se descarta.
- Envía por BLE (Nordic UART, notificaciones en `6e400003`) una línea de texto por muestra: `v2,<t_ms>,<ax>,<ay>,<az>,<gx>,<gy>,<gz>\n`.
- **Frecuencia:** 100 Hz si la línea cabe en un paquete (MTU ≥ 59; el teléfono negocia 185); si no, 50 Hz, partiendo la línea en trozos.
- `t_ms` es `ticks_ms()` del ESP32 (vuelve a cero cada 2^30 ms). El parser lo maneja con `ticksDiff`.
- **LED GPIO2:** parpadeo = esperando teléfono · fijo = conectado · parpadeo rápido = MPU6050 no encontrado.
- **Robustez:**
  - vuelve a anunciarse siempre tras una desconexión;
  - tolera errores de I²C;
  - descarta muestras si la cola BLE se llena;
  - el bucle de 100 Hz se resincroniza sin acumular atraso.
- La característica RX (`6e400002`) está **registrada pero sin uso**. Servirá para la vibración en una versión futura.
- No mide batería.

## 3. Alcance de v2

**Entra:**
- Flujo de usuario sin Google:
  - preparación (solo la primera vez);
  - inicio;
  - elegir modo (Libre o Niveles), y en Niveles, el nivel;
  - pantalla del nivel e inserción en el eje;
  - calibración;
  - juego solo con luz;
  - final.
- **Nivel 1 «Juntos» y modo Libre** completos: motor, sonido en tres capas, voz de consignas, luz en dos mitades y telemetría.
- **Banco de prueba** con plano limitado, fuentes táctil, sintética y stick real por rol, ajuste en vivo y telemetría por nivel.
- Progreso de la canción y sesiones pasadas guardados en el teléfono.
- Pérdida y reconexión de sticks.

**Queda fuera:**
- Google;
- vibración;
- niveles 2–7 (visibles como «Próximamente»);
- causa «batería agotada»;
- botón «Compartir sesión»;
- voces grabadas (se usa síntesis de voz del teléfono como marcador).

## 4. Especificación ejecutable (portada del prototipo)

Unidades: posición en el plano de −6 a 6, tiempo en ms salvo que se indique otra cosa.

### 4.1 Inclinación desde el stick real (`TiltReader`), nuevo

El prototipo recibe la inclinación ya hecha (el dedo simula ±60°). En el teléfono hay que calcularla:

1. **Gravedad estimada `ĝ`** (vector unitario en el marco del sensor), con un filtro complementario:
   - **Predicción con el giroscopio** (bias restado, en rad/s): `ĝ ← ĝ − (ω × ĝ)·dt`, con `dt` sacado de `t_ms`.
   - **Corrección con el acelerómetro:** `ĝ ← normalizar(ĝ + k·(â − ĝ))`, con `â = a/|a|`.
     - `k = 0,02` cuando `| |a| − |a|ᵣₑₚₒₛₒ | < 0,15 g`;
     - `k = 0` cuando el gesto es brusco (solo manda el giroscopio).
2. **Neutro `g₀`:** el promedio de `ĝ` durante el primer segundo de la calibración (§4.3). Ese momento es la posición de descanso de cada persona.
3. **Ejes del usuario:** `e_arriba` y `e_derecha` en el marco del sensor, ortonormalizados respecto de `g₀`. Por defecto `e_derecha` = eje X del sensor y `e_arriba` = `g₀ × e_derecha` (§10.1). El **asistente de ejes** (§5.3) puede corregirlos una vez por stick; se guardan con su MAC.
4. **Ángulos:** `tiltY = atan2(ĝ·e_arriba, ĝ·g₀)` y `tiltX = atan2(ĝ·e_derecha, ĝ·g₀)`, en grados.
5. A partir de aquí el stick real entrega `(tiltX, tiltY)`, lo mismo que el dedo. El resto del motor no distingue la fuente.

Constantes con nombre y ajustables: `kAccel = 0,02` y `accelGate = 0,15 g`. El bias se estima con la misma regla de quietud de `ImuGestureReader` (desviación < 3 °/s durante 0,5 s).

### 4.2 Stick (lectura común, port de la clase `Stick`)

- `feedTilt(tx, ty)`: `raw = clamp(6·(t − centro)/medioRango, −6, 6)` por eje.
- `update(t, dt)`:
  - `a = clamp(α·1,6, 0,02, 1)`, con α = 0,2;
  - `pos += (raw − pos)·a`;
  - `speed = speed·0,7 + |Δpos|/dt·0,3`;
  - si `speed > onSpeed` (2,5 u/s), `lastActive = t`;
  - historial de 4,5 s.
- `active(t)`: hay lectura y `t − lastActive < 2000`.
- `rhythm(t)`: frecuencia por cruces por cero en el eje dominante, ventana de 3 s (se usa para la luz y el banco; el nivel 5 la necesitará).
- **`pos` y `raw` nunca salen de [−6, 6].** Es la base del límite del plano.

### 4.3 Calibración (6 s)

- Se guardan las inclinaciones crudas de cada stick.
- **Centro** = promedio del primer segundo.
- **Medio rango** = `max(|p95 − centro|, |p5 − centro|)` en X e Y, con lo que quede después del primer segundo. Mínimo de 15° (adulto) y 25° (niño).
- Si hay menos de 3 muestras en el primer segundo o menos de 10 después, se usan los valores por defecto: 30° (adulto) y 45° (niño).
- La voz dice «Muévanse libremente unos segundos». La luz respira (`0,65 + 0,25·sin(t/400)`).

### 4.4 Motor de sincronía (`SyncEngine`)

**Distancia `d`:**
- Nivel 1 «Juntos»: `d = |c.y − p.y|`. Solo cuenta la altura; el movimiento lateral no influye.
- Libre: `d = min(|c.y − p.y| + 0,5·|c.x − p.x|, hypot(c.x + p.x, c.y − p.y), |c.y + p.y| + 0,5·|c.x − p.x|)`, es decir, la relación más cercana entre juntos, espejo y sube y baja.

**Sincronía con histéresis:** `inSync = inSync ? d ≤ 1,25·tol : d < tol`, con `tol = 1,2·tolScale`.

**Por cada tick (`dt` con tope de 0,05 s), en estado `playing`:**
- Telemetría: `juego += dt`, `dS += d`, `dN++`.
- **Si los dos están activos:**
  - `bothT += dt`;
  - si `inSync`: `sinc += dt`, `syncT += dt`, se marca la primera sincronía y, en Niveles, `prog += dt`.
- **Si no están activos los dos:**
  - tras `idleAfter` (3 s) se cuenta una pausa (una vez por episodio) y `prog` baja `decay·dt` (0,5/s);
  - tras `endAfter` (30 s), **la sesión se cierra** (solo en el flujo de usuario, no en el banco).
- Al volver a estar los dos activos tras una pausa se cuenta una reanudación.

**Nivel 1:**
- Guía el adulto. Cuando `prog ≥ sec/2` (4 s), cambia a «Ahora guía el niño», una sola vez.
- Con `prog ≥ sec` (8 s) el nivel queda **logrado**:
  - se guarda en el progreso;
  - suena la frase do4–re4–mi4–sol4 y la luz destella;
  - **v2: al terminar la frase se cierra la sesión y va al final**, porque el nivel 2 no está habilitado.
- `sec = 8·secScale`.

**Libre:** no hay progreso ni guía. Solo sonido, luz y telemetría.

**Quién guía:** correlación cruzada cada 500 ms, en una ventana de 4 s, con retrasos de −1 a +1 s en pasos de 0,1 s, sobre el eje dominante del adulto. Si `|r| < 0,3` no hay dato. Retraso > 0 = guía el adulto.

**Estados:** `idle` → `calibrating` → `playing` → `levelComplete` → (cierre).

### 4.5 Parámetros (persistidos y editables en el banco)

`tolScale 1 · alpha 0,2 · rangeA 30° · rangeC 45° · minA 15° · minC 25° · onSpeed 2,5 · hyst 1,25 · secScale 1 · idleAfter 3 s · decay 0,5 · maxDetune 4 Hz · followLag 0,8 · rhythmWin 3 s · endAfter 30 s`

Se agregan `kAccel` y `accelGate` (§4.1). Se quita `vibMs`.

### 4.6 Sonido

**Notas:** pentatónica de do. Adulto: `PA = [48, 50, 52, 55, 57, 60, 62, 64, 67]` (do3–sol4). Niño: `PC = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84]` (do4–do6).

**Capa 1 · Voz del adulto (continua):**
- seno en `fa = hz(PA[round((p.y + 6)/12·8)])`, más un 2.º armónico con ganancia 0,22;
- glide con τ = 50 ms;
- ganancia 0,12 si el adulto está activo (subida τ 0,1 s) y 0 si no (bajada τ 0,5 s).

**Capa 2 · Tono de relación (continuo):**
- `det = 0` si `d ≤ tol`; si no, `0,5 + (maxDetune − 0,5)·clamp((d − tol)/(6 − tol))` Hz;
- se suaviza con `df += (det − df)·min(1, 3·dt)`;
- dos senos en `2fa` y `2fa + df`: su batido es la «ondulación»;
- más una quinta en `3fa`;
- ganancia 0,045 si los dos están activos en `playing`; la quinta suma 0,022 solo con `det = 0`.

**Capa 3 · Notas del niño:**
- marimba en `PC[round((c.y + 6)/12·10)]` cada vez que el punto cambia de celda entera `(round x, round y)`, como mucho cada 100 ms;
- `gain = clamp(0,08 + speed/45, 0,08, 0,22)`;
- suenan aunque el adulto esté quieto, como en el prototipo.

**Extras:**
- **pad:** cada 420 ms repite las notas de las frases ya ganadas, con ganancia `0,03 + 0,004·nFrases`;
- frase al lograr el nivel: glock, 0,24 s entre notas;
- canción en el final;
- cierre: do3, mi3 y sol3 en low, 0,12 s entre notas.

**Familias (parciales `[ratio, ganancia, duración]`):**

| Familia | Onda | Decay | Parciales |
|---|---|---|---|
| `marimba2` | sine | 1,1 | `[1,1,1] [4,.16,.3] [10,.04,.12]` |
| `glock2` | sine | 1,9 | `[1,1,1] [2.76,.22,.7] [5.4,.07,.4]` |
| `pad` | sine | 1,6 | `[1,1,1] [2,.12,.5]` |
| `low` | sine | 3 | `[1,1,1] [2,.25,.6] [3,.1,.4]` |

- **Envolvente:** ataque lineal de 12 ms y caída exponencial con τ = `decay·d/4,5`.
- **Polifonía:** máximo 22 voces; la ganancia baja con `1/√(1 + 0,35·voces)`.

**Cadena de mezcla:** bus 0,8 → pasa-altos 70 Hz → EQ (low-shelf 220 Hz +1 dB, pico 1,4 kHz −2 dB, high-shelf 3,8 kHz −5 dB) → pasa-bajos 8,5 kHz. Desde ahí:
- seco → compresor (−22 dB, ratio 2,5);
- en paralelo, una reverb (pasa-bajos 3,2 kHz, cola de ~2,4 s, retorno 0,2) que entra al mismo compresor.

Después: limitador (−4 dB, ratio 20) → master 0,75.

**En flutter_soloud:**
- las voces continuas son 5 fuentes `loadWaveform(WaveForm.sin)` con `setWaveformFreq` y `setVolume`. El glide y los τ se calculan en Dart en cada tick;
- reverb = `FreeverbFilter`; compresor y limitador = filtros globales; EQ = `BiquadResonantFilter` y `ParametricEq`;
- las notas, frases y el pad siguen como WAV prerenderizados por `SynthRenderer`: 11 notas del niño, 16 de las frases, la escala del pad y low.
- **Riesgo:** «zipper» al cambiar la frecuencia a 60 Hz. Mitigación: subir la tasa de actualización o pasar a `flutter_pcm_sound` (plan B de la v1).

**Voz de consignas:** `flutter_tts` (español), activable y desactivable en el banco. Frases del nivel 1:
- «Nivel 1. Juntos. Suban y bajen los sticks al mismo tiempo. Guía el adulto, luego el niño.»
- «Ahora guía el niño.»

Libre: «Juego libre. Busquen un movimiento en común.» Calibración: «Muévanse libremente unos segundos.»

**Pérdida de stick:** el bus baja en 1,2 s; al reconectar sube en 0,6 s y los sticks se reinician sin perder la telemetría (como en v1).

### 4.7 Luz en dos mitades (pantalla en el eje)

- **Arriba, adulto:** lila `(179,162,220)`. **Abajo, niño:** coral `(232,94,69)`. Ambas se funden hacia oliva `(143,163,62)` según `s = clamp(1 − d/(2·tol))`, solo en `playing` con los dos activos (`s = 1` con la canción completa).
- **Brillo por mitad:** `clamp(0,5 + speed/14, 0,5, 1)` si esa persona está activa; si no, 0,14.
- **Latido en sincronía:** `0,72 + 0,28·sin(2π·f·t)`, con `f = 1 Hz` (en el nivel 5 sería la frecuencia del ritmo).
- Destello corto al lograr el nivel y largo con la canción completa.
- Las esquinas superiores conservan la salida actual: izquierda = banco, derecha = terminar.

### 4.8 Telemetría y recuerdo

**Reporte JSON (mismas claves que `report()` del prototipo):**
- campos generales: `proyecto`, `nota`, `inicio`, `modo`, `duracion_s`, `en_sincronia_s`, `niveles_logrados`, `cancion_completa`, `parametros`;
- por nivel: `niveles[] { nivel, tiempo_a_primera_sincronia_s, porcentaje_en_sincronia, d_promedio, retraso_promedio_s, porcentaje_adulto_sigue_al_nino, pausas, reanudaciones, tiempo_para_completar_s }`.

**Registro de sesión (para «Sesiones pasadas»):**
- `{ t, mode, levels, dur, sync, song, lead, traj }`;
- `traj` = posiciones cada 100 ms, reducidas a ≤ 300 puntos;
- se guardan las últimas 20 si duraron más de 2 s.

**Recuerdo:** dibujo de las dos trayectorias (lila y coral) sobre el plano. «Guardar el recuerdo» lo exporta como **imagen PNG** (se reutiliza `gal`).

## 5. Banco de prueba con plano limitado

Reemplaza al «Tablero de validación» de v1. Se llega desde el inicio, en la sección «Herramientas del equipo», junto a «Diagnóstico BLE» y «Prueba de audio».

### 5.1 Contenido (port de `#banco`)

- **Píldora de estado:** Listo, Calibrando, Jugando o Nivel logrado, con la descripción del nivel.
- **Plano** de −6 a 6:
  - rejilla con ejes;
  - estela de 2 s de cada punto;
  - punto lila del adulto (radio 11) y coral del niño (7,5);
  - en el nivel 1, la **zona objetivo**: círculo de radio `tol` en `(c.x, p.y)`, con una línea discontinua y la etiqueta `d` desde el niño.
- **Medidores:**
  - `d` y tolerancia;
  - «En sincronía», «Fuera de sincronía» o «Sincronía sin actividad»;
  - barra de progreso;
  - nivel y quién guía;
  - ritmo de cada uno y «quién va adelante».
- **Dos paneles táctiles** (adulto y niño), cada uno con su punto y «Activo» o «Quieto». Cada mitad acepta su propio dedo (multitouch).
- **Controles:**
  - nivel (Libre o 1);
  - Calibrar rango;
  - Fuente **por rol**: Dedo · Sintética (sincronía, cerca, lejos, ciclo) · Stick;
  - Voz;
  - Modo eje;
  - Terminar.
- **Tabla de telemetría por nivel**, con «Descargar JSON» (compartir).
- **Ajuste:** sliders de los 8 parámetros del prototipo más `kAccel` y `accelGate`, con «Copiar valores» y «Valores iniciales». Se guardan en el teléfono.
- **Lecturas del stick por rol:**
  - Hz;
  - bias estimado;
  - inclinación cruda (°);
  - medio rango calibrado;
  - `|a|` en g;
  - si el filtro está corrigiendo o solo usa el giroscopio.

### 5.2 Límite del plano (requisito V5)

1. **Límite del modelo:** `raw` y `pos` siempre están en [−6, 6] (§4.2), con test incluido.
2. **Límite del dibujo:** el área dibujable es `[−6 − m, 6 + m]`, con `m` = el radio del punto más grande más la estela. El borde de ±6 se dibuja como un **marco visible**. Ningún punto ni estela se pinta fuera del lienzo (`clipRect`).
3. **Punto en el borde:** si la inclinación cruda supera el rango calibrado, el punto queda pegado al marco y aparece una **marca en el borde** (un arco corto del color del rol) que indica hacia dónde se salió. Así se distingue de un punto que de verdad está en ±6.
4. **Indicador «% del tiempo en el borde»** por rol, en el banco. Si pasa del 15 %, conviene recalibrar o subir el rango por defecto.
5. **Sin datos:** si un stick deja de enviar más de 1 s, su punto se atenúa y queda en su última posición. No salta al centro ni desaparece.

### 5.3 Asistente de ejes por stick

Se hace una vez por stick y se guarda con su MAC:
1. «Deja el stick en tu posición de descanso» (1 s) → `g₀`.
2. «Inclínalo hacia arriba» → `e_arriba`.
3. «Inclínalo hacia tu derecha» → `e_derecha`.

Se valida que los dos ejes estén separados al menos 60°. El asistente se abre desde el banco y, si el stick no tiene ejes guardados, desde el paso 4 de la preparación.

## 6. Arquitectura de carpetas

```
lib/balancin_v2/
  core/                         ← Dart puro (Claude), sin Flutter
    params.dart                 (P_DEF, §4.5; serialización)
    levels.dart                 (catálogo de 7 niveles; solo el 1 habilitado)
    tilt/tilt_reader.dart       (fusión §4.1 + bias)
    tilt/axis_map.dart          (g₀, e_arriba, e_derecha; asistente)
    stick_state.dart            (§4.2: pos, speed, active, historial, rhythm)
    calibration.dart            (§4.3)
    sync_engine.dart            (§4.4: d, sincronía, progreso, guía, pausas, cierre)
    lead_lag.dart               (correlación cruzada)
    sources/synthetic_source.dart  (sync, cerca, lejos, ciclo; port de synthDrive)
    audio/layers.dart           (§4.6 como objetivos de frecuencia y ganancia por tick)
    audio/families_v2.dart      (recetas para SynthRenderer)
    light/light_model.dart      (§4.7)
    telemetry/level_telemetry.dart, report.dart, session_record.dart
  platform/                     ← Antigravity
    audio_engine_v2.dart        (voces continuas, cadena de mezcla, notas)
    voice_prompts.dart          (flutter_tts)
    progress_store.dart         (progreso, sesiones, ejes por MAC, parámetros)
  screens/                      ← Antigravity
    home_v2.dart, mode_screen.dart, levels_screen.dart, pre_level_screen.dart,
    play_eje_screen.dart, final_screen.dart, bench_screen.dart, axis_wizard.dart
  widgets/
    sync_plane.dart             (plano limitado §5.2; se usa en el banco y en el recuerdo)
    two_halves_light.dart, level_pictogram.dart, song_bar.dart
test/balancin_v2/               ← Claude
```

El motor es **determinista**: `tick(now, adult, child)` devuelve el estado y los comandos de sonido. El reloj se inyecta (`AppClock`).

## 7. Fases

### Fase 0 · Preparación ✅ (17-10-2026)
- Rama `mecanica-v2`, prototipo en `reference/mecanica-v2/` y este plan.
- Pendiente del usuario: decidir si se suben a GitHub `balancin` y `mecanica-v2`.

### Fase 1 · Núcleo de sincronía en Dart puro (Claude) ✅ (17-10-2026)
- `params`, `levels`, `stick_state`, `calibration`, `sync_engine`, `lead_lag`, `synthetic_source`, `light_model` y telemetría.
- **Tests de paridad con el prototipo:** se ejecuta el JS del prototipo con Node sobre escenarios sintéticos (sync, cerca, lejos, ciclo, pausa de 4 s, quietud de 31 s) y se comparan `d`, `inSync`, `prog`, el momento del cambio de guía y del nivel logrado, y el JSON, con tolerancia de 1e-6.
- **Tests de límite:** cualquier entrada (±1000°, NaN, saltos) deja `pos` en [−6, 6].
- **Hecho cuando:** `flutter test` está en verde.

### Fase 2 · Inclinación desde el MPU6050 (Claude) ✅ en simulación (17-10-2026) · falta la traza real
- `tilt_reader` y `axis_map`.
- Tests con trazas sintéticas:
  - rotación pura de 30° → 30° ± 1°;
  - sacudida de 3 g sin rotación → menos de 3° de error;
  - bias de 41,6 °/s → sin deriva tras la calibración;
  - montaje del sensor rotado 90° → mismos ángulos después del asistente.
- **Grabador de trazas:** el banco guarda las líneas `v2` crudas en un archivo, para convertir pruebas reales en tests.
- **Hecho cuando:** los tests están en verde y una traza real de cada stick da ángulos coherentes.

### Fase 3 · Audio v2 (Claude: recetas y capas · Antigravity: motor)
- Familias v2 en `SynthRenderer`, `layers.dart` (objetivos por tick) y `audio_engine_v2` con voces continuas, cadena de mezcla y `voice_prompts`.
- Pantalla de prueba: sliders `p.y`, `c.y` y `d` → oír la voz del adulto, el batido y la quinta.
- **Hecho cuando:**
  - en el teléfono la ondulación se oye clara a `d` alto y desaparece al entrar en tolerancia;
  - no hay zipper ni crujidos;
  - la latencia es imperceptible.

### Fase 4 · Banco de prueba (Antigravity, prompt de Claude)
- Todo lo de §5, con fuente Dedo y Sintética.
- **Hecho cuando:**
  - en el teléfono se comporta como `index.html#banco&lv=1&demo=cycle`;
  - el modo Libre funciona;
  - el punto nunca sale del plano (prueba: arrastrar el dedo fuera del panel e inclinar el stick a 90°).

### Fase 5 · Sticks reales en el banco (Antigravity + Claude)
- Fuente «Stick» por rol con `TiltReader`, asistente de ejes y lecturas del stick (§5.1).
- Ajuste con los dos sticks: `alpha`, `onSpeed`, `kAccel` y rangos por defecto. Los valores validados pasan a ser los de fábrica.
- **Hecho cuando:**
  - los dos sticks mueven sus puntos de forma estable;
  - un gesto pequeño del adulto sentado recorre el plano igual que uno amplio del niño (tras calibrar);
  - en reposo el punto no deriva en 2 minutos;
  - funcionan 10 minutos sin desconexiones.

### Fase 6 · Flujo de usuario (Antigravity)
- Preparación (reutilizada), inicio v2 (Jugar, Sesiones pasadas, Idea para hoy, Repasar la preparación, Herramientas del equipo), modo, niveles (2–7 «Próximamente»), pantalla del nivel e inserción con iris.
- Juego solo con luz, que incluye la calibración.
- Final:
  - título según el resultado;
  - duración y porcentaje en sincronía;
  - barra de la canción;
  - recuerdo como imagen;
  - texto de quién guió;
  - «Escuchar la canción» (Niveles) o «Jugar otra vez» (Libre).
- Pérdida de stick y cierre por 30 s de quietud.
- Se elimina de la navegación lo de v1.
- **Hecho cuando:** una instalación limpia llega, con los dos sticks, de la preparación al final del nivel 1 sin tocar el banco.

### Fase 7 · Validación del nivel 1 y Libre, y entregable 2.0.0-beta
- Lista de §8 en el teléfono con los dos sticks y con una díada real.
- APK `balancin-2.0.0-beta.apk` y actualización de `entregable/LEEME.md`.

## 8. Criterios de aceptación: nivel 1 y Libre

| # | Prueba | Resultado esperado | Dónde |
|---|---|---|---|
| 1 | Los dos quietos | Sin voz del adulto ni tono de relación, sin progreso; las dos mitades de luz tenues (0,14) | Test + banco |
| 2 | Solo el adulto se mueve | Suena la voz del adulto y sigue su altura; no hay tono de relación; el progreso no avanza | Test + banco |
| 3 | Solo el niño se mueve | Suenan notas de marimba; el progreso no avanza | Test + banco |
| 4 | Los dos suben y bajan juntos (`d < 1,2`) | «En sincronía»; desaparece la ondulación y aparece la quinta; la luz se funde a oliva y late; el progreso avanza | Test + teléfono |
| 5 | Mismo movimiento pero desfasado (uno arriba, el otro abajo) | `d` alto; ondulación de hasta 4 Hz; el progreso no avanza | Test + teléfono |
| 6 | Mover solo en horizontal en el nivel 1 | `d` no cambia | Test |
| 7 | 4 s acumulados en sincronía | La voz dice «Ahora guía el niño», una sola vez | Test + teléfono |
| 8 | 8 s acumulados | Frase do4–re4–mi4–sol4 y destello; el nivel queda «Lograda» y se va al final | Test + teléfono |
| 9 | Quietos 3 s a mitad del nivel | Se cuenta una pausa y el progreso baja 0,5 por segundo; al retomar se cuenta una reanudación | Test |
| 10 | Quietos 30 s | La sesión se cierra sola y va al final | Test + teléfono |
| 11 | Sin calibración: adulto con gestos de ±15° | Llega a ±3 en el plano. Tras calibrar llega a ±6, igual que el niño con ±40° | Teléfono |
| 12 | Stick a 90° o arrastre fuera del panel | El punto queda en el borde con la marca de salida; nunca sale del plano | Test + teléfono |
| 13 | Sacudida fuerte sin inclinar | El punto se mueve menos de 0,5 en el plano | Test + teléfono |
| 14 | Libre: juntos, espejo o sube y baja | `d` baja en los tres casos; «Sonaron juntos» en el final | Test + teléfono |
| 15 | Se apaga un stick a mitad de juego | Pantalla de pérdida; al reconectar sigue la misma sesión con su telemetría | Teléfono |
| 16 | Gesto → sonido | Sin retraso perceptible | Teléfono |
| 17 | JSON del nivel 1 | Mismas claves que el prototipo; valores coherentes con la tabla del banco | Test |
| 18 | Díada real sin explicación previa (solo la voz) | Logran el nivel 1 en menos de 2 minutos | Fase 7 |

## 9. Riesgos

| Riesgo | Mitigación |
|---|---|
| Montaje del MPU distinto en cada stick | Asistente de ejes por MAC (§5.3). |
| La inclinación salta con gestos bruscos | Filtro complementario con compuerta del acelerómetro; criterio 13. |
| Zipper en las voces continuas de SoLoud | Actualización más frecuente o plan B `flutter_pcm_sound`. |
| La voz del sistema (TTS) varía según el teléfono | Es un marcador; v3 usa audios grabados. Se puede desactivar. |
| El niño suena solo (cambio respecto de v1) | Es decisión del prototipo (V1). Se observa en la prueba con díadas. |

## 10. Decisiones del usuario (antes preguntas abiertas)

1. **Montaje y forma de sostener el stick.** El stick es la ESP32 con el MPU6050 pegado. Se sostiene **vertical, hacia arriba**, en la mano. Mover la muñeca hacia los lados mueve el **eje X del sensor**. Consecuencias:
   - en reposo la gravedad cae sobre el eje largo de la placa; el neutro `g₀` lo mide la calibración;
   - `e_derecha` por defecto es el **eje X** del sensor (inclinar hacia los lados → X del plano);
   - `e_arriba` por defecto es el eje restante, perpendicular a X y a `g₀`: **inclinar hacia adelante o atrás → Y del plano** («subir y bajar» en el nivel 1);
   - el signo de cada eje se confirma en la fase 5 con el asistente de ejes (§5.3). Si los dos sticks tienen el mismo montaje, basta con los valores por defecto.
2. **Al lograr el nivel 1 se va al final**, con:
   - el dibujo de lo que hicieron los sticks;
   - la barra de la canción con la parte nueva marcada;
   - «Escuchar la canción», «Guardar el recuerdo» y el texto de quién guió.
3. **Sin interruptor «Sesión de estudio».** El historial se guarda siempre, solo en el teléfono. El JSON de telemetría se exporta desde el banco.

## 11. Registro

| Fecha | Fase | Nota |
|---|---|---|
| 17-10-2026 | 0 | Plan v2. Rama `mecanica-v2` desde `balancin` (`6d26705`). Prototipo copiado en `reference/mecanica-v2/`. Decisiones V1–V6. |
| 17-10-2026 | 0 | Respuestas del usuario: stick vertical, muñeca hacia los lados = X del sensor; al lograr el nivel 1 se va al final con el dibujo y la canción; historial siempre guardado sin interruptor de estudio (§10). |
| 17-10-2026 | 1 | ✅ Núcleo en `lib/balancin_v2/core/`: `params`, `levels`, `stick_state` (límite ±6 con desborde y % en el borde), `calibration`, `lead_lag`, `sync_engine` (temporizadores internos, cierre al lograr el último nivel habilitado), `synthetic_source`, `light_model`, `telemetry`. Paridad: `tool/parity/gen_golden.mjs` ejecuta en Node el código del prototipo extraído por líneas y genera `test/balancin_v2/golden/proto_scenarios.json` (14 escenarios, niveles 1–7 y Libre); `parity_test.dart` los reproduce con tolerancia 1e-6 (verificado con una mutación de 0,5 → 0,51 que sí falla). `core_test.dart`: 22 pruebas (límite del plano, calibración, nivel 1, Libre, pausa y cierre, parámetros, luz, registro). Suite completa: 125/125 en verde, `flutter analyze` sin problemas. Diferencia deliberada: un nivel ya logrado no se repite en `levelsDone`. |
| 17-10-2026 | 2 | ✅ `lib/balancin_v2/core/tilt/`: `vec3`, `axis_map` (mapa por defecto §10.1: derecha = X, vertical = ±Y según la primera lectura; asistente de 3 pasos con validación de 15° y 60°; JSON), `tilt_reader` (filtro complementario con Rodrigues, compuerta de |a|, bias y |a| de reposo solo con quietud real: giro con desviación < 3 °/s Y gravedad estable ±2°, para no confundir un giro lento con el bias; solo acelerómetro hasta calibrar; `dt` del reloj del ESP con vuelta y tope de 0,1 s), `imu_trace` (formato de trazas). `tilt_reader_test.dart`: 19 pruebas con un simulador de MPU6050 (bias 41,6 °/s, escala 1,08 g, ruido, vuelta de reloj): sin deriva en 2 min, 30° ±1°, giro de 200 °/s con error < 3°, sacudida de 3 g < 3°, balanceo de 0,8 Hz < 2°, huecos de 300 ms, montaje distinto, asistente. Mutación (signo del giro) detectada. Suite: 145/145. **Pendiente:** grabar una traza real de cada stick (con el banco, fases 4–5) y confirmar que la vertical del stick es el eje Y. |
