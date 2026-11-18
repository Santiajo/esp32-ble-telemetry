import 'dart:async';

import '../audio/sonidos.dart';
import '../datos/niveles.dart';
import 'estado_juego.dart';

/// La simulación de «Eco · descubrir la melodía», cuadro por cuadro igual que
/// la función `run()` de EcoJuego.dc.html.
///
/// Sirve para dos cosas:
/// 1. Ver la pantalla de juego funcionando sin sticks (demo, pruebas de UI).
/// 2. Como guion de lo que la lógica real tiene que producir: en cada paso,
///    1) la luz del que guía late, 2) el guía elige y su luz va al borde,
///    3) se enciende la franja del borde para el que sigue, 4) el otro
///    responde, 5) aciertan: suena el trozo, luz verde y las luces se apagan.
///
/// Los tiempos (`at(ms, …)`) son acumulativos, como en el prototipo.
class SimulacionEco {
  SimulacionEco({
    required this.nivel,
    required this.estado,
    required this.alTerminar,
    EpuSonidos? sonidos,
  }) : sonidos = sonidos ?? EpuSonidos.instancia;

  final NivelEco nivel;
  final EstadoJuegoEco estado;
  final EpuSonidos sonidos;

  /// Se llama al final, cuando el prototipo pasa a «el recuerdo».
  final void Function() alTerminar;

  final List<Timer> _timers = [];
  int _t = 0;

  void _at(int ms, void Function() fn) {
    _t += ms;
    _timers.add(Timer(Duration(milliseconds: _t), fn));
  }

  void detener() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void iniciar() {
    detener();
    _t = 0;
    final e = estado;
    final n = nivel.pasos.length;
    final guiaAdulto = nivel.guiaAdulto;

    // go(ad, d): mueve la luz de una persona al borde d (null = reposo).
    void ir(bool adulto, Borde? b) => adulto
        ? e.cambiar(adulto: EstadoJuegoEco.enBorde(b, true))
        : e.cambiar(nino: EstadoJuegoEco.enBorde(b, false));

    // ok(i): aciertan el trozo i.
    void acierto(int i) {
      e.cambiar(acierto: true, pistas: const {}, quitarSostener: true, lucesVisibles: false, quitarParpadeo: true);
      sonidos.tocarTrozo(nivel, i);
    }

    e.reiniciar();

    for (var i = 0; i < n; i++) {
      final paso = nivel.pasos[i];
      final tipo = paso[0];
      final d = paso.substring(2);
      // L = ¿guía el adulto en este paso? (en 'Q' guía el niño)
      final L = tipo == 'Q' ? false : guiaAdulto;
      final colorSigue = L ? ColorPista.nino : ColorPista.adulto;
      final quien = L ? Guia.adulto : Guia.nino;
      final dir = Borde.desdeLetra(d);

      // 1. La luz del que guía late hasta que elige.
      _at(i == 0 ? 1200 : 500, () => e.cambiar(parpadea: quien));

      if (tipo == 'S' || tipo == 'O' || tipo == 'Q') {
        // Iguales u opuestos: k es el borde al que tiene que ir quien sigue.
        final k = tipo == 'O' ? dir!.opuesto : dir!;
        _at(1400, () {
          e.cambiar(quitarParpadeo: true);
          ir(L, dir);
        });
        _at(850, () => e.pista(k, colorSigue));
        if (i % 3 == 2) {
          // Cada tres pasos el que sigue se equivoca primero (va al otro
          // lado) y después corrige. No hay sonido de error.
          _at(650, () => ir(!L, k.opuesto));
          _at(1100, () => ir(!L, k));
        } else {
          _at(900, () => ir(!L, k));
        }
        _at(800, () => acierto(i));
      } else if (tipo == 'H') {
        // Quietos: van al mismo borde y lo sostienen.
        _at(1400, () {
          e.cambiar(quitarParpadeo: true);
          ir(L, dir);
        });
        _at(850, () => e.pista(dir!, colorSigue));
        _at(900, () => ir(!L, dir));
        _at(750, () => e.cambiar(pistas: const {}, sostener: dir));
        if (i % 2 == 1) {
          // En los pasos impares el que sigue se va antes de tiempo: se corta
          // y lo vuelven a intentar.
          _at(650, () {
            e.cambiar(quitarSostener: true);
            ir(!L, null);
          });
          _at(700, () => e.pista(dir!, colorSigue));
          _at(900, () => ir(!L, dir));
          _at(750, () => e.cambiar(pistas: const {}, sostener: dir));
        }
        _at(1600, () => acierto(i));
      } else if (tipo == 'G') {
        // Giro: el guía empieza arriba y da media vuelta; el otro se suma y
        // giran juntos una vuelta más, en tramos de 45° cada 230 ms.
        final sg = d == '-' ? -1 : 1;
        void pos(bool adulto, double grados) => adulto
            ? e.cambiar(adulto: EstadoJuegoEco.enCirculo(grados, true))
            : e.cambiar(nino: EstadoJuegoEco.enCirculo(grados, false));
        _at(1400, () {
          e.cambiar(quitarParpadeo: true);
          pos(L, -90);
        });
        _at(800, () => e.cambiar(giro: true));
        for (var q = 1; q <= 4; q++) {
          _at(230, () => pos(L, -90.0 + sg * 45 * q));
        }
        _at(230, () => e.cambiar(
              adulto: EstadoJuegoEco.enCirculo(-90.0 + sg * 225, true),
              nino: EstadoJuegoEco.enCirculo(-90.0 + sg * 225, false),
            ));
        for (var q = 6; q <= 13; q++) {
          _at(230, () => e.cambiar(
                adulto: EstadoJuegoEco.enCirculo(-90.0 + sg * 45 * q, true),
                nino: EstadoJuegoEco.enCirculo(-90.0 + sg * 45 * q, false),
              ));
        }
        _at(300, () => acierto(i));
      } else {
        // 'E' · eco por turnos: el guía va y vuelve; después el otro repite.
        _at(1400, () {
          e.cambiar(quitarParpadeo: true);
          ir(L, dir);
        });
        _at(1150, () => ir(L, null));
        _at(500, () => e.pista(dir!, colorSigue));
        if (i % 2 == 1) {
          _at(650, () => ir(!L, dir!.opuesto));
          _at(1100, () => ir(!L, dir));
        } else {
          _at(900, () => ir(!L, dir));
        }
        _at(800, () => acierto(i));
      }

      // Las luces vuelven al centro y, si queda otro trozo, reaparecen.
      _at(600, () => e.cambiar(
            giro: false,
            adulto: EstadoJuegoEco.reposoAdulto,
            nino: EstadoJuegoEco.reposoNino,
          ));
      _at(1500, () => e.cambiar(acierto: false, lucesVisibles: i < n - 1));
    }

    // Final: suena la melodía completa y la luz verde destella una vez por
    // trozo; después pasa a «el recuerdo».
    _at(900, () {
      e.cambiar(acierto: true);
      sonidos.tocarMelodia(nivel);
    });
    _at(1600, () => e.cambiar(acierto: false));
    for (var j = 1; j < n; j++) {
      _at(400, () => e.cambiar(acierto: true));
      _at(1600, () => e.cambiar(acierto: false));
    }
    _at(700, alTerminar);
  }
}
