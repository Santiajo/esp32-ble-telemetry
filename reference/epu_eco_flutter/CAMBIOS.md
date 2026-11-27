# Epu · flujo Eco en Flutter · cambios desde la versión 0.1

Este archivo junta lo que cambió en el paquete respecto de la primera entrega (0.1). Primero va lo nuevo de la **0.3** y después lo de la **0.2**: el recuerdo abstracto al final del nivel, el marcador para guardarlo, el menú hamburguesa «Tu archivo» con recuerdos y sesiones, el Home solo con «Jugar», las manos nuevas de «Calibrar», la luz de ayuda más suave y la espera de 4 s.

Para revisar en un teléfono, lo más rápido es abrir la app con el archivo lleno:

```dart
runApp(EpuEcoApp(estado: EstadoEco.demoLleno()));
```

# Versión 0.3

| Archivo | Estado | Qué cambió |
|---|---|---|
| `lib/epu/widgets/lados_de_cada_uno.dart` | nuevo | «Quién va en cada lado» |
| `lib/epu/pantallas/eco_juego.dart` | cambiado | muestra los lados 5 s y recién ahí arranca el juego |
| `lib/epu/pantallas/calibrar.dart` | cambiado | textos nuevos y aviso para el niño |
| `README.md`, `pubspec.yaml` | cambiados | versión 0.3.0+3 |

## Quién va en cada lado (al empezar el juego)

**Antes:** la pantalla de juego empezaba directo con las luces de los sticks.

**Ahora:** durante los primeros 5 s la pantalla se divide en dos para que cada uno sepa cuál es su lado. El teléfono va dentro del eje, entre los dos.

| Zona | Quién | Color | Texto |
|---|---|---|---|
| Arriba, lado de la cámara | Niño | coral | «Niño», girado 180° para que el niño lo lea derecho |
| Abajo | Adulto | lila | «Adulto» |

* Cada mitad es un degradado desde su borde: color sólido hasta el 22 % y transparente hacia el centro.
* Los nombres van en 64 px, peso 900, blancos y con una sombra suave, al centro de su mitad.

**Animación (5 s):**

| Tramo | Qué pasa |
|---|---|
| 0 – 1,4 s | Cada color se abre como un círculo difuminado desde el centro de su borde. Curva `cubic-bezier(.65,0,.35,1)`, la misma de la cortina de la bienvenida. |
| 1,4 – 3,6 s | Queda completo. |
| 3,6 – 5 s | Se desvanece sin cambiar de forma (ease-in-out). |
| Nombres | Aparecen entre 0,75 y 1,5 s (opacidad y escala .88 → 1) y se van entre 3,3 y 4 s. |

* El círculo es una máscara radial (`ShaderMask` con `RadialGradient`) con núcleo opaco hasta el 55 % del radio y borde difuminado. Crece de 0 a 1600 px de diámetro en el marco de 390, escalado al ancho real.
* Las luces de los sticks están apagadas mientras se ven los lados. A los 5 s arranca la simulación (`SimulacionEco.iniciar()`), que las enciende.
* Con «Quitar animaciones» se ve completo y quieto durante los 5 s.
* `LadosDeCadaUno(fija: true)` lo deja quieto y completo, útil para revisarlo.
* **Para la app real:** el juego con los sticks debe empezar en el mismo punto, en `_empezar()` de `eco_juego.dart`.

## Textos de «Calibren los sticks»

**Antes:** «Cada uno sostiene su stick, con la luz hacia arriba» y debajo «Quédense quietos hasta que termine.».

**Ahora:**

* Arriba del todo, antes del dibujo, va «Leer esta instrucción al **niño**», en 18 px, peso 900, interlineado 1,2. «niño» va en el coral del stick del niño.
* El texto pasa a ser «Cada uno sostiene su stick, con la luz hacia el frente tuyo como en el dibujo».
* Se quitó «Quédense quietos hasta que termine.».
* La descripción accesible del dibujo ahora dice «con la luz de la punta hacia el frente».

## Qué se verificó en la 0.3

* **Analizador:** `dart analyze` sobre Flutter 3.47.9, sin errores ni avisos.
* **Tiempos y curvas:** los de los lados se copiaron del CSS del prototipo, tramo por tramo.
* **No se corrió en un teléfono.** Conviene revisar el círculo difuminado y que «Niño» quede bien orientado con el teléfono dentro del eje.

# Versión 0.2

## Resumen de archivos (0.2)

| Archivo | Estado | Tareas |
|---|---|---|
| `lib/epu/ilustraciones/huella_datos.dart` | nuevo | EPU-1 |
| `lib/epu/ilustraciones/huella.dart` | nuevo | EPU-1, EPU-4 |
| `lib/epu/pantallas/eco_final.dart` | reescrito | EPU-1, EPU-2, EPU-3 |
| `lib/epu/estado/estado_eco.dart` | reescrito | EPU-3, EPU-4, EPU-5 |
| `lib/epu/pantallas/home.dart` | reescrito | EPU-4, EPU-6 |
| `lib/epu/navegacion/rutas.dart` | cambiado | EPU-3, EPU-4 |
| `lib/epu/widgets/comunes.dart` | cambiado | EPU-3 |
| `lib/epu/pantallas/eco_juego.dart` | cambiado | EPU-5, EPU-9 |
| `lib/epu/ilustraciones/preparacion.dart` | cambiado | EPU-8 |
| `lib/epu/ilustraciones/manos.dart` | cambiado | EPU-8 |
| `lib/epu/pantallas/calibrar.dart` | cambiado | EPU-8 |
| `lib/epu/pantallas/eco_antes.dart` | cambiado | EPU-10 |
| `test/recuerdo_test.dart` | nuevo | EPU-1, EPU-4, EPU-5 |
| `README.md`, `pubspec.yaml` | cambiados | versión 0.2.0+2 |

No se agregaron paquetes.

---

## EPU-1 · Recuerdo abstracto en la pantalla final del nivel

**Antes:** una fila de destellos de color, uno por trozo, sobre un brillo verde. Debajo, «Instrumento · X segundos · N trozos».

**Ahora:** un dibujo abstracto, la «huella», hecho con los movimientos del nivel.

**Cómo es el dibujo**

* Por cada trozo salen hilos desde el centro hacia donde se volcó cada stick: 4 del adulto (lila) y 3 del niño (coral).
* En los giros, cada uno tiene 2 hilos en forma de espiral.
* En cada trozo hay una luz amarilla (halo y núcleo) donde se encontraron.
* Es **estático**: se dibuja el cuadro final y no tiene animación de entrada.
* No tiene fondo: va directo sobre el fondo de la pantalla.
* Ocupa todo el ancho (346 px en el marco de 390), es cuadrado y va pegado arriba del área central.
* Debajo va la leyenda «Adulto», «Niño» y «Se encontraron», y luego el resumen de quién guió.
* El encabezado ahora dice «Nivel N · nombre · instrumento». Se quitaron los segundos y los trozos.

**Archivos**

* `ilustraciones/huella_datos.dart`: genera los datos del dibujo. Es Dart puro, sin Flutter, para poder probarlo.
  * Usa un generador con semilla (`id × 977`), así cada nivel dibuja siempre lo mismo.
  * **No cambien el orden en que se piden los números.** Si cambia, cambia el dibujo. Por eso se mantienen las «nieblas»: ya no se dibujan, pero consumen números igual que en el prototipo.
* `ilustraciones/huella.dart`: el widget `DibujoHuella` y su `PintorHuella`. Grosores y radios se escalan por `ancho / 346`.
* `pantallas/eco_final.dart`: usa `DibujoHuella` en lugar de `_Destellos`.

**«Escuchar la melodía»**

* El trozo que suena queda más opaco (peso 1,6) y su luz crece ×1,35.
* Los demás bajan a peso 0,3.
* El cambio es instantáneo, como en el prototipo. Antes, el destello crecía en 0,35 s.

**Para la app real:** hoy el dibujo sale de la partitura del nivel (`NivelEco.pasos`). Si se quiere que salga de lo que de verdad hicieron con los sticks, basta con entregarle a `DatosHuella.de` los pasos registrados en la partida. El dibujo no cambia.

---

## EPU-2 · Palabra «juntos» con degradado animado

**Antes:** «La descubrieron juntos» era de un solo color.

**Ahora:** «juntos» lleva un degradado lila → coral → lila que se desplaza lento.

* `pantallas/eco_final.dart`, widget `_PalabraJuntos`: un `ShaderMask` con un degradado del doble del ancho de la palabra, que se repite.
* El degradado se corre un largo completo cada 10 s, de forma lineal y sin fin. Así el ciclo empalma sin salto. Es lo mismo que `background-size: 200%` con `background-position` de 0 % a 200 %.
* Va dentro del título con un `WidgetSpan` alineado a la línea base, para que no se mueva respecto del resto del texto.
* Con «Quitar animaciones» queda quieto en la posición inicial.

---

## EPU-3 · Guardar el recuerdo con un marcador

**Antes:** no se podía guardar.

**Ahora:** hay un marcador arriba a la derecha.

* `pantallas/eco_final.dart`, widget `_Marcador`:
  * Círculo blanco de 44 px con sombra y el ícono de marcador vacío en tinta.
  * Al guardar, el fondo pasa a teal en 0,3 s y el ícono queda blanco y relleno.
  * Hace un «pop»: ×1 → ×1,22 → ×1 en 0,45 s, con la curva aplicada a cada tramo, como en CSS.
  * No hay texto de confirmación: el estado del botón basta.
  * Una vez guardado no se puede tocar de nuevo.
* `widgets/comunes.dart`: `PantallaBase` tiene un nuevo parámetro `accion`, un widget que va en `top: 14, right: 14`.
* `estado/estado_eco.dart`: `guardarRecuerdo(nivel)` agrega el recuerdo al principio de la lista con la fecha de hoy.
  * Cada vez que se guarda queda uno nuevo (uno por partida), igual que en el prototipo.
* `navegacion/rutas.dart`: nuevo `ArgumentosRecuerdo.desdeArchivo`.
  * Cuando la pantalla se abre desde «Tu archivo», el marcador ya aparece guardado y no anima.

---

## EPU-4 · Menú hamburguesa «Tu archivo»

**Antes:** no existía.

**Ahora:** en el Home, un botón de 44 px arriba a la izquierda abre un panel lateral con los recuerdos y las sesiones agrupados por nivel.

**Archivo:** `pantallas/home.dart`, con `_MenuArchivo`, `_Pestanas`, `_Grupo`, `_FilaSesion` y `_BotonVerMas`.

**Panel**

* Mide 330 px de ancho, con esquinas derechas de 28 y sombra hacia la derecha.
* Arriba: el logo de Epu a 30 px, alineado a la izquierda, y la X para cerrar.
* Debajo, el título «Tu archivo» y las pestañas «Recuerdos» / «Sesiones», sin contador.

**Grupos**

* Van del nivel 1 al 7 y solo aparecen los que tienen algo.
* El título es «Nivel N - nombre» seguido del instrumento, más la cantidad en una píldora.
* Se muestran 3 elementos por nivel (`_Grupo.maximo`). El resto se abre con «Ver N más» y se cierra con «Ver menos».
* Lo que se despliega se recuerda por pestaña mientras el menú siga abierto.

**Elementos**

* **Recuerdos:** tarjeta de 92 px con el dibujo en miniatura (80 px, el mismo `DibujoHuella`) y la fecha.
* **Sesiones:** fila con la fecha, «X min · ok de N trozos», una barra teal de progreso y un chevrón.
* **Fechas:** se muestran como «Hoy», «Ayer» o «Domingo, 15 nov» (`fechaArchivo` en `estado_eco.dart`).
* **Al tocar un elemento:** se cierra el menú y se abre «Eco · el recuerdo» de ese nivel, ya guardado.

**Si no hay nada:** se muestra un texto para cada pestaña.

* Recuerdos: «…toquen el marcador para guardarlo». El prototipo todavía decía «Guardar el recuerdo»; se ajustó al marcador.
* Sesiones: aparecen solas cuando terminan una melodía.

**Animaciones**

* Abrir: el velo aparece en 0,25 s y el panel entra en 0,35 s `cubic-bezier(.2,.8,.2,1)`.
* Cerrar: los dos en 0,22 s.
* Pestañas: cambian de color en 0,25 s.
* «Ver N más»: el chevrón gira en 0,25 s.

**Cómo se cierra:** con la X, tocando el velo o con «volver» de Android.

**Datos**

* `estado/estado_eco.dart` reemplaza `SesionPasada` por `RecuerdoGuardado` y `SesionNivel`.
* `EstadoEco.demo()` trae los ejemplos del prototipo.
* `EstadoEco.demoLleno()` llena el archivo con el mismo generador que la opción «datos: muchos» del canvas.
* `PantallaHome(menuInicial: PestanaArchivo.sesiones)` abre el menú de entrada, útil para revisar la vista.

---

## EPU-5 · Registro automático de sesiones

**Antes:** las sesiones eran solo ejemplos fijos.

**Ahora:** cada nivel terminado se guarda como sesión.

* `pantallas/eco_juego.dart`: al terminar, antes de abrir el recuerdo, llama a `registrarSesion(nivel, minutos, logrados)`.
  * Los minutos se miden de verdad desde que se abrió el juego, con un mínimo de 1. El prototipo anotaba siempre 1.
  * Los trozos logrados hoy son todos, porque la simulación siempre completa el nivel. **Con los sticks reales hay que pasar los trozos que de verdad lograron.**
* Abrir un recuerdo desde el archivo no cuenta como sesión nueva.

---

## EPU-6 · Home solo con el botón Jugar

**Antes:** el Home tenía el logo, «Jugar», la lista «Sesiones pasadas» (con botón de compartir) y el enlace «Repasar la preparación».

**Ahora:** solo el logo y «Jugar», más el botón del menú.

* `pantallas/home.dart`: se quitaron `_TarjetaSesion`, `_IconoCompartir` y el enlace a la preparación.
* «Repasar la preparación» tampoco está en el menú.
* **Pendiente de decidir:** con esto, la preparación ya no se puede abrir desde ninguna parte de la app.

---

## EPU-8 · Ilustración de calibración con las manos de los niveles

**Antes:** sticks y manos hechos con rectángulos, en otro estilo.

**Ahora:** las mismas manos de «Quién guía» y de las pantallas de nivel. El adulto sostiene el stick lila grande y el niño el coral más pequeño, cada uno con una flecha verde punteada hacia arriba.

* `ilustraciones/preparacion.dart`: `pintarCalibrar` ahora dibuja con `dibujarMano` y `GeometriaMano(0, 0)`, con la mano quieta y el stick derecho.
  * Las flechas tienen trazo 1,4 y punteado `.4 3.2`.
  * El viewBox es `0 −10 120 110` a 285 px de ancho; se corre 10 unidades porque `LienzoSvg` no maneja el −10.
* `ilustraciones/manos.dart`: `LuzMano` tiene un segundo anillo (`anillo2Opacidad`, `anillo2Escala`). Solo lo usa «Calibrar».
* `pantallas/calibrar.dart`: el lienzo pasa de 320 × 260 a 120 × 110.
* Las animaciones al calibrar no cambian, ahora sobre la luz de cada mano:
  * dos anillos que se expanden ×1 → ×2,8 en 1,3 s, el segundo con 0,65 s de retraso;
  * la luz parpadea cada 0,7 s.

---

## EPU-9 · Luz de ayuda más suave y angosta

**Antes:** la franja del borde partía con opacidad 0,9, bajaba a 0,45 y desaparecía. Llegaba al 7,5 % de la pantalla arriba y abajo, y al 16 % en los lados.

**Ahora:** es más difuminada y cerca de la mitad de ancha. El largo es el mismo: cubre todo el borde.

`pantallas/eco_juego.dart`, `_Franja`:

| opacidad | 0,6 | 0,34 | 0,14 | 0,05 | 0 |
|---|---|---|---|---|---|
| bordes de arriba y abajo | 0 | 0,8 % | 2 % | 3,2 % | 4,4 % |
| bordes de los lados | 0 | 1,8 % | 4,4 % | 7 % | 9,6 % |

* Vale para los tres colores: lila, coral y amarillo.
* La franja de **sostener** (la amarilla ancha que crece) no cambió.

---

## EPU-10 · Espera de 4 s en «Comenzar»

**Antes:** «Comenzar» en «Antes del nivel» quedaba bloqueado 3 s.

**Ahora:** 4 s.

* `pantallas/eco_antes.dart`: la barra de llenado y el desbloqueo duran 4 s.
* «Empezar nivel» en «Quién guía» **no** tiene bloqueo: se probó y se descartó.

---

## Qué se verificó

* **Analizador:** `dart analyze` sobre Flutter 3.47.9, sin errores ni avisos.
* **Dibujo del recuerdo:** se compararon 3.216 valores entre hilos y luces de los 7 niveles contra el JavaScript del prototipo, y salieron idénticos. Quedó una prueba en `test/recuerdo_test.dart` con valores de referencia.
* **Fechas:** se probaron los días de la semana del archivo (por ejemplo, 15 nov 2026 es domingo y 30 oct es viernes).
* **No se corrió en un teléfono.** Conviene revisar:
  * que el dibujo del recuerdo y las miniaturas se vean como en el canvas;
  * el degradado de «juntos» alineado con el resto del título;
  * la apertura y el cierre del menú;
  * la nueva luz de ayuda en el juego, sobre todo en pantallas grandes.

## Pendientes para la app real

* Guardar en el teléfono los recuerdos, las sesiones y los niveles completados. Hoy viven en memoria. Los puntos para engancharlo son `guardarRecuerdo`, `registrarSesion` y `marcarCompletado` en `EstadoEco`.
* Pasar los trozos logrados reales al registrar la sesión.
* Decidir si la preparación necesita una entrada en la app.
