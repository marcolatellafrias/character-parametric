class_name IkUtil

static func create_pole(lower_leg: CustomBone, distance: float, color: Color, parent: Node) -> Node3D:
	var pole := Node3D.new()
	parent.add_child(pole) # parent first so global == what you expect
	var fwd := (lower_leg.global_basis.z).normalized() # Godot forward is -Z
	pole.global_position = lower_leg.global_transform.origin + fwd * distance
	pole.add_child(DebugUtil.create_debug_sphere(color))
	return pole

static func create_leg_raycast(x_offset: float, color: Color, length: float) -> RayCast3D:
	var raycast = RayCast3D.new()
	raycast.target_position = Vector3(0, -length, 0)
	raycast.add_child(DebugUtil.create_debug_line(color, length))
	raycast.translate(Vector3(x_offset, 0, 0))
	return raycast

static func create_next_target(x_offset: float, color: Color, length: float) -> Node3D:
	var target = Node3D.new()
	target.position = Vector3(x_offset, -length, 0)
	target.add_child(DebugUtil.create_debug_sphere(color))
	return target

static func create_ik_target(color: Color, walk_radius: float, turn_radius: float) -> Node3D:
	var _ik_target = Node3D.new()
	_ik_target.add_child(DebugUtil.create_debug_cube(color))
	_ik_target.add_child(DebugUtil.create_debug_ring(color,walk_radius))
	_ik_target.add_child(DebugUtil.create_debug_ring(color,turn_radius))
	return _ik_target

static func solve_leg_ik(upper_bone: CustomBone, lower_bone: CustomBone, ik_target: Vector3, pole_target: Vector3) -> void:
	var root_pos  : Vector3 = upper_bone.global_position
	var target_pos: Vector3 = ik_target
	var upper_len : float   = upper_bone.length
	var lower_len : float   = lower_bone.length

	# ---- Direction & reach ----
	var root_to_target = target_pos - root_pos
	var total_len = root_to_target.length()
	var clamped_len = clamp(total_len, 0.001, upper_len + lower_len)
	var dir_to_target = root_to_target.normalized()

	# ---- Bend plane using pole ----
	var raw_pole = (pole_target - root_pos).normalized()
	var right_vec = dir_to_target.cross(raw_pole)
	if right_vec.length() < 1e-6:
		right_vec = dir_to_target.orthogonal()
	var bend_plane_normal = right_vec.normalized()
	var pole_on_plane = (bend_plane_normal.cross(dir_to_target)).normalized()

	# ---- Knee position (law of cosines) ----
	var a = upper_len
	var b = lower_len
	var c = clamped_len
	var cosA = clamp((a*a + c*c - b*b) / (2.0 * a * c), -1.0, 1.0)
	var sinA = sqrt(max(0.0, 1.0 - cosA * cosA))
	var knee_pos = root_pos + dir_to_target * (cosA * a) + pole_on_plane * (sinA * a)

	# ---- Segment directions ----
	var upper_dir = (knee_pos - root_pos).normalized()
	var lower_dir = (target_pos - knee_pos).normalized()

	upper_bone.global_transform.basis = upper_bone.pose_from_rest_to(upper_dir, pole_on_plane)
	lower_bone.global_transform.basis = upper_bone.pose_from_rest_to(lower_dir, pole_on_plane)


# --- Guardas compartidas entre ambas piernas (por script/clase) ---
static var _last_step_time: float = -1.0
static var _last_step_frame: int = -1
static var _last_step_leg_id: int = -1  # usamos instance_id() del current_target

# --- IK update con arbitraje por frame + alternancia -------------
static func update_ik_raycast(
	raycast: RayCast3D, next_target: Node3D, current_target: Node3D,
	upper_leg: CustomBone, lower_leg: CustomBone, pole: Node3D,
	opposite_target: Node3D, step_radius: float, step_height: float, step_speed: float,
	# knobs nuevos (opcionales)
	step_cooldown: float = 0.01,           # seg mínimos entre inicios de pasos
	alternate: bool = true                 # alternar prioridad entre piernas
) -> Node3D:
	raycast.force_raycast_update()

	if raycast.is_colliding():
		var collision_point: Vector3 = raycast.get_collision_point()
		next_target.global_position = collision_point

		# Distancia al target en XZ (cuadrada)
		var dist2 := (
			Vector2(next_target.global_position.x, next_target.global_position.z) -
			Vector2(current_target.global_position.x, current_target.global_position.z)
		).length_squared()

		var wants_step := dist2 > (step_radius * step_radius)

		if wants_step and _can_start_step(current_target, opposite_target, step_cooldown, alternate):
			var dist: float = current_target.global_position.distance_to(next_target.global_position)
			var duration: float = clamp(dist / step_speed, 0.06, 0.25)

			_register_step(current_target) # registra arbitraje (frame/tiempo/leg)

			_tween_foot_to(current_target, current_target.global_position, collision_point, duration, step_height)

	else:
		# Snap solo si no estamos en medio del paso
		if not _is_stepping(current_target):
			_tween_foot_to(current_target, current_target.global_position, next_target.global_position, 0.0, step_height)

	solve_leg_ik(upper_leg, lower_leg, current_target.global_position, pole.global_position)
	return current_target


# --- Helpers de arbitraje ---
static func _can_start_step(current_target: Node3D, opposite_target: Node3D, step_cooldown: float, alternate: bool) -> bool:
	# Si cualquiera está pisando, no arranques otro
	if _is_stepping(current_target) or _is_stepping(opposite_target):
		return false

	# Solo un inicio de paso por frame de física (evita doble disparo por orden de update)
	var frame := Engine.get_physics_frames()
	if frame == _last_step_frame:
		return false

	# Respetar cooldown mínimo global (ritmo más parejo)
	var now := Time.get_ticks_msec() / 1000.0
	if _last_step_time >= 0.0 and (now - _last_step_time) < step_cooldown:
		return false

	# Alternar prioridad: si la última pierna que inició fue esta misma, cedé el turno
	if alternate and _last_step_leg_id == current_target.get_instance_id():
		return false

	return true


static func _register_step(current_target: Node3D) -> void:
	_last_step_time = Time.get_ticks_msec() / 1000.0
	_last_step_frame = Engine.get_physics_frames()
	_last_step_leg_id = current_target.get_instance_id()


static func _tween_foot_to(node: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float, step_height: float) -> void:
	# Kill any in-flight tween for this node
	if node.has_meta("ik_tween"):
		var old: Tween = node.get_meta("ik_tween")
		if old and old.is_running():
			old.kill()

	# Instant snap: no tween, clear flags
	if duration <= 0.0 or from_pos.is_equal_approx(to_pos):
		node.global_position = to_pos
		node.set_meta("ik_tween", null)
		node.set_meta("stepping", false)
		return

	var tween := node.get_tree().create_tween()
	#var tween : = get_tree().create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	node.set_meta("ik_tween", tween)
	node.set_meta("stepping", true) # mark as stepping while tween runs

	var from := from_pos
	var to   := to_pos

	# Tween with a small vertical arc using tween_method
	tween.tween_method(
		func(p: float) -> void:
			# p goes 0..1 — lerp on XZ and add a soft arc on Y
			var pos := from.lerp(to, p)
			pos.y += sin(p * PI) * step_height
			node.global_position = pos
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Cleanup metas when finished
	tween.finished.connect(func() -> void:
		node.set_meta("ik_tween", null)
		node.set_meta("stepping", false)
	)
	
static func _is_stepping(n: Node) -> bool:
	return n.has_meta("stepping") and bool(n.get_meta("stepping"))

static func _mark_stepping(n: Node, stepping: bool) -> void:
	n.set_meta("stepping", stepping)


# ---------------- BIPED IK ARBITER ----------------
# Call this once per physics frame.
# Notes:
# - Left/Right "current" are your planted foot targets (the tweened ones).
# - Left/Right "next" are the instantaneous raycast hits you already compute.
# - `solve_leg_ik` is your solver. `_tween_foot_to` / _is_stepping are the ones you posted.

static func update_biped_center_gate(
	char: CharacterBody3D,
	left_raycast: RayCast3D, left_next: Node3D, left_current: Node3D,
	right_raycast: RayCast3D, right_next: Node3D, right_current: Node3D,
	upperL: CustomBone, lowerL: CustomBone, poleL: Node3D,
	upperR: CustomBone, lowerR: CustomBone, poleR: Node3D,
	avg_start_radius: float,         # when avg(feet) is farther than this -> request a step
	avg_release_radius: float,       # when avg(feet) comes back within this -> release the gate (hysteresis)
	per_foot_trigger_radius: float,  # foot must be at least this far from its next hit to justify stepping
	step_height: float,
	step_speed: float,
	cooldown_s: float = 0.08
) -> void:
	# 1) Update both raycasts -> next targets
	left_raycast.force_raycast_update()
	right_raycast.force_raycast_update()

	if left_raycast.is_colliding():
		left_next.global_position = left_raycast.get_collision_point()
	if right_raycast.is_colliding():
		right_next.global_position = right_raycast.get_collision_point()



	var body_xz := xz(char.global_position)
	var lc_xz   := xz(left_current.global_position)
	var rc_xz   := xz(right_current.global_position)
	var ln_xz   := xz(left_next.global_position)
	var rn_xz   := xz(right_next.global_position)

	# Center of planted feet
	var center_xz := (lc_xz + rc_xz) * 0.5
	var center_dev := center_xz.distance_to(body_xz)

	# 3) Hysteresis gate stored on the character
	var gate_active := bool(char.get_meta("avg_gate_active")) if char.has_meta("avg_gate_active") else false
	if not gate_active and center_dev > avg_start_radius:
		gate_active = true
	elif gate_active and center_dev < avg_release_radius:
		gate_active = false
	char.set_meta("avg_gate_active", gate_active)

	# 4) Simple global cooldown so steps don't chain too tightly
	var now_frames := Engine.get_physics_frames()
	var tps := float(Engine.get_physics_ticks_per_second())
	var cd_frames := int(ceil(cooldown_s * tps))
	var next_ok_frame := int(char.get_meta("next_step_ok_frame")) if char.has_meta("next_step_ok_frame") else 0
	var cooldown_ok := now_frames >= next_ok_frame

	# 5) Decide if we should step and which foot
	var left_stepping := _is_stepping(left_current)
	var right_stepping := _is_stepping(right_current)

	if gate_active and cooldown_ok and not left_stepping and not right_stepping:
		# distances of each planted foot to the body
		var dl := lc_xz.distance_to(body_xz)
		var dr := rc_xz.distance_to(body_xz)

		# also require that the selected foot has a meaningful delta to its next target
		var left_move_dist  := lc_xz.distance_to(ln_xz)
		var right_move_dist := rc_xz.distance_to(rn_xz)

		var pick_left := false
		if dl > dr:
			pick_left = left_move_dist > per_foot_trigger_radius
		else:
			pick_left = false
			if right_move_dist <= per_foot_trigger_radius and left_move_dist > per_foot_trigger_radius:
				pick_left = true

		if pick_left or right_move_dist <= per_foot_trigger_radius:
			# If both small, do nothing this frame (prevents micro steps)
			pass
		else:
			# 6) Launch the step tween for the chosen foot
			if pick_left:
				var dist := left_current.global_position.distance_to(left_next.global_position)
				var dur : float = clamp(dist / step_speed, 0.06, 0.25)
				_tween_foot_to(left_current, left_current.global_position, left_next.global_position, dur, step_height)
				char.set_meta("next_step_ok_frame", now_frames + cd_frames)
				char.set_meta("last_stepped", "L")
			else:
				var dist := right_current.global_position.distance_to(right_next.global_position)
				var dur : float = clamp(dist / step_speed, 0.06, 0.25)
				_tween_foot_to(right_current, right_current.global_position, right_next.global_position, dur, step_height)
				char.set_meta("next_step_ok_frame", now_frames + cd_frames)
				char.set_meta("last_stepped", "R")

	# 7) If a raycast loses ground, snap only when not mid-step (your behavior)
	if not left_raycast.is_colliding() and not _is_stepping(left_current):
		_tween_foot_to(left_current, left_current.global_position, left_next.global_position, 0.0, step_height)
	if not right_raycast.is_colliding() and not _is_stepping(right_current):
		_tween_foot_to(right_current, right_current.global_position, right_next.global_position, 0.0, step_height)

	# 8) Solve IK for both legs to the *planted* targets
	solve_leg_ik(upperL, lowerL, left_current.global_position, poleL.global_position)
	solve_leg_ik(upperR, lowerR, right_current.global_position, poleR.global_position)
	
		# 2) Compute XZ helpers
static func xz(v: Vector3) -> Vector2: return Vector2(v.x, v.z)
