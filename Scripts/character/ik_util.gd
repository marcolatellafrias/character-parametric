class_name IkUtil

class LegData:
	var raycast: RayCast3D
	var raycast_indicator: MeshInstance3D
	var next_target: Node3D
	var current_target: Node3D
	var pole: Node3D
	var neutral_local: Vector3

var left_leg_raycast: RayCast3D
var right_leg_raycast: RayCast3D
var left_leg_raycast_indicator: MeshInstance3D
var right_leg_raycast_indicator: MeshInstance3D
var left_leg_pole: Node3D
var right_leg_pole: Node3D
const left_color: Color = Color(1, 0, 0)
const right_color: Color = Color(0, 1, 0)
const raycast_color: Color = Color(0, 0, 1)
var left_leg_next_target: Node3D
var right_leg_next_target: Node3D
var left_leg_current_target: Node3D
var right_leg_current_target: Node3D
var left_neutral_local: Vector3
var right_neutral_local: Vector3
var raycast_offset: Vector2 = Vector2.ZERO
var current_step_radius: float:
	set(value):
		current_step_radius = value
		current_step_left_mesh_instance.mesh = DebugUtil.create_debug_ring_mesh(current_step_radius)
		current_step_right_mesh_instance.mesh = DebugUtil.create_debug_ring_mesh(current_step_radius)
	get:
		return current_step_radius
var current_step_left_mesh_instance: MeshInstance3D
var current_step_right_mesh_instance: MeshInstance3D

var left_arm_ik_target: Node3D
var right_arm_ik_target: Node3D
var left_arm_pole: Node3D
var right_arm_pole: Node3D

var _left_dist2: float = 0.0
var _left_wants_step: bool = false
var _left_next_pos: Vector3 = Vector3.ZERO
var _left_step_duration: float = 0.3
var _left_step_height: float = 0.3
var _right_dist2: float = 0.0
var _right_wants_step: bool = false
var _right_next_pos: Vector3 = Vector3.ZERO
var _right_step_duration: float = 0.3
var _right_step_height: float = 0.3

var _last_step_time: float = -1.0
var _last_step_frame: int = -1
var _last_step_leg_id: int = -1

var recovery_targets_locked: bool = false

func get_leg_data(left: bool) -> LegData:
	var d := LegData.new()
	d.raycast = left_leg_raycast if left else right_leg_raycast
	d.raycast_indicator = left_leg_raycast_indicator if left else right_leg_raycast_indicator
	d.next_target = left_leg_next_target if left else right_leg_next_target
	d.current_target = left_leg_current_target if left else right_leg_current_target
	d.pole = left_leg_pole if left else right_leg_pole
	d.neutral_local = left_neutral_local if left else right_neutral_local
	return d

static func create(sizes: SkeletonSizesUtil, skeleton: BoneInstantiator) -> IkUtil:
	var new_ik_util = IkUtil.new()
	new_ik_util.left_leg_raycast = create_leg_raycast(true, sizes)
	new_ik_util.right_leg_raycast = create_leg_raycast(false, sizes)
	new_ik_util.left_leg_raycast_indicator = create_leg_raycast_indicator(sizes)
	new_ik_util.left_leg_raycast.add_child(new_ik_util.left_leg_raycast_indicator)
	new_ik_util.right_leg_raycast_indicator = create_leg_raycast_indicator(sizes)
	new_ik_util.right_leg_raycast.add_child(new_ik_util.right_leg_raycast_indicator)
	new_ik_util.left_leg_pole = create_pole(true, sizes, skeleton.local_targets)
	new_ik_util.right_leg_pole = create_pole(false, sizes, skeleton.local_targets)
	new_ik_util.left_leg_next_target  = IkUtil.create_next_target(-sizes.raycast_stance_offset, left_color,  sizes.raycast_leg_lenght)
	new_ik_util.right_leg_next_target = IkUtil.create_next_target( sizes.raycast_stance_offset, right_color, sizes.raycast_leg_lenght)
	new_ik_util.left_neutral_local = new_ik_util.left_leg_raycast.transform.origin
	new_ik_util.right_neutral_local = new_ik_util.right_leg_raycast.transform.origin
	new_ik_util.left_leg_current_target = IkUtil.create_ik_target(true, sizes.step_radius_min, sizes.step_radius_max, new_ik_util)
	new_ik_util.right_leg_current_target = IkUtil.create_ik_target(false, sizes.step_radius_min, sizes.step_radius_max, new_ik_util)
	new_ik_util.left_arm_ik_target  = IkUtil.create_simple_ik_target(true)
	new_ik_util.right_arm_ik_target = IkUtil.create_simple_ik_target(false)
	new_ik_util.left_arm_pole  = IkUtil.create_simple_ik_target(true)
	new_ik_util.right_arm_pole = IkUtil.create_simple_ik_target(false)
	return new_ik_util

static func create_pole(left: bool, sizes: SkeletonSizesUtil, local_targets: Node3D) -> Node3D:
	var color: Color = left_color if left else right_color
	var horizontal_offset: float = -sizes.hips_width if left else sizes.hips_width
	var pole := Node3D.new()
	local_targets.add_child(pole)
	pole.global_position = local_targets.global_position + Vector3(horizontal_offset, 0, 0) + Vector3(0, 0, -1) * sizes.pole_distance
	pole.add_child(DebugUtil.create_debug_sphere(color))
	return pole

static func create_leg_raycast(left: bool, sizes: SkeletonSizesUtil) -> RayCast3D:
	var length := sizes.raycast_leg_lenght
	var x_offset: float = -sizes.raycast_stance_offset if left else sizes.raycast_stance_offset
	var raycast := RayCast3D.new()
	raycast.target_position = Vector3(0, -length, 0)
	raycast.translate(Vector3(x_offset, 0, 0))
	return raycast

static func create_leg_raycast_indicator(sizes: SkeletonSizesUtil) -> MeshInstance3D:
	return DebugUtil.create_debug_line(Color.BLUE, sizes.raycast_leg_lenght)

static func create_next_target(x_offset: float, color: Color, length: float) -> Node3D:
	var target := Node3D.new()
	target.position = Vector3(x_offset, -length, 0)
	target.add_child(DebugUtil.create_debug_sphere(color))
	return target

static func create_simple_ik_target(left: bool) -> Node3D:
	var color := left_color if left else right_color
	var _ik_target := Node3D.new()
	_ik_target.add_child(DebugUtil.create_debug_cube(color))
	return _ik_target

static func create_ik_target(left: bool, min_radius: float, max_radius: float, ik_util: IkUtil) -> Node3D:
	var color := left_color if left else right_color
	var _ik_target := Node3D.new()
	_ik_target.add_child(DebugUtil.create_debug_cube(color))
	_ik_target.add_child(DebugUtil.create_debug_ring(color, max_radius))
	var radius_disc: MeshInstance3D = DebugUtil.create_debug_ring(color, min_radius)
	_ik_target.add_child(radius_disc)
	if left:
		ik_util.current_step_left_mesh_instance = radius_disc
	else:
		ik_util.current_step_right_mesh_instance = radius_disc
	return _ik_target

func solve_two_bone_ik(upper_bone: CustomBone, lower_bone: CustomBone, ik_target: Vector3, pole_target: Vector3) -> void:
	var root_pos: Vector3 = upper_bone.global_position
	var target_pos: Vector3 = ik_target
	var upper_len: float = upper_bone.length
	var lower_len: float = lower_bone.length

	var root_to_target: Vector3 = target_pos - root_pos
	var clamped_len: float = clamp(root_to_target.length(), 0.001, upper_len + lower_len)
	var dir_to_target: Vector3 = root_to_target.normalized()

	var raw_pole := (pole_target - root_pos).normalized()
	var right_vec := dir_to_target.cross(raw_pole)
	if right_vec.length() < 1e-6:
		right_vec = get_orthogonal(dir_to_target)
	var bend_plane_normal := right_vec.normalized()
	var pole_on_plane := (bend_plane_normal.cross(dir_to_target)).normalized()

	var cosA: float = clamp((upper_len*upper_len + clamped_len*clamped_len - lower_len*lower_len) / (2.0 * upper_len * clamped_len), -1.0, 1.0)
	var sinA: float = sqrt(max(0.0, 1.0 - cosA * cosA))
	var knee_pos: Vector3 = root_pos + dir_to_target * (cosA * upper_len) + pole_on_plane * (sinA * upper_len)

	upper_bone.global_transform.basis = upper_bone.pose_from_rest_to((knee_pos - root_pos).normalized(), pole_on_plane)
	lower_bone.global_transform.basis = upper_bone.pose_from_rest_to((target_pos - knee_pos).normalized(), pole_on_plane)

func _set_leg_measure(left: bool, dist2: float, wants_step: bool, next_pos: Vector3, step_duration: float = 0.3, step_height: float = 0.3) -> void:
	if left:
		_left_dist2 = dist2
		_left_wants_step = wants_step
		_left_next_pos = next_pos
		_left_step_duration = step_duration
		_left_step_height = step_height
	else:
		_right_dist2 = dist2
		_right_wants_step = wants_step
		_right_next_pos = next_pos
		_right_step_duration = step_duration
		_right_step_height = step_height

func _try_start_farther_leg(step_cooldown: float, alternate: bool) -> void:
	var a := left_leg_current_target
	var b := right_leg_current_target
	if _is_stepping(a) or _is_stepping(b):
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_step_frame:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_step_time >= 0.0 and (now - _last_step_time) < step_cooldown:
		return
	if not _left_wants_step and not _right_wants_step:
		return

	var chosen := a
	var chosen_pos := _left_next_pos
	var chosen_dur := _left_step_duration
	var chosen_height := _left_step_height

	if _left_wants_step and not _right_wants_step:
		pass
	elif _right_wants_step and not _left_wants_step:
		chosen = b; chosen_pos = _right_next_pos; chosen_dur = _right_step_duration; chosen_height = _right_step_height
	else:
		var eps := 1e-6
		if _right_dist2 > _left_dist2 + eps:
			chosen = b; chosen_pos = _right_next_pos; chosen_dur = _right_step_duration; chosen_height = _right_step_height
		elif abs(_left_dist2 - _right_dist2) <= eps and alternate and _last_step_leg_id == a.get_instance_id():
			chosen = b; chosen_pos = _right_next_pos; chosen_dur = _right_step_duration; chosen_height = _right_step_height

	_register_step(chosen)
	_tween_foot_to(chosen, chosen.global_position, chosen_pos, max(chosen_dur, 0.01), chosen_height)

func _register_step(current_target: Node3D) -> void:
	_last_step_time = Time.get_ticks_msec() / 1000.0
	_last_step_frame = Engine.get_physics_frames()
	_last_step_leg_id = current_target.get_instance_id()

func update_ik_raycast(
	left: bool, bones: CustomBonesUtil, sizes: SkeletonSizesUtil, char_rigidbody: CharacterRigidBody3D,
) -> void:
	var leg := get_leg_data(left)
	var upper_leg := bones.left_upper_leg if left else bones.right_upper_leg
	var lower_leg := bones.left_lower_leg if left else bones.right_lower_leg
	var step_radius := current_step_radius

	if not recovery_targets_locked:
		_update_stepping_foot(leg.current_target)

	var total_raycast_length: float = sizes.raycast_leg_lenght + sizes.raycast_leg_lenght / 2.0
	leg.raycast.target_position.y = -total_raycast_length

	if left:
		left_leg_raycast_indicator = DebugUtil.update_debug_line_mesh(left_leg_raycast_indicator, total_raycast_length)
	else:
		right_leg_raycast_indicator = DebugUtil.update_debug_line_mesh(right_leg_raycast_indicator, total_raycast_length)

	leg.raycast.force_raycast_update()

	var raycast_in_range: bool = char_rigidbody.is_grounded and leg.raycast.is_colliding()

	if raycast_in_range:
		var collision_point: Vector3 = leg.raycast.get_collision_point()
		leg.next_target.global_position = collision_point

		if not recovery_targets_locked:
			var dist2: float = (
				Vector2(collision_point.x, collision_point.z) -
				Vector2(leg.current_target.global_position.x, leg.current_target.global_position.z)
			).length_squared()

			var basis_owner   := leg.raycast.get_parent() as Node3D
			var neutral_world := basis_owner.global_transform * leg.neutral_local

			var dist2Exp: float = (
				Vector2(collision_point.x, collision_point.z) -
				Vector2(neutral_world.x, neutral_world.z)
			).length_squared()

			var step_distance: float = sqrt(dist2Exp)
			var wants_step: bool     = dist2 > (step_radius * step_radius)
			var step_duration: float = get_step_duration(char_rigidbody, sizes, step_distance)
			var step_height: float   = sizes.step_height * clamp(step_distance / sizes.step_radius_max, 0.1, 1.0)

			_set_leg_measure(left, dist2, wants_step, collision_point, step_duration, step_height)
		else:
			_set_leg_measure(left, 0.0, false, collision_point)
	else:
		var rest_pos := _compute_rest_position(leg, sizes)
		leg.next_target.global_position = rest_pos
		if not recovery_targets_locked:
			_clear_step_data(leg.current_target)
			leg.current_target.global_position = rest_pos
		_set_leg_measure(left, 0.0, false, rest_pos)

	if not left and not recovery_targets_locked:
		_try_start_farther_leg(0.05, false)

	solve_two_bone_ik(upper_leg, lower_leg, leg.current_target.global_position, leg.pole.global_position)

func _compute_rest_position(leg: LegData, sizes: SkeletonSizesUtil) -> Vector3:
	var basis_owner := leg.raycast.get_parent() as Node3D
	var local_rest := Vector3(leg.neutral_local.x, leg.neutral_local.y - sizes.leg_height, leg.neutral_local.z)
	return basis_owner.global_transform * local_rest

static func _tween_foot_to(node: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float, step_height: float) -> void:
	if duration <= 0.0 or from_pos.is_equal_approx(to_pos):
		node.global_position = to_pos
		_clear_step_data(node)
		return
	node.set_meta("stepping", true)
	node.set_meta("ik_step_start_time", Time.get_ticks_msec() / 1000.0)
	node.set_meta("ik_step_duration", duration)
	node.set_meta("ik_step_from", from_pos)
	node.set_meta("ik_step_to", to_pos)
	node.set_meta("ik_step_height", step_height)

static func _update_stepping_foot(node: Node3D) -> void:
	if not _is_stepping(node):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var start_time := float(node.get_meta("ik_step_start_time"))
	var duration := float(node.get_meta("ik_step_duration"))
	var from_pos := Vector3(node.get_meta("ik_step_from"))
	var to_pos := Vector3(node.get_meta("ik_step_to"))
	var step_height := float(node.get_meta("ik_step_height"))
	var progress: float = clamp((now - start_time) / duration, 0.0, 1.0)
	var eased_progress := ease_out_sine(progress)
	var pos := from_pos.lerp(to_pos, eased_progress)
	pos.y += sin(eased_progress * PI) * step_height
	node.global_position = pos
	if progress >= 1.0:
		node.global_position = to_pos
		_clear_step_data(node)

static func ease_out_sine(t: float) -> float:
	return sin(t * PI * 0.5)

static func _clear_step_data(node: Node3D) -> void:
	node.set_meta("stepping", false)
	node.remove_meta("ik_step_start_time")
	node.remove_meta("ik_step_duration")
	node.remove_meta("ik_step_from")
	node.remove_meta("ik_step_to")
	node.remove_meta("ik_step_height")

static func _is_stepping(n: Node) -> bool:
	return n.has_meta("stepping") and bool(n.get_meta("stepping"))

func update_leg_raycast_offsets(root_rigidbody: RigidBody3D, delta: float, left: bool, sizes: SkeletonSizesUtil, entity_stats: EntityArchetype) -> void:
	var leg := get_leg_data(left)

	if not (root_rigidbody as CharacterRigidBody3D).is_grounded:
		raycast_offset = Vector2.ZERO
		leg.raycast.transform.origin = leg.neutral_local
		return

	var hvel := root_rigidbody.linear_velocity
	hvel.y = 0.0

	var basis_owner := leg.raycast.get_parent() as Node3D
	var local_vel: Vector3 = basis_owner.global_transform.basis.inverse() * hvel
	var v2 := Vector2(local_vel.x, local_vel.z)
	var speed := v2.length()
	var dir := (v2 / speed) if (speed > 0.0) else Vector2.ZERO
	var n: float = clamp(speed / sizes.speed_for_max, 0.0, 1.0)
	var curve_gain: float = sizes.speed_curve.sample_baked(n) if (sizes.speed_curve != null) else n
	var amount := sizes.raycast_amount * curve_gain
	var target_off := dir * (amount * sizes.raycast_max_offset)
	target_off = Vector2(target_off.x * sizes.axis_weights.x, target_off.y * sizes.axis_weights.y)
	var k: float = clamp(delta * sizes.raycast_smooth, 0.0, 1.0)
	raycast_offset = raycast_offset.lerp(target_off, k)

	leg.raycast.transform.origin = leg.neutral_local + Vector3(raycast_offset.x, 0.0, raycast_offset.y)

static func get_orthogonal(v: Vector3) -> Vector3:
	if abs(v.x) < abs(v.y):
		return Vector3(0, -v.z, v.y).normalized()
	else:
		return Vector3(-v.z, 0, v.x).normalized()

func get_step_duration(char_rigidbody: CharacterRigidBody3D, sizes: SkeletonSizesUtil, step_distance: float) -> float:
	var dxz := Vector2(char_rigidbody.linear_velocity.x, char_rigidbody.linear_velocity.z)
	var horizontal_speed := dxz.length()
	if horizontal_speed < 0.01:
		return 0.3
	var step_duration := (step_distance / horizontal_speed) * 0.8
	var min_duration := 0.04 * sizes.leg_height
	var max_duration := 0.4 * sizes.leg_height
	return clamp(step_duration, min_duration, max_duration)
