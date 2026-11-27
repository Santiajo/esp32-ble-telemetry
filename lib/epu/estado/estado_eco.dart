import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Un recuerdo guardado con el marcador de «Eco · el recuerdo».
///
/// Solo guarda el nivel y la fecha: el dibujo se vuelve a generar con los
/// datos del nivel (ver ilustraciones/huella_datos.dart). Si en la app real
/// el dibujo sale de las lecturas de los sticks, aquí habría que guardar
/// también esas lecturas.
class RecuerdoGuardado {
  const RecuerdoGuardado({required this.nivel, required this.fecha, this.pasos});

  final int nivel;
  final DateTime fecha;

  /// Integración: lo que de verdad jugaron (`S:B`, `O:L`…), para que el dibujo
  /// salga de la partida y no de la partitura. `null` = la partitura del nivel.
  final List<String>? pasos;

  Map<String, Object?> toJson() => {'n': nivel, 'f': fecha.toIso8601String(), if (pasos != null) 'p': pasos};
  static RecuerdoGuardado fromJson(Map<String, Object?> j) => RecuerdoGuardado(
        nivel: j['n']! as int,
        fecha: DateTime.parse(j['f']! as String),
        pasos: (j['p'] as List?)?.cast<String>(),
      );
}

/// Una sesión jugada: se registra sola al terminar un nivel (al pasar del
/// juego a «Eco · el recuerdo»).
class SesionNivel {
  const SesionNivel({
    required this.nivel,
    required this.fecha,
    required this.minutos,
    required this.logrados,
    this.pasos,
  });

  final int nivel;
  final DateTime fecha;
  final int minutos;

  /// Trozos logrados (de los trozos del nivel).
  final int logrados;

  /// Integración: lo que jugaron (ver [RecuerdoGuardado.pasos]).
  final List<String>? pasos;

  Map<String, Object?> toJson() =>
      {'n': nivel, 'f': fecha.toIso8601String(), 'm': minutos, 'ok': logrados, if (pasos != null) 'p': pasos};
  static SesionNivel fromJson(Map<String, Object?> j) => SesionNivel(
        nivel: j['n']! as int,
        fecha: DateTime.parse(j['f']! as String),
        minutos: j['m']! as int,
        logrados: j['ok']! as int,
        pasos: (j['p'] as List?)?.cast<String>(),
      );
}

/// Estado compartido del flujo Eco.
///
/// El prototipo lo guarda en `sessionStorage` (`epuMelodia`, `epuModo`,
/// `epuRecuerdos`, `epuSesiones`) y en el estado de «App completa · Eco».
/// Aquí vive en un solo [ChangeNotifier] que se entrega a toda la app con
/// [EpuEstado].
///
/// **Persistencia:** recuerdos, sesiones y niveles completados tienen que
/// sobrevivir a cerrar la app. Este paquete los deja en memoria; el equipo
/// debe guardarlos en el teléfono (`shared_preferences`, una base local,
/// etc.). Los puntos para engancharlo son [guardarRecuerdo],
/// [registrarSesion] y [marcarCompletado].
class EstadoEco extends ChangeNotifier {
  EstadoEco({
    int nivel = 4,
    Set<int>? completados,
    List<RecuerdoGuardado>? recuerdos,
    List<SesionNivel>? sesiones,
  })  : _nivel = nivel,
        _completados = completados ?? {},
        _recuerdos = recuerdos ?? [],
        _sesiones = sesiones ?? [];

  /// Valores de ejemplo para que la app se vea igual que el prototipo:
  /// nivel 4 elegido (valor inicial de «App completa · Eco»), niveles 1 y 2
  /// completados y el archivo de ejemplo del Home (`DEMO_REC`, `DEMO_SES`).
  factory EstadoEco.demo({DateTime? hoy}) {
    final h = _soloDia(hoy ?? DateTime.now());
    final ayer = h.subtract(const Duration(days: 1));
    final viernes = DateTime(2026, 10, 30);
    return EstadoEco(
      nivel: 4,
      completados: {1, 2},
      recuerdos: [
        RecuerdoGuardado(nivel: 2, fecha: ayer),
        RecuerdoGuardado(nivel: 1, fecha: viernes),
      ],
      sesiones: [
        SesionNivel(nivel: 2, fecha: ayer, minutos: 5, logrados: 4),
        SesionNivel(nivel: 3, fecha: ayer, minutos: 4, logrados: 3),
        SesionNivel(nivel: 1, fecha: viernes, minutos: 4, logrados: 4),
        SesionNivel(nivel: 1, fecha: viernes, minutos: 3, logrados: 2),
      ],
    );
  }

  /// Archivo lleno (varias semanas de juego) para revisar cómo se comporta
  /// «Tu archivo» con mucho contenido. Es la opción `datos: muchos` del
  /// prototipo, con el mismo generador y la misma semilla.
  factory EstadoEco.demoLleno({DateTime? hoy}) {
    final h = _soloDia(hoy ?? DateTime.now());
    // Días hacia atrás que corresponden a las fechas fijas del prototipo
    // (Hoy, Ayer, Domingo 15 nov… Sábado 24 oct, contando desde el 17 nov).
    const dias = [0, 1, 2, 3, 5, 7, 10, 13, 16, 18, 21, 24];
    const trozos = [4, 4, 4, 5, 5, 6, 6];
    var sd = 7;
    double r() {
      sd = (sd * 16807) % 2147483647;
      return sd / 2147483647;
    }

    final rec = <RecuerdoGuardado>[], ses = <SesionNivel>[];
    for (var n = 1; n <= 7; n++) {
      final tot = trozos[n - 1];
      final nS = 13 - n + (r() * 4).floor(), nR = math.max(3, (nS * .7).round());
      for (var k = 0; k < nS; k++) {
        final i = math.min(dias.length - 1, ((k + r() * 1.5) * dias.length / nS).floor());
        final f = h.subtract(Duration(days: dias[i]));
        final min = 2 + (r() * 8).floor();
        final ok = r() < .7 ? tot : math.max(1, tot - 1 - (r() * 2).floor());
        ses.add(SesionNivel(nivel: n, fecha: f, minutos: min, logrados: ok));
        if (k < nR) rec.add(RecuerdoGuardado(nivel: n, fecha: f));
      }
    }
    return EstadoEco(nivel: 4, completados: {1, 2}, recuerdos: rec, sesiones: ses);
  }

  static DateTime _soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

  int _nivel;
  final Set<int> _completados;
  final List<RecuerdoGuardado> _recuerdos;
  final List<SesionNivel> _sesiones;

  /// Nivel (melodía) elegido, de 1 a 7.
  int get nivel => _nivel;
  set nivel(int valor) {
    final v = valor.clamp(1, 7);
    if (v == _nivel) return;
    _nivel = v;
    notifyListeners();
  }

  bool completado(int nivel) => _completados.contains(nivel);

  /// Se llama al terminar la melodía (pantalla de juego).
  void marcarCompletado(int nivel) {
    if (_completados.add(nivel)) notifyListeners();
  }

  /// Recuerdos guardados, del más nuevo al más antiguo.
  List<RecuerdoGuardado> get recuerdos => List.unmodifiable(_recuerdos);

  /// Sesiones jugadas, de la más nueva a la más antigua.
  List<SesionNivel> get sesiones => List.unmodifiable(_sesiones);

  /// Marcador de «Eco · el recuerdo». Cada vez que se guarda queda uno
  /// nuevo (uno por partida), igual que en el prototipo.
  void guardarRecuerdo(int nivel, {DateTime? fecha}) {
    _recuerdos.insert(0, RecuerdoGuardado(nivel: nivel, fecha: fecha ?? DateTime.now(), pasos: pasosVista));
    notifyListeners();
  }

  /// Integración: pasos que dibuja «Eco · el recuerdo» (los de la partida recién
  /// jugada o los del recuerdo/sesión abierto desde «Tu archivo»). `null` = la
  /// partitura del nivel.
  List<String>? pasosVista;

  /// Integración: todo lo que hay que guardar en el teléfono.
  Map<String, Object?> archivoJson() => {
        'completados': _completados.toList(),
        'recuerdos': [for (final r in _recuerdos) r.toJson()],
        'sesiones': [for (final s in _sesiones) s.toJson()],
      };

  /// Integración: lee lo guardado con [archivoJson] (lo que no se entienda se ignora).
  static EstadoEco desdeArchivo(Map<String, Object?>? j, {int nivel = 1}) {
    List<T> lista<T>(String k, T Function(Map<String, Object?>) f) {
      final out = <T>[];
      for (final e in (j?[k] as List?) ?? const []) {
        try {
          out.add(f((e as Map).cast<String, Object?>()));
        } catch (_) {}
      }
      return out;
    }

    return EstadoEco(
      nivel: nivel,
      completados: {...((j?['completados'] as List?) ?? const []).whereType<int>()},
      recuerdos: lista('recuerdos', RecuerdoGuardado.fromJson),
      sesiones: lista('sesiones', SesionNivel.fromJson),
    );
  }

  /// Se llama al pasar del juego al recuerdo. El prototipo anota 1 minuto y
  /// todos los trozos; aquí la pantalla de juego entrega lo real.
  void registrarSesion(int nivel, {required int minutos, required int logrados, DateTime? fecha, List<String>? pasos}) {
    _sesiones.insert(
      0,
      SesionNivel(
          nivel: nivel, fecha: fecha ?? DateTime.now(), minutos: math.max(1, minutos), logrados: logrados, pasos: pasos),
    );
    notifyListeners();
  }
}

/// Fecha como la muestra «Tu archivo»: «Hoy», «Ayer» o «Domingo, 15 nov».
String fechaArchivo(DateTime fecha, {DateTime? hoy}) {
  const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
  final h = hoy ?? DateTime.now();
  final d0 = DateTime(h.year, h.month, h.day), d = DateTime(fecha.year, fecha.month, fecha.day);
  final diferencia = (d0.difference(d).inHours / 24).round(); // redondeo: a prueba de cambio de horario
  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Ayer';
  return '${dias[d.weekday - 1]}, ${d.day} ${meses[d.month - 1]}';
}

/// Entrega el [EstadoEco] a toda la app. Uso: `EpuEstado.of(context).nivel`.
class EpuEstado extends InheritedNotifier<EstadoEco> {
  const EpuEstado({super.key, required EstadoEco estado, required super.child})
      : super(notifier: estado);

  static EstadoEco of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EpuEstado>()!.notifier!;

  /// Lo mismo sin suscribirse a cambios (para usar dentro de callbacks).
  static EstadoEco leer(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EpuEstado>()!.notifier!;
}
