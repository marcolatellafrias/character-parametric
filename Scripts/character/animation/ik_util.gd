class_name IkUtil

const STEP_DURATION_FACTOR := 1.0

class LegData:
	var raycast: RayCast3D
	var raycast_indicator: MeshInstance3D
	var next_target: Node3D
	var current_target: Node3D
	var airborne_target: Node3D
	var pole: Node3D
	var neutral_local: Vector3

var left_leg_raycast: RayCast3D
var right_leg_raycast: RayCast3D
var left_leg_raycast_indicator: MeshInstance3D
var right_leg_raycast_indicator: MeshInstance3D
var left_leg_raycast_indicator_b: MeshInstance3D
var right_leg_raycast_indicator_b: MeshInstance3D
var left_leg_raycast_indicator_c: MeshInstance3D
var right_leg_raycast_indicator_c: MeshInstance3D
var left_leg_raycast_indicator_d: MeshInstance3D
var right_leg_raycast_indicator_d: MeshInstance3D
var left_leg_pole: Node3D
var right_leg_pole: Node3D
const left_color: Color = Color(1, 0, 0)
const right_color: Color = Color(0, 1, 0)
const raycast_color: Color = Color(0, 0, 1)
const inactive_raycast_color: Color = Color(0.3, 0.3, 0.3)
var left_leg_next_target: Node3D
var right_leg_next_target: Node3D
var left_leg_current_target: Node3D
var right_leg_current_target: Node3D
var left_neutral_local: Vector3
var right_neutral_local: Vector3
var raycast_offset: Vector2 = Vector2.ZERO
var _step_radius_rendered: float = -1.0
var current_step_radius: float:
	set(value):
		current_step_radius = value
		# Actualizamos el anillo de debug aunque no sea el jugador activo, así en un proxy el step
		# radius se ve escalar con la velocidad (el valor ya escalaba; era solo la viz).
		if is_equal_approx(value, _step_radius_rendered) or not is_instance_valid(current_step_left_mesh_instance):
			return
		_step_radius_rendered = value
		current_step_left_mesh_instance.mesh  = DebugUtil.create_debug_ring_mesh(value)
		current_step_right_mesh_instance.mesh = DebugUtil.create_debug_ring_mesh(value)
	get:
		return current_step_radius
var left_leg_airborne_target: Node3D
var right_leg_airborne_target: Node3D
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
var debug_enabled: bool = true

func get_leg_data(left: bool) -> LegData:
	var d := LegData.new()
	d.raycast = left_leg_raycast if left else right_leg_raycast
	d.raycast_indicator = left_leg_raycast_indicator if left else right_leg_raycast_indicator
	d.next_target = left_leg_next_target if left else right_leg_next_target
	d.current_target = left_leg_current_target if left else right_leg_current_target
	d.airborne_target = left_leg_airborne_target if left else right_leg_airborne_target
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

	new_ik_util.left_leg_raycast_indicator_b = create_leg_raycast_indicator(sizes)
	new_ik_util.left_leg_raycast.add_child(new_ik_util.left_leg_raycast_indicator_b)
	new_ik_util.right_leg_raycast_indicator_b = create_leg_raycast_indicator(sizes)
	new_ik_util.right_leg_raycast.add_child(new_ik_util.right_leg_raycast_indicator_b)
	new_ik_util.left_leg_raycast_indicator_c = create_leg_raycast_indicator(sizes)
	new_ik_util.left_leg_raycast.add_child(new_ik_util.left_leg_raycast_indicator_c)
	new_ik_util.right_leg_raycast_indicator_c = create_leg_raycast_indicator(sizes)
	new_ik_util.right_leg_raycast.add_child(new_ik_util.right_leg_raycast_indicator_c)
	new_ik_util.left_leg_raycast_indicator_d = create_leg_raycast_indicator(sizes)
	new_ik_util.left_leg_raycast.add_child(new_ik_util.left_leg_raycast_indicator_d)
	new_ik_util.right_leg_raycast_indicator_d = create_leg_raycast_indicator(sizes)
	new_ik_util.right_leg_raycast.add_child(new_ik_util.right_leg_raycast_indicator_d)

	new_ik_util.left_leg_pole = create_pole(true, sizes, skeleton.local_targets)
	new_ik_util.right_leg_pole = create_pole(false, sizes, skeleton.local_targets)
	new_ik_util.left_leg_next_target  = IkUtil.create_next_target(-sizes.raycast_stance_offset, left_color,  sizes.raycast_leg_lenght)
	new_ik_util.right_leg_next_target = IkUtil.create_next_target( sizes.raycast_stance_offset, right_color, sizes.raycast_leg_lenght)
	new_ik_util.left_neutral_local = new_ik_util.left_leg_raycast.transform.origin
	new_ik_util.right_neutral_local = new_ik_util.right_leg_raycast.transform.origin
	new_ik_util.left_leg_current_target = IkUtil.create_ik_target(true, sizes.step_radius_min, sizes.step_radius_max, new_ik_util)
	new_ik_util.right_leg_current_target = IkUtil.create_ik_target(false, sizes.step_radius_min, sizes.step_radius_max, new_ik_util)
	new_ik_util.left_leg_airborne_target = IkUtil.create_simple_ik_target(true)
	new_ik_util.right_leg_airborne_target = IkUtil.create_simple_ik_target(false)
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
	pole.position = Vector3(horizontal_offset, 0, -sizes.pole_distance)
	pole.add_child(DebugUtil.create_debug_sphere(color))
	return pole

static func create_leg_raycast(left: bool, sizes: SkeletonSizesUtil) -> RayCast3D:
	var length := sizes.raycast_leg_lenght
	var x_offset: float = -sizes.raycast_stance_offset if left else sizes.raycast_stance_offset
	var raycast := RayCast3D.new()
	raycast.target_position = Vector3(0, -length, 0)
	raycast.translate(Vector3(x_offset, -sizes.raycast_start_y_offset, 0))
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
	left: bool, bones: CustomBonesUtil, sizes: SkeletonSizesUtil, inputs: AnimationInputs,
) -> void:
	var leg := get_leg_data(left)
	var upper_leg := bones.left_upper_leg if left else bones.right_upper_leg
	var lower_leg := bones.left_lower_leg if left else bones.right_lower_leg
	var step_radius := current_step_radius

	if not recovery_targets_locked:
		_update_stepping_foot(leg.current_target)
	var was_airborne: bool = leg.current_target.get_meta("was_airborne", false)

	var min_raycast_length: float   = sizes.raycast_leg_lenght
	var additional_length: float    = sizes.raycast_leg_lenght / 2.0
	var total_raycast_length: float = min_raycast_length + additional_length
	leg.raycast.target_position.y   = -(total_raycast_length - sizes.raycast_start_y_offset)
	var max_raycast_distance: float       = leg.raycast.target_position.length()
	var leg_reach_raycast_distance: float = sizes.leg_height - sizes.raycast_start_y_offset

	if debug_enabled:
		if left:
			left_leg_raycast_indicator   = DebugUtil.update_debug_line_mesh(left_leg_raycast_indicator,   total_raycast_length - sizes.raycast_start_y_offset)
			left_leg_raycast_indicator_b = DebugUtil.update_debug_line_mesh(left_leg_raycast_indicator_b, total_raycast_length - sizes.raycast_start_y_offset)
			left_leg_raycast_indicator_c = DebugUtil.update_debug_line_mesh(left_leg_raycast_indicator_c, total_raycast_length - sizes.raycast_start_y_offset)
			left_leg_raycast_indicator_d = DebugUtil.update_debug_line_mesh(left_leg_raycast_indicator_d, total_raycast_length - sizes.raycast_start_y_offset)
		else:
			right_leg_raycast_indicator   = DebugUtil.update_debug_line_mesh(right_leg_raycast_indicator,   total_raycast_length - sizes.raycast_start_y_offset)
			right_leg_raycast_indicator_b = DebugUtil.update_debug_line_mesh(right_leg_raycast_indicator_b, total_raycast_length - sizes.raycast_start_y_offset)
			right_leg_raycast_indicator_c = DebugUtil.update_debug_line_mesh(right_leg_raycast_indicator_c, total_raycast_length - sizes.raycast_start_y_offset)
			right_leg_raycast_indicator_d = DebugUtil.update_debug_line_mesh(right_leg_raycast_indicator_d, total_raycast_length - sizes.raycast_start_y_offset)

	var indicator_a := left_leg_raycast_indicator   if left else right_leg_raycast_indicator
	var indicator_b := left_leg_raycast_indicator_b if left else right_leg_raycast_indicator_b
	var indicator_c := left_leg_raycast_indicator_c if left else right_leg_raycast_indicator_c
	var indicator_d := left_leg_raycast_indicator_d if left else right_leg_raycast_indicator_d

	if not inputs.grounded:
		if not recovery_targets_locked:
			leg.current_target.set_meta("was_airborne", true)
			if not _is_stepping(leg.current_target):
				_tween_foot_to(leg.current_target, leg.current_target.global_position, leg.airborne_target.global_position, 0.0, sizes.step_height)
		_set_leg_measure(left, 0.0, false, leg.airborne_target.global_position)
		indicator_b.visible = false
		indicator_c.visible = false
		indicator_d.visible = false
		solve_two_bone_ik(upper_leg, lower_leg, leg.current_target.global_position, leg.pole.global_position)
		return

	indicator_b.visible = true
	indicator_c.visible = true
	indicator_d.visible = true

	var original_origin := leg.raycast.transform.origin

	var basis_owner := leg.raycast.get_parent() as Node3D
	var ground_world := inputs.ground_point
	var ground_local := basis_owner.global_transform.affine_inverse() * ground_world

	var candidate_origins: Array[Vector3] = [
		original_origin,
		Vector3(raycast_offset.x, leg.neutral_local.y,  raycast_offset.y),
		Vector3(raycast_offset.x, leg.neutral_local.y, leg.neutral_local.z + raycast_offset.y),
		Vector3(ground_local.x,   leg.neutral_local.y, ground_local.z),
	]

	var active_candidate_idx := -1
	var resolved := false

	for i in candidate_origins.size():
		leg.raycast.transform.origin = candidate_origins[i]
		leg.raycast.force_raycast_update()

		if not leg.raycast.is_colliding():
			continue

		var collision_point    := leg.raycast.get_collision_point()
		var collision_distance := leg.raycast.global_position.distance_to(collision_point)
		leg.raycast.transform.origin = original_origin
		active_candidate_idx = i

		if collision_distance >= leg_reach_raycast_distance:
			var t: float = clamp(
				(collision_distance - leg_reach_raycast_distance) / (max_raycast_distance - leg_reach_raycast_distance),
				0.0, 1.0
			)
			var interpolated_position := Vector3(
				leg.airborne_target.global_position.x,
				lerpf(collision_point.y, leg.airborne_target.global_position.y, t),
				leg.airborne_target.global_position.z
			)
			leg.next_target.global_position = interpolated_position

			if not recovery_targets_locked:
				leg.current_target.set_meta("was_airborne", true)
				if not _is_stepping(leg.current_target):
					_tween_foot_to(leg.current_target, leg.current_target.global_position, interpolated_position, 0.0, sizes.step_height * 0.5)
			_set_leg_measure(left, 0.0, false, interpolated_position)
		else:
			leg.next_target.global_position = collision_point

			if not recovery_targets_locked:
				if was_airborne:
					_clear_step_data(leg.current_target)
					leg.current_target.global_position = collision_point
					leg.current_target.set_meta("was_airborne", false)

				var dist2: float = (
					Vector2(leg.next_target.global_position.x, leg.next_target.global_position.z) -
					Vector2(leg.current_target.global_position.x, leg.current_target.global_position.z)
				).length_squared()

				var neutral_world := basis_owner.global_transform * leg.neutral_local

				var dist2Exp: float = (
					Vector2(leg.next_target.global_position.x, leg.next_target.global_position.z) -
					Vector2(neutral_world.x, neutral_world.z)
				).length_squared()

				var step_distance: float = sqrt(dist2Exp)
				var wants_step: bool     = dist2 > (step_radius * step_radius)
				var step_duration: float = get_step_duration(inputs, sizes, step_distance)
				var step_height: float   = sizes.step_height * clamp(step_distance / sizes.step_radius_max, 0.1, 1.0)

				_set_leg_measure(left, dist2, wants_step, collision_point, step_duration, step_height)
			else:
				_set_leg_measure(left, 0.0, false, collision_point)

		resolved = true
		break

	if not resolved:
		leg.raycast.transform.origin = original_origin
		if not recovery_targets_locked:
			leg.current_target.set_meta("was_airborne", true)
			if not _is_stepping(leg.current_target):
				_tween_foot_to(leg.current_target, leg.current_target.global_position, leg.airborne_target.global_position, 0.0, sizes.step_height)
		_set_leg_measure(left, 0.0, false, leg.airborne_target.global_position)

	var offset_b := candidate_origins[1] - original_origin
	var offset_c := candidate_origins[2] - original_origin
	var offset_d := candidate_origins[3] - original_origin
	indicator_b.position = Vector3(offset_b.x, indicator_b.position.y, offset_b.z)
	indicator_c.position = Vector3(offset_c.x, indicator_c.position.y, offset_c.z)
	indicator_d.position = Vector3(offset_d.x, indicator_d.position.y, offset_d.z)
	_set_indicator_color(indicator_a, raycast_color if active_candidate_idx == 0 else inactive_raycast_color)
	_set_indicator_color(indicator_b, raycast_color if active_candidate_idx == 1 else inactive_raycast_color)
	_set_indicator_color(indicator_c, raycast_color if active_candidate_idx == 2 else inactive_raycast_color)
	_set_indicator_color(indicator_d, raycast_color if active_candidate_idx == 3 else inactive_raycast_color)

	if not left and not recovery_targets_locked:
		_try_start_farther_leg(0.05, false)

	solve_two_bone_ik(upper_leg, lower_leg, leg.current_target.global_position, leg.pole.global_position)

static func _set_indicator_color(indicator: MeshInstance3D, color: Color) -> void:
	if not indicator.material_override is StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		indicator.material_override = mat
	(indicator.material_override as StandardMaterial3D).albedo_color = color

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
	var eased_xz := ease_in_out(progress)
	var eased_y  := ease_in_out(progress)
	var pos := from_pos.lerp(to_pos, eased_xz)
	pos.y += sin(eased_y * PI) * step_height
	node.global_position = pos
	if progress >= 1.0:
		node.global_position = to_pos
		_clear_step_data(node)

static func ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

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

func update_leg_raycast_offsets(inputs: AnimationInputs, delta: float, left: bool, sizes: SkeletonSizesUtil, entity_stats: EntityArchetype) -> void:
	var hvel := inputs.velocity
	hvel.y = 0.0

	var leg := get_leg_data(left)

	var basis_owner := leg.raycast.get_parent() as Node3D
	var local_vel: Vector3 = basis_owner.global_transform.basis.inverse() * hvel
	var v2 := Vector2(local_vel.x, local_vel.z)
	var speed := v2.length()
	var dir := (v2 / speed) if (speed > 0.0) else Vector2.ZERO

	var needed_offset := current_step_radius / STEP_DURATION_FACTOR
	var target_off := dir * needed_offset
	var weight_z := sizes.axis_weight_forward if v2.y <= 0.0 else sizes.axis_weight_backward
	target_off = Vector2(target_off.x * sizes.axis_weight_lateral, target_off.y * weight_z)

	var grounded_target := target_off if inputs.grounded else Vector2.ZERO
	var k: float = clamp(delta * sizes.raycast_smooth, 0.0, 1.0)
	raycast_offset = raycast_offset.lerp(grounded_target, k)

	var y_vel := inputs.velocity.y
	var velocity_factor: float = clamp(abs(y_vel) / 5.0, 0.0, 1.0)
	var target_y_position: float = lerp(sizes.leg_height * 0.5, sizes.leg_height, velocity_factor)

	leg.raycast.transform.origin = leg.neutral_local + Vector3(raycast_offset.x, 0.0, raycast_offset.y)
	leg.airborne_target.transform.origin = Vector3(
		leg.neutral_local.x,
		leg.neutral_local.y - target_y_position,
		leg.neutral_local.z
	)

static func get_orthogonal(v: Vector3) -> Vector3:
	if abs(v.x) < abs(v.y):
		return Vector3(0, -v.z, v.y).normalized()
	else:
		return Vector3(-v.z, 0, v.x).normalized()

func get_step_duration(inputs: AnimationInputs, sizes: SkeletonSizesUtil, step_distance: float) -> float:
	var dxz := Vector2(inputs.velocity.x, inputs.velocity.z)
	var horizontal_speed := dxz.length()
	if horizontal_speed < 0.01:
		return 0.3
	var step_duration := (step_distance / horizontal_speed) * STEP_DURATION_FACTOR
	var min_duration := 0.04 * sizes.leg_height
	var max_duration := 0.4 * sizes.leg_height
	return clamp(step_duration, min_duration, max_duration)
	
func reset_raycast_offset() -> void:
	raycast_offset = Vector2.ZERO

## Planta cada pie donde el raycast dice que va (current_target = next_target) y limpia el paso en
## curso. Se llama al SALIR de la recuperación: durante ella los targets están congelados
## (recovery_targets_locked), y sin esto los pies tienen que "alcanzar" al cuerpo a los pasos —
## lento, y peor en un proxy que corre el solve a media tasa (feet lag por unos segundos).
## TEMPORAL: estado de pasos para diagnosticar el feet-lag del proxy tras recuperarse.
func debug_step_state() -> String:
	return "step_radius=%.2f  L(wants=%s dist=%.2f stepping=%s)  R(wants=%s dist=%.2f stepping=%s)" % [
		current_step_radius,
		_left_wants_step,  sqrt(_left_dist2),  _is_stepping(left_leg_current_target),
		_right_wants_step, sqrt(_right_dist2), _is_stepping(right_leg_current_target)]

func reset_step_targets_to_ground() -> void:
	for pair in [[left_leg_current_target, left_leg_next_target], [right_leg_current_target, right_leg_next_target]]:
		var cur: Node3D = pair[0]
		var nxt: Node3D = pair[1]
		if is_instance_valid(cur) and is_instance_valid(nxt):
			cur.global_position = nxt.global_position
			_clear_step_data(cur)
