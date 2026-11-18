import 'dart:async';
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
import '../epu/tema/colores.dart';
import 'fuente_sticks_ble.dart';
import 'juego_eco_real.dart';
import 'progreso_epu.dart';

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

class _EpuRootState extends State<EpuRoot> with WidgetsBindingObserver {
  final StickHub _hub = StickHub();
  late final FuenteSticksBle _fuente = FuenteSticksBle(
    _hub,
    unStick: const bool.fromEnvironment('EPU_UN_STICK'),
    alConectarLosDos: () => unawaited(_marcarPreparacion()),
  );
  /// Clave del progreso guardado (niveles completados y sesiones).
  static const String progresoKey = 'epu_progreso';

  EstadoEco? _estado;
  ProgresoEpu _progreso = ProgresoEpu();
  final List<SesionPasada> _sesionesHome = [];
  bool? _preparado;
  StreamSubscription<LecturaStick>? _registro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    EpuSticks.fuente = _fuente;
    EpuSticks.alMantenerLogo = _abrirBanco;
    EpuSticks.crearJuego = (nivel, estado, alTerminar) => JuegoEcoReal.para(_fuente, nivel, estado, alTerminar);
    if (FuenteSticksBle.registrar) _registro = _fuente.lecturas.listen((_) {});
    unawaited(_iniciar());
  }

  Future<void> _iniciar() async {
    bool hecho = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      hecho = prefs.getBool(EpuRoot.preparacionKey) ?? false;
      _progreso = ProgresoEpu.fromJson(prefs.getString(progresoKey));
    } catch (_) {}
    _sesionesHome
      ..clear()
      ..addAll(_progreso.sesionesParaHome(DateTime.now()));
    _estado = EstadoEco(nivel: 1, completados: {..._progreso.completados}, sesiones: _sesionesHome)
      ..addListener(_alCambiarEstado);
    // Sticks ya vinculados: reconectar de fondo sin pedir permisos todavía.
    try {
      if (!Platform.isAndroid || await Permission.bluetoothConnect.isGranted) await _hub.reconnectSaved();
    } catch (_) {}
    if (mounted) setState(() => _preparado = hecho);
  }

  Future<void> _marcarPreparacion() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(EpuRoot.preparacionKey, true);
    } catch (_) {}
  }

  /// Un nivel recién completado (la pantalla de juego llama a `marcarCompletado`):
  /// se suma a la sesión, se actualiza el Home y se guarda.
  void _alCambiarEstado() {
    final e = _estado;
    if (e == null) return;
    // Cada vez que termina un nivel se registra, aunque ya estuviera completado antes.
    final terminado = e.ultimoTerminado;
    if (terminado == null || terminado == _ultimoRegistrado) return;
    _ultimoRegistrado = terminado;
    final ahora = DateTime.now();
    _progreso.terminarNivel(terminado.nivel, ahora);
    _sesionesHome
      ..clear()
      ..addAll(_progreso.sesionesParaHome(ahora));
    unawaited(_guardar());
  }

  ({int nivel, int vez})? _ultimoRegistrado;

  Future<void> _guardar() async {
    try {
      await (await SharedPreferences.getInstance()).setString(progresoKey, _progreso.toJson());
    } catch (_) {}
  }

  void _abrirBanco(BuildContext context) {
    unawaited(Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => BenchScreen(hub: _hub)),
    ));
  }

  /// Cerrar la app o mandarla al fondo termina la sesión de juego.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) _progreso.cerrarSesion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
