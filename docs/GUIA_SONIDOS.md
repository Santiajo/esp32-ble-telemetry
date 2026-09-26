# Balancín · Guía de sonidos: qué gesto produce qué

> Cómo se produce cada sonido del instrumento, con los valores **reales** del código actual
> (`lib/balancin/core/constants.dart` y `ImuTuning` en `imu_gesture_reader.dart`).
> Si cambias un umbral en el panel "Ajuste IMU", los números de esta guía cambian en proporción.
> Versión 1 · 26-09-2026 · rama `balancin`, fase 5.

---

## 1. La regla de oro

**A abre el campo, B lo hace sonar.**

- **Stick A** (grande, adulto) nunca dispara notas. Decide **cuántas** alturas están disponibles, en **qué zona** de la escala y con **qué timbre**.
- **Stick B** (pequeño, niño) dispara notas, pero **solo dentro del campo** de A. Solo, B no suena nunca.

Mientras el stick A no exista, A se reemplaza en el tablero con el **dedo** en su panel o con **"Automático"** (su velocidad se ajusta de 1 a 7 con el slider).

La escala tiene **25 alturas pentatónicas** (Do, Re, Mi, Sol, La) en 5 octavas, desde C3 (índice 0) hasta A7 (índice 24). Ninguna combinación de gestos puede sonar fuera de ella.

---

## 2. Qué controla cada gesto

### 2.1 Stick A → el campo

| Gesto de A | Qué cambia | Stick real (valores actuales) | Dedo en el panel |
|---|---|---|---|
| **Amplitud** (cuánto recorre en 0,8 s) | **Ancho del campo** = 1 + 13·amp alturas (de 1 a 14) | amp = excursión angular / 90°. ±5° → ~2 alturas · ±20° → ~7 · ±45° o más → 14 | Recorrido relativo al panel: un trazo corto → pocas alturas; cruzar medio panel → campo máximo |
| **Velocidad** | **Registro** (qué zona de la escala) y, con él, el **timbre** | vel = ω / 400 °/s. El centro migra lento (~1 s de inercia) | vel = px/s ÷ 900 |
| Quietud | El campo se **estrecha** 1,6 alturas/s hasta cerrarse | — | — |

**Timbre según la velocidad de A** (el registro elige la familia):

| Velocidad sostenida de A | Registro | Familia | Carácter |
|---|---|---|---|
| Stick < ~127 °/s · dedo < ~285 px/s | grave | **marimba** | cálido, corto (0,8 s) |
| Stick ~127–293 °/s · dedo ~285–660 px/s | medio | **mixta** | intermedio (1,1 s) |
| Stick > ~293 °/s · dedo > ~660 px/s | agudo | **glockenspiel** | cristalino, largo (1,6 s) |
| (coincidencia de sacudidas, §4) | — | **oculto** (campana) | brillante y largo (2,2 s) |

### 2.2 Stick B → las notas

| Gesto de B | Qué cambia | Stick real (valores actuales) | Dedo |
|---|---|---|---|
| **Recorrido** | **Densidad**: una nota por unidad de recorrido | 1 nota cada **25°** de giro → 100 °/s ≈ 4 notas/s · 250 °/s ≈ 10/s · 400 °/s ≈ 16/s | 1 nota cada **42 px** |
| **Amplitud** | **Intensidad** de cada nota: ganancia = (0,18 + 0,82·amp)·0,3 | Gesto chico (±5°) = suave · gesto amplio (±45°) = fuerte (unas 4 veces más) | Trazo corto = suave · largo = fuerte |
| **Dirección** | **Recorrido melódico** dentro del campo (ver tabla) | `dx` = sentido del eje dominante del giro; `dy` = sentido del segundo eje | `dx` = izquierda/derecha; `dy` = arriba/abajo |
| Quietud ≥ 1,5 s | Entra en **Latencia**: resonancia del campo (§3) | — | — |

**Dirección → paso melódico** (`paso = dx − dy`; si da 0, sube 1). El campo es circular: al pasar el tope, la melodía vuelve al principio (arpegio cíclico).

| `dx` (eje principal) | `dy` (eje secundario) | Paso | Qué se oye |
|---|---|---|---|
| +1 | −1 | **+2** | sube saltando de a 2 |
| +1 | +1 | +1 | sube por grados |
| −1 | +1 | **−2** | baja saltando de a 2 |
| −1 | −1 | +1 | sube por grados |

`dy` **conserva su último sentido** hasta que el eje secundario vuelve a moverse con claridad (> 15 °/s). En la práctica:
- Un **vaivén en un solo eje** (ida y vuelta) usa el último `dy`: en un sentido sube por grados y en el otro baja de a 2 (o sube en ambos, según ese `dy`). El resultado es una ondulación que recorre el campo de forma cíclica.
- Un **vaivén en diagonal** (inclinando la muñeca) mantiene `dx` y `dy` opuestos y produce **saltos de 2** en ambos sentidos.
- Con el **dedo** (en pantalla, `dy = +1` es hacia **abajo**): la diagonal **arriba-derecha** sube de a 2; la diagonal **abajo-izquierda** baja de a 2; derecha-abajo y arriba-izquierda suben por grados.

---

## 3. Sonidos del sistema (no dependen de la melodía)

| Sonido | Cuándo aparece | Cómo provocarlo |
|---|---|---|
| **Resonancia de apertura** (acorde grave Do–Sol–Do) | Solo A se mueve estando en Reposo (estado "Espera"). Una vez por apertura | B quieto; mover A. Se repite si A se detiene (vuelve a Reposo) y arranca de nuevo |
| **Silencio absoluto** | Solo B se mueve | A quieto; mover B todo lo que quieras |
| **Resonancia del campo** (arpegio del campo abierto, una nota cada 70 ms, decae 2,4 s) | En juego activo, **B se detiene ≥ 1,5 s** y A sigue | Jugar ambos → dejar B quieto. El arpegio usa las alturas y el timbre que A tenga en ese momento |
| **Campo que se apaga** | En juego activo, **A se detiene ≥ 1,5 s** y B sigue | Jugar ambos → dejar A quieto. B sigue sonando, pero con cada vez menos alturas (el campo se cierra a 1,6 alturas/s), hasta el silencio |
| **Reanudación sin corte** | Durante una latencia, el que se detuvo retoma | Volver a mover el stick quieto antes de que se agote el campo |
| **Resonancia final** (acorde grave Do–Mi–Sol, decae 5 s) | "Terminar sesión", o una latencia de más de 20 s | Botón "Terminar", o dejar a uno de los dos quieto 20 s |

---

## 4. Timbre oculto (campana)

- **Condición:** en juego activo, **A y B sacuden a la vez**.
- **Sacudida con el stick:** ≥ 4 cambios de sentido del eje dominante en 0,6 s, cada uno con |ω| > 80 °/s. Equivale a agitar rápido, a unas 3–4 vueltas por segundo o más.
- **Sacudida con el dedo:** ≥ 4 cambios de dirección horizontal en 0,6 s.
- **Efecto:** durante **6 s** todas las notas de B suenan con el timbre **oculto** (campana). La luz y la banda se vuelven amarillas y el tablero muestra el badge "Timbre oculto".
- No se puede volver a abrir hasta que terminan esos 6 s.
- La especificación exige que no haya pistas de su existencia: en la experiencia final (fase 8) no se mostrará el badge.

---

## 5. Recetas: combinaciones para reproducir cada textura

Los números son orientativos, con los valores por defecto. "A automático v=N" significa Adulto = "Automático" con el slider en N.

| # | Para escuchar… | A hace | B hace | Régimen |
|---|---|---|---|---|
| 1 | **Pulso casi fijo** (1–2 notas repetidas) | Movimiento mínimo pero sin detenerse (recorrido total ≤ 6°, apenas sobre el umbral de movimiento) → campo de 1–2 alturas. Con el dedo es más fácil: trazos muy cortos | Vaivén regular | 4 · mínima |
| 2 | **Calma grave** (marimba, pocas notas, colas largas) | Gesto chico y lento (recorrido total < 17°, o sea ±8°; < 120 °/s) → ≤ 3 alturas, registro grave | Vaivén lento y chico (< 50 °/s) → ≤ 2 notas/s, suaves | 4 · mínima |
| 3 | **Arpegio claro de marimba** | Amplitud media (±20°), lento → ~7 alturas graves. A automático v=1 | Vaivén regular (~150 °/s) | 1 · estable |
| 4 | **Textura densa y rica** | Gesto amplio (±25° o más → 8 alturas; ±45° → 14) | Rápido y sostenido (≥ 125 °/s → ≥ 5 notas/s) | 3 · densa |
| 5 | **Brillo de glockenspiel** | Rápido (> 300 °/s). A automático v=6–7 | Cualquier vaivén | 1 o 3 |
| 6 | **Mismo patrón, otras notas** (phase shifting) | Cambiar la velocidad gradualmente (lento → rápido o al revés) | Mantener exactamente el mismo vaivén | 2 · desplazamiento |
| 7 | **Notas fuertes vs. suaves** | Cualquiera | Gesto amplio = fuerte · gesto chico = suave, a la misma velocidad | — |
| 8 | **Saltos melódicos** | Campo ancho (≥ 8 alturas) | Vaivén en diagonal (muñeca inclinada) | — |
| 9 | **Ondulación / escala** | Campo ancho | Vaivén en un solo eje, o el dedo en línea horizontal | — |
| 10 | **Campana (timbre oculto)** | Sacudir rápido | Sacudir rápido **al mismo tiempo** | 5 · coincidencias |
| 11 | **Arpegio de despedida** (resonancia del campo) | Seguir moviéndose | Detenerse ≥ 1,5 s | — |
| 12 | **Campo que se apaga** | Detenerse | Seguir moviéndose: las notas se concentran y se apagan | — |
| 13 | **Llamado del adulto** (resonancia de apertura) | Moverse solo | Quieto | — |
| 14 | **Silencio que invita** | Quieto | Moverse solo: no suena nada | — |

---

## 6. Regímenes (cómo los clasifica la telemetría)

Cada instante de juego activo se clasifica en uno solo de los regímenes, en este orden de prioridad:

1. **Coincidencias**: timbre oculto activo.
2. **Desplazamiento**: el registro migra a más de 1,2 alturas/s (A cambia de velocidad).
3. **Densa**: campo ≥ 8 alturas (A con recorrido ≥ ~45°, o sea ±22°) **y** ≥ 5 notas/s (B a ≥ ~125 °/s).
4. **Mínima**: campo ≤ 3 alturas (A con recorrido < ~17°) **y** ≤ 2 notas/s (B a ≤ ~50 °/s).
5. **Estable**: todo lo demás.

Ningún régimen es mejor que otro: la variedad visitada es el indicador de exploración.

---

## 7. Parámetros ajustables (panel "Ajuste IMU")

| Parámetro | Por defecto | Si lo subes… |
|---|---|---|
| `onDps` | 25 °/s | cuesta más que el stick "cuente" como en movimiento |
| `offDps` | 12 °/s | se considera quieto antes |
| `omegaMaxDps` | 400 °/s | hace falta más velocidad para llegar al registro agudo (A) y para intensidades altas |
| `ampFullDeg` | 90° | hace falta más recorrido para abrir el campo (A) y para notas fuertes (B) |
| `articulationDeg` | 25° | menos notas por segundo (B) |
| `shakeMinDps` | 80 °/s | la sacudida para el timbre oculto debe ser más enérgica |
| `stillStdDps` | 3 °/s | la calibración acepta un stick menos quieto |

Cuando encuentres valores que se sientan bien, pásale a Claude el texto de "Copiar valores" para fijarlos en el código.
