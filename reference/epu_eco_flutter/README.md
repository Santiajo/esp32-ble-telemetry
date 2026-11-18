# Epu · flujo Eco en Flutter

Traducción a Flutter del prototipo **«App completa · Eco»** del canvas «Epu · 11a Flujo completo» (la sección «Eco · melodías para descubrir juntos»). Incluye las 14 pantallas del flujo, todas sus animaciones, los sonidos por nivel y un punto de conexión claro para los sticks.

Los valores (duraciones, retrasos, curvas, colores, tamaños, textos) se copiaron del código del prototipo. En cada archivo hay comentarios que dicen de qué regla CSS o de qué función de JavaScript sale cada cosa.

Reemplaza al paquete anterior `epu_flutter`, que solo traía el kit y tres animaciones.

## Cómo correrlo

```bash
# 1. Crear la carpeta de Android (este paquete solo trae lib/, assets/ y test/)
flutter create --platforms=android --org cl.epu --project-name epu_eco .

# 2. Dependencias
flutter pub get

# 3. Correr en un teléfono Android
flutter run
```

* Requiere Flutter 3.32 o más nuevo (Dart 3.8).
* La fuente Nunito ya viene incluida en `assets/fuentes` (pesos 600, 700, 800 y 900, licencia OFL).
* `flutter test` corre las pruebas que comparan el dibujo y el movimiento de las manos contra el prototipo.

La app abre en modo demostración: los sticks son simulados con los mismos tiempos del prototipo, los niveles 1 y 2 aparecen completados y el Home muestra dos sesiones de ejemplo, igual que en el canvas.

## Estructura

```
lib/
├── main.dart                 arranque (orientación vertical, barras transparentes)
└── epu/
    ├── app.dart              EpuEcoApp: navegación, estado y estilo base
    ├── tema/                 colores y estilos de texto (los del kit de Figma)
    ├── util/                 traducciones CSS → Flutter (curvas, sombras, fotogramas,
    │                         trazados SVG, punteados, degradados elípticos)
    ├── widgets/              piezas comunes (botón Atrás, botón principal, pasos,
    │                         botón con estado, botón Jugar, reloj de animación)
    ├── ilustraciones/        logo, ilustraciones de preparación, manos con stick
    ├── datos/niveles.dart    los 7 niveles: textos, partitura oculta, animaciones
    ├── estado/               nivel elegido, niveles completados, sesiones
    ├── navegacion/rutas.dart las 14 pantallas y cómo se va de una a otra
    ├── audio/sonidos.dart    reproducción de los audios
    ├── juego/                estado de la pantalla de juego, simulación y sticks
    └── pantallas/            una pantalla por archivo
assets/
├── fuentes/                  Nunito
└── sonidos/                  34 trozos + 7 melodías + tono de conexión (WAV)
test/                         pruebas contra los valores del prototipo
```

## Pantallas

| # | Pantalla | Prototipo | Archivo | Lleva a |
|---|---|---|---|---|
| 1 | Inicio | `Main` | `inicio.dart` | Permisos |
| 2 | Activa Bluetooth y No Molestar | `Prep1` | `prep_permisos.dart` | Sin interrupciones |
| 3 | Sin interrupciones | `Prep2` | `prep_sin_avisos.dart` | Conecta los sticks |
| 4 | Conecta los dos sticks | `Prep4` | `prep_conectar.dart` | sola, 1,5 s después de conectar |
| 5 | Quién usa cada stick | `Prep5` | `prep_quien_usa.dart` | Bienvenida |
| 6 | Bienvenida | `Bienvenida` | `bienvenida.dart` | Home, sola a los 2,6 s |
| 7 | Home | `Home` | `home.dart` | Elegir nivel · Recuerdo · Preparación |
| 8 | ¿Qué melodía van a descubrir? | `EcoNiveles` | `eco_niveles.dart` | Antes del nivel |
| 9 | Antes del nivel | `EcoAntes` | `eco_antes.dart` | Quién guía |
| 10 | Quién guía | `EcoGuia` | `eco_guia.dart` | Calibrar |
| 11 | Calibren los sticks | `Calibrar` | `calibrar.dart` | Juego, 1,2 s después de calibrar |
| 12 | Descubrir la melodía | `EcoJuego` | `eco_juego.dart` | Recuerdo, al terminar |
| 13 | La descubrieron juntos | `EcoFinal` | `eco_final.dart` | Siguiente nivel · Elegir nivel |
| 14 | Se perdió un stick | `Perdida` | `perdida.dart` | vuelve a Antes del nivel |

Cada «Atrás» lleva a la misma pantalla que en el prototipo (por ejemplo, el del recuerdo vuelve a elegir nivel, no al juego). El botón «volver» de Android hace lo mismo. En el juego no hay salida, como en el prototipo.

## Animaciones

Todas están en el código con sus valores originales. Resumen:

| Pantalla | Qué se mueve | Valores del prototipo |
|---|---|---|
| Conecta los sticks | luz de cada stick | parpadea cada 250 ms; queda fija al conectar (1,7 s y 2,6 s en la simulación) |
| | botón «Conectando…» | brillo teal que late: 1,4 s ease-in-out infinito |
| | colores del botón | 0,3 s ease |
| Quién usa cada stick | stick del niño | aparece: 0,5 s ease-out, retraso 0,1 s |
| | stick del adulto | sube 46 px y crece de 0,9 a 1: 0,7 s `cubic-bezier(.2,.8,.2,1)`, retraso 0,8 s |
| | se separan | ±66 px: 1 s `cubic-bezier(.4,0,.2,1)`, retraso 1,5 s |
| | etiqueta del adulto | sube 6 px: 0,45 s ease-out, retraso 2,6 s |
| | cortina al tocar «Comenzar» | círculo de 960 px: 0,6 s `cubic-bezier(.65,0,.35,1)`; cambia de pantalla a los 650 ms |
| Bienvenida | logo | aparece ×2,2 → ×3 en el centro (0,1–0,7 s) y baja a su lugar ×3 → ×1 (1,4–2,25 s) |
| | capa de fondo | se desvanece 1,85–2,45 s, ease-in-out |
| Home | botón «Jugar» | 5 manchas de color con ritmos de 9, 10,5, 13, 14 y 10 s, ease-in-out en cada tramo |
| Antes del nivel | manos y sticks | modelo 3D del prototipo (`geo`), fases de la tabla `PH`, pasos de 33 ms que acercan un 22 % |
| | flechas | entran en 0,6 s `cubic-bezier(.2,.7,.3,1)` desde −5 hasta +1,5 unidades; se apagan en 0,25 s |
| | flecha de giro | una vuelta cada 1,68 s, lineal |
| | anillo de «quietos» | late ×0,8 ↔ ×1,25 cada 1 s |
| | «Comenzar» | bloqueado 3 s con barra lineal; después pasa a oscuro en 0,3 s |
| Quién guía | dibujo | entra: 0,5 s `cubic-bezier(.2,.8,.2,1)`, retraso 0,1 s |
| | luz de quien guía | parpadea 1 → 0,35 y su anillo late ×0,8 ↔ ×1,25, cada 1,1 s |
| Calibrar | anillos | ×1 → ×2,8 y 0,9 → 0 de opacidad, 1,3 s ease-out, el segundo con 0,65 s de retraso |
| | luz | parpadea 1 → 0,3 cada 0,7 s |
| | botón | barra lineal de 3 s |
| Juego | luces de los sticks | se mueven en 0,7 s `cubic-bezier(.4,0,.2,1)` (en el giro, tramos de 0,23 s lineales); aparecen y se apagan en 0,4 s |
| | luz de quien guía | late 1 → 0,4 y ×1 → ×0,9 cada 0,9 s |
| | franjas de pista | 0,5 s ease |
| | franja de sostener | crece en 1,4 s lineal, se va en 0,25 s ease |
| | luz verde de acierto | 0,5 s ease |
| Recuerdo | destellos | entran desde ×0,4, 0,5 s ease-out, uno cada 0,15 s |
| | «Escuchar la melodía» | cada destello crece a ×1,35 (0,35 s ease) mientras suena su trozo |
| Pérdida de stick | anillo punteado | 0,35 ↔ 1 de opacidad y ×0,97 ↔ ×1, 1,6 s ease-in-out |
| | botón | brillo del color del stick y luz que parpadea cada 250 ms |

Con «Quitar animaciones» activado en Android, cada pantalla hace lo mismo que el prototipo con `prefers-reduced-motion`.

### Cómo se tradujo

| CSS | Flutter |
|---|---|
| `cubic-bezier(a,b,c,d)` | `Cubic(a, b, c, d)` (la misma curva) |
| `ease`, `ease-in-out`, `ease-out` | `Curves.ease`, `Curves.easeInOut`, `Curves.easeOut` (idénticas) |
| `animation: x 0.5s … 0.8s both` | `tramoCss(...)`: un controlador de retraso + duración con `Interval` |
| `@keyframes` con varios pasos | `Fotogramas` / `latido`: la curva se aplica a cada tramo, como CSS |
| `transition: …` | `AnimatedContainer`, `AnimatedOpacity`, `AnimatedPositioned` con la misma duración y curva |
| `setTimeout` en cadena | un `Reloj` (Ticker) que simula los mismos pasos a partir del tiempo |
| `box-shadow` / `text-shadow` | `sombraCss(...)`: corrige que Flutter y CSS miden distinto el desenfoque |
| `filter: blur(1.5px)` | `ImageFilter.blur(sigmaX: 1.5)` (en CSS ese valor ya es la sigma) |
| `radial-gradient(circle, …)` | `RadialGradient(radius: .7071)`: CSS llega a la esquina y Flutter mide sobre el lado |
| `radial-gradient(ellipse …)` | `RadialGradient` + `EstirarDegradado` |
| SVG en línea | `CustomPainter` con los mismos trazados (`trazadoSvg('M… L… A…')`) |
| `flex: 1; min-height; max-height` + `margin-top: auto` | `ZonaIlustracion` + `ColumnaConBoton` (Flutter reparte el espacio distinto que CSS) |

## Sonidos

`lib/epu/audio/sonidos.dart`, con el paquete `audioplayers`. Son los mismos audios de `epu_sonidos/por_nivel`, grabados con el código del prototipo:

* `tocarTrozo(nivel, i)`: suena cuando aciertan el trozo `i`.
* `tocarMelodia(nivel)`: al terminar el nivel y en «Escuchar la melodía».
* `tonoConexion()`: cuando un stick termina de conectarse.
* `precargarNivel(nivel)`: se llama al entrar a «Antes del nivel» para que no haya retraso al acertar.

No hay sonido de error, como define la mecánica.

## Conexión con los sticks

El prototipo no tiene Bluetooth: simula los tiempos. Las pantallas nunca hablan con el Bluetooth directamente. Pasan por dos piezas:

1. **`FuenteSticks`** (`juego/fuente_sticks.dart`): conectar, calibrar, reconectar y leer el movimiento. Hoy está `FuenteSticksSimulada`, con los tiempos del prototipo. Para la app real hay que escribir una implementación con el BLE de los sticks (XIAO ESP32-C3 + ICM-42688-P) y asignarla en `main()`:
   ```dart
   EpuSticks.fuente = MiFuenteBluetooth();
   ```
2. **`EstadoJuegoEco`** (`juego/estado_juego.dart`): todo lo que se ve en la pantalla de juego (dónde va cada luz, qué borde se enciende, si hay que sostener, el verde de acierto, quién late). La pantalla solo lo dibuja.

Hoy lo mueve `SimulacionEco`, que es el guion del prototipo cuadro por cuadro. Para el juego real hay que reemplazarla por la lógica que lee los sticks:

* el vuelco de cada stick mueve su luz hacia un borde;
* la partitura del nivel (`NivelEco.pasos`) dice qué tiene que pasar;
* al acertar, se llama a `tocarTrozo` y se enciende el verde.

Los tipos de paso están documentados en `datos/niveles.dart` (`TipoPaso`). La simulación sirve de guía para el orden y los tiempos de cada paso.

Si un stick se pierde en medio del juego, la capa de Bluetooth llama a:

```dart
EpuNavegacion.mostrarPerdida(context, stick: Stick.pequeno, causa: CausaPerdida.bateriaAgotada);
```

## Diferencias a propósito con el prototipo

* **Barra de estado.** El prototipo es un marco de 390 × 844 sin barra de estado. Aquí las pantallas van dentro de `SafeArea` y el juego es a pantalla completa (sin barras), porque el teléfono va dentro del eje.
* **Tamaño de pantalla.** Las pantallas se acomodan al alto real igual que en el prototipo (zonas flexibles). En el juego, las posiciones se escalan desde el marco de 390 × 844 al tamaño real.
* **Sonido en el juego.** En el canvas, tocar la pantalla de juego activa o silencia el sonido. Eso era solo para la vista previa: en «App completa · Eco» siempre suena, y así quedó aquí.
* **Borde punteado de «Pérdida de stick».** Chrome no expone cómo reparte las rayas de un borde `dashed` redondeado. Se midió en una captura (rayas de unos 6 px y espacios de 4 px) y se repartió parejo en el contorno.
* **Flecha que se apaga.** En el prototipo, cuando una flecha de «Antes del nivel» se apaga, vuelve a apuntar hacia arriba de golpe. Se dejó igual. Si prefieren que conserve su dirección, basta con `AnimacionAntes(..., conservarDireccionAlApagar: true)`.
* **Tamaño de letra del sistema.** Se respeta el tamaño de letra que la persona tenga configurado en Android. Si se quiere fijo, como en el prototipo, se envuelve la app en `MediaQuery.withNoTextScaling`.

## Qué se verificó

* **Analizador:** `dart analyze` sobre Flutter 3.47.9, sin errores ni avisos.
* **Manos:** la geometría de las manos se probó contra el JavaScript del prototipo en 114 poses y salió idéntica, carácter por carácter. Ese JavaScript es el que dibuja «Antes del nivel», «Quién guía» y las miniaturas.
* **Movimiento:** el movimiento de «Antes del nivel» en los 7 niveles se comparó contra el prototipo durante 12 s y también salió idéntico. Las pruebas quedaron en `test/`.
* **No se corrió en un teléfono:** el entorno donde se escribió no tiene el motor de Flutter. Conviene revisar en un Android real:
  * que las pantallas se vean iguales al canvas;
  * la latencia de los sonidos al acertar;
  * el desenfoque de las luces del juego.

## Pendientes para la app real (no están en el prototipo)

* La implementación de `FuenteSticks` con Bluetooth y la lógica del juego con los sticks reales.
* Permisos de Bluetooth y de No Molestar (Android `ACCESS_NOTIFICATION_POLICY`) en «Conceder permisos».
* Mantener la pantalla encendida durante el juego (por ejemplo, con el paquete `wakelock_plus`).
* Guardar en el teléfono los niveles completados y las sesiones.
