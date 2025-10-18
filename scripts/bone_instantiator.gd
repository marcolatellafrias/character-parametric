extends Node3D

#ALTURA DEL PERSONAJE
@export var feet_to_head_height := 1.8: #This excludes arms and horizontal bones,
	set(value):
		feet_to_head_height = value
		initialize_skeleton()

#PROPORCIONES/INTERFAZ
@export var neck_to_head_proportion := 0.2:
	set(value):
		neck_to_head_proportion = value
		initialize_skeleton()
@export var chest_to_low_spine_proportion := 0.3:
	set(value):
		chest_to_low_spine_proportion = value
		initialize_skeleton()
@export var legs_to_feet_proportion := 0.5:
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
var step_radius_walk := 0.32
var step_radius_turn := 0.2
@export var distance_from_ground_factor := 0.1 #10% del tamaño de sus piernas desde el suelo
var distance_from_ground: float
# Adjustable step settings
const STEP_SPEED_MPS  := 6.0      # how fast the foot travels toward its new spot
const STEP_HEIGHT     := 0.4     # how high the foot lifts during the step

#IK variables
@onready var ik_targets := $"../../ik_targets"
var pole_distance: float = 0.8
var target_height: float = -2.0
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

@onready var character_controller := $"../../player_controller"
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

	# --------- PIERNAS ---------
	upper_leg_size = Vector3(0.1, leg_height * 0.45, 0.1)
	lower_leg_size = Vector3(0.1, leg_height * 0.55, 0.1)

	# Separar el pie de la pierna
	upper_feet_size = Vector3(0.1, leg_height * 0.2, 0.1)
	lower_feet_size = Vector3(0.1, leg_height * 0.02, 0.1)

	# --------- TORSO ---------
	# Proporciones ajustadas internamente para coherencia anatómica
	lower_spine_size = Vector3(0.1, torso_height * 0.1, 0.1)
	middle_spine_size = Vector3(0.1, torso_height * 0.2, 0.1)
	upper_spine_size = Vector3(0.1, torso_height * 0.3, 0.1)
	chest_size = Vector3(0.2, torso_height * 0.4, 0.2)

	# Anchuras laterales
	hip_width = Vector3( 0.1,hips_width_proportion * feet_to_head_height, 0.1)
	shoulder_width = Vector3( 0.1,shoulder_width_proportion * feet_to_head_height, 0.1)

	# --------- CABEZA Y CUELLO ---------
	if has_neck:
		neck_size = Vector3(0.1, head_height * 0.4, 0.1)
		head_size = Vector3(0.3, head_height * 0.6, 0.3)
	else:
		neck_size = Vector3.ZERO
		head_size = Vector3(0.3, head_height, 0.3)

	# --------- BRAZOS ---------
	var arm_total := leg_height #torso_height * arms_proportion
	upper_arm_size = Vector3(0.1, arm_total * 0.45, 0.1)
	lower_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	raycast_leg_lenght = leg_height
	distance_from_ground = leg_height * (distance_from_ground_factor)
	if collision_shape is CollisionShape3D:
		if collision_shape.shape is CapsuleShape3D:
			var radius :=  hip_width.y * 2
			var height := feet_to_head_height
			var y_offset :=  leg_height - (leg_height - distance_from_ground)
			collision_shape.shape.height = height
			collision_shape.shape.radius = radius
			collision_shape.position = (Vector3(0, y_offset ,0))
			character_controller.add_child.call_deferred(DebugUtil.create_debug_capsule(radius,  height, y_offset))
			print("added capsule debug")

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
	
func create_ik_controls() -> void:
	#Agrego cosas q se mueven con el pj, como hijos
	left_leg_raycast = IkUtil.create_leg_raycast(-hip_width.y, raycast_color, raycast_leg_lenght)
	right_leg_raycast = IkUtil.create_leg_raycast(hip_width.y, raycast_color, raycast_leg_lenght)
	add_child(left_leg_raycast)
	add_child(right_leg_raycast)
	left_leg_pole = IkUtil.create_pole(left_lower_leg, pole_distance, left_color,self)
	right_leg_pole = IkUtil.create_pole(right_lower_leg, pole_distance, right_color,self)
	add_child(left_leg_pole)
	add_child(right_leg_pole)
	left_leg_next_target = IkUtil.create_next_target(-hip_width.y, left_color, raycast_leg_lenght)
	right_leg_next_target = IkUtil.create_next_target(hip_width.y, right_color, raycast_leg_lenght)
	add_child(left_leg_next_target)
	add_child(right_leg_next_target)
	
	#Agrego cosas q se mueven con el mundo, en ik_targets
	left_leg_current_target = IkUtil.create_ik_target(left_color, step_radius_walk, step_radius_turn)
	right_leg_current_target = IkUtil.create_ik_target(right_color, step_radius_walk, step_radius_turn)
	ik_targets.add_child(left_leg_current_target)
	ik_targets.add_child(right_leg_current_target)

func _physics_process(_delta: float) -> void:
	var isRotating := false
	var isTranslating := false
	if character_controller:
		previous_transform = character_controller.transform
	left_leg_current_target = IkUtil.update_ik_raycast(
		left_leg_raycast, left_leg_next_target, left_leg_current_target,
		left_upper_leg, left_lower_leg, left_leg_pole,
		right_leg_current_target,  # 👈 pass the opposite leg
		step_radius_walk, STEP_HEIGHT, STEP_SPEED_MPS,
	)
	right_leg_current_target = IkUtil.update_ik_raycast(
		right_leg_raycast, right_leg_next_target, right_leg_current_target,
		right_upper_leg, right_lower_leg, right_leg_pole,
		left_leg_current_target,   # 👈 pass the opposite leg
		step_radius_walk, STEP_HEIGHT, STEP_SPEED_MPS,
	)
