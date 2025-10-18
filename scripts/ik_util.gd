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
# --- NUEVO: helpers para medir por pierna y arbitrar por distancia ---

static func _store_leg_measure(target: Node3D, dist2: float, wants_step: bool, next_pos: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	target.set_meta("_ik_frame", frame)
	target.set_meta("_ik_dist2", dist2)
	target.set_meta("_ik_wants", wants_step)
	target.set_meta("_ik_next_pos", next_pos)

static func _fresh_measure(target: Node3D) -> bool:
	return target.has_meta("_ik_frame") and int(target.get_meta("_ik_frame")) == Engine.get_physics_frames()

static func _try_start_farther_leg(
	a: Node3D, b: Node3D,
	step_height: float, step_duration: float,
	step_cooldown: float, alternate: bool
) -> void:
	# 1) Reglas globales: solo una pierna a la vez + cooldown + 1 inicio por frame
	if _is_stepping(a) or _is_stepping(b):
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_step_frame:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_step_time >= 0.0 and (now - _last_step_time) < step_cooldown:
		return

	# 2) Necesitamos que AMBAS piernas hayan medido en este frame
	if not _fresh_measure(a) or not _fresh_measure(b):
		return

	var wa := bool(a.get_meta("_ik_wants"))
	var wb := bool(b.get_meta("_ik_wants"))
	if not wa and not wb:
		return

	var chosen := a
	if wa and not wb:
		chosen = a
	elif wb and not wa:
		chosen = b
	else:
		var da := float(a.get_meta("_ik_dist2"))
		var db := float(b.get_meta("_ik_dist2"))
		var eps := 1e-6
		if db > da + eps:
			chosen = b
		elif abs(da - db) <= eps and alternate and _last_step_leg_id == chosen.get_instance_id():
			# desempate opcional: alternar si quedaron casi iguales
			chosen = b if (chosen == a) else a

	var start_pos: Vector3 = chosen.global_position
	var target_pos: Vector3 = chosen.get_meta("_ik_next_pos")
	# ANTES: var duration : float = clamp(dist / step_speed, 0.06, 0.25)
	var duration: float = max(step_duration, 0.01)  # fija; evitamos 0.0

	_register_step(chosen)
	_tween_foot_to(chosen, start_pos, target_pos, duration, step_height)

static func _register_step(current_target: Node3D) -> void:
	_last_step_time = Time.get_ticks_msec() / 1000.0
	_last_step_frame = Engine.get_physics_frames()
	_last_step_leg_id = current_target.get_instance_id()

# --- Reemplazo de tu update_ik_raycast (solo cambió el “arranque del paso”) ---
static func update_ik_raycast(
	raycast: RayCast3D, next_target: Node3D, current_target: Node3D,
	upper_leg: CustomBone, lower_leg: CustomBone, pole: Node3D,
	opposite_target: Node3D, step_radius: float, step_height: float, step_duration: float,
	step_cooldown: float = 0.01,           # seg mínimos entre inicios de pasos
	alternate: bool = false                # alternar prioridad entre piernas (solo para empates)
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

		# 👉 Guardamos la "propuesta" de esta pierna para arbitrar más tarde en el mismo frame
		_store_leg_measure(current_target, dist2, wants_step, collision_point)

	else:
		# Si no hay colisión, marcamos que esta pierna NO quiere paso en este frame,
		# pero igual guardamos datos frescos para que el árbitro pueda decidir.
		_store_leg_measure(current_target, 0.0, false, next_target.global_position)

		# Snap solo si no estamos en medio del paso
		if not _is_stepping(current_target):
			_tween_foot_to(current_target, current_target.global_position, next_target.global_position, 0.0, step_height)

	# 👉 Intentamos iniciar UN paso (como mucho) eligiendo la pierna más "atrasada"
	#    Este llamado puede ocurrir dos veces por frame (una por pierna),
	#    pero solo el segundo tendrá ambas mediciones frescas y disparará, a lo sumo, un paso.
	_try_start_farther_leg(current_target, opposite_target, step_height, step_duration, step_cooldown, alternate)

	solve_leg_ik(upper_leg, lower_leg, current_target.global_position, pole.global_position)
	return current_target


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



static func update_leg_raycast_offsets(character: CharacterBody3D, delta: float, leg_raycast : RayCast3D, speed_for_max: float, speed_curve: Curve, raycast_amount: float, raycast_max_offset: float, axis_weights: Vector2, raycast_smooth: float, neutral_local: Vector3, raycast_offset: Vector2) -> Vector2:
	# Velocidad horizontal
	var hvel := character.velocity
	hvel.y = 0.0

	# A espacio local del padre de raycasts
	var basis_owner := leg_raycast.get_parent() as Node3D
	var local_vel: Vector3 = basis_owner.global_transform.basis.inverse() * hvel

	var v2 := Vector2(local_vel.x, local_vel.z)
	var speed := v2.length()
	var dir := (v2 / speed) if (speed > 0.0) else Vector2.ZERO

	# Velocidad normalizada (0..1) y ganancia total
	var n : float = clamp(speed / speed_for_max, 0.0, 1.0)
	var curve_gain : = speed_curve.sample_baked(n) if (speed_curve != null) else n
	var amount := raycast_amount * curve_gain

	# Offset objetivo limitado por el radio máximo
	var target_off := dir * (amount * raycast_max_offset)
	target_off = Vector2(target_off.x * axis_weights.x, target_off.y * axis_weights.y)

	# Suavizado
	var k : float = clamp(delta * raycast_smooth, 0.0, 1.0)
	raycast_offset = raycast_offset.lerp(target_off, k)

	# Volver al centro en el aire
	if not character.is_on_floor():
		raycast_offset = raycast_offset.lerp(Vector2.ZERO, k)

	# Aplicar alrededor de las posiciones locales neutras
	leg_raycast.transform.origin  = neutral_local  + Vector3(raycast_offset.x, 0.0, raycast_offset.y)
	return raycast_offset
