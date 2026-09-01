class_name PassiveState
extends RefCounted

## RELOJ Y ESFUERZO de las animaciones pasivas — respiración, temblor, y lo que venga.
##
## Existe para que todos los efectos pasivos lean de UN solo lugar. Agregar el pestañeo o el balanceo
## idle después no agrega estado: ya está el tiempo, ya está la fase, ya está el esfuerzo.
##
## ── POR QUÉ LA FASE SALE DEL SEED ─────────────────────────────────────────────────────────────────
## Sin un offset por personaje, **una calle entera de peatones respira al unísono** y se lee como un
## error de motor. Con la fase sembrada del `master_seed` cada uno va por su lado, gratis y estable
## entre máquinas (el mismo seed da la misma fase, aunque acá ni siquiera haga falta que coincida).
##
## ── POR QUÉ EL ESFUERZO SE DERIVA Y NO SE SINCRONIZA ──────────────────────────────────────────────
## `exertion` sale de la VELOCIDAD OBSERVADA, que ya viaja por la red. Entonces:
##
##   - el proxy de otro jugador lo calcula solo, sin un byte extra de protocolo
##   - **los NPC lo tienen gratis**, con el mismo código — un peatón que corrió media cuadra jadea
##   - se auto-corrige: si se desfasa por un paquete perdido, vuelve en cuanto el otro cambia de ritmo
##
## Un desfase del 15% es invisible en una curva tan lenta. Si algún día hiciera falta exacto, mandar
## la stamina del jugador local por la red es ADITIVO: reemplaza la entrada y esta fórmula no cambia.

## Segundos por ciclo respiratorio, en reposo y agitado.
const BREATH_PERIOD_REST := 4.6
const BREATH_PERIOD_HARD := 1.5

## Cuánto sube `exertion` por segundo esprintando a fondo, y cuánto baja descansando.
##
## La bajada es MÁS LENTA que la subida a propósito: seguir jadeando después de frenar es justo el
## momento en que el efecto se lee, porque es cuando el personaje está quieto y se lo mira.
const EXERTION_RISE := 0.10
const EXERTION_FALL := 0.045

## 0 = respirando tranquilo, 1 = sin aire. Lo consume la respiración (ritmo Y amplitud).
var exertion: float = 0.0
## Fase del ciclo respiratorio, 0..TAU.
var breath_phase: float = 0.0
## Tiempo acumulado, para los efectos que no son cíclicos (el temblor).
var time: float = 0.0

## ⚠ FALSE MIENTRAS SE REGISTRAN LAS ANIMACIONES, y por una razón que no se ve venir.
##
## `ProceduralBoneAnimator` guarda como línea de base **el valor del driver en el momento del
## registro**, y después resta eso siempre. Para las señales de marcha es correcto (el reposo del
## hueso corresponde al valor de reposo de la señal). Para un OSCILADOR es un bug: `time` arranca en
## un valor sembrado al azar, así que la base sale un número cualquiera y queda un **corrimiento
## permanente** — una mano colgando 10 mm fuera de lugar, distinta en cada respawn, y el pecho fijo
## medio inhalado.
##
## Con esto en false los drivers devuelven 0 durante el registro, la base queda en 0, y la oscilación
## sale centrada en el reposo. Lo prende `PassiveAnimations.register_all()` al terminar.
var active: bool = false


static func create(character_seed: int) -> PassiveState:
	var s := PassiveState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = character_seed
	s.breath_phase = rng.randf() * TAU
	s.time = rng.randf() * 1000.0
	return s


## `effort` es 0..1: cuánto se está esforzando el personaje AHORA. Lo calcula quien llama, de la
## velocidad, así que sirve igual para el jugador local, para un proxy y para un NPC.
func update(delta: float, effort: float) -> void:
	var rate: float = EXERTION_RISE * effort - EXERTION_FALL * (1.0 - effort)
	exertion = clampf(exertion + rate * delta, 0.0, 1.0)

	var period: float = lerpf(BREATH_PERIOD_REST, BREATH_PERIOD_HARD, exertion)
	breath_phase = fposmod(breath_phase + TAU * delta / maxf(period, 0.01), TAU)
	time += delta


## Curva respiratoria, 0 = exhalado, 1 = inhalado.
##
## NO es un seno, y esa es la mitad del efecto: una respiración real **inhala rápido, exhala más
## lento, y hace una pausa** antes de volver a empezar. Un seno puro se lee como un fuelle mecánico.
##
## La pausa se acorta con el esfuerzo — jadeando no hay descanso entre ciclos.
func breath() -> float:
	if not active:
		return 0.0
	var pause: float = lerpf(0.20, 0.02, exertion)
	var inhale: float = (1.0 - pause) * 0.40
	var exhale: float = (1.0 - pause) - inhale
	var t: float = breath_phase / TAU
	if t < inhale:
		return smoothstep(0.0, 1.0, t / inhale)
	if t < inhale + exhale:
		return 1.0 - smoothstep(0.0, 1.0, (t - inhale) / exhale)
	return 0.0


## Amplitud de la respiración: crece con el esfuerzo. Cansado no es solo más rápido, es más profundo.
func breath_amplitude() -> float:
	return 1.0 + exertion * 1.8


## Piso del envolvente del temblor: la amplitud nunca baja de esta fracción del pico.
##
## Es LA perilla del carácter del temblor. En 1.0 tiembla parejo y se lee mecánico; en 0.1 se apaga por
## completo entre ondas y parece que se cura y recae.
##
## En 0.2 baja bastante, pero NO tanto como sugiere el número: el sesgo hacia arriba y las dos
## frecuencias hacen que el valle profundo sea raro en vez de periódico.
const TREMOR_FLOOR := 0.2

## Temblor cuasi-periódico, −1..1. `offset` desfasa articulaciones entre sí.
##
## Tres decisiones en el envolvente, todas para que no se lea como una onda:
##
##   1. **Dos senos a frecuencias inconmensurables** (1.7 y 0.73). Con uno solo el sube-y-baja tiene un
##      período fijo de ~3.7 s y el ojo lo aprende. Con dos que no encajan, los valles rara vez
##      coinciden y el patrón tarda decenas de segundos en repetirse.
##   2. **Sesgo hacia arriba** (`pow(mix, 0.6)`). Un seno pasa tanto tiempo abajo como arriba; el sesgo
##      lo empuja al techo, así que tiembla casi siempre y solo baja un instante.
##   3. **Reescalado sobre TREMOR_FLOOR**, para que el valle no llegue a cero.
##
## Y `fast` no es ruido blanco: un temblor real ronda los 5 Hz. `randf()` por frame se lee como un error
## de render y además depende de los FPS.
func tremor(offset: float) -> float:
	if not active:
		return 0.0
	var t: float = time + offset
	var fast: float = sin(t * 31.4)
	var slow_a: float = 0.5 + 0.5 * sin(t * 1.70 + offset)
	var slow_b: float = 0.5 + 0.5 * sin(t * 0.73 + offset * 2.0 + 2.1)
	var mix: float = pow(slow_a * 0.6 + slow_b * 0.4, 0.6)
	return fast * (TREMOR_FLOOR + (1.0 - TREMOR_FLOOR) * mix)
