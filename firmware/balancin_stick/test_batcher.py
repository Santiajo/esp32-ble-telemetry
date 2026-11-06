"""Prueba en el computador el envío por paquetes del firmware, sin placa.

Uso (desde la raíz del repo):  python firmware/balancin_stick/test_batcher.py
Carga main.py con módulos de MicroPython simulados, sin arrancar el bucle principal.
"""
import sys
import types
from pathlib import Path

clock = {'ms': 0}
fake_time = types.SimpleNamespace(
    ticks_ms=lambda: clock['ms'],
    ticks_us=lambda: clock['ms'] * 1000,
    ticks_add=lambda a, b: a + b,
    ticks_diff=lambda a, b: a - b,
    sleep_ms=lambda v: None,
    sleep_us=lambda v: None,
)
sys.modules['time'] = fake_time
sys.modules['bluetooth'] = types.SimpleNamespace(UUID=lambda v: v, FLAG_READ=1, FLAG_NOTIFY=2, FLAG_WRITE=4, FLAG_WRITE_NO_RESPONSE=8)
sys.modules['machine'] = types.SimpleNamespace(I2C=None, Pin=None)
sys.modules['micropython'] = types.SimpleNamespace(const=lambda v: v)

src = (Path(__file__).parent / 'main.py').read_text(encoding='utf-8')
assert src.rstrip().endswith('main()')
ns = {}
exec(compile(src.rstrip()[:-len('main()')], 'main.py', 'exec'), ns)
Batcher = ns['Batcher']


class FakeBle:
    def __init__(self, mtu=185, fail=lambda: False, delay=0):
        self.mtu, self.fail, self.delay = mtu, fail, delay
        self.packets = []
        self.slow_sends = 0

    def fits(self, n):
        return n <= self.mtu - 3

    def send(self, data):
        clock['ms'] += self.delay
        if self.fail():
            return False
        self.packets.append(data)
        return True


def line(i):
    return b'v2,%d,-1234,5678,-4096,-12345,23456,-3456\n' % (1000000 + i * 10)


def feed(batch, n, start=0):
    for i in range(start, start + n):
        clock['ms'] += 10
        batch.add(line(i))


ble = FakeBle()
b = Batcher(ble)
feed(b, 300)
assert len(ble.packets) == 100, len(ble.packets)
assert all(len(p) <= 182 and p.count(b'\n') == 3 and p.endswith(b'\n') for p in ble.packets)
assert b''.join(ble.packets) == b''.join(line(i) for i in range(300)), 'ninguna muestra se pierde ni cambia de orden'
print('100 Hz: 3 muestras por paquete, 33 paquetes por segundo, sin pérdidas')

ble = FakeBle(mtu=100)
b = Batcher(ble)
feed(b, 90)
assert all(len(p) <= 97 for p in ble.packets) and sum(p.count(b'\n') for p in ble.packets) >= 88
print('MTU chico: nunca pasa el tamaño del paquete')

fails = {'n': 1}


def fail_once():
    fails['n'] -= 1
    return fails['n'] == 0


ble = FakeBle(fail=fail_once)
b = Batcher(ble)
feed(b, 3)
assert not ble.packets and b.slow_until is not None
feed(b, 150, 3)  # 1,5 s congestionado
sent = sum(p.count(b'\n') for p in ble.packets)
assert 70 <= sent <= 80, sent
feed(b, 100, 153)  # pasa el tiempo de congestión
assert b.slow_until is None
print('Paquete rechazado: manda la mitad durante 2 s y vuelve a 100 Hz')

ble = FakeBle(delay=80)
b = Batcher(ble)
feed(b, 3)
assert b.slow_until is not None and ble.slow_sends == 1
print('Envío lento: también aligera')
print('OK')
