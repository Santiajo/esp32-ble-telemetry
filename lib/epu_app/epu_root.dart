import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../balancin/platform/stick_hub.dart';
import '../balancin_v2/screens/bench_screen.dart';
import '../epu/app.dart';
import '../epu/estado/estado_eco.dart';
import '../epu/juego/fuente_sticks.dart';
import '../epu/navegacion/rutas.dart';
import '../epu/pantallas/perdida.dart' show CausaPerdida;
import '../epu/tema/colores.dart';
import 'fuente_sticks_ble.dart';
import 'juego_eco_real.dart';

/// Raíz de la app Epu: crea la conexión con los sticks una sola vez, la entrega a
/// las pantallas de Joaquín por [EpuSticks.fuente] y abre el flujo Eco.
///
/// * La primera vez abre en «Inicio» (preparación); cuando los dos sticks quedan
///   conectados se recuerda, y las siguientes veces abre en el Home.
/// * Mantener pulsado el logo del Home abre el banco de pruebas, con la misma
///   conexión (no hay dos `StickHub` peleando por los sticks).
class EpuRoot extends StatefulWidget {
  const EpuRoot({super.key});

  /// Clave de «ya hicieron la preparación».
  static const String preparacionKey = 'epu_preparacion_hecha';

  @override
  State<EpuRoot> createState() => _EpuRootState();
}

class _EpuRootState extends State<EpuRoot> {
  final StickHub _hub = StickHub(bluetoothEncendido: FuenteSticksBle.bluetoothEncendido);
  late final FuenteSticksBle _fuente = FuenteSticksBle(
    _hub,
    unStick: const bool.fromEnvironment('EPU_UN_STICK'),
    alConectarLosDos: () => unawaited(_marcarPreparacion()),
  );

  /// Sin sticks: las pantallas usan los tiempos simulados de Joaquín
  /// (`--dart-define=EPU_SIMULADO=true`). No toca el Bluetooth.
  static const bool simulado = bool.fromEnvironment('EPU_SIMULADO');

  /// «Tu archivo» lleno de ejemplo (`EstadoEco.demoLleno`) para revisar vistas.
  /// No se guarda nada (`--dart-define=EPU_DEMO=true`).
  static const bool demo = bool.fromEnvironment('EPU_DEMO');

  /// Clave del archivo guardado: niveles completados, recuerdos y sesiones.
  /// (En modo simulado se guarda aparte, para no mezclar partidas de mentira).
  static const String archivoKey = simulado ? 'epu_archivo_simulado' : 'epu_archivo';

  /// Clave antigua (hasta dev.12): de ahí solo se rescatan los niveles completados.
  static const String progresoAntiguoKey = 'epu_progreso';

  EstadoEco? _estado;
  bool? _preparado;
  StreamSubscription<LecturaStick>? _registro;

  @override
  void initState() {
    super.initState();
    EpuSticks.alMantenerLogo = _abrirBanco;
    if (!simulado) {
      EpuSticks.fuente = _fuente;
      EpuSticks.crearJuego = (nivel, estado, alTerminar) =>
          JuegoEcoReal.para(_fuente, nivel, estado, alTerminar, alPerderStick: _mostrarPerdida);
    }
    if (FuenteSticksBle.registrar) _registro = _fuente.lecturas.listen((_) {});
    unawaited(_iniciar());
  }

  Future<void> _iniciar() async {
    bool hecho = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      hecho = prefs.getBool(EpuRoot.preparacionKey) ?? false;
      final texto = prefs.getString(archivoKey) ?? (simulado ? null : prefs.getString(progresoAntiguoKey));
      if (texto != null) _estado = EstadoEco.desdeArchivo((jsonDecode(texto) as Map).cast<String, Object?>());
    } catch (_) {}
    if (demo) _estado = EstadoEco.demoLleno();
    _estado ??= EstadoEco(nivel: 1);
    _estado!.addListener(_alCambiarEstado);
    // Sticks ya vinculados: reconectar de fondo sin pedir permisos todavía.
    try {
      if (!simulado && (!Platform.isAndroid || await Permission.bluetoothConnect.isGranted)) {
        await _hub.reconnectSaved();
      }
    } catch (_) {}
    if (mounted) setState(() => _preparado = hecho);
  }

  Future<void> _marcarPreparacion() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(EpuRoot.preparacionKey, true);
    } catch (_) {}
  }

  /// Cualquier cambio del estado (nivel completado, sesión registrada, recuerdo
  /// guardado) se guarda en el teléfono. Es poco y cambia pocas veces.
  void _alCambiarEstado() {
    final e = _estado;
    if (e == null || demo) return;
    final texto = jsonEncode(e.archivoJson());
    if (texto == _ultimoGuardado) return;
    _ultimoGuardado = texto;
    unawaited(_guardar(texto));
  }

  String? _ultimoGuardado;

  Future<void> _guardar(String texto) async {
    try {
      await (await SharedPreferences.getInstance()).setString(archivoKey, texto);
    } catch (_) {}
  }

  /// Un stick dejó de mandar datos en pleno juego: «Se perdió un stick» de Joaquín.
  /// Al reconectarlo, esa pantalla vuelve sola a «Antes del nivel».
  void _mostrarPerdida(Stick stick) {
    final ctx = EpuNavegacion.registro.navigator?.context;
    if (ctx == null || !ctx.mounted) return;
    unawaited(EpuNavegacion.mostrarPerdida(ctx, stick: stick, causa: CausaPerdida.fueraDeAlcance));
  }

  void _abrirBanco(BuildContext context) {
    unawaited(Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => BenchScreen(hub: _hub)),
    ));
  }

  @override
  void dispose() {
    unawaited(_registro?.cancel());
    EpuSticks.alMantenerLogo = null;
    EpuSticks.crearJuego = null;
    _estado?.removeListener(_alCambiarEstado);
    _estado?.dispose();
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _preparado;
    if (p == null) return const ColoredBox(color: EpuColores.fondo);
    return EpuEcoApp(estado: _estado, inicio: p ? Pantalla.home : Pantalla.inicio);
  }
}
