class_name EntityArchetype

enum Archetype {fat_man, kid, tall_lanky, giga, old, generic}

# BASE STATS
var strenght : float = 1.0
var weight : float = 60.0
var speed : float = 1.0
var back_speed_factor : float = 1.0
var lateral_speed_factor : float = 1.0
## Cuántas veces la velocidad de caminata alcanza el sprint. Solo toca el TOPE — la aceleración para
## llegar ahí la maneja `CharacterRigidBody3D.SPRINT_TOP_ACCEL`, que la hace caer cerca del techo.
var sprint_multiplier : float = 2.2
var acceleration : float = 4.0
var foward_stability : float = 1.0
var backwards_stability : float = 1.0
var sideways_stability : float = 1.0
var stability_spring : float = 1.0
var stability_damp : float = 1.0
var time_to_standup : float = 4.0

# REACH/ARMS
var throw_strenght : float = 1.0

# JUMP
## Altura del apex a carga máxima, EN METROS (CharacterRigidBody3D.jump_to_height despeja el impulso).
## Un toque sin cargar sube el 30% de esto.
var jump_height : float = 0.8
var time_to_max_jump : float = 1.0

# AGE RANGE
var min_age : float = 1
var max_age : float = 99

# SPECIE PROBABILITIES
var robot_chance : float = 0.3
var alien_chance : float = 0.3
var human_chance : float = 1.0

# ANIMATIONS
## CUÁNTO SE MUEVE EL HOMBRO AL CAMINAR. **1.0 = el andar de referencia**, no el máximo: por debajo se
## apaga, por encima se exagera. Escala las seis registraciones de hombro de `animations.gd`.
##
## Los valores se re-escalaron ×2 cuando el knob pasó a manejar todo el hombro: antes 0.5 era el default
## y solo tocaba una registración menor, así que subirlo o bajarlo casi no hacía nada.
var shoulder_swing : float = 1.0
var hip_swing : float = 0.5
var side_swing : float = 0.5
var arm_swing : float = 0.5
var root_bounciness : float = 0.5
## Altura del arco del paso, en fracción del largo de pierna.
var step_height : float = 0.5
## ZANCADA — el único knob del andar, 0..1. No está en metros ni en fracción de pierna: es "cuánto
## de su alcance útil usa este personaje al caminar". 0 = pasitos cortos, 1 = zancada máxima.
##
## De acá sale TODO lo demás (SkeletonSizesUtil.create): la altura de pelvis que hace falta para que
## el pie llegue a esa zancada con la rodilla flexionada, y de ahí el alcance y la zancada en metros.
## Por eso `distance_from_ground_factor` ya no se escribe a mano — se deriva. Ver
## technical/character-animation.md (el modelo de marcha).
var stride : float = 0.6
var leg_cripple_chance : float = 0.0
var stance_width: float = 1.0

# POSTURE
var slouch : float = 0.0
## FLEXIÓN DE RODILLA EN REPOSO, 0..1. 0 = piernas casi rectas (~20° de rodilla), 1 = bien flexionadas
## (~52°). Es el equivalente de `arm_bentness` para la pierna.
##
## No es una pose que se escriba en un hueso: sale de **cuánto de su largo usa la pierna al estar
## parada**, o sea de la altura de pelvis. La geometría hace el resto — más flexión es la pelvis más
## abajo, y la IK acomoda rodilla y pie sola.
##
## Volvió a existir porque el modelo dejó de aportarla: antes la postura de reposo venía inclinada en el
## esqueleto y se leía de ahí; ahora está todo derecho y la flexión hay que pedirla.
var leg_bentness : float = 0.0
## ── POSTURA DE HOMBRO, −1..1 cada una ─────────────────────────────────────────────────────────────
## El signo importa y las dos direcciones sirven:
##
##   `shoulders_forward`  +adelante (encorvado, tímido, cargando peso)  /  −atrás (pecho abierto, marcial)
##   `shoulders_drop`     +caídos (cansado, vencido)                    /  −levantados (tenso, con frío)
##
## Independientes de `slouch` a propósito. Nacieron con el viejo, pero un hombro adelantado o caído no
## es exclusivo de una espalda vencida: sirve para un tímido, para alguien cargando peso, para un
## derrotado. Atarlas al slouch las hubiera dejado inservibles fuera de ese caso.
##
## Y van SEPARADAS entre sí porque son dos lecturas distintas: adelantar cierra el pecho, bajar afloja
## el cuello y alarga la silueta. Un viejo hace las dos, pero no en la misma proporción.
## ── ANCHO DE ESQUELETO ────────────────────────────────────────────────────────────────────────────
## Multiplican el hueso de hombro y el de cadera. 1.0 = el modelo.
##
## NO tienen shape key ni cuestan una escultura: son dos huesos horizontales, y escalarlos se lleva el
## brazo y la pierna con ellos. Es la perilla más barata de todo el sistema de proporciones.
##
## Existen porque `muscle` y `fat` solo pueden ENSANCHAR desde el modelo, que es la esquina más angosta.
## El nene los necesitaba más angostos todavía —con el ancho de un adulto y 1.35 m se leía como petiso
## y no como chico— y ningún valor de masa podía darle eso.
##
## Van SEPARADOS porque la RELACIÓN hombro/cadera es de las que más dice: en un adulto ronda 1.5 y en un
## chico está mucho más cerca de 1. Con un solo multiplicador esa relación quedaba clavada.
##
## Se aplican DESPUÉS de la masa, así que componen: un chico gordito es más ancho que un chico flaco, y
## los dos entran en un esqueleto de chico.
var shoulders_scale : float = 1.0
var hips_scale : float = 1.0

var shoulders_forward : float = 0.0
var shoulders_drop : float = 0.0

## TEMBLOR EN REPOSO, 0..1. Manda las registraciones de `passive_animations.gd`.
##
## Es su propia variable y no se deduce de la edad a propósito: así el mismo efecto sirve después para
## un personaje herido, con frío o asustado, sin tocar nada.
var tremor : float = 0.0

## PROFUNDIDAD EXTRA DE LA RESPIRACIÓN, 0..1. **0 = normal**, no "sin respirar".
##
## Sube cuánto se abre el pecho SIN tocar el ritmo: el período sale solo de `exertion` en
## `PassiveState`, así que un gordo al que le cuesta respirar se lee por lo hondo, no por lo rápido.
##
## Normalizado como el resto de los knobs de cuerpo —0 neutro y el máximo declarado en un solo lugar,
## `PassiveState.BREATH_DEPTH_MAX`— y no como multiplicador crudo. Un multiplicador mezcla bien igual,
## pero el número no significa nada hasta que abrís el archivo que lo consume.
var breath_depth : float = 0.0

## ── OJOS Y CARA — TEMPORAL ────────────────────────────────────────────────────────────────────────
## Perillas de la prueba de ojos 3D. Cuando los párpados tengan huesos propios, esto se rehace bien y
## estas cuatro se van con `EyeRig`.
##
## `eye_openness`: 1 = ojo abierto normal, abajo de 1 entrecerrado. Es la mitad del carácter de una
## mirada — un viejo cansado y un nene despierto se distinguen antes por esto que por el movimiento.
var eye_openness : float = 1.0
## Cuánto se mueve la mirada. Multiplica la amplitud Y la frecuencia de las sacadas, porque un ojo
## inquieto hace las dos cosas: salta más lejos y más seguido.
var gaze_restlessness : float = 1.0
## Multiplicador de frecuencia de parpadeo. >1 parpadea más seguido.
var blink_rate : float = 1.0
## TEMPORAL: prende los planos de arruga (frente, pómulos, ojera, mentón). Las cejas se muestran
## siempre y no dependen de esto.
var has_wrinkles : bool = false

## FRECUENCIA EXTRA DE LA RESPIRACIÓN, 0..1. **0 = normal.** Acorta el período sin tocar la amplitud.
##
## Es el eje INDEPENDIENTE de `breath_depth`, y tenerlos separados es todo el punto: hondo y lento lee
## como "le cuesta respirar" (el gordo), rápido y normal lee como nervioso o hiperactivo (el giga). Con
## una sola perilla los dos personajes respirarían igual, más fuerte.
##
## Se compone con el esfuerzo en vez de reemplazarlo: `exertion` sigue acelerando desde acá, así que un
## personaje hiperactivo que además corrió jadea más rápido todavía. Techo en `PassiveState`.
var breath_rate : float = 0.0
var arm_openness: float = 0.5
var arm_bentness: float = 0.3

# VISUAL
var fatness : float = 0.5
var muscularity : float = 0.5
var has_neck: bool = true

# PROPORTIONS — LARGOS DE HUESO
## Las tres cadenas paramétricas, 0..1 sobre los rangos medidos del modelo de Blender
## (SkeletonSizesUtil.MIN_/MID_/MAX_*). **0.5 = el largo tal como fue esculpido**, no el promedio de
## los extremos: el modelo ES el genérico, y los extremos se modelan a mano sin obligación de quedar
## simétricos. Por eso la interpolación va en dos tramos (lerp_three).
## Reemplazan a `height` + `legs_to_feet_proportion` + `chest_to_low_spine_proportion` + `reach`:
## ahora el modelo define lo posible y el arquetipo elige adentro. Ver
## technical/skinned-character-migration.md.
##
## ── EL TORSO PUEDE SER NEGATIVO, Y ESTÁ BIEN ──────────────────────────────────────────────────────
## `torso_chain_for` no clampea, así que un valor negativo ENCOGE respecto de lo esculpido. El nene, el
## flaco y el viejo lo usan. No es un bug ni un valor a "arreglar".
##
## Es la consecuencia de re-basar el torso al MEDIO del rango usado (×1.4547 en Blender) en vez de al
## extremo corto. El motivo fue de sombreado, no de proporción: el espejo escala el hueso solo en su
## eje Y (`SkinnedBodyUtil`, `scaled_local(1, s, 1)`) y el skinning transforma las normales con esa
## misma matriz, cuando a una normal le corresponde la inversa transpuesta. El error crece con
## `|s − 1|`, y el giga —el más estirado, con s = 1.70— se veía mal en hombros y panza.
##
## Centrando la base, la desviación máxima cayó de 0.75 a 0.20 y el sombreado se limpió para los seis.
## Las proporciones NO cambiaron: los seis valores se recalibraron con `t = s_viejo / 1.4547 − 1`.
##
## ⚠ `TORSO_MODEL_FACTOR` sigue en 2.0 y ahora sobra: nadie pasa de 1.20. Da igual mientras no exista
## `torso_length_max` (sin key, el factor solo alimenta una `w` que no se escribe), pero el día que se
## esculpa hay que bajarlo a ~1.25 o el correctivo queda autorado para un rango que nadie usa.
##
## Piernas y brazos tienen el mismo problema de normales sin resolver, con desviaciones parecidas.
var legs_length  : float = 0.5
var arms_length  : float = 0.5
var torso_length : float = 0.5

## Cuánto puede ESTIRAR el brazo al agarrar, en múltiplos de su largo en reposo. Es una variable
## INDEPENDIENTE de `arms_length`, y la distinción importa: `arms_length` es la proporción del cuerpo
## —qué brazo tiene el personaje parado sin hacer nada— y esto es cuánto se sale de esa proporción
## para alcanzar algo. Un personaje de brazos cortos puede tener un estirón enorme y al revés.
##
## De acá sale `SkeletonSizesUtil.interaction_reach`, o sea el alcance de agarre en metros: es LA
## perilla del alcance por arquetipo.
##
## El techo lo pone el rango autorado en Blender (ver ReferenceRig.ARM_MODEL_FACTOR): el brazo
## estirado tiene la silueta que se esculpió, así que estirar no es "malla de goma" mientras el
## resultado caiga adentro del rango. SkeletonSizesUtil lo clampea ahí solo.
var arm_stretch : float = 2.0

## ── LOS DOS EJES DE MASA (clase B: solo malla) ────────────────────────────────────────────────────
## Van derecho a un shape key y no tocan ningún hueso: no cambian el alcance, ni la altura, ni la
## marcha, ni nada que el motor lea. Por eso NO llevan la curva `F·v/s` — esa existe solo para cancelar
## la escala de un hueso, y acá no hay hueso. Se escriben lineales y una sola vez, al construir.
##
## `0, 0` = LA MALLA TAL CUAL SE ESCULPIÓ, que es el extremo FLACO Y SIN MÚSCULO. Por eso ningún
## arquetipo va en 0: hasta el viejo débil lleva algo de las dos.
##
## `muscle + fat` es cuánta masa; `muscle / (muscle + fat)` es de qué tipo. Un tipo normal vive cerca de
## 0.7 de suma, un fuerte o un gordo cerca de 1, y el gordo fuerte arriba de 1.5 — ahí los dos deltas
## se apilan y el brazo queda más grande que el de cualquiera de los dos extremos, que es lo buscado.
##
## Están separados de `fatness` a propósito: `fatness` dimensiona los COLISIONADORES del rig lógico
## (los radios de las cápsulas de la columna), que es otra cosa. Si con el tiempo resulta que siempre
## se mueven juntos, se unifican; hoy no hay evidencia de eso.
var muscle : float = 0.0
var fat : float = 0.0


# PROPORTIONS — VESTIGIALES
## Ya NO alimentan el esqueleto: los largos salen de las tres variables de arriba, y cadera/hombros/
## cuello/cabeza están fijos en el largo esculpido hasta la fase 3. `height` en particular pasó a ser
## un RESULTADO (SkeletonSizesUtil.total_height); estos campos quedan solo como referencia de autor.
var height : float = 1.8
var chest_to_low_spine_proportion : float = 1.0
var legs_to_feet_proportion : float = 1.0
var shoulder_width_proportion : float = 1.0
var head_neck_ratio: float = 0.4

var uncompatible_archetypes : Array[Archetype] = []
var archetype_frequency : float = 1.0

static func create(archetype: Archetype) -> EntityArchetype:
	if(archetype == Archetype.fat_man):
		return fat_man_arch()
	if(archetype == Archetype.tall_lanky):
		return tall_lanky_arch()
	if(archetype == Archetype.kid):
		return kid_arch()
	if(archetype == Archetype.giga):
		return giga_arch()
	if(archetype == Archetype.generic):
		return generic_arch()
	else:
		return old_arch()

## NEUTRO — el arquetipo de referencia del modelo skinneado. Postura sin nada raro: sin joroba, sin
## piernas lisiadas, base de pies angosta, brazos rectos al costado. No es un
## personaje de juego: existe para poder MIRAR el modelo tal como se esculpió, sin que la postura de
## un arquetipo se coma la evaluación.
##
## Sus cadenas están elegidas para reproducir el modelo esculpido ORIGINAL, que no es lo mismo que
## poner 0.5: a medida que una cadena consigue sus extremos autorados en Blender, el modelo pasa a ser
## el 0.0 de esa cadena y el valor que reproduce el original se corre. Ver abajo.
##
## Con `EntityInstantiation.FORCE_ARCHETYPE` apuntando acá, todos los personajes vuelven a ser este —
## la vista de la fase 1, que sigue sirviendo para mirar el modelo sin ruido. Para mirar UN arquetipo
## sin tocar código está el panel de debug (tab Arquetipos).
## Ver technical/skinned-character-migration.md.
static func generic_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 1.0
	arch.weight = 80.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.6
	arch.acceleration = 0.6
	arch.foward_stability = 1.0
	arch.backwards_stability = 1.0
	arch.sideways_stability = 1.0
	arch.stability_spring = 1.0
	arch.stability_damp = 1.0
	arch.time_to_standup = 1.5
	arch.throw_strenght = 0.7
	arch.jump_height = 1.12
	arch.time_to_max_jump = 0.5
	arch.min_age = 20
	arch.max_age = 60
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	# No entra en el sorteo ni en los blends: es un arquetipo de referencia, no de población.
	arch.archetype_frequency = 0.0
	arch.shoulder_swing = 1.0
	arch.side_swing = 0.5
	arch.arm_swing = 0.5
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.5
	arch.step_height = 0.4
	# ZANCADA — significa literalmente "qué tan largo es el paso", nada más. La altura de pelvis ya NO
	# sale de acá: la resuelve la geometría cada frame (ver SkeletonSizesUtil.foot_reach y
	# BoneInstantiator._update_pelvis_drop).
	#
	# 0.95 da 0.460 m de excursión de pie contra los 0.354 de 0.60 — un 30% más de paso. Ojo que queda
	# cerca del techo del rango (FOOT_REACH_MIN/MAX): si hiciera falta más, conviene subir el techo y no
	# este número, que ya casi no tiene recorrido.
	arch.stride = 0.95
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.0
	arch.leg_bentness = 0.00
	arch.tremor = 0.0
	arch.shoulders_scale = 1.0
	arch.hips_scale = 1.0
	arch.eye_openness = 1.00
	arch.gaze_restlessness = 1.00
	arch.blink_rate = 1.00
	arch.has_wrinkles = false
	arch.shoulders_forward = -0.25
	arch.shoulders_drop = 0.0
	# Brazos casi rectos al costado, apenas separados del torso. `arm_openness` en 0.0 los mete dentro
	# del cuerpo, de ahí el 0.25.
	#
	# `arm_bentness` SÍ puede ser 0: el piso de la flexión lo pone `SkeletonSizesUtil.ARM_REST_EXTENSION`
	# (0.985 → ~20° de codo), que existe justo para que la extensión total nunca se alcance. A extensión
	# total el codo queda colineal, el plano de flexión se indefine y la torsión de la mano sale
	# arbitraria — fue el bug de las manos dadas vuelta.
	#
	# HOY TODOS LOS ARQUETIPOS ESTÁN EN 0. Los valores viejos (0.10–0.20) venían de cuando el brazo del
	# modelo era más corto y el codo necesitaba flexión propia para no quedar colineal; con el tope de
	# 0.985 haciendo ese trabajo, lo único que agregaban era un codo doblado de más. Vuelve a ser un
	# knob por arquetipo cuando haya una razón de postura para diferenciarlos.
	#
	# `arm_openness` y `stance_width` estuvieron IGUALADOS EN LOS SEIS un tiempo: los valores viejos
	# (0.2 a 0.58) eran de cuando la postura era lo único que distinguía a un arquetipo de otro, y con
	# la variedad viniendo de largo de cadena, músculo y grasa, abrir los brazos encima solo era ruido.
	#
	# El `fat_man` es el primero que los vuelve a mover, y con la razón que faltaba: no es gusto de
	# postura, es que el cuerpo OCUPA LUGAR. Con la cadera a 1.62× los muslos se tocan y con ese torso
	# los brazos no pueden colgar pegados. Los dos números salen de la geometría, no del estilo — y ese
	# es el criterio para que otro arquetipo los toque.
	arch.arm_openness = 0.18
	arch.arm_bentness = 0.0
	arch.fatness = 0.5
	arch.muscularity = 0.5
	arch.has_neck = true
	# ── LOS VALORES QUE REPRODUCEN EL MODELO ESCULPIDO ────────────────────────────────────────────
	# Ojo: NO son 0.5 los tres, y la diferencia es estructural, no un ajuste fino.
	#
	# Una cadena sin extremos autorados usa el esquema provisorio (el modelo es el 0.5, los extremos son
	# factores sobre él) ⇒ 0.5 reproduce el modelo. Una cadena YA AUTORADA en Blender tiene el modelo
	# como 0.0 —porque el 0.0 tiene que ser un extremo real— ⇒ el valor que reproduce el original es
	# otro, y sale de despejar `1 + (F−1)·v` contra el largo que tenía antes de acortarlo.
	#
	#   pierna: se acortó al 65% en Blender, F = 2 ⇒ v = 0.5385 devuelve los 0.9119 m de siempre
	#   brazo:  ver ARM_EXT_MIN/MAX — el arquetipo se mueve en una banda angosta del rango ×4
	#   torso:  todavía provisorio ⇒ 0.5
	arch.legs_length  = 0.589
	arch.arms_length  = 0.5851
	arch.torso_length = 0.09232
	# El genérico es la malla tal cual: deformación cero también en las de clase B.
	arch.muscle        = 0.0
	arch.fat           = 0.0
	arch.arm_stretch  = 2.0
	arch.height = 1.71
	arch.chest_to_low_spine_proportion = 0.33
	arch.legs_to_feet_proportion = 0.55
	arch.shoulder_width_proportion = 0.125
	arch.head_neck_ratio = 0.25
	# STANCE NEUTRAL EN TODOS LOS ARQUETIPOS, por ahora a propósito.
	#
	# La separación de pies ya sale del MODELO (`rig.foot_rest_x`, escalado por el largo de
	# pierna); esto es un multiplicador encima. Estaba en 1.3–1.4 en todos, de cuando la estancia
	# se estimaba del ancho de cadera, y se leía como piernas muy abiertas.
	#
	# Vuelve a diferenciarse cuando estén `torso_length` y `frame_width`: recién ahí la postura
	# tiene con qué distinguirse y el stance deja de ser el único parche disponible.
	arch.stance_width = 1.0
	return arch

static func fat_man_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.9
	arch.weight = 120.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.3
	arch.acceleration = 0.375
	arch.foward_stability = 0.7
	arch.backwards_stability = 0.7
	arch.sideways_stability = 0.7
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 2.0
	arch.throw_strenght = 0.5
	arch.jump_height = 0.5
	arch.time_to_max_jump = 0.3
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.3
	arch.alien_chance = 0.6
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing = 0.6
	arch.side_swing = 0.5
	arch.arm_swing = 0.5
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.8
	arch.step_height = 0.4
	# Camina "corto para lo que mide": pasitos rápidos bajo un cuerpo pesado, base ancha.
	arch.stride = 0.45
	arch.leg_cripple_chance = 0.1
	arch.slouch = 0.0
	arch.leg_bentness = 0.25
	arch.tremor = 0.0
	# DESPEJADAS contra la masa, no medidas solas. El ancho final es `masa × escala`, y las medidas de
	# Blender son 1.61765 de cadera y 1.45811 de hombro: con `fat 1.0` la cadera ya trae ×1.3 puesto, y
	# con `muscle 0.0` el hombro no trae nada y la medida va entera acá.
	# ⚠ Si algún día se mueve `fat` o `muscle`, estos dos hay que volver a despejarlos.
	arch.shoulders_scale = 1.27
	arch.hips_scale = 1.24435
	arch.breath_depth = 0.6
	arch.breath_rate = 0.0
	arch.eye_openness = 0.93
	arch.gaze_restlessness = 0.70
	arch.blink_rate = 1.25
	arch.has_wrinkles = false
	arch.shoulders_forward = -0.70
	arch.shoulders_drop = 0.0
	arch.arm_openness = 0.36
	arch.arm_bentness = 0.0
	arch.fatness = 1.0
	arch.muscularity = 0.9
	arch.has_neck = true
	# Torso grande sobre piernas cortas. ≈1.74 m.
	arch.legs_length  = 0.60
	arch.arms_length  = 0.7245
	arch.torso_length = 0.20198
	arch.muscle        = 0.0
	arch.fat           = 1.0
	arch.height = 1.85
	arch.chest_to_low_spine_proportion = 0.28
	arch.legs_to_feet_proportion = 0.42
	arch.shoulder_width_proportion = 0.13
	arch.head_neck_ratio = 0.4
	arch.stance_width = 1.18
	return arch

static func kid_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.3
	arch.weight = 30.0
	arch.speed = 0.4
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.5
	arch.acceleration = 0.9
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.3
	arch.jump_height = 0.75
	arch.time_to_max_jump = 0.5
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing = 1.0
	arch.side_swing = 0.5
	arch.arm_swing = 0.7
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.7
	arch.step_height = 0.4
	# Trotecito: piernas cortas, muchos pasos chicos.
	arch.stride = 0.40
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.1
	arch.leg_bentness = 0.00
	arch.tremor = 0.0
	arch.shoulders_scale = 0.901
	arch.hips_scale = 0.9224
	arch.eye_openness = 1.40
	arch.gaze_restlessness = 1.90
	arch.blink_rate = 1.45
	arch.has_wrinkles = false
	arch.shoulders_forward = 0.0
	arch.shoulders_drop = 0.55
	arch.arm_openness = 0.25
	arch.arm_bentness = 0.0
	arch.fatness = 0.23
	arch.muscularity = 0.17
	arch.has_neck = true
	# El más chico de todos. ≈1.38 m.
	arch.legs_length  = 0.26
	# 0.0 es el PISO REAL: el brazo tal cual se esculpió en Blender. No hay más corto que esto
	# sin re-esculpir la base, y para un personaje de 1.43 m sigue quedando proporcionalmente
	# largo — el mismo re-baseo que hubo que hacerle a la pierna le va a hacer falta al brazo.
	arch.arms_length  = 0.3614
	arch.torso_length = -0.16821
	arch.muscle        = 0.0
	arch.fat           = 0.0
	arch.height = 1.45
	arch.chest_to_low_spine_proportion = 0.27
	arch.legs_to_feet_proportion = 0.48
	arch.shoulder_width_proportion = 0.15
	arch.head_neck_ratio = 0.25
	arch.stance_width = 1.0
	return arch

static func tall_lanky_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.5
	arch.weight = 80.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.8
	arch.acceleration = 0.45
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.5
	arch.jump_height = 0.95
	arch.time_to_max_jump = 0.5
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.7
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing = 1.0
	arch.side_swing = 0.5
	arch.arm_swing = 0.2
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.8
	arch.step_height = 0.4
	# Zancada larga y suelta: el que más estira el paso para su pierna (que además es la más larga).
	arch.stride = 0.85
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.68
	arch.leg_bentness = 0.05
	arch.tremor = 0.0
	arch.shoulders_scale = 0.94
	arch.hips_scale = 0.97
	arch.eye_openness = 1.10
	arch.gaze_restlessness = 1.35
	arch.blink_rate = 0.85
	arch.has_wrinkles = false
	arch.shoulders_forward = 0.0
	arch.shoulders_drop = 0.58
	arch.arm_openness = 0.18
	arch.arm_bentness = 0.0
	arch.fatness = 0.37
	arch.muscularity = 0.27
	arch.has_neck = true
	# Piernas y brazos largos, torso medio: el desgarbado. ≈1.89 m.
	arch.legs_length  = 1.0790
	# Techo de la banda del arquetipo (ARM_EXT_MAX). El 1.0 del rango de Blender NO es esto:
	# ese está reservado para el estirón del agarre.
	arch.arms_length  = 1.0
	arch.torso_length = -0.10497
	# Enjuto: se queda en la malla esculpida, que es el extremo flaco.
	arch.muscle        = 0.20
	arch.fat           = 0.20
	arch.height = 1.95
	arch.chest_to_low_spine_proportion = 0.28
	arch.legs_to_feet_proportion = 0.52
	arch.shoulder_width_proportion = 0.13
	arch.head_neck_ratio = 0.45
	arch.stance_width = 1.0
	return arch

static func giga_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 1.2
	arch.weight = 120.0
	arch.speed = 0.2
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.3
	arch.acceleration = 0.5
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.9
	arch.jump_height = 0.85
	arch.time_to_max_jump = 0.5
	arch.min_age = 20
	arch.max_age = 90
	arch.robot_chance = 0.0
	arch.alien_chance = 1.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing = 1.5
	arch.side_swing = 0.5
	arch.arm_swing = 0.2
	arch.hip_swing = 0.5
	arch.root_bounciness = 1.0
	arch.step_height = 0.45
	# Pisotones: pocos pasos, largos y lentos (es de los más lentos, así que la cadencia baja igual).
	arch.stride = 0.75
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.0
	arch.leg_bentness = 0.00
	arch.tremor = 0.0
	# DESPEJADAS contra la masa, igual que en el fat_man. Medida de Blender: 1.20519 de cadera, con
	# `fat 0.10` aportando ×1.03. El hombro se midió en 1.61738 (con `muscle 1.0` trayendo ×1.3) y
	# después se bajó a ojo a 1.391: el ancho esculpido se leía de más una vez puesto el `muscle_max`.
	# La cadera siguió el mismo camino, de 1.20519 a 1.1610.
	# ⚠ Si se mueve `muscle` o `fat`, hay que volver a despejarlas.
	arch.shoulders_scale = 1.07
	arch.hips_scale = 1.12718
	arch.eye_openness = 0.88
	arch.gaze_restlessness = 0.45
	arch.blink_rate = 0.70
	arch.has_wrinkles = false
	arch.shoulders_forward = 0.0
	arch.breath_rate = 0.85
	arch.shoulders_drop = -0.32
	arch.arm_openness = 0.25
	arch.arm_bentness = 0.0
	arch.fatness = 0.5
	arch.muscularity = 1.0
	arch.has_neck = true
	# Tronco enorme sobre piernas medias: el macizo. ≈1.85 m.
	arch.legs_length  = 0.3824
	arch.arms_length  = 0.7857
	arch.torso_length = 0.07281
	# Grande y macizo, no gordo: pierna al máximo, panza moderada.
	arch.muscle        = 1.00
	arch.fat           = 0.10
	arch.height = 1.7
	arch.chest_to_low_spine_proportion = 0.3
	arch.legs_to_feet_proportion = 0.47
	arch.shoulder_width_proportion = 0.14
	arch.head_neck_ratio = 0.5
	arch.stance_width = 1.0
	return arch

static func old_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.4
	arch.weight = 120.0
	arch.speed = 0.15
	arch.back_speed_factor = 0.6
	arch.lateral_speed_factor = 0.8
	arch.sprint_multiplier = 1.8
	arch.acceleration = 0.5
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.35
	arch.jump_height = 0.35
	arch.time_to_max_jump = 0.5
	arch.min_age = 50
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing = 0.35
	arch.side_swing = 0.5
	arch.arm_swing = 0.5
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.5
	arch.step_height = 0.3
	# Arrastra los pies: la zancada más corta de todas.
	arch.stride = 0.12
	arch.leg_cripple_chance = 0.0
	arch.slouch = 1.0
	arch.leg_bentness = 0.30
	arch.tremor = 0.75
	arch.shoulders_scale = 1.0
	arch.hips_scale = 0.97
	arch.eye_openness = 0.78
	arch.gaze_restlessness = 0.60
	arch.blink_rate = 0.75
	arch.has_wrinkles = true
	arch.shoulders_forward = 1.0
	arch.shoulders_drop = 1.0
	arch.arm_openness = 0.25
	arch.arm_bentness = 0.0
	arch.fatness = 0.1
	arch.muscularity = 0.0
	arch.has_neck = true
	# Encogido: todo por debajo de la media. ≈1.59 m.
	arch.legs_length  = 0.560
	arch.arms_length  = 0.4819
	arch.torso_length = -0.08572
	arch.muscle        = 0.0
	arch.fat           = 0.0
	arch.height = 1.65
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.shoulder_width_proportion = 0.11
	arch.head_neck_ratio = 0.45
	arch.stance_width = 1.0
	return arch


func blend_with(b: EntityArchetype, t: float) -> EntityArchetype:
	var r := EntityArchetype.new()
	r.strenght                      = lerpf(strenght, b.strenght, t)
	r.weight                        = lerpf(weight, b.weight, t)
	r.speed                         = lerpf(speed, b.speed, t)
	r.back_speed_factor             = lerpf(back_speed_factor, b.back_speed_factor, t)
	r.lateral_speed_factor          = lerpf(lateral_speed_factor, b.lateral_speed_factor, t)
	r.sprint_multiplier             = lerpf(sprint_multiplier, b.sprint_multiplier, t)
	r.acceleration                  = lerpf(acceleration, b.acceleration, t)
	r.foward_stability              = lerpf(foward_stability, b.foward_stability, t)
	r.backwards_stability           = lerpf(backwards_stability, b.backwards_stability, t)
	r.sideways_stability            = lerpf(sideways_stability, b.sideways_stability, t)
	r.stability_spring              = lerpf(stability_spring, b.stability_spring, t)
	r.stability_damp                = lerpf(stability_damp, b.stability_damp, t)
	r.time_to_standup               = lerpf(time_to_standup, b.time_to_standup, t)
	r.throw_strenght                = lerpf(throw_strenght, b.throw_strenght, t)
	r.jump_height                   = lerpf(jump_height, b.jump_height, t)
	r.time_to_max_jump              = lerpf(time_to_max_jump, b.time_to_max_jump, t)
	r.min_age                       = lerpf(min_age, b.min_age, t)
	r.max_age                       = lerpf(max_age, b.max_age, t)
	r.robot_chance                  = lerpf(robot_chance, b.robot_chance, t)
	r.alien_chance                  = lerpf(alien_chance, b.alien_chance, t)
	r.human_chance                  = lerpf(human_chance, b.human_chance, t)
	r.shoulder_swing                = lerpf(shoulder_swing, b.shoulder_swing, t)
	r.side_swing 					= lerpf(side_swing, b.side_swing, t)
	r.arm_swing 					= lerpf(arm_swing, b.arm_swing, t)
	r.hip_swing                     = lerpf(hip_swing, b.hip_swing, t)
	r.root_bounciness               = lerpf(root_bounciness, b.root_bounciness, t)
	r.step_height                   = lerpf(step_height, b.step_height, t)
	r.stride                        = lerpf(stride, b.stride, t)
	r.leg_cripple_chance            = lerpf(leg_cripple_chance, b.leg_cripple_chance, t)
	r.slouch                        = lerpf(slouch, b.slouch, t)
	r.leg_bentness                  = lerpf(leg_bentness, b.leg_bentness, t)
	r.tremor                        = lerpf(tremor, b.tremor, t)
	r.breath_depth                  = lerpf(breath_depth, b.breath_depth, t)
	r.breath_rate                   = lerpf(breath_rate, b.breath_rate, t)
	r.eye_openness                  = lerpf(eye_openness, b.eye_openness, t)
	r.gaze_restlessness             = lerpf(gaze_restlessness, b.gaze_restlessness, t)
	r.blink_rate                    = lerpf(blink_rate, b.blink_rate, t)
	# Discreto: o tiene arrugas o no. Se toma el del primario, como has_neck.
	r.has_wrinkles                  = has_wrinkles
	r.shoulders_scale               = lerpf(shoulders_scale, b.shoulders_scale, t)
	r.hips_scale                    = lerpf(hips_scale, b.hips_scale, t)
	r.shoulders_forward             = lerpf(shoulders_forward, b.shoulders_forward, t)
	r.shoulders_drop                = lerpf(shoulders_drop, b.shoulders_drop, t)
	r.fatness                       = lerpf(fatness, b.fatness, t)
	r.muscle                        = lerpf(muscle, b.muscle, t)
	r.fat                           = lerpf(fat, b.fat, t)
	r.muscularity                   = lerpf(muscularity, b.muscularity, t)
	r.arm_stretch                   = lerpf(arm_stretch, b.arm_stretch, t)
	# DISCRETO A PROPÓSITO, y por eso se copia de A en vez de promediarse: no es una proporción, es de
	# qué está hecho el personaje. Un robot puede no tener cuello; medio cuello no existe.
	r.has_neck                      = has_neck
	r.legs_length                   = lerpf(legs_length, b.legs_length, t)
	r.arms_length                   = lerpf(arms_length, b.arms_length, t)
	r.torso_length                  = lerpf(torso_length, b.torso_length, t)
	r.height                        = lerpf(height, b.height, t)
	r.chest_to_low_spine_proportion = lerpf(chest_to_low_spine_proportion, b.chest_to_low_spine_proportion, t)
	r.legs_to_feet_proportion       = lerpf(legs_to_feet_proportion, b.legs_to_feet_proportion, t)
	r.shoulder_width_proportion     = lerpf(shoulder_width_proportion, b.shoulder_width_proportion, t)
	r.head_neck_ratio = lerpf(head_neck_ratio, b.head_neck_ratio, t)
	r.stance_width = lerpf(stance_width, b.stance_width, t)
	r.arm_openness          = lerpf(arm_openness, b.arm_openness, t)
	r.arm_bentness          = lerpf(arm_bentness, b.arm_bentness, t)
	return r
