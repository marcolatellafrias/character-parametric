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
var head_offset: Vector3
var neck_size: Vector3
var neck_offset: Vector3
var chest_size: Vector3
var chest_offset: Vector3
var upper_spine_size: Vector3
var upper_spine_offset: Vector3
var middle_spine_size: Vector3
var middle_spine_offset: Vector3
var lower_spine_size: Vector3 #this is the root
var lower_spine_offset: Vector3
var upper_leg_size: Vector3
var upper_leg_offset: Vector3
var lower_leg_size: Vector3
var lower_leg_offset: Vector3
var upper_feet_size: Vector3
var upper_feet_offset: Vector3
var lower_feet_size: Vector3
var lower_feet_offset: Vector3
var upper_arm_size: Vector3
var upper_arm_offset: Vector3
var lower_arm_size: Vector3
var lower_arm_offset: Vector3
var shoulder_width: Vector3
var shoulder_offset: Vector3
var hip_size: Vector3
var hip_offset: Vector3

#MISCELANEO: Argumentos de caminata, velocidad y iks, dependiendes de medidas
var speed : float
var distance_from_ground : float
var raycast_leg_lenght: float
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

const alpha := 1.1   # cuánto influye el tamaño de pierna (↑ piernas ⇒ ↑ duración). 1 = lineal (como ahora)
const beta := 1.0   # cuánto influye la velocidad (↑ vel ⇒ ↓ duración). 1 = lineal en la razón
var base_step_duration_ref: float = 0.3  # baseline (inspector-friendly)
var base_step_duration: float
var step_cooldown: float = 0.05

var _prev_origin: Vector3 = Vector3.INF
var _ema_speed: float = 0.0
const SPEED_TAU := 0.15 # s, suavizado (más chico = más reactivo)



static func create(entityStats: EntityStats) -> SkeletonSizesUtil:
	var skelSizes = SkeletonSizesUtil.new()
	#MEDIDAS DE MEDIANO NIVEL
	var total := entityStats.legs_to_feet_proportion + entityStats.chest_to_low_spine_proportion + entityStats.neck_to_head_proportion
	if total == 0.0:
		total = 1.0
	var leg_ratio := entityStats.legs_to_feet_proportion / total
	var torso_ratio := entityStats.chest_to_low_spine_proportion / total
	var head_ratio := entityStats.neck_to_head_proportion / total
	var new_leg_height := entityStats.height * leg_ratio
	var new_torso_height := entityStats.height * torso_ratio
	var new_head_height := entityStats.height * head_ratio
	var new_hips_width := entityStats.hips_width_proportion * entityStats.height
	var new_shoulders_width := entityStats.shoulder_width_proportion * entityStats.height
	skelSizes.leg_height = new_leg_height
	skelSizes.torso_height = new_torso_height
	skelSizes.head_height = new_head_height
	skelSizes.hips_width = new_hips_width
	skelSizes.shoulders_width = new_shoulders_width
	#TAMAÑO DE HUESOS
	if entityStats.has_neck:
		skelSizes.neck_size = Vector3(0.1, new_head_height * 0.4, 0.1)
		skelSizes.head_size = Vector3(0.2, new_head_height * 0.6, 0.2)
	else:
		skelSizes.neck_size = Vector3.ZERO
		skelSizes.head_size = Vector3(0.2, new_head_height, 0.2)
	skelSizes.head_offset = Vector3(0.6, 1.0,-0.8)
		
	#PARA VISUALES CAMBIAR ESTO
	skelSizes.lower_spine_size = Vector3(0.1, new_torso_height * 0.1, 0.1)
	
	var upper_belly_radius : float = lerp_range(0.1,0.7,entityStats.fatness)
	var lower_belly_radius : float = lerp_range(0.1,0.5,entityStats.fatness)	
	skelSizes.middle_spine_size = Vector3(upper_belly_radius, new_torso_height * 0.2, lower_belly_radius)
	
	skelSizes.upper_spine_size = Vector3(0.1, new_torso_height * 0.3, 0.1)
	skelSizes.chest_size = Vector3(0.2, new_torso_height * 0.4, 0.2)
	
	var upper_shoulder_radius : float = lerp_range(0.08,0.2,entityStats.muscularity)
	var lower_shoulder_radius : float = lerp_range(0.08,0.25,entityStats.muscularity)	
	skelSizes.shoulder_width = Vector3( upper_shoulder_radius, new_shoulders_width, lower_shoulder_radius)
	var arm_total := entityStats.reach
	var upper_arm_u_radius : float = lerp_range(0.06,0.2,entityStats.muscularity)
	var upper_arm_l_radius : float = lerp_range(0.06,0.23, entityStats.muscularity)	
	skelSizes.upper_arm_size = Vector3(upper_arm_u_radius, arm_total * 0.45, upper_arm_l_radius)
	skelSizes.upper_arm_offset = Vector3(0.0, 1.0,0.0)
	skelSizes.lower_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	skelSizes.upper_leg_size = Vector3(0.1, new_leg_height * 0.45, 0.1)
	skelSizes.lower_leg_size = Vector3(0.1, new_leg_height * 0.55, 0.1)
	
	
	skelSizes.upper_feet_size = Vector3(0.1, new_leg_height * 0.2, 0.1)
	skelSizes.lower_feet_size = Vector3(0.1, new_leg_height * 0.02, 0.1)

	skelSizes.hip_size = Vector3( 0.1, new_hips_width, 0.1)

	
	
	
	#TAMAÑOS MISCELANEOS
	skelSizes.raycast_leg_lenght = new_leg_height
	skelSizes.distance_from_ground = new_leg_height * (1-entityStats.distance_from_ground_factor)
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

	var ema_alpha := 1.0 - exp(-delta / SPEED_TAU) # renamed to avoid shadowing
	_ema_speed += (instant_speed - _ema_speed) * ema_alpha

	var clamped_speed_ref : float = max(0.001, self.speed_ref) # use class const
	var speed_term := pow(1.0 + (_ema_speed / clamped_speed_ref), self.beta) # use class const

	var base : float = max(0.001, base_step_duration)
	step_duration = base * speed_term

	_prev_origin = origin


static func lerp_range(min_val: float, max_val: float, t: float) -> float:
	return min_val + (max_val - min_val) * clamp(t, 0.0, 1.0)
