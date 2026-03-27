class_name ArmsController
extends Node

var bi: BoneInstantiator
var anim_mod: AnimationModifiers

const ARM_COMPRESS_CROUCH: float = 1.35
const ARM_COMPRESS_JUMP:   float = 0.45
const ARM_COMPRESS_IMPACT: float = 0.30
const ARM_FORWARD_SCALE:   float = 0.25
const ARM_BEND_SCALE:      float = 0.18
const THROW_CHARGE_SMOOTH: float = 8.0
const THROW_PUSH_SMOOTH:   float = 14.0
const HANDLE_SWITCH_SPEED: float = 8.0
const ARM_JUMP_EXTENSION_FACTOR: float = 0.35

var _grab_arm_blend: float = 0.0
var _grab_left_handle_world:  Vector3 = Vector3.ZERO
var _grab_right_handle_world: Vector3 = Vector3.ZERO
var _grab_left_handle_node:   Node3D = null
var _grab_right_handle_node:  Node3D = null
var _grab_left_blend_t:  float = 1.0
var _grab_right_blend_t: float = 1.0
var _grab_left_prev_world:  Vector3 = Vector3.ZERO
var _grab_right_prev_world: Vector3 = Vector3.ZERO

var _throw_left_local:       Vector3 = Vector3.ZERO
var _throw_right_local:      Vector3 = Vector3.ZERO
var _throw_left_pole_local:  Vector3 = Vector3.ZERO
var _throw_right_pole_local: Vector3 = Vector3.ZERO

func setup(anim: AnimationModifiers) -> void:
	anim_mod = anim

# Llamado antes de procedural_animator.update(), en espacio local
func update_arm_compress(jump_squat_t: float, crouch_t: float) -> void:
	var rb           := bi.char_rigidbody
	var arm_bentness := bi.entity_instantiation.arch_final.arm_bentness
	var remaining    := 1.0 - arm_bentness
	var raw: float   = jump_squat_t * ARM_COMPRESS_JUMP \
		+ crouch_t * ARM_COMPRESS_CROUCH \
		+ max(0.0, rb.impact_y) * ARM_COMPRESS_IMPACT
	bi.locomotion_signals.arm_compress = clamp(raw * remaining, 0.0, remaining)

# Llamado después de convertir a global positions, antes del solve IK
func apply_world_overrides(delta: float) -> void:
	_apply_throw_arms(delta)
	_apply_grab_arms()

func _apply_throw_arms(delta: float) -> void:
	if not is_instance_valid(anim_mod):
		return
	var throw_t      := anim_mod.throw_t
	var throw_push_t := anim_mod.throw_push_t
	if throw_t <= 0.0 and throw_push_t <= 0.0:
		_sync_throw_locals_to_current()
		return

	var ik         := bi.ik_util
	var sizes      := bi.skel_sizes_util
	var cb         := bi.custom_bones_util
	var rb         := bi.char_rigidbody
	var cam        := bi.player_camera
	var arm_total  := sizes.upper_arm_size.y + sizes.lower_arm_size.y
	var char_basis     := rb.global_transform.basis
	var char_basis_inv := char_basis.inverse()
	var char_right := char_basis.x
	var char_up    := char_basis.y
	var left_shoulder_pos  := cb.left_upper_arm.global_position
	var right_shoulder_pos := cb.right_upper_arm.global_position
	var pitch      := cam.rotation.x if is_instance_valid(cam) else 0.0
	var pitch_norm : float = clamp(pitch / 1.2, -1.0, 1.0)
	var throw_dir  := anim_mod.throw_world_dir
	var blend_t: float

	if throw_push_t > 0.0:
		var hand_sep     := sizes.shoulders_width * 0.35 * lerpf(1.0, 0.4, abs(pitch_norm))
		var left_dir     := (throw_dir - char_right * (hand_sep / arm_total)).normalized()
		var right_dir    := (throw_dir + char_right * (hand_sep / arm_total)).normalized()
		var left_world   := left_shoulder_pos  + left_dir  * arm_total * 1.5
		var right_world  := right_shoulder_pos + right_dir * arm_total * 1.5
		var elbow_drop   := -char_up * arm_total * 0.4
		var left_pole_world  := left_world  + elbow_drop - throw_dir * arm_total * 0.3
		var right_pole_world := right_world + elbow_drop - throw_dir * arm_total * 0.3
		var k : float = clamp(delta * THROW_PUSH_SMOOTH, 0.0, 1.0)
		_throw_left_local       = _throw_left_local.lerp(       char_basis_inv * (left_world       - left_shoulder_pos),  k)
		_throw_right_local      = _throw_right_local.lerp(      char_basis_inv * (right_world      - right_shoulder_pos), k)
		_throw_left_pole_local  = _throw_left_pole_local.lerp(  char_basis_inv * (left_pole_world  - left_shoulder_pos),  k)
		_throw_right_pole_local = _throw_right_pole_local.lerp( char_basis_inv * (right_pole_world - right_shoulder_pos), k)
		blend_t = throw_push_t
	else:
		var vertical_shift := pitch * sizes.torso_height * 0.4
		var side_ext       := arm_total * 0.5 * lerpf(1.0, 0.4, abs(pitch_norm))
		var forward_pull   := throw_dir * arm_total * lerpf(0.0, 0.15, throw_t)
		var left_world     := left_shoulder_pos  - char_right * side_ext + forward_pull + char_up * vertical_shift
		var right_world    := right_shoulder_pos + char_right * side_ext + forward_pull + char_up * vertical_shift
		var pole_spread    : float = arm_total * (0.6 + abs(pitch_norm) * 0.4)
		var elbow_back     := -throw_dir * arm_total * 0.4
		var elbow_down     := -char_up * arm_total * (0.25 + pitch_norm * 0.2)
		var left_pole_world  := left_shoulder_pos  + elbow_back + elbow_down - char_right * pole_spread + char_up * vertical_shift
		var right_pole_world := right_shoulder_pos + elbow_back + elbow_down + char_right * pole_spread + char_up * vertical_shift
		var k : float = clamp(delta * THROW_CHARGE_SMOOTH, 0.0, 1.0)
		_throw_left_local       = _throw_left_local.lerp(       char_basis_inv * (left_world       - left_shoulder_pos),  k)
		_throw_right_local      = _throw_right_local.lerp(      char_basis_inv * (right_world      - right_shoulder_pos), k)
		_throw_left_pole_local  = _throw_left_pole_local.lerp(  char_basis_inv * (left_pole_world  - left_shoulder_pos),  k)
		_throw_right_pole_local = _throw_right_pole_local.lerp( char_basis_inv * (right_pole_world - right_shoulder_pos), k)
		blend_t = throw_t

	var left_ws       := left_shoulder_pos  + char_basis * _throw_left_local
	var right_ws      := right_shoulder_pos + char_basis * _throw_right_local
	var left_pole_ws  := left_shoulder_pos  + char_basis * _throw_left_pole_local
	var right_pole_ws := right_shoulder_pos + char_basis * _throw_right_pole_local

	var ik_l := bi.ik_util
	ik_l.left_arm_ik_target.global_position  = ik_l.left_arm_ik_target.global_position.lerp(left_ws,        blend_t)
	ik_l.right_arm_ik_target.global_position = ik_l.right_arm_ik_target.global_position.lerp(right_ws,      blend_t)
	ik_l.left_arm_pole.global_position       = ik_l.left_arm_pole.global_position.lerp(left_pole_ws,        blend_t)
	ik_l.right_arm_pole.global_position      = ik_l.right_arm_pole.global_position.lerp(right_pole_ws,      blend_t)

func _sync_throw_locals_to_current() -> void:
	var ik  := bi.ik_util
	var cb  := bi.custom_bones_util
	var inv := bi.char_rigidbody.global_transform.basis.inverse()
	_throw_left_local       = inv * (ik.left_arm_ik_target.global_position  - cb.left_upper_arm.global_position)
	_throw_right_local      = inv * (ik.right_arm_ik_target.global_position - cb.right_upper_arm.global_position)
	_throw_left_pole_local  = inv * (ik.left_arm_pole.global_position       - cb.left_upper_arm.global_position)
	_throw_right_pole_local = inv * (ik.right_arm_pole.global_position      - cb.right_upper_arm.global_position)

func _apply_grab_arms() -> void:
	if _grab_arm_blend <= 0.0:
		return
	var ik := bi.ik_util
	ik.left_arm_ik_target.global_position  = ik.left_arm_ik_target.global_position.lerp(
		_grab_left_handle_world,  _grab_arm_blend)
	ik.right_arm_ik_target.global_position = ik.right_arm_ik_target.global_position.lerp(
		_grab_right_handle_world, _grab_arm_blend)

func update_grab_handles(delta: float, grabbed: RigidBody3D, get_grabbable: Callable) -> void:
	var grabbable := get_grabbable.call(grabbed) as Grabbable
	if not grabbable:
		return
	var cb      := bi.custom_bones_util
	var left_h  := grabbable.get_nearest_handle_point(cb.left_upper_arm.global_position)
	var right_h := grabbable.get_nearest_handle_point(cb.right_upper_arm.global_position, left_h)

	if left_h != _grab_left_handle_node:
		_grab_left_prev_world  = _grab_left_handle_world
		_grab_left_handle_node = left_h
		_grab_left_blend_t     = 0.0
	if right_h != _grab_right_handle_node:
		_grab_right_prev_world  = _grab_right_handle_world
		_grab_right_handle_node = right_h
		_grab_right_blend_t     = 0.0

	_grab_left_blend_t  = clamp(_grab_left_blend_t  + delta * HANDLE_SWITCH_SPEED, 0.0, 1.0)
	_grab_right_blend_t = clamp(_grab_right_blend_t + delta * HANDLE_SWITCH_SPEED, 0.0, 1.0)

	if is_instance_valid(left_h):
		_grab_left_handle_world  = _grab_left_prev_world.lerp(left_h.global_position,  _grab_left_blend_t)
	if is_instance_valid(right_h):
		_grab_right_handle_world = _grab_right_prev_world.lerp(right_h.global_position, _grab_right_blend_t)

func start_grab(grabbed: RigidBody3D, get_grabbable: Callable) -> void:
	var grabbable := get_grabbable.call(grabbed) as Grabbable
	if not grabbable:
		return
	var cb      := bi.custom_bones_util
	var left_h  := grabbable.get_nearest_handle_point(cb.left_upper_arm.global_position)
	var right_h := grabbable.get_nearest_handle_point(cb.right_upper_arm.global_position, left_h)
	_grab_left_handle_node  = left_h
	_grab_right_handle_node = right_h
	_grab_left_blend_t      = 1.0
	_grab_right_blend_t     = 1.0
	_grab_left_handle_world  = left_h.global_position  if is_instance_valid(left_h)  else cb.left_upper_arm.global_position
	_grab_right_handle_world = right_h.global_position if is_instance_valid(right_h) else cb.right_upper_arm.global_position
	_grab_left_prev_world    = _grab_left_handle_world
	_grab_right_prev_world   = _grab_right_handle_world
	var tw := bi.create_tween()
	tw.tween_property(self, "_grab_arm_blend", 1.0, 0.15)

func stop_grab() -> void:
	var tw := bi.create_tween()
	tw.tween_property(self, "_grab_arm_blend", 0.0, 0.15)
	_grab_left_handle_node  = null
	_grab_right_handle_node = null
