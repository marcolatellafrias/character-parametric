class_name LocomotionSignals

var ik_util: IkUtil
var char_rigidbody: CharacterRigidBody3D
var sizes: SkeletonSizesUtil

var foot_spread_unified: Vector2 = Vector2.ZERO
var step_progress: float = 0.0
var step_length_norm: float = 0.0
var horizontal_velocity_smooth: Vector2 = Vector2.ZERO
var vertical_velocity_smooth: float = 0.0
var foot_spread_norm: Vector2 = Vector2.ZERO
var left_foot_local_norm: Vector2 = Vector2.ZERO
var right_foot_local_norm: Vector2 = Vector2.ZERO
var speed_norm: float = 0.0

const H_SMOOTH: float = 8.0
const V_SMOOTH: float = 6.0
const SPREAD_SMOOTH: float = 10.0

static func create(ik: IkUtil, rb: CharacterRigidBody3D, sz: SkeletonSizesUtil) -> LocomotionSignals:
	var s := LocomotionSignals.new()
	s.ik_util = ik
	s.char_rigidbody = rb
	s.sizes = sz
	return s

func update(delta: float) -> void:
	_update_step_signals(delta)
	_update_velocity_signals(delta)

func _update_step_signals(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var best_arc := 0.0
	var best_len := step_length_norm
	for target in [ik_util.left_leg_current_target, ik_util.right_leg_current_target]:
		if not IkUtil._is_stepping(target):
			continue
		var start_time := float(target.get_meta("ik_step_start_time"))
		var duration := float(target.get_meta("ik_step_duration"))
		var from_pos := Vector3(target.get_meta("ik_step_from"))
		var to_pos := Vector3(target.get_meta("ik_step_to"))
		var raw: float = clamp((now - start_time) / duration, 0.0, 1.0)
		var arc := sin(raw * PI)
		if arc > best_arc:
			best_arc = arc
			var dist := Vector2(from_pos.x, from_pos.z).distance_to(Vector2(to_pos.x, to_pos.z))
			best_len = clamp(dist / sizes.leg_height, 0.0, 1.0)
	step_progress = best_arc
	step_length_norm = best_len

	var left_pos := ik_util.left_leg_current_target.global_position
	var right_pos := ik_util.right_leg_current_target.global_position
	var rest_x_separation := sizes.hips_width * 2.0
	var raw_spread := Vector2(
		max(0.0, abs(left_pos.x - right_pos.x) - rest_x_separation) / sizes.leg_height,
		abs(left_pos.z - right_pos.z) / sizes.leg_height
	)
	var k_s: float = clamp(delta * SPREAD_SMOOTH, 0.0, 1.0)
	foot_spread_norm = foot_spread_norm.lerp(raw_spread.clamp(Vector2.ZERO, Vector2.ONE), k_s)

	var basis_inv := char_rigidbody.global_transform.basis.inverse()
	var left_local := basis_inv * (ik_util.left_leg_current_target.global_position - char_rigidbody.global_position)
	var right_local := basis_inv * (ik_util.right_leg_current_target.global_position - char_rigidbody.global_position)
	left_foot_local_norm = Vector2(left_local.x, left_local.z) / sizes.leg_height
	right_foot_local_norm = Vector2(right_local.x, right_local.z) / sizes.leg_height

	var left_rest_x := -sizes.hips_width
	var right_rest_x := sizes.hips_width
	var left_offset: float = (left_local.x - left_rest_x) / sizes.leg_height
	var right_offset: float = (right_local.x - right_rest_x) / sizes.leg_height
	foot_spread_unified = Vector2(
		clamp(right_offset - left_offset, -1.0, 1.0),
		clamp((left_foot_local_norm.y - right_foot_local_norm.y) / 2.0, -1.0, 1.0)
	)

func _update_velocity_signals(delta: float) -> void:
	var vel := char_rigidbody.linear_velocity
	var local_vel := char_rigidbody.global_transform.basis.inverse() * Vector3(vel.x, 0.0, vel.z)
	var k_h: float = clamp(delta * H_SMOOTH, 0.0, 1.0)
	horizontal_velocity_smooth = horizontal_velocity_smooth.lerp(Vector2(local_vel.x, local_vel.z), k_h)
	var k_v: float = clamp(delta * V_SMOOTH, 0.0, 1.0)
	vertical_velocity_smooth = lerp(vertical_velocity_smooth, vel.y, k_v)
	var max_speed := sizes.leg_height * 3.0
	speed_norm = clamp(Vector2(vel.x, vel.z).length() / max_speed, 0.0, 1.0)
