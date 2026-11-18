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

### Regla del guía: qué tan obligatoria es la partitura

Hay dos lecturas y no coinciden:
- **Figma y los textos** («El adulto elige si van hacia arriba o hacia abajo», «Cada nivel es una melodía breve y escondida»): **el guía elige** la dirección; lo escondido es la melodía.
- **El README del paquete**: «la partitura del nivel (`NivelEco.pasos`) dice qué tiene que pasar»; la dirección de cada paso viene escrita.

**Propuesta para el sábado:** el **tipo** de paso es obligatorio (en el nivel 4, el que sigue va al borde contrario); la **dirección la elige el guía** entre las de su nivel, y la que trae la partitura solo sirve para la simulación. Así el texto que leen los usuarios es cierto. → **Confirmar con Joaquín** (§6). Cambiarlo después toca una sola función del motor.

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

### Jueves 19 · las pantallas de Joaquín andando en el teléfono
- [ ] Copiar `reference/epu_eco_flutter/lib/epu` a `lib/epu`, sus fuentes y sonidos a `assets/`, y sumar `audioplayers`. *Listo cuando* `flutter analyze` queda limpio y las pruebas de Joaquín (`ilustraciones_test.dart`) pasan junto con las nuestras.
- [ ] Abrir la app en `EpuEcoApp`, con el banco detrás del gesto escondido. *Listo cuando* el flujo completo corre en el moto g34 con la simulación, y las pantallas se ven como el canvas (revisar desenfoque de las luces y alto de pantalla).
- [ ] **`FuenteSticksBle`**: conectar, calibrar y `lecturas` con el stick P2 real. *Listo cuando* «Conecta los dos sticks» deja fija la luz del adulto con el tono, y mover el stick cambia `lateral`/`frontal` con el signo correcto.
- [ ] **Vuelco a borde:** umbral 20° con margen para que no salte. *Listo cuando* el borde que marca la app coincide con el del stick en las 4 direcciones.

### Viernes 20 · el juego de verdad
- [ ] **`MotorEco`** niveles 1 a 4 en Dart puro, con pruebas: quién guía, regla del paso (iguales, quietos, opuestos), acierto con < 1 s y 0,3 s, trozo, melodía final y `alTerminar`. *Listo cuando* las pruebas juegan los 4 niveles completos con lecturas inventadas, incluidos los casos de error (el que sigue va al borde equivocado, se suelta antes de tiempo).
- [ ] Juego con el stick P2 + el segundo stick o, si no está, el niño simulado con botones en pantalla. *Listo cuando* el nivel 1 se completa de punta a punta en el teléfono y el trozo suena sin retraso notorio.
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

1. **Partitura obligatoria o guía libre** (§1). Pregunta para Joaquín, sin términos técnicos: *«En cada nivel, ¿el que guía elige libremente hacia dónde ir, o hay un orden escondido (por ejemplo, en Madera: arriba, abajo, abajo, arriba) que tienen que adivinar para que suene la melodía? Si es libre, ¿cualquier dirección vale o solo algunas (en Madera, solo arriba o abajo)?»*
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
