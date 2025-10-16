extends Node3D

#ALTURA DEL PERSONAJE
@export var feet_to_head_height := 1.8: #This excludes arms and horizontal bones,
	set(value):
		feet_to_head_height = value
		initialize_skeleton()

#PROPORCIONES/INTERFAZ
@export var neck_to_head_proportion := 0.1:
	set(value):
		neck_to_head_proportion = value
		initialize_skeleton()
@export var chest_to_low_spine_proportion := 0.4:
	set(value):
		chest_to_low_spine_proportion = value
		initialize_skeleton()
@export var legs_to_feet_proportion := 0.6:
	set(value):
		legs_to_feet_proportion = value
		initialize_skeleton()
@export var hips_width_proportion := 0.15:
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


#Step sizes
var step_radius_walk := 0.1
var step_radius_turn := 0.05

#IK variables
var pole_distance: float = 0.8
var target_height: float = -2.0
var left_color: Color = Color(1, 0, 0)      # rojo
var right_color: Color = Color(0, 1, 0)    # verde
var raycast_color: Color = Color(0, 0, 1)    # verde
var raycast_lenght: float #la distancia del raycast desde la altura del rootbone
var left_pole: Node3D
var right_pole: Node3D
var left_target: Node3D
var right_target: Node3D
var current_left_target: Node3D
var current_right_target: Node3D
var left_raycast: RayCast3D
var right_raycast: RayCast3D

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
	upper_leg_size = Vector3(0.1, leg_height * 0.55, 0.1)
	lower_leg_size = Vector3(0.1, leg_height * 0.45, 0.1)

	# Separar el pie de la pierna
	upper_feet_size = Vector3(0.1, leg_height * 0.28, 0.1)
	lower_feet_size = Vector3(0.1, leg_height * 0.02, 0.1)

	# --------- TORSO ---------
	# Proporciones ajustadas internamente para coherencia anatómica
	lower_spine_size = Vector3(0.1, torso_height * 0.1, 0.1)
	middle_spine_size = Vector3(0.1, torso_height * 0.2, 0.1)
	upper_spine_size = Vector3(0.1, torso_height * 0.3, 0.1)
	chest_size = Vector3(0.2, torso_height * 0.4, 0.2)

	# Anchuras laterales
	hip_width = Vector3( 0.1,hips_width_proportion * feet_to_head_height, 0.1)
	shoulder_width = Vector3( 0.1,shoulder_width_proportion * feet_to_head_height, 0.3)

	# --------- CABEZA Y CUELLO ---------
	if has_neck:
		neck_size = Vector3(0.1, head_height * 0.8, 0.1)
		head_size = Vector3(0.3, head_height * 1.0, 0.3)
	else:
		neck_size = Vector3.ZERO
		head_size = Vector3(0.3, head_height, 0.3)

	# --------- BRAZOS ---------
	var arm_total := torso_height * arms_proportion
	upper_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	lower_arm_size = Vector3(0.1, arm_total * 0.45, 0.1)
	raycast_lenght = leg_height * 1.5

func _ready() -> void:
	initialize_skeleton()

func initialize_skeleton() -> void:
	update_sizes()
	
	for child in get_children():
		child.queue_free()

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
	right_lower_arm = CustomBone.createFromToDown(right_upper_arm, lower_arm_size, 0.0,0.0, Color.RED , true)
	left_upper_arm = CustomBone.createFromToDown(left_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	left_lower_arm = CustomBone.createFromToDown(left_upper_arm, lower_arm_size, 0.0,0.0, Color.RED , true)
	
	create_ik_controls()

func create_ik_controls() -> void:	
	left_raycast = RayCast3D.new()
	left_raycast.target_position = Vector3(0,-raycast_lenght,0)
	left_raycast.add_child(DebugUtil.create_debug_line(raycast_color, raycast_lenght))
	left_raycast.translate(Vector3(-hip_width.y,0,0))
	add_child(left_raycast)
	right_raycast = RayCast3D.new()
	right_raycast.target_position = Vector3(0,-raycast_lenght,0)
	right_raycast.add_child(DebugUtil.create_debug_line(raycast_color, raycast_lenght))
	right_raycast.translate(Vector3(hip_width.y,0,0))
	add_child(right_raycast)
	
	# === LEFT POLE ===
	left_pole = Node3D.new()
	add_child(left_pole)
	left_pole.global_position = left_lower_leg.global_position + left_lower_leg.global_transform.basis.z * pole_distance
	left_pole.add_child(DebugUtil.create_debug_sphere(left_color))

	# === RIGHT POLE ===
	right_pole = Node3D.new()
	add_child(right_pole)
	right_pole.global_position = right_lower_leg.global_position + right_lower_leg.global_transform.basis.z * pole_distance
	right_pole.add_child(DebugUtil.create_debug_sphere(right_color))

	# === IK TARGETS ===
	left_target = Node3D.new()
	add_child(left_target)
	left_target.position = Vector3(-hip_width.y,-raycast_lenght,0)
	left_target.add_child(DebugUtil.create_debug_sphere(left_color))

	right_target = Node3D.new()
	add_child(right_target)
	right_target.position = Vector3(hip_width.y,-raycast_lenght,0)
	right_target.add_child(DebugUtil.create_debug_sphere(right_color))
   
func _physics_process(delta: float) -> void:
	left_raycast.force_raycast_update()
	if left_raycast.is_colliding():
		var collisionPoint : Vector3 = left_raycast.get_collision_point()
		left_target.global_position = collisionPoint
		#if (!current_left_target):
			#current_left_target = Node3D.new()
			#current_left_target.global_position = collisionPoint
			#current_left_target.add_child(DebugUtil.create_debug_cube(right_color))
			#custom_add_sibling(current_left_target)
	right_raycast.force_raycast_update()
	if right_raycast.is_colliding():
		var collisionPoint : Vector3 = right_raycast.get_collision_point()
		right_target.global_position = collisionPoint
	
func custom_add_sibling(sibling: Node) -> void:
	var parent = get_parent()
	if parent:
		parent.add_child(sibling)
		
