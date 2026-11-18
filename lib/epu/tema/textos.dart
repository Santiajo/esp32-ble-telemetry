import 'package:flutter/painting.dart';

import 'colores.dart';

/// Estilos de texto de Epu (Nunito).
///
/// Cómo se tradujo desde el CSS del prototipo:
/// * `line-height` → [TextStyle.height] con
///   [TextLeadingDistribution.even]: reparte el interlineado arriba y abajo
///   igual que el navegador.
/// * `letter-spacing: -.02em` → píxeles (−0,02 × tamaño).
/// * Peso 400: el prototipo solo carga Nunito 600–900, así que todo texto sin
///   peso explícito (los párrafos) se ve en 600. Aquí se usa 600 directamente.
///
/// Los nombres coinciden con los estilos de texto del kit en Figma.
class EpuTextos {
  EpuTextos._();

  static const String familia = 'Nunito';

  /// Estilo base. Úsalo con `.copyWith` cuando una pantalla necesita un
  /// color o un interlineado distinto.
  static TextStyle nunito(
    double tamano,
    FontWeight peso, {
    double alto = 1.35,
    double espaciadoEm = 0,
    Color color = EpuColores.tinta,
  }) =>
      TextStyle(
        fontFamily: familia,
        fontSize: tamano,
        fontWeight: peso,
        height: alto,
        letterSpacing: espaciadoEm * tamano,
        leadingDistribution: TextLeadingDistribution.even,
        color: color,
      );

  // ── Títulos ──────────────────────────────────────────────────────────────
  /// h1 de «¿Qué melodía van a descubrir?» y «La descubrieron juntos»:
  /// 32 px, 900, line-height 1.05, letter-spacing −.02em.
  static final tituloGrande =
      nunito(32, FontWeight.w900, alto: 1.05, espaciadoEm: -.02);

  /// h2 de «Guía el adulto / niño»: 32 px, 900, line-height 1.1, −.02em.
  static final tituloGuia =
      nunito(32, FontWeight.w900, alto: 1.1, espaciadoEm: -.02);

  /// h2 de «Calibren los sticks» y del nombre del nivel: 28 px, 900, 1.1, −.01em.
  static final tituloMediano =
      nunito(28, FontWeight.w900, alto: 1.1, espaciadoEm: -.01);

  /// h2 de las pantallas de preparación: 26 px, 900, 1.1, −.01em.
  static final tituloPequeno =
      nunito(26, FontWeight.w900, alto: 1.1, espaciadoEm: -.01);

  /// h2 de «Se perdió el stick…»: 24 px, 900, 1.1, −.01em.
  static final tituloAviso =
      nunito(24, FontWeight.w900, alto: 1.1, espaciadoEm: -.01);

  /// «Sesiones pasadas»: 18 px, 900, −.01em.
  static final tituloSeccion =
      nunito(18, FontWeight.w900, espaciadoEm: -.01);

  /// Nombre del nivel en la tarjeta: 16 px, 900, line-height 1.1.
  static final tarjetaTitulo = nunito(16, FontWeight.w900, alto: 1.1);

  // ── Cuerpo ───────────────────────────────────────────────────────────────
  /// Párrafos (15 px, color cuerpo). En CSS no tienen peso → se ven en 600.
  static final cuerpo =
      nunito(15, FontWeight.w600, color: EpuColores.textoCuerpo);

  /// Subtítulo fuerte (peculiaridad del nivel, resumen del recuerdo).
  static final subtitulo = nunito(15, FontWeight.w800);

  /// Frase de apoyo bajo el logo en «Inicio».
  static final lema =
      nunito(16, FontWeight.w600, color: EpuColores.textoCuerpo);

  /// Notas cortas (13 px, 700, secundario): «Quédense quietos…».
  static final detalle =
      nunito(13, FontWeight.w700, color: EpuColores.textoSecundario);

  /// Etiquetas de nivel arriba de la pantalla (13 px, 800, secundario).
  static final etiqueta =
      nunito(13, FontWeight.w800, color: EpuColores.textoSecundario);

  /// Instrumento y peculiaridad en la tarjeta de nivel (12 px, 700).
  static final mini =
      nunito(12, FontWeight.w700, color: EpuColores.textoSecundario);

  /// Dificultad bajo la etiqueta del nivel (12 px, 800).
  static final miniFuerte =
      nunito(12, FontWeight.w800, color: EpuColores.textoSecundario);

  /// Dificultad dentro de la tarjeta de nivel (11 px, 800).
  static final miniDificultad =
      nunito(11, FontWeight.w800, color: EpuColores.textoSecundario);

  /// Leyenda del recuerdo («Guió el adulto»): 12,5 px, 800.
  static final leyenda =
      nunito(12.5, FontWeight.w800, color: EpuColores.textoCuerpo);

  // ── Botones ──────────────────────────────────────────────────────────────
  /// Botón principal (17 px, 800, blanco). Altura de línea 1.35 heredada.
  static final botonGrande =
      nunito(17, FontWeight.w800, color: EpuColores.blanco);

  /// Botones con estado (conectar, calibrar): line-height 1.15.
  static final botonEstado = nunito(17, FontWeight.w800, alto: 1.15);

  /// Botones dobles del recuerdo y botón de reconectar: 15 px, 800, 1.15.
  static final botonMediano = nunito(15, FontWeight.w800, alto: 1.15);

  /// «Atrás»: 13 px, 800.
  static final botonAtras = nunito(13, FontWeight.w800);

  /// Número de paso dentro del círculo: 15 px, 900, line-height 1.
  static final pasoNumero = nunito(15, FontWeight.w900, alto: 1);
}
