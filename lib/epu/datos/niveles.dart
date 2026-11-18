import '../ilustraciones/geometria_mano.dart';

/// Quién guía un nivel. En cada nivel guía una sola persona.
enum Guia { adulto, nino }

/// Los 7 niveles del flujo Eco.
///
/// Todo sale del prototipo. Para no perder la pista, cada campo dice de qué
/// tabla viene:
/// * `MEL` de EcoAntes.dc.html → nombre, instrumento, dificultad,
///   peculiaridad, texto e `alt`.
/// * `MEL` de EcoGuia.dc.html → quién guía y el texto de «Quién guía».
/// * `MEL` de EcoJuego.dc.html → pasos (la partitura oculta) y fragmentos.
/// * `PH` de EcoAntes.dc.html → la animación de las manos.
/// * Las miniaturas de EcoNiveles.dc.html.
class NivelEco {
  const NivelEco({
    required this.id,
    required this.nombre,
    required this.instrumento,
    required this.clave,
    required this.dificultad,
    required this.peculiaridad,
    required this.texto,
    required this.alt,
    required this.guia,
    required this.textoGuia,
    required this.pasos,
    required this.fragmentos,
    required this.fases,
    required this.miniatura,
  });

  final int id;

  /// «Madera», «Viento»…
  final String nombre;

  /// «Marimba», «Flauta dulce»…
  final String instrumento;

  /// Parte del nombre de los audios: `nivel{id}_{clave}_trozo{n}.wav`.
  final String clave;

  /// 1 Fácil, 2 Media, 3 Difícil.
  final int dificultad;

  /// La peculiaridad de movimiento del nivel («Juntos», «Quietos»…).
  final String peculiaridad;

  /// Texto de «Antes del nivel».
  final String texto;

  /// Descripción accesible de la ilustración de «Antes del nivel».
  final String alt;

  final Guia guia;

  /// Texto de «Quién guía».
  final String textoGuia;

  /// La partitura oculta: un paso por trozo, con el formato del prototipo
  /// `TIPO:DIRECCIÓN`. Ver [PasoEco].
  final List<String> pasos;

  /// Notas de cada trozo (`A3:2 C4:2`). Cada número son tiempos de 0,5 s.
  /// Todos los trozos suman 4 tiempos = 2 s (lo usa la animación del recuerdo).
  final List<String> fragmentos;

  /// Animación de las manos en «Antes del nivel»: lista de fases
  /// (dirección adulto, dirección niño, duración ms, tipo). Ver [FaseAntes].
  final List<FaseAntes> fases;

  /// Cómo se dibuja la miniatura en «Elegir nivel».
  final Miniatura miniatura;

  int get trozos => fragmentos.length;
  bool get guiaAdulto => guia == Guia.adulto;

  /// «Fácil», «Media» o «Difícil».
  String get dificultadTexto => const ['', 'Fácil', 'Media', 'Difícil'][dificultad];

  /// En el nivel 7 el último trozo lo elige el niño.
  bool get ultimoTrozoNino => id == 7;

  /// Pasos ya interpretados.
  List<PasoEco> get pasosEco => [for (final p in pasos) PasoEco.desde(p)];

  static NivelEco de(int id) => niveles[(id.clamp(1, 7)) - 1];
}

/// Tipos de paso de la partitura oculta (primera letra en el prototipo).
enum TipoPaso {
  /// S · iguales: los dos vuelcan hacia el mismo borde.
  iguales,

  /// O · opuestos: quien sigue va al borde contrario del guía.
  opuestos,

  /// H · quietos: van al mismo borde y se quedan ahí hasta que suene.
  quietos,

  /// G · giro: giran la punta en círculo hacia el mismo lado (+ / −).
  giro,

  /// E · eco por turnos: el guía va a un borde y vuelve; después el otro repite.
  eco,

  /// Q · igual que «iguales» pero guía el niño (último trozo del nivel 7).
  igualesGuiaNino,
}

/// Un paso de la partitura: tipo + dirección (F, B, L, R, o + / − en el giro).
class PasoEco {
  const PasoEco(this.tipo, this.direccion);

  factory PasoEco.desde(String codigo) {
    final tipo = switch (codigo[0]) {
      'S' => TipoPaso.iguales,
      'O' => TipoPaso.opuestos,
      'H' => TipoPaso.quietos,
      'G' => TipoPaso.giro,
      'E' => TipoPaso.eco,
      'Q' => TipoPaso.igualesGuiaNino,
      _ => throw ArgumentError('Paso desconocido: $codigo'),
    };
    return PasoEco(tipo, codigo.substring(2));
  }

  final TipoPaso tipo;

  /// 'F' adelante, 'B' atrás, 'L' izquierda, 'R' derecha; '+' o '−' (giro).
  final String direccion;
}

/// Una fase de la animación de «Antes del nivel».
class FaseAntes {
  const FaseAntes(this.adulto, this.nino, this.ms, [this.tipo = '']);

  /// Dirección de cada stick: '', 'F', 'B', 'L' o 'R' ('' = al centro).
  final String adulto, nino;

  /// Cuánto dura la fase.
  final int ms;

  /// '' normal, 'h' quietos (se enciende el anillo de la luz), 'g' giro (se
  /// muestra la flecha de giro en vez de la recta).
  final String tipo;

  bool get giro => tipo == 'g';
  bool get quieto => tipo == 'h';
}

/// Flecha de una miniatura: recta con ángulo, de giro o ninguna.
class FlechaMiniatura {
  const FlechaMiniatura.recta(this.grados, {this.opacidad = 1}) : giro = false;
  const FlechaMiniatura.giro()
      : grados = 0,
        opacidad = 1,
        giro = true;

  final double grados;
  final double opacidad;
  final bool giro;
}

/// Pose congelada de cada mano en la tarjeta de «Elegir nivel».
class Miniatura {
  const Miniatura({
    required this.adulto,
    required this.nino,
    required this.flechaAdulto,
    required this.flechaNino,
    this.anillo = false,
  });

  final Pose adulto, nino;
  final FlechaMiniatura flechaAdulto, flechaNino;

  /// Anillo de «quietos» encendido en las dos luces (nivel 2).
  final bool anillo;
}

const niveles = <NivelEco>[
  NivelEco(
    id: 1,
    nombre: 'Madera',
    instrumento: 'Marimba',
    clave: 'madera',
    dificultad: 1,
    peculiaridad: 'Juntos',
    texto: 'Vuelquen el stick los dos hacia el mismo borde de la pantalla, arriba o abajo. Como dos remos que van a la par.',
    alt: 'Los dos sticks se vuelcan hacia el mismo borde',
    guia: Guia.adulto,
    textoGuia: 'El adulto elige si van hacia arriba o hacia abajo. El niño vuelca su stick hacia el mismo borde.',
    pasos: ['S:F', 'S:B', 'S:B', 'S:F'],
    fragmentos: ['A3:2 C4:2', 'D4:2 E4:2', 'D4:1 C4:1 A3:2', 'C4:2 A3:2'],
    fases: [
      FaseAntes('F', 'F', 1100),
      FaseAntes('', '', 700),
      FaseAntes('B', 'B', 1100),
      FaseAntes('', '', 700),
    ],
    miniatura: Miniatura(
      adulto: Pose.adelante,
      nino: Pose.adelante,
      flechaAdulto: FlechaMiniatura.recta(0),
      flechaNino: FlechaMiniatura.recta(0),
    ),
  ),
  NivelEco(
    id: 2,
    nombre: 'Viento',
    instrumento: 'Flauta dulce',
    clave: 'viento',
    dificultad: 1,
    peculiaridad: 'Quietos',
    texto: 'Vuelquen el stick hacia el mismo borde y quédense ahí, sin moverse, hasta que suene. Como una nota larga de flauta.',
    alt: 'Los dos sticks se vuelcan hacia el mismo borde y se quedan quietos',
    guia: Guia.nino,
    textoGuia: 'El niño elige un borde y se queda ahí. El adulto va al mismo borde y esperan quietos hasta que suene.',
    pasos: ['H:F', 'H:R', 'H:L', 'H:B'],
    fragmentos: ['E4:2 G4:2', 'A4:3 G4:1', 'E4:2 D4:2', 'E4:4'],
    fases: [
      FaseAntes('R', 'R', 2400, 'h'),
      FaseAntes('', '', 800),
      FaseAntes('F', 'F', 2400, 'h'),
      FaseAntes('', '', 800),
    ],
    miniatura: Miniatura(
      adulto: Pose.derecha,
      nino: Pose.derecha,
      flechaAdulto: FlechaMiniatura.recta(90),
      flechaNino: FlechaMiniatura.recta(90),
      anillo: true,
    ),
  ),
  NivelEco(
    id: 3,
    nombre: 'Cuerda',
    instrumento: 'Guitarra',
    clave: 'cuerda',
    dificultad: 2,
    peculiaridad: 'Lados contrarios',
    texto: 'Cada uno vuelca el stick hacia un costado distinto: si uno va a la izquierda, el otro va a la derecha. Como estirar un elástico entre los dos.',
    alt: 'Un stick se vuelca hacia la izquierda y el otro hacia la derecha',
    guia: Guia.nino,
    textoGuia: 'El niño elige un costado, izquierda o derecha. El adulto va hacia el costado contrario.',
    pasos: ['O:L', 'O:R', 'O:R', 'O:L'],
    fragmentos: ['A3:1 E4:1 D4:2', 'C4:1 D4:1 E4:2', 'G4:2 E4:2', 'D4:1 C4:1 A3:2'],
    fases: [
      FaseAntes('L', 'R', 1100),
      FaseAntes('', '', 700),
      FaseAntes('R', 'L', 1100),
      FaseAntes('', '', 700),
    ],
    miniatura: Miniatura(
      adulto: Pose.izquierda,
      nino: Pose.derecha,
      flechaAdulto: FlechaMiniatura.recta(270),
      flechaNino: FlechaMiniatura.recta(90),
    ),
  ),
  NivelEco(
    id: 4,
    nombre: 'Caña',
    instrumento: 'Clarinete',
    clave: 'cana',
    dificultad: 2,
    peculiaridad: 'Sube y baja',
    texto: 'Uno vuelca el stick hacia arriba y el otro hacia abajo, y después cambian. Como un balancín.',
    alt: 'Un stick se vuelca hacia arriba mientras el otro va hacia abajo, y se alternan',
    guia: Guia.adulto,
    textoGuia: 'El adulto elige si parte hacia arriba o hacia abajo. El niño va al revés, y después cambian.',
    pasos: ['O:F', 'O:B', 'O:F', 'O:B', 'O:F'],
    fragmentos: ['D4:2 E4:2', 'G4:3 E4:1', 'D4:2 C4:2', 'A3:2 C4:2', 'D4:4'],
    fases: [
      FaseAntes('F', 'B', 1100),
      FaseAntes('B', 'F', 1100),
    ],
    miniatura: Miniatura(
      adulto: Pose.adelante,
      nino: Pose.atras,
      flechaAdulto: FlechaMiniatura.recta(0),
      flechaNino: FlechaMiniatura.recta(180),
    ),
  ),
  NivelEco(
    id: 5,
    nombre: 'Metal',
    instrumento: 'Handpan',
    clave: 'metal',
    dificultad: 2,
    peculiaridad: 'Giro',
    texto: 'Giren la punta del stick en círculo alrededor del centro, los dos hacia el mismo lado. Como revolver una olla.',
    alt: 'Los dos sticks giran la punta en círculo hacia el mismo lado',
    guia: Guia.nino,
    textoGuia: 'El niño elige hacia qué lado girar. El adulto se suma y giran juntos.',
    pasos: ['G:+', 'G:+', 'G:-', 'G:+', 'G:-'],
    fragmentos: ['A3:1 C4:1 E4:2', 'D4:1 E4:1 G4:2', 'A4:2 G4:2', 'E4:1 D4:1 C4:2', 'A3:4'],
    fases: [
      FaseAntes('L', 'L', 420, 'g'),
      FaseAntes('F', 'F', 420, 'g'),
      FaseAntes('R', 'R', 420, 'g'),
      FaseAntes('B', 'B', 420, 'g'),
    ],
    miniatura: Miniatura(
      adulto: Pose.giro,
      nino: Pose.giro,
      flechaAdulto: FlechaMiniatura.giro(),
      flechaNino: FlechaMiniatura.giro(),
    ),
  ),
  NivelEco(
    id: 6,
    nombre: 'Voces',
    instrumento: 'Coro',
    clave: 'voces',
    dificultad: 3,
    peculiaridad: 'Eco por turnos',
    texto: 'Uno vuelca el stick hacia un borde y vuelve al centro. Después el otro repite el mismo movimiento. Como un eco.',
    alt: 'Un stick se vuelca hacia un borde y después el otro repite el mismo movimiento',
    guia: Guia.adulto,
    textoGuia: 'El adulto vuelca el stick hacia un borde y vuelve al centro. El niño repite el mismo movimiento.',
    pasos: ['E:F', 'E:L', 'E:B', 'E:R', 'E:L', 'E:F'],
    fragmentos: ['A3:4', 'C4:2 D4:2', 'E4:4', 'G4:2 E4:2', 'D4:2 C4:2', 'A3:4'],
    fases: [
      FaseAntes('F', '', 1000),
      FaseAntes('', '', 500),
      FaseAntes('', 'F', 1000),
      FaseAntes('', '', 800),
      FaseAntes('', 'L', 1000),
      FaseAntes('', '', 500),
      FaseAntes('L', '', 1000),
      FaseAntes('', '', 800),
    ],
    miniatura: Miniatura(
      adulto: Pose.izquierda,
      nino: Pose.centro,
      flechaAdulto: FlechaMiniatura.recta(270),
      flechaNino: FlechaMiniatura.recta(270, opacidad: .4),
    ),
  ),
  NivelEco(
    id: 7,
    nombre: 'Teclas',
    instrumento: 'Piano',
    clave: 'teclas',
    dificultad: 3,
    peculiaridad: 'Mezcla',
    texto: 'Aquí se mezcla todo: juntos, contrarios, giros y turnos. El último trozo lo elige el niño y el adulto lo sigue.',
    alt: 'Los sticks combinan los movimientos de los niveles anteriores',
    guia: Guia.adulto,
    textoGuia: 'El adulto va eligiendo los movimientos y el niño responde. El último trozo lo elige el niño.',
    pasos: ['S:F', 'O:R', 'G:+', 'O:B', 'E:L', 'Q:L'],
    fragmentos: ['E4:1 G4:1 A4:2', 'G4:1 E4:1 D4:2', 'C4:1 D4:1 E4:2', 'G4:2 A4:2', 'E4:1 D4:1 C4:2', 'A3:4'],
    fases: [
      FaseAntes('F', 'F', 1000),
      FaseAntes('', '', 500),
      FaseAntes('L', 'R', 1000),
      FaseAntes('', '', 500),
      FaseAntes('L', 'L', 400, 'g'),
      FaseAntes('F', 'F', 400, 'g'),
      FaseAntes('R', 'R', 400, 'g'),
      FaseAntes('B', 'B', 400, 'g'),
      FaseAntes('', '', 700),
      FaseAntes('', 'B', 1000),
      FaseAntes('', '', 500),
      FaseAntes('B', '', 1000),
      FaseAntes('', '', 800),
    ],
    miniatura: Miniatura(
      adulto: Pose.adelante,
      nino: Pose.giro,
      flechaAdulto: FlechaMiniatura.recta(0),
      flechaNino: FlechaMiniatura.giro(),
    ),
  ),
];

/// Pose de cada dirección en «Antes del nivel» (tabla `POSE` del prototipo).
Pose poseDe(String direccion) => switch (direccion) {
      'L' => Pose.izquierda,
      'R' => Pose.derecha,
      'F' => Pose.adelante,
      'B' => Pose.atras,
      _ => Pose.centro,
    };
