class_name SkeletonSizesUtil #La funcion de esta clase, es convertir valores de alta abstraccion en medidas
#concretas, desde proporciones, gordura, altura, etc. a medidas concretas de los huesos y musculos, son todas
#medidas fijas que no cambian, para medidas dinamicas, mirar dynamic sizes util (tamaño de pasos, etc)

#Medidas de mediano nivel
var leg_height : float
var torso_height : float
var head_height : float
var hips_width : float
var shoulders_width : float

#Tamaños de huesos
var head_size: Vector3
var neck_size: Vector3
var chest_size: Vector3
var upper_spine_size: Vector3
var middle_spine_size: Vector3
var lower_spine_size: Vector3 #this is the root
var upper_leg_size: Vector3
var lower_leg_size: Vector3
var upper_feet_size: Vector3
var lower_feet_size: Vector3
var upper_arm_size: Vector3
var lower_arm_size: Vector3
var shoulder_width: Vector3
var hip_size: Vector3

#MISCELANEO: Argumentos de caminata, velocidad y iks, dependiendes de medidas
var distance_from_ground : float
var raycast_leg_lenght: float
var speed: float
var step_radius_turn: float
var step_radius_walk: float
var step_height: float
var pole_distance: float
var raycast_max_offset: float
var step_duration : float      # how fast the foot travels toward its new spot
var raycast_amount := 4.0        # 0 = no se mueve, 1 = normal, >1 = amplifica
var speed_for_max := 6.0          # velocidad a la que llega al offset máximo
var axis_weights := Vector2(1.0, 1.0)                    # x (lateral), z (adelante) para atenuar por eje
var speed_curve: Curve     
const raycast_accel_gain := 0.06        # meters per (m/s^2)
const raycast_vel_gain   := 0.02        # meters per (m/s)  -> keeps offset while moving
const raycast_smooth     := 8.0        # 1/sec; higher = snappier
const leg_ref := 1.0     # altura de pierna "promedio" (tus unidades)
const speed_ref := 3.0     # vel. a la que querés que la duración se reduzca ~a la mitad si BETA=1
const alpha := 1.2   # cuánto influye el tamaño de pierna (↑ piernas ⇒ ↑ duración). 1 = lineal (como ahora)
const beta := 0.6   # cuánto influye la velocidad (↑ vel ⇒ ↓ duración). 1 = lineal en la razón
var base_step_duration_ref: float = 0.3  # baseline (inspector-friendly)
var base_step_duration: float
var step_cooldown: float = 0.05

var _prev_origin: Vector3 = Vector3.INF
var _ema_speed: float = 0.0
const SPEED_TAU := 0.15 # s, suavizado (más chico = más reactivo)



static func create(skel: BoneInstantiator) -> SkeletonSizesUtil:
	var skelSizes = SkeletonSizesUtil.new()
	#MEDIDAS DE MEDIANO NIVEL
	var total := skel.legs_to_feet_proportion + skel.chest_to_low_spine_proportion + skel.neck_to_head_proportion
	if total == 0.0:
		total = 1.0
	var leg_ratio := skel.legs_to_feet_proportion / total
	var torso_ratio := skel.chest_to_low_spine_proportion / total
	var head_ratio := skel.neck_to_head_proportion / total
	var new_leg_height := skel.feet_to_head_height * leg_ratio
	var new_torso_height := skel.feet_to_head_height * torso_ratio
	var new_head_height := skel.feet_to_head_height * head_ratio
	var new_hips_width := skel.hips_width_proportion * skel.feet_to_head_height
	var new_shoulders_width := skel.shoulder_width_proportion * skel.feet_to_head_height
	skelSizes.leg_height = new_leg_height
	skelSizes.torso_height = new_torso_height
	skelSizes.head_height = new_head_height
	skelSizes.hips_width = new_hips_width
	skelSizes.shoulders_width = new_shoulders_width
	#TAMAÑO DE HUESOS
	if skel.has_neck:
		skelSizes.neck_size = Vector3(0.1, new_head_height * 0.4, 0.1)
		skelSizes.head_size = Vector3(0.3, new_head_height * 0.6, 0.3)
	else:
		skelSizes.neck_size = Vector3.ZERO
		skelSizes.head_size = Vector3(0.3, new_head_height, 0.3)
	skelSizes.lower_spine_size = Vector3(0.1, new_torso_height * 0.1, 0.1)
	skelSizes.middle_spine_size = Vector3(0.1, new_torso_height * 0.2, 0.1)
	skelSizes.upper_spine_size = Vector3(0.1, new_torso_height * 0.3, 0.1)
	skelSizes.chest_size = Vector3(0.2, new_torso_height * 0.4, 0.2)
	skelSizes.upper_leg_size = Vector3(0.1, new_leg_height * 0.45, 0.1)
	skelSizes.lower_leg_size = Vector3(0.1, new_leg_height * 0.55, 0.1)
	skelSizes.upper_feet_size = Vector3(0.1, new_leg_height * 0.2, 0.1)
	skelSizes.lower_feet_size = Vector3(0.1, new_leg_height * 0.02, 0.1)
	var arm_total := new_leg_height *0.5#torso_height * arms_proportion
	skelSizes.upper_arm_size = Vector3(0.1, arm_total * 0.45, 0.1)
	skelSizes.lower_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	skelSizes.hip_size = Vector3( 0.1, new_hips_width, 0.1)
	skelSizes.shoulder_width = Vector3( 0.1, new_shoulders_width, 0.1)
	#TAMAÑOS MISCELANEOS
	skelSizes.raycast_leg_lenght = new_leg_height
	skelSizes.distance_from_ground = new_leg_height * (1-skel.distance_from_ground_factor)
	skelSizes.speed = new_leg_height * 1.8
	skelSizes.step_radius_walk   = new_leg_height * 0.5
	skelSizes.step_radius_turn   = new_leg_height * 0.20
	skelSizes.step_height = new_leg_height * 0.40
	skelSizes.pole_distance = new_leg_height
	skelSizes.raycast_max_offset = new_leg_height * 0.20
	# --- duración base del paso (SIN velocidad) ---
	# Guardamos una referencia inmutable del valor "de fábrica" (para leg_ref)
	# la primera vez que se llama, para no re-escalarla en cada cambio.
	var bsd_ref: float
	if skelSizes.has_meta("bsd_ref"):
		bsd_ref = float(skelSizes.get_meta("bsd_ref"))
	else:
		# Asumimos que skel.base_step_duration contiene el valor de referencia (p.ej. 0.2s) para leg_ref
		bsd_ref = float(skelSizes.base_step_duration)
		skelSizes.set_meta("bsd_ref", bsd_ref)

	var leg_term: float = pow(new_leg_height / skelSizes.leg_ref, skelSizes.alpha)
	skelSizes.base_step_duration = bsd_ref * leg_term
	skelSizes.step_duration = skelSizes.base_step_duration
	return skelSizes


func update(delta: float, char_rigidbody: CharacterRigidBody3D) -> void:
	_update_step_duration(delta,char_rigidbody)

func _update_step_duration(delta: float, char_rigidbody: CharacterRigidBody3D) -> void:
	var node := char_rigidbody
	var origin: Vector3 = node.global_transform.origin

	if _prev_origin == Vector3.INF:
		_prev_origin = origin
		step_duration = max(0.001, base_step_duration)
		return

	var dxz := Vector2(origin.x - _prev_origin.x, origin.z - _prev_origin.z)
	var instant_speed: float = dxz.length() / max(delta, 0.0001)

	var sprint_mult := 1.0
	var _sm = node.get("sprint_multiplier") # Object.get() always exists; returns null if no prop
	if typeof(_sm) == TYPE_FLOAT or typeof(_sm) == TYPE_INT:
		sprint_mult = max(1.0, float(_sm))

	var effective_speed: float = instant_speed * sprint_mult

	var ema_alpha := 1.0 - exp(-delta / SPEED_TAU) # renamed to avoid shadowing
	_ema_speed += (effective_speed - _ema_speed) * ema_alpha

	var clamped_speed_ref : float = max(0.001, self.speed_ref) # use class const
	var speed_term := pow(1.0 + (_ema_speed / clamped_speed_ref), self.beta) # use class const

	var base : float = max(0.001, base_step_duration)
	step_duration = base / speed_term

	_prev_origin = origin
