# Firmware Epu · sticks P1 y P2 (XIAO ESP32-C3 + ICM-42688-P)

Un solo archivo, `main.py`, sirve para los dos sticks. Al arrancar, cada placa se reconoce sola:

| Stick | Se anuncia como | Pines del sensor (GPIO) | LED |
|---|---|---|---|
| **P2** (grande, adulto) | Epu - adulto | CS 5 · SCK 4 · MISO 6 · MOSI 10 | GPIO21 (D6) |
| **P1** (chico, niño) | Epu - niño | CS 5 · SCK 6 · MISO 7 · MOSI 10 | GPIO21 (D6) |

No hay que editar nada: el firmware detecta cuál de los dos cableados responde. El sensor va con **3V3** y **GND** de la placa.

## Cargarlo

1. Conecta el stick por USB (con un cable de datos, no solo de carga) y abre **Thonny**.
2. Ve a **Herramientas → Opciones → Intérprete**, elige **MicroPython (ESP32)** y el puerto del stick.
3. Detén el programa que esté corriendo con el botón **Stop** (o Ctrl+C).
4. Abre `main.py` y guárdalo **en la placa** con el nombre `main.py` (Archivo → Guardar como → Dispositivo MicroPython).
5. Reinicia con **Ctrl+D**.

**El P1 es distinto:** mientras corre un programa, no deja que el PC le escriba, así que Thonny no logra detenerlo ni guardar. En ese caso hay que reinstalar MicroPython y guardar `main.py` enseguida:

1. En **Herramientas → Opciones → Intérprete**, haz clic en **«Instalar o actualizar MicroPython (esptool)»**.
2. Elige familia **ESP32-C3** y variante **Seeed • XIAO ESP32C3**, versión **1.29.0**, y haz clic en **Instalar**. Si no encuentra la placa, mantén apretado **BOOT** mientras la enchufas.
3. Guarda `main.py` en la placa (paso 4 de arriba) **antes** de reiniciarla.

## Revisar que funciona

Al reiniciar, la consola de Thonny debería mostrar:

```
[PLACA] P1 (ac276e8148fc) · rol B · Epu - niño
[SPI] WHO_AM_I = 0x00 (CS 5, SCK 4, MISO 6, MOSI 10)     ← cableado del P2: en el P1 da 0x00, es normal
[SPI] WHO_AM_I = 0x47 (CS 5, SCK 6, MISO 7, MOSI 10)     ← 0x47 = el sensor responde
[ICM] OK por SPI 1 MHz
[DIAG] … ruido acel … mg · … |g| 1.00x
[BLE] Anunciando como Epu - niño
```

- **`WHO_AM_I = 0x47`** en la línea de su cableado indica que el sensor responde bien.
- **0x00 o 0xFF en las dos líneas** indica que el sensor no responde: hay un cable o una soldadura con mal contacto. Es lo que tiene hoy el **P1 (EPU-16)**. El firmware reintenta cada 2 s, así que al arreglar el contacto se recupera solo, sin recargar nada.
- **`|g|`** debería quedar cerca de 1,00 con el stick quieto. El ruido del acelerómetro, cerca de 1–2 mg.

Una forma rápida de encontrar el falso contacto: con el stick conectado y la consola abierta, mueve un poco cada cable. Si al tocar uno aparece `0x47` y el stick empieza a anunciarse, ese es el cable.

## Qué significa la luz

| Luz | Qué pasa |
|---|---|
| Parpadeo rápido (5 por segundo) | No encuentra el sensor; reintenta cada 2 s |
| Parpadeo lento (1 por segundo) | Sensor OK; espera que el teléfono se conecte |
| Fija | Conectado al teléfono y mandando datos |

## Para comprobarlo con la app

Con el stick a batería, abre la app Epu en **un solo teléfono** y entra a **«Repasar la preparación» → «Conectar sticks»**. Cada stick acepta un solo teléfono a la vez; si otro teléfono tiene la app abierta, puede tenerlo tomado.
