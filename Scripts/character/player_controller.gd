class_name PlayerController
extends Node

var head_bone: CustomBone
var head_size: Vector3
var char_rigidbody: CharacterRigidBody3D
var player_camera: Camera3D
var is_ready: bool = false

var camera_pitch: float = 0.0
var camera_yaw: float = 0.0
var camera_y_smooth: float = 0.0
const CAMERA_Y_SMOOTH: float = 8.0

var stamina_max: float = 5.0
var stamina_drain_rate: float = 0.01
var stamina_regen_rate: float = 0.75
var stamina_refractory_time: float = 2.0
var _stamina: float = 5.0
var _refractory_timer: float = 0.0
var _was_sprinting: bool = false

var _is_charging_jump: bool = false
var _jump_charge: float = 0.0
var _is_crouched: bool = false

var _was_ragdoll_active: bool = false

var _debug_cam_mode: int = 0
var _debug_camera: Camera3D = null
const DEBUG_CAM_DISTANCE: float = 5.0
const DEBUG_CAM_HEIGHT: float = 1.5

var _hud: PlayerHUD = null
var _impact_debug_hud: ImpactDebugHUD = null
var _prev_fall_rb: CharacterRigidBody3D = null

var interaction_controller: InteractionController = null
var arms_controller: ArmsController = null

func setup(rb: CharacterRigidBody3D, cam: Camera3D, head: CustomBone, h_size: Vector3, inst: EntityInstantiation) -> void:
	char_rigidbody = rb
	player_camera  = cam
	head_bone      = head
	head_size      = h_size
	is_ready       = true
	camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var bi := _get_bi()
	arms_controller = bi.arms_controller

	interaction_controller = InteractionController.new()
	add_child(interaction_controller)
	var max_reach := inst.arch_final.reach * inst.arch_final.reach_multiplier
	interaction_controller.setup(char_rigidbody, player_camera, arms_controller, bi.anim_mod, max_reach, inst)

	_hud = PlayerHUD.create(inst)
	char_rigidbody.add_child(_hud)
	_impact_debug_hud = ImpactDebugHUD.create()
	_connect_fall_signal(char_rigidbody)

	_debug_camera = Camera3D.new()
	_debug_camera.current = false
	add_child(_debug_camera)
	_set_debug_cam(0)

func _get_bi() -> BoneInstantiator:
	return char_rigidbody.get_parent() as BoneInstantiator


func _get_arch() -> EntityArchetype:
	var bi := _get_bi()
	return bi.entity_instantiation.arch_final if is_instance_valid(bi) else null


func _connect_fall_signal(rb: CharacterRigidBody3D) -> void:
	if is_instance_valid(_prev_fall_rb) and is_instance_valid(_impact_debug_hud):
		if _prev_fall_rb.fall_triggered.is_connected(_impact_debug_hud.notify_fall_triggered):
			_prev_fall_rb.fall_triggered.disconnect(_impact_debug_hud.notify_fall_triggered)
	_prev_fall_rb = rb
	if is_instance_valid(_impact_debug_hud):
		rb.fall_triggered.connect(func(_d): _impact_debug_hud.notify_fall_triggered())


func _get_ragdoll() -> RagdollUtil:
	var bi := _get_bi()
	return bi.ragdoll_util if is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) else null


func _is_ragdoll_active() -> bool:
	var rd := _get_ragdoll()
	return rd != null and (rd.is_active or rd.is_recovering)


func _input(event: InputEvent) -> void:
	if not is_ready:
		return

	if is_instance_valid(interaction_controller):
		interaction_controller.handle_input(event)

	if event is InputEventMouseMotion and not _is_ragdoll_active():
		var sens := interaction_controller.get_camera_sensitivity_factor() if is_instance_valid(interaction_controller) else 1.0
		if not (interaction_controller and interaction_controller._is_rotating):
			apply_camera_pitch(clamp(camera_pitch - event.relative.y * 0.002 * sens, -1.2, 1.2))
			camera_yaw  -= event.relative.x * 0.002 * sens

	if event is InputEventKey and not event.echo:
		var bi := _get_bi()
		var seated := is_instance_valid(bi) and bi.is_seated
		if event.pressed:
			match event.keycode:
				KEY_SPACE:
					if not _is_crouched and char_rigidbody.is_grounded and not seated:
						_is_charging_jump = true
				KEY_CTRL:
					if not _is_crouched and not seated:
						_start_crouch()
				KEY_F:
					var hovered := interaction_controller.get_hovered_rb() if interaction_controller else null
					if is_instance_valid(hovered):
						var target_bi := _find_bone_instantiator(hovered)
						if target_bi and target_bi != _get_bi():
							_switch_to(target_bi)
				KEY_E:
					if not _is_ragdoll_active():
						var hovered := interaction_controller.detector.get_hovered() if is_instance_valid(interaction_controller) else null
						if hovered is ActivatableInteractable:
							(hovered as ActivatableInteractable).activate()
				KEY_G:
					_toggle_ragdoll()
				KEY_P:
					_respawn()
				KEY_KP_5: _set_debug_cam(0)
				KEY_KP_1: _set_debug_cam(1)
				KEY_KP_2: _set_debug_cam(2)
				KEY_KP_3: _set_debug_cam(3)
				KEY_KP_4: _set_debug_cam(4)
				KEY_KP_6: _set_debug_cam(6)
				KEY_KP_7: _set_debug_cam(7)
				KEY_KP_8: _set_debug_cam(8)
				KEY_KP_9: _set_debug_cam(9)
		else:
			match event.keycode:
				KEY_SPACE:
					if _is_charging_jump:
						_release_jump()
						_is_charging_jump = false
				KEY_CTRL:
					if _is_crouched:
						_stop_crouch()
	


func _physics_process(delta: float) -> void:
	if not is_ready:
		return

	var ragdoll_active := _is_ragdoll_active()

	if ragdoll_active and not _was_ragdoll_active:
		if is_instance_valid(interaction_controller):
			interaction_controller.stop_all()
	_was_ragdoll_active = ragdoll_active

	_update_hud(delta)
	_update_debug_camera()

	if ragdoll_active:
		_update_ragdoll_camera(delta)
		return

	char_rigidbody.rotation.y = camera_yaw

	if _debug_cam_mode == 0:
		var target_y := head_bone.global_position.y + head_size.y * 0.5
		camera_y_smooth = lerp(camera_y_smooth, target_y, clamp(delta * CAMERA_Y_SMOOTH, 0.0, 1.0))
		player_camera.global_position.y = camera_y_smooth
		apply_camera_pitch(camera_pitch)

	_process_stamina(delta)

	if _is_charging_jump:
		if char_rigidbody.is_grounded and not _is_crouched:
			var arch := _get_arch()
			_jump_charge = min(_jump_charge + delta, arch.time_to_max_jump)
			_get_bi().jump_squat_t = _jump_charge / arch.time_to_max_jump
		else:
			_cancel_jump_charge()

	if is_instance_valid(interaction_controller):
		interaction_controller.update(delta)

	_update_hud_throw_jump()


func _update_hud(delta: float) -> void:
	if not is_instance_valid(_hud):
		return
	var hvel := Vector3(char_rigidbody.linear_velocity.x, 0.0, char_rigidbody.linear_velocity.z)
	_hud.update_speed(hvel.length())
	_hud.update_stability(char_rigidbody.velocity_indicator, char_rigidbody.impact_xz, char_rigidbody.impact_y)

	if is_instance_valid(_impact_debug_hud):
		var bi := _get_bi()
		_impact_debug_hud.update_impact_debug(
			char_rigidbody.impact_xz,
			char_rigidbody.global_transform.basis,
			char_rigidbody.impact_y,
			char_rigidbody.linear_velocity,
			char_rigidbody._last_impact_world_dir,
			char_rigidbody.ragdoll_threshold,
			is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_active,
			is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_recovering,
			char_rigidbody._last_impact_xz_magnitude,
			max(char_rigidbody.max_speed_forward, char_rigidbody.max_speed_side) * char_rigidbody.sprint_multiplier,
			char_rigidbody.ragdoll_threshold,
			char_rigidbody._snapshot_capture_count,
			char_rigidbody._snapshot_flag_at_capture,
			char_rigidbody._snapshot_ragdoll_at_capture,
			char_rigidbody._snapshot_acc_before,
			char_rigidbody._snapshot_acc_after
		)


func _update_hud_throw_jump() -> void:
	if not is_instance_valid(_hud):
		return
	var arch     := _get_arch()
	var jump_max := arch.time_to_max_jump if arch else 1.0
	var throw_t  := interaction_controller.get_throw_charge_normalized() if is_instance_valid(interaction_controller) else 0.0
	_hud.update_throw(throw_t)
	_hud.update_jump(_jump_charge / jump_max)


func _update_ragdoll_camera(_delta: float) -> void:
	var rd := _get_ragdoll()
	if _debug_cam_mode == 0:
		if rd != null and is_instance_valid(rd.head_body):
			player_camera.global_position = rd.head_body.global_position
		player_camera.global_rotation = Vector3(camera_pitch, camera_yaw, 0.0)
	if rd != null and rd.is_recovering:
		char_rigidbody.rotation.y = camera_yaw


func _set_debug_cam(mode: int) -> void:
	_debug_cam_mode = mode
	var bi := _get_bi()
	if mode == 0:
		player_camera.current = true
		_debug_camera.current = false
		if is_instance_valid(bi):
			bi.set_first_person_visibility(true)
	else:
		_debug_camera.current = true
		player_camera.current = false
		if is_instance_valid(bi):
			bi.set_first_person_visibility(false)


func _update_debug_camera() -> void:
	if _debug_cam_mode == 0 or not is_instance_valid(_debug_camera):
		return
	var yaw_basis := Basis(Vector3.UP, camera_yaw)
	var forward   := -yaw_basis.z
	var right     := yaw_basis.x
	var look_target := char_rigidbody.global_position + Vector3(0.0, DEBUG_CAM_HEIGHT, 0.0)
	var flat_offset := Vector3.ZERO
	match _debug_cam_mode:
		1: flat_offset = (-forward - right).normalized() * DEBUG_CAM_DISTANCE
		2: flat_offset = -forward * DEBUG_CAM_DISTANCE
		3: flat_offset = (-forward + right).normalized() * DEBUG_CAM_DISTANCE
		4: flat_offset = -right * DEBUG_CAM_DISTANCE
		6: flat_offset = right * DEBUG_CAM_DISTANCE
		7: flat_offset = (forward - right).normalized() * DEBUG_CAM_DISTANCE
		8: flat_offset = forward * DEBUG_CAM_DISTANCE
		9: flat_offset = (forward + right).normalized() * DEBUG_CAM_DISTANCE
	_debug_camera.global_position = look_target + Vector3(flat_offset.x, 0.0, flat_offset.z)
	_debug_camera.look_at(look_target, Vector3.UP)


func _release_jump() -> void:
	var arch := _get_arch()
	if arch == null or not char_rigidbody.is_grounded:
		_cancel_jump_charge()
		return
	var t          := _jump_charge / arch.time_to_max_jump
	var max_impulse := arch.jump_strenght * char_rigidbody.mass * CharacterRigidBody3D.JUMP_SCALE
	char_rigidbody.jump(lerpf(max_impulse * 0.3, max_impulse, t))
	_cancel_jump_charge()


func _cancel_jump_charge() -> void:
	_jump_charge = 0.0
	var bi := _get_bi()
	if is_instance_valid(bi):
		var tw := create_tween()
		tw.tween_property(bi, "jump_squat_t", 0.0, 0.08)


func _start_crouch() -> void:
	var bi := _get_bi()
	if not is_instance_valid(bi):
		return
	_is_crouched = true
	if _is_charging_jump:
		_is_charging_jump = false
		_jump_charge = 0.0
	var tw := create_tween()
	tw.tween_property(bi, "crouch_t", 1.0, 0.12)
	tw.tween_callback(func(): char_rigidbody.set_crouched(true))
	char_rigidbody.crouch_speed_factor = 0.6


func _stop_crouch() -> void:
	var bi := _get_bi()
	if not is_instance_valid(bi):
		return
	_is_crouched = false
	char_rigidbody.set_crouched(false)
	var tw := create_tween()
	tw.tween_property(bi, "crouch_t", 0.0, 0.12)
	char_rigidbody.crouch_speed_factor = 1.0


func _toggle_ragdoll() -> void:
	var bi := _get_bi()
	if not is_instance_valid(bi) or not is_instance_valid(bi.ragdoll_util):
		return
	if bi.ragdoll_util.is_active:
		bi.ragdoll_util.deactivate(char_rigidbody, bi.custom_bones_util.lower_spine)
		char_rigidbody.rotation.y = camera_yaw
		camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
	else:
		char_rigidbody.is_snapshot_active = false
		bi.ragdoll_util.activate(char_rigidbody, bi.custom_bones_util.lower_spine)


func _find_bone_instantiator(node: Node) -> BoneInstantiator:
	var current := node.get_parent()
	while current:
		if current is BoneInstantiator:
			return current
		current = current.get_parent()
	return null


func _switch_to(target: BoneInstantiator) -> void:
	var current_bi := _get_bi()
	if not (is_instance_valid(current_bi.ragdoll_util) and current_bi.ragdoll_util.is_active):
		current_bi.char_rigidbody.is_active = false
	current_bi.is_active = false

	target.is_active = true
	char_rigidbody = target.char_rigidbody
	head_bone      = target.custom_bones_util.head
	head_size      = target.skel_sizes_util.head_size

	var max_reach := target.entity_instantiation.arch_final.reach * target.entity_instantiation.arch_final.reach_multiplier
	if is_instance_valid(interaction_controller):
		interaction_controller.set_reach(max_reach)
		interaction_controller.char_rigidbody = char_rigidbody
		interaction_controller.player_camera  = player_camera
		interaction_controller.anim_mod       = target.anim_mod
		interaction_controller.set_entity_instantiation(target.entity_instantiation)

	arms_controller = target.arms_controller
	if is_instance_valid(interaction_controller):
		interaction_controller.arms_controller = arms_controller

	player_camera.get_parent().remove_child(player_camera)
	char_rigidbody.add_child(player_camera)
	target.player_camera = player_camera
	player_camera.current = _debug_cam_mode == 0
	player_camera.position = Vector3.ZERO
	player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)
	char_rigidbody.is_active = true
	char_rigidbody.rotation.y = camera_yaw
	camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
	_was_ragdoll_active = false

	var bones_to_clear := [
		target.custom_bones_util.head,
		target.custom_bones_util.neck,
		target.custom_bones_util.chest,
		target.custom_bones_util.upper_spine,
		target.custom_bones_util.middle_spine,
	]
	for bone in bones_to_clear:
		if is_instance_valid(bone):
			target.procedural_animator.unregister_bone(bone)
	target.refresh_camera_animations()

	if _is_crouched:
		char_rigidbody.set_crouched(false)
	_is_crouched = false
	_is_charging_jump = false
	_jump_charge = 0.0
	char_rigidbody.crouch_speed_factor = 1.0

	if is_instance_valid(_hud):
		_hud.queue_free()
	_hud = PlayerHUD.create(target.entity_instantiation)
	char_rigidbody.add_child(_hud)

	_connect_fall_signal(char_rigidbody)
	_set_debug_cam(_debug_cam_mode)

	if is_instance_valid(interaction_controller):
		interaction_controller.stop_all()


func _respawn() -> void:
	var current_bi := _get_bi()
	if not current_bi:
		return
	if is_instance_valid(current_bi.ragdoll_util) and current_bi.ragdoll_util.is_active:
		current_bi.ragdoll_util.deactivate(char_rigidbody, current_bi.custom_bones_util.lower_spine)

	var prev_pos := Vector3(char_rigidbody.global_position.x, 3.0, char_rigidbody.global_position.z)
	current_bi.master_seed = randi() % 100000
	current_bi.initialize_skeleton()

	char_rigidbody = current_bi.char_rigidbody
	head_bone      = current_bi.custom_bones_util.head
	head_size      = current_bi.skel_sizes_util.head_size

	var max_reach := current_bi.entity_instantiation.arch_final.reach * current_bi.entity_instantiation.arch_final.reach_multiplier
	if is_instance_valid(interaction_controller):
		interaction_controller.set_reach(max_reach)
		interaction_controller.char_rigidbody = char_rigidbody
		interaction_controller.anim_mod       = current_bi.anim_mod
		interaction_controller.set_entity_instantiation(current_bi.entity_instantiation)
	arms_controller = current_bi.arms_controller
	if is_instance_valid(interaction_controller):
		interaction_controller.arms_controller = arms_controller

	char_rigidbody.global_position = prev_pos
	char_rigidbody.rotation.y = camera_yaw
	camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
	_was_ragdoll_active = false

	if _is_crouched:
		char_rigidbody.set_crouched(false)
	_is_crouched = false
	_is_charging_jump = false
	_jump_charge = 0.0
	char_rigidbody.crouch_speed_factor = 1.0

	player_camera.get_parent().remove_child(player_camera)
	char_rigidbody.add_child(player_camera)
	player_camera.current = _debug_cam_mode == 0
	player_camera.position = Vector3.ZERO
	player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)

	if is_instance_valid(_hud):
		_hud.queue_free()
	_hud = PlayerHUD.create(current_bi.entity_instantiation)
	char_rigidbody.add_child(_hud)

	_connect_fall_signal(char_rigidbody)
	if is_instance_valid(interaction_controller):
		interaction_controller.stop_all()


func _process_stamina(delta: float) -> void:
	var is_sprinting := Input.is_action_pressed("sprint") \
		and Input.get_axis("move_forward", "move_backward") < 0.0 \
		and char_rigidbody.can_sprint

	if is_sprinting:
		_stamina = max(0.0, _stamina - stamina_drain_rate * delta)
		if _stamina == 0.0:
			char_rigidbody.can_sprint = false
		_refractory_timer = stamina_refractory_time
		_was_sprinting = true
	else:
		if _was_sprinting:
			_was_sprinting = false
		if _refractory_timer > 0.0:
			_refractory_timer = max(0.0, _refractory_timer - delta)
		else:
			if not char_rigidbody.can_sprint:
				char_rigidbody.can_sprint = true
			_stamina = min(stamina_max, _stamina + stamina_regen_rate * delta)

	if is_instance_valid(_hud):
		_hud.update_stamina(_stamina / stamina_max)
		
func apply_camera_pitch(pitch: float) -> void:
	camera_pitch = pitch
	if is_instance_valid(player_camera):
		player_camera.rotation.x = camera_pitch
