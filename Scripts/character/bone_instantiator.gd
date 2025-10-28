class_name BoneInstantiator
extends Node3D

@export var archetype: EntityStats.Archetype = EntityStats.Archetype.fat_man

var entity_stats : EntityStats
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
	entity_stats = EntityStats.create(archetype)
	#Luego calculo los tamaños de todos los huesos a partir de las proporciones y medidas de alto nivel
	skel_sizes_util = SkeletonSizesUtil.create(entity_stats)
	#Luego ensamblo los huesos en una jerarquia con sus respectivos angulos de reposo, en clases de custombones
	custom_bones_util = CustomBonesUtil.create(skel_sizes_util, entity_stats)
	#Luego creo los local targets, global targets y raycasts
	ik_util = IkUtil.create(skel_sizes_util, custom_bones_util, self)
	#Luego creo el character rigidbody
	#var camera3d = Camera3D.new()
	#camera3d.position = Vector3(0, 1.7, 2.7)
	var charRb = Vector3(skel_sizes_util.shoulders_width * 2 ,skel_sizes_util.torso_height +skel_sizes_util.head_height,skel_sizes_util.hips_width*2)
	char_rigidbody = CharacterRigidBody3D.create(charRb,ik_util.left_leg_raycast,ik_util.right_leg_raycast,skel_sizes_util.distance_from_ground)
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
	ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, true, skel_sizes_util) 
	ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, false, skel_sizes_util) 
	#raycast_offset = ik_util.update_leg_raycast_offsets(root_rigidbody, _delta, false, speed_for_max, speed_curve, raycast_amount, raycast_max_offset, axis_weights, raycast_smooth, right_neutral_local, raycast_offset) 
	
	skel_sizes_util.update(_delta,char_rigidbody,entity_stats,ik_util)
	
	ik_util.update_ik_raycast(true, custom_bones_util, skel_sizes_util,char_rigidbody)
	ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util,char_rigidbody)
	
	
	#right_leg_current_target = IkUtil.update_ik_raycast(
		#right_leg_raycast, right_leg_next_target, right_leg_current_target,
		#right_upper_leg, right_lower_leg, right_leg_pole,
		#left_leg_current_target,   # la pierna opuesta
		#step_radius_walk, step_height, step_duration,
	#)


func _update_local_targets_positions()-> void:
	pass
	local_targets.global_position = char_rigidbody.global_position
	local_targets.global_rotation = Vector3(0,char_rigidbody.global_rotation.y,0)
