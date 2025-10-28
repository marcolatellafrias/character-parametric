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

var step_radius_min: float
var step_radius_max: float
var step_height: float


var distance_from_ground : float
var raycast_leg_lenght: float
var pole_distance: float
var raycast_max_offset: float
var raycast_amount := 10.0        # 0 = no se mueve, 1 = normal, >1 = amplifica
var speed_for_max := 6.0          # velocidad a la que llega al offset máximo
var axis_weights := Vector2(1.0, 1.0)                    # x (lateral), z (adelante) para atenuar por eje
var speed_curve: Curve     
const raycast_accel_gain := 0.06        # meters per (m/s^2)
const raycast_vel_gain   := 0.02        # meters per (m/s)  -> keeps offset while moving
const raycast_smooth     := 8.0        # 1/sec; higher = snappier


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
		skelSizes.head_size = Vector3(0.2, new_head_height * 0.6, 0.15)
	else:
		skelSizes.neck_size = Vector3.ZERO
		skelSizes.head_size = Vector3(0.2, new_head_height, 0.2)
	skelSizes.head_offset = Vector3(0.8, 1.0,-0.8)
		
	#TORSO-------------------------------------------------------------------------
	var chest_u_radius : float = lerp_range(0.08, 0.45, entityStats.muscularity)
	var chest_l_radius : float = lerp_range(0.08, 0.45, entityStats.muscularity)
	var chest_new_offset : float = lerp_range( 0.0, -0.35, entityStats.muscularity)
	skelSizes.chest_offset = Vector3(0.4, 0.4, chest_new_offset)
	skelSizes.chest_size = Vector3(chest_u_radius, new_torso_height * 0.25, chest_l_radius)
	
	var upper_spine_u_radius : float = lerp_range(0.1,0.3,entityStats.fatness)
	var upper_spine_l_radius : float = lerp_range(0.1,0.3,entityStats.fatness)
	var upper_spine_new_offset : float = lerp_range (0.0, -0.55, entityStats.fatness)
	skelSizes.upper_spine_size = Vector3(upper_spine_u_radius, new_torso_height * 0.25, upper_spine_l_radius) 
	skelSizes.upper_spine_offset = Vector3(0.0, 0.0, upper_spine_new_offset)
	
	var middle_spine_u_radius : float = lerp_range(0.1,0.45,entityStats.fatness)
	var middle_spine_l_radius : float = lerp_range(0.1,0.45,entityStats.fatness)
	var middle_spine_new_offset : float = lerp_range( 0.0, -0.55, entityStats.fatness)
	skelSizes.middle_spine_size = Vector3(middle_spine_u_radius, new_torso_height * 0.25, middle_spine_l_radius)
	skelSizes.middle_spine_offset = Vector3(0.0, 0.0, middle_spine_new_offset)
	
	var lower_spine_u_radius : float = lerp_range(0.1,0.1,entityStats.fatness)
	var lower_spine_l_radius : float = lerp_range(0.1,0.1,entityStats.fatness)
	var lower_spine_new_offset : float = lerp_range( 0.0, -0.55, entityStats.fatness)
	skelSizes.lower_spine_size = Vector3(lower_spine_u_radius, new_torso_height * 0.25, lower_spine_l_radius)
	skelSizes.lower_spine_offset = Vector3(0.0, 0.0, lower_spine_new_offset)
	
	#HOMBROS-------------------------------------------------------------------------
	var shoulder_u_radius : float = lerp_range(0.08,0.2,entityStats.muscularity)
	var shoulder_l_radius : float = lerp_range(0.08,0.25,entityStats.muscularity)	
	skelSizes.shoulder_width = Vector3(shoulder_u_radius, new_shoulders_width, shoulder_l_radius)
	
	#BRAZOS-------------------------------------------------------------------------
	var arm_total := entityStats.reach
	var upper_arm_u_radius : float = lerp_range(0.06,0.2,entityStats.muscularity)
	var upper_arm_l_radius : float = lerp_range(0.06,0.23, entityStats.muscularity)	
	skelSizes.upper_arm_size = Vector3(upper_arm_u_radius, arm_total * 0.45, upper_arm_l_radius)
	skelSizes.upper_arm_offset = Vector3(1.0, 1.0,0.0)
	var lower_arm_u_radius : float = lerp_range(0.06,0.13,entityStats.muscularity)
	var lower_arm_l_radius : float = lerp_range(0.06,0.18, entityStats.muscularity)	
	skelSizes.lower_arm_size = Vector3(lower_arm_u_radius, arm_total * 0.55, lower_arm_l_radius)
	skelSizes.lower_arm_offset = Vector3(0.0, 1.0,0.0)
	
	#PIERNAS-------------------------------------------------------------------------
	var upper_leg_u_radius : float = lerp_range(0.06,0.2,entityStats.fatness)
	var upper_leg_l_radius : float = lerp_range(0.06,0.23, entityStats.fatness)	
	skelSizes.upper_leg_size = Vector3(upper_leg_u_radius, new_leg_height * 0.45, upper_leg_l_radius)
	skelSizes.upper_leg_offset = Vector3(1.0, 0.0,0.0)
	
	var lower_leg_u_radius : float = lerp_range(0.06,0.2,entityStats.fatness)
	var lower_leg_l_radius : float = lerp_range(0.06,0.23, entityStats.fatness)	
	skelSizes.lower_leg_size = Vector3(lower_leg_u_radius, new_leg_height * 0.55, lower_leg_l_radius)
	skelSizes.lower_leg_offset = Vector3(1.0, 1.0,0.0)
	
	skelSizes.upper_feet_size = Vector3(0.1, new_leg_height * 0.2, 0.1)
	skelSizes.lower_feet_size = Vector3(0.1, new_leg_height * 0.02, 0.1)

	
	skelSizes.hip_size = Vector3( 0.1, new_hips_width, 0.1)
	skelSizes.hip_offset = Vector3(1.0, 1.0,0.0)
	
	
	#TAMAÑOS MISCELANEOS
	skelSizes.raycast_leg_lenght = new_leg_height
	skelSizes.distance_from_ground = new_leg_height * (1-entityStats.distance_from_ground_factor)
	skelSizes.step_radius_max   = new_leg_height * 0.5
	skelSizes.step_radius_min   = new_leg_height * 0.20
	skelSizes.step_height = new_leg_height * 0.40
	skelSizes.pole_distance = new_leg_height
	skelSizes.raycast_max_offset = new_leg_height * 0.20
	return skelSizes


func update(delta: float, char_rigidbody: CharacterRigidBody3D, entityStats: EntityStats, ik_util: IkUtil) -> void:
	_update_step_radius(char_rigidbody,entityStats,ik_util)

func _update_step_radius(char_rigidbody: CharacterRigidBody3D, entity_stats: EntityStats, ik_util: IkUtil) -> void:
	var dxz := Vector2(char_rigidbody.linear_velocity.x, char_rigidbody.linear_velocity.z)
	var instant_speed = dxz.length()
	
	# Velocidades
	var min_speed = 0.01
	var max_speed = entity_stats.speed_forw /3#entity_stats.speed_multiplier
	 
	# Interpolación segura
	var speed_range = max(max_speed - min_speed, 0.01)
	var t = clamp((instant_speed - min_speed) / speed_range, 0.0, 1.0)
	
	# Aplicar con smoothstep para transiciones naturales
	var t_smooth = smoothstep(0.0, 1.0, t)  # GDScript tiene smoothstep built-in
	ik_util.current_step_radius = lerp(step_radius_min , step_radius_max, t)

static func lerp_range(min_val: float, max_val: float, t: float) -> float:
	return min_val + (max_val - min_val) * clamp(t, 0.0, 1.0)
