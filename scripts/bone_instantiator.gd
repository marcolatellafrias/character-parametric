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

#IK raycasts
var left_ray_cast: RayCast3D
var right_ray_cast: RayCast3D

var step_radius_walk := 0.1
var step_radius_turn := 0.05

#IK targets
var pole_distance: float = 0.8
var target_height: float = -2.0
var pole_color: Color = Color(1, 0, 0)      # rojo
var target_color: Color = Color(0, 1, 0)    # verde
var raycast_color: Color = Color(0, 0, 1)    # verde

var left_pole: Node3D
var right_pole: Node3D
var left_target: Node3D
var right_target: Node3D

#NECK TO HEAD
var neck_size: Vector3
var head_size: Vector3

#CHEST TO LOW SPINE
var chest_size: Vector3
var upper_spine_size: Vector3
var middle_spine_size: Vector3
var lower_spine_size: Vector3 #this is the root

#LEGS TO FEET
var upper_leg_size: Vector3
var lower_leg_size: Vector3
var upper_feet_size: Vector3
var lower_feet_size: Vector3

#ARMS
var upper_arm_size: Vector3
var lower_arm_size: Vector3

#HORIZONTAL BONES
var shoulder_width: Vector3
var hip_width: Vector3

func calculate_sizes() -> void:
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
	lower_feet_size = Vector3(0.3, leg_height * 0.02, 0.3)

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
	#if has_neck:
	neck_size = Vector3(0.1, head_height * 0.8, 0.1)
	head_size = Vector3(0.3, head_height * 1.0, 0.3)
	#else:
	#	neck_size = Vector3.ZERO
	#	head_size = Vector3(0.3, head_height, 0.3)

	# --------- BRAZOS ---------
	var arm_total := torso_height * arms_proportion
	upper_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	lower_arm_size = Vector3(0.1, arm_total * 0.45, 0.1)

func create_debug_line(color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.01,10,0.01)
	mesh_instance.mesh = cube
	mesh_instance.position = Vector3 (0.0,5,0.0)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	return mesh_instance

func create_debug_sphere(color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3(0.1,0.1,0.1)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	return mesh_instance

func _ready() -> void:
	initialize_skeleton()

func initialize_skeleton() -> void:
	calculate_sizes()
	for child in get_children():
		child.queue_free()

	# Hueso raíz
	var lower_spine := CustomBone.create(lower_spine_size, Vector3.ZERO, Color.WHITE_SMOKE)
	add_child(lower_spine)

	# Chest and spine
	var middle_spine := CustomBone.createFromToUp(lower_spine, middle_spine_size, 0.0,0.0, Color.SKY_BLUE, true)
	var upper_spine := CustomBone.createFromToUp(middle_spine, upper_spine_size, 0.0,0.0, Color.BURLYWOOD , true)
	var chest := CustomBone.createFromToUp(upper_spine, chest_size, 0.0,0.0, Color.BURLYWOOD , true)
	var left_hip := CustomBone.createFromToLeft(lower_spine, hip_width, 0.0,0.0, Color.ROYAL_BLUE , false)
	var right_hip := CustomBone.createFromToRight(lower_spine, hip_width, 0.0,0.0, Color.ROYAL_BLUE , false)

	# Legs
	var left_upper_leg := CustomBone.createFromToDown(left_hip, upper_leg_size, 0.0,0.0, Color.YELLOW , true)
	var left_lower_leg := CustomBone.createFromToDown(left_upper_leg, lower_leg_size, 0.0,0.0, Color.ORANGE , true)
	var right_upper_leg := CustomBone.createFromToDown(right_hip, upper_leg_size, 0.0,0.0, Color.YELLOW , true)
	var right_lower_leg := CustomBone.createFromToDown(right_upper_leg, lower_leg_size, 0.0,0.0, Color.ORANGE , true)
	var right_upper_feet := CustomBone.createFromToForward(right_lower_leg, upper_feet_size, 0.0,0.0, Color.ORANGE , true)
	var left_upper_feet := CustomBone.createFromToForward(left_lower_leg, upper_feet_size, 0.0,0.0, Color.ORANGE , true)
	
	# Head
	var neck := CustomBone.createFromToUp(chest, neck_size, 0.0,0.0, Color.RED , true)
	var head := CustomBone.createFromToUp(neck, head_size, 0.0,0.0, Color.GREEN , true)
	
	# Shoulders
	var left_shoulder := CustomBone.createFromToLeft(chest, shoulder_width, 0.0,0.3, Color.CHOCOLATE , true)
	var right_shoulder := CustomBone.createFromToRight(chest, shoulder_width, 0.0,-0.3, Color.GREEN , true)

	# Arms
	var right_upper_arm := CustomBone.createFromToDown(right_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	var right_lower_arm := CustomBone.createFromToDown(right_upper_arm, lower_arm_size, 0.0,0.0, Color.RED , true)
	var left_upper_arm := CustomBone.createFromToDown(left_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	var left_lower_arm := CustomBone.createFromToDown(left_upper_arm, lower_arm_size, 0.0,0.0, Color.RED , true)
	
	left_ray_cast = RayCast3D.new()
	left_ray_cast.position = lower_spine.position
	left_ray_cast.translate(Vector3(hip_width.y,0,0))
	left_ray_cast.rotation = Vector3.DOWN
	add_child(left_ray_cast)
	
	create_ik_controls(left_lower_leg, right_lower_leg)

func create_ik_controls(left_lower_leg: CustomBone, right_lower_leg: CustomBone) -> void:
	left_ray_cast = RayCast3D.new()
	left_ray_cast.rotation = Vector3(deg_to_rad(180), 0, 0)
	left_ray_cast.translate(Vector3(1,0,0))
	left_ray_cast.add_child(create_debug_line(raycast_color))
	add_child(left_ray_cast)
	
	# Limpia controles previos
	for node in [left_pole, right_pole, left_target, right_target]:
		if node and is_instance_valid(node):
			node.queue_free()

	# === LEFT POLE ===
	left_pole = Node3D.new()
	add_child(left_pole)
	left_pole.global_position = left_lower_leg.global_position + left_lower_leg.global_transform.basis.z * pole_distance
	left_pole.add_child(create_debug_sphere(pole_color))

	# === RIGHT POLE ===
	right_pole = Node3D.new()
	add_child(right_pole)
	right_pole.global_position = right_lower_leg.global_position + right_lower_leg.global_transform.basis.z * pole_distance
	right_pole.add_child(create_debug_sphere(pole_color))

	# === IK TARGETS ===
	left_target = Node3D.new()
	add_child(left_target)
	left_target.global_position = Vector3.ZERO
	left_target.add_child(create_debug_sphere(target_color))

	#right_target = Node3D.new()
	#add_child(right_target)
	#right_target.global_position = Vector3.ZERO
	#right_target.add_child(create_debug_sphere(target_color))
	
func _process(delta: float) -> void:
	if left_ray_cast.is_colliding():
		var collisionPoint : Vector3 = left_ray_cast.get_collision_point()
		left_target.position = collisionPoint
		
