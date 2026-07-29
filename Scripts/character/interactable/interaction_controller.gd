class_name InteractionController
extends Node

var char_rigidbody: CharacterRigidBody3D
var player_camera:  Camera3D
var arms_controller: ArmsController
var anim_mod: AnimationModifiers

var grab_stiffness:           float = 150.0
var grab_damping:             float = 15.0
var grab_rotation_sensitivity: float = 0.005
var grab_rotation_stiffness:  float = 50.0
var grab_rotation_damping:    float = 8.0
var grab_angular_damp:        float = 4.0
var show_grab_curve:          bool  = true
var grab_cone_half_angle:     float = 120.0
var throw_strength:           float = 500.0
var throw_max_charge_time:    float = 0.5
var scroll_sensitivity:       float = 0.15
var effort_cone_fraction:     float = 0.6
var effort_time_threshold:    float = 0.5

var _grabbed:               RigidBody3D = null
var _grabbed_grab_point:    Node3D      = null
var _grab_distance:         float       = 3.0
var _is_rotating:           bool        = false
var _grab_target_rotation:  Quaternion  = Quaternion.IDENTITY
var _grab_relative_rotation: Quaternion = Quaternion.IDENTITY

var _line_mesh:         MeshInstance3D = null
var _is_charging_throw: bool           = false
var _throw_charge:      float          = 0.0
var _effort_timer:      float          = 0.0
var _is_high_effort:    bool           = false

var _controlled:           ControllableInteractable = null
var _entity_instantiation: EntityInstantiation      = null

var detector: InteractionDetector = null

var interact_dist_max: float = 0.0
var grab_dist_max:     float = 0.0
var grip_dist_max:     float = 0.0
var grab_dist_min:     float = 0.0

signal high_effort_started()
signal high_effort_ended()

func setup(rb: CharacterRigidBody3D, cam: Camera3D, arms: ArmsController, anim: AnimationModifiers, max_reach: float, inst: EntityInstantiation) -> void:
	char_rigidbody        = rb
	player_camera         = cam
	arms_controller       = arms
	anim_mod              = anim
	_entity_instantiation = inst
	_update_grab_strength()

	detector = InteractionDetector.new()
	add_child(detector)
	detector.setup(rb, cam, rb.get_parent() as BoneInstantiator)

	set_reach(max_reach)

## Re-apunta el IC (persistente) a un esqueleto nuevo tras un respawn/switch: refs de cápsula,
## cámara, brazos, anim y el detector. El IC y su detector sobreviven; solo se re-vinculan.
func rebind(rb: CharacterRigidBody3D, cam: Camera3D, arms: ArmsController, anim: AnimationModifiers, max_reach: float, inst: EntityInstantiation) -> void:
	char_rigidbody        = rb
	player_camera         = cam
	arms_controller       = arms
	anim_mod              = anim
	_entity_instantiation = inst
	_update_grab_strength()
	set_reach(max_reach)
	if is_instance_valid(detector):
		detector.rebind(rb, cam, rb.get_parent() as BoneInstantiator)

func set_reach(max_reach: float) -> void:
	interact_dist_max = max_reach * 0.85
	grab_dist_max     = max_reach * 0.9
	grab_dist_min     = max_reach * 0.1
	grip_dist_max     = max_reach * 1.0
	if is_instance_valid(detector):
		detector.set_reach(interact_dist_max)

func set_entity_instantiation(inst: EntityInstantiation) -> void:
	_entity_instantiation = inst
	_update_grab_strength()

func get_camera_sensitivity_factor() -> float:
	if is_instance_valid(_controlled):
		return _controlled.camera_sensitivity_factor
	return 1.0

func get_hovered_rb() -> RigidBody3D:
	var h := detector.get_hovered() if is_instance_valid(detector) else null
	if h is GrabbableInteractable:
		return h.get_parent() as RigidBody3D
	return null

func get_throw_charge_normalized() -> float:
	return _throw_charge / throw_max_charge_time

func is_charging_throw() -> bool:
	return _is_charging_throw

func update(delta: float) -> void:
	if is_instance_valid(detector):
		if not is_instance_valid(_grabbed) and not is_instance_valid(_controlled):
			detector.update()

	if _is_charging_throw:
		_throw_charge = min(_throw_charge + delta, throw_max_charge_time)
		if is_instance_valid(anim_mod):
			anim_mod.set_throw_charge(_throw_charge / throw_max_charge_time, -player_camera.global_transform.basis.z)

	if is_instance_valid(_controlled):
		var handle     := _controlled.get_nearest_handle_point(_get_interaction_origin())
		var ctrl_world := handle.global_position if is_instance_valid(handle) else _controlled.global_position
		if _is_out_of_reach(ctrl_world):
			_stop_control()
			return
		if is_instance_valid(arms_controller):
			arms_controller.update_grab_handles(delta, _controlled, _get_interaction_origin(), handle)
		_update_debug_line()
		return

	if not is_instance_valid(_grabbed):
		_reset_effort()
		return

	_apply_grab_force()
	if not is_instance_valid(_grabbed):
		return
	_apply_grab_torque()
	_update_effort_zone(delta)
	if is_instance_valid(arms_controller):
		var grabbable := _get_grabbable(_grabbed)
		if is_instance_valid(grabbable):
			arms_controller.update_grab_handles(delta, grabbable, _get_interaction_origin(), _grabbed_grab_point)
	_update_debug_line()

func stop_all() -> void:
	_stop_grab()
	_stop_control()
	if is_instance_valid(detector):
		detector.force_clear()
	cancel_throw()

func cancel_throw() -> void:
	_is_charging_throw = false
	_throw_charge      = 0.0
	if is_instance_valid(anim_mod):
		anim_mod.cancel_throw()

# ── Control ───────────────────────────────────────────────────────────────────

func _start_control(ctrl: ControllableInteractable) -> void:
	_controlled = ctrl
	if not ctrl.control_lost.is_connected(_on_control_lost):
		ctrl.control_lost.connect(_on_control_lost)
	_controlled.start_control()
	var origin := _get_interaction_origin()
	var handle := ctrl.get_nearest_handle_point(origin)
	if is_instance_valid(arms_controller):
		arms_controller.start_grab(ctrl, origin, handle, grab_dist_min, grab_dist_max)
	var ns := _char_net_sync()  # avisar qué controlo, para que los proxies muevan los brazos al handle
	if is_instance_valid(ns):
		ns.set_grab_target(ctrl)

func _stop_control() -> void:
	if is_instance_valid(_controlled):
		if _controlled.control_lost.is_connected(_on_control_lost):
			_controlled.control_lost.disconnect(_on_control_lost)
		_controlled.stop_control()
	_controlled = null
	if is_instance_valid(_line_mesh):
		_line_mesh.queue_free()
		_line_mesh = null
	if is_instance_valid(arms_controller):
		arms_controller.stop_grab()
	var ns := _char_net_sync()
	if is_instance_valid(ns):
		ns.set_grab_target(null)

## El host me negó el control (perdí la carrera por el mismo control): soltar.
func _on_control_lost() -> void:
	_stop_control()

# ── Grab ──────────────────────────────────────────────────────────────────────

func _start_grab(grabbable: GrabbableInteractable) -> void:
	var rb := grabbable.get_parent() as RigidBody3D
	if not is_instance_valid(rb):
		return
	_grabbed = rb
	# Si el objeto está sincronizado, avisamos que lo agarramos (el host maneja autoridad/co-grabbers).
	var net := _net_body_of(rb)
	if is_instance_valid(net):
		net.begin_grab()
	var origin          := _get_interaction_origin()
	_grabbed_grab_point  = grabbable.get_nearest_grab_point(origin)
	var grab_world      := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
	_grab_distance       = clamp(origin.distance_to(grab_world), grab_dist_min, grab_dist_max)
	_grabbed.sleeping      = false
	_grab_target_rotation  = _grabbed.global_transform.basis.get_rotation_quaternion()
	var player_rot         := Quaternion(char_rigidbody.global_transform.basis)
	_grab_relative_rotation = player_rot.inverse() * _grab_target_rotation
	if is_instance_valid(arms_controller):
		arms_controller.start_grab(grabbable, _get_interaction_origin(), _grabbed_grab_point, grab_dist_min, grab_dist_max)
	var ns := _char_net_sync()  # avisar a los otros qué agarré, para que sus proxies muevan los brazos
	if is_instance_valid(ns):
		ns.set_grab_target(grabbable)

func _stop_grab() -> void:
	_reset_effort()
	# Avisamos que soltamos (el host promueve autoridad al que quede, o vuelve al host).
	if is_instance_valid(_grabbed):
		var net := _net_body_of(_grabbed)
		if is_instance_valid(net):
			net.end_grab()
	_grabbed            = null
	_grabbed_grab_point = null
	_is_rotating        = false
	if is_instance_valid(_line_mesh):
		_line_mesh.queue_free()
		_line_mesh = null
	if is_instance_valid(arms_controller):
		arms_controller.stop_grab()
	var ns := _char_net_sync()
	if is_instance_valid(ns):
		ns.set_grab_target(null)

func _apply_grab_force() -> void:
	if not is_instance_valid(_grabbed):
		_grabbed = null
		return
	var origin     := _get_interaction_origin()
	var cam_fwd    := -player_camera.global_transform.basis.z
	var target_pos := origin + cam_fwd * _grab_distance
	var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
	if _is_out_of_reach(grab_world):
		_stop_grab()
		return

	# Co-agarre: si el objeto está sincronizado y NO somos su autoridad, mandamos la intención
	# (grab point + a dónde tiramos) a quien lo simula, y no tocamos el cuerpo (está frozen acá).
	var net := _net_body_of(_grabbed)
	if is_instance_valid(net) and multiplayer.has_multiplayer_peer() and not net.is_multiplayer_authority():
		net.send_grab_intent(_grabbed.to_local(grab_world), target_pos, grab_stiffness, grab_damping)
		return

	# Autoridad (u offline): fuerza en el GRAB POINT (off-center → traslación + rotación
	# emergente) + damping angular para frenar giros indeseados.
	var force := (target_pos - grab_world) * grab_stiffness - _grabbed.linear_velocity * grab_damping
	_grabbed.apply_force(force, grab_world - _grabbed.global_position)
	_grabbed.apply_torque(-_grabbed.angular_velocity * grab_angular_damp)
	_grabbed.sleeping = false

func _apply_grab_torque() -> void:
	if not is_instance_valid(_grabbed):
		return
	# Yaw-follow (la caja rota con el personaje) SOLO con un agarrador. Con co-agarre se apaga
	# (la orientación sale de las fuerzas en los grab points), y los co-grabbers no aplican torque.
	var net := _net_body_of(_grabbed)
	if is_instance_valid(net) and multiplayer.has_multiplayer_peer():
		if not net.is_multiplayer_authority() or net.has_cograbbers():
			return
	var player_rot          := Quaternion(char_rigidbody.global_transform.basis)
	_grab_target_rotation   = player_rot * _grab_relative_rotation
	var current := _grabbed.global_transform.basis.get_rotation_quaternion()
	var error   := (_grab_target_rotation * current.inverse()).normalized()
	var angle   := error.get_angle()
	if angle > PI: angle -= TAU
	_grabbed.apply_torque(error.get_axis() * angle * grab_rotation_stiffness - _grabbed.angular_velocity * grab_rotation_damping)

func _release_throw() -> void:
	var dir := -player_camera.global_transform.basis.z
	var t   := _throw_charge / throw_max_charge_time
	if is_instance_valid(_grabbed):
		_grabbed.apply_central_impulse(dir * throw_strength * t)
	elif is_instance_valid(detector):
		var h := detector.get_hovered()
		if h is GrabbableInteractable:
			var rb := h.get_parent() as RigidBody3D
			if is_instance_valid(rb):
				rb.apply_impulse(dir * throw_strength * t, rb.global_position - _get_interaction_origin())
	if is_instance_valid(anim_mod):
		anim_mod.trigger_throw_push(dir)
	_is_charging_throw = false
	_throw_charge      = 0.0
	_stop_grab()

func _get_interaction_origin() -> Vector3:
	var bi := char_rigidbody.get_parent() as BoneInstantiator
	if not is_instance_valid(bi):
		return player_camera.global_position
	return bi.get_interaction_origin()

func _get_grabbable(rb: RigidBody3D) -> GrabbableInteractable:
	for child in rb.get_children():
		if child is GrabbableInteractable:
			return child as GrabbableInteractable
	return null

func _net_body_of(rb: RigidBody3D) -> NetBody:
	for child in rb.get_children():
		if child is NetBody:
			return child as NetBody
	return null

func _char_net_sync() -> CharacterNetSync:
	var bi := char_rigidbody.get_parent() as BoneInstantiator
	return bi.net_sync if is_instance_valid(bi) else null

# ── Debug line ────────────────────────────────────────────────────────────────

func _get_reach_color(dist: float) -> Color:
	if dist <= interact_dist_max: return Color(0.0, 1.0, 0.0)
	if dist <= grab_dist_max:     return Color(1.0, 1.0, 0.0)
	if dist <= grip_dist_max:     return Color(1.0, 0.5, 0.0)
	return Color(1.0, 0.0, 0.0)

func _update_debug_line() -> void:
	if is_instance_valid(_line_mesh):
		_line_mesh.queue_free()
		_line_mesh = null
	if not show_grab_curve:
		return
	var origin := _get_interaction_origin()
	var target := Vector3.ZERO
	if is_instance_valid(_grabbed):
		target = _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
	elif is_instance_valid(_controlled):
		var handle := _controlled.get_nearest_handle_point(origin)
		target = handle.global_position if is_instance_valid(handle) else _controlled.global_position
	else:
		return
	var color := _get_reach_color(origin.distance_to(target))
	_line_mesh = DebugUtil.create_debug_path3d([
		{ "pos": origin, "in": Vector3.ZERO, "out": Vector3.ZERO },
		{ "pos": target, "in": Vector3.ZERO, "out": Vector3.ZERO }
	], 2, color, 0.01)
	get_tree().current_scene.add_child(_line_mesh)

# ── Effort ────────────────────────────────────────────────────────────────────

func _update_effort_zone(delta: float) -> void:
	var origin     := _get_interaction_origin()
	var cam_fwd    := -player_camera.global_transform.basis.z
	var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
	var to_grab    := (grab_world - origin).normalized()
	if to_grab.dot(cam_fwd) >= cos(deg_to_rad(grab_cone_half_angle * effort_cone_fraction)):
		_reset_effort()
	else:
		_effort_timer += delta
		if not _is_high_effort and _effort_timer >= effort_time_threshold:
			_is_high_effort = true
			high_effort_started.emit()

func _reset_effort() -> void:
	_effort_timer = 0.0
	if _is_high_effort:
		_is_high_effort = false
		high_effort_ended.emit()

func _update_grab_strength() -> void:
	if not is_instance_valid(_entity_instantiation):
		return
	var arch       := _entity_instantiation.arch_final
	grab_stiffness = arch.strenght * arch.weight * 9.8
	grab_damping   = grab_stiffness * 0.1

func _is_outside_cone(world_pos: Vector3) -> bool:
	var origin  := _get_interaction_origin()
	var cam_fwd := -player_camera.global_transform.basis.z
	var to_pos  := world_pos - origin
	if to_pos.length() <= 0.001:
		return false
	return to_pos.normalized().dot(cam_fwd) < cos(deg_to_rad(grab_cone_half_angle))

func _is_out_of_reach(world_pos: Vector3) -> bool:
	var origin := _get_interaction_origin()
	var to_pos := world_pos - origin
	var dist   := to_pos.length()
	print("[OUT_OF_REACH] dist=%.3f grip_dist_max=%.3f interact_dist_max=%.3f" % [dist, grip_dist_max, interact_dist_max])
	if dist > grip_dist_max:
		print("[OUT_OF_REACH] LOST — too far (%.3f > %.3f)" % [dist, grip_dist_max])
		return true
	if dist <= 0.001:
		return false
	var cam_fwd := -player_camera.global_transform.basis.z
	var dot     := to_pos.normalized().dot(cam_fwd)
	var cone    := cos(deg_to_rad(grab_cone_half_angle))
	if dot < cone:
		print("[OUT_OF_REACH] LOST — outside cone (dot=%.3f < cone=%.3f)" % [dot, cone])
		return true
	return false

# ── Input API ─────────────────────────────────────────────────────────────────

func try_interact() -> void:
	var hovered := detector.get_hovered() if is_instance_valid(detector) else null
	if not is_instance_valid(hovered): return
	if hovered is GrabbableInteractable:
		_start_grab(hovered as GrabbableInteractable)
	elif hovered is ControllableInteractable:
		_start_control(hovered as ControllableInteractable)

func release_interact() -> void:
	_stop_grab()
	_stop_control()

func set_rotating(_value: bool) -> void:
	# Rotación libre con el mouse desactivada: con 1 agarrador el yaw sigue al personaje solo,
	# con co-agarre la orientación es emergente. Ver technical/ui.md / conceptual/multiplayer.md.
	_is_rotating = false

func apply_grab_rotation(relative: Vector2) -> void:
	if not _is_rotating or not is_instance_valid(_grabbed): return
	var delta_rot := Quaternion(player_camera.global_transform.basis.x, -relative.y * grab_rotation_sensitivity) \
				  * Quaternion(player_camera.global_transform.basis.y, -relative.x * grab_rotation_sensitivity)
	_grab_target_rotation = delta_rot * _grab_target_rotation

func apply_controlled_motion(relative: Vector2) -> void:
	if is_instance_valid(_controlled):
		_controlled.handle_mouse_motion(relative)

func adjust_distance(dir: float) -> void:
	if is_instance_valid(_grabbed):
		_grab_distance = clamp(_grab_distance + dir * scroll_sensitivity, grab_dist_min, grab_dist_max)
	elif is_instance_valid(_controlled):
		_controlled.handle_scroll(dir)

func try_activate(bi: Node) -> void:
	var seated : bool = is_instance_valid(bi) and bi.is_seated
	if seated and is_instance_valid(bi.current_seat):
		bi.current_seat.activate(bi)
		return
	var hovered := detector.get_hovered() if is_instance_valid(detector) else null
	if hovered is ActivatableInteractable:
		(hovered as ActivatableInteractable).activate(bi)

func start_throw_charge() -> void:
	if _is_charging_throw: return
	_is_charging_throw = true
	_throw_charge = 0.0

func release_throw() -> void:
	if _is_charging_throw:
		_release_throw()
