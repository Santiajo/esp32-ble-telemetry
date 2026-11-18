# Epu · 11a Flujo completo · copia del prototipo

Copia de todos los archivos del prototipo (canvas Design de Claude), tal como estaban publicados.

## Qué hay

- `project/`: las 55 pantallas y vistas del canvas (`.dc.html`) y `canvas.json`, que guarda la posición, el título y las notas de cada mesa de trabajo.
  - Flujo nuevo (Eco): `AppEco`, `EcoIni1` a `EcoIni6`, `EcoNiveles`, `EcoAntes`, `EcoGuia`, `EcoJuego`, `EcoFinal` y las vistas de los 7 niveles (`Eco1Antes` … `Eco7Final`). Usa también `Main`, `Prep1`, `Prep2`, `Prep4`, `Prep5`, `Bienvenida`, `Home` y `Calibrar`.
  - Flujo anterior (por movimiento): `App`, `Niveles`, `Antes`, `Guia`, `Juego`, `Final` y `Perdida`.
- `assets/logo-epu.svg`: el logo. En el prototipo vive en el almacén de archivos del artefacto, y `Main`, `Home` y `Bienvenida` lo cargan con una dirección que empieza con `/_blob/19f7632108754f2205b82c485f808219`.

## Cómo pasarlo a otra cuenta de Claude

Estos archivos solo funcionan dentro de un artefacto de tipo Design en Claude; abiertos sueltos en un navegador no se ven.

1. En la otra cuenta, abrir una conversación nueva y adjuntar este zip.
2. Pedirle a Claude algo como:
   > Crea un artefacto de tipo Design llamado «Epu · 11a Flujo completo» con los archivos de `project/` de este zip, tal cual. Sube `assets/logo-epu.svg` al almacén de archivos del artefacto y reemplaza en `Main`, `Home` y `Bienvenida` la dirección `/_blob/19f7632108754f2205b82c485f808219` por la del logo subido.
3. Revisar que el canvas abra con las mismas filas y que «App completa · Eco» se pueda recorrer de punta a punta.

El historial de versiones y los comentarios del artefacto original no se copian: la cuenta nueva parte desde esta versión.
