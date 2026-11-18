import 'package:flutter/widgets.dart';

/// Una sesión de juego guardada, como las que muestra el Home.
class SesionPasada {
  const SesionPasada({
    required this.titulo,
    required this.minutos,
    required this.partes,
  });

  /// «Ayer · 2 partes», «Viernes, 30 oct · 2 partes».
  final String titulo;
  final int minutos;

  /// Una barrita por nivel (7). `true` = nivel jugado en esa sesión.
  final List<bool> partes;
}

/// Estado compartido del flujo Eco.
///
/// El prototipo lo guarda en `sessionStorage` (`epuMelodia`, `epuModo`) y en
/// el estado de «App completa · Eco». Aquí vive en un solo [ChangeNotifier]
/// que se entrega a toda la app con [EpuEstado].
///
/// Lo que sea persistente de verdad (niveles completados, sesiones) debería
/// guardarse en el teléfono (`shared_preferences`, una base local, etc.).
/// Ese guardado no existe en el prototipo y queda fuera de este paquete.
class EstadoEco extends ChangeNotifier {
  EstadoEco({
    int nivel = 4,
    Set<int>? completados,
    List<SesionPasada>? sesiones,
  })  : _nivel = nivel,
        _completados = completados ?? {},
        sesiones = sesiones ?? const [];

  /// Valores de ejemplo para que la app se vea igual que el prototipo:
  /// nivel 4 elegido (es el valor inicial de «App completa · Eco»), niveles
  /// 1 y 2 completados (así están dibujados en «Eco · elegir nivel») y las dos
  /// sesiones del Home.
  factory EstadoEco.demo() => EstadoEco(
        nivel: 4,
        completados: {1, 2},
        sesiones: const [
          SesionPasada(
            titulo: 'Ayer · 2 partes',
            minutos: 11,
            partes: [false, false, true, true, false, false, false],
          ),
          SesionPasada(
            titulo: 'Viernes, 30 oct · 2 partes',
            minutos: 9,
            partes: [true, true, false, false, false, false, false],
          ),
        ],
      );

  int _nivel;
  final Set<int> _completados;
  final List<SesionPasada> sesiones;

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
