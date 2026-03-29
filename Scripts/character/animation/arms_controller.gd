class_name ArmsController
extends Node

var bi: BoneInstantiator
var anim_mod: AnimationModifiers

const ARM_COMPRESS_CROUCH:       float = 1.35
const ARM_COMPRESS_JUMP:         float = 0.45
const ARM_COMPRESS_IMPACT:       float = 0.30
const ARM_FORWARD_SCALE:         float = 0.25
const ARM_BEND_SCALE:            float = 0.18
const THROW_CHARGE_SMOOTH:       float = 8.0
const THROW_PUSH_SMOOTH:         float = 14.0
const HANDLE_SWITCH_SPEED:       float = 8.0
const ARM_JUMP_EXTENSION_FACTOR: float = 0.35
const HANDLE_HYSTERESIS:         float = 1.5
const HANDLE_VERTICAL_WEIGHT:    float = 0.3
const GRAB_MIN_BEND_FACTOR:      float = 0.97
const GRAB_POLE_SMOOTH:          float = 10.0
const GRAB_BLEND_SPEED:          float = 6.0

const GRAB_ROOT_TILT_BACK:    float = 0.23
const GRAB_ROOT_TILT_FORWARD: float = 0.32

const GRAB_SHOULDER_Z_UP:      float = 0.65
const GRAB_SHOULDER_Z_DOWN:    float = 0.32
const GRAB_SHOULDER_Y_BACK:    float = 0.65
const GRAB_SHOULDER_Y_FORWARD: float = 0.85

var _grab_left_blend:  float = 0.0
var _grab_right_blend: float = 0.0
var _grab_left_blend_target:  float = 0.0
var _grab_right_blend_target: float = 0.0

var _grab_left_handle_world:  Vector3 = Vector3.ZERO
var _grab_right_handle_world: Vector3 = Vector3.ZERO
var _grab_left_handle_node:   Node3D  = null
var _grab_right_handle_node:  Node3D  = null
var _grab_left_blend_t:  float = 1.0
var _grab_right_blend_t: float = 1.0
var _grab_left_prev_world:  Vector3 = Vector3.ZERO
var _grab_right_prev_world: Vector3 = Vector3.ZERO

var _throw_left_local:       Vector3 = Vector3.ZERO
var _throw_right_local:      Vector3 = Vector3.ZERO
var _throw_left_pole_local:  Vector3 = Vector3.ZERO
var _throw_right_pole_local: Vector3 = Vector3.ZERO

var _grab_dist_min:         float   = 0.0
var _grab_dist_max:         float   = 1.0
var _grab_chest_rest_world: Vector3 = Vector3.ZERO
var _grab_point_world:      Vector3 = Vector3.ZERO

const GRAB_POLE_SIDE_OFFSET: float = 3.0

func setup(anim: AnimationModifiers) -> void:
	anim_mod = anim

func update_arm_compress(jump_squat_t: float, crouch_t: float) -> void:
	var rb           := bi.char_rigidbody
	var arm_bentness := bi.entity_instantiation.arch_final.arm_bentness
	var remaining    := 1.0 - arm_bentness
	var raw: float   = jump_squat_t * ARM_COMPRESS_JUMP \
		+ crouch_t * ARM_COMPRESS_CROUCH \
		+ max(0.0, rb.impact_y) * ARM_COMPRESS_IMPACT
	bi.locomotion_signals.arm_compress = clamp(raw * remaining, 0.0, remaining)

func apply_world_overrides(delta: float) -> void:
	_apply_throw_arms(delta)
	_apply_grab_arms(delta)

func _weighted_dist(a: Vector3, b: Vector3) -> float:
	var diff := a - b
	diff.y *= HANDLE_VERTICAL_WEIGHT
	return diff.length()

func _best_handle(interactable: Interactable, shoulder: Vector3, exclude: Node3D, current: Node3D, is_left: bool) -> Node3D:
	var char_right   := bi.char_rigidbody.global_transform.basis.x
	var obj_center   := interactable.global_position
	var correct_sign := -1.0 if is_left else 1.0

	var best: Node3D = null
	var best_dist := INF
	for h in interactable.handle_points:
		if h == exclude:
			continue
		var d := _weighted_dist(h.global_position, shoulder)
		var lateral := (h.global_position - obj_center).dot(char_right) * correct_sign
		if lateral < 0.0:
			d -= lateral * 2.0
		if d < best_dist:
			best = h
			best_dist = d

	if not is_instance_valid(best):
		return current
	if is_instance_valid(current) and current != exclude:
		var current_dist := _weighted_dist(current.global_position, shoulder)
		var current_lateral := (current.global_position - obj_center).dot(char_right) * correct_sign
		if current_lateral < 0.0:
			current_dist -= current_lateral * 2.0
		if best_dist >= current_dist / HANDLE_HYSTERESIS:
			return current
	return best

func update_grab_handles(delta: float, interactable: Interactable, chest_rest_world: Vector3, grab_point: Node3D) -> void:
	_grab_chest_rest_world = chest_rest_world
	if is_instance_valid(grab_point):
		_grab_point_world = grab_point.global_position

	var cb      := bi.custom_bones_util
	var left_h  := _best_handle(interactable, cb.left_upper_arm.global_position,  null,   _grab_left_handle_node,  true)
	var right_h := _best_handle(interactable, cb.right_upper_arm.global_position, left_h, _grab_right_handle_node, false)

	_grab_left_blend_target  = 1.0 if is_instance_valid(left_h)  else 0.0
	_grab_right_blend_target = 1.0 if is_instance_valid(right_h) else 0.0

	var k :float= clamp(delta * GRAB_BLEND_SPEED, 0.0, 1.0)
	_grab_left_blend  = lerpf(_grab_left_blend,  _grab_left_blend_target,  k)
	_grab_right_blend = lerpf(_grab_right_blend, _grab_right_blend_target, k)

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

func start_grab(interactable: Interactable, chest_rest_world: Vector3, grab_point: Node3D, dist_min: float, dist_max: float) -> void:
	_grab_dist_min         = dist_min
	_grab_dist_max         = dist_max
	_grab_chest_rest_world = chest_rest_world
	_grab_point_world      = grab_point.global_position if is_instance_valid(grab_point) else chest_rest_world

	var cb      := bi.custom_bones_util
	var left_h  := _best_handle(interactable, cb.left_upper_arm.global_position,  null,   _grab_left_handle_node,  true)
	var right_h := _best_handle(interactable, cb.right_upper_arm.global_position, left_h, _grab_right_handle_node, false)

	_grab_left_handle_node  = left_h
	_grab_right_handle_node = right_h
	_grab_left_blend_t      = 1.0
	_grab_right_blend_t     = 1.0
	_grab_left_handle_world  = left_h.global_position  if is_instance_valid(left_h)  else cb.left_upper_arm.global_position
	_grab_right_handle_world = right_h.global_position if is_instance_valid(right_h) else cb.right_upper_arm.global_position
	_grab_left_prev_world    = _grab_left_handle_world
	_grab_right_prev_world   = _grab_right_handle_world

	_grab_left_blend_target  = 1.0 if is_instance_valid(left_h)  else 0.0
	_grab_right_blend_target = 1.0 if is_instance_valid(right_h) else 0.0
	_grab_left_blend  = _grab_left_blend_target
	_grab_right_blend = _grab_right_blend_target

func stop_grab() -> void:
	_grab_left_blend_target  = 0.0
	_grab_right_blend_target = 0.0
	_grab_left_handle_node   = null
	_grab_right_handle_node  = null

func _apply_grab_arms(delta: float) -> void:
	# Aun cuando los targets son 0, seguimos lerpeando los blends para la transicion de salida
	var k :float= clamp(delta * GRAB_BLEND_SPEED, 0.0, 1.0)
	_grab_left_blend  = lerpf(_grab_left_blend,  _grab_left_blend_target,  k)
	_grab_right_blend = lerpf(_grab_right_blend, _grab_right_blend_target, k)

	_apply_grab_body_adjustments()
	var ik    := bi.ik_util
	var cb    := bi.custom_bones_util
	var sizes := bi.skel_sizes_util
	_apply_arm_grab(delta, cb.left_upper_arm,  cb.left_lower_arm,  ik.left_arm_ik_target,  ik.left_arm_pole,  _grab_left_handle_world,  sizes, true,  _grab_left_blend)
	_apply_arm_grab(delta, cb.right_upper_arm, cb.right_lower_arm, ik.right_arm_ik_target, ik.right_arm_pole, _grab_right_handle_world, sizes, false, _grab_right_blend)

func _apply_grab_body_adjustments() -> void:
	var body_blend :float= max(_grab_left_blend, _grab_right_blend)
	if body_blend <= 0.0:
		return

	var cb    := bi.custom_bones_util
	var sizes := bi.skel_sizes_util

	var dist_l     := cb.left_upper_arm.global_position.distance_to(_grab_left_handle_world)
	var dist_r     := cb.right_upper_arm.global_position.distance_to(_grab_right_handle_world)
	var dist_range : float = max(_grab_dist_max - _grab_dist_min, 0.001)
	var t_l        : float = clamp((dist_l - _grab_dist_min) / dist_range, 0.0, 1.0) * _grab_left_blend
	var t_r        : float = clamp((dist_r - _grab_dist_min) / dist_range, 0.0, 1.0) * _grab_right_blend
	var t_avg      : float = (t_l + t_r) / max(_grab_left_blend + _grab_right_blend, 0.001)

	var root_tilt   := lerpf(-GRAB_ROOT_TILT_BACK, GRAB_ROOT_TILT_FORWARD, t_avg)
	var spine       := cb.lower_spine
	var spine_basis := spine.transform.basis
	var parent_basis := (spine.get_parent() as Node3D).global_transform.basis
	var local_world_right := spine_basis.inverse() * parent_basis.inverse() * bi.char_rigidbody.global_transform.basis.x
	spine.transform.basis *= Basis(local_world_right, -root_tilt * body_blend)

	var grab_y_rel := _grab_point_world.y - _grab_chest_rest_world.y
	var y_norm     : float = clamp(grab_y_rel / max(sizes.torso_height, 0.001), -1.0, 1.0)
	var shoulder_z := y_norm * (GRAB_SHOULDER_Z_UP if y_norm >= 0.0 else GRAB_SHOULDER_Z_DOWN)
	var shoulder_y_l := _grab_shoulder_y(t_l)
	var shoulder_y_r := _grab_shoulder_y(t_r)

	_apply_shoulder_rotation(cb.left_shoulder,  shoulder_y_l,  shoulder_z,  _grab_left_blend)
	_apply_shoulder_rotation(cb.right_shoulder, -shoulder_y_r, -shoulder_z, _grab_right_blend)

func _grab_shoulder_y(t: float) -> float:
	if t < 0.5:
		return lerpf(GRAB_SHOULDER_Y_BACK, 0.0, t * 2.0)
	else:
		return lerpf(0.0, -GRAB_SHOULDER_Y_FORWARD, (t - 0.5) * 2.0)

func _apply_shoulder_rotation(shoulder: CustomBone, y_angle: float, z_angle: float, blend: float) -> void:
	var local_basis         := shoulder.transform.basis
	var parent_basis        := (shoulder.get_parent() as Node3D).global_transform.basis
	var local_world_up      := local_basis.inverse() * parent_basis.inverse() * Vector3.UP
	var local_world_forward := local_basis.inverse() * parent_basis.inverse() * (-bi.char_rigidbody.global_transform.basis.z)
	shoulder.transform.basis *= Basis(local_world_up,      y_angle * blend)
	shoulder.transform.basis *= Basis(local_world_forward, z_angle * blend)

func _apply_arm_grab(delta: float, upper: CustomBone, lower: CustomBone, ik_target: Node3D, pole: Node3D, handle_world: Vector3, sizes: SkeletonSizesUtil, is_left: bool, blend: float) -> void:
	var nat_upper := sizes.upper_arm_size.y
	var nat_lower := sizes.lower_arm_size.y
	var nat_total := nat_upper + nat_lower
	var ratio     := nat_upper / nat_total

	var dist         := upper.global_position.distance_to(handle_world)
	var target_total : float = max(nat_total, dist / GRAB_MIN_BEND_FACTOR)
	var new_total    := lerpf(nat_total, target_total, blend)
	var new_upper_l  := new_total * ratio
	var new_lower_l  := new_total * (1.0 - ratio)

	upper.set_length(new_upper_l)
	lower.position  = Vector3(0.0, new_upper_l, 0.0)
	lower.set_length(new_lower_l)

	if blend <= 0.0:
		return

	ik_target.global_position = ik_target.global_position.lerp(handle_world, blend)

	var char_basis := bi.char_rigidbody.global_transform.basis
	var char_up    := char_basis.y
	var side_dir   := char_basis.x * (-1.0 if is_left else 1.0)
	var shoulder   := upper.global_position + side_dir * bi.skel_sizes_util.upper_arm_size.x * GRAB_POLE_SIDE_OFFSET
	var to_handle  := handle_world - shoulder
	var arm_plane_n := to_handle.cross(char_up)

	var elbow_dir: Vector3
	if arm_plane_n.length_squared() > 1e-6:
		elbow_dir = to_handle.cross(arm_plane_n).normalized()
	else:
		elbow_dir = -char_basis.z

	pole.global_position = shoulder + elbow_dir * new_upper_l * 1.5

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

	ik.left_arm_ik_target.global_position  = ik.left_arm_ik_target.global_position.lerp(left_ws,       blend_t)
	ik.right_arm_ik_target.global_position = ik.right_arm_ik_target.global_position.lerp(right_ws,     blend_t)
	ik.left_arm_pole.global_position       = ik.left_arm_pole.global_position.lerp(left_pole_ws,       blend_t)
	ik.right_arm_pole.global_position      = ik.right_arm_pole.global_position.lerp(right_pole_ws,     blend_t)

func _sync_throw_locals_to_current() -> void:
	var ik  := bi.ik_util
	var cb  := bi.custom_bones_util
	var inv := bi.char_rigidbody.global_transform.basis.inverse()
	_throw_left_local       = inv * (ik.left_arm_ik_target.global_position  - cb.left_upper_arm.global_position)
	_throw_right_local      = inv * (ik.right_arm_ik_target.global_position - cb.right_upper_arm.global_position)
	_throw_left_pole_local  = inv * (ik.left_arm_pole.global_position       - cb.left_upper_arm.global_position)
	_throw_right_pole_local = inv * (ik.right_arm_pole.global_position      - cb.right_upper_arm.global_position)
