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

var _creative: bool = false
var _debug_panel: DebugPanel = null
var _character_hidden: bool = false

## Punto de entrada único cuando el BoneInstantiator (re)construye el esqueleto del jugador
## activo — tanto el build inicial como cada respawn. Construye lo persistente una sola vez
## (InteractionController, cámara de debug, HUD de impacto) y re-vincula el controlador al
## esqueleto nuevo. Lo llama BoneInstantiator.initialize_skeleton.
func on_skeleton_built(target: BoneInstantiator, cam: Camera3D) -> void:
	player_camera = cam
	if not is_ready:
		_construct_persistent(target, cam)
		is_ready = true
	rebind(target)
	_set_debug_cam(_debug_cam_mode)
	if target.debug_enabled:
		_setup_debug_panel()  # refleja el personaje nuevo (se recrea adentro)
	# El mouse_mode lo maneja UIState (technical/ui.md); acá no lo tocamos.

## Nodos que viven en el PlayerController y sobreviven a los respawns: se crean una sola vez.
func _construct_persistent(target: BoneInstantiator, cam: Camera3D) -> void:
	interaction_controller = InteractionController.new()
	add_child(interaction_controller)
	var max_reach := target.skel_sizes_util.interaction_reach
	interaction_controller.setup(target.char_rigidbody, cam, target.arms_controller, target.anim_mod, max_reach, target.entity_instantiation)

	_impact_debug_hud = ImpactDebugHUD.create()

	_debug_camera = Camera3D.new()
	_debug_camera.current = false
	add_child(_debug_camera)

## Re-vincula el controlador (persistente) al esqueleto target: refs de cápsula/brazos/anim, el
## InteractionController, reparenta la cámara y recrea el HUD. Único lugar donde se re-cablea:
## compartido por on_skeleton_built (build/respawn) y _switch_to (cambio de cuerpo en creative).
func rebind(target: BoneInstantiator) -> void:
	char_rigidbody  = target.char_rigidbody
	head_bone       = target.custom_bones_util.head
	head_size       = target.skel_sizes_util.head_size
	arms_controller = target.arms_controller

	var max_reach := target.skel_sizes_util.interaction_reach
	if is_instance_valid(interaction_controller):
		interaction_controller.rebind(char_rigidbody, player_camera, arms_controller, target.anim_mod, max_reach, target.entity_instantiation)

	if is_instance_valid(player_camera):
		if is_instance_valid(player_camera.get_parent()):
			player_camera.get_parent().remove_child(player_camera)
		char_rigidbody.add_child(player_camera)
		target.player_camera   = player_camera
		player_camera.position = Vector3.ZERO
		player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)
		player_camera.current  = _debug_cam_mode == 0

	camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5

	if is_instance_valid(_hud):
		_hud.queue_free()
	_hud = PlayerHUD.create(target.entity_instantiation)
	char_rigidbody.add_child(_hud)

	_connect_fall_signal(char_rigidbody)

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

	# F1 abre/cierra el panel de debug — disponible siempre, incluso con overlay abierto.
	if is_instance_valid(_debug_panel) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1:
		_debug_panel.toggle()
		return

	# Con cualquier overlay abierto (pausa/menú/consola/debug) se bloquea el input de gameplay.
	if not UIState.gameplay_active():
		return

	var ic     := interaction_controller if is_instance_valid(interaction_controller) else null
	var bi     := _get_bi()
	var seated := is_instance_valid(bi) and bi.is_seated

	# V alterna creative (solo en gameplay).
	if is_instance_valid(_debug_panel) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_V:
		_set_creative(not _creative)
		return

	# ── Mouse motion ─────────────────────────────────────────────────────────
	if event is InputEventMouseMotion:
		if not _is_ragdoll_active():
			var sens := ic.get_camera_sensitivity_factor() if ic else 1.0
			if not (ic and ic._is_rotating):
				apply_camera_pitch(clamp(camera_pitch - event.relative.y * 0.002 * sens, -1.2, 1.2))
				camera_yaw -= event.relative.x * 0.002 * sens
		if ic:
			ic.apply_grab_rotation(event.relative)
			ic.apply_controlled_motion(event.relative)

	# ── Mouse buttons ─────────────────────────────────────────────────────────
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if not _is_ragdoll_active(): ic.try_interact()
				else:
					ic.release_interact()
			MOUSE_BUTTON_RIGHT:
				if ic: ic.set_rotating(event.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if ic: ic.adjust_distance(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if ic: ic.adjust_distance(1.0)

	# ── Keyboard ──────────────────────────────────────────────────────────────
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			match event.keycode:
				# Movimiento
				KEY_SPACE:
					if not _is_crouched and char_rigidbody.is_grounded and not seated and not _creative:
						_is_charging_jump = true
				KEY_CTRL:
					if not _is_crouched and not seated and not _creative:
						_start_crouch()

				# Interacción
				KEY_E:
					if ic and not _is_ragdoll_active(): ic.try_activate(bi)
				KEY_R:
					if ic: ic.start_throw_charge()
				KEY_F:
					if not seated:
						var hovered := ic.get_hovered_rb() if ic else null
						if is_instance_valid(hovered):
							var target_bi := _find_bone_instantiator(hovered)
							if target_bi and target_bi != bi:
								_switch_to(target_bi)

				# Físicas / debug
				KEY_G: _toggle_ragdoll()
				KEY_P: _respawn()

				# Cámaras de debug
				KEY_KP_5: _set_debug_cam(0)
				KEY_KP_1: _set_debug_cam(1)
				KEY_KP_2: _set_debug_cam(2)
				KEY_KP_3: _set_debug_cam(3)
				KEY_KP_4: _set_debug_cam(4)
				KEY_KP_6: _set_debug_cam(6)
				KEY_KP_7: _set_debug_cam(7)
				KEY_KP_8: _set_debug_cam(8)
				KEY_KP_9: _set_debug_cam(9)

		else: # released
			match event.keycode:
				KEY_SPACE:
					if _is_charging_jump:
						_release_jump()
						_is_charging_jump = false
				KEY_CTRL:
					if _is_crouched:
						_stop_crouch()
				KEY_R:
					if ic: ic.release_throw()


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


## true cuando la cámara activa es la del jugador (no una de debug), o sea cuando hay que esconderle
## la cabeza y el torso. Lo lee BoneInstantiator al final de initialize_skeleton para aplicar el
## estado correcto en el build/respawn, no solo cuando cambiás de cámara.
func is_first_person_view() -> bool:
	return _debug_cam_mode == 0

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
	var t := _jump_charge / arch.time_to_max_jump
	# La carga interpola ALTURA (no impulso): así la barra es lineal con lo que se ve saltar, y un
	# toque sin cargar sigue siendo un saltito util (30% de la altura), no el 9% que daba en impulso.
	char_rigidbody.jump_to_height(lerpf(arch.jump_height * 0.3, arch.jump_height, t))
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
	elif bi.ragdoll_util.is_recovering:
		return  # ya te estás levantando: no se puede re-ragdollear (nada de G-spam). En el futuro el
				 # levantarse será por timer según arch.time_to_standup, no con G. Ver onfoot-gameplay.md.
	else:
		_leave_seat_in_place(bi)  # sentado y ragdoll son excluyentes: primero salir del asiento
		char_rigidbody.is_snapshot_active = false
		bi.ragdoll_util.activate(char_rigidbody, bi.custom_bones_util.lower_spine)


## Sale del asiento en el lugar, si estaba sentado. Lo llaman los cambios de estado que son
## MUTUAMENTE EXCLUYENTES con estar sentado: el ragdoll (G) y el respawn (P). Sentado, la cápsula
## queda inerte (colisión off, axis lock, is_active=false) y el asiento le presta una malla hija, así
## que entrar a cualquiera de esos estados sin salir primero deja un híbrido inválido — ragdollear
## sentado te mandaba a volar con la silla pegada (y los proxies la veían quieta en su lugar).
## El camino por impacto no necesita esto: BoneInstantiator._on_fall_triggered ya se niega a
## ragdollear si estás sentado.
func _leave_seat_in_place(bi: BoneInstantiator) -> void:
	var seat := bi.current_seat as SeatInteractable
	if is_instance_valid(seat):
		seat.release_occupant_in_place()


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
	rebind(target)  # cápsula, IC, cámara, HUD, fall signal — compartido con el respawn
	char_rigidbody.is_active  = true
	char_rigidbody.rotation.y = camera_yaw
	_was_ragdoll_active = false

	# En primera persona la cabeza/torso los maneja la cámara: sacamos esos bones del animador.
	var bones_to_clear := [
		target.custom_bones_util.head,
		target.custom_bones_util.neck,
		target.custom_bones_util.chest,
		target.custom_bones_util.higher_spine,
		target.custom_bones_util.middle_spine,
	]
	for bone in bones_to_clear:
		if is_instance_valid(bone):
			target.procedural_animator.unregister_bone(bone)
	target.refresh_camera_animations()

	_is_crouched      = false
	_is_charging_jump = false
	_jump_charge      = 0.0
	char_rigidbody.crouch_speed_factor = 1.0

	_set_debug_cam(_debug_cam_mode)
	if is_instance_valid(interaction_controller):
		interaction_controller.stop_all()


func _respawn() -> void:
	var bi := _get_bi()
	if not bi:
		return

	# Salir limpio de todo estado que se aferra a la cápsula actual, ANTES de reconstruirla.
	if _creative:
		_set_creative(false)
	_leave_seat_in_place(bi)  # soltar YA (sincrónico) antes de reconstruir
	if is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_active:
		bi.ragdoll_util.deactivate(char_rigidbody, bi.custom_bones_util.lower_spine)
	if is_instance_valid(interaction_controller):
		interaction_controller.stop_all()  # suelta grab/control (y sincroniza grab_target null)

	var prev_pos := Vector3(char_rigidbody.global_position.x, 3.0, char_rigidbody.global_position.z)

	# Reconstruir el esqueleto con seed nueva. initialize_skeleton → on_skeleton_built → rebind
	# re-vincula todo (cápsula, IC, cámara, HUD); acá solo reposicionamos y reseteamos estado.
	bi.master_seed = randi() % 100000
	bi.initialize_skeleton()
	if is_instance_valid(bi.net_sync):
		bi.net_sync.broadcast_seed()  # multiplayer: reconstruir mi proxy en las demás máquinas

	char_rigidbody.global_position = prev_pos
	char_rigidbody.rotation.y      = camera_yaw

	# El esqueleto nuevo arranca limpio; reseteamos el estado de locomoción que vive acá.
	_is_crouched        = false
	_is_charging_jump   = false
	_jump_charge        = 0.0
	_was_ragdoll_active = false
	char_rigidbody.crouch_speed_factor = 1.0


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


# ── Creative / debug ────────────────────────────────────────────────────────

func _set_creative(on: bool) -> void:
	if on == _creative:
		return
	_creative = on
	var bi := _get_bi()
	if on:
		# Force-exit ragdoll before flying (the capsule is frozen while ragdolled).
		if is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) \
				and (bi.ragdoll_util.is_active or bi.ragdoll_util.is_recovering):
			bi.ragdoll_util.deactivate(char_rigidbody, bi.custom_bones_util.lower_spine)
		if is_instance_valid(interaction_controller):
			interaction_controller.stop_all()
		if _is_crouched:
			_stop_crouch()
		_is_charging_jump = false
		_jump_charge = 0.0
		char_rigidbody.set_creative_mode(true)
	else:
		char_rigidbody.set_creative_mode(false)
		char_rigidbody.rotation.y = camera_yaw
		camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5


func _setup_debug_panel() -> void:
	# Se re-llama en cada respawn (desde on_skeleton_built): recreamos el panel para reflejar
	# el nuevo personaje (y no acumular paneles).
	if is_instance_valid(_debug_panel):
		_debug_panel.queue_free()
	_debug_panel = DebugPanel.new()
	add_child(_debug_panel)

	# ── Info (stats del personaje generado + mundo + red) ──
	var bi := _get_bi()
	if is_instance_valid(bi) and is_instance_valid(bi.entity_instantiation):
		_debug_panel.add_text("Info", _character_stats_text(bi.entity_instantiation))
	var d := WorldSeeds.ba_date()
	_debug_panel.add_info("BA date",     "%04d-%02d-%02d" % [int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0))])
	_debug_panel.add_info("Weekly seed", str(WorldSeeds.weekly_seed()))
	_debug_panel.add_info("Daily seed",  str(WorldSeeds.daily_seed()))
	_debug_panel.add_info("Red", _net_status_text())

	# ── Acciones ──
	_debug_panel.add_action("Acciones", "Toggle creative (V)",      func(): _set_creative(not _creative))
	_debug_panel.add_action("Acciones", "Toggle ragdoll (G)",       _toggle_ragdoll)
	_debug_panel.add_action("Acciones", "Respawn (P)",              _respawn)
	_debug_panel.add_action("Acciones", "Esconder personaje",        _debug_toggle_character_hidden)
	_debug_panel.add_action("Acciones", "Ver cápsula física",        _debug_toggle_capsule_mesh)
	_debug_panel.add_action("Acciones", "Ragdoll debug color",      _debug_toggle_ragdoll_color)
	_debug_panel.add_action("Acciones", "Grab cone",                _debug_toggle_grab_cone)
	_debug_panel.add_action("Acciones", "Ver esqueleto",            _debug_toggle_skeleton_draw)
	_debug_panel.add_action("Acciones", "Ver colisionadores",       _debug_toggle_collider_draw)
	_debug_panel.add_action("Acciones", "Probe de precisión",        _debug_precision_probe)

	# ── Spawn ──
	_debug_panel.add_action("Spawn", "Go to start",        _go_to_start)
	_debug_panel.add_action("Spawn", "Character",          _debug_spawn_character)
	_debug_panel.add_action("Spawn", "Caja liviana ▪",     func(): _debug_spawn("box_light_square"))
	_debug_panel.add_action("Spawn", "Caja pesada ▪",      func(): _debug_spawn("box_heavy_square"))
	_debug_panel.add_action("Spawn", "Caja liviana ▬",     func(): _debug_spawn("box_light_long"))
	_debug_panel.add_action("Spawn", "Caja pesada ▬",      func(): _debug_spawn("box_heavy_long"))
	_debug_panel.add_action("Spawn", "Caja liviana ▭",     func(): _debug_spawn("box_light_xlong"))
	_debug_panel.add_action("Spawn", "Caja pesada ▭",      func(): _debug_spawn("box_heavy_xlong"))
	_debug_panel.add_action("Spawn", "Dashboard",          func(): _debug_spawn("dashboard"))
	_debug_panel.add_action("Spawn", "Seat",               func(): _debug_spawn("seat"))
	_debug_panel.add_action("Spawn", "Limpiar spawns",     func(): NetSpawner.request_clear_all())


func _character_stats_text(inst: EntityInstantiation) -> String:
	var arch := inst.arch_final
	var sizes := SkeletonSizesUtil.create(inst)
	var primary := str(EntityArchetype.Archetype.keys()[inst.archetype_type])
	var blend := "arch      (no blend)"
	if inst.archetype_blend > 0.0:
		blend = "secondary %s (%.0f%%)" % [
			str(EntityArchetype.Archetype.keys()[inst.secondary_archetype_type]),
			inst.archetype_blend * 100.0]
	var lines := [
		"seed      %d" % inst.master_seed,
		"arch      %s" % primary,
		blend,
		"%s  |  age %d" % [EntitySpecie.Specie.keys()[inst.specie_type], inst.age],
		"",
		# height y reach son DERIVADOS del modelo (SkeletonSizesUtil), ya no campos del arquetipo.
		"height    %.2f m" % sizes.total_height,
		"weight    %.1f kg" % arch.weight,
		"speed     %.1f" % arch.speed,
		"strength  %.2f" % arch.strenght,
		"jump      %.2fm" % arch.jump_height,
		"arm       %.2f m  (reach %.2f)" % [sizes.arm_reach, sizes.interaction_reach],
		"fatness   %.2f" % arch.fatness,
		"muscle    %.2f" % arch.muscularity,
	]
	return "\n".join(lines)


## Esconde el personaje ENTERO. Antes esto venía pegado a mostrar la cápsula y usaba el camino de
## primera persona, que deja manos y uñas visibles; ahora son dos botones y este no deja nada.
func _debug_toggle_character_hidden() -> void:
	_character_hidden = not _character_hidden
	var bi := _get_bi()
	if is_instance_valid(bi):
		bi.set_character_visible(not _character_hidden)


## La cápsula de colisión del cuerpo físico, aparte del personaje.
func _debug_toggle_capsule_mesh() -> void:
	if is_instance_valid(char_rigidbody) and is_instance_valid(char_rigidbody.mesh_instance):
		char_rigidbody.mesh_instance.visible = not char_rigidbody.mesh_instance.visible


func _debug_toggle_ragdoll_color() -> void:
	var rd := _get_ragdoll()
	if rd != null:
		rd.debug_ragdoll_color = not rd.debug_ragdoll_color


func _debug_toggle_grab_cone() -> void:
	var bi := _get_bi()
	if is_instance_valid(bi):
		bi.show_grab_cone = not bi.show_grab_cone


## Líneas por hueso + esferas en las articulaciones. Los gizmos cuelgan de los CustomBone, así que
## siguen el pose solos: no hay que redibujar nada por frame salvo el largo, que cambia al estirar
## el brazo. Ver Scripts/character/debug/skeleton_debug_draw.gd.
func _debug_toggle_skeleton_draw() -> void:
	var bi := _get_bi()
	if is_instance_valid(bi):
		bi.get_skeleton_debug().toggle_bones()


## Las cápsulas de colisión de los huesos (las que usa el ragdoll), leídas de los colliders reales.
func _debug_toggle_collider_draw() -> void:
	var bi := _get_bi()
	if is_instance_valid(bi):
		bi.get_skeleton_debug().toggle_colliders()


## Mide si los huesos se están separando por precisión fp32 (empeora lejos del origen) o por un bug
## de lógica. Corrélo JUSTO cuando veas el problema. Ver Scripts/character/debug/precision_probe.gd.
func _debug_precision_probe() -> void:
	var bi := _get_bi()
	if is_instance_valid(bi):
		print(PrecisionProbe.run(bi))


func _debug_spawn_pos() -> Vector3:
	var fwd := -player_camera.global_transform.basis.z
	return char_rigidbody.global_position + fwd * 2.5 + Vector3.UP


func _go_to_start() -> void:
	var spawner := get_tree().get_first_node_in_group("character_spawner")
	if spawner and spawner.has_method("respawn_local_at_start"):
		spawner.respawn_local_at_start()


func _net_status_text() -> String:
	if SessionManager.is_host and SessionManager.lobby_code != "":
		return "Host — código %s" % SessionManager.lobby_code
	if SessionManager.is_host:
		return "Host"
	if SessionManager.session_started and SessionManager.local_peer_id != 1:
		return "Cliente"
	return "Solo (local)"


func _debug_spawn_character() -> void:
	var scene := load("res://Scenes/player.tscn") as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate() as BoneInstantiator
	if inst == null:
		return
	inst.is_active = false
	inst.master_seed = randi() % 100000
	get_tree().current_scene.add_child(inst)
	inst.global_position = _debug_spawn_pos()


func _debug_spawn(type_name: String) -> void:
	var pos := _debug_spawn_pos()
	# Objetos de escena estáticos (no caen). El asiento se apoya en el piso; el dashboard es un panel
	# de control y va a altura de uso, sobre el piso. Las cajas son rigidbodies: caen solas.
	if type_name == "seat":
		pos = _snap_to_ground(pos)
	elif type_name == "dashboard":
		pos = _snap_to_ground(pos) + Vector3.UP * 1.2
	NetSpawner.request_spawn(type_name, Transform3D(Basis(), pos))

## Baja un punto hasta el piso con un raycast (para spawnear objetos estáticos apoyados).
func _snap_to_ground(from: Vector3) -> Vector3:
	var space := char_rigidbody.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.DOWN * 20.0)
	q.exclude = [char_rigidbody.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position if hit else from
