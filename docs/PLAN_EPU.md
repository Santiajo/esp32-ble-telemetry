# Epu · plan de integración (semana del 16 al 21-11-2026)

Fuentes: `docs/Epu · Plan de la semana.xlsx` (calendario de Joaquín), `reference/epu_prototipo/` (canvas «Epu · 11a Flujo completo», flujo **Eco**), `reference/epu_sonidos/`, Figma «Epu · Vistas + Kit» (`ZWBOXljxDWPIIAdmi8ANHD`, página `701:9413`) y Jira EPU.

**Meta:** el sábado 21-11 una díada juega los niveles 1 a 4 de Eco con los dos sticks nuevos, sin ayuda.

## 1. Qué cambia respecto de la app actual (v2 «Balancín»)

| Tema | Hoy en `lib/balancin_v2` | Epu · Eco |
|---|---|---|
| Placa | ESP32 DevKit + MPU6050, `ESP32-BAL-A/B` | **XIAO ESP32-C3 + ICM-42688-P**, `Epu-Adulto` / `Epu-Niño` |
| Mecánica | Sincronía continua (punto, zonas, trazo) y audio en tres capas | **Por pasos**: el guía vuelca su stick, se enciende el borde del que sigue, el que sigue responde; si aciertan **suena un trozo** de la melodía. Sin sonido de error. Al final suena la melodía completa |
| Lectura | Inclinación continua en el plano | **Dirección discreta**: adelante, atrás, izquierda, derecha o centro (umbral ~20° con margen) |
| Acierto | % de tiempo en sincronía | Llegan con **< 1 s** de diferencia y se quedan **0,3 s** |
| Sonido | Síntesis en vivo (SoLoud) | **WAV precargados**: `por_nivel/nivelN_*_trozoM.wav` y `*_completa.wav` |
| Flujo | Inicio → niveles → antes → inserción → juego → final | Conectar → Elegir nivel → Antes → Quién guía → Calibrar → Juego → Recuerdo |

### Los 7 niveles (del prototipo)

| N | Nombre · instrumento | Regla | Guía | Trozos | Para el sábado |
|---|---|---|---|---|---|
| 1 | Madera · marimba | **Juntos**: mismo borde, arriba o abajo | adulto | 4 | sí |
| 2 | Viento · flauta | **Quietos**: mismo borde y se quedan hasta que suene | niño | 4 | sí |
| 3 | Cuerda · guitarra | **Lados contrarios**: izquierda ↔ derecha | niño | 4 | sí |
| 4 | Caña · clarinete | **Sube y baja**: uno arriba, el otro abajo, y cambian | adulto | 5 | sí |
| 5 | Metal · handpan | **Giro**: círculo hacia el mismo lado | niño | 5 | después |
| 6 | Voces · coro | **Eco por turnos**: va al borde, vuelve; el otro repite | adulto | 6 | después |
| 7 | Teclas · piano | **Mezcla**; el último trozo lo elige el niño | adulto | 6 | después |

### Regla del guía (confirmada en Figma, nota «Eco · melodías para descubrir juntos»)

«Cada nivel es una melodía breve y escondida.» Lo escondido es la **melodía**, no los movimientos: **el guía elige libre** dentro de lo que permite su nivel (nivel 1: arriba o abajo; nivel 3: izquierda o derecha…), el que sigue responde según la regla y cada acierto destapa el trozo siguiente. La lista de pasos del prototipo (`MEL[].steps` en `EcoJuego`) es solo la simulación. La tabla de Joaquín puede afinar los detalles, pero el motor no la espera.

## 2. Arquitectura: Eco dentro de esta app

El calendario dice «crear el proyecto Flutter» desde cero. **Se decide no hacerlo** (18-11): Eco vive en un módulo nuevo `lib/epu/` dentro de esta app. **Los usuarios no notan la diferencia**: lo que ven es lo de Figma, y lo que se reutiliza está por debajo. Solo cambia el nombre de la app instalada si no se le pone «Epu» (EPU-15) y que el banco de pruebas sigue escondido. Se reutiliza lo que ya está probado con sticks reales:

- BLE con dos sticks, permisos de Android 12+ y reconexión (`lib/balancin/platform/ble_stick_link.dart`).
- Lectura del protocolo `v2` y filtro de inclinación (`lib/balancin_v2/core/tilt/`).
- Calibración de usuarios con revisión de ejes (`calibrate_sticks_screen.dart`, `StickCheck`).
- Motor de audio SoLoud (para tocar WAV precargados).

El firmware nuevo manda **la misma línea `v2`** con la misma escala, así la app lee la placa nueva sin cambios. El código de Balancín v2 queda en el banco de pruebas y no se borra.

## 3. Plan por día

Cada tarea dice cuándo está lista. Marca `[x]` al verificar.

### Miércoles 18 (hoy) · placa nueva
- [ ] **Respaldo:** tests en verde (301/301 el 18-11), commit y push de `niveles-2-3` (5 commits y 38 archivos solo locales, incluyen EPU-7 y EPU-8).
- [x] **Firmware 1** (`firmware/epu_stick/main.py`, por **SPI**): en el stick P2, `WHO_AM_I = 0x47`, 100 lecturas por segundo, grados en consola y `|g|` 1,016 en reposo. (EPU-11, ver §7)
- [x] La app acepta `Epu-Adulto`, `Epu-Niño` y `Epu-Nino` (`lib/core/ble/ble_constants.dart`). 2.0.0-dev.22+25.
- [x] **Firmware 2:** el banco encuentra `Epu-Adulto` («Recomendado»), conecta y recibe 100 líneas `v2` por segundo sin cortes (§7). (EPU-5, EPU-6)
- [x] Banco: paneles de los sticks con espacio y pantalla con desplazamiento (antes se escondía el estado y no se podía tocar ⋮); copia local de cada traza.
- [ ] Repetir la medición en movimiento y con los dos sticks (falta el segundo stick con `STICK_ROLE = 'B'`).
- [ ] **Ejes:** con la app actual (banco, «Chequeo de sticks») se graba un chequeo de la placa nueva y se ajustan `expectedForward` y `expectedRight` si el sensor quedó montado girado.

### Jueves 19 · lectura y motor
- [ ] App acepta `Epu-Adulto` / `Epu-Niño` (además de los nombres viejos) en `lib/core/ble/ble_constants.dart`. (EPU-5)
- [ ] **Vuelco** (`lib/epu/core/direction.dart`): inclinación → adelante/atrás/izquierda/derecha/centro, umbral 20° con margen para no saltar. *Listo cuando* la dirección en pantalla coincide con la del stick.
- [ ] **Motor Eco** en Dart puro (`lib/epu/core/eco_engine.dart`): niveles 1 a 4 como datos, quién guía, regla del que sigue, acierto con 1 s y 0,3 s. *Listo cuando* los tests juegan el nivel 1 completo con valores de prueba.

### Viernes 20 · sonido y pantallas
- [ ] **Sonido:** copiar `por_nivel/` niveles 1 a 4 a `assets/epu/sonidos/`, precargarlos al entrar al nivel; trozo al acertar y melodía completa al final. *Listo cuando* el trozo suena sin retraso notorio.
- [ ] **Pantallas mínimas** con colores y tipos de Figma: Elegir nivel → Antes → Quién guía → Calibrar → Juego (fondo oscuro, luces, borde del que sigue, verde al acertar) → Recuerdo. *Listo cuando* se juega un nivel sin tocar código. (EPU-14, parte 1)
- [ ] APK instalado en el teléfono de la prueba.

### Sábado 21 · prueba
- [ ] Dos sticks conectados y calibrados a la vez.
- [ ] Prueba con una díada, niveles 1 a 4; ajustar umbral, 1 s y 0,3 s en Ajuste.
- [ ] Colchón: arreglos e instalar la versión de la entrega.

**Si algo se atrasa** (del calendario): un stick y botones en pantalla para el segundo; solo niveles 1 y 2; Quién guía y Recuerdo como pantallas solo de texto; tonos de la pentatónica si faltara un WAV.

## 4. Después de la entrega

Niveles 5 a 7 (giro, eco por turnos, mezcla) · onboarding de 4 pasos con stepper, bienvenida con logo y Home con sesiones pasadas (EPU-14, parte 2) · pérdida de stick y reconexión · animaciones y manos 3D · ajuste fino contra Figma · LED del stick como luz del guía · batería en la app · icono y nombre «Epu» (EPU-15).

## 5. Jira

| Ticket | Qué lo cierra |
|---|---|
| EPU-11 Probar nueva placa | Firmware 1 y 2 del miércoles |
| EPU-5 Nombres BLE | Firmware 2 + nombres en la app |
| EPU-6 No aparecen en Bluetooth | Los sticks usan BLE y la app conecta directo: no aparecen en Ajustes → Bluetooth para vincular, y no hace falta. Se cierra cuando nRF Connect y la app los ven. Confirmar con el equipo |
| EPU-14 Nuevo flujo | Parte 1 el viernes; parte 2 después |
| EPU-15 Icono | Después de la entrega |
| EPU-7, EPU-8 | Ya hechos; quedan respaldados con el push del miércoles |

## 6. Dudas abiertas

1. **Paquete Flutter** con colores, textos y animaciones: pedido a Joaquín. Mientras tanto se toman de Figma (página «Kit de componentes»: Colores, Tipografía, Espaciados, Radios).
2. **Nombre con «ñ»:** `Epu-Niño` funciona en BLE; si algún teléfono lo muestra mal, el firmware usa `Epu-Nino` (la app ya acepta los dos).
3. **Segundo stick:** cargarle el mismo firmware con `STICK_ROLE = 'B'` y repetir el diagnóstico.

## 7. Placa nueva frente al MPU6050 (18-11-2026)

**Stick P2** (XIAO ESP32-C3 + ICM-42688-P por SPI: CS GPIO5, SCK GPIO4, MISO GPIO6, MOSI GPIO10, LED GPIO21; MicroPython 1.29). Su firmware de prueba («P2 - Adulto», Bluefruit) quedó respaldado en `firmware/epu_stick/respaldo_p2/`.

**MPU6050 (sticks A y B):** sale de las trazas de `test/balancin_v2/golden/` con `tools/trace_stats.py`, tomando su segundo más quieto.

| Medida | MPU6050 (A / B) | ICM-42688-P (P2) | Qué significa |
|---|---|---|---|
| \|g\| quieto (debe ser 1,000) | 1,14 / 1,16 | **1,016** | El MPU6050 medía ~15 % de más; afecta los grados de inclinación |
| Sesgo del giroscopio quieto | hasta 6 °/s / **41 °/s** en un eje | **< 0,7 °/s** | El stick B «giraba» solo a 41 °/s; la app lo compensaba calibrando |
| Ruido del acelerómetro | 8–14 mg (en la mano) | **0,6–1,3 mg** (en la mesa) | 10 veces menos, aunque la condición no es la misma |
| Ruido del giroscopio | 0,6–1,3 °/s (en la mano) | **0,02–0,03 °/s** (en la mesa) | ídem |
| Ritmo del sensor | 100/s marcado por el ESP32 | **100,0/s** marcado por el propio sensor (aviso de dato listo) | Sin muestras repetidas ni saltadas |
| Lectura | I2C | SPI: 0,5 ms (1 MHz), 0,34 ms (8 MHz) | 1 MHz alcanza: lo demás es el intérprete |

**Enlace Bluetooth** (moto g34, app 2.0.0-dev.22, stick quieto en la mesa, 60 s: `test/balancin_v2/golden/epu_p2_reposo_ble.trace`):

| Medida | MPU6050 A, chequeo bueno (05-11) | MPU6050 A, con cortes (05-11) | P2 (18-11) |
|---|---|---|---|
| Datos por segundo | 100,0 | 76,6 | **100,2** |
| Huecos > 30 ms | 0 | 16 (hasta 1 s) | **0** |
| Retraso relativo mediano / p95 | 8 / 16 ms | 7 / 18 ms | 22 / 40 ms |
| Cortes > 150 ms al llegar | 0 | 16 | **0** |

Se conecta a la primera (MTU 185, intervalo 15 ms). El retraso un poco mayor es esperable: llegan 3 muestras por paquete, o sea uno cada 30 ms. Sigue muy por debajo de lo que se nota.

**Falta:** repetir con el stick **en movimiento y en la mano**, y con **los dos sticks a la vez**, que es cuando aparecían los cortes. Para eso hace falta el segundo stick.

**Cómo sacar una traza sin compartirla:** desde la dev.22, el banco guarda una copia de cada traza en `Android/data/cl.balancin.prototipo/files/registros/`. Se baja con `adb pull` (en Git Bash, con `MSYS_NO_PATHCONV=1`) y se mide con `python tools/trace_stats.py <traza>`.

**Compilar el APK en este PC:** si Gradle falla con «Unable to establish loopback connection», definir `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\tmpj`.
