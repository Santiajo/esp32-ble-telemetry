import 'package:flutter/widgets.dart';

import '../pantallas/bienvenida.dart';
import '../pantallas/calibrar.dart';
import '../pantallas/eco_antes.dart';
import '../pantallas/eco_final.dart';
import '../pantallas/eco_guia.dart';
import '../pantallas/eco_juego.dart';
import '../pantallas/eco_niveles.dart';
import '../pantallas/home.dart';
import '../pantallas/inicio.dart';
import '../pantallas/perdida.dart';
import '../pantallas/prep_conectar.dart';
import '../pantallas/prep_permisos.dart';
import '../pantallas/prep_quien_usa.dart';
import '../pantallas/prep_sin_avisos.dart';

/// Las 14 pantallas del flujo Eco, en el orden en que se recorren.
///
/// Entre paréntesis, el archivo del prototipo de donde sale cada una.
enum Pantalla {
  inicio, //          Main.dc.html        (canvas: «Inicio»)
  permisos, //        Prep1.dc.html       («Preparación 1 · Permisos»)
  sinAvisos, //       Prep2.dc.html       («Preparación 2 · No Molestar»)
  conectar, //        Prep4.dc.html       («Preparación 3 · Vincular sticks»)
  quienUsa, //        Prep5.dc.html       («Preparación 4 · Quién usa cada stick»)
  bienvenida, //      Bienvenida.dc.html  («Bienvenida · logo Epu»)
  home, //            Home.dc.html
  elegirNivel, //     EcoNiveles.dc.html  («Eco · elegir nivel»)
  antes, //           EcoAntes.dc.html    («Eco · antes del nivel»)
  guia, //            EcoGuia.dc.html     («Eco · quién guía»)
  calibrar, //        Calibrar.dc.html    (modo eco)
  juego, //           EcoJuego.dc.html    («Eco · descubrir la melodía»)
  recuerdo, //        EcoFinal.dc.html    («Eco · el recuerdo»)
  perdida, //         Perdida.dc.html     («Pérdida de stick»)
}

/// Argumento de [Pantalla.recuerdo] cuando se abre desde «Tu archivo».
enum ArgumentosRecuerdo { desdeArchivo }

/// Navegación del flujo.
///
/// En el prototipo cada enlace apunta a una pantalla concreta (por ejemplo,
/// el «Atrás» del recuerdo lleva a «elegir nivel», no a la pantalla de
/// juego). Por eso aquí no se usa un `pop()` a ciegas: [volverA] regresa a la
/// pantalla indicada si ya está en la pila, y si no, la abre en su lugar.
///
/// El cambio entre pantallas es instantáneo, sin transición, igual que en el
/// prototipo. Las únicas transiciones son las que cada pantalla dibuja por su
/// cuenta (el círculo que cubre «Quién usa cada stick» y la bienvenida).
class EpuNavegacion {
  EpuNavegacion._();

  static final registro = RegistroRutas();

  /// Abre [pantalla] encima de la actual.
  static Future<void> ir(BuildContext context, Pantalla pantalla, {Object? argumentos}) =>
      Navigator.of(context).pushNamed(pantalla.name, arguments: argumentos);

  /// Vuelve a [pantalla]. Si no está en la pila, reemplaza la actual por ella.
  static void volverA(BuildContext context, Pantalla pantalla) {
    final nav = Navigator.of(context);
    if (registro.contiene(pantalla.name)) {
      nav.popUntil((r) => r.settings.name == pantalla.name);
    } else {
      nav.pushReplacementNamed(pantalla.name);
    }
  }

  /// Abre [pantalla] y borra todo lo anterior (se usa al terminar la
  /// preparación: desde el Home no se vuelve a la bienvenida).
  static void empezarEn(BuildContext context, Pantalla pantalla) =>
      Navigator.of(context).pushNamedAndRemoveUntil(pantalla.name, (_) => false);

  /// Muestra «Pérdida de stick». Lo llama la capa de Bluetooth cuando un
  /// stick deja de responder (ver lib/epu/juego/fuente_sticks.dart).
  static Future<void> mostrarPerdida(
    BuildContext context, {
    required StickPerdido stick,
    required CausaPerdida causa,
  }) =>
      ir(context, Pantalla.perdida, argumentos: (stick, causa));

  /// Arma la ruta de cada pantalla. Sin animación de entrada ni de salida.
  static Route<void> generar(RouteSettings ajustes) {
    final pantalla = Pantalla.values.byName(ajustes.name ?? Pantalla.inicio.name);
    return PageRouteBuilder<void>(
      settings: ajustes,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => _construir(pantalla, ajustes.arguments),
    );
  }

  static Widget _construir(Pantalla p, Object? argumentos) => switch (p) {
        Pantalla.inicio => const PantallaInicio(),
        Pantalla.permisos => const PantallaPermisos(),
        Pantalla.sinAvisos => const PantallaSinAvisos(),
        Pantalla.conectar => const PantallaConectar(),
        Pantalla.quienUsa => const PantallaQuienUsa(),
        Pantalla.bienvenida => const PantallaBienvenida(),
        Pantalla.home => const PantallaHome(),
        Pantalla.elegirNivel => const PantallaEcoNiveles(),
        Pantalla.antes => const PantallaEcoAntes(),
        Pantalla.guia => const PantallaEcoGuia(),
        Pantalla.calibrar => const PantallaCalibrar(),
        Pantalla.juego => const PantallaEcoJuego(),
        // Abierto desde «Tu archivo» (menú del Home): se muestra ya guardado.
        Pantalla.recuerdo => PantallaEcoFinal(desdeArchivo: argumentos == ArgumentosRecuerdo.desdeArchivo),
        Pantalla.perdida => switch (argumentos) {
            (StickPerdido s, CausaPerdida c) => PantallaPerdida(stick: s, causa: c),
            _ => const PantallaPerdida(),
          },
      };
}

/// Lleva la cuenta de qué pantallas están abiertas, para [EpuNavegacion.volverA].
class RegistroRutas extends NavigatorObserver {
  final List<String?> _pila = [];

  bool contiene(String nombre) => _pila.contains(nombre);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _pila.add(route.settings.name);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _quitar(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _quitar(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pila.lastIndexOf(oldRoute.settings.name);
    if (i >= 0) {
      _pila[i] = newRoute?.settings.name;
    } else if (newRoute != null) {
      _pila.add(newRoute.settings.name);
    }
  }

  void _quitar(Route<dynamic> route) {
    final i = _pila.lastIndexOf(route.settings.name);
    if (i >= 0) _pila.removeAt(i);
  }
}
