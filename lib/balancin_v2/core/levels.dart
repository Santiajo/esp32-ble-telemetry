/// Catálogo de niveles de la mecánica v2 (prototipo §11.1, `LEVELS`).
///
/// Los siete niveles están definidos; cuáles se pueden jugar lo decide
/// [enabledLevelIds] (los siete desde el 05-11-2026).
library;

enum Role { adult, child }

/// Relación que pide cada nivel. [free] = modo Libre; [song] = nivel 7 (encadena partes).
enum Relation { together, mirror, same, seesaw, pulse, follow, song, free }

const Map<Relation, String> relationNames = {
  Relation.together: 'Juntos',
  Relation.mirror: 'Espejo',
  Relation.same: 'Iguales',
  Relation.seesaw: 'Señalados',
  Relation.pulse: 'Mismo pulso',
  Relation.follow: 'Sígueme',
};

/// Nombre de cada rol tal como lo dice la voz («Guía el adulto»).
const Map<Role, String> roleNames = {Role.adult: 'el adulto', Role.child: 'el niño'};

/// Notas con nombre (MIDI), como `NN` del prototipo.
const Map<String, int> noteNumbers = {
  'do3': 48, 're3': 50, 'mi3': 52, 'sol3': 55, 'la3': 57, //
  'do4': 60, 're4': 62, 'mi4': 64, 'sol4': 67, 'la4': 69,
  'do5': 72, 're5': 74, 'mi5': 76, 'sol5': 79, 'la5': 81, 'do6': 84,
};

/// Escala del adulto (do3–sol4) y del niño (do4–do6).
const List<int> adultScale = [48, 50, 52, 55, 57, 60, 62, 64, 67];
const List<int> childScale = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84];

class Level {
  const Level({
    required this.id,
    required this.name,
    required this.text,
    required this.relation,
    required this.guides,
    required this.tol,
    required this.sec,
    required this.phrase,
    required this.difficulty,
    this.parts = const [],
  });

  final int id;
  final String name;

  /// Consigna corta («Apunten el stick a ustedes mismos y al otro, sin parar.»).
  final String text;
  final Relation relation;

  /// Quién guía en cada mitad (o en cada parte, en el nivel 7). `null` = sin cambio de guía.
  final List<Role?> guides;

  /// Tolerancia de `d` antes de [SyncParams.tolScale].
  final double tol;

  /// Segundos en sincronía para completar (por parte, en el nivel 7), antes de [SyncParams.secScale].
  final double sec;

  /// Frase que suma a la canción (nombres de [noteNumbers]).
  final List<String> phrase;

  /// 1 = fácil · 2 = media · 3 = difícil.
  final int difficulty;

  /// Solo el nivel 7: relaciones que encadena.
  final List<Relation> parts;

  bool get isSong => relation == Relation.song;

  List<int> get phraseMidi => [for (final n in phrase) noteNumbers[n]!];

  /// Quién guía al empezar.
  Role get firstGuide => guides.first ?? Role.adult;

  /// Texto de guía que dice la voz al presentar el nivel (`guideOf` del prototipo).
  String get guideText {
    if (isSong) return 'La voz indica quién guía';
    final g0 = guides[0]!;
    final g1 = guides.length > 1 ? guides[1] : null;
    if (g1 == null) return 'Guía ${roleNames[g0]}';
    return 'Guía ${roleNames[g0]}, luego ${roleNames[g1]}';
  }

  String get difficultyName => const ['', 'Fácil', 'Media', 'Difícil'][difficulty];
}

const List<Level> levels = [
  Level(
      id: 1,
      name: 'Juntos',
      text: 'Apunten el stick a ustedes mismos y al otro, sin parar.',
      relation: Relation.together,
      guides: [Role.adult, Role.child],
      tol: 1.2,
      sec: 8,
      phrase: ['do4', 're4', 'mi4', 'sol4'],
      difficulty: 1),
  Level(
      id: 2,
      name: 'Espejo',
      text: 'Apunten al mismo lado, como en un espejo.',
      relation: Relation.mirror,
      guides: [Role.child, Role.adult],
      tol: 1.2,
      sec: 8,
      phrase: ['sol4', 'mi4', 're4', 'do4'],
      difficulty: 1),
  Level(
      id: 3,
      name: 'Iguales',
      text: 'Apunten el stick al mismo punto de la pieza.',
      relation: Relation.same,
      guides: [Role.adult, Role.child],
      tol: 1.0,
      sec: 8,
      phrase: ['mi4', 'sol4', 'la4', 'sol4'],
      difficulty: 2),
  Level(
      id: 4,
      name: 'Señalados',
      text: 'Apunten el stick a la misma persona.',
      relation: Relation.seesaw,
      guides: [Role.adult, Role.child],
      tol: 1.0,
      sec: 8,
      phrase: ['do5', 'la4', 'sol4', 'mi4'],
      difficulty: 2),
  Level(
      id: 5,
      name: 'Mismo pulso',
      text: 'Muevan el stick al mismo ritmo.',
      relation: Relation.pulse,
      guides: [Role.child, null],
      tol: 0.9,
      sec: 8,
      phrase: ['re4', 'mi4', 'sol4', 'la4'],
      difficulty: 2),
  Level(
      id: 6,
      name: 'Sígueme',
      text: 'Uno mueve la muñeca y el otro lo imita. Luego cambian.',
      relation: Relation.follow,
      guides: [Role.adult, Role.child],
      tol: 1.2,
      sec: 8,
      phrase: ['la4', 'sol4', 'mi4', 're4'],
      difficulty: 3),
  Level(
      id: 7,
      name: 'La canción',
      text: 'Usen todos los movimientos para terminar la canción.',
      relation: Relation.song,
      parts: [Relation.together, Relation.mirror, Relation.seesaw, Relation.pulse],
      guides: [Role.adult, Role.child, Role.adult, Role.child],
      tol: 0.8,
      sec: 6,
      phrase: ['do4', 'mi4', 'sol4', 'do5'],
      difficulty: 3),
];

/// Niveles que se pueden jugar. Desde el 05-11-2026 son los siete y se eligen en
/// cualquier orden (plan v2 §17).
const Set<int> enabledLevelIds = {1, 2, 3, 4, 5, 6, 7};

Level levelById(int id) => levels[id - 1];
