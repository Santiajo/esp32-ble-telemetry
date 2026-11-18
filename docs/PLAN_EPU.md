# Epu · plan de integración (semana del 16 al 21-11-2026)

Fuentes: `docs/Epu · Plan de la semana.xlsx` (calendario de Joaquín), **`reference/epu_eco_flutter/`** (paquete Flutter de Joaquín, 18-11), `reference/epu_prototipo/` (canvas «Epu · 11a Flujo completo», flujo **Eco**), `reference/epu_sonidos/`, Figma «Epu · Vistas + Kit» (`ZWBOXljxDWPIIAdmi8ANHD`, página `701:9413`) y Jira EPU.

**Meta:** el sábado 21-11 una díada juega los niveles 1 a 4 de Eco con los dos sticks nuevos, sin ayuda.

## 1. Qué cambia respecto de la app actual (v2 «Balancín»)

| Tema | Hoy en `lib/balancin_v2` | Epu · Eco |
|---|---|---|
| Placa | ESP32 DevKit + MPU6050, `ESP32-BAL-A/B` | **XIAO ESP32-C3 + ICM-42688-P**, `Epu-Adulto` / `Epu-Niño` |
| Mecánica | Sincronía continua (punto, zonas, trazo) y audio en tres capas | **Por pasos**: el guía vuelca su stick, se enciende el borde del que sigue, el que sigue responde; si aciertan **suena un trozo** de la melodía. Sin sonido de error. Al final suena la melodía completa |
| Lectura | Inclinación continua en el plano | **Dirección discreta**: adelante, atrás, izquierda, derecha o centro (umbral ~20° con margen) |
| Acierto | % de tiempo en sincronía | Llegan con **< 1 s** de diferencia y se quedan **0,3 s** |
| Sonido | Síntesis en vivo (SoLoud) | **WAV precargados**, uno por trozo y la melodía completa |
| Flujo | Inicio → niveles → antes → inserción → juego → final | Inicio → preparación (4 pasos) → Bienvenida → Home → Elegir nivel → Antes → Quién guía → Calibrar → Juego → Recuerdo (+ Pérdida de stick) |

### Los 7 niveles

| N | Nombre · instrumento | Regla | Guía | Partitura (`NivelEco.pasos`) | Para el sábado |
|---|---|---|---|---|---|
| 1 | Madera · marimba | **Juntos**: mismo borde, arriba o abajo | adulto | `S:F S:B S:B S:F` | sí |
| 2 | Viento · flauta | **Quietos**: mismo borde y se quedan hasta que suene | niño | `H:F H:R H:L H:B` | sí |
| 3 | Cuerda · guitarra | **Lados contrarios**: izquierda ↔ derecha | niño | `O:L O:R O:R O:L` | sí |
| 4 | Caña · clarinete | **Sube y baja**: uno arriba, el otro abajo, y cambian | adulto | `O:F O:B O:F O:B O:F` | sí |
| 5 | Metal · handpan | **Giro**: círculo hacia el mismo lado | niño | `G:+ G:+ G:- G:+ G:-` | después |
| 6 | Voces · coro | **Eco por turnos**: va al borde, vuelve; el otro repite | adulto | `E:F E:L E:B E:R E:L E:F` | después |
| 7 | Teclas · piano | **Mezcla**; el último trozo lo elige el niño | adulto | `S:F O:R G:+ O:B E:L Q:L` | después |

Tipos: `S` iguales, `O` opuestos, `H` quietos, `G` giro, `E` eco por turnos, `Q` iguales guiando el niño.

### Regla del guía: libre (confirmado por el equipo, 18-11)

**No hay un orden escondido: el guía elige libremente.** Lo escondido es la melodía, que se destapa trozo a trozo. El motor:
- toma de la partitura solo el **tipo** de paso (`S`, `O`, `H`…) y **qué bordes valen** en el nivel: nivel 1 arriba/abajo, nivel 2 los cuatro, nivel 3 izquierda/derecha, nivel 4 arriba/abajo. Coincide con lo que dicen los textos;
- deja que el guía elija cualquiera de esos bordes;
- enciende para el que sigue el borde que le toca según la regla (el mismo, o el contrario);
- con cada acierto toca el **siguiente** trozo, en orden;
- usa la dirección escrita en `NivelEco.pasos` solo en la simulación de Joaquín.

## 2. Arquitectura: las pantallas de Joaquín sobre nuestros sticks

El calendario dice «crear el proyecto Flutter» desde cero. **Se decide no hacerlo** (18-11). **Los usuarios no notan la diferencia**: ven lo de Figma, y lo reutilizado está por debajo.

El paquete `reference/epu_eco_flutter` (5 986 líneas, 14 pantallas) trae **toda la parte visible ya hecha**:
- las 14 pantallas con sus animaciones, copiadas valor por valor del prototipo;
- colores, textos y la fuente Nunito;
- los 7 niveles como datos;
- los 42 WAV (el mismo audio que `epu_sonidos/por_nivel`) con precarga.

Está pensado para enchufarle los sticks en **dos puntos**, y eso es lo que nos toca:

| Pieza | Qué hace | De dónde sale |
|---|---|---|
| `FuenteSticksBle` implementa `FuenteSticks` | `conectar()` (un evento por stick), `calibrar()` (cero con el stick derecho y quieto), `reconectar()`, `lecturas` (vuelco lateral/frontal en grados) | `StickHub` y `BleStickLink` (BLE con dos sticks, permisos, reconexión) + el lector de inclinación de `lib/balancin_v2/core/tilt/`, ya probados con sticks reales |
| `MotorEco` reemplaza a `SimulacionEco` | Lee `lecturas`, pasa el vuelco a borde (umbral y margen), aplica la regla del paso y mueve `EstadoJuegoEco`: luz del guía late → su luz va al borde → franja para el que sigue → acierto: trozo, verde y luces apagadas. Al final, la melodía y `alTerminar` | Nuevo, en Dart puro con pruebas. La simulación sirve de guion de orden y tiempos |

Además:
- **Entrada:** `main()` abre `EpuEcoApp` con `EpuSticks.fuente = FuenteSticksBle(...)`. El banco de pruebas y la app v2 quedan detrás de un gesto escondido (por ejemplo, mantener pulsado el logo del Home).
- **Permisos:** en «Conceder permisos» se usa nuestro `ble_permissions.dart`. No Molestar (`ACCESS_NOTIFICATION_POLICY`) puede esperar.
- **Pantalla encendida:** `wakelock_plus` ya está en el proyecto.
- **Sonido:** el paquete usa `audioplayers`; lo dejamos tal cual (toca un solo archivo) y medimos el retraso al acertar en el teléfono. Si se nota, se cambia `sonidos.dart` a `flutter_soloud`, que ya tenemos.
- **Calibración:** Joaquín pide un cero «derechos y quietos» de 3 s, más simple que nuestra calibración de rango. Para Eco basta: los ejes de montaje se fijan una vez por stick (en el P2, los de fábrica: vertical = Z), sin el asistente en el flujo de usuarios.
- **Datos de ejemplo:** el paquete arranca en modo demo (niveles 1 y 2 completados, dos sesiones inventadas). Para la prueba se arranca vacío.
- **Ajuste en vivo** del umbral, la ventana de 1 s y los 0,3 s: desde el banco o un panel escondido, para afinar el sábado sin recompilar.

## 3. Plan por día

Cada tarea dice cuándo está lista. Marca `[x]` al verificar.

### Miércoles 18 · placa nueva ✔
- [x] **Respaldo:** commit y push de `niveles-2-3` (`5315a9f` dev.21 con EPU-7 y EPU-8, `c61c643` Epu dev.22).
- [x] **Firmware 1** (`firmware/epu_stick/main.py`, por **SPI**): en el stick P2, `WHO_AM_I = 0x47`, 100 lecturas por segundo y `|g|` 1,016 en reposo. (EPU-11, §7)
- [x] La app acepta `Epu-Adulto`, `Epu-Niño` y `Epu-Nino` (`lib/core/ble/ble_constants.dart`). (EPU-5)
- [x] **Firmware 2:** el banco encuentra `Epu-Adulto`, conecta y recibe 100 líneas `v2` por segundo sin cortes (§7). (EPU-5, EPU-6)
- [x] Banco usable en el teléfono y copia local de cada traza.
- [x] Paquete Flutter de Joaquín recibido y revisado (este plan).

### Jueves 19 · las pantallas de Joaquín andando en el teléfono (adelantado al 18-11)
- [x] `lib/epu` = paquete de Joaquín con el arreglo de recorte; sonidos y Nunito en `assets/`; `audioplayers`. 313/313 pruebas (las 12 de Joaquín incluidas).
- [x] La app abre en Epu (`lib/epu_app/epu_root.dart`): la primera vez en «Inicio», después en el Home. Sin datos de ejemplo. **Mantener pulsado el logo del Home abre el banco** con la misma conexión; «Atrás» vuelve a Epu. Nombre de la app: «Epu». 2.1.0-dev.1+26.
- [x] **`FuenteSticksBle`** (`lib/epu_app/fuente_sticks_ble.dart`): «Conceder permisos» pide los de Bluetooth; «Conectar sticks» vincula `Epu-Adulto` con el P2 real; «Calibrar» toma la postura como cero (3 s); `lecturas` da `lateral`/`frontal` 50 veces por segundo. Probado en el moto g34 con el P2.
  - Pruebas con un stick: `--dart-define=EPU_UN_STICK=true` deja al niño conectado y quieto. El APK instalado hoy está compilado así.
  - Registro en `adb logcat`: `--dart-define=EPU_REGISTRO=true` imprime `[EPU]` con las lecturas cada 1 s y el cero.
- [x] **Ejes del stick en la mano** (18-11): el sensor del P2 va de canto (derecho = +Y, derecha = −X, adelante = +Z del sensor). El firmware los rota (`AXES` en `firmware/epu_stick/main.py`) para mandar lo que espera la app: derecho = +Z, derecha = +X, adelante = +Y. Comprobado con la secuencia grabada en la mano (adelante hasta +76°, derecha hasta +84°) y con el stick cargado (derecho: Z ≈ 1 g). El segundo stick, si viene armado igual, usa el mismo `AXES`; si no, el diagnóstico al arrancar lo muestra.
- [x] **Vuelco a borde** (`DetectorBorde` en `lib/epu_app/motor_eco.dart`): entra a 20°, sale bajo 14°, y para cambiar de borde sin pasar por el centro el otro eje tiene que ganar por 5°. En el teléfono, inclinar el P2 adelante marcó el borde de arriba (−26°).

### Viernes 20 · el juego de verdad
- [x] **`MotorEco`** (`lib/epu_app/motor_eco.dart`, adelantado al 18-11), niveles 1 a 4. Mueve el `EstadoJuegoEco` de Joaquín en lugar de su simulación (niveles 5 a 7 siguen simulados). 16 pruebas (`test/epu/motor_eco_test.dart`) juegan los niveles completos y los casos de error.
  1. La luz del guía late.
  2. El guía elige libre entre los bordes de su nivel: tiene que quedarse 0,15 s en el borde.
  3. Se enciende la franja del que sigue: el mismo borde o el contrario.
  4. Si los dos se sostienen juntos 0,3 s (1,4 s en «Quietos»), hay acierto: suena el trozo siguiente, se ve el verde y las luces se apagan 1,5 s.
  5. Para el siguiente trozo, el guía vuelve al centro.
  6. Al final: la melodía completa con un destello por trozo, y pasa al recuerdo.
  - **La ventana de 1 s se usa como gracia:** si el guía se sale de su borde menos de 1 s, no pierde la elección; si se sale más, vuelve a elegir.
  - **Frente a frente** (confirmado el 18-11): la pantalla se lee desde el adulto, así que el adelante y la derecha del niño van al revés. Es un ajuste (`AjustesEco.ninoEnfrente`).
  - La pantalla queda encendida durante el juego (`wakelock_plus`).
- [x] Con un stick, el niño simulado juega solo: si sigue, va a su borde 0,6 s después; si guía, elige uno. Se activa con `EPU_UN_STICK`, igual que en el APK 2.1.0-dev.2 instalado.
- [ ] Juego con el stick P2 y el niño simulado. *Listo cuando* el nivel 1 se completa de punta a punta en el teléfono y el trozo suena sin retraso notorio.
- [ ] Niveles completados guardados en el teléfono (`shared_preferences`) y arranque sin datos de ejemplo.
- [ ] APK 2.1.0 instalado en el teléfono de la prueba.

### Sábado 21 · prueba
- [ ] Dos sticks (P2 + el segundo con `STICK_ROLE = 'B'`) conectados y calibrados a la vez; medir el enlace con los dos en movimiento (§7).
- [ ] Prueba con una díada, niveles 1 a 4; ajustar umbral, 1 s y 0,3 s.
- [ ] Colchón: arreglos e instalar la versión de la entrega.

**Si algo se atrasa** (del calendario): un stick y botones en pantalla para el segundo; solo niveles 1 y 2; la simulación de Joaquín como respaldo visual de la pantalla de juego.

## 4. Después de la entrega

Las pantallas ya existen en el paquete; lo que queda es lógica:
- niveles 5 a 7 en `MotorEco` (giro, eco por turnos, mezcla);
- pérdida de stick en medio del juego (`EpuNavegacion.mostrarPerdida` desde `FuenteSticksBle`);
- sesiones pasadas reales en el Home;
- permiso de No Molestar;
- LED del stick como luz del guía (la app le manda órdenes al stick);
- batería en la app;
- icono y nombre «Epu» (EPU-15). Es barato: el logo ya está en `reference/epu_prototipo/assets/logo-epu.svg` y en `ilustraciones/logo_epu.dart`, y se puede adelantar si sobra tiempo.

## 5. Jira

| Ticket | Qué lo cierra |
|---|---|
| EPU-11 Probar nueva placa | Hecho el 18-11 con un stick (§7); falta repetirlo con los dos sticks |
| EPU-5 Nombres BLE | Hecho: firmware `Epu-Adulto` / `Epu-Niño` y la app los acepta |
| EPU-6 No aparecen en Bluetooth | Los sticks usan BLE y la app conecta directo: no aparecen en Ajustes → Bluetooth para vincular, y no hace falta. La app los encuentra y conecta (18-11). Confirmar con el equipo y cerrar |
| EPU-14 Nuevo flujo | Las pantallas vienen en el paquete; se cierra con `FuenteSticksBle` + `MotorEco` (jueves y viernes) |
| EPU-15 Icono | Después de la entrega, o antes si sobra tiempo |
| EPU-7, EPU-8 | Hechos y en GitHub (`5315a9f`) |

## 6. Dudas abiertas

1. ~~Partitura obligatoria o guía libre~~: **libre**, confirmado el 18-11 (§1).
2. **«Quietos» (nivel 2):** se prueba con **1,4 s** (lo que tarda en llenarse la franja amarilla), en vez de los 0,3 s generales. Ajustable el sábado.
3. **Sonido:** se prueba con `audioplayers`, como viene; si el trozo se oye tarde, se pasa a `flutter_soloud`.
4. **Calibración en cada nivel:** con el ICM-42688-P **no hace falta por el sensor** (ver §8). Se deja la pantalla «Calibren los sticks» porque toma la postura de cada persona como centro; si en la prueba molesta, se acorta a 1 s.
5. **«Stick del padre» / «adulto»:** el diseño usa las dos palabras en la misma pantalla (Preparación 4). Para Joaquín.
6. **Nombre con «ñ»:** `Epu-Niño` funciona en BLE; si algún teléfono lo muestra mal, el firmware usa `Epu-Nino` (la app ya acepta los dos).
7. **Segundo stick:** cargarle el mismo firmware con `STICK_ROLE = 'B'` y repetir el diagnóstico.

## 8. El paquete de Joaquín frente a Figma (18-11-2026)

Se corrió el paquete solo (app aparte `cl.epu.epu_eco`) en el moto g34 y se comparó cada pantalla con su marco de Figma, lado a lado.

- **Textos:** los 90 de las vistas de Figma están en el paquete; 34 se arman con variables («Nivel N de 7 · …», «Marimba · 8 segundos · 4 trozos») y también coinciden.
- **Colores:** los 20 del kit de Figma, idénticos.
- **Pantallas iguales:**
  - Inicio, Permisos, Conecta los sticks (conectando y conectados), Quién usa cada stick;
  - Home, Calibrar;
  - Juego (borde del que sigue, posiciones y desenfoque casi al píxel) y El recuerdo.
- **Error encontrado y corregido** (en la copia de prueba; se aplica al integrar): las manos se salían de su dibujo y los brazos cruzaban el texto en **Elegir nivel**, **Antes del nivel** y **Quién guía**. Un `<svg>` recorta lo que sale de su caja y el `CustomPaint` de Flutter no. Arreglo: `ClipRect` en `LienzoSvg` (`ilustraciones/preparacion.dart`) y en `MiniaturaNivel` (`pantallas/eco_niveles.dart`). Verificado en el teléfono; las 12 pruebas del paquete siguen pasando.
- **Diferencia de Figma, no del paquete:** en «Sin interrupciones» el anillo es punteado en el prototipo y en el paquete (`stroke-dasharray="0 13"`) y continuo en Figma, que no dibuja ese punteado. Se deja punteado.
- **Diferencias esperables:**
  - la barra de estado del teléfono, que Figma no tiene;
  - el teléfono mide 360 dp de ancho y Figma 390, así que todo se ve un poco más chico en proporción.

**Calibración y el ICM-42688-P:**
- Con el MPU6050 la calibración era necesaria: el giroscopio del stick B marcaba 41 °/s quieto y el acelerómetro medía un 15 % de más.
- El ICM marca < 0,7 °/s y \|g\| 1,016, y la inclinación se mide contra la gravedad, así que el sensor no necesita calibración.
- Lo que sí aporta el cero es la **postura**: si alguien sostiene el stick 10° inclinado, sin cero quedaría a mitad de camino del umbral de 20°.

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
