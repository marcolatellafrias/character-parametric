class_name EntityArchetype

enum Archetype {fat_man, kid, tall_lanky, giga, old, generic}

# BASE STATS
var strenght : float = 1.0
var weight : float = 60.0
var speed : float = 1.0
var back_speed_factor : float = 1.0
var lateral_speed_factor : float = 1.0
var sprint_multiplier : float = 2.0
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
var shoulder_swing : float = 0.5
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
var legs_length  : float = 0.5
var arms_length  : float = 0.5
var torso_length : float = 0.5

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
## Tiene las tres cadenas en 0.5, o sea el largo esculpido exacto ⇒ deformación cero. Poniendo
## EntityInstantiation.FORCE_GENERIC_ARCHETYPE en true todos los personajes vuelven a ser este, que es
## la vista de la fase 1 y sigue sirviendo para mirar el modelo sin ruido.
## Ver technical/skinned-character-migration.md.
static func generic_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 1.0
	arch.weight = 80.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 1.6
	arch.acceleration = 0.6
	arch.foward_stability = 1.0
	arch.backwards_stability = 1.0
	arch.sideways_stability = 1.0
	arch.stability_spring = 1.0
	arch.stability_damp = 1.0
	arch.time_to_standup = 1.5
	arch.throw_strenght = 0.7
	arch.jump_height = 0.8
	arch.time_to_max_jump = 0.5
	arch.min_age = 20
	arch.max_age = 60
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	# No entra en el sorteo ni en los blends: es un arquetipo de referencia, no de población.
	arch.archetype_frequency = 0.0
	arch.shoulder_swing = 0.5
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
	# Brazos casi rectos al costado, apenas separados del torso. En 0.0 se meten dentro del cuerpo.
	# `arm_bentness` no puede ser 0 en la práctica: a extensión total el codo queda colineal y la mano
	# sale rotada al azar (ver SkeletonSizesUtil.ARM_REST_EXTENSION).
	arch.arm_openness = 0.25
	arch.arm_bentness = 0.12
	arch.fatness = 0.5
	arch.muscularity = 0.5
	arch.has_neck = true
	# El modelo tal cual se esculpió. 0.5 en las tres = deformación cero.
	arch.legs_length  = 0.5
	arch.arms_length  = 0.5
	arch.torso_length = 0.5
	arch.height = 1.71
	arch.chest_to_low_spine_proportion = 0.33
	arch.legs_to_feet_proportion = 0.55
	arch.shoulder_width_proportion = 0.125
	arch.head_neck_ratio = 0.25
	arch.stance_width = 1.0
	return arch

static func fat_man_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.9
	arch.weight = 120.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 1.65
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
	arch.shoulder_swing = 0.3
	arch.side_swing = 0.5
	arch.arm_swing = 0.5
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.8
	arch.step_height = 0.4
	# Camina "corto para lo que mide": pasitos rápidos bajo un cuerpo pesado, base ancha.
	arch.stride = 0.45
	arch.leg_cripple_chance = 0.1
	arch.slouch = 0.0
	arch.arm_openness = 0.58
	arch.arm_bentness = 0.18
	arch.fatness = 1.0
	arch.muscularity = 0.9
	arch.has_neck = true
	# Torso grande sobre piernas cortas. ≈1.74 m.
	arch.legs_length  = 0.45
	arch.arms_length  = 0.50
	arch.torso_length = 0.70
	arch.height = 1.85
	arch.chest_to_low_spine_proportion = 0.28
	arch.legs_to_feet_proportion = 0.42
	arch.shoulder_width_proportion = 0.13
	arch.head_neck_ratio = 0.4
	arch.stance_width = 1.4
	return arch

static func kid_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.3
	arch.weight = 30.0
	arch.speed = 0.4
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 1.5
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
	arch.shoulder_swing = 0.5
	arch.side_swing = 0.5
	arch.arm_swing = 0.7
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.7
	arch.step_height = 0.4
	# Trotecito: piernas cortas, muchos pasos chicos.
	arch.stride = 0.40
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.1
	arch.arm_openness = 0.5
	arch.arm_bentness = 0.2
	arch.fatness = 0.23
	arch.muscularity = 0.17
	arch.has_neck = true
	# El más chico de todos. ≈1.38 m.
	arch.legs_length  = 0.15
	arch.arms_length  = 0.20
	arch.torso_length = 0.25
	arch.height = 1.45
	arch.chest_to_low_spine_proportion = 0.27
	arch.legs_to_feet_proportion = 0.48
	arch.shoulder_width_proportion = 0.15
	arch.head_neck_ratio = 0.25
	arch.stance_width = 1.4
	return arch

static func tall_lanky_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.5
	arch.weight = 80.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 1.5
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
	arch.shoulder_swing = 0.5
	arch.side_swing = 0.5
	arch.arm_swing = 0.2
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.8
	arch.step_height = 0.4
	# Zancada larga y suelta: el que más estira el paso para su pierna (que además es la más larga).
	arch.stride = 0.85
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.5
	arch.arm_openness = 0.2
	arch.arm_bentness = 0.11
	arch.fatness = 0.37
	arch.muscularity = 0.27
	arch.has_neck = true
	# Piernas y brazos largos, torso medio: el desgarbado. ≈1.89 m.
	arch.legs_length  = 0.85
	arch.arms_length  = 0.80
	arch.torso_length = 0.55
	arch.height = 1.95
	arch.chest_to_low_spine_proportion = 0.28
	arch.legs_to_feet_proportion = 0.52
	arch.shoulder_width_proportion = 0.13
	arch.head_neck_ratio = 0.45
	arch.stance_width = 1.4
	return arch

static func giga_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 1.2
	arch.weight = 120.0
	arch.speed = 0.2
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 1.5
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
	arch.shoulder_swing = 1.0
	arch.side_swing = 0.5
	arch.arm_swing = 0.2
	arch.hip_swing = 0.5
	arch.root_bounciness = 1.0
	arch.step_height = 0.45
	# Pisotones: pocos pasos, largos y lentos (es de los más lentos, así que la cadencia baja igual).
	arch.stride = 0.75
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.0
	arch.arm_openness = 0.4
	arch.arm_bentness = 0.18
	arch.fatness = 0.5
	arch.muscularity = 1.0
	arch.has_neck = true
	# Tronco enorme sobre piernas medias: el macizo. ≈1.85 m.
	arch.legs_length  = 0.60
	arch.arms_length  = 0.65
	arch.torso_length = 0.80
	arch.height = 1.7
	arch.chest_to_low_spine_proportion = 0.3
	arch.legs_to_feet_proportion = 0.47
	arch.shoulder_width_proportion = 0.14
	arch.head_neck_ratio = 0.5
	arch.stance_width = 1.3
	return arch

static func old_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.4
	arch.weight = 120.0
	arch.speed = 0.15
	arch.back_speed_factor = 0.6
	arch.lateral_speed_factor = 0.8
	arch.sprint_multiplier = 1.5
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
	arch.shoulder_swing = 0.5
	arch.side_swing = 0.5
	arch.arm_swing = 0.5
	arch.hip_swing = 0.5
	arch.root_bounciness = 0.5
	arch.step_height = 0.3
	# Arrastra los pies: la zancada más corta de todas.
	arch.stride = 0.25
	arch.leg_cripple_chance = 0.0
	arch.slouch = 1.0
	arch.arm_openness = 0.25
	arch.arm_bentness = 0.1
	arch.fatness = 0.1
	arch.muscularity = 0.0
	arch.has_neck = true
	# Encogido: todo por debajo de la media. ≈1.59 m.
	arch.legs_length  = 0.40
	arch.arms_length  = 0.40
	arch.torso_length = 0.40
	arch.height = 1.65
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.shoulder_width_proportion = 0.11
	arch.head_neck_ratio = 0.45
	arch.stance_width = 1.4
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
	r.fatness                       = lerpf(fatness, b.fatness, t)
	r.muscularity                   = lerpf(muscularity, b.muscularity, t)
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
