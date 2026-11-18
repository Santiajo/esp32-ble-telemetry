import 'dart:async';

import '../../balancin/core/ble/imu_frame_parser.dart';
import '../../balancin/platform/ble_stick_link.dart';
import '../core/params.dart';
import '../core/stick_check.dart';
import '../core/tilt/axis_map.dart';
import '../core/tilt/imu_trace.dart';
import '../core/tilt/tilt_reader.dart';
import 'axis_store.dart';
import 'bias_store.dart';

/// Un stick real visto por la mecánica v2 (plan v2 §4.1 y fase 4).
///
/// Se cuelga del [BleStickLink] de v1 (misma conexión, misma MAC guardada) y le
/// pasa cada muestra a un [TiltReader]. También graba trazas: las líneas v2
/// crudas con su hora de llegada, para convertir pruebas reales en tests.
///
/// El bias del giroscopio medido se guarda por MAC ([BiasStore]) y el siguiente
/// `TiltStick` de la misma placa parte con él.
class TiltStick {
  TiltStick(this.link, {SyncParams? params, AxisMap? ejesFijos}) : reader = TiltReader(params: params, axes: ejesFijos) {
    link.sampleListeners.add(_onSample);
    reader.onBiasMeasured = _onBiasMeasured;
    // Con ejes fijos (sticks Epu: el firmware ya manda derecho = +Z, derecha = +X,
    // adelante = +Y) no se cargan los del asistente ni se deducen de la primera lectura.
    if (ejesFijos == null) unawaited(loadSavedAxes());
    // El bias guardado puede venir de otro firmware (otros ejes): con ejes fijos se
    // vuelve a medir (con el ICM-42688-P basta medio segundo quieto).
    if (ejesFijos == null) unawaited(_loadSavedBias());
  }

  /// Cada cuánto se guarda el bias mientras se sigue afinando (ms).
  static const int biasSaveEveryMs = 30000;
  DateTime? _biasSavedAt;
  bool _biasDirty = false;

  Future<void> _loadSavedBias() async {
    final b = await BiasStore.load(link.savedMac);
    if (b != null) reader.seedBias(b.bias, b.restMag);
  }

  void _onBiasMeasured() {
    _biasDirty = true;
    final last = _biasSavedAt;
    if (last == null || DateTime.now().difference(last).inMilliseconds > biasSaveEveryMs) _saveBias();
  }

  void _saveBias() {
    if (!_biasDirty) return;
    _biasDirty = false;
    _biasSavedAt = DateTime.now();
    unawaited(BiasStore.save(link.savedMac, reader.biasDps, reader.restMagG));
  }

  /// Ejes del asistente guardados para esta placa (por MAC), si los hay.
  Future<void> loadSavedAxes() async {
    final map = await AxisStore.load(link.savedMac);
    if (map != null) reader.setAxes(map);
  }

  /// Guarda los ejes del asistente para esta placa y los aplica.
  Future<void> saveAxes(AxisMap map) async {
    reader.setAxes(map);
    await AxisStore.save(link.savedMac, map);
  }

  /// Olvida los ejes del asistente: vuelve a los de fábrica (vertical = Z, derecha = X).
  Future<void> resetAxes() async {
    reader.useDefaultAxes();
    await AxisStore.clear(link.savedMac);
  }

  final BleStickLink link;
  final TiltReader reader;

  List<TraceSample>? _recording;
  double _recordStart = 0;

  /// Máximo de muestras por traza (10 min a 100 Hz).
  static const int maxTraceSamples = 60000;

  bool get connected => link.connected;

  /// Conectado pero sin muestras hace más de 1 s (o nunca llegaron).
  bool stale(double now) => !reader.hasTilt || now - reader.lastArrivalMs > 1000;

  bool get recording => _recording != null;
  int get recordedSamples => _recording?.length ?? 0;
  double recordedSeconds(double now) => recording ? (now - _recordStart) / 1000 : 0;

  void _onSample(ImuSample s, double arrivalMs) {
    reader.addSample(s, arrivalMs);
    final r = _recording;
    if (r != null && r.length < maxTraceSamples) r.add(TraceSample(arrivalMs, s));
  }

  void startRecording(double now) {
    _recording = [];
    _recordStart = now;
  }

  /// Termina la grabación y devuelve el texto de la traza ([ImuTrace]).
  String stopRecording({required String role, required DateTime when}) {
    final r = _recording ?? const <TraceSample>[];
    _recording = null;
    return ImuTrace.encode(r, comments: [
      'Balancín v2 · traza del stick $role',
      'Grabada el ${when.toIso8601String()} · ${r.length} muestras',
      'Ejes: ${reader.axesFromDefault ? 'por defecto (vertical = Z, derecha = X)' : 'del asistente'}',
    ]);
  }

  /// Lectura actual para el chequeo de sticks ([now] en el reloj de la app).
  StickSnapshot snapshot(double now) => StickSnapshot(
        connected: link.connected,
        receiving: !stale(now),
        hz: stale(now) ? 0 : reader.sampleRateHz,
        tiltX: reader.tiltX,
        tiltY: reader.tiltY,
        gravity: reader.gravity,
        accelMagG: reader.accelMagG,
        restMagG: reader.restMagG,
        gyroReady: reader.calibrated,
        stillCount: reader.stillCount,
        axes: reader.axes,
        lagMs: reader.lagMs,
        gaps: reader.gaps,
      );

  /// Texto de estado para el banco.
  String statusText(double now) {
    if (!link.connected) return link.statusText;
    if (reader.lastSample == null) return 'Conectado · esperando datos';
    if (stale(now)) return 'Conectado · sin datos hace más de 1 s';
    final cal = !reader.calibrated
        ? ' · déjalo quieto para calibrar'
        : reader.biasSeeded
            ? ' · giro guardado'
            : '';
    return 'Conectado · ${reader.sampleRateHz.toStringAsFixed(0)} Hz$cal';
  }

  void dispose() {
    link.sampleListeners.remove(_onSample);
    reader.onBiasMeasured = null;
    _saveBias();
  }
}
