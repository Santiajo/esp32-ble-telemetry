# ==============================================================================
# XIAO ESP32-C3 + ICM-42688-P -> Streaming BLE (Nordic UART Service)
# Compatible con Adafruit Bluefruit LE Connect (UART y Plotter)
# Nombre BLE: "P1 - Niño"
#
# NOTA: No escribe archivos CSV en la flash; envia los datos en vivo por BLE.
#
# Conexiones verificadas (por cable):
#   CS   = D3  (GPIO5)
#   SCK  = D4  (GPIO6)
#   MISO = D5  (GPIO7)
#   MOSI = D10 (GPIO10)
#   LED  = D6  (GPIO21) - indicador de estado (opcional)
#
# Estados del LED (D6):
#   - Parpadeo lento (0.5 s): anunciando BLE, esperando telefono
#   - Encendido fijo:         conectado (esperando, pausado o sin sensor)
#   - Parpadeo rapido:        transmitiendo muestras por BLE
#
# Comandos desde Bluefruit UART:
#   START | STOP | RAW | PLOT | HEX | PHYS | RATE <hz> | HDR | HELP
# ==============================================================================

from machine import Pin, SPI
from micropython import const
import bluetooth
import binascii
import gc
import struct
import time

# ------------------------------------------
# 1. CONSTANTES Y PINES
# ------------------------------------------

BLE_NAME = "P1 - Niño"

CS_PIN = const(5)       # D3
SCK_PIN = const(6)      # D4
MOSI_PIN = const(10)    # D10
MISO_PIN = const(7)     # D5
LED_PIN = const(21)     # D6

# Registros ICM-42688-P (banco 0)
REG_BANK_SEL = const(0x76)
WHO_AM_I = const(0x75)
DEVICE_CONFIG = const(0x11)
INT_STATUS = const(0x2D)
PWR_MGMT0 = const(0x4E)
GYRO_CONFIG0 = const(0x4F)
ACCEL_CONFIG0 = const(0x50)
ACCEL_DATA_X1 = const(0x1F)
DATA_RDY_INT = const(0x08)

# Configuracion: +/-4g, +/-250 dps, 100 Hz, Low Noise
GYRO_CFG = const(0x68)
ACCEL_CFG = const(0x48)
PWR_LN = const(0x0F)

SENS_ACC = 8192.0
SENS_GYR = 131.072
G = 9.80665

# BLE IRQ (NimBLE ESP32)
_IRQ_CENTRAL_CONNECT = const(1)
_IRQ_CENTRAL_DISCONNECT = const(2)
_IRQ_GATTS_WRITE = const(3)
_IRQ_MTU_EXCHANGED = const(21)

_NUS_UUID = bluetooth.UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
_NUS_RX = (
    bluetooth.UUID("6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
    bluetooth.FLAG_WRITE | bluetooth.FLAG_WRITE_NO_RESPONSE,
)
_NUS_TX = (
    bluetooth.UUID("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"),
    bluetooth.FLAG_NOTIFY | bluetooth.FLAG_READ,
)

# Modos de salida
MODE_RAW = const(0)
MODE_HEX = const(1)
MODE_PHYS = const(2)
MODE_PLOT = const(3)

ZERO12 = b"\x00" * 12
FF12 = b"\xff" * 12

# ------------------------------------------
# 2. HARDWARE SPI + SENSOR
# ------------------------------------------

led = Pin(LED_PIN, Pin.OUT, value=0)
cs = Pin(CS_PIN, Pin.OUT, value=1)
spi = SPI(
    1,
    baudrate=1000000,
    polarity=0,
    phase=0,
    bits=8,
    sck=Pin(SCK_PIN),
    mosi=Pin(MOSI_PIN),
    miso=Pin(MISO_PIN),
)

_tx_status = bytearray([INT_STATUS | 0x80, 0])
_rx_status = bytearray(2)
_tx_data = bytearray(13)
_tx_data[0] = ACCEL_DATA_X1 | 0x80
_rx_data = bytearray(13)


def _reg_read(reg, n=1):
    tx = bytearray(n + 1)
    rx = bytearray(n + 1)
    tx[0] = reg | 0x80
    cs.value(0)
    try:
        spi.write_readinto(tx, rx)
    finally:
        cs.value(1)
    return bytes(rx[1:])


def _reg_write(reg, val):
    cs.value(0)
    try:
        spi.write(bytes([reg & 0x7F, val]))
    finally:
        cs.value(1)


def init_imu():
    who = 0
    for _ in range(3):
        _reg_write(REG_BANK_SEL, 0x00)
        time.sleep_ms(10)
        who = _reg_read(WHO_AM_I)[0]
        if who == 0x47:
            break
        time.sleep_ms(50)
    else:
        return False, "ICM-42688-P no detectado (WHO_AM_I=%s)" % hex(who)

    _reg_write(DEVICE_CONFIG, 0x01)
    time.sleep_ms(20)
    _reg_write(REG_BANK_SEL, 0x00)
    time.sleep_ms(2)

    _reg_write(GYRO_CONFIG0, GYRO_CFG)
    time.sleep_ms(2)
    _reg_write(ACCEL_CONFIG0, ACCEL_CFG)
    time.sleep_ms(2)
    _reg_write(PWR_MGMT0, PWR_LN)
    time.sleep_ms(200)

    if (
        _reg_read(PWR_MGMT0)[0] != PWR_LN
        or _reg_read(GYRO_CONFIG0)[0] != GYRO_CFG
        or _reg_read(ACCEL_CONFIG0)[0] != ACCEL_CFG
    ):
        return False, "Error verificando registros del ICM-42688-P"

    _data_ready()
    return True, "OK"


def _data_ready():
    cs.value(0)
    try:
        spi.write_readinto(_tx_status, _rx_status)
    finally:
        cs.value(1)
    return _rx_status[1] & DATA_RDY_INT


def _read_sample_into(buf13):
    cs.value(0)
    try:
        spi.write_readinto(_tx_data, buf13)
    finally:
        cs.value(1)


# ------------------------------------------
# 3. SERVICIO BLE NORDIC UART (BLUEFRUIT)
# ------------------------------------------

def _build_adv_payloads(name):
    name_b = name.encode("utf-8")
    adv = bytearray(b"\x02\x01\x06")
    adv.extend(bytes([1 + len(name_b), 0x09]))
    adv.extend(name_b)

    uuid_b = bytes(_NUS_UUID)
    resp = bytearray([1 + len(uuid_b), 0x07])
    resp.extend(uuid_b)
    return adv, resp


class BluefruitIMU:
    def __init__(self, imu_ok, imu_msg):
        self.imu_ok = imu_ok
        self.imu_msg = imu_msg

        self.ble = bluetooth.BLE()
        self.ble.active(True)
        self.ble.config(gap_name=BLE_NAME, mtu=247)
        self.ble.irq(self._irq)

        ((self._h_tx, self._h_rx),) = self.ble.gatts_register_services(
            ((_NUS_UUID, (_NUS_TX, _NUS_RX)),)
        )
        self.ble.gatts_set_buffer(self._h_rx, 128, False)

        self._adv, self._resp = _build_adv_payloads(BLE_NAME)

        self.conn = None
        self.conn_ms = 0
        self.mtu_payload = 20
        self.streaming = True
        self.mode = MODE_RAW
        self.divider = 1
        self.pending_cmds = []
        self.greeted = False
        self.rx_drops = 0

        self._start_adv()

    def _start_adv(self):
        self.ble.gap_advertise(100_000, adv_data=self._adv, resp_data=self._resp)

    def _irq(self, event, data):
        if event == _IRQ_CENTRAL_CONNECT:
            conn_handle, _, _ = data
            self.conn = conn_handle
            self.conn_ms = time.ticks_ms()
            self.mtu_payload = 20
            self.greeted = False
            self.streaming = True
            self.pending_cmds.clear()
            self.ble.gap_advertise(None)

        elif event == _IRQ_CENTRAL_DISCONNECT:
            self.conn = None
            self.greeted = False
            self.pending_cmds.clear()
            self._start_adv()

        elif event == _IRQ_MTU_EXCHANGED:
            _, mtu = data
            if mtu > 23:
                self.mtu_payload = min(mtu - 3, 244)

        elif event == _IRQ_GATTS_WRITE:
            conn_handle, attr_handle = data
            if conn_handle == self.conn and attr_handle == self._h_rx:
                raw = self.ble.gatts_read(self._h_rx)
                if raw:
                    self.pending_cmds.append(raw.decode("utf-8", "ignore"))

    def send_bytes(self, buf):
        if self.conn is None or not buf:
            return True
        mv = memoryview(buf)
        step = self.mtu_payload
        i = 0
        n = len(buf)
        while i < n:
            if self.conn is None:
                return False
            end = i + step
            if end > n:
                end = n
            ok = False
            for _ in range(6):
                try:
                    self.ble.gatts_notify(self.conn, self._h_tx, mv[i:end])
                    ok = True
                    break
                except OSError:
                    time.sleep_ms(4)
            if not ok:
                return False
            i = end
            if i < n:
                time.sleep_ms(3)
        return True

    def send_text(self, txt):
        return self.send_bytes(txt.encode("utf-8"))

    def handle_commands(self):
        while self.pending_cmds:
            cmd = self.pending_cmds.pop(0).strip().upper()
            for part in cmd.splitlines():
                p = part.strip()
                if not p:
                    continue
                if p == "STOP":
                    self.streaming = False
                    self.send_text("# PAUSADO\n")
                elif p == "START":
                    self.streaming = True
                    self.send_text("# INICIADO\n")
                elif p == "RAW":
                    self.mode = MODE_RAW
                    self.send_text("# MODO=RAW (t_ms,ax,ay,az,gx,gy,gz int16)\n")
                elif p == "HEX":
                    self.mode = MODE_HEX
                    self.send_text("# MODO=HEX (t_ms,24hex)\n")
                elif p == "PHYS":
                    self.mode = MODE_PHYS
                    self.send_text("# MODO=PHYS (t_ms,ax_ms2,ay,az,gx_dps,gy,gz)\n")
                elif p == "PLOT":
                    self.mode = MODE_PLOT
                    self.send_text("# MODO=PLOT (ax,ay,az,gx,gy,gz)\n")
                elif p == "HDR":
                    self.send_header()
                elif p.startswith("RATE"):
                    tokens = p.split()
                    if len(tokens) == 2 and tokens[1].isdigit():
                        hz = int(tokens[1])
                        if hz in (100, 50, 25, 20, 10, 5, 1):
                            self.divider = 100 // hz
                            self.send_text("# RATE=%d Hz\n" % hz)
                        else:
                            self.send_text("# RATE validos: 100,50,25,20,10,5,1\n")
                elif p == "HELP" or p == "?":
                    self.send_text(
                        "# %s | ICM-42688-P\n"
                        "# Cmds: START, STOP, RAW, PLOT, HEX, PHYS, RATE <hz>, HDR\n"
                        % BLE_NAME
                    )

    def send_header(self):
        if self.mode == MODE_RAW:
            self.send_text("# t_ms,ax,ay,az,gx,gy,gz | 8192 LSB/g, 131.072 LSB/dps\n")
        elif self.mode == MODE_PLOT:
            self.send_text("# ax,ay,az,gx,gy,gz (int16)\n")
        elif self.mode == MODE_HEX:
            self.send_text("# t_ms,raw12_hex\n")
        else:
            self.send_text("# t_ms,ax_ms2,ay_ms2,az_ms2,gx_dps,gy_dps,gz_dps\n")


# ------------------------------------------
# 4. BUCLE PRINCIPAL (RING BUFFER + WATCHDOG)
# ------------------------------------------

def format_sample(mode, t_ms, mv12):
    if mode == MODE_HEX:
        return "%d,%s\n" % (t_ms, binascii.hexlify(mv12).decode())
    ax, ay, az, gx, gy, gz = struct.unpack(">hhhhhh", mv12)
    if mode == MODE_RAW:
        return "%d,%d,%d,%d,%d,%d,%d\n" % (t_ms, ax, ay, az, gx, gy, gz)
    if mode == MODE_PLOT:
        return "%d,%d,%d,%d,%d,%d\n" % (ax, ay, az, gx, gy, gz)
    return "%d,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f\n" % (
        t_ms,
        ax * G / SENS_ACC,
        ay * G / SENS_ACC,
        az * G / SENS_ACC,
        gx / SENS_GYR,
        gy / SENS_GYR,
        gz / SENS_GYR,
    )


def main():
    print("Iniciando %s (BLE + ICM-42688-P)..." % BLE_NAME)
    imu_ok, imu_msg = init_imu()
    print("IMU:", imu_ok, imu_msg)

    app = BluefruitIMU(imu_ok, imu_msg)
    print("BLE anunciando como:", BLE_NAME)

    CAP = 128
    ring_raw = bytearray(CAP * 12)
    mv_ring = memoryview(ring_raw)
    ring_t = [0] * CAP
    head = 0
    tail = 0
    count = 0
    sample_idx = 0
    bad_spi_streak = 0

    t0_ms = time.ticks_ms()
    last_led_ms = t0_ms
    last_flush_ms = t0_ms
    last_data_ms = t0_ms
    last_retry_ms = t0_ms
    out_chunks = []
    out_bytes = 0

    while True:
        now = time.ticks_ms()

        # Sin cliente BLE conectado: anunciar y parpadear LED lento
        if app.conn is None:
            head = tail = count = 0
            out_chunks.clear()
            out_bytes = 0
            if time.ticks_diff(now, last_led_ms) >= 500:
                led.value(0 if led.value() else 1)
                last_led_ms = now
            # Si el sensor fallo al arrancar, seguir intentando en segundo plano
            if not app.imu_ok and time.ticks_diff(now, last_retry_ms) >= 2000:
                app.imu_ok, app.imu_msg = init_imu()
                last_retry_ms = now
                if app.imu_ok:
                    print("IMU recuperado:", app.imu_msg)
            time.sleep_ms(20)
            continue

        # Esperar margen tras conexion para descubrimiento GATT / CCCD / MTU
        if not app.greeted:
            led.value(1)  # Encendido fijo mientras conecta (no parece apagado)
            if time.ticks_diff(now, app.conn_ms) >= 800:
                if app.imu_ok:
                    ok = app.send_text(
                        "# Conectado a %s (MTU=%d)\n" % (BLE_NAME, app.mtu_payload + 3)
                    )
                    if ok:
                        app.send_header()
                        app.greeted = True
                        t0_ms = time.ticks_ms()
                        last_data_ms = t0_ms
                        _data_ready()
                else:
                    if app.send_text("# ERROR SENSOR: " + app.imu_msg + "\n"):
                        app.greeted = True
                        last_retry_ms = now
            time.sleep_ms(15)
            continue

        # Procesar comandos desde la app
        if app.pending_cmds:
            app.handle_commands()

        # Si el sensor fallo o esta en pausa: LED encendido fijo + reintento cada 2 s
        if not app.imu_ok or not app.streaming:
            led.value(1)
            if not app.imu_ok and time.ticks_diff(now, last_retry_ms) >= 2000:
                last_retry_ms = now
                app.imu_ok, app.imu_msg = init_imu()
                if app.imu_ok:
                    app.send_text("# SENSOR RECUPERADO\n")
                    last_data_ms = time.ticks_ms()
                else:
                    app.send_text("# SENSOR SIN RESPUESTA: " + app.imu_msg + "\n")
            time.sleep_ms(20)
            continue

        # Adquirir muestras listas del sensor hacia el ring buffer
        if _data_ready():
            _read_sample_into(_rx_data)
            raw12 = bytes(memoryview(_rx_data)[1:13])
            if raw12 == ZERO12 or raw12 == FF12:
                bad_spi_streak += 1
                if bad_spi_streak >= 10:
                    app.imu_ok = False
                    app.imu_msg = "Trama SPI invalida (posible falso contacto)"
                    app.send_text("# ERROR SPI: " + app.imu_msg + "\n")
                    bad_spi_streak = 0
                    last_retry_ms = now
                    continue
            else:
                bad_spi_streak = 0
                last_data_ms = now
                sample_idx += 1
                if (sample_idx % app.divider) == 0:
                    t_rel = time.ticks_diff(now, t0_ms)
                    off = head * 12
                    mv_ring[off:off + 12] = raw12
                    ring_t[head] = t_rel
                    head = (head + 1) % CAP
                    if count == CAP:
                        tail = (tail + 1) % CAP
                        app.rx_drops += 1
                    else:
                        count += 1
        elif time.ticks_diff(now, last_data_ms) >= 500:
            # Timeout de DATA_RDY: reintentar sensor y avisar por BLE
            app.imu_ok, app.imu_msg = init_imu()
            last_data_ms = time.ticks_ms()
            if not app.imu_ok:
                app.send_text("# SENSOR SIN DATOS: " + app.imu_msg + "\n")
                last_retry_ms = last_data_ms
                continue

        # Empaquetar solo lineas completas sin superar mtu_payload (si MTU >= 40)
        # Si MTU es pequeno (20 bytes), enviar 1 sola linea por turno
        if count > 0:
            if app.mtu_payload >= 40:
                while count > 0:
                    off = tail * 12
                    b_line = format_sample(app.mode, ring_t[tail], mv_ring[off:off + 12]).encode("utf-8")
                    if out_bytes > 0 and out_bytes + len(b_line) > app.mtu_payload:
                        break
                    out_chunks.append(b_line)
                    out_bytes += len(b_line)
                    tail = (tail + 1) % CAP
                    count -= 1
                    if out_bytes >= app.mtu_payload - 32:
                        break
            else:
                if out_bytes == 0:
                    off = tail * 12
                    b_line = format_sample(app.mode, ring_t[tail], mv_ring[off:off + 12]).encode("utf-8")
                    out_chunks.append(b_line)
                    out_bytes = len(b_line)
                    tail = (tail + 1) % CAP
                    count -= 1

        if out_bytes > 0 and (
            app.mtu_payload < 40
            or out_bytes >= app.mtu_payload - 32
            or time.ticks_diff(now, last_flush_ms) >= 45
        ):
            payload = b"".join(out_chunks)
            out_chunks.clear()
            out_bytes = 0
            app.send_bytes(payload)
            last_flush_ms = now
            if time.ticks_diff(now, last_led_ms) >= 120:
                led.value(0 if led.value() else 1)
                last_led_ms = now
        else:
            time.sleep_ms(1)

        if (sample_idx & 0xFF) == 0 and gc.mem_free() < 30000:
            gc.collect()


if __name__ == "__main__":
    main()
