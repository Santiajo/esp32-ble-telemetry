import 'dart:ui' show Color;

/// Colores de Epu.
///
/// Los nombres de la primera parte son los de la colección de variables
/// «Epu · Colores» del kit en Figma (página «Epu Completo»). La segunda parte
/// son tonos que solo aparecen dentro de una pantalla o una ilustración del
/// prototipo; se anota dónde se usan para no confundirlos con el kit.
class EpuColores {
  EpuColores._();

  // ── Tinta · neutros oscuros ──────────────────────────────────────────────
  static const noche = Color(0xFF1D1927); // fondo de la pantalla de juego
  static const tinta = Color(0xFF2B2536); // texto principal y botón principal
  static const textoCuerpo = Color(0xFF4A445A);
  static const textoSecundario = Color(0xFF5A536B);

  // ── Papel · fondos y estructura ──────────────────────────────────────────
  static const blanco = Color(0xFFFFFFFF);
  static const fondo = Color(0xFFEFECE4);
  static const linea = Color(0xFFDCD8CF); // conectores de pasos, puntos apagados
  static const bloqueado = Color(0xFFD5CFC3); // botón «Comenzar» bloqueado
  static const pendienteBorde = Color(0xFFCFC8BA);
  static const bloqueadoBarra = Color(0xFFB8B1A4); // relleno de los 3 s
  static const pendienteTexto = Color(0xFFA39C8E);
  static const bloqueadoTexto = Color(0xFF6B6557);

  // ── Adulto · lila ────────────────────────────────────────────────────────
  static const lilaAdulto = Color(0xFFB3A2DC);
  static const lilaProfundo = Color(0xFF7B5FCB);

  // ── Niño · coral (en los textos de la app se le dice «naranjo») ─────────
  static const coralSuave = Color(0xFFF4C3B6);
  static const coralNino = Color(0xFFE85E45);

  // ── Estados · luz y confirmación ─────────────────────────────────────────
  static const teal = Color(0xFF0D9488);
  static const tealOscuro = Color(0xFF0B6F66);
  static const verdeAcierto = Color(0xFF4AD282); // luz verde del juego
  static const luzStick = Color(0xFFF2E44A); // luz amarilla de la punta

  // ── Tonos internos (no están en el kit) ──────────────────────────────────
  /// Flechas de movimiento y señales de las ilustraciones.
  static const flecha = Color(0xFF7E9142);

  /// Grises cálidos de las ilustraciones: suelo, manos, burbujas de avisos.
  static const ilustracionClaro = Color(0xFFDAD4C8);
  static const ilustracionLinea = Color(0xFFC3BCAD);

  /// Relleno del botón «Calibrar» mientras corre la barra de 3 s.
  static const rellenoCalibrar = Color(0xFFE6F4F2);

  /// Luz apagada de cada stick en «Conecta los dos sticks».
  static const luzApagadaAdulto = Color(0xFF9A8BC4);
  static const luzApagadaNino = Color(0xFFC24A35);

  /// «Pérdida de stick»: stick sin señal, luz apagada y fondos del botón.
  static const stickSinSenal = Color(0xFFCFC9D8);
  static const luzApagada = Color(0xFFE2DED6);
  static const tinteAdulto = Color(0xFFF1EDFA);
  static const tinteNino = Color(0xFFFCE6E1);

  /// Centro más claro de cada luz en el juego (degradado radial).
  static const centroLuzAdulto = Color(0xFFCFC2EE);
  static const centroLuzNino = Color(0xFFF28A76);

  /// Verde del brillo de fondo en «La descubrieron juntos».
  static const verdeRecuerdo = Color(0xFF22A054);

  /// Colores del logo (archivo logo-epu.svg).
  static const logoLila = Color(0xFFA896D6);
  static const logoVerde = Color(0xFF7E9142);
  static const logoCoral = Color(0xFFD9634D);
  static const logoAmarillo = Color(0xFFEBD75A);
}
