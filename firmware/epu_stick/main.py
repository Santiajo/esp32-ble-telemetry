# Epu · firmware del stick (MicroPython, Seeed XIAO ESP32-C3 + ICM-42688-P)
#
# Igual que firmware/balancin_stick/main.py (ESP32 DevKit + MPU6050), con otra placa y otro sensor:
#   - Lee el ICM-42688-P (acelerómetro ±8 g, giroscopio ±1000 °/s) a 100 Hz.
#   - Manda la misma línea por BLE (Nordic UART Service), así la app no cambia:
#         v2,<t_ms>,<ax>,<ay>,<az>,<gx>,<gy>,<gz>\n
#     Con ±8 g y ±1000 °/s el ICM-42688-P usa la misma escala que el MPU6050
#     (4096 LSB por g y 32,8 LSB por °/s).
#   - Se anuncia como «Epu-Adulto» o «Epu-Niño» (calendario de la semana y EPU-5).
#   - Sin teléfono conectado, imprime 5 veces por segundo la inclinación en grados
#     (adelante/atrás e izquierda/derecha) y los valores crudos, para la prueba en Thonny.
#   - Con teléfono conectado, imprime un resumen [STATS] cada 2 s.
#   - Al arrancar hace un autodiagnóstico de 3 s con el stick quieto ([DIAG]): tiempo de
#     lectura del sensor, ritmo real y ruido en reposo. Sirve para comparar con el MPU6050
#     (docs/PLAN_EPU.md §7) y con tools/trace_stats.py.
#
# Para el otro stick solo cambia STICK_ROLE.
# Protocolo: docs/PLAN_BALANCIN.md §3. Plan: docs/PLAN_EPU.md.

import time
import math
import struct
import bluetooth
from machine import I2C, SPI, Pin
from micropython import const

# ---------------- Configuración ----------------
STICK_ROLE = 'A'                 # 'A' = adulto · 'B' = niño
DEVICE_NAME = 'Epu-Adulto' if STICK_ROLE == 'A' else 'Epu-Niño'
BUS = 'spi'                      # 'spi' (así está cableado el stick P2) o 'i2c'
# SPI · cableado del stick P2 (verificado en respaldo_p2/main.py y medido el 18-11-2026)
CS_PIN = 5                       # D3
SCK_PIN = 4                      # D2
MISO_PIN = 6                     # D4
MOSI_PIN = 10                    # D10
SPI_HZ = 1_000_000               # a 8 MHz también funciona, pero solo ahorra 0,1 ms por lectura
# I2C (otra forma de cablear el sensor): SDA = D4 (GPIO6), SCL = D5 (GPIO7)
SDA_PIN = 6
SCL_PIN = 7
LED_PIN = 21                     # D6: LED del stick
LED_ACTIVE_LOW = False
SELFTEST_MS = 3000               # autodiagnóstico al arrancar; 0 lo salta
RATE_HZ = 100
BATCH_SAMPLES = 3                # muestras por paquete BLE (3 líneas caben con MTU 185)
CONGESTED_MS = 2000              # tiempo con la mitad de las muestras tras una congestión
SLOW_SEND_MS = 50                # enviar un paquete no debería tardar más que esto
STATS_MS = 2000                  # resumen por la consola cada 2 s, con teléfono conectado
DEBUG_PRINT_HZ = 5               # impresión en consola cuando no hay teléfono conectado
ACC_LSB_PER_G = 4096

# ---------------- ICM-42688-P (banco 0) ----------------
_DEVICE_CONFIG = const(0x11)
_INT_STATUS = const(0x2D)
_REG_BANK_SEL = const(0x76)
_ACCEL_DATA_X1 = const(0x1F)     # 0x1F..0x24 acelerómetro, 0x25..0x2A giroscopio (big-endian)
_PWR_MGMT0 = const(0x4E)
_GYRO_CONFIG0 = const(0x4F)
_ACCEL_CONFIG0 = const(0x50)
_WHO_AM_I = const(0x75)
_ICM_ID = const(0x47)


class BusI2C:
    def __init__(self, i2c, addr):
        self.i2c = i2c
        self.addr = addr
        self._buf = bytearray(12)

    def write(self, reg, val):
        self.i2c.writeto_mem(self.addr, reg, bytes([val]))

    def read1(self, reg):
        return self.i2c.readfrom_mem(self.addr, reg, 1)[0]

    def read12(self, reg):
        self.i2c.readfrom_mem_into(self.addr, reg, self._buf)
        return self._buf

    def name(self):
        return 'I2C 0x%02X' % self.addr


class BusSPI:
    def __init__(self, spi, cs):
        self.spi = spi
        self.cs = cs
        self.cs.value(1)
        self._tx = bytearray(13)     # byte de registro + 12 de relleno
        self._rx = bytearray(13)
        self._mv = memoryview(self._rx)[1:]

    def write(self, reg, val):
        self.cs.value(0)
        self.spi.write(bytes([reg & 0x7F, val]))
        self.cs.value(1)

    def read1(self, reg):
        rx = bytearray(2)
        self.cs.value(0)
        self.spi.write_readinto(bytes([reg | 0x80, 0]), rx)
        self.cs.value(1)
        return rx[1]

    def read12(self, reg):
        self._tx[0] = reg | 0x80
        self.cs.value(0)
        self.spi.write_readinto(self._tx, self._rx)
        self.cs.value(1)
        return self._mv

    def name(self):
        return 'SPI %d MHz' % (SPI_HZ // 1_000_000)


class ICM42688:
    def __init__(self, bus):
        self.bus = bus
        w = bus.write
        w(_DEVICE_CONFIG, 0x01)  # reinicio por software
        time.sleep_ms(20)
        w(_REG_BANK_SEL, 0x00)
        w(_GYRO_CONFIG0, 0x28)   # ±1000 °/s, 100 Hz
        w(_ACCEL_CONFIG0, 0x28)  # ±8 g, 100 Hz
        w(_PWR_MGMT0, 0x0F)      # acelerómetro y giroscopio en bajo ruido
        time.sleep_ms(200)       # el giroscopio necesita ~45 ms para arrancar
        r = bus.read1
        self.ok = r(_GYRO_CONFIG0) == 0x28 and r(_ACCEL_CONFIG0) == 0x28 and r(_PWR_MGMT0) == 0x0F
        self.ready()             # limpia un aviso de dato listo anterior

    def ready(self):
        """El sensor avisa cuando hay una muestra nueva (100 por segundo, con su propio reloj)."""
        return self.bus.read1(_INT_STATUS) & 0x08

    def read(self):
        return struct.unpack('>hhhhhh', self.bus.read12(_ACCEL_DATA_X1))


def open_bus():
    """Abre el bus configurado y comprueba que responda un ICM-42688-P. Devuelve el bus o None."""
    if BUS == 'spi':
        spi = SPI(1, baudrate=SPI_HZ, polarity=0, phase=0,
                  sck=Pin(SCK_PIN), mosi=Pin(MOSI_PIN), miso=Pin(MISO_PIN))
        bus = BusSPI(spi, Pin(CS_PIN, Pin.OUT, value=1))
        who = 0
        for _ in range(3):       # la primera transacción pasa el sensor a modo SPI
            bus.write(_REG_BANK_SEL, 0x00)
            time.sleep_ms(10)
            who = bus.read1(_WHO_AM_I)
            if who == _ICM_ID:
                break
            time.sleep_ms(50)
        print('[SPI] WHO_AM_I = 0x%02X (SCK %d, MISO %d, MOSI %d, CS %d)' % (who, SCK_PIN, MISO_PIN, MOSI_PIN, CS_PIN))
        return bus if who == _ICM_ID else None
    i2c = I2C(0, scl=Pin(SCL_PIN), sda=Pin(SDA_PIN), freq=400_000)
    found = i2c.scan()
    print('[I2C] detectado:', [hex(d) for d in found])
    for addr in (0x68, 0x69):   # 0x69 si AP_AD0 está a 3V3
        if addr in found:
            bus = BusI2C(i2c, addr)
            who = bus.read1(_WHO_AM_I)
            print('[I2C] 0x%02X WHO_AM_I = 0x%02X' % (addr, who))
            if who == _ICM_ID:
                return bus
    return None


def selftest(imu, ms):
    """Con el stick quieto: tiempo de lectura, ritmo y ruido. Mismas métricas que tools/trace_stats.py.
    Suma en marcha (sin guardar las muestras) para no quedarse sin memoria."""
    print('[DIAG] Dejen el stick quieto %d s...' % (ms // 1000))
    n = 0
    s = [0.0] * 6
    s2 = [0.0] * 6
    gsum = 0.0
    worst_us = 0
    total_us = 0
    imu.ready()
    t_end = time.ticks_add(time.ticks_ms(), ms)
    while time.ticks_diff(t_end, time.ticks_ms()) > 0:
        if not imu.ready():
            time.sleep_us(500)
            continue
        t0 = time.ticks_us()
        try:
            r = imu.read()
        except OSError:
            continue
        dt = time.ticks_diff(time.ticks_us(), t0)
        total_us += dt
        worst_us = max(worst_us, dt)
        n += 1
        for k in range(6):
            s[k] += r[k]
            s2[k] += r[k] * r[k]
        gsum += math.sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2])
    if n < 10:
        print('[DIAG] ERROR: solo %d lecturas' % n)
        return
    sd = [math.sqrt(max(0, s2[k] / n - (s[k] / n) ** 2)) for k in range(6)]
    print('[DIAG] bus %s · lectura media %d us, peor %d us · %.1f lecturas/s'
          % (imu.bus.name(), total_us // n, worst_us, n * 1000 / ms))
    print('[DIAG] ruido acel %s mg · ruido giro %s °/s · sesgo giro %s °/s · |g| %.3f'
          % ('/'.join('%.2f' % (sd[k] / ACC_LSB_PER_G * 1000) for k in (0, 1, 2)),
             '/'.join('%.3f' % (sd[k] / 32.8) for k in (3, 4, 5)),
             '/'.join('%+.2f' % (s[k] / n / 32.8) for k in (3, 4, 5)), gsum / n / ACC_LSB_PER_G))


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
        self.slow_sends = 0
        self.packets = 0
        self.bytes_sent = 0
        self.max_send_ms = 0
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
            self._advertise()   # si no, tras una caída el stick queda invisible hasta reiniciarlo
        elif event == _IRQ_MTU_EXCHANGED:
            self.mtu = data[1]
            print('[BLE] MTU negociado:', self.mtu)

    @property
    def connected(self):
        return self.conn is not None

    def fits(self, nbytes):
        return nbytes <= self.mtu - 3

    def send(self, data):
        chunk = self.mtu - 3
        conn = self.conn
        if conn is None:
            return False
        try:
            for i in range(0, len(data), chunk):
                self._ble.gatts_notify(conn, self._tx, data[i:i + chunk])
                self.packets += 1
            self.bytes_sent += len(data)
            return True
        except OSError:
            self.dropped += 1
            return False


class Batcher:
    """Junta muestras en un paquete y aligera el envío si el enlace se congestiona."""

    def __init__(self, ble):
        self.ble = ble
        self.buf = b''
        self.count = 0
        self.slow_until = None
        self.skip = False

    def clear(self):
        self.buf = b''
        self.count = 0

    def add(self, data):
        if self.slow_until is not None:
            if time.ticks_diff(time.ticks_ms(), self.slow_until) >= 0:
                self.slow_until = None
            else:
                self.skip = not self.skip
                if self.skip:
                    return
        if self.count and not self.ble.fits(len(self.buf) + len(data)):
            self.flush()
        self.buf += data
        self.count += 1
        if self.count >= BATCH_SAMPLES:
            self.flush()

    def flush(self):
        t0 = time.ticks_ms()
        ok = self.ble.send(self.buf)
        self.clear()
        took = time.ticks_diff(time.ticks_ms(), t0)
        if took > self.ble.max_send_ms:
            self.ble.max_send_ms = took
        if took > SLOW_SEND_MS:
            self.ble.slow_sends += 1
        if not ok or took > SLOW_SEND_MS:
            self.slow_until = time.ticks_add(time.ticks_ms(), CONGESTED_MS)


# ---------------- Bucle principal ----------------
class Led:
    def __init__(self, pin):
        self.pin = Pin(pin, Pin.OUT) if pin is not None else None

    def set(self, on):
        if self.pin is not None:
            self.pin.value((not on) if LED_ACTIVE_LOW else on)


def tilt_deg(ax, ay, az):
    """Inclinación con el stick vertical (Z hacia arriba): adelante/atrás y izquierda/derecha."""
    fwd = math.degrees(math.atan2(ax, math.sqrt(ay * ay + az * az)))
    side = math.degrees(math.atan2(ay, math.sqrt(ax * ax + az * az)))
    return fwd, side


def fail_forever(led, msg):
    while True:
        print(msg)
        for _ in range(10):
            led.set(1); time.sleep_ms(100)
            led.set(0); time.sleep_ms(100)


def main():
    led = Led(LED_PIN)
    bus = open_bus()
    if bus is None:
        fail_forever(led, 'ERROR: ICM-42688-P no responde por %s. Revisar pines (arriba en Configuración), VCC->3V3, GND->GND'
                     % BUS.upper())
    imu = ICM42688(bus)
    if not imu.ok:
        fail_forever(led, 'ERROR: el ICM-42688-P no guardó la configuración. Revisar cables (MISO/MOSI) y alimentación.')
    print('[ICM] OK por', bus.name())
    if SELFTEST_MS:
        selftest(imu, SELFTEST_MS)
    stick = StickBLE(DEVICE_NAME)
    batch = Batcher(stick)

    debug_every = max(1, RATE_HZ // DEBUG_PRINT_HZ)
    n = 0
    i2c_errors_seq = 0
    t_stats = time.ticks_ms()
    max_loop_ms = 0
    reads = 0
    i2c_errors = 0

    while True:
        # Se lee solo cuando el sensor avisa una muestra nueva: el ritmo lo marca su reloj (100 Hz),
        # sin muestras repetidas ni saltadas por el temporizador del ESP32.
        try:
            if not imu.ready():
                time.sleep_us(500)
                continue
        except OSError:
            i2c_errors += 1
            continue
        t_loop = time.ticks_ms()
        try:
            ax, ay, az, gx, gy, gz = imu.read()
            i2c_errors_seq = 0
            reads += 1
            line = 'v2,%d,%d,%d,%d,%d,%d,%d\n' % (time.ticks_ms(), ax, ay, az, gx, gy, gz)

            if stick.connected:
                led.set(1)
                data = line.encode()
                if stick.fits(len(data)):
                    batch.add(data)
                elif n % 2 == 0:
                    stick.send(data)   # MTU chico: 50 Hz, una línea por paquete
            else:
                batch.clear()
                led.set(time.ticks_ms() // 500 % 2)  # parpadeo = esperando teléfono
                if n % debug_every == 0:
                    fwd, side = tilt_deg(ax, ay, az)
                    g = math.sqrt(ax * ax + ay * ay + az * az) / ACC_LSB_PER_G
                    print('adelante %+6.1f°  lado %+6.1f°  |g| %.2f  ·  %s' % (fwd, side, g, line), end='')
        except OSError:
            i2c_errors_seq += 1
            i2c_errors += 1
            if i2c_errors_seq == 10:
                print('AVISO: 10 errores I2C seguidos - revisar cables del ICM-42688-P')

        n += 1
        took = time.ticks_diff(time.ticks_ms(), t_loop)
        if took > max_loop_ms:
            max_loop_ms = took
        if time.ticks_diff(time.ticks_ms(), t_stats) >= STATS_MS:
            if stick.connected:
                print('[STATS] lecturas', reads, 'paquetes', stick.packets, 'bytes', stick.bytes_sent, 'rechazados', stick.dropped,
                      'lentos', stick.slow_sends, 'envio_max_ms', stick.max_send_ms, 'vuelta_max_ms', max_loop_ms,
                      'i2c', i2c_errors, 'mtu', stick.mtu, 'mitad', batch.slow_until is not None)
            t_stats = time.ticks_ms()
            max_loop_ms = 0
            reads = 0
            i2c_errors = 0
            stick.packets = 0
            stick.bytes_sent = 0
            stick.max_send_ms = 0
            stick.dropped = 0
            stick.slow_sends = 0


main()
