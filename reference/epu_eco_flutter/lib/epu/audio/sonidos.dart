import 'package:audioplayers/audioplayers.dart';

import '../datos/niveles.dart';

/// Sonidos del flujo Eco.
///
/// En el prototipo los sonidos se sintetizan en vivo con Web Audio
/// (osciladores + filtro). Aquí se reproducen los audios ya grabados con ese
/// mismo código (carpeta assets/sonidos, la misma que «epu_sonidos/por_nivel»),
/// así que suenan igual.
///
/// | Prototipo                                   | Aquí                    |
/// |---------------------------------------------|-------------------------|
/// | `tone()` al conectar un stick (Do5, 0,8 s)  | [tonoConexion]          |
/// | `play(i, i + 1)` al acertar un trozo        | [tocarTrozo]            |
/// | `play(0, n)` al terminar / «Escuchar…»      | [tocarMelodia]          |
///
/// No hay sonido de error: así lo define la mecánica.
///
/// Si se cambia `audioplayers` por otro paquete, este es el único archivo
/// que hay que tocar.
class EpuSonidos {
  EpuSonidos._();

  static final EpuSonidos instancia = EpuSonidos._();

  static const _carpeta = 'sonidos';

  // Tres voces para los trozos: la cola de un trozo (hasta 2 s en el handpan)
  // puede seguir sonando cuando empieza el siguiente.
  final List<AudioPlayer> _voces = [];
  int _siguienteVoz = 0;
  AudioPlayer? _melodia;
  AudioPlayer? _tono;

  static String _trozo(NivelEco n, int i) => '$_carpeta/nivel${n.id}_${n.clave}_trozo${i + 1}.wav';
  static String _completa(NivelEco n) => '$_carpeta/nivel${n.id}_${n.clave}_completa.wav';

  /// Deja listos en memoria los audios del nivel, para que el trozo suene
  /// apenas aciertan (llamar al entrar a «Antes del nivel» o a «Calibrar»).
  Future<void> precargarNivel(NivelEco nivel) async {
    await AudioCache.instance.loadAll([
      for (var i = 0; i < nivel.trozos; i++) _trozo(nivel, i),
      _completa(nivel),
      '$_carpeta/conexion_stick.wav',
    ]);
  }

  /// Tono corto que suena cuando un stick termina de conectarse.
  Future<void> tonoConexion() async {
    final p = _tono ??= AudioPlayer();
    await p.stop();
    await p.play(AssetSource('$_carpeta/conexion_stick.wav'), mode: PlayerMode.lowLatency);
  }

  /// Trozo [indice] (desde 0) del [nivel]: suena cuando la díada acierta.
  Future<void> tocarTrozo(NivelEco nivel, int indice) async {
    if (_voces.isEmpty) {
      for (var i = 0; i < 3; i++) {
        _voces.add(AudioPlayer());
      }
    }
    final p = _voces[_siguienteVoz];
    _siguienteVoz = (_siguienteVoz + 1) % _voces.length;
    await p.stop();
    await p.play(AssetSource(_trozo(nivel, indice)), mode: PlayerMode.lowLatency);
  }

  /// Melodía completa del [nivel] (al terminar el nivel y en el recuerdo).
  /// Dura 2 s por trozo más la cola del último sonido.
  Future<void> tocarMelodia(NivelEco nivel) async {
    final p = _melodia ??= AudioPlayer();
    await p.stop();
    // Modo normal (no lowLatency): en Android, lowLatency usa SoundPool, que
    // no está pensado para audios de más de unos pocos segundos.
    await p.play(AssetSource(_completa(nivel)), mode: PlayerMode.mediaPlayer);
  }

  /// Corta todo (al salir de una pantalla con sonido).
  Future<void> detener() async {
    for (final p in [..._voces, _melodia, _tono]) {
      await p?.stop();
    }
  }
}
