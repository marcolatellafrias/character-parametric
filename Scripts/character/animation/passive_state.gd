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


## Temblor cuasi-periódico, −1..1. `offset` desfasa articulaciones entre sí.
##
## No es ruido blanco: un temblor real ronda los 5 Hz con la amplitud vagando. `randf()` por frame se
## lee como un error de render y además depende de los FPS.
func tremor(offset: float) -> float:
	var t: float = time + offset
	var fast: float = sin(t * 31.4)
	var wander: float = 0.55 + 0.45 * sin(t * 1.7 + offset)
	return fast * wander
