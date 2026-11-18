import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/params.dart';
import 'v2_ui.dart';

/// Cómo se edita un parámetro en el panel.
enum TuneKind { slider, toggle, choice }

/// Un control del panel de ajuste con su ayuda («?»): qué es, para qué sirve y
/// cómo moverlo, en palabras para quien ajusta sin saber de sonido ni sensores.
class TuneSpec {
  const TuneSpec(
    this.key,
    this.label, {
    this.kind = TuneKind.slider,
    this.min = 0,
    this.max = 1,
    this.step = 1,
    this.unit = '',
    this.dec = 0,
    this.choices = const [],
    required this.what,
    required this.why,
    required this.how,
  });

  final String key, label;
  final TuneKind kind;
  final double min, max, step;
  final String unit;
  final int dec;

  /// Nombres de cada valor entero (solo [TuneKind.choice]).
  final List<String> choices;
  final String what, why, how;

  /// Valor como se lee en pantalla («1,25 ×», «Sí», «Zonas y trazo»).
  String format(double v) => switch (kind) {
        TuneKind.toggle => v > 0 ? 'Sí' : 'No',
        TuneKind.choice => choices[v.round().clamp(0, choices.length - 1)],
        TuneKind.slider => '${v.toStringAsFixed(dec).replaceAll('.', ',')}$unit',
      };
}

class TuneSection {
  const TuneSection(this.title, this.intro, this.specs);
  final String title, intro;
  final List<TuneSpec> specs;
}

/// Todos los controles, por tema. Los textos los lee el diseñador (Joaquín) para
/// ajustar en la prueba; la guía larga está en `docs/GUIA_AJUSTE_V2.md`.
const List<TuneSection> tuneSections = [
  TuneSection('Cómo se mide la sincronía', 'Qué cuenta como «van juntos». Es lo que más cambia la dificultad.', [
    TuneSpec('matchMode', 'Medir la sincronía por',
        kind: TuneKind.choice,
        max: 3,
        choices: ['Punto', 'Zonas', 'Trazo', 'Zonas y trazo'],
        what: 'La regla que decide si los dos van juntos. «Punto»: el niño tiene que estar casi en el mismo lugar que '
            'le corresponde según el adulto (un círculo chico). «Zonas»: basta con estar en la misma franja del plano '
            '(arriba, medio o abajo). «Trazo»: basta con moverse hacia el mismo lado al mismo tiempo, aunque uno haga '
            'el gesto más grande. «Zonas y trazo»: hacen falta las dos cosas.',
        why: 'Jugando en el eje nadie ve la pantalla. Acertar un punto a ciegas es casi imposible; una franja y un '
            'movimiento parecido sí se pueden sentir con el cuerpo. «Zonas y trazo» fue lo que mejor funcionó en las pruebas.',
        how: 'Si a ciegas casi nunca coinciden: «Trazo». Si se logra demasiado fácil: «Zonas y trazo» o «Punto». '
            '«Mismo pulso» y «Sígueme» no cambian con esto.'),
    TuneSpec('zoneCount', 'Zonas: franjas por eje',
        min: 2,
        max: 6,
        what: 'En cuántas franjas se divide el plano en cada eje cuando se mide por zonas.',
        why: 'Menos franjas = franjas más anchas = más fácil coincidir.',
        how: '3 = arriba, medio y abajo. Si cuesta, baja a 2 (arriba y abajo). Si es muy fácil, sube a 4.'),
    TuneSpec('traceWinMs', 'Trazo: ventana',
        min: 600,
        max: 3000,
        step: 100,
        unit: ' ms',
        what: 'Cuánto tiempo hacia atrás se compara el movimiento de los dos cuando se mide por trazo.',
        why: 'Una ventana larga pide un gesto parecido sostenido; una corta reacciona rápido pero perdona menos los cambios.',
        how: 'Si tarda en darse cuenta de que ya van juntos, bájala (1000 ms). Si cuenta movimientos sueltos, súbela (2000 ms).'),
    TuneSpec('traceMin', 'Trazo: parecido mínimo',
        min: 0.2,
        max: 0.95,
        step: 0.05,
        dec: 2,
        what: 'Qué tan parecidos tienen que ser los dos movimientos para contar (1 = idénticos, 0 = sin relación).',
        why: 'Es la exigencia del trazo. En el banco, la línea «Por detrás» muestra el parecido en vivo.',
        how: 'Si cuenta aunque no vayan tan parejos, súbelo (0,75). Si no cuenta aunque se mueven juntos, bájalo (0,45).'),
    TuneSpec('tolScale', 'Tolerancia (× nivel)',
        min: 0.5,
        max: 1.5,
        step: 0.05,
        unit: ' ×',
        dec: 2,
        what: 'Multiplica cuánta distancia se perdona en cada nivel.',
        why: 'Afecta a todas las formas de medir: el tamaño del círculo, el margen de las zonas y del trazo.',
        how: 'Más alta = más fácil. Si frustra, súbela a 1,15–1,3. Si se logra sin esfuerzo, bájala a 0,85.'),
    TuneSpec('hyst', 'Histéresis de la sincronía',
        min: 1,
        max: 2,
        step: 0.05,
        unit: ' ×',
        dec: 2,
        what: 'Una vez que entran en sincronía, cuánto más pueden alejarse antes de salir.',
        why: 'Evita que el sonido parpadee entre afinado y ondulado cuando están justo en el límite.',
        how: 'Si el sonido parpadea en el borde, súbela a 1,4.'),
    TuneSpec('sideOnly', 'Espejo e Iguales: solo el lado',
        kind: TuneKind.toggle,
        what: 'En «Espejo» e «Iguales» mide solo hacia qué lado se inclina cada uno; la altura queda libre.',
        why: 'Coordinar altura y lado a la vez sin ver es muy difícil.',
        how: 'Enciéndelo si en esos niveles no logran las dos cosas a la vez.'),
    TuneSpec('edgeNoSync', 'Pegados al borde no cuenta',
        kind: TuneKind.toggle,
        what: 'Si los dos sticks están inclinados al máximo (pegados al borde del plano), no cuenta como sincronía.',
        why: 'Cierra un atajo: con la pantalla a la vista, dejar los dos sticks en una esquina «gana» sin moverse juntos.',
        how: 'Enciéndelo si ves que ganan estacionándose en las esquinas. Con trazo casi no hace falta.'),
    TuneSpec('velWeight', 'Peso de la velocidad',
        max: 0.3,
        step: 0.01,
        unit: ' s',
        dec: 2,
        what: 'Cuánto importa que los dos se muevan a una velocidad parecida (en las mediciones por punto y zonas).',
        why: 'Evita que cuente cuando uno sube y el otro baja y justo se cruzan.',
        how: 'Si cuenta al cruzarse, súbelo a 0,1. Si no cuenta porque uno es más brusco, bájalo a 0,03 (0 = no importa).'),
    TuneSpec('syncLagMs', 'Tolerancia de retraso',
        max: 300,
        step: 10,
        unit: ' ms',
        what: 'Cuánto atraso de uno respecto del otro se perdona.',
        why: 'Siempre hay un pequeño desfase (de la persona o del Bluetooth). A alta velocidad separa mucho los puntos.',
        how: 'Si a alta velocidad pierden la sincronía, súbela a 200–250. Si cuenta aunque uno va claramente atrasado, bájala a 80.'),
  ]),
  TuneSection('Lograr el nivel', 'Cuánto dura y cuánto cuesta avanzar o perder lo ganado.', [
    TuneSpec('secScale', 'Segundos por nivel',
        min: 0.25,
        max: 2,
        step: 0.05,
        unit: ' ×',
        dec: 2,
        what: 'Multiplica el tiempo en sincronía que pide cada nivel (1 = 8 segundos).',
        why: 'Es la duración del desafío.',
        how: 'Bájalo para niveles más cortos, súbelo para más largos.'),
    TuneSpec('slipGrace', 'Margen al salir de la zona',
        max: 1.5,
        step: 0.05,
        unit: ' s',
        dec: 2,
        what: 'Cuánto pueden estar fuera de la sincronía, moviéndose, antes de empezar a perder avance.',
        why: 'Perdona los tropiezos cortos.',
        how: 'Si se pierde el avance por nada, súbelo a 0,7. Si se logra pasando de rebote, bájalo a 0,2.'),
    TuneSpec('slipDrain', 'Pérdida al salir',
        max: 3,
        step: 0.1,
        unit: ' ×',
        dec: 1,
        what: 'Qué tan rápido baja el avance cuando están fuera de la sincronía (1 = baja tan rápido como sube).',
        why: 'Hace que mantenerse juntos importe.',
        how: 'Si frustra, bájala a 0,4–0,5. Si es demasiado fácil, súbela a 1,5–2. Con 0 no se pierde nada.'),
    TuneSpec('idleAfter', 'Quietud antes de perder avance',
        min: 1,
        max: 8,
        step: 0.5,
        unit: ' s',
        dec: 1,
        what: 'Cuántos segundos pueden estar quietos (uno o los dos) antes de que el avance empiece a bajar.',
        why: 'Una pausa corta no debería castigar.',
        how: 'Si una pausa de 2–3 s ya les baja el avance, súbelo a 5.'),
    TuneSpec('decay', 'Pérdida por quietud',
        max: 2,
        step: 0.1,
        unit: ' ×',
        dec: 1,
        what: 'Qué tan rápido baja el avance mientras están quietos, pasado el tiempo de arriba.',
        why: 'Invita a retomar el juego.',
        how: 'Bájala si las pausas les quitan demasiado.'),
    TuneSpec('autoNext', 'Seguir al siguiente nivel',
        kind: TuneKind.toggle,
        what: 'Al lograr un nivel, pasar solo al siguiente (como el prototipo) o ir a la pantalla final.',
        why: 'Seguido da una partida larga; apagado deja ver el recuerdo de cada nivel.',
        how: 'Apágalo si quieres ver el final después de cada nivel.'),
    TuneSpec('levelLimit', 'Tiempo por nivel',
        max: 120,
        step: 5,
        unit: ' s',
        what: 'Segundos de juego para lograr un nivel. Al pasar, va al final con el % logrado (solo en el juego, no en el banco). 0 = sin límite.',
        why: 'Una díada que no lo logra no queda atrapada en el nivel.',
        how: 'Súbelo si se cierra cuando están cerca de lograrlo.'),
    TuneSpec('endAfter', 'Cerrar tras quietud',
        min: 10,
        max: 90,
        step: 5,
        unit: ' s',
        what: 'Cuántos segundos sin juego cierran la sesión sola y van al final (solo en el juego, no en el banco).',
        why: 'Termina cuando la díada dejó de jugar.',
        how: 'Súbelo si se cierra mientras conversan o se acomodan.'),
    TuneSpec('followLag', 'Sígueme: retraso permitido',
        min: 0.2,
        max: 2,
        step: 0.1,
        unit: ' s',
        dec: 1,
        what: 'En «Sígueme», cuánto atraso se permite a quien copia.',
        why: 'Copiar siempre llega un poco después.',
        how: 'Súbelo si a quien copia le cuesta seguir.'),
    TuneSpec('rhythmWin', 'Ventana del ritmo',
        min: 1.5,
        max: 6,
        step: 0.5,
        unit: ' s',
        dec: 1,
        what: 'Cuántos segundos se miran para medir el ritmo de cada uno (vaivenes por segundo).',
        why: 'Se usa en «Mismo pulso» y en la luz.',
        how: 'Más larga = ritmo más estable pero más lento en reaccionar.'),
  ]),
  TuneSection('Sonido', 'Qué se oye y cómo ayuda a ubicarse sin mirar.', [
    TuneSpec('sharedScale', 'Niño en la escala del adulto',
        kind: TuneKind.toggle,
        what: 'El niño usa las mismas notas que el adulto, una octava más arriba.',
        why: 'A la misma altura suenan la misma nota: el niño puede oír dónde está el adulto.',
        how: 'Enciéndelo para jugar sin vista.'),
    TuneSpec('sideTimbre', 'El lado cambia el timbre',
        kind: TuneKind.toggle,
        what: 'Las notas del niño suenan a marimba a la izquierda y a campana a la derecha; la voz del adulto, más brillante a la derecha.',
        why: 'Sin esto, inclinarse hacia los lados no cambia el sonido.',
        how: 'Enciéndelo para «Espejo» e «Iguales» sin vista.'),
    TuneSpec('fifthRamp', 'Quinta gradual al acercarse',
        kind: TuneKind.toggle,
        what: 'La nota de premio (la quinta) aparece de a poco a medida que se acercan, en vez de encenderse de golpe.',
        why: 'Funciona como «frío o caliente».',
        how: 'Enciéndelo si no se dan cuenta de cuándo están cerca.'),
    TuneSpec('guideChime', 'Campanita al cambiar de guía',
        kind: TuneKind.toggle,
        what: 'Suena una campanita cuando cambia quién guía.',
        why: 'La voz viene apagada; sin aviso no saben que ahora guía el otro.',
        how: 'Enciéndela si juegan con la voz apagada.'),
    TuneSpec('maxDetune', 'Ondulación máxima',
        min: 1,
        max: 8,
        step: 0.1,
        unit: ' Hz',
        dec: 1,
        what: 'Qué tan fuerte ondula el sonido cuando están lejos de la sincronía.',
        why: 'La ondulación dice «todavía no».',
        how: 'Si es muy agresiva, bájala a 2,5. Si casi no se nota, súbela a 6.'),
    TuneSpec('phraseSteps', 'Frase nota a nota',
        kind: TuneKind.toggle,
        what: 'Suena una nota de la frase del nivel en cada cuarto del avance; si el avance baja, la nota «cae».',
        why: 'Deja oír cuánto falta.',
        how: 'Apágala si las notas distraen.'),
    TuneSpec('runMaxNotes', 'Notas de paso (máximo)',
        max: 10,
        what: 'Cuando el niño salta varias notas de golpe, cuántas notas intermedias se tocan rápido para llegar.',
        why: 'Hace que el movimiento suene como una escala y no como saltos.',
        how: 'Si suena como cascada, bájalo a 3. Si todavía se oyen saltos, súbelo a 8. Con 0, salta directo.'),
    TuneSpec('runMs', 'Duración de la escala de paso',
        min: 40,
        max: 300,
        step: 10,
        unit: ' ms',
        what: 'Cuánto dura esa escala de notas de paso.',
        why: 'Muy larga atrasa la nota de llegada; muy corta se atropella.',
        how: 'Si la nota de llegada se siente atrasada, bájala a 80. Si suena atropellada, súbela a 180.'),
    TuneSpec('runGain', 'Volumen de las notas de paso',
        min: 0.2,
        max: 1,
        step: 0.05,
        unit: ' ×',
        dec: 2,
        what: 'Volumen de las notas de paso respecto de la nota de llegada.',
        why: 'Que acompañen sin tapar.',
        how: 'Si no se distinguen, súbelo a 0,8. Si tapan la nota final, bájalo a 0,4.'),
  ]),
  TuneSection('Movimiento y rango', 'Cómo se convierte la inclinación del stick en movimiento del punto.', [
    TuneSpec('samePoint', 'Iguales: mismo punto',
        kind: TuneKind.toggle,
        what: 'En «Iguales», frente a frente, los dos apuntan al mismo punto físico: el lado y el adelante-atrás van opuestos para cada uno.',
        why: 'Así el nivel reconoce lo que dice su consigna.',
        how: 'Apagado vuelve a medir la misma posición para cada uno, como el prototipo.'),
    TuneSpec('zoneStrict', 'Zonas exactas',
        kind: TuneKind.toggle,
        what: 'Con zonas, estar fuera de la franja que toca cuenta como fuera, sin margen.',
        why: 'Así solo cuentan las divisiones y el trazo, y no la tolerancia del punto.',
        how: 'Apágalo para perdonar un poco el cruce de una franja a otra.'),
    TuneSpec('axisCheck', 'Revisar ejes al calibrar',
        kind: TuneKind.toggle,
        what: 'La calibración de usuarios no avanza si el gesto va por el eje equivocado del stick.',
        why: 'Evita que un stick girado en la mano quede calibrado al revés o de lado.',
        how: 'Apágalo solo si un stick está montado distinto y nadie logra pasar la calibración.'),
    TuneSpec('edgeFollow', 'Volver del borde sin espera',
        kind: TuneKind.toggle,
        what: 'Si el stick se pasa del rango, el límite se corre con él y el punto vuelve apenas el stick se devuelve.',
        why: 'Sin esto el punto queda pegado al borde hasta reentrar en el rango, y se siente como retraso.',
        how: 'Déjalo encendido. Apagado, el punto marca el rango fijo, como el prototipo.'),
    TuneSpec('alpha', 'Suavizado del punto',
        min: 0.05,
        max: 0.6,
        step: 0.01,
        dec: 2,
        what: 'Qué tan rápido sigue el punto a la mano.',
        why: 'Poco suavizado = rápido pero tembloroso; mucho = suave pero atrasado.',
        how: 'Si el punto tiembla, bájalo a 0,12. Si va atrasado, súbelo a 0,3.'),
    TuneSpec('onSpeed', 'Umbral de actividad',
        min: 0.5,
        max: 6,
        step: 0.1,
        unit: ' u/s',
        dec: 1,
        what: 'Qué tan rápido hay que moverse para contar como «activo».',
        why: 'Separa jugar de sostener el stick quieto con un poco de temblor.',
        how: 'Si dice «activo» con el stick casi quieto, súbelo a 3,5. Si no detecta un gesto lento, bájalo a 1,5.'),
    TuneSpec('rangeA', 'Rango sin calibrar · adulto',
        min: 10,
        max: 60,
        unit: '°',
        what: 'Cuánto hay que inclinar el stick del adulto para llegar al borde, si no se calibró.',
        why: 'Solo se usa sin calibrar; la calibración mide el rango de cada persona.',
        how: 'Si al adulto le cuesta llegar a los bordes, bájalo a 20.'),
    TuneSpec('rangeC', 'Rango sin calibrar · niño',
        min: 15,
        max: 80,
        unit: '°',
        what: 'Lo mismo para el stick del niño.',
        why: 'El prototipo pide al niño gestos más amplios.',
        how: 'Si el punto del niño se pega al borde enseguida, súbelo a 60.'),
    TuneSpec('minA', 'Rango mínimo · adulto',
        min: 5,
        max: 40,
        unit: '°',
        what: 'El rango más chico que puede dejar la calibración para el adulto.',
        why: 'Si el adulto calibra con gestos muy chicos, después vive pegado al borde.',
        how: 'Si el adulto llega al borde con un gesto muy chico (más de 15 % del tiempo en el borde), súbelo a 20–25.'),
    TuneSpec('minC', 'Rango mínimo · niño',
        min: 5,
        max: 50,
        unit: '°',
        what: 'El rango más chico que puede dejar la calibración para el niño.',
        why: 'Es una decisión de diseño: hoy el niño necesita gestos más amplios que el adulto.',
        how: 'Si el niño tiene que moverse mucho más que el adulto, bájalo a 15.'),
    TuneSpec('calMode', 'Calibración robusta',
        kind: TuneKind.toggle,
        what: 'Durante los 6 s de calibración, solo cuentan los momentos en que el stick se mueve, y el rango se mide por separado hacia los lados y hacia adelante.',
        why: 'Si un stick estaba apoyado al empezar, la calibración del prototipo deja el punto pegado a un borde.',
        how: 'Déjala encendida. Apágala solo para comparar con el prototipo.'),
  ]),
  TuneSection('Sensor del stick', 'Solo con sticks reales. Cambia cómo se calcula la inclinación.', [
    TuneSpec('kAccel', 'Corrección con la gravedad',
        min: 0.005,
        max: 0.1,
        step: 0.005,
        dec: 3,
        what: 'Cuánto se corrige la inclinación con la gravedad en cada lectura.',
        why: 'Mucho: el punto salta con las sacudidas. Poco: con el tiempo se desliza.',
        how: 'Si con el stick quieto el punto se desliza lento, súbelo a 0,04. Si salta al sacudir, bájalo a 0,01.'),
    TuneSpec('accelGate', 'Compuerta de sacudidas',
        min: 0.05,
        max: 0.5,
        step: 0.01,
        unit: ' g',
        dec: 2,
        what: 'Qué tan fuerte tiene que ser una sacudida para ignorar la gravedad mientras dura.',
        why: 'Durante una sacudida la gravedad medida miente.',
        how: 'Si el punto salta al sacudir sin inclinar, bájala a 0,1.'),
  ]),
];

/// Panel «Ajuste» del banco: secciones, valores en palabras, ayuda (?) por
/// control y botones de valores. Guarda con [save] cada cambio.
class TuningSheet extends StatefulWidget {
  const TuningSheet({super.key, required this.params, required this.save});

  final SyncParams params;
  final Future<void> Function(SyncParams) save;

  static Future<void> open(BuildContext context, SyncParams params, {required Future<void> Function(SyncParams) save}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: V2.paper,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Theme(data: V2.theme, child: TuningSheet(params: params, save: save)),
      );

  @override
  State<TuningSheet> createState() => _TuningSheetState();
}

class _TuningSheetState extends State<TuningSheet> {
  static final SyncParams _factory = SyncParams();

  SyncParams get p => widget.params;

  void _set(String k, double v, {bool save = true}) {
    setState(() => p[k] = v);
    if (save) unawaited(widget.save(p));
  }

  void _setAll(SyncParams o, String msg) {
    setState(() => p.setAll(o));
    unawaited(widget.save(p));
    _snack(msg);
  }

  void _snack(String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.4,
      maxChildSize: 0.97,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: V2.line, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const Text('Ajuste', style: V2.h2),
          const SizedBox(height: 4),
          const Text('Los cambios se guardan solos en el teléfono y valen también para el juego. Toca ? para saber qué hace cada control.',
              style: V2.sub),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _preset('Valores de fábrica', Icons.restart_alt, () => _setAll(SyncParams(), 'Volvió a los valores de fábrica.')),
            _preset('Sin vista', Icons.visibility_off_outlined,
                () => _setAll(SyncParams.blind(), 'Todas las ayudas para jugar sin ver, encendidas.')),
            _preset('Como el prototipo', Icons.history, () => _setAll(SyncParams.prototype(), 'Como el prototipo HTML.')),
            _preset('Copiar valores', Icons.copy_outlined, () async {
              await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(p.toJson())));
              _snack('Valores copiados: pégalos en un mensaje para guardarlos.');
            }),
          ]),
          for (final s in tuneSections) ..._section(s),
        ],
      ),
    );
  }

  Widget _preset(String label, IconData icon, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: V2.ink,
          side: const BorderSide(color: Color(0x402B2536), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
      );

  List<Widget> _section(TuneSection s) => [
        const SizedBox(height: 22),
        Text(s.title.toUpperCase(), style: V2.kicker.copyWith(letterSpacing: 0.6)),
        const SizedBox(height: 2),
        Text(s.intro, style: V2.small.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            for (var i = 0; i < s.specs.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: V2.line, indent: 14, endIndent: 14),
              _control(s.specs[i]),
            ],
          ]),
        ),
      ];

  bool _changed(TuneSpec t) => (p[t.key] - _factory[t.key]).abs() > 1e-9;

  Widget _control(TuneSpec t) {
    final v = p[t.key];
    final changed = _changed(t);
    final header = Row(children: [
      Expanded(
        child: Text(t.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: V2.ink, height: 1.2)),
      ),
      if (t.kind == TuneKind.toggle)
        Switch(
          value: v > 0,
          activeThumbColor: Colors.white,
          activeTrackColor: V2.olive,
          onChanged: (on) => _set(t.key, on ? 1 : 0),
        )
      else
        _valueChip(t.format(v), changed),
      IconButton(
        tooltip: 'Qué es «${t.label}»',
        icon: const Icon(Icons.help_outline, color: V2.mute),
        onPressed: () => _help(t),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (t.kind == TuneKind.slider) _slider(t, v),
        if (t.kind == TuneKind.choice)
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < t.choices.length; i++)
                ChoiceChip(
                  label: Text(t.choices[i]),
                  selected: v.round() == i,
                  showCheckmark: false,
                  selectedColor: V2.ink,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x402B2536)),
                  labelStyle: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: v.round() == i ? Colors.white : V2.ink),
                  onSelected: (_) => _set(t.key, i.toDouble()),
                ),
            ]),
          ),
        if (changed && t.kind != TuneKind.choice)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('De fábrica: ${t.format(_factory[t.key])}', style: V2.small.copyWith(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _valueChip(String text, bool changed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: changed ? V2.olive : V2.paper,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: changed ? Colors.white : V2.ink)),
      );

  Widget _slider(TuneSpec t, double v) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: V2.ink,
          inactiveTrackColor: V2.line,
          thumbColor: V2.ink,
          overlayColor: V2.ink.withValues(alpha: 0.08),
          trackHeight: 4,
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: Slider(
          value: v.clamp(t.min, t.max).toDouble(),
          min: t.min,
          max: t.max,
          divisions: ((t.max - t.min) / t.step).round(),
          onChanged: (x) => _set(t.key, x, save: false),
          onChangeEnd: (_) => unawaited(widget.save(p)),
        ),
      );

  Future<void> _help(TuneSpec t) => showDialog<void>(
        context: context,
        builder: (ctx) => Theme(
          data: V2.theme,
          child: AlertDialog(
            backgroundColor: V2.paper,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text(t.label, style: V2.h2),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _valueChip('Ahora: ${t.format(p[t.key])}', _changed(t)),
                  _valueChip('De fábrica: ${t.format(_factory[t.key])}', false),
                ]),
                _helpBlock('Qué es', t.what),
                _helpBlock('Para qué sirve', t.why),
                _helpBlock('Cómo ajustarlo', t.how),
              ]),
            ),
            actions: [
              if (_changed(t))
                TextButton(
                  onPressed: () {
                    _set(t.key, _factory[t.key]);
                    Navigator.of(ctx).pop();
                  },
                  style: TextButton.styleFrom(foregroundColor: V2.ink),
                  child: const Text('Volver al de fábrica'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(backgroundColor: V2.ink, foregroundColor: Colors.white),
                child: const Text('Entendido'),
              ),
            ],
          ),
        ),
      );

  Widget _helpBlock(String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: V2.ink)),
          const SizedBox(height: 3),
          Text(body, style: const TextStyle(fontSize: 14.5, color: V2.soft, fontWeight: FontWeight.w600, height: 1.35)),
        ]),
      );
}
