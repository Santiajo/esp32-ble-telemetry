"""Compara sticks a partir de trazas .trace (las graba el banco de la app) o de la consola de Thonny.

Uso:  python tools/trace_stats.py archivo1.trace [archivo2.trace ...]

Por archivo informa:
  - Ritmo: muestras por segundo según t_ms del stick, y huecos > 30 ms.
  - Llegada al teléfono (si la traza la tiene): retraso relativo y cortes > 150 ms.
  - Reposo: la ventana de 1 s más quieta (menor variación del giroscopio); en ella,
    ruido del acelerómetro (mg, desviación) y del giroscopio (°/s), sesgo del giroscopio
    (°/s, cuánto marca quieto) y |g|.
Escalas del protocolo v2: 4096 LSB por g y 32,8 LSB por °/s (MPU6050 y ICM-42688-P iguales).
"""
import math
import statistics as st
import sys

ACC = 4096.0
GYR = 32.8


def load(path):
    rows = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            arr = None
            if '\t' in line:
                a, line = line.split('\t', 1)
                arr = float(a)
            i = line.find('v2,')
            if i < 0:
                continue
            p = line[i:].split(',')
            if len(p) < 8:
                continue
            try:
                t, ax, ay, az, gx, gy, gz = (int(x) for x in p[1:8])
            except ValueError:
                continue
            rows.append((arr, t, ax, ay, az, gx, gy, gz))
    return rows


def quietest(rows, span_ms=1000):
    best = None
    j = 0
    for i in range(len(rows)):
        while j < len(rows) and rows[j][1] - rows[i][1] < span_ms:
            j += 1
        w = rows[i:j]
        if len(w) < 5 or rows[j - 1][1] - rows[i][1] < span_ms * 0.8:
            continue
        score = sum(st.pstdev([r[k] for r in w]) for k in (5, 6, 7))
        if best is None or score < best[0]:
            best = (score, w)
    return best[1] if best else None


def report(path):
    rows = load(path)
    print('==', path, '·', len(rows), 'muestras')
    if len(rows) < 10:
        print('   muy pocas muestras')
        return
    ts = [r[1] for r in rows]
    dur = (ts[-1] - ts[0]) / 1000
    gaps = [b - a for a, b in zip(ts, ts[1:])]
    print('   ritmo: %.1f muestras/s en %.1f s · paso mediano %d ms · huecos >30 ms: %d (máx %d ms)'
          % ((len(rows) - 1) / dur if dur else 0, dur, st.median(gaps), sum(g > 30 for g in gaps), max(gaps)))
    arr = [r[0] for r in rows if r[0] is not None]
    if len(arr) == len(rows) and any(a != t for a, t in zip(arr, ts)):
        lag = [a - t for a, t in zip(arr, ts)]
        base = min(lag)
        rel = [x - base for x in lag]
        agaps = [b - a for a, b in zip(arr, arr[1:])]
        print('   llegada: retraso relativo mediano %.0f ms · p95 %.0f ms · cortes >150 ms: %d (máx %.0f ms)'
              % (st.median(rel), sorted(rel)[int(len(rel) * .95)], sum(g > 150 for g in agaps), max(agaps)))
    w = quietest(rows)
    if not w:
        print('   sin ventana quieta de 1 s')
        return
    col = lambda k: [r[k] for r in w]
    acc_sd = [st.pstdev(col(k)) / ACC * 1000 for k in (2, 3, 4)]
    gyr_sd = [st.pstdev(col(k)) / GYR for k in (5, 6, 7)]
    gyr_b = [st.mean(col(k)) / GYR for k in (5, 6, 7)]
    g = st.mean(math.sqrt(r[2] ** 2 + r[3] ** 2 + r[4] ** 2) / ACC for r in w)
    print('   reposo (%d muestras): ruido acel %s mg · ruido giro %s °/s · sesgo giro %s °/s · |g| %.3f'
          % (len(w), '/'.join('%.1f' % x for x in acc_sd), '/'.join('%.2f' % x for x in gyr_sd),
             '/'.join('%+.1f' % x for x in gyr_b), g))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    for p in sys.argv[1:]:
        report(p)
