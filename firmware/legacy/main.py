# ============================================================
# FIRMWARE MicroPython - ESP32 DevKit V1 + MPU6050
# Envia "rawX,rawY\n" por BLE (Nordic UART Service) a ~50 Hz,
# compatible con el dashboard web corregido.
# ============================================================
import bluetooth
import struct
import time
from machine import Pin, I2C

# ---------- CONFIGURACION ----------
NOMBRE_BLE = "ESP32-MPU-B"     # IMPORTANTE: en la segunda placa cambiar a "ESP32-MPU-B"
                               # Debe empezar con "ESP32" (filtro del dashboard).
                               # Nombres distintos permiten identificar cada placa
                               # en el selector Bluetooth del celular.
FRECUENCIA_HZ = 50             # 50 Hz = 20 ms entre envios. NO subir de ~66 Hz:
                               # saturar el stack BLE causa desconexiones.
PIN_SDA = 21                   # Pines I2C por defecto de la DevKit V1
PIN_SCL = 22
MPU_ADDR = 0x68                # 0x69 si AD0 esta en 3V3

# UUIDs Nordic UART Service (los mismos que usa ble.js del dashboard)
_UART_SERVICE = bluetooth.UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
_UART_TX = (
    bluetooth.UUID("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"),
    bluetooth.FLAG_READ | bluetooth.FLAG_NOTIFY,
)
_UART_UUID_ADV = _UART_SERVICE

# ---------- DRIVER MINIMO MPU6050 ----------
class MPU6050:
    def __init__(self, i2c, addr=MPU_ADDR):
        self.i2c = i2c
        self.addr = addr
        # Despertar el sensor (registro PWR_MGMT_1 = 0) y configurar rango +-2g
        self.i2c.writeto_mem(self.addr, 0x6B, b"\x00")
        time.sleep_ms(100)
        self.i2c.writeto_mem(self.addr, 0x1C, b"\x00")  # ACCEL_CONFIG: +-2g -> 16384 LSB/g
        self.i2c.writeto_mem(self.addr, 0x1A, b"\x03")  # DLPF 44 Hz: filtra ruido en hardware

    def leer_accel_xy(self):
        # Registros 0x3B..0x3E: ACCEL_XOUT_H/L, ACCEL_YOUT_H/L (big-endian, con signo)
        datos = self.i2c.readfrom_mem(self.addr, 0x3B, 4)
        ax, ay = struct.unpack(">hh", datos)
        return ax, ay

# ---------- SERVIDOR BLE ----------
class ServidorBLE:
    def __init__(self):
        self.ble = bluetooth.BLE()
        self.ble.active(True)
        self.ble.irq(self._irq)
        ((self.handle_tx,),) = self.ble.gatts_register_services(
            ((_UART_SERVICE, (_UART_TX,)),)
        )
        self.conexiones = set()
        self._anunciar()

    def _payload_adv(self):
        # Flags (LE general discoverable) + nombre completo
        nombre = NOMBRE_BLE.encode()
        payload = b"\x02\x01\x06" + bytes((len(nombre) + 1, 0x09)) + nombre
        return payload

    def _anunciar(self):
        # Intervalo 100 ms: anuncio agresivo = conexion mas rapida y confiable
        self.ble.gap_advertise(100_000, adv_data=self._payload_adv())
        print("BLE anunciando como:", NOMBRE_BLE)

    def _irq(self, evento, datos):
        if evento == 1:  # _IRQ_CENTRAL_CONNECT
            conn_handle, _, _ = datos
            self.conexiones.add(conn_handle)
            print("Central conectado:", conn_handle)
        elif evento == 2:  # _IRQ_CENTRAL_DISCONNECT
            conn_handle, _, _ = datos
            self.conexiones.discard(conn_handle)
            print("Central desconectado. Re-anunciando...")
            # CLAVE: volver a anunciar SIEMPRE tras una desconexion.
            # Sin esto, tras una caida el ESP32 queda invisible
            # y el celular "no lo encuentra" hasta reiniciar la placa.
            self._anunciar()

    def enviar(self, texto):
        buf = texto.encode()
        for conn in self.conexiones:
            try:
                self.ble.gatts_notify(conn, self.handle_tx, buf)
            except OSError:
                # Conexion en mal estado: se limpiara en el IRQ de desconexion
                pass

# ---------- PROGRAMA PRINCIPAL ----------
def main():
    i2c = I2C(0, scl=Pin(PIN_SCL), sda=Pin(PIN_SDA), freq=400_000)
    dispositivos = i2c.scan()
    print("I2C detectado:", [hex(d) for d in dispositivos])
    if MPU_ADDR not in dispositivos:
        print("ERROR: MPU6050 no responde en", hex(MPU_ADDR),
              "- revisar cableado SDA->21, SCL->22, VCC->3V3, GND->GND")
        return

    mpu = MPU6050(i2c)
    ble = ServidorBLE()
    led = Pin(2, Pin.OUT)  # LED azul integrado de la DevKit V1

    periodo_ms = 1000 // FRECUENCIA_HZ
    errores_i2c = 0

    while True:
        inicio = time.ticks_ms()
        try:
            ax, ay = mpu.leer_accel_xy()
            errores_i2c = 0
            if ble.conexiones:
                ble.enviar("{},{}\n".format(ax, ay))
                led.value(1)
            else:
                led.value(time.ticks_ms() // 500 % 2)  # Parpadeo = esperando conexion
        except OSError:
            # Lectura I2C fallida (cable flojo/ruido): no matar el programa
            errores_i2c += 1
            if errores_i2c == 10:
                print("AVISO: 10 errores I2C seguidos - revisar cables del MPU6050")

        # Mantener la cadencia exacta de envio
        transcurrido = time.ticks_diff(time.ticks_ms(), inicio)
        restante = periodo_ms - transcurrido
        if restante > 0:
            time.sleep_ms(restante)

main()
