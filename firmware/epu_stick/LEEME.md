# Firmware Epu · stick (ESP32-C3 + ICM-42688-P)

Un solo archivo, `main.py`, para todos los sticks. Lee el sensor ICM-42688-P por SPI a 100 Hz y lo manda por Bluetooth a la app Epu. El stick se anuncia como **«Epu - adulto»** o **«Epu - niño»**.

Las placas de los sticks P1 y P2 (XIAO ESP32-C3) ya están reconocidas. Para probar **otra placa**, por ejemplo una **ESP32-C3 Super Mini**, sigue estos pasos.

## 1. Instalar MicroPython en la placa (una sola vez)

1. Conecta la placa por USB y abre **Thonny**.
2. Ve a **Herramientas → Opciones → Intérprete**, elige **MicroPython (ESP32)** y el puerto de la placa.
3. Haz clic en **«Instalar o actualizar MicroPython (esptool)»**. Elige la familia **ESP32-C3** y la variante **Espressif • ESP32-C3** (la Super Mini usa la genérica; la XIAO, la de Seeed). Haz clic en **Instalar**.
4. Si no la encuentra: mantén apretado el botón **BOOT** mientras enchufas la placa y vuelve a intentarlo.

## 2. Ajustar el firmware para la placa nueva

Abre `main.py`. Al principio está la sección **«Placa nueva»**:

```python
NUEVA_ROL = 'B'              # 'A' = adulto · 'B' = niño
NUEVA_SPI = None             # (CS, SCK, MISO, MOSI) en GPIO, o None
NUEVA_LED = 8                # Super Mini: LED azul en GPIO8 (None = sin LED)
NUEVA_LED_INVERTIDO = True   # el LED de la Super Mini se enciende con 0
```

- **Rol:** `'B'` si reemplaza al stick del niño y `'A'` si reemplaza al del adulto. No pongas dos sticks con el mismo rol.
- **Cableado del sensor.** El firmware prueba solo estos tres (números de **GPIO**):

  | Placa | CS | SCK | MISO | MOSI |
  |---|---|---|---|---|
  | P2 (XIAO) | 5 | 4 | 6 | 10 |
  | P1 (XIAO) | 5 | 6 | 7 | 10 |
  | Super Mini (pines SPI de la placa) | 7 | 4 | 5 | 6 |

  Si el sensor va en otros pines, ponlos en `NUEVA_SPI`, por ejemplo `NUEVA_SPI = (7, 4, 5, 6)`. Así se prueban primero.
- **LED:** si el stick usa un LED propio, pon su GPIO en `NUEVA_LED` y `NUEVA_LED_INVERTIDO = False`.

El sensor va con **3V3** y **GND** de la placa.

## 3. Cargarlo y revisar la consola

1. En Thonny, guarda el archivo **en la placa** con el nombre `main.py` (Archivo → Guardar como → Dispositivo MicroPython).
2. Reinicia la placa (Ctrl+D). En la consola debería aparecer:
   ```
   [PLACA] nueva (xxxxxxxxxxxx) · rol B · Epu - niño
   [SPI] WHO_AM_I = 0x47 (CS …, SCK …, MISO …, MOSI …)
   [ICM] OK por SPI 1 MHz
   [DIAG] … |g| 1.00x
   [BLE] Anunciando como Epu - niño
   ```
   - **`WHO_AM_I = 0x47`** significa que el sensor responde.
   - **0x00 o 0xFF** en todas las líneas significa que no responde: revisa el cableado. El firmware reintenta cada 2 s, así que al arreglar el cable se recupera solo.
   - **`|g|`** debe estar cerca de 1,00 con el stick quieto.
3. Anota el número entre paréntesis de la línea `[PLACA]` (es la MAC). Con él se agrega la placa a la lista y queda reconocida, igual que P1 y P2.

## 4. Qué significa la luz

| Luz | Qué pasa |
|---|---|
| Parpadeo rápido (5 por segundo) | No encuentra el sensor; reintenta cada 2 s |
| Parpadeo lento (1 por segundo) | Sensor OK; espera que el teléfono se conecte |
| Fija | Conectado al teléfono y mandando datos |

## 5. Ejes (si el sensor va montado distinto)

El firmware supone el sensor montado **de canto**, como en P1 y P2. Con la placa conectada y **sin teléfono**, la consola muestra 5 veces por segundo `adelante …°  lado …°`:

- con el stick **derecho**, los dos valores deben quedar cerca de 0°;
- con la **punta hacia adelante**, «adelante» debe subir;
- con la **punta a la derecha**, «lado» debe subir.

Si no da así, avísale a Santiago con esos números y se ajusta para esa placa.

## Nota sobre el stick P1

Mientras corre un programa, el P1 no acepta que el PC le escriba por USB. Para recargarlo hay que reinstalar MicroPython (paso 1) y guardar `main.py` enseguida. Además tiene un falso contacto con su sensor (EPU-16).
