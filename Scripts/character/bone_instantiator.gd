class_name BoneInstantiator
extends Node3D

@export var is_active: bool = false
@export var master_seed: int = 0
var entity_instantiation: EntityInstantiation

var player_camera: Camera3D
var entity_archetype : EntityArchetype
var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil 
var char_rigidbody : CharacterRigidBody3D
var ik_util : IkUtil
var locomotion_signals: LocomotionSignals
var procedural_animator: ProceduralBoneAnimator
var ragdoll_util: RagdollUtil

var player_controller: PlayerController
@onready var global_targets : Node3D = $"global_targets"
@onready var local_targets : Node3D = $"local_targets"
@onready var skel_rigidbodies : Node3D = $"skel_rigidbodies"
@onready var joints : Node3D = $"joints"

var previous_transform : Transform3D

var jump_squat_t: float = 0.0
var crouch_t: float = 0.0
var _last_root_z_offset: float = 0.0

const JUMP_SQUAT_Y    := -0.22
const JUMP_SQUAT_Z    :=  0.09
const JUMP_SQUAT_TILT :=  0.22
const CROUCH_Y        := -0.22
const CROUCH_Z        :=  0.13
const CROUCH_TILT     :=  0.3

const ARM_COMPRESS_CROUCH: float = 1.35
const ARM_COMPRESS_JUMP:   float = 0.45
const ARM_COMPRESS_IMPACT: float = 0.30
const ARM_FORWARD_SCALE:   float = 0.25  # cuanto se mueven hacia adelante por unidad de compress
const ARM_BEND_SCALE:      float = 0.18  # cuanto suben (bend) por unidad de compress

var ARM_JUMP_EXTENSION_FACTOR: float = 0.35


func _ready() -> void:
	if is_active:
		player_controller = PlayerController.new()
		add_child(player_controller)
	initialize_skeleton()

func initialize_skeleton() -> void:
	_clear_prior_generations()
	entity_instantiation = EntityInstantiation.create(master_seed)
	entity_archetype = entity_instantiation.arch_final
	skel_sizes_util = SkeletonSizesUtil.create(entity_instantiation)
	custom_bones_util = CustomBonesUtil.create(skel_sizes_util, entity_instantiation)
	ik_util = IkUtil.create(skel_sizes_util, self)
	var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
	var charRb := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
	char_rigidbody = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active, entity_instantiation)
	char_rigidbody.fall_triggered.connect(_on_fall_triggered)
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

	local_targets.add_child(ik_util.left_arm_ik_target)
	local_targets.add_child(ik_util.right_arm_ik_target)
	local_targets.add_child(ik_util.left_arm_pole)
	local_targets.add_child(ik_util.right_arm_pole)

	if is_active and is_instance_valid(player_controller):
		player_camera = Camera3D.new()
		player_camera.current = true
		char_rigidbody.add_child(player_camera)
		player_controller.setup(char_rigidbody, player_camera, custom_bones_util.head, skel_sizes_util.head_size, entity_instantiation)

	locomotion_signals = LocomotionSignals.create(ik_util, char_rigidbody, skel_sizes_util)

	ik_util.left_arm_ik_target.position  = skel_sizes_util.left_arm_tip_rest_local
	ik_util.right_arm_ik_target.position = skel_sizes_util.right_arm_tip_rest_local
	ik_util.left_arm_pole.position       = skel_sizes_util.left_arm_pole_rest_local
	ik_util.right_arm_pole.position      = skel_sizes_util.right_arm_pole_rest_local

	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
		ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
		ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

	procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)
	_register_bone_animations()
	ragdoll_util = RagdollUtil.create(custom_bones_util, skel_rigidbodies, joints)

	jump_squat_t = 0.0
	crouch_t = 0.0
	_last_root_z_offset = 0.0

func _on_fall_triggered(world_dir: Vector3) -> void:
	if not is_instance_valid(ragdoll_util) or ragdoll_util.is_active:
		return
	char_rigidbody.is_snapshot_active = false
	ragdoll_util.activate_with_impact(char_rigidbody, custom_bones_util.lower_spine, world_dir)

func _register_bone_animations() -> void:
	var PA := ProceduralBoneAnimator
	var ls := locomotion_signals

	var vertical_bobbing := entity_instantiation.root_bounciness
	var shoulder_swing   := entity_instantiation.shoulder_swing
	var hip_swing        := entity_instantiation.hip_swing

	var _top_spine_rotation    := 0.1
	var _bottom_spine_rotation := -0.5 * hip_swing

	var right_hip      := custom_bones_util.right_hip
	var left_hip       := custom_bones_util.left_hip
	var lower_spine    := custom_bones_util.lower_spine
	var middle_spine   := custom_bones_util.middle_spine
	var upper_spine    := custom_bones_util.upper_spine
	var chest          := custom_bones_util.chest
	var right_shoulder := custom_bones_util.right_shoulder
	var left_shoulder  := custom_bones_util.left_shoulder

	# ─── HIPS ───────────────────────────────────────────────────────────────────

	procedural_animator.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.6 * hip_swing)
	procedural_animator.register(left_hip,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.6 * hip_swing)
	procedural_animator.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.1 * hip_swing)
	procedural_animator.register(left_hip,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.1 * hip_swing)

	var hips_rotation := spine_local_weight(0, 5, _bottom_spine_rotation, _top_spine_rotation)
	procedural_animator.register(right_hip, PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -hips_rotation)
	procedural_animator.register(left_hip,  PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  hips_rotation)

	# ─── SPINE ──────────────────────────────────────────────────────────────────

	procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_X, vertical_bobbing * -0.14)
	procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_Z, vertical_bobbing * -0.3)

	procedural_animator.register_formula(lower_spine, PA.Axis.ROT_Z,
		func(): return ls.foot_spread_unified.x * (0.01 + 0.04 * ls.speed_norm),
		1.0)

	var lower_spine_rotation  := spine_local_weight(1, 5, _bottom_spine_rotation, _top_spine_rotation)
	var middle_spine_rotation := spine_local_weight(2, 5, _bottom_spine_rotation, _top_spine_rotation)
	var upper_spine_rotation  := spine_local_weight(3, 5, _bottom_spine_rotation, _top_spine_rotation)
	var chest_rotation        := spine_local_weight(4, 5, _bottom_spine_rotation, _top_spine_rotation)

	procedural_animator.register(lower_spine,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, lower_spine_rotation)
	procedural_animator.register(middle_spine, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, middle_spine_rotation)
	procedural_animator.register(upper_spine,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, upper_spine_rotation)
	procedural_animator.register(chest,        PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, chest_rotation)

	# ─── SPINE BOW (forward lean while walking) ──────────────────────────────────

	var bow_w := 0.15
	procedural_animator.register(lower_spine,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  bow_w * 0.5)
	procedural_animator.register(middle_spine, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  bow_w * 1.0)
	procedural_animator.register(upper_spine,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -bow_w * 1.0)
	procedural_animator.register(chest,        PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -bow_w * 0.5)
	procedural_animator.register(lower_spine,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.03)

	# ─── SPINE TILT (velocity lean) ──────────────────────────────────────────────

	var tilt_weight := 0.05
	procedural_animator.register(lower_spine, PA.Axis.ROT_X, PA.SignalType.H_VEL_Z, -tilt_weight)
	procedural_animator.register(lower_spine, PA.Axis.ROT_Z, PA.SignalType.H_VEL_X, -tilt_weight)

	# ─── SHOULDERS ───────────────────────────────────────────────────────────────

	procedural_animator.register(right_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  shoulder_swing * 0.1)
	procedural_animator.register(left_shoulder,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  shoulder_swing * 0.1)
	procedural_animator.register(right_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -0.3)
	procedural_animator.register(left_shoulder,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -0.3)
	procedural_animator.register(right_shoulder, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -0.95)
	procedural_animator.register(left_shoulder,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -0.95)
	procedural_animator.register(right_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  0.0)
	procedural_animator.register(left_shoulder,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  0.0)
	procedural_animator.register(right_shoulder, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.5)
	procedural_animator.register(left_shoulder,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.5)

	# ─── HEAD / NECK PITCH (player camera follow) ────────────────────────────────

	if is_active and is_instance_valid(player_camera):
		var bi := self
		var pitch_callable := func() -> float:
			if not is_instance_valid(bi.player_camera):
				return 0.0
			return clamp(bi.player_camera.rotation.x, -0.5, 0.8)

		procedural_animator.register_formula(custom_bones_util.head, PA.Axis.ROT_X, pitch_callable, 0.50)
		if is_instance_valid(custom_bones_util.neck):
			procedural_animator.register_formula(custom_bones_util.neck, PA.Axis.ROT_X, pitch_callable, 0.25)
		procedural_animator.register_formula(chest,        PA.Axis.ROT_X, pitch_callable, 0.12)
		procedural_animator.register_formula(upper_spine,  PA.Axis.ROT_X, pitch_callable, 0.08)
		procedural_animator.register_formula(middle_spine, PA.Axis.ROT_X, pitch_callable, 0.05)

	# ─── ARM SWING ───────────────────────────────────────────────────────────────

	var arm_swing  := entity_instantiation.arch_final.arm_swing
	var arm_total  := skel_sizes_util.upper_arm_size.y + skel_sizes_util.lower_arm_size.y
	var z_weight   := arm_swing * arm_total
	var arc_extra  := 0.4

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.FORWARD,
		func():
			return ls.foot_spread_unified.y * z_weight * ls.speed_norm,
		1.0)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.FORWARD,
		func():
			return -ls.foot_spread_unified.y * z_weight * ls.speed_norm,
		1.0)

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.UP,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)) + abs(d) * arc_extra,
		1.0)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.UP,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)) + abs(d) * arc_extra,
		1.0)

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.LEFT,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)),
		1.0)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.LEFT,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return -(arm_total - sqrt(max(0.0, arm_total * arm_total - d * d))),
		1.0)

	# ─── VERTICAL VELOCITY (jump / fall) ─────────────────────────────────────────

	var v_vel_arm_weight := 0.44
	var arm_bentness     := entity_instantiation.arch_final.arm_bentness
	var max_extension    := arm_bentness * ARM_JUMP_EXTENSION_FACTOR * arm_total

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.UP,
		func():
			return max(ls.vertical_velocity_smooth / -10.0, -max_extension),
		v_vel_arm_weight)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.UP,
		func():
			return max(ls.vertical_velocity_smooth / -10.0, -max_extension),
		v_vel_arm_weight)

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)),
		1.0)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return -(arm_total - sqrt(max(0.0, arm_total * arm_total - d * d))),
		1.0)

	procedural_animator.register_formula(right_shoulder, PA.Axis.ROT_Z,
		func():
			return ls.vertical_velocity_smooth / 10.0,
		0.3)
	procedural_animator.register_formula(left_shoulder, PA.Axis.ROT_Z,
		func():
			return ls.vertical_velocity_smooth / 10.0,
		-0.3)

	procedural_animator.register_node_formula(ik_util.left_arm_pole, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)),
		1.0)
	procedural_animator.register_node_formula(ik_util.right_arm_pole, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return -(arm_total - sqrt(max(0.0, arm_total * arm_total - d * d))),
		1.0)

	procedural_animator.register_node_formula(ik_util.left_arm_pole, Vector3.UP,
		func():
			return max(0.0, ls.vertical_velocity_smooth / -10.0),
		v_vel_arm_weight * 1.0)
	procedural_animator.register_node_formula(ik_util.right_arm_pole, Vector3.UP,
		func():
			return max(0.0, ls.vertical_velocity_smooth / -10.0),
		v_vel_arm_weight * 1.0)

	# ─── ARM COMPRESS (crouch / jump squat / landing) ────────────────────────────

	var arm_forward_scale := ARM_FORWARD_SCALE
	var arm_bend_scale    := ARM_BEND_SCALE
	var bi                := self

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.FORWARD,
		func(): return bi.locomotion_signals.arm_compress,
		arm_forward_scale)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.FORWARD,
		func(): return bi.locomotion_signals.arm_compress,
		arm_forward_scale)

	procedural_animator.register_node_formula(ik_util.left_arm_ik_target, Vector3.UP,
		func(): return bi.locomotion_signals.arm_compress,
		arm_bend_scale)
	procedural_animator.register_node_formula(ik_util.right_arm_ik_target, Vector3.UP,
		func(): return bi.locomotion_signals.arm_compress,
		arm_bend_scale)

	# ─── LANDING ────────────────────────────────────────────────────────────────

	var impact_y_weight := 0.9

	procedural_animator.register_formula(lower_spine, PA.Axis.POS_Y,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0),
		-impact_y_weight * 2)
	procedural_animator.register_formula(lower_spine, PA.Axis.POS_Z,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0),
		impact_y_weight)
	procedural_animator.register_formula(lower_spine, PA.Axis.ROT_X,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0),
		-impact_y_weight * 3)

	procedural_animator.register_formula(right_shoulder, PA.Axis.ROT_Z,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0),
		-impact_y_weight * 0.5)
	procedural_animator.register_formula(left_shoulder, PA.Axis.ROT_Z,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0),
		impact_y_weight * 0.5)
		
	# ─── XZ IMPACT ──────────────────────────────────────────────────────────────

	procedural_animator.register_formula(lower_spine, PA.Axis.ROT_X,
		func(): return ls.impact_xz_smooth.y,
		impact_y_weight * 1.5)
	procedural_animator.register_formula(lower_spine, PA.Axis.ROT_Z,
		func(): return ls.impact_xz_smooth.x,
		impact_y_weight * 1.5)
	
	
	
func _clear_prior_generations() -> void:
	if is_instance_valid(ragdoll_util):
		if ragdoll_util.is_active and is_instance_valid(char_rigidbody):
			char_rigidbody.freeze = false
			char_rigidbody.collider.disabled = false
		ragdoll_util.cleanup()
	ragdoll_util = null

	for global_target in global_targets.get_children(): 
		global_target.queue_free()
	for local_target in local_targets.get_children(): 
		local_target.queue_free()
	for skel_rigidbody in skel_rigidbodies.get_children(): 
		skel_rigidbody.queue_free()
	for joint in joints.get_children(): 
		joint.queue_free()
	if is_instance_valid(char_rigidbody):
		char_rigidbody.queue_free()
	player_camera = null

func _physics_process(_delta: float) -> void:
	_update_local_targets_positions()

	if is_instance_valid(char_rigidbody) and is_instance_valid(ragdoll_util):
		if ragdoll_util.is_active:
			char_rigidbody._ext_ragdoll_state = 1
		elif ragdoll_util.is_recovering:
			char_rigidbody._ext_ragdoll_state = 2
		else:
			char_rigidbody._ext_ragdoll_state = 0

	ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, true, skel_sizes_util, entity_archetype)
	ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, false, skel_sizes_util, entity_archetype)

	if is_instance_valid(ragdoll_util):
		ragdoll_util.update(_delta)
		if ragdoll_util.is_active:
			ik_util.update_ik_raycast(true, custom_bones_util, skel_sizes_util, char_rigidbody)
			ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, char_rigidbody)
			return
		if ragdoll_util.is_recovering and not ik_util.recovery_targets_locked:
			ik_util.recovery_targets_locked = true
		elif not ragdoll_util.is_recovering and ik_util.recovery_targets_locked:
			ik_util.recovery_targets_locked = false
			char_rigidbody.is_snapshot_active = true

	skel_sizes_util.update(_delta, char_rigidbody, entity_instantiation, ik_util)
	ik_util.update_ik_raycast(true, custom_bones_util, skel_sizes_util, char_rigidbody)
	ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, char_rigidbody)
	var arm_bentness := entity_instantiation.arch_final.arm_bentness
	var remaining := 1.0 - arm_bentness
	var raw_compress : float = crouch_t * ARM_COMPRESS_CROUCH \
		+ jump_squat_t * ARM_COMPRESS_JUMP \
		+ max(0.0, char_rigidbody.impact_y) * ARM_COMPRESS_IMPACT
	locomotion_signals.arm_compress = clamp(raw_compress * remaining, 0.0, remaining)
	locomotion_signals.update(_delta)

	ik_util.left_arm_ik_target.position  = skel_sizes_util.left_arm_tip_rest_local
	ik_util.right_arm_ik_target.position = skel_sizes_util.right_arm_tip_rest_local
	procedural_animator.update()
	_apply_root_offsets()

	var rb_basis := custom_bones_util.lower_spine.global_transform.basis
	var left_anim_offset: Vector3  = ik_util.left_arm_ik_target.position  - skel_sizes_util.left_arm_tip_rest_local
	var right_anim_offset: Vector3 = ik_util.right_arm_ik_target.position - skel_sizes_util.right_arm_tip_rest_local

	ik_util.left_arm_ik_target.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_tip_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_anim_offset)
	ik_util.right_arm_ik_target.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_tip_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_anim_offset)

	var left_pole_anim_offset: Vector3  = ik_util.left_arm_pole.position  - skel_sizes_util.left_arm_pole_rest_local
	var right_pole_anim_offset: Vector3 = ik_util.right_arm_pole.position - skel_sizes_util.right_arm_pole_rest_local

	ik_util.left_arm_pole.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_pole_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_pole_anim_offset)
	ik_util.right_arm_pole.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_pole_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_pole_anim_offset)

	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
		ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
		ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

	if is_instance_valid(ragdoll_util) and not ragdoll_util.is_recovering:
		ragdoll_util.sync_to_bones()

func _apply_root_offsets() -> void:
	var y    := JUMP_SQUAT_Y    * jump_squat_t + CROUCH_Y    * crouch_t
	var z    := JUMP_SQUAT_Z    * jump_squat_t + CROUCH_Z    * crouch_t
	var tilt := JUMP_SQUAT_TILT * jump_squat_t + CROUCH_TILT * crouch_t
	var spine := custom_bones_util.lower_spine
	spine.position.z -= _last_root_z_offset
	spine.position.z += z
	_last_root_z_offset = z
	spine.position.y += y
	spine.transform.basis *= Basis(Vector3.RIGHT, -tilt)

func _update_local_targets_positions() -> void:
	local_targets.global_position = char_rigidbody.global_position
	local_targets.global_rotation = Vector3(0, char_rigidbody.global_rotation.y, 0)

func spine_local_weight(index: int, count: int, min_rot: float, max_rot: float) -> float:
	var global_weight := func(i: int) -> float:
		if i < 0:
			return 0.0
		var t := float(i) / float(count - 1)
		return lerp(max_rot, min_rot, t)
	return global_weight.call(index) - global_weight.call(index - 1)

static func _get_arm_tip_rest_local(left: bool, sizes: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var tip_y := sizes.lower_spine_size.y \
		+ sizes.middle_spine_size.y \
		+ sizes.upper_spine_size.y \
		+ sizes.chest_size.y \
		- sizes.upper_arm_size.y \
		- sizes.lower_arm_size.y
	var tip_x := sign_x * (sizes.shoulder_width.y + sizes.shoulders_width)
	return Vector3(tip_x, tip_y, 0.0)

func refresh_camera_animations() -> void:
	if not is_active or not is_instance_valid(player_camera):
		return
	var PA := ProceduralBoneAnimator
	var bi := self
	var pitch_callable := func() -> float:
		if not is_instance_valid(bi.player_camera):
			return 0.0
		return clamp(bi.player_camera.rotation.x, -0.5, 0.8)

	procedural_animator.register_formula(custom_bones_util.head, PA.Axis.ROT_X, pitch_callable, 0.50)
	if is_instance_valid(custom_bones_util.neck):
		procedural_animator.register_formula(custom_bones_util.neck, PA.Axis.ROT_X, pitch_callable, 0.25)
	procedural_animator.register_formula(custom_bones_util.chest,        PA.Axis.ROT_X, pitch_callable, 0.12)
	procedural_animator.register_formula(custom_bones_util.upper_spine,  PA.Axis.ROT_X, pitch_callable, 0.08)
	procedural_animator.register_formula(custom_bones_util.middle_spine, PA.Axis.ROT_X, pitch_callable, 0.05)
