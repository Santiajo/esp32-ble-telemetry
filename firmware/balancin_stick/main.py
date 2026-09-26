# Balancín · firmware del stick (MicroPython, ESP32 DevKit V1 + MPU6050)
#
# Qué hace:
#   - Lee el MPU6050 (acelerómetro ±8 g, giroscopio ±1000 °/s) a 100 Hz.
#   - Lo envía por BLE (Nordic UART Service) como texto, una línea por muestra:
#         v2,<t_ms>,<ax>,<ay>,<az>,<gx>,<gy>,<gz>\n
#     t_ms = time.ticks_ms() del ESP32 (se reinicia cada 2^30 ms ≈ 12 días; la app lo maneja).
#   - Si el teléfono negocia un MTU chico (la línea no cabe en un paquete), baja a 50 Hz
#     para no saturar la pila BLE (el firmware antiguo documentó desconexiones sobre ~66 Hz).
#   - LED azul (GPIO2): parpadea = esperando teléfono · fijo = conectado ·
#     parpadeo rápido = MPU6050 no encontrado (revisar cables).
#   - Sin teléfono conectado, imprime 5 muestras por segundo en la consola de Thonny.
#
# Para el otro stick solo cambia STICK_ROLE a 'A'.
# Protocolo completo: docs/PLAN_BALANCIN.md §3.
# Versión anterior (rawX,rawY a 50 Hz): firmware/legacy/main.py

import time
import struct
import bluetooth
from machine import I2C, Pin
from micropython import const

# ---------------- Configuración ----------------
STICK_ROLE = 'B'                 # 'A' = stick grande (adulto) · 'B' = stick pequeño (niño)
DEVICE_NAME = 'ESP32-BAL-' + STICK_ROLE   # debe empezar con "ESP32" (filtro de la app)
SDA_PIN = 21                     # pines I2C por defecto de la DevKit V1
SCL_PIN = 22
LED_PIN = 2                      # LED azul integrado de la DevKit V1
RATE_HZ = 100
DEBUG_PRINT_HZ = 5               # impresión en consola cuando no hay teléfono conectado

# LEGACY_OUTPUT = True envía "rawX,rawY\n" (escalado a ±2 g, como el firmware antiguo) a 50 Hz,
# para probar con la app actual (estación BLE) antes de la fase 2. Normalmente False.
LEGACY_OUTPUT = False

# ---------------- MPU6050 ----------------
_PWR_MGMT_1 = const(0x6B)
_SMPLRT_DIV = const(0x19)
_CONFIG = const(0x1A)
_GYRO_CONFIG = const(0x1B)
_ACCEL_CONFIG = const(0x1C)
_ACCEL_XOUT_H = const(0x3B)


class MPU6050:
    def __init__(self, i2c, addr):
        self.i2c = i2c
        self.addr = addr
        w = self._write
        w(_PWR_MGMT_1, 0x01)   # despertar, reloj del giroscopio X (más estable que el interno)
        time.sleep_ms(100)
        w(_CONFIG, 0x03)       # DLPF ~44 Hz: filtra ruido en hardware
        w(_SMPLRT_DIV, 0x09)   # 1 kHz / (1 + 9) = 100 Hz
        w(_GYRO_CONFIG, 0x10)  # ±1000 °/s  (32.8 LSB por °/s)
        w(_ACCEL_CONFIG, 0x10) # ±8 g       (4096 LSB por g)
        self._buf = bytearray(14)

    def _write(self, reg, val):
        self.i2c.writeto_mem(self.addr, reg, bytes([val]))

    def read(self):
        self.i2c.readfrom_mem_into(self.addr, _ACCEL_XOUT_H, self._buf)
        ax, ay, az, _temp, gx, gy, gz = struct.unpack('>hhhhhhh', self._buf)
        return ax, ay, az, gx, gy, gz


def find_mpu(i2c):
    found = i2c.scan()
    print('[I2C] detectado:', [hex(d) for d in found])
    for addr in (0x68, 0x69):   # 0x69 si AD0 está a 3V3
        if addr in found:
            return addr
    return None


# ---------------- BLE: Nordic UART Service ----------------
_IRQ_CENTRAL_CONNECT = const(1)
_IRQ_CENTRAL_DISCONNECT = const(2)
_IRQ_MTU_EXCHANGED = const(21)

_NUS_UUID = bluetooth.UUID('6E400001-B5A3-F393-E0A9-E50E24DCCA9E')
_NUS_TX = (bluetooth.UUID('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'), bluetooth.FLAG_READ | bluetooth.FLAG_NOTIFY)
_NUS_RX = (bluetooth.UUID('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'), bluetooth.FLAG_WRITE | bluetooth.FLAG_WRITE_NO_RESPONSE)
_NUS_SERVICE = (_NUS_UUID, (_NUS_TX, _NUS_RX))


def _adv_field(adv_type, value):
    return bytes((len(value) + 1, adv_type)) + value


class StickBLE:
    def __init__(self, name):
        self.name = name
        self.conn = None
        self.mtu = 23
        self.dropped = 0
        self._ble = bluetooth.BLE()
        self._ble.active(True)
        self._ble.config(gap_name=name)
        try:
            self._ble.config(mtu=185)  # tamaño preferido; el teléfono decide el final
        except Exception:
            pass
        self._ble.irq(self._irq)
        ((self._tx, self._rx),) = self._ble.gatts_register_services((_NUS_SERVICE,))
        # El nombre va en el anuncio; el UUID de 128 bits en la respuesta de escaneo (no caben juntos en 31 bytes).
        self._adv = _adv_field(0x01, b'\x06') + _adv_field(0x09, name.encode())
        self._resp = _adv_field(0x07, bytes(_NUS_UUID))
        self._advertise()

    def _advertise(self):
        # Intervalo 100 ms: anuncio agresivo = conexión más rápida
        self._ble.gap_advertise(100_000, adv_data=self._adv, resp_data=self._resp)
        print('[BLE] Anunciando como', self.name)

    def _irq(self, event, data):
        if event == _IRQ_CENTRAL_CONNECT:
            self.conn = data[0]
            self.mtu = 23
            print('[BLE] Teléfono conectado')
        elif event == _IRQ_CENTRAL_DISCONNECT:
            self.conn = None
            print('[BLE] Teléfono desconectado. Re-anunciando...')
            # Volver a anunciar SIEMPRE: si no, tras una caída el stick queda invisible hasta reiniciarlo.
            self._advertise()
        elif event == _IRQ_MTU_EXCHANGED:
            self.mtu = data[1]
            print('[BLE] MTU negociado:', self.mtu)

    @property
    def connected(self):
        return self.conn is not None

    def fits(self, nbytes):
        return nbytes <= self.mtu - 3

    def send(self, data):
        # Si la línea no cabe en un paquete se parte en trozos; la app la vuelve a unir por '\n'.
        chunk = self.mtu - 3
        conn = self.conn
        if conn is None:
            return
        try:
            for i in range(0, len(data), chunk):
                self._ble.gatts_notify(conn, self._tx, data[i:i + chunk])
        except OSError:
            # Cola BLE llena o conexión cayéndose: se descarta la muestra
            # (la app descarta la línea incompleta; el IRQ limpia la conexión).
            self.dropped += 1


# ---------------- Bucle principal ----------------
def blink_forever(led, period_ms):
    while True:
        led.value(not led.value())
        time.sleep_ms(period_ms)


def main():
    led = Pin(LED_PIN, Pin.OUT)
    i2c = I2C(0, scl=Pin(SCL_PIN), sda=Pin(SDA_PIN), freq=400_000)
    addr = find_mpu(i2c)
    if addr is None:
        print('ERROR: MPU6050 no responde. Revisar cableado SDA->%d, SCL->%d, VCC->3V3, GND->GND'
              % (SDA_PIN, SCL_PIN))
        blink_forever(led, 100)
    mpu = MPU6050(i2c, addr)
    print('[MPU] OK en dirección 0x%02X' % addr)
    stick = StickBLE(DEVICE_NAME)

    period_us = 1_000_000 // RATE_HZ
    debug_every = max(1, RATE_HZ // DEBUG_PRINT_HZ)
    n = 0
    i2c_errors_seq = 0
    t_next = time.ticks_us()

    while True:
        try:
            ax, ay, az, gx, gy, gz = mpu.read()
            i2c_errors_seq = 0
            if LEGACY_OUTPUT:
                clamp = lambda v: max(-32768, min(32767, v * 4))  # ±8 g → escala ±2 g
                line = '%d,%d\n' % (clamp(ax), clamp(ay))
            else:
                line = 'v2,%d,%d,%d,%d,%d,%d,%d\n' % (time.ticks_ms(), ax, ay, az, gx, gy, gz)

            if stick.connected:
                led.value(1)
                data = line.encode()
                # A 100 Hz solo si la línea cabe en un paquete; si no (o en modo legado), 50 Hz.
                full_rate = stick.fits(len(data)) and not LEGACY_OUTPUT
                if full_rate or n % 2 == 0:
                    stick.send(data)
            else:
                led.value(time.ticks_ms() // 500 % 2)  # parpadeo = esperando teléfono
                if n % debug_every == 0:
                    print(line, end='')
        except OSError:
            # Lectura I2C fallida (cable flojo / ruido): no matar el programa
            i2c_errors_seq += 1
            if i2c_errors_seq == 10:
                print('AVISO: 10 errores I2C seguidos - revisar cables del MPU6050')

        n += 1
        if n % (RATE_HZ * 10) == 0 and stick.dropped:
            print('[BLE] muestras descartadas por cola llena:', stick.dropped)

        t_next = time.ticks_add(t_next, period_us)
        wait = time.ticks_diff(t_next, time.ticks_us())
        if wait > 0:
            time.sleep_us(wait)
        else:
            t_next = time.ticks_us()  # nos atrasamos: se resincroniza sin acumular deuda


main()
