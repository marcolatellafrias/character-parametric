class_name BoneInstantiator
extends Node3D

#ALTURA DEL PERSONAJE
@export var feet_to_head_height := 3.2: #This excludes arms and horizontal bones,
	set(value):
		feet_to_head_height = value
		initialize_skeleton()
#PROPORCIONES/INTERFAZ
@export var neck_to_head_proportion := 0.15:
	set(value):
		neck_to_head_proportion = value
		initialize_skeleton()
@export var chest_to_low_spine_proportion := 0.15:
	set(value):
		chest_to_low_spine_proportion = value
		initialize_skeleton()
@export var legs_to_feet_proportion := 0.7:
	set(value):
		legs_to_feet_proportion = value
		initialize_skeleton()
@export var hips_width_proportion := 0.11:
	set(value):
		hips_width_proportion = value
		initialize_skeleton()	
@export var shoulder_width_proportion := 0.2:
	set(value):
		shoulder_width_proportion = value
		initialize_skeleton()
@export var arms_proportion := 0.7:
	set(value):
		arms_proportion = value
		initialize_skeleton()
@export var has_neck := true:
	set(value):
		has_neck = value
		initialize_skeleton()

#PARAMETROS DE CAMINATA
const distance_from_ground_factor := 0.1  #tiene las piernas 10% flexionadas cuando esta en el piso
var distance_from_ground: float
var step_radius_walk : float
var step_radius_turn : float
var step_duration : float      # how fast the foot travels toward its new spot
var base_step_duration: float = 0.3
var step_height : float     # how high the foot lifts during the step
var raycast_amount := 4.0        # 0 = no se mueve, 1 = normal, >1 = amplifica
var speed_for_max := 6.0          # velocidad a la que llega al offset máximo
var axis_weights := Vector2(1.0, 1.0)                    # x (lateral), z (adelante) para atenuar por eje
var speed_curve: Curve     
var raycast_max_offset : float        # meters; "up to a point"
const raycast_accel_gain := 0.06        # meters per (m/s^2)
const raycast_vel_gain   := 0.02        # meters per (m/s)  -> keeps offset while moving
const raycast_smooth     := 8.0        # 1/sec; higher = snappier
var raycast_offset: Vector2 = Vector2.ZERO     # smoothed current offset (x,z)
var left_neutral_local: Vector3
var right_neutral_local: Vector3
const leg_ref := 1.0     # altura de pierna "promedio" (tus unidades)
const speed_ref := 3.0     # vel. a la que querés que la duración se reduzca ~a la mitad si BETA=1
const alpha := 1.2   # cuánto influye el tamaño de pierna (↑ piernas ⇒ ↑ duración). 1 = lineal (como ahora)
const beta := 0.6   # cuánto influye la velocidad (↑ vel ⇒ ↓ duración). 1 = lineal en la razón
var dynamic_sizes_util : DynamicSizesUtil

#IK variables
@onready var ik_targets := $"../../ik_targets"
var pole_distance: float
var left_color: Color = Color(1, 0, 0)      # rojo
var right_color: Color = Color(0, 1, 0)    # verde
var raycast_color: Color = Color(0, 0, 1)    # verde
var raycast_leg_lenght: float #la distancia del raycast desde la altura del rootbone
var left_leg_pole: Node3D
var right_leg_pole: Node3D
var left_leg_next_target: Node3D
var right_leg_next_target: Node3D
var left_leg_current_target: Node3D
var right_leg_current_target: Node3D
var left_leg_raycast: RayCast3D
var right_leg_raycast: RayCast3D

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
var hip_width: Vector3
var stable_sizes_util: StableSizesUtil

# Huesos
var lower_spine : CustomBone
var middle_spine : CustomBone
var upper_spine : CustomBone
var chest : CustomBone
var left_hip : CustomBone
var right_hip : CustomBone
var left_upper_leg : CustomBone
var left_lower_leg : CustomBone
var right_upper_leg : CustomBone
var right_lower_leg : CustomBone
var right_upper_feet : CustomBone
var left_upper_feet : CustomBone
var neck : CustomBone
var head : CustomBone
var left_shoulder : CustomBone
var right_shoulder : CustomBone
var right_upper_arm : CustomBone
var right_lower_arm : CustomBone
var left_upper_arm : CustomBone
var left_lower_arm : CustomBone

@onready var character_controller : CustomCharacterBody = $"../../player_controller"
@onready var collision_shape : CollisionShape3D = $"../CollisionShape3D"
var previous_transform : Transform3D 

func _ready() -> void:
	initialize_skeleton()

func update_sizes() -> void:
	# Evitar división por cero
	var total := legs_to_feet_proportion + chest_to_low_spine_proportion + neck_to_head_proportion
	if total == 0.0:
		total = 1.0
	# Calcular proporciones relativas
	var leg_ratio := legs_to_feet_proportion / total
	var torso_ratio := chest_to_low_spine_proportion / total
	var head_ratio := neck_to_head_proportion / total
	# Calcular alturas absolutas
	var leg_height := feet_to_head_height * leg_ratio
	var torso_height := feet_to_head_height * torso_ratio
	var head_height := feet_to_head_height * head_ratio
	var hips_width := hips_width_proportion * feet_to_head_height
	var shoulders_width := shoulder_width_proportion * feet_to_head_height
	# Primero calculo los tamaños estables
	stable_sizes_util = StableSizesUtil.create(self,leg_height,torso_height,head_height,hips_width,shoulders_width)
	stable_sizes_util.set_sizes()
	# Luego calculo los tamaños dinamicos
	dynamic_sizes_util = DynamicSizesUtil.create(self,leg_height)
	dynamic_sizes_util.set_base()

func initialize_skeleton() -> void:
	for bone in get_children():
		bone.queue_free()
	for target in ik_targets.get_children():
		target.queue_free()

	update_sizes()

	# Hueso raíz
	lower_spine = CustomBone.create(lower_spine_size, Vector3.ZERO, Color.WHITE_SMOKE)
	add_child(lower_spine)

	# Chest and spine
	middle_spine = CustomBone.createFromToUp(lower_spine, middle_spine_size, 0.0,0.0, Color.SKY_BLUE, true)
	upper_spine = CustomBone.createFromToUp(middle_spine, upper_spine_size, 0.0,0.0, Color.BURLYWOOD , true)
	chest = CustomBone.createFromToUp(upper_spine, chest_size, 0.0,0.0, Color.BURLYWOOD , true)
	left_hip = CustomBone.createFromToLeft(lower_spine, hip_width, 0.0,0.0, Color.ROYAL_BLUE , false)
	right_hip = CustomBone.createFromToRight(lower_spine, hip_width, 0.0,0.0, Color.ROYAL_BLUE , false)

	# Legs
	left_upper_leg = CustomBone.createFromToDown(left_hip, upper_leg_size, 0.0,0.0, Color.YELLOW , true)
	left_lower_leg = CustomBone.createFromToDown(left_upper_leg, lower_leg_size, 0.0,0.0, Color.ORANGE , true)
	right_upper_leg = CustomBone.createFromToDown(right_hip, upper_leg_size, 0.0,0.0, Color.YELLOW , true)
	right_lower_leg = CustomBone.createFromToDown(right_upper_leg, lower_leg_size, 0.0,0.0, Color.ORANGE , true)
	right_upper_feet = CustomBone.createFromToForward(right_lower_leg, upper_feet_size, 0.0,0.0, Color.ORANGE , true)
	left_upper_feet = CustomBone.createFromToForward(left_lower_leg, upper_feet_size, 0.0,0.0, Color.ORANGE , true)
	
	# Head
	if has_neck:
		neck = CustomBone.createFromToUp(chest, neck_size, 0.0,0.0, Color.RED , true)
	head = CustomBone.createFromToUp(neck if neck else chest, head_size, 0.0,0.0, Color.GREEN , true)
	
	# Shoulders
	left_shoulder = CustomBone.createFromToLeft(chest, shoulder_width, 0.0,0.3, Color.CHOCOLATE , true)
	right_shoulder = CustomBone.createFromToRight(chest, shoulder_width, 0.0,-0.3, Color.GREEN , true)

	# Arms
	right_upper_arm = CustomBone.createFromToDown(right_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	right_lower_arm = CustomBone.createFromToDown(right_upper_arm, lower_arm_size, 0.0,0.5, Color.RED , true)
	left_upper_arm = CustomBone.createFromToDown(left_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	left_lower_arm = CustomBone.createFromToDown(left_upper_arm, lower_arm_size, 0.0,0.5, Color.RED , true)
	
	create_ik_controls()
	self.position = Vector3.ZERO
	
func create_ik_controls() -> void:
	#Agrego cosas q se mueven con el pj, como hijos
	left_leg_raycast = IkUtil.create_leg_raycast(-hip_width.y, raycast_color, raycast_leg_lenght)
	right_leg_raycast = IkUtil.create_leg_raycast(hip_width.y, raycast_color, raycast_leg_lenght)
	add_child(left_leg_raycast)
	add_child(right_leg_raycast)
	left_leg_pole = IkUtil.create_pole(left_lower_leg, pole_distance, left_color,self)
	right_leg_pole = IkUtil.create_pole(right_lower_leg, pole_distance, right_color,self)
	#poles are added in function, because it needs access to global transforms
	left_leg_next_target = IkUtil.create_next_target(-hip_width.y, left_color, raycast_leg_lenght)
	right_leg_next_target = IkUtil.create_next_target(hip_width.y, right_color, raycast_leg_lenght)
	add_child(left_leg_next_target)
	add_child(right_leg_next_target)
	
	left_neutral_local  = left_leg_raycast.transform.origin
	right_neutral_local  = right_leg_raycast.transform.origin
	
	#Agrego cosas q se mueven con el mundo, en ik_targets
	left_leg_current_target = IkUtil.create_ik_target(left_color, step_radius_walk, step_radius_turn)
	right_leg_current_target = IkUtil.create_ik_target(right_color, step_radius_walk, step_radius_turn)
	ik_targets.add_child(left_leg_current_target)
	ik_targets.add_child(right_leg_current_target)

func _physics_process(_delta: float) -> void:
	dynamic_sizes_util.update(_delta)
	
	var isTranslating := false
	if character_controller:
		previous_transform = character_controller.transform
		
	raycast_offset = IkUtil.update_leg_raycast_offsets(character_controller, _delta, left_leg_raycast, speed_for_max, speed_curve, raycast_amount, raycast_max_offset, axis_weights, raycast_smooth, left_neutral_local, raycast_offset) 
	raycast_offset = IkUtil.update_leg_raycast_offsets(character_controller, _delta, right_leg_raycast, speed_for_max, speed_curve, raycast_amount, raycast_max_offset, axis_weights, raycast_smooth, right_neutral_local, raycast_offset) 
	
	left_leg_current_target = IkUtil.update_ik_raycast(
		left_leg_raycast, left_leg_next_target, left_leg_current_target,
		left_upper_leg, left_lower_leg, left_leg_pole,
		right_leg_current_target,  # la pierna opuesta
		step_radius_walk, step_height, step_duration,
	)
	right_leg_current_target = IkUtil.update_ik_raycast(
		right_leg_raycast, right_leg_next_target, right_leg_current_target,
		right_upper_leg, right_lower_leg, right_leg_pole,
		left_leg_current_target,   # la pierna opuesta
		step_radius_walk, step_height, step_duration,
	)
