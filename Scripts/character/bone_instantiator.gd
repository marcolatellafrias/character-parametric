class_name BoneInstantiator
extends Node3D

#ALTURA DEL PERSONAJE
@export var feet_to_head_height := 2.2: #This excludes arms and horizontal bones,
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
@export var distance_from_ground_factor := 0.1  #tiene las piernas 10% flexionadas cuando esta en el piso

var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil
var char_rigidbody : CharacterRigidBody3D
var ik_util : IkUtil

@onready var global_targets : Node3D = $"global_targets"
@onready var local_targets : Node3D = $"local_targets"
@onready var skel_rigidbodies : Node3D = $"skel_rigidbodies"
@onready var joints : Node3D = $"joints"

var previous_transform : Transform3D 

func _ready() -> void:
	initialize_skeleton()

func initialize_skeleton() -> void:
	#Primero limpio todas las generaciones anteriores
	_clear_prior_generations()
	#Luego calculo los tamaños de todos los huesos a partir de las proporciones y medidas de alto nivel
	skel_sizes_util = SkeletonSizesUtil.create(self)
	#Luego ensamblo los huesos en una jerarquia con sus respectivos angulos de reposo, en clases de custombones
	custom_bones_util = CustomBonesUtil.create(skel_sizes_util, has_neck)
	#Luego creo los local targets, global targets y raycasts
	ik_util = IkUtil.create(skel_sizes_util, custom_bones_util, self)
	#Luego creo el character rigidbody
	#var camera3d = Camera3D.new()
	#camera3d.position = Vector3(0, 1.7, 2.7)
	var charRb = Vector3(1,2,1)
	char_rigidbody = CharacterRigidBody3D.create(charRb,ik_util.left_leg_raycast,ik_util.right_leg_raycast)
	#Agrego el esqueleto target y la camara como hijo de el rigidbody
	char_rigidbody.add_child(custom_bones_util.lower_spine)
	#char_rigidbody.add_child(camera3d)
	
	#AÑADO AL PLAYER ROOT
	#Character rigidbody
	add_child(char_rigidbody) 
	#Local objects
	local_targets.add_child(ik_util.left_leg_raycast)
	local_targets.add_child(ik_util.right_leg_raycast)
	local_targets.add_child(ik_util.left_leg_pole)
	local_targets.add_child(ik_util.right_leg_pole)
	local_targets.add_child(ik_util.left_leg_next_target)
	local_targets.add_child(ik_util.right_leg_next_target)
	#Global objects
	global_targets.add_child(ik_util.left_leg_current_target)
	global_targets.add_child(ik_util.right_leg_current_target)

func _clear_prior_generations()-> void:
	for global_target in global_targets.get_children(): 
		global_target.queue_free()
	for local_target in local_targets.get_children(): 
		local_target.queue_free()
	for skel_rigidbody in skel_rigidbodies.get_children(): 
		skel_rigidbody.queue_free()
	for joint in joints.get_children(): 
		joint.queue_free()
	if (char_rigidbody):
		char_rigidbody.queue_free()

func _physics_process(_delta: float) -> void:
	_update_local_targets_positions()
	#dynamic_sizes_util.update(_delta)
	#
	#var isTranslating := false
	#if root_rigidbody:
		#previous_transform = root_rigidbody.transform
		#
	#raycast_offset = IkUtil.update_leg_raycast_offsets(char_rigidbody, _delta, left_leg_raycast, speed_for_max, speed_curve, raycast_amount, raycast_max_offset, axis_weights, raycast_smooth, left_neutral_local, raycast_offset) 
	#raycast_offset = IkUtil.update_leg_raycast_offsets(root_rigidbody, _delta, right_leg_raycast, speed_for_max, speed_curve, raycast_amount, raycast_max_offset, axis_weights, raycast_smooth, right_neutral_local, raycast_offset) 
	##
	ik_util.update_ik_raycast(
		true, custom_bones_util, skel_sizes_util, false, false,
	)
	ik_util.update_ik_raycast(
		false, custom_bones_util, skel_sizes_util, false, false,
	)
	#right_leg_current_target = IkUtil.update_ik_raycast(
		#right_leg_raycast, right_leg_next_target, right_leg_current_target,
		#right_upper_leg, right_lower_leg, right_leg_pole,
		#left_leg_current_target,   # la pierna opuesta
		#step_radius_walk, step_height, step_duration,
	#)


func _update_local_targets_positions()-> void:
	local_targets.global_position = char_rigidbody.global_position
	#local_targets.global_rotation = Vector3(0,char_rigidbody.global_rotation.y,0)

#func _place_rays() -> void:
	## Bottom-left/right of the box in collider local space.
	#var half_w := _box.size.x * 0.5
	#var bottom_y := -_box.size.y * 0.5
	#var left_local := Vector3(-half_w, bottom_y, 0.0)
	#var right_local := Vector3(half_w, bottom_y, 0.0)
#
	#var start_left := _collider.to_global(left_local)
	#var start_right := _collider.to_global(right_local)
#
	#var end_left := start_left + Vector3.DOWN * ray_length
	#var end_right := start_right + Vector3.DOWN * ray_length
#
	#_left_ray.global_transform.origin = start_left
	#_right_ray.global_transform.origin = start_right
	#_left_ray.target_position = _left_ray.to_local(end_left)
	#_right_ray.target_position = _right_ray.to_local(end_right)
