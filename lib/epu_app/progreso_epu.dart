import 'dart:convert';

import '../epu/estado/estado_eco.dart';

/// Una sesión de juego: los niveles terminados mientras la app estuvo abierta
/// y en pantalla (ver [ProgresoEpu.cerrarSesion]).
class RegistroSesion {
  RegistroSesion({required this.inicio, required this.fin, required Set<int> niveles}) : niveles = {...niveles};

  DateTime inicio;
  DateTime fin;

  /// Niveles (1 a 7) terminados en la sesión.
  final Set<int> niveles;

  Map<String, Object> toJson() =>
      {'inicio': inicio.toIso8601String(), 'fin': fin.toIso8601String(), 'niveles': niveles.toList()..sort()};

  static RegistroSesion? fromJson(Object? j) {
    try {
      final m = j! as Map<String, Object?>;
      return RegistroSesion(
        inicio: DateTime.parse(m['inicio']! as String),
        fin: DateTime.parse(m['fin']! as String),
        niveles: {for (final n in m['niveles']! as List<Object?>) n! as int},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Lo que la app recuerda entre una vez y otra: niveles completados y sesiones
/// pasadas (para el Home). Dart puro; el guardado en el teléfono lo hace quien
/// lo usa con [toJson] / [fromJson].
class ProgresoEpu {
  ProgresoEpu({Set<int>? completados, List<RegistroSesion>? sesiones})
      : completados = completados ?? {},
        sesiones = sesiones ?? [];

  /// Sesiones que se guardan (las más recientes).
  static const int maxSesiones = 20;

  final Set<int> completados;

  /// La más reciente primero.
  final List<RegistroSesion> sesiones;

  /// Hay una sesión en curso (no se guarda: al abrir la app siempre empieza otra).
  bool _sesionAbierta = false;

  /// Dejaron de jugar: la app se cerró o pasó al fondo. El próximo nivel
  /// terminado abre una sesión nueva (18-11: 30 min era demasiado).
  void cerrarSesion() => _sesionAbierta = false;

  /// Registra un nivel terminado en [ahora].
  void terminarNivel(int nivel, DateTime ahora) {
    completados.add(nivel);
    final ultima = sesiones.isEmpty ? null : sesiones.first;
    if (ultima != null && _sesionAbierta) {
      ultima.fin = ahora;
      ultima.niveles.add(nivel);
    } else {
      _sesionAbierta = true;
      sesiones.insert(0, RegistroSesion(inicio: ahora, fin: ahora, niveles: {nivel}));
      if (sesiones.length > maxSesiones) sesiones.removeRange(maxSesiones, sesiones.length);
    }
  }

  /// Sesiones como las muestra el Home de Joaquín.
  List<SesionPasada> sesionesParaHome(DateTime ahora) => [
        for (final s in sesiones)
          SesionPasada(
            titulo: '${tituloDia(s.inicio, ahora)} · ${s.niveles.length} ${s.niveles.length == 1 ? 'parte' : 'partes'}',
            minutos: _minutos(s),
            partes: [for (var n = 1; n <= 7; n++) s.niveles.contains(n)],
          ),
      ];

  /// Cada nivel dura unos 40 s; una sesión de un solo nivel cuenta 1 min.
  static int _minutos(RegistroSesion s) {
    final m = (s.fin.difference(s.inicio).inMilliseconds / 60000).round();
    return m < 1 ? 1 : m;
  }

  static const _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];

  /// «Hoy», «Ayer» o «Viernes, 30 oct» (como el prototipo).
  static String tituloDia(DateTime dia, DateTime ahora) {
    final d = DateTime(dia.year, dia.month, dia.day), h = DateTime(ahora.year, ahora.month, ahora.day);
    final dif = h.difference(d).inDays;
    if (dif == 0) return 'Hoy';
    if (dif == 1) return 'Ayer';
    return '${_dias[dia.weekday - 1]}, ${dia.day} ${_meses[dia.month - 1]}';
  }

  String toJson() => jsonEncode({
        'completados': completados.toList()..sort(),
        'sesiones': [for (final s in sesiones) s.toJson()],
      });

  static ProgresoEpu fromJson(String? texto) {
    if (texto == null) return ProgresoEpu();
    try {
      final m = jsonDecode(texto) as Map<String, Object?>;
      return ProgresoEpu(
        completados: {for (final n in (m['completados'] as List<Object?>? ?? const [])) n! as int},
        sesiones: [
          for (final j in (m['sesiones'] as List<Object?>? ?? const [])) ?RegistroSesion.fromJson(j),
        ],
      );
    } catch (_) {
      return ProgresoEpu();
    }
  }
}
