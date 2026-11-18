import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../datos/niveles.dart';

/// Bordes de la pantalla de juego. Con el teléfono dentro del eje, cada borde
/// es una dirección de vuelco del stick.
enum Borde {
  frente('F'), // borde superior
  atras('B'), // borde inferior
  izquierda('L'),
  derecha('R');

  const Borde(this.letra);
  final String letra;

  Borde get opuesto => switch (this) {
        frente => atras,
        atras => frente,
        izquierda => derecha,
        derecha => izquierda,
      };

  static Borde? desdeLetra(String l) {
    for (final b in values) {
      if (b.letra == l) return b;
    }
    return null;
  }
}

/// Color de la franja de pista de un borde.
enum ColorPista {
  /// Lila: el adulto tiene que ir a ese borde.
  adulto,

  /// Coral: el niño tiene que ir a ese borde.
  nino,

  /// Amarillo: los dos tienen que ir al mismo borde. Está dibujado en el
  /// prototipo pero la simulación no lo usa (allí la pista es solo para
  /// quien sigue).
  ambos,
}

/// Todo lo que se ve en la pantalla de juego en un instante.
///
/// La pantalla ([PantallaEcoJuego]) solo dibuja este estado: no sabe de
/// reglas ni de sticks. Quien lo cambia es la simulación del prototipo
/// ([SimulacionEco]) o, en la app real, la lógica del juego con los datos de
/// los sticks (ver `fuente_sticks.dart`).
///
/// Las posiciones están en el sistema del prototipo: una pantalla de
/// 390 × 844. La pantalla las escala al tamaño real del teléfono.
class EstadoJuegoEco extends ChangeNotifier {
  EstadoJuegoEco();

  // ── Posiciones de referencia (centro de cada luz) ───────────────────────
  static const reposoAdulto = Offset(150, 398);
  static const reposoNino = Offset(240, 446);

  static Offset reposo(bool adulto) => adulto ? reposoAdulto : reposoNino;

  /// Luz junto a un borde. Adulto y niño quedan separados para no taparse.
  static Offset enBorde(Borde? b, bool adulto) => switch (b) {
        Borde.frente => Offset(adulto ? 132 : 258, 138),
        Borde.atras => Offset(adulto ? 132 : 258, 706),
        Borde.izquierda => Offset(78, adulto ? 320 : 524),
        Borde.derecha => Offset(312, adulto ? 320 : 524),
        null => reposo(adulto),
      };

  /// Luz sobre el círculo del giro (radio 140 el adulto, 92 el niño,
  /// centro en 195, 422). [grados] 0 = derecha, −90 = arriba.
  static Offset enCirculo(double grados, bool adulto) {
    final r = adulto ? 140.0 : 92.0, q = grados * math.pi / 180;
    return Offset(195 + r * math.cos(q), 422 + r * math.sin(q));
  }

  // ── Estado ───────────────────────────────────────────────────────────────
  Offset _adulto = reposoAdulto;
  Offset _nino = reposoNino;
  Map<Borde, ColorPista?> _pistas = const {};
  Borde? _sostener;
  bool _giro = false;
  bool _acierto = false;
  bool _lucesVisibles = true;
  Guia? _parpadea;

  /// Centro de la luz del stick del adulto (104 px).
  Offset get adulto => _adulto;

  /// Centro de la luz del stick del niño (84 px).
  Offset get nino => _nino;

  /// Franja de pista encendida en cada borde (solo guía a quien sigue).
  Map<Borde, ColorPista?> get pistas => _pistas;

  /// Borde que hay que sostener (paso «quietos»): se enciende una franja
  /// amarilla más ancha que crece en 1,4 s.
  Borde? get sostener => _sostener;

  /// Durante el giro las luces se mueven en tramos rectos de 230 ms.
  bool get giro => _giro;

  /// Luz verde de acierto en toda la pantalla.
  bool get acierto => _acierto;

  /// Las dos luces se apagan al acertar y vuelven para el siguiente trozo.
  bool get lucesVisibles => _lucesVisibles;

  /// Luz que late porque esa persona tiene que elegir el movimiento.
  Guia? get parpadea => _parpadea;

  /// Cambia varias cosas a la vez y avisa una sola vez (como `setState`).
  void cambiar({
    Offset? adulto,
    Offset? nino,
    Map<Borde, ColorPista?>? pistas,
    Borde? sostener,
    bool quitarSostener = false,
    bool? giro,
    bool? acierto,
    bool? lucesVisibles,
    Guia? parpadea,
    bool quitarParpadeo = false,
  }) {
    if (adulto != null) _adulto = adulto;
    if (nino != null) _nino = nino;
    if (pistas != null) _pistas = Map.unmodifiable(pistas);
    if (sostener != null) _sostener = sostener;
    if (quitarSostener) _sostener = null;
    if (giro != null) _giro = giro;
    if (acierto != null) _acierto = acierto;
    if (lucesVisibles != null) _lucesVisibles = lucesVisibles;
    if (parpadea != null) _parpadea = parpadea;
    if (quitarParpadeo) _parpadea = null;
    notifyListeners();
  }

  /// Enciende la pista de un borde sin tocar las demás.
  void pista(Borde b, ColorPista c) => cambiar(pistas: {..._pistas, b: c});

  /// Vuelve todo al inicio del nivel.
  void reiniciar() => cambiar(
        adulto: reposoAdulto,
        nino: reposoNino,
        pistas: const {},
        quitarSostener: true,
        giro: false,
        acierto: false,
        lucesVisibles: true,
        quitarParpadeo: true,
      );
}
