import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../datos/niveles.dart';
import '../util/css.dart';
import 'geometria_mano.dart';
import 'manos.dart';
import 'movimiento_antes.dart';

/// Animación de las manos en «Antes del nivel» (EcoAntes.dc.html).
///
/// El prototipo la arma con dos cadenas de `setTimeout`:
/// * `tick()` cambia de fase según la tabla `PH` del nivel. La primera fase
///   dura 600 ms más que su valor (el `tick` arranca a los 600 ms).
/// * `step()` corre cada 33 ms y acerca cada ángulo un 22 % a su objetivo
///   (y lo deja exacto cuando le falta menos de 0,2°).
///
/// Aquí se reproduce lo mismo con un reloj: [avanzar] recibe los ms desde que
/// se abrió la pantalla y simula los pasos de 33 ms que tocan, así el
/// movimiento es igual sin importar los cuadros por segundo del teléfono.
///
/// Flechas (clase `.ar` y sus animaciones):
/// * Cuando un stick toma una dirección, su flecha entra en 600 ms
///   (`cubic-bezier(.2,.7,.3,1)`): aparece y avanza de −5 a +1,5 unidades en
///   el sentido que indica.
/// * Cuando vuelve al centro, la flecha se apaga en 250 ms (ease). Igual que
///   en el prototipo, mientras se apaga vuelve a apuntar hacia arriba y sin
///   desplazamiento (ver [conservarDireccionAlApagar]).
/// * En las fases de giro se apagan las rectas y aparece la flecha de giro
///   (250 ms), que da una vuelta cada 1,68 s.
class AnimacionAntes {
  AnimacionAntes(this.nivel, {this.quieta = false, this.conservarDireccionAlApagar = false}) {
    _mov = MovimientoAntes(nivel.fases, quieta: quieta, alCambiarFase: (_, inicio) => _aplicarClases(inicio));
    _aplicarClases(0, inicial: true);
  }

  final NivelEco nivel;

  /// «Quitar animaciones»: primera fase fija, sin flechas que entran.
  final bool quieta;

  /// `false` = idéntico al prototipo (la flecha que se apaga gira hacia
  /// arriba de golpe). `true` = conserva su dirección mientras se apaga, que
  /// se ve un poco más prolijo.
  final bool conservarDireccionAlApagar;

  late final MovimientoAntes _mov;

  final _flechas = [_Flecha(), _Flecha()];
  final _giros = [_Giro(), _Giro()];

  double _ms = 0;

  /// Avanza la animación hasta [ms] (milisegundos desde que se abrió).
  void avanzar(double ms) {
    _mov.avanzar(ms);
    _ms = ms;
  }

  String _clase(String dir, bool giro) => dir.isNotEmpty && !giro ? dir : '';

  void _aplicarClases(double t, {bool inicial = false}) {
    final f = nivel.fases[_mov.fase];
    final dirs = [f.adulto, f.nino];
    for (var i = 0; i < 2; i++) {
      final fl = _flechas[i];
      final nueva = _clase(dirs[i], f.giro);
      fl.grados = Direccion.desdeLetra(dirs[i])?.grados ?? 0;
      if (inicial || nueva != fl.clase) {
        if (nueva.isNotEmpty) {
          fl.inicioEntrada = t;
        } else {
          fl.opacidadAlApagar = inicial ? 0 : fl.opacidad(t, quieta);
          fl.inicioApagado = t;
          // Dirección con la que se apaga si se conserva (la que tenía).
          fl.gradosApagado = Direccion.desdeLetra(fl.clase)?.grados ?? 0;
        }
        fl.clase = nueva;
      }
      final gi = _giros[i];
      final objetivo = f.giro ? 1.0 : 0.0;
      if (inicial) {
        gi
          ..desde = objetivo
          ..objetivo = objetivo
          ..inicio = t;
      } else if (objetivo != gi.objetivo) {
        gi
          ..desde = gi.valor(t, quieta)
          ..objetivo = objetivo
          ..inicio = t;
      }
    }
  }

  // ── Lo que se dibuja ahora ───────────────────────────────────────────────
  GeometriaMano get geometriaAdulto => GeometriaMano(_mov.cur[0], _mov.cur[1]);
  GeometriaMano get geometriaNino => GeometriaMano(_mov.cur[2], _mov.cur[3]);

  FaseAntes get faseActual => nivel.fases[_mov.fase];

  /// Pinta toda la escena en coordenadas del viewBox 120 × 100.
  void pintar(Canvas canvas) {
    final ms = _ms;
    // 1. Flechas rectas y de giro (detrás de las manos).
    final giroRad = quieta ? 0.0 : (ms % 1680) / 1680 * 2 * math.pi;
    for (var i = 0; i < 2; i++) {
      final fl = _flechas[i];
      final enMovimiento = fl.clase.isNotEmpty;
      dibujarFlecha(
        canvas,
        en: i == 0 ? PosicionesFlecha.adulto : PosicionesFlecha.nino,
        // Sin dirección, el prototipo usa el `rotate()` de la fase actual
        // (0 al volver al centro): la flecha que se apaga apunta arriba.
        grados: enMovimiento || !conservarDireccionAlApagar ? fl.grados : fl.gradosApagado,
        opacidad: fl.opacidad(ms, quieta),
        desplazamiento: enMovimiento ? fl.desplazamiento(ms, quieta) : Offset.zero,
      );
      dibujarGiro(
        canvas,
        en: i == 0 ? PosicionesFlecha.giroAdultoAntes : PosicionesFlecha.nino,
        opacidad: _giros[i].valor(ms, quieta),
        radianes: giroRad,
      );
    }
    // 2. Manos. El anillo se enciende en las fases «quietos» y late (`hr`,
    //    1 s, .8 ↔ 1.25).
    final anillo = faseActual.quieto ? 1.0 : 0.0;
    final escalaAnillo = quieta ? 1.0 : latido((ms % 1000) / 1000, .8, 1.25);
    final luz = LuzMano(anilloOpacidad: anillo, anilloEscala: escalaAnillo);
    dibujarMano(canvas, geometriaAdulto, EstiloMano.adulto, luz);
    dibujarMano(canvas, geometriaNino, EstiloMano.nino, luz);
  }
}

class _Flecha {
  String clase = ''; // '' o la letra de la dirección (equivale a `.ar.dF`…)
  double grados = 0;
  double gradosApagado = 0;
  double inicioEntrada = 0;
  double inicioApagado = 0;
  double opacidadAlApagar = 0;

  double _entrada(double ms) =>
      CurvasEpu.flecha.transform(((ms - inicioEntrada) / 600).clamp(0.0, 1.0));

  double opacidad(double ms, bool quieta) {
    if (clase.isNotEmpty) return quieta ? 1 : _entrada(ms);
    if (quieta) return 0;
    final p = ((ms - inicioApagado) / 250).clamp(0.0, 1.0);
    return opacidadAlApagar * (1 - Curves.ease.transform(p));
  }

  Offset desplazamiento(double ms, bool quieta) {
    if (quieta) return Offset.zero;
    final v = Direccion.desdeLetra(clase)!.vector;
    return v * (-5 + 6.5 * _entrada(ms));
  }
}

class _Giro {
  double desde = 0, objetivo = 0, inicio = 0;

  double valor(double ms, bool quieta) {
    if (quieta) return objetivo;
    final p = ((ms - inicio) / 250).clamp(0.0, 1.0);
    return mezclar(desde, objetivo, Curves.ease.transform(p));
  }
}
