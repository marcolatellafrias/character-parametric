class_name SkeletonSizesUtil

var leg_height : float
var torso_height : float
var head_height : float
var hips_width : float
var shoulders_width : float
## Largo de la cadena del brazo (hombro→muñeca) en metros. Reemplaza a `EntityArchetype.reach`, que
## ya no existe: el largo del brazo sale del rango del modelo, no de un número autorado.
var arm_reach : float
## Hasta dónde llega a agarrar, en metros. Derivado del brazo (× MAX_ARM_STRETCH × 0.97), no autorado
## — reemplaza a `reach × reach_multiplier`. Ver "The arm reach problem" en el doc de migración.
var interaction_reach : float
## Altura total del personaje, en metros. Es un RESULTADO (pierna + torso + cabeza), no una entrada.
var total_height : float

var head_size: Vector3
var neck_size: Vector3
var chest_size: Vector3
var higher_spine_size: Vector3
var middle_spine_size: Vector3
var lower_spine_size: Vector3
var higher_leg_size: Vector3
var lower_leg_size: Vector3
var foot_size: Vector3
var lower_feet_size: Vector3
var upper_arm_size: Vector3
var lower_arm_size: Vector3
var shoulder_width: Vector3
var hip_size: Vector3
var raycast_stance_offset: float

# ── MARCHA ────────────────────────────────────────────────────────────────────────────────────────
# Todo esto se deriva del knob `stride` del arquetipo. Ver technical/character-animation.md.

## Extensión máxima "cómoda" de la cadena de la pierna, en fracción de su largo. A 1.0 la pierna
## queda trabada recta (la IK clampea y el pie deja de llegar al target); 0.95 deja la rodilla
## visiblemente flexionada incluso en el punto más estirado del paso.
const MAX_EXTENSION := 0.95
## Extensión de la pierna PARADO, en fracción de su largo. NO es un margen de seguridad (la pelvis ya
## baja sola cuando no llega): es la GARANTÍA de que la pierna alcanza el piso estando parado. Subirlo
## hacia 1.0 endereza la pierna y acerca el reposo al modelo, a cambio de trabar antes en terreno
## irregular.
const STAND_EXTENSION := 0.97

## Excursión máxima del pie desde la cadera, en fracción del largo de pierna, mapeada desde `stride`.
## Ya NO se deriva de la altura de pelvis: es al revés — se elige la zancada y la pelvis baja lo que
## haga falta (ver BoneInstantiator._update_pelvis_drop). El tope existe para que la bajada no se
## vaya de rango, no por geometría.
const FOOT_REACH_MIN := 0.20
const FOOT_REACH_MAX := 0.55
## Duty factor: fracción del ciclo que el pie pasa APOYADO. Caminando >0.5 (siempre hay un pie en el
## piso, y hay doble apoyo); corriendo <0.5 (hay fase de vuelo con los dos pies en el aire).
const DUTY_WALK := 0.62
const DUTY_RUN  := 0.40

## Excursión máxima del pie desde la cadera, en metros. Es una ELECCIÓN (sale de `stride`), no una
## consecuencia de la altura de pelvis: la pelvis se acomoda para que el pie llegue.
var foot_reach: float
## EXCURSIÓN del pie de este frame (A, metros): cuánto se adelanta/atrasa el pie respecto de la
## cadera. El pie pisa en +A y despega en −A, así que su recorrido en el marco del cuerpo es 2A.
var current_excursion: float
## ZANCADA de este frame (S, metros): lo que avanza el cuerpo en un ciclo completo de un pie.
## Durante el apoyo (fracción D del ciclo) el pie está fijo en el mundo, o sea que en el marco del
## cuerpo retrocede D·S; y ese recorrido tiene que ser exactamente 2A ⇒ **S = 2A/D**. De ahí sale la
## cadencia: f = v/S. No es un parámetro libre — se deriva de la geometría y del duty.
var current_stride: float
var current_duty: float

var step_height: float
## Altura del TOBILLO sobre el piso, o sea el grosor de pie/zapato. Sale del modelo (en Blender la
## planta apoya en 0). Es lo que separa "el pie apoya" de "el tobillo toca el piso".
var ankle_height: float
## Altura de la pelvis parado, en metros sobre el piso. Sale del modelo (ReferenceRig).
var standing_pelvis_height: float
var distance_from_ground: float
var raycast_leg_lenght: float
var pole_distance: float
var axis_weight_lateral:  float = 0.6
var axis_weight_forward:  float = 0.8
var axis_weight_backward: float = 1.0

var slouchiness_chest: float
var slouchiness_center_spine: float
var slouchiness_neck: float

var arm_openness_angle: float
var arm_bentness: float
## Hacia dónde apunta el codo, 0..1 (0 = adentro, 0.5 = atrás, 1 = afuera). Constante por ahora:
## era por arquetipo y se simplificó mientras se cierra el personaje genérico.
const ELBOW_POLE_DIRECTION := 0.7
var left_arm_tip_rest_local: Vector3
var right_arm_tip_rest_local: Vector3
var left_arm_pole_rest_local: Vector3
var right_arm_pole_rest_local: Vector3

var left_arm_shoulder_rest_local: Vector3
var right_arm_shoulder_rest_local: Vector3


var raycast_start_y_offset: float = 0.0

const CONST_HEAD_HEIGHT    := 0.378
const CONST_HEAD_RADIUS_XZ := 0.19

# ── LARGOS DE HUESO: EL MODELO DE BLENDER MANDA ───────────────────────────────────────────────────
# Todos los largos salen de rangos medidos del modelo, NO de `height` × proporciones. El arquetipo
# solo aporta un 0..1 por cadena (legs_length / arms_length / torso_length) y acá se convierte a
# metros. Consecuencia buscada: `height` deja de ser una entrada y pasa a ser un RESULTADO — ver
# `total_height`. Si un arquetipo quisiera un largo fuera del rango, gana el rango.
#
# EL MODELO ES EL 0.5. El largo esculpido de cada cadena es el valor en 0.5, y se LEE DEL RIG — no se
# transcribe. Antes eran constantes copiadas de un volcado, y quedaban viejas en silencio en cuanto se
# re-exportaba el modelo: el rig lógico seguía pidiendo las proporciones de la versión anterior y el
# espejo estiraba la malla para cumplirlas.
#
# ⚠ Los EXTREMOS siguen siendo provisorios: factores sobre el largo esculpido, hasta que estén
# modelados en Blender y sepamos los reales. Ver technical/character-blender-length-variable.md.
const LENGTH_MIN_FACTOR := 0.65
const LENGTH_MAX_FACTOR := 1.30



## Extensión máxima del brazo en reposo, en fracción de su cadena. Nunca 1.0: a extensión total el
## codo queda colineal, el plano de flexión se indefine y la torsión de la mano sale arbitraria.
const ARM_REST_EXTENSION := 0.97

## Techo de estiramiento del brazo al agarrar algo, en múltiplos de su largo esculpido. De acá sale
## el alcance de interacción: más allá de esto la malla del brazo se ve de goma. Ver "The arm reach
## problem" en el doc.
const MAX_ARM_STRETCH := 1.25

static func create(inst: EntityInstantiation) -> SkeletonSizesUtil:
	var skelSizes = SkeletonSizesUtil.new()
	var entityStats := inst.arch_final
	var rig := ReferenceRig.get_rig()

	# Las tres cadenas paramétricas: 0..1 del arquetipo → metros, dentro del rango del modelo.
	var new_leg_height   := _chain(rig.leg_chain, entityStats.legs_length)
	var new_torso_height := _chain(rig.torso_chain,   entityStats.torso_length)
	var new_arm_length   := _chain(rig.arm_chain,     entityStats.arms_length)
	# Cuánto se aparta esta pierna de la del modelo: escala lo que se lee del rig (estancia, tobillo).
	var leg_scale: float = new_leg_height / rig.leg_chain if rig.leg_chain > 0.0 else 1.0
	# Todavía sin parametrizar (fase 3): quedan en el largo esculpido.
	# Todavía sin parametrizar (fase 3): quedan en el largo esculpido, leído del rig.
	var new_head_height       := rig.neck_len + rig.head_len
	var new_hips_width        := rig.hip_len
	var new_shoulders_width   := rig.shoulder_len

	skelSizes.arm_reach = new_arm_length
	# Alcance de interacción: hasta dónde puede agarrar, derivado del brazo y no autorado. El 0.97 es
	# el GRAB_MIN_BEND_FACTOR de ArmsController — con ese techo el brazo nunca se estira más de
	# MAX_ARM_STRETCH veces su largo esculpido.
	skelSizes.interaction_reach = new_arm_length * MAX_ARM_STRETCH * 0.97
	# `height` ya no es una entrada: es esto. Lo lee la cápsula, la cámara y el panel de debug.
	skelSizes.total_height = new_leg_height + new_torso_height + new_head_height

	skelSizes.leg_height      = new_leg_height
	skelSizes.torso_height    = new_torso_height
	skelSizes.head_height     = new_head_height
	skelSizes.hips_width      = new_hips_width
	# La estancia sale del MODELO, no del ancho de cadera. Si el pie en reposo no cae donde el modelo lo
	# tiene, la tibia queda girada respecto de él y el pie —que cuelga rígido de la tibia— hereda ese
	# giro: eran los pies apuntando para adentro. `stance_width` queda como multiplicador encima.
	skelSizes.raycast_stance_offset = rig.foot_rest_x * leg_scale * inst.arch_final.stance_width
	skelSizes.shoulders_width = new_shoulders_width

	if entityStats.has_neck:
		var neck_radius := lerp_range(0.05, 0.12, entityStats.muscularity)
		skelSizes.neck_size = Vector3(neck_radius, new_head_height * entityStats.head_neck_ratio, neck_radius)
		skelSizes.head_size = Vector3(CONST_HEAD_RADIUS_XZ, new_head_height * (1.0 - entityStats.head_neck_ratio), CONST_HEAD_RADIUS_XZ * 0.75)
	else:
		skelSizes.neck_size = Vector3.ZERO
		skelSizes.head_size = Vector3(CONST_HEAD_RADIUS_XZ, new_head_height, CONST_HEAD_RADIUS_XZ * 0.85)

	var chest_u_radius : float = lerp_range(0.16, 0.45, entityStats.muscularity)
	var chest_l_radius : float = lerp_range(0.16, 0.45, entityStats.muscularity)
	skelSizes.chest_size = Vector3(chest_u_radius, new_torso_height * 0.3, chest_l_radius)

	var higher_spine_u_radius : float = lerp_range(0.1, 0.3, entityStats.fatness)
	var higher_spine_l_radius : float = lerp_range(0.1, 0.3, entityStats.fatness)
	skelSizes.higher_spine_size = Vector3(higher_spine_u_radius, new_torso_height * 0.25, higher_spine_l_radius)

	var middle_spine_u_radius : float = lerp_range(0.1, 0.55, entityStats.fatness)
	var middle_spine_l_radius : float = lerp_range(0.1, 0.5, entityStats.fatness)
	skelSizes.middle_spine_size = Vector3(middle_spine_u_radius, new_torso_height * 0.25, middle_spine_l_radius)

	var lower_spine_u_radius : float = lerp_range(0.1, 0.35, entityStats.fatness)
	var lower_spine_l_radius : float = lerp_range(0.1, 0.35, entityStats.fatness)
	skelSizes.lower_spine_size = Vector3(lower_spine_u_radius, new_torso_height * 0.2, lower_spine_l_radius)

	var shoulder_u_radius : float = lerp_range(0.08, 0.2, entityStats.muscularity)
	var shoulder_l_radius : float = lerp_range(0.08, 0.25, entityStats.muscularity)
	skelSizes.shoulder_width = Vector3(shoulder_u_radius, new_shoulders_width, shoulder_l_radius)

	var arm_total := new_arm_length
	var upper_arm_u_radius : float = lerp_range(0.06, 0.2, entityStats.muscularity)
	var upper_arm_l_radius : float = lerp_range(0.06, 0.23, entityStats.muscularity)
	skelSizes.upper_arm_size = Vector3(upper_arm_u_radius, arm_total * 0.45, upper_arm_l_radius)
	var lower_arm_u_radius : float = lerp_range(0.06, 0.13, entityStats.muscularity)
	var lower_arm_l_radius : float = lerp_range(0.06, 0.18, entityStats.muscularity)
	skelSizes.lower_arm_size = Vector3(lower_arm_u_radius, arm_total * 0.55, lower_arm_l_radius)

	var higher_leg_u_radius : float = lerp_range(0.06, 0.2, entityStats.fatness)
	var higher_leg_l_radius : float = lerp_range(0.06, 0.23, entityStats.fatness)
	skelSizes.higher_leg_size = Vector3(higher_leg_u_radius, new_leg_height * 0.45, higher_leg_l_radius)
	var lower_leg_u_radius : float = lerp_range(0.06, 0.2, entityStats.fatness)
	var lower_leg_l_radius : float = lerp_range(0.06, 0.23, entityStats.fatness)
	skelSizes.lower_leg_size = Vector3(lower_leg_u_radius, new_leg_height * 0.55, lower_leg_l_radius)
	skelSizes.foot_size = Vector3(0.1, new_leg_height * 0.2, 0.1)
	skelSizes.lower_feet_size = Vector3(0.1, new_leg_height * 0.02, 0.1)
	var hip_u_radius : float = lerp_range(0.1, 0.2, entityStats.fatness)
	var hip_l_radius : float = lerp_range(0.1, 0.2, entityStats.fatness)
	skelSizes.hip_size = Vector3(hip_u_radius, new_hips_width, hip_l_radius)

	# Largo de cada hueso: la cadena repartida en las proporciones del MODELO, leídas del rig. Va DESPUÉS del bloque que
	# arma los tamaños (que fija los radios) y ANTES de todo lo derivado (marcha, poles, targets de
	# reposo de brazos), que lee estos campos.
	# Los radios (.x/.z) NO se tocan: son la forma de la cápsula del CustomBone, que ya no se dibuja.
	# Hueso hoja = no estira malla, así que `foot_size` se queda con su fórmula derivada.
	skelSizes.lower_spine_size.y  = _share(rig, "lower_spine",  new_torso_height, rig.torso_chain)
	skelSizes.middle_spine_size.y = _share(rig, "middle_spine", new_torso_height, rig.torso_chain)
	skelSizes.higher_spine_size.y = _share(rig, "higher_spine", new_torso_height, rig.torso_chain)
	skelSizes.chest_size.y        = _share(rig, "chest",        new_torso_height, rig.torso_chain)
	skelSizes.neck_size.y         = rig.neck_len if entityStats.has_neck else 0.0
	skelSizes.head_size.y         = rig.head_len if entityStats.has_neck else new_head_height
	skelSizes.shoulder_width.y    = rig.shoulder_len
	skelSizes.upper_arm_size.y    = _share(rig, "left_upper_arm",  new_arm_length, rig.arm_chain)
	skelSizes.lower_arm_size.y    = _share(rig, "left_lower_arm",  new_arm_length, rig.arm_chain)
	skelSizes.hip_size.y          = rig.hip_len
	skelSizes.higher_leg_size.y   = _share(rig, "left_higher_leg", new_leg_height, rig.leg_chain)
	skelSizes.lower_leg_size.y    = _share(rig, "left_lower_leg",  new_leg_height, rig.leg_chain)

	skelSizes.raycast_leg_lenght = new_leg_height

	# ── Marcha: de la zancada deseada sale la altura de pelvis, y de ahí el alcance ───────────────
	# La cadena de la pierna (fémur 0.45 + tibia 0.55) mide exactamente new_leg_height. Con la cadera
	# INVERTIDO respecto de como era: antes se elegía la altura de pelvis y de ahí salía el alcance del
	# pie. Ahora se elige el alcance (la zancada) y la pelvis BAJA lo que haga falta, frame a frame,
	# midiendo si las piernas llegan (BoneInstantiator._update_pelvis_drop).
	#
	# Y la altura PARADO sale del modelo, no de una fracción del largo de pierna: en Blender la planta
	# está en 0, así que la Y del hueso raíz es literalmente a qué altura se para el personaje. Con eso
	# el reposo del juego coincide con Blender por construcción, incluida la flexión que hayas modelado
	# y el grosor de pie/zapato (que no se deduce del esqueleto, pero se mide porque el modelo apoya en
	# 0). Se escala con el largo de pierna para que un arquetipo de piernas cortas baje proporcional.
	#
	# Antes había además un margen de seguridad (STAND_EXTENSION) para que un pie en un escalón no
	# trabara la rodilla. Quedó redundante: la pelvis ya baja sola cuando las piernas no llegan, así que
	# el margen estático solo agachaba al personaje de gratis, siempre.
	# La pelvis parada se DERIVA, no se copia del modelo. Copiarla fue el error anterior: el modelo la
	# tiene a 0.8885 sobre una cadena de 0.863, o sea que la pierna no llegaba al piso ni estirada del
	# todo — el personaje flotaba y nunca daba un paso. Del modelo sale solo la altura de TOBILLO (el
	# grosor de pie/zapato, que ningún hueso puede decir), y encima va lo que la pierna alcanza.
	skelSizes.ankle_height = rig.ankle_rest_height * leg_scale
	skelSizes.standing_pelvis_height = skelSizes.ankle_height + new_leg_height * STAND_EXTENSION
	skelSizes.distance_from_ground = new_leg_height - skelSizes.standing_pelvis_height
	skelSizes.foot_reach = new_leg_height * lerp_range(FOOT_REACH_MIN, FOOT_REACH_MAX, inst.stride)
	skelSizes.current_duty = DUTY_WALK
	skelSizes.current_excursion = 0.0
	skelSizes.current_stride = 0.0

	skelSizes.step_height = new_leg_height * inst.step_height
	skelSizes.pole_distance = new_leg_height
	skelSizes.raycast_start_y_offset = new_leg_height * 0.35

	skelSizes.slouchiness_chest        = lerp_range(0.0, 0.6, entityStats.slouch)
	skelSizes.slouchiness_center_spine = lerp_range(0.0, 0.6, entityStats.slouch)
	skelSizes.slouchiness_neck         = lerp_range(0.2, 0.6, entityStats.slouch)

	skelSizes.arm_openness_angle   = lerp_range(0.0, -PI * 0.25, entityStats.arm_openness)
	skelSizes.arm_bentness         = entityStats.arm_bentness

	skelSizes.left_arm_tip_rest_local   = _compute_arm_tip_local(true,  skelSizes)
	skelSizes.right_arm_tip_rest_local  = _compute_arm_tip_local(false, skelSizes)
	skelSizes.left_arm_pole_rest_local  = _compute_arm_pole_local(true,  skelSizes)
	skelSizes.right_arm_pole_rest_local = _compute_arm_pole_local(false, skelSizes)

	skelSizes.left_arm_shoulder_rest_local  = _compute_arm_shoulder_local(true,  skelSizes)
	skelSizes.right_arm_shoulder_rest_local = _compute_arm_shoulder_local(false, skelSizes)

	return skelSizes


static func _compute_arm_shoulder_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var pos := Vector3.ZERO
	pos += Vector3(0, s.lower_spine_size.y, 0)
	var b := Basis.from_euler(Vector3(s.slouchiness_center_spine, 0, 0))
	pos += b * Vector3(0, s.middle_spine_size.y, 0)
	pos += Vector3(0, s.higher_spine_size.y, 0)
	b = Basis.from_euler(Vector3(-s.slouchiness_chest, 0, 0))
	pos += b * Vector3(0, s.chest_size.y, 0)
	if left:
		b = Basis.from_euler(Vector3(0, 0, deg_to_rad(90)))
	else:
		b = Basis.from_euler(Vector3(0, 0, deg_to_rad(-90)))
	pos += b * Vector3(0, s.shoulder_width.y, 0)
	return pos

static func _compute_arm_tip_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var shoulder := _compute_arm_shoulder_local(left, s)
	var arm_length := s.upper_arm_size.y + s.lower_arm_size.y \
		+ 0.4 * s.upper_arm_size.x \
		+ 0.4 * s.lower_arm_size.z
	var actual_distance: float = lerp(arm_length, 0.0, s.arm_bentness)
	var arm_dir := Basis(Vector3.FORWARD, s.arm_openness_angle * sign_x) * Vector3.DOWN
	return shoulder + arm_dir * actual_distance

static func _compute_arm_pole_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var shoulder := _compute_arm_shoulder_local(left, s)
	var arm_dir := Basis(Vector3.FORWARD, s.arm_openness_angle * sign_x) * Vector3.DOWN
	var elbow := shoulder + arm_dir * s.upper_arm_size.y

	var backward := Vector3(0, 0, 1)
	var outward  := Vector3(sign_x, 0, 0)
	var pole_dir: Vector3
	if ELBOW_POLE_DIRECTION >= 0.5:
		pole_dir = backward.lerp(outward,  (ELBOW_POLE_DIRECTION - 0.5) * 2.0).normalized()
	else:
		pole_dir = backward.lerp(-outward, (0.5 - ELBOW_POLE_DIRECTION) * 2.0).normalized()

	return elbow + pole_dir * s.upper_arm_size.y * 0.8 + Vector3(0, 0, 0.5)


func update(delta: float, inputs: AnimationInputs, inst: EntityInstantiation, ik_util: IkUtil) -> void:
	_update_gait(inputs, inst.arch_final)
	ik_util.advance_gait(delta, self, inputs)

## Excursión, duty y zancada de este frame, en función de la velocidad. La excursión crece con la
## velocidad (pasos más largos al correr) pero SIEMPRE acotada por foot_reach, que ya viene del
## alcance real de la pierna — así nunca se le pide al pie un punto al que la IK no llega. El duty
## baja de caminata a carrera: >0.5 hay doble apoyo, <0.5 hay fase de vuelo. La zancada (y con ella
## la cadencia) es consecuencia de los otros dos, no un parámetro.
func _update_gait(inputs: AnimationInputs, entity_stats: EntityArchetype) -> void:
	var instant_speed := Vector2(inputs.velocity.x, inputs.velocity.z).length()
	var max_speed: float = entity_stats.speed * entity_stats.sprint_multiplier * CharacterRigidBody3D.SPEED_SCALE
	var t: float = clamp(instant_speed / max(max_speed, 0.01), 0.0, 1.0)
	current_duty      = lerp_range(DUTY_WALK, DUTY_RUN, t)
	# √t, no un lerp con piso: la excursión tiene que llegar a CERO parado. Con un piso (antes 0.35)
	# el pie apuntaba a un objetivo adelantado incluso a velocidad ~0 — la dirección está normalizada,
	# así que a 0.001 m/s la colocación seguía siendo la excursión entera. El paso de asentamiento
	# apuntaba ahí, aterrizaba fuera de su propio umbral y volvía a dispararse: pasitos infinitos.
	# La raíz además sube rápido al arrancar, así que caminar despacio no queda en pasitos ínfimos
	# (con `t` lineal la cadencia sale constante; con √t crece con la velocidad, que es lo real).
	current_excursion = foot_reach * sqrt(t)
	current_stride    = 2.0 * current_excursion / max(current_duty, 0.05)

static func lerp_range(min_val: float, max_val: float, t: float) -> float:
	return min_val + (max_val - min_val) * clamp(t, 0.0, 1.0)

## Interpolación en DOS TRAMOS sobre tres valores autorales: 0.0 → 0.5 → 1.0.
##
## No es un lerp de dos puntos porque **el 0.5 no es el punto medio**: es el personaje genérico tal
## como fue esculpido, y los extremos se modelan a mano sin obligación de quedar simétricos. Esa
## asimetría ES el control artístico — con un lerp de dos extremos, el genérico saldría del promedio
## en vez de salir del modelo.
## Largo de una cadena: el esculpido es el 0.5, y los extremos son factores provisorios sobre él.
static func _chain(sculpted: float, t: float) -> float:
	return lerp_three(sculpted * LENGTH_MIN_FACTOR, sculpted, sculpted * LENGTH_MAX_FACTOR, t)

## Largo de UN hueso dentro de una cadena ya escalada: la cadena repartida en la misma proporción que
## tiene en el modelo. Se lee del rig en runtime por la misma razón que las cadenas — transcribirlo
## fue exactamente el bug: el muslo estaba al 0.4592 de la pierna cuando el modelo lo tiene al 0.3810,
## así que la rodilla quedaba 7 cm fuera de lugar y el pie no caía donde la IK lo mandaba.
static func _share(rig: ReferenceRig, field: String, chain: float, rig_chain: float) -> float:
	if rig_chain <= 0.0:
		return 0.0
	return chain * float(rig.lengths.get(field, 0.0)) / rig_chain

static func lerp_three(lo: float, mid: float, hi: float, t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	if c <= 0.5:
		return lo + (mid - lo) * (c * 2.0)
	return mid + (hi - mid) * ((c - 0.5) * 2.0)

## La inversa de lerp_three: dado un largo en metros, qué valor 0..1 lo produce. La usa el agarre
## para despejar "necesito un brazo de tanto, ¿qué arms_length es eso?" y clampear en 1.0.
static func inverse_lerp_three(lo: float, mid: float, hi: float, value: float) -> float:
	if value <= mid:
		if absf(mid - lo) < 0.0001:
			return 0.5
		return clampf(0.5 * (value - lo) / (mid - lo), 0.0, 1.0)
	if absf(hi - mid) < 0.0001:
		return 0.5
	return clampf(0.5 + 0.5 * (value - mid) / (hi - mid), 0.0, 1.0)
