class_name BoneInstantiator
extends Node3D

@export var is_active: bool = false
@export var archetype: EntityStats.Archetype = EntityStats.Archetype.fat_man

var player_camera: Camera3D
var entity_stats : EntityStats
var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil 
var char_rigidbody : CharacterRigidBody3D
var ik_util : IkUtil
# NEW
var locomotion_signals: LocomotionSignals
var procedural_animator: ProceduralBoneAnimator

@onready var player_controller: PlayerController
@onready var global_targets : Node3D = $"global_targets"
@onready var local_targets : Node3D = $"local_targets"
@onready var skel_rigidbodies : Node3D = $"skel_rigidbodies"
@onready var joints : Node3D = $"joints"

var previous_transform : Transform3D 

func _ready() -> void:
	if is_active:
		player_controller = PlayerController.new()
		add_child(player_controller)
	initialize_skeleton()

func initialize_skeleton() -> void:
	_clear_prior_generations()
	entity_stats = EntityStats.create(archetype)
	skel_sizes_util = SkeletonSizesUtil.create(entity_stats)
	custom_bones_util = CustomBonesUtil.create(skel_sizes_util, entity_stats)
	ik_util = IkUtil.create(skel_sizes_util, self)
	var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
	var charRb := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
	char_rigidbody = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active)
	char_rigidbody.add_child(custom_bones_util.lower_spine)
	add_child(char_rigidbody) 
	local_targets.add_child(ik_util.left_leg_raycast)
	local_targets.add_child(ik_util.right_leg_raycast)
	ik_util.left_leg_raycast.add_exception(char_rigidbody)
	ik_util.right_leg_raycast.add_exception(char_rigidbody)
	local_targets.add_child(ik_util.left_leg_next_target)
	local_targets.add_child(ik_util.right_leg_next_target)
	local_targets.add_child(ik_util.left_leg_airborne_target)
	local_targets.add_child(ik_util.right_leg_airborne_target)
	global_targets.add_child(ik_util.left_leg_current_target)
	global_targets.add_child(ik_util.right_leg_current_target)

	if is_active:
		player_camera = Camera3D.new()
		player_camera.current = true
		char_rigidbody.add_child(player_camera)
		player_controller.setup(char_rigidbody, player_camera, custom_bones_util.head, skel_sizes_util.head_size)

	# NEW — create signals and animator
	locomotion_signals = LocomotionSignals.create(ik_util, char_rigidbody, skel_sizes_util)
	procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)
	_register_bone_animations()

# NEW — wire up which bones get animated and how
func _register_bone_animations() -> void:
	var PA := ProceduralBoneAnimator
	var lower_spine := custom_bones_util.lower_spine

	# Root bob: dips down mid-step, scaled by step size
	procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_X, -0.07)

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
	player_camera = null

func _physics_process(_delta: float) -> void:
	_update_local_targets_positions()
	ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, true, skel_sizes_util, entity_stats) 
	ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, false, skel_sizes_util, entity_stats) 
	skel_sizes_util.update(_delta,char_rigidbody,entity_stats,ik_util)
	ik_util.update_ik_raycast(true, custom_bones_util, skel_sizes_util,char_rigidbody)
	ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util,char_rigidbody)
	# NEW — update signals first, then apply bone animations after IK
	locomotion_signals.update(_delta)
	procedural_animator.update()

func _update_local_targets_positions()-> void:
	pass
	local_targets.global_position = char_rigidbody.global_position
	local_targets.global_rotation = Vector3(0,char_rigidbody.global_rotation.y,0)
