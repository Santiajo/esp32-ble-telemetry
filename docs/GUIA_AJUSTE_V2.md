# Guía de ajuste · Banco de prueba v2

Cómo mover los controles de **Banco de prueba v2 → Ajuste** según lo que quieras lograr. No hace falta saber de sonido ni de sensores: busca la frase que describe lo que te pasa y prueba el cambio sugerido.

## Cómo probar sin perderse

1. **Cambia un control a la vez.** Si mueves dos, no sabrás cuál produjo el efecto.
2. **Prueba uno o dos minutos** con la misma persona y el mismo gesto antes de decidir.
3. **Anota** el valor y lo que sentiste. Ejemplo: «Pérdida al salir 1,5: se siente justo; 2: frustra».
4. Los cambios se guardan solos en el teléfono. Hay tres botones arriba del panel:
   - **Copiar valores:** copia todo como texto. Pégamelo y lo dejo como valores de fábrica.
   - **Valores iniciales:** vuelve a lo recomendado.
   - **Como el prototipo:** apaga los cambios del 18-10-2026 para comparar con el original.
5. El progreso, las salidas de sincronía y el tiempo en sincronía de cada intento quedan en **Telemetría**.

---

## 1. Lograr el nivel: qué tan exigente es

| Lo que pasa | Qué mover | Hacia dónde |
|---|---|---|
| **Se logra demasiado fácil**, aunque no suenen bien juntos | Pérdida al salir | Subir: 1 → 1,5 o 2 |
| | Tolerancia (× nivel) | Bajar: 1 → 0,85 |
| | Margen al salir de la zona | Bajar: 0,4 → 0,2 s |
| **Frustra: se pierde el avance por nada** | Margen al salir de la zona | Subir: 0,4 → 0,7 s |
| | Pérdida al salir | Bajar: 1 → 0,5 |
| | Tolerancia (× nivel) | Subir: 1 → 1,15 |
| **Tras calibrar, un punto queda pegado a un borde** | Calibración robusta | Debe estar en 1. Repite «Calibrar rango» moviendo los sticks por todo su recorrido. |
| **A alta velocidad se pierde la sincronía** aunque los dos lo hagan bien | Tolerancia de retraso | Subir: 150 → 200–250 ms |
| | Calibrar al empezar | «sí» (botón del banco): si el stick vive pegado al borde, su curva se recorta |
| **Cuenta como juntos aunque uno vaya claramente atrasado** | Tolerancia de retraso | Bajar: 150 → 80 ms |
| **El sonido parpadea** entre afinado y ondulando cuando están justo en el borde | Histéresis de la sincronía | Subir: 1,25 → 1,4. Una vez dentro, cuesta más salir. |
| **Cuenta como «juntos»** cuando uno sube y el otro baja y se cruzan | Peso de la velocidad en d | Subir: 0,06 → 0,1 |
| **No cuenta** aunque van juntos, porque uno mueve la mano más rápido o más brusco | Peso de la velocidad en d | Bajar: 0,06 → 0,03. Con 0 solo importa la altura. |
| **El nivel dura mucho** (o muy poco) | Segundos por nivel (×) | Bajar o subir: 1 = 8 s en sincronía |
| **Una pausa corta** (2–3 s) ya les baja el progreso | Inactividad antes de decaer | Subir: 3 → 5 s |

> **Cómo funciona ahora:** el progreso sube mientras están dentro de la zona *y* se mueven a una velocidad parecida. La app perdona un pequeño desfase entre los dos (la **tolerancia de retraso**, 150 ms): compara al niño con el adulto un poco antes o después y se queda con el mejor calce. Sin eso, a alta velocidad un retraso mínimo de la mano o del Bluetooth separa mucho los puntos. Si salen, tienen un **margen** (0,4 s) antes de que empiece a bajar. Pasado el margen, baja a la **velocidad de pérdida**: con 1, baja tan rápido como sube.

## 2. La frase que se arma durante el nivel

| Lo que pasa | Qué mover |
|---|---|
| Quiero escuchar el avance: do, re, mi… | Frase nota a nota = **1** (viene así) |
| Las notas de la frase distraen | Frase nota a nota = **0** |

Con 1, suena una nota de la frase por cada cuarto del nivel (a los 2, 4 y 6 s). Al completar, suena la frase entera. Si el progreso vuelve a bajar de un cuarto, esa nota «cae»: suena suave y apagada.

## 3. Notas del niño: la escala de paso

Cuando el niño se mueve rápido, su nota puede saltar varias notas de golpe. La **escala de paso** recorre las notas intermedias muy rápido para llegar, en vez de saltar.

| Lo que pasa | Qué mover | Hacia dónde |
|---|---|---|
| **Todavía se oyen saltos** | Notas de paso (máximo) | Subir: 6 → 8 |
| **Suena como cascada**, demasiadas notas | Notas de paso (máximo) | Bajar: 6 → 3 |
| **La nota de llegada se siente atrasada** respecto del gesto | Duración de la escala de paso | Bajar: 120 → 80 ms |
| **La escala suena atropellada** | Duración de la escala de paso | Subir: 120 → 180 ms |
| **No se distinguen** las notas de paso | Volumen de las notas de paso | Subir: 0,6 → 0,8 |
| **Las notas de paso tapan** la nota a la que llega | Volumen de las notas de paso | Bajar: 0,6 → 0,4 |
| Prefiero los saltos como antes | Notas de paso (máximo) = **0** | |

## 4. El sonido de la relación

| Lo que pasa | Qué mover | Hacia dónde |
|---|---|---|
| La **ondulación** cuando no van juntos es **muy agresiva** | Desafinación máxima | Bajar: 4 → 2,5 Hz |
| La ondulación **casi no se nota** | Desafinación máxima | Subir: 4 → 6 Hz |

## 5. Los puntos en el plano (dedo o stick)

| Lo que pasa | Qué mover | Hacia dónde |
|---|---|---|
| El punto **tiembla** | Suavizado de posición α | Bajar: 0,2 → 0,12. Más suave, pero un poco más lento. |
| El punto **va atrasado** respecto de la mano | Suavizado de posición α | Subir: 0,2 → 0,3 |
| Dice «activo» con el stick **casi quieto** (temblor de la mano) | Umbral de actividad | Subir: 2,5 → 3,5 |
| **No detecta** un gesto lento del adulto | Umbral de actividad | Bajar: 2,5 → 1,5 |
| **El niño tiene que moverse mucho más que el adulto** para lo mismo | Rango mínimo · niño | Bajar: 25 → 15° (igual que el adulto). Es una decisión de diseño: el prototipo pide al niño gestos más amplios. |
| El adulto llega a los bordes con un gesto **demasiado chico** | Rango mínimo · adulto | Subir: 15 → 20–25° |
| **Sin calibrar**, al adulto le cuesta llegar a los bordes | Rango por defecto · adulto | Bajar: 30 → 20°. O toca «Calibrar rango». |
| **Sin calibrar**, el punto del niño se pega al borde enseguida | Rango por defecto · niño | Subir: 45 → 60° |

> **Cómo calibra ahora («Calibración robusta» = 1):** durante los 6 s solo cuentan los momentos en que el stick **se mueve**. El centro es el medio de ese recorrido y el rango se mide por separado hacia los lados y hacia adelante. No importa si el stick estaba apoyado o en otra postura al empezar. Con 0 vuelve al método del prototipo (centro = cómo estaba el stick el primer segundo). Al cambiar la fuente de un panel, su calibración se descarta: vuelve a calibrar.
>
> **Para calibrar bien:** cuando diga «Calibrando», cada persona mueve su stick por **todo el recorrido que usará al jugar** (arriba y abajo, y un poco a los lados) durante los 6 s. Si al terminar el Registro dice «no se movió», ese stick queda con el rango por defecto.
>
> **«Calibrar al empezar: sí»** (botón del banco, viene encendido) hace que cada sesión empiece con 6 s de «muévanse libremente». Si el porcentaje «En el borde» de un stick pasa de ~15 %, su rango es chico: calibra o sube su rango por defecto. En la prueba del 18-10-2026 el niño estaba en el borde el 70 % del tiempo.
>
> «Calibrar rango» mide 6 s de movimiento libre de cada persona y ajusta el rango a ella. Es lo mejor antes de cada prueba seria. Los rangos por defecto solo se usan sin calibrar.

## 6. Solo con stick real (sensor)

| Lo que pasa | Qué mover | Hacia dónde |
|---|---|---|
| Con el stick quieto, el punto **se desliza lento** hacia un lado | Stick: corrección con gravedad | Subir: 0,02 → 0,04 |
| El punto **salta** cuando se sacude el stick sin inclinarlo | Stick: corrección con gravedad | Bajar: 0,02 → 0,01 |
| | Stick: compuerta de \|a\| | Bajar: 0,15 → 0,1 g |
| Recién conectado, el punto **gira solo** | Ningún control: deja el stick **quieto 1 s** para que mida el error del giroscopio, o toca «Recalibrar giro» en su panel. | |

Si algo del stick se ve raro, usa **Grabar traza** en su panel, repite el gesto unos 30 s, toca «Detener y compartir» y mándame el archivo: lo convierto en prueba automática.

---

## Valores recomendados (de fábrica)

| Control | Valor | Control | Valor |
|---|---|---|---|
| Tolerancia (× nivel) | 1 | Margen al salir de la zona | 0,4 s |
| Suavizado de posición α | 0,2 | Pérdida al salir | 1× |
| Rango por defecto · adulto / niño | 30° / 45° |
| Rango mínimo · adulto / niño | 15° / 25° | Peso de la velocidad en d | 0,06 s |
| Tolerancia de retraso | 150 ms |
| Calibración robusta | 1 |
| Umbral de actividad | 2,5 u/s | Histéresis de la sincronía | 1,25× |
| Desafinación máxima | 4 Hz | Frase nota a nota | 1 |
| Segundos por nivel | 1× (8 s) | Notas de paso (máximo) | 6 |
| Inactividad antes de decaer | 3 s | Duración de la escala de paso | 120 ms |
| Stick: corrección con gravedad | 0,02 | Volumen de las notas de paso | 0,6× |
| Stick: compuerta de \|a\| | 0,15 g | | |
