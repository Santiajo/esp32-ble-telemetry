# Sonidos de Epu · versión Eco

Generados con el mismo código de audio del prototipo, así que suenan igual que en el artefacto. Vienen en dos formas, para usar la que más le acomode a la app. Las dos suenan igual.

```
epu_sonidos/
├── conexion_stick.wav   tono que suena cuando cada stick termina de conectarse
├── por_nivel/           trozos y melodías ya armados (41 archivos)
└── por_nota/            una nota por archivo + melodias.json (96 archivos)
```

## Opción A · `por_nivel/` (la más simple)

- **34 trozos:** `nivelN_instrumento_trozoM.wav`. Suena uno cada vez que la díada acierta un paso del nivel, en orden (paso 1 → trozo 1, paso 2 → trozo 2…).
- **7 melodías completas:** `nivelN_instrumento_completa.wav`. Suena al terminar el nivel y en «Escuchar la melodía» de la pantalla del recuerdo.
- **`listado.csv`:** cada archivo con sus notas y su duración.

La app solo reproduce el archivo que corresponde.

## Opción B · `por_nota/` (la más flexible)

- **Las 6 notas de la pentatónica** (la3, do4, re4, mi4, sol4 y la4) en los 7 instrumentos.
  - **Marimba, guitarra, handpan y piano** (`madera`, `cuerda`, `metal`, `teclas`): se apagan solas, un archivo por nota (`madera_la3.wav`).
  - **Flauta, clarinete y coro** (`viento`, `cana`, `voces`): son sostenidas, así que hay un archivo por nota y por duración (`viento_mi4_1000ms.wav`), en 500, 1000, 1500 y 2000 ms.
- **`melodias.json`:** las melodías de los 7 niveles. Cada nivel indica su instrumento y sus trozos, y cada trozo es la lista de notas en orden con su duración en milisegundos.
- **`listado.csv`:** cada archivo con su instrumento, nota, frecuencia y largo.

Para armar un trozo:

1. Tomar el trozo en `melodias.json` (por ejemplo, nivel 1, trozo 1: la3 1000 ms, do4 1000 ms).
2. Tocar la primera nota y, al cumplirse su `duracionMs`, la siguiente, hasta el final del trozo.
   - En instrumentos sostenidos se usa el archivo de esa duración (`viento_mi4_1000ms.wav`).
   - En los que se apagan solos se usa el de la nota (`madera_la3.wav`).
3. Las notas se superponen (la cola de una sigue sonando cuando empieza la otra), así que el reproductor tiene que poder tocar varias a la vez.
4. La melodía completa es lo mismo con todos los trozos seguidos.

Sirve si más adelante se cambian las melodías: basta con editar `melodias.json`, sin generar audios nuevos.

## Niveles

| Nivel | Instrumento | Trozos |
|---|---|---|
| 1 · Madera | Marimba | 4 |
| 2 · Viento | Flauta dulce | 4 |
| 3 · Cuerda | Guitarra | 4 |
| 4 · Caña | Clarinete | 5 |
| 5 · Metal | Handpan | 5 |
| 6 · Voces | Coro | 6 |
| 7 · Teclas | Piano | 6 |

## Formato

- WAV, 16 bits, mono, 44,1 kHz.
- Empiezan sin silencio, para que suenen apenas se acierta.
- Las dos carpetas llevan la misma ganancia: el sonido más fuerte llega a −1 dBFS y se mantiene el balance de volumen del prototipo.
- No hay sonido de error, como define la mecánica.
- Conviene precargar los sonidos del nivel antes de empezar a jugar, para que no haya retraso al acertar.
