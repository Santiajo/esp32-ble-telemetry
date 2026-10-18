import '../../balancin/core/ble/imu_frame_parser.dart';
import '../../balancin/platform/ble_stick_link.dart';
import '../core/params.dart';
import '../core/tilt/imu_trace.dart';
import '../core/tilt/tilt_reader.dart';

/// Un stick real visto por la mecánica v2 (plan v2 §4.1 y fase 4).
///
/// Se cuelga del [BleStickLink] de v1 (misma conexión, misma MAC guardada) y le
/// pasa cada muestra a un [TiltReader]. También graba trazas: las líneas v2
/// crudas con su hora de llegada, para convertir pruebas reales en tests.
class TiltStick {
  TiltStick(this.link, {SyncParams? params}) : reader = TiltReader(params: params) {
    link.sampleListeners.add(_onSample);
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

  /// Texto de estado para el banco.
  String statusText(double now) {
    if (!link.connected) return link.statusText;
    if (reader.lastSample == null) return 'Conectado · esperando datos';
    if (stale(now)) return 'Conectado · sin datos hace más de 1 s';
    final cal = reader.calibrated ? '' : ' · déjalo quieto para calibrar';
    return 'Conectado · ${reader.sampleRateHz.toStringAsFixed(0)} Hz$cal';
  }

  void dispose() {
    link.sampleListeners.remove(_onSample);
  }
}
