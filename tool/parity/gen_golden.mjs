// Genera los datos de referencia de paridad entre el prototipo v2 y el motor Dart.
//
// Extrae del prototipo (reference/mecanica-v2/index.html) el código del motor
// TAL CUAL —clase Stick, syncDist, leadLag, startSession, frame, report…—
// por rango de líneas, lo ejecuta con un reloj y temporizadores falsos, y
// guarda muestras de cada escenario en test/balancin_v2/golden/proto_scenarios.json.
// La UI y la vibración se reemplazan por stubs (v2 no vibra: decisión V3). Del audio
// se ejecuta el código real (audioUpdate, detune, vSilence, loopStart) sobre nodos
// falsos que registran cada setTargetAtTime y cada AU.tone.
//
// Uso (desde la raíz del repo):  node tool/parity/gen_golden.mjs

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const SRC = 'reference/mecanica-v2/index.html';
const OUT = 'test/balancin_v2/golden/proto_scenarios.json';
const lines = readFileSync(SRC, 'utf8').split(/\r?\n/);
const take = (a, b) => lines.slice(a - 1, b).join('\n');

// Rangos de líneas (1 = primera línea del archivo). Si el prototipo cambia, revisar.
const RANGES = [
  [2708, 2711], // clamp, hz, f1, mean
  [2714, 2715], // NN, PA, PC
  [2718, 2719], // P_DEF, P
  [2722, 2737], // REL_N, LEVELS, GN, guideOf, progreso
  [2824, 2825], // vSilence, detune
  [2828, 2829], // loopIv, loopStart (pad)
  [2843, 2865], // class Stick, ST, A, C
  [2887, 2904], // synth, feedPlane, synthDrive
  [2907, 2936], // G, curLevel…, syncDist, target, leadLag, newLT
  [2938, 2971], // startSession … levelComplete
  [2975, 3001], // frame
  [3004, 3014], // audioUpdate
  [3093, 3098], // report
  [3101, 3111], // sessionRecord, closeSession
];
const code = RANGES.map(([a, b]) => take(a, b)).join('\n');

function makeProto() {
  const env = { clock: 0, timers: [], seq: 0, events: [], tones: [], closed: null };
  const param = () => ({ target: null, tau: null, setTargetAtTime(v, t, tau) { this.target = v; this.tau = tau; } });
  const node = () => ({ frequency: param(), gain: param() });
  const stubs = {
    performance: { now: () => env.clock },
    setTimeout: (fn, ms) => { env.timers.push({ due: env.clock + ms, seq: env.seq++, fn }); return env.seq; },
    setInterval: (fn, ms) => { const id = ++env.seq; env.timers.push({ due: env.clock + ms, seq: id, fn, period: ms, id }); return id; },
    clearInterval: id => { env.timers = env.timers.filter(t => t.id !== id || !id); },
    $: () => ({ textContent: '', style: { setProperty() { } }, classList: { add() { }, remove() { }, toggle() { } }, querySelector() { return stubs.$(); } }),
    store: { get: (k, d) => d, set() { }, del() { } },
    AU: {
      touched: false, ok: () => true, ensure() { }, ctx: { get currentTime() { return env.clock / 1000; } },
      tone: (freq, fam, gain, decay) => env.tones.push({ t: env.clock, freq, fam, gain }),
    },
    V: { ok: true, df: 0, aO: node(), aH: node(), aG: node(), r1: node(), r2: node(), r3: node(), rG: node(), fG: node() },
    show() { }, wake() { }, unwake() { }, requestAnimationFrame() { },
    say: txt => env.events.push({ t: env.clock, kind: 'say', text: txt }),
    vibrate() { },
    flashAll: long => env.events.push({ t: env.clock, kind: 'flash', long: !!long }),
    setStatus() { }, keyDrive() { }, lightUpdate() { }, drawBoard() { },
    speechSynthesis: { cancel() { } },
    document: { body: { classList: { add() { }, remove() { }, toggle() { } } } },
    renderFinal: rec => { env.closed = rec; },
    PARENT: {}, setEje() { },
  };
  // playPhrase/playSong con registro; mismas duraciones que el prototipo (rama sin audio).
  const prelude = `
    let activePointers = 0;
    const panels = { adult: {}, child: {} };
    function playPhrase(names, step = .24, gain = .17) { __ev.push({ t: performance.now(), kind: 'phrase', midi: names.map(n => NN[n]) }); return names.length * step + 1; }
    function playSong(ids) { const list = (ids || LEVELS.map(L => L.id)); __ev.push({ t: performance.now(), kind: 'song', ids: list }); return list.length * 4 * .3 + 2; }
  `;
  const exportsCode = `
    return { G, A, C, P, startSession, frame, report, sessionRecord, closeSession,
      setApp: v => { appMode = v; }, setSynth: v => { synth = v; }, setProgress: v => { PROG_OVR = v; }, isRunning: () => running };`;
  const names = Object.keys(stubs);
  const fn = new Function(...names, '__ev', prelude + code + exportsCode);
  const api = fn(...names.map(n => stubs[n]), env.events);
  api.__V = stubs.V;
  return { env, api };
}

function runTimers(env, api) {
  for (; ;) {
    let next = null;
    for (const t of env.timers) if (t.due <= env.clock && (!next || t.due < next.due || (t.due === next.due && t.seq < next.seq))) next = t;
    if (!next) return;
    env.timers.splice(env.timers.indexOf(next), 1);
    if (next.period) env.timers.push({ ...next, due: next.due + next.period, seq: env.seq++ });
    next.fn();
  }
}

const FPS_MS = 1000 / 60;
const T0 = 1000;
const SAMPLE_EVERY = 15;

// actions: [{ f: frame, synth: 'sync'|'cerca'|'lejos'|'cycle'|null }]
const SCENARIOS = [
  { name: 'lv1_sync', mode: 'levels', li: 0, cal: false, app: true, frames: 60 * 30, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv1_lejos', mode: 'levels', li: 0, cal: false, app: true, frames: 60 * 15, actions: [{ f: 0, synth: 'lejos' }] },
  { name: 'lv1_cycle', mode: 'levels', li: 0, cal: false, app: true, frames: 60 * 45, actions: [{ f: 0, synth: 'cycle' }] },
  { name: 'free_cycle', mode: 'free', li: 0, cal: false, app: true, frames: 60 * 25, actions: [{ f: 0, synth: 'cycle' }] },
  { name: 'lv1_cal_cycle', mode: 'levels', li: 0, cal: true, app: true, frames: 60 * 25, actions: [{ f: 0, synth: 'cycle' }] },
  { name: 'lv1_idle_close', mode: 'levels', li: 0, cal: false, app: true, frames: 60 * 45, actions: [{ f: 0, synth: 'sync' }, { f: 360, synth: null }] },
  { name: 'lv1_pause_resume', mode: 'levels', li: 0, cal: false, app: true, frames: 60 * 25, actions: [{ f: 0, synth: 'sync' }, { f: 180, synth: null }, { f: 600, synth: 'sync' }] },
  { name: 'bench_lv1_sync', mode: 'levels', li: 0, cal: false, app: false, frames: 60 * 30, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv2_sync', mode: 'levels', li: 1, cal: false, app: true, frames: 60 * 20, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv3_cerca', mode: 'levels', li: 2, cal: false, app: true, frames: 60 * 20, actions: [{ f: 0, synth: 'cerca' }] },
  { name: 'lv4_sync', mode: 'levels', li: 3, cal: false, app: true, frames: 60 * 20, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv5_sync', mode: 'levels', li: 4, cal: false, app: true, frames: 60 * 20, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv6_sync', mode: 'levels', li: 5, cal: false, app: true, frames: 60 * 20, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv7_song', mode: 'levels', li: 6, cal: false, app: true, frames: 60 * 70, actions: [{ f: 0, synth: 'sync' }] },
  { name: 'lv1_cycle_progress', mode: 'levels', li: 0, cal: false, app: true, frames: 60 * 30, progress: [1, 2, 3], actions: [{ f: 0, synth: 'cycle' }] },
  { name: 'lv1_cal_progress_idle', mode: 'levels', li: 0, cal: true, app: true, frames: 60 * 50, progress: [2], actions: [{ f: 0, synth: 'cerca' }, { f: 900, synth: null }] },
];

const stubsV = api => api.__V;

function run(sc) {
  const { env, api } = makeProto();
  const { G, A, C } = api;
  const V = stubsV(api);
  api.setApp(sc.app);
  if (sc.progress) api.setProgress([...sc.progress]);
  env.clock = T0;
  api.startSession({ mode: sc.mode, li: sc.li, cal: sc.cal });
  const samples = [];
  let report = null, record = null;
  for (let f = 0; f < sc.frames; f++) {
    const now = T0 + f * FPS_MS;
    for (const a of sc.actions) if (a.f === f) api.setSynth(a.synth);
    env.clock = now;
    runTimers(env, api);
    if (env.closed && !record) record = env.closed;
    api.frame(now);
    if (env.closed && !record) record = env.closed;
    if (f % SAMPLE_EVERY === 0) {
      samples.push({
        f, state: G.state, d: G.d, inSync: G.inSync, prog: G.prog, guide: G.guide, li: G.li, part: G.part,
        a: [A.pos.x, A.pos.y, A.speed], c: [C.pos.x, C.pos.y, C.speed],
        aAct: A.active(now), cAct: C.active(now), running: api.isRunning(),
        au: [V.aO.frequency.target, V.aG.gain.target, V.aG.gain.tau, V.r2.frequency.target, V.rG.gain.target, V.fG.gain.target, V.fG.gain.tau, V.df],
      });
    }
  }
  report = api.report();
  if (record) record = { ...record, t: undefined, trajLen: record.traj.length, traj: record.traj.slice(0, 40) };
  return { ...sc, samples, events: env.events, tones: env.tones, report: { ...report, inicio: undefined, parametros: undefined, proyecto: undefined }, record };
}

const out = { source: SRC, generated: new Date().toISOString().slice(0, 10), fpsMs: FPS_MS, t0: T0, sampleEvery: SAMPLE_EVERY, scenarios: SCENARIOS.map(run) };
mkdirSync('test/balancin_v2/golden', { recursive: true });
writeFileSync(OUT, JSON.stringify(out));
for (const s of out.scenarios) {
  const last = s.samples[s.samples.length - 1];
  console.log(s.name.padEnd(22), 'tones', String(s.tones.length).padStart(4), 'events', String(s.events.length).padStart(3), '| levels', JSON.stringify(s.report.niveles_logrados), '| closed', !!s.record, '| final', last.state);
}
