import 'dart:math' as math;

import '../epu/datos/niveles.dart';
import '../epu/juego/estado_juego.dart';

/// Ajustes del juego real (se afinan en la prueba del sábado).
class AjustesEco {
  const AjustesEco({
    this.umbral = 25,
    this.salida = 18,
    this.cambioLado = 5,
    this.elegirMs = 150,
    this.sostenerMs = 300,
    this.quietosMs = 1400,
    this.graciaMs = 1000,
    this.pausaAciertoMs = 1500,
    this.ninoEnfrente = true,
  });

  /// Grados de vuelco para que cuente como «en un borde». 25° desde el 18-11: con
  /// 20° volver al centro bajando el brazo se pasaba al borde de abajo.
  final double umbral;

  /// Por debajo de estos grados vuelve al centro (margen para que no salte).
  final double salida;

  /// Para pasar de un borde a otro sin volver al centro, el otro eje tiene que
  /// ganarle al actual por estos grados.
  final double cambioLado;

  /// El guía tiene que quedarse este tiempo en un borde para que cuente como
  /// elegido (evita que pasar por un borde lo elija).
  final int elegirMs;

  /// Los dos en su borde a la vez durante este tiempo = acierto.
  final int sostenerMs;

  /// En «quietos» (nivel 2) hay que sostener más: lo que tarda en llenarse la
  /// franja amarilla del prototipo.
  final int quietosMs;

  /// Si el guía sale de su borde, se espera este tiempo antes de volver a
  /// pedirle que elija (un tambaleo no borra la elección).
  final int graciaMs;

  /// Luz verde y luces apagadas tras un acierto, como en el prototipo.
  final int pausaAciertoMs;

  /// Adulto y niño frente a frente con el teléfono al medio: la pantalla se ve
  /// desde el adulto; el adelante y la derecha del niño quedan al revés.
  final bool ninoEnfrente;
}

/// Vuelco a borde con histéresis.
class DetectorBorde {
  DetectorBorde(this.ajustes);
  final AjustesEco ajustes;
  Borde? borde;

  /// [lateral] + = derecha, [frontal] − = adelante (borde superior), en grados.
  Borde? actualizar(double lateral, double frontal) {
    final mag = math.sqrt(lateral * lateral + frontal * frontal);
    final b = borde;
    if (b == null) {
      if (mag >= ajustes.umbral) borde = _dominante(lateral, frontal);
    } else if (mag < ajustes.salida) {
      borde = null;
    } else {
      final lateralManda = b == Borde.izquierda || b == Borde.derecha;
      final otro = lateralManda ? frontal.abs() : lateral.abs();
      final actual = lateralManda ? lateral.abs() : frontal.abs();
      final enOtro = _dominante(lateral, frontal);
      if (otro > actual + ajustes.cambioLado) {
        borde = enOtro;
      } else if (lateralManda) {
        borde = lateral > 0 ? Borde.derecha : Borde.izquierda;
      } else {
        borde = frontal < 0 ? Borde.frente : Borde.atras;
      }
    }
    return borde;
  }

  static Borde _dominante(double lateral, double frontal) => lateral.abs() > frontal.abs()
      ? (lateral > 0 ? Borde.derecha : Borde.izquierda)
      : (frontal < 0 ? Borde.frente : Borde.atras);
}

/// Vuelco de un stick en el marco de quien lo sostiene (`null` = sin datos).
typedef Vuelco = ({double lateral, double frontal});

enum _Fase { eligiendo, siguiendo, acierto, melodia, terminado }

/// El juego Eco con los sticks reales (niveles 1 a 4: iguales, quietos y
/// opuestos). Reemplaza a la `SimulacionEco` de Joaquín y mueve el mismo
/// [EstadoJuegoEco], así que la pantalla no cambia.
///
/// Regla (confirmada el 18-11): **el guía elige libre** cualquiera de los bordes
/// que usa la partitura del nivel; el que sigue va al mismo borde (`S`, `H`) o al
/// contrario (`O`). Cada acierto toca el **siguiente** trozo. Sin sonido de error.
///
/// Dart puro y sin relojes propios: quien lo usa llama a [tick] con la hora en ms.
class MotorEco {
  MotorEco({
    required this.nivel,
    required this.estado,
    required this.tocarTrozo,
    required this.tocarMelodia,
    required this.alTerminar,
    this.ajustes = const AjustesEco(),
  })  : _detAdulto = DetectorBorde(ajustes),
        _detNino = DetectorBorde(ajustes),
        pasos = nivel.pasosEco,
        permitidos = {for (final p in nivel.pasosEco) Borde.desdeLetra(p.direccion)!};

  final NivelEco nivel;
  final EstadoJuegoEco estado;
  final void Function(int indice) tocarTrozo;
  final void Function() tocarMelodia;
  final void Function() alTerminar;
  final AjustesEco ajustes;

  final List<PasoEco> pasos;

  /// Bordes que el guía puede elegir en este nivel.
  final Set<Borde> permitidos;

  /// Niveles que este motor sabe jugar (los demás siguen con la simulación).
  static bool soporta(NivelEco n) => n.pasosEco.every(
      (p) => p.tipo == TipoPaso.iguales || p.tipo == TipoPaso.opuestos || p.tipo == TipoPaso.quietos);

  final DetectorBorde _detAdulto, _detNino;
  _Fase _fase = _Fase.eligiendo;
  int _paso = 0;
  bool _guiaCentrado = false;
  Borde? _candidato;
  double _candidatoDesde = 0;
  Borde? _elegido;
  Borde? _objetivo;
  double? _guiaFueraDesde;
  double? _juntosDesde;
  double _faseDesde = 0;
  int _destellos = 0;
  bool _iniciado = false;

  /// Paso actual (0 = primer trozo). Para pruebas y el registro.
  int get paso => _paso;
  bool get terminado => _fase == _Fase.terminado;
  Borde? get elegido => _elegido;
  Borde? get objetivo => _objetivo;
  Borde? get bordeAdulto => _detAdulto.borde;
  Borde? get bordeNino => _detNino.borde;

  bool get _guiaAdulto => nivel.guiaAdulto;
  Guia get _quienGuia => _guiaAdulto ? Guia.adulto : Guia.nino;
  ColorPista get _colorSigue => _guiaAdulto ? ColorPista.nino : ColorPista.adulto;

  /// Avanza el juego. [adulto] y [nino] en el marco de cada persona.
  void tick(double ahora, {Vuelco? adulto, Vuelco? nino}) {
    if (!_iniciado) {
      _iniciado = true;
      estado.reiniciar();
      _faseDesde = ahora;
      estado.cambiar(parpadea: _quienGuia);
    }
    final bA = adulto == null ? null : _detAdulto.actualizar(adulto.lateral, adulto.frontal);
    final bN = nino == null
        ? null
        : ajustes.ninoEnfrente
            ? _detNino.actualizar(-nino.lateral, -nino.frontal)
            : _detNino.actualizar(nino.lateral, nino.frontal);
    final bGuia = _guiaAdulto ? bA : bN;
    final bSigue = _guiaAdulto ? bN : bA;

    switch (_fase) {
      case _Fase.eligiendo:
        _luces(bA, bN);
        if (bGuia == null) _guiaCentrado = true;
        if (!_guiaCentrado || bGuia == null || !permitidos.contains(bGuia)) {
          _candidato = null;
          return;
        }
        if (_candidato != bGuia) {
          _candidato = bGuia;
          _candidatoDesde = ahora;
        }
        if (ahora - _candidatoDesde >= ajustes.elegirMs) _elegir(bGuia, ahora);
      case _Fase.siguiendo:
        _luces(bA, bN);
        _seguir(bGuia, bSigue, ahora);
      case _Fase.acierto:
        if (ahora - _faseDesde < ajustes.pausaAciertoMs) return;
        _paso++;
        final quedan = _paso < pasos.length;
        estado.cambiar(acierto: false, lucesVisibles: quedan);
        if (quedan) {
          _fase = _Fase.eligiendo;
          _guiaCentrado = false; // para el siguiente trozo el guía vuelve al centro
          _candidato = null;
          _elegido = _objetivo = null;
          estado.cambiar(parpadea: _quienGuia);
          _luces(bA, bN);
        } else {
          _fase = _Fase.melodia;
          _faseDesde = ahora;
          _destellos = 0;
        }
      case _Fase.melodia:
        _melodia(ahora);
      case _Fase.terminado:
        return;
    }
  }

  void _elegir(Borde b, double ahora) {
    _elegido = b;
    _objetivo = pasos[_paso].tipo == TipoPaso.opuestos ? b.opuesto : b;
    _guiaFueraDesde = null;
    _juntosDesde = null;
    _fase = _Fase.siguiendo;
    estado.cambiar(quitarParpadeo: true, pistas: {_objetivo!: _colorSigue}, quitarSostener: true);
  }

  void _seguir(Borde? bGuia, Borde? bSigue, double ahora) {
    final quietos = pasos[_paso].tipo == TipoPaso.quietos;
    if (bGuia != _elegido) {
      _guiaFueraDesde ??= ahora;
      _juntosDesde = null;
      if (quietos) estado.cambiar(quitarSostener: true, pistas: {_objetivo!: _colorSigue});
      if (ahora - _guiaFueraDesde! >= ajustes.graciaMs) {
        // El guía se fue: vuelve a elegir (puede ser otro borde).
        _fase = _Fase.eligiendo;
        _elegido = _objetivo = null;
        _candidato = null;
        _guiaCentrado = bGuia == null;
        estado.cambiar(pistas: const {}, quitarSostener: true, parpadea: _quienGuia);
      }
      return;
    }
    _guiaFueraDesde = null;
    if (bSigue != _objetivo) {
      if (_juntosDesde != null && quietos) {
        estado.cambiar(quitarSostener: true, pistas: {_objetivo!: _colorSigue});
      }
      _juntosDesde = null;
      return;
    }
    if (_juntosDesde == null) {
      _juntosDesde = ahora;
      if (quietos) estado.cambiar(pistas: const {}, sostener: _objetivo);
    }
    if (ahora - _juntosDesde! >= (quietos ? ajustes.quietosMs : ajustes.sostenerMs)) {
      _fase = _Fase.acierto;
      _faseDesde = ahora;
      estado.cambiar(
        acierto: true,
        pistas: const {},
        quitarSostener: true,
        lucesVisibles: false,
        quitarParpadeo: true,
        adulto: EstadoJuegoEco.reposoAdulto,
        nino: EstadoJuegoEco.reposoNino,
      );
      tocarTrozo(_paso);
    }
  }

  /// Final del prototipo: a los 0,9 s suena la melodía y la luz verde destella
  /// una vez por trozo (cada 2 s, 1,6 s encendida); 0,7 s después, el recuerdo.
  void _melodia(double ahora) {
    final t = ahora - _faseDesde;
    if (t < 900) return;
    if (_destellos == 0) {
      tocarMelodia();
      _destellos = 1;
    }
    final n = pasos.length;
    final enMelodia = t - 900;
    final i = (enMelodia / 2000).floor();
    final encendida = i < n && (enMelodia - i * 2000) < 1600;
    if (estado.acierto != encendida) estado.cambiar(acierto: encendida);
    if (enMelodia >= (n - 1) * 2000 + 1600 + 700) {
      _fase = _Fase.terminado;
      alTerminar();
    }
  }

  void _luces(Borde? bA, Borde? bN) {
    final a = EstadoJuegoEco.enBorde(bA, true), c = EstadoJuegoEco.enBorde(bN, false);
    if (a != estado.adulto || c != estado.nino) estado.cambiar(adulto: a, nino: c);
  }
}
