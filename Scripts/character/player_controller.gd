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

## ── STAMINA ───────────────────────────────────────────────────────────────────────────────────────
## Se gasta corriendo y se recupera al soltar, después de `stamina_refractory_time`.
##
## Los números están puestos en TIEMPO, no en unidades: con el máximo en 5.0, el drenaje es
## `5 / segundos_de_sprint` y la regeneración `5 / segundos_de_recarga`.
##
##   sprint continuo  →  10 s        recarga completa  →  10 s
##
## El drenaje estaba en 0.01, o sea **500 segundos** de sprint: la barra existía pero nunca se vaciaba.
var stamina_max: float = 5.0
var stamina_drain_rate: float = 0.5
var stamina_regen_rate: float = 0.5
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
## Zoom de la cámara de debug, ADIMENSIONAL: multiplica la distancia a la que el personaje entra justo
## en cuadro. 1.0 = encuadrado exacto, y no se puede acercar más que eso. Al ser un múltiplo y no una
## medida en metros, se ajusta solo a cualquier altura de personaje. Numpad +/- mientras se mantienen
## apretados; no se resetea al volver a primera persona.
var _debug_cam_zoom: float = 2.5
const DEBUG_CAM_ZOOM_SPEED: float = 2.0
const DEBUG_CAM_ZOOM_MAX:   float = 8.0
## Aire alrededor del personaje con el zoom al mínimo, para que no quede pegado a los bordes.
const DEBUG_CAM_FRAME_MARGIN: float = 1.15

var _hud: PlayerHUD = null
var _impact_debug_hud: ImpactDebugHUD = null
var _prev_fall_rb: CharacterRigidBody3D = null

var interaction_controller: InteractionController = null
var arms_controller: ArmsController = null

var _creative: bool = false
var _debug_panel: DebugPanel = null

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
			# La rueda emite un evento pressed y otro released por cada muesca: sin el guard de
			# pressed cada muesca aplicaría el paso dos veces (rotación y distancia de agarre).
			MOUSE_BUTTON_WHEEL_UP:
				if ic and event.pressed: ic.adjust_distance(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if ic and event.pressed: ic.adjust_distance(1.0)

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
	_update_debug_camera(delta)

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


func _update_debug_camera(delta: float) -> void:
	if _debug_cam_mode == 0 or not is_instance_valid(_debug_camera):
		return

	# Zoom con numpad +/-. Se lee el estado de la tecla en vez de escuchar eventos porque es una acción
	# SOSTENIDA: con eventos habría que manejar press/release/echo para lo mismo.
	var zoom := 0.0
	if Input.is_key_pressed(KEY_KP_ADD):
		zoom -= 1.0
	if Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom += 1.0
	if not is_zero_approx(zoom):
		_debug_cam_zoom = clampf(_debug_cam_zoom + zoom * DEBUG_CAM_ZOOM_SPEED * delta, 1.0, DEBUG_CAM_ZOOM_MAX)

	# Encuadre derivado del personaje, no de constantes en metros: mira a su CENTRO, y la distancia
	# mínima es la que lo hace entrar justo en cuadro — trigonometría del FOV. Así funciona igual con un
	# personaje de 1.38 m que con uno de 1.9 m, sin tocar un número.
	var sizes  := _get_bi().skel_sizes_util
	var ground := char_rigidbody.global_position.y - sizes.standing_pelvis_height
	var fit    : float = (sizes.total_height * 0.5 * DEBUG_CAM_FRAME_MARGIN) / tan(deg_to_rad(_debug_camera.fov) * 0.5)
	var _debug_cam_distance := fit * _debug_cam_zoom

	var yaw_basis := Basis(Vector3.UP, camera_yaw)
	var forward   := -yaw_basis.z
	var right     := yaw_basis.x
	var look_target := Vector3(char_rigidbody.global_position.x, ground + sizes.total_height * 0.5, char_rigidbody.global_position.z)
	var flat_offset := Vector3.ZERO
	match _debug_cam_mode:
		1: flat_offset = (-forward - right).normalized() * _debug_cam_distance
		2: flat_offset = -forward * _debug_cam_distance
		3: flat_offset = (-forward + right).normalized() * _debug_cam_distance
		4: flat_offset = -right * _debug_cam_distance
		6: flat_offset = right * _debug_cam_distance
		7: flat_offset = (forward - right).normalized() * _debug_cam_distance
		8: flat_offset = forward * _debug_cam_distance
		9: flat_offset = (forward + right).normalized() * _debug_cam_distance
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
	bi.master_seed = DebugArchetype.respawn_seed()
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
	# Todos globales: se aplican a TODOS los personajes de la escena, no solo al propio.
	_debug_panel.add_action("Acciones", "Esconder personajes",       func(): CharacterDebugView.toggle_hide_character(get_tree()))
	_debug_panel.add_action("Acciones", "Ver cápsula física",        func(): CharacterDebugView.toggle_capsule(get_tree()))
	_debug_panel.add_action("Acciones", "Ragdoll debug color",       func(): CharacterDebugView.toggle_ragdoll_color(get_tree()))
	_debug_panel.add_action("Acciones", "Grab cone",                 func(): CharacterDebugView.toggle_grab_cone(get_tree()))
	_debug_panel.add_action("Acciones", "Ver esqueleto",             func(): CharacterDebugView.toggle_skeleton(get_tree()))
	_debug_panel.add_action("Acciones", "Ver colisionadores",        func(): CharacterDebugView.toggle_colliders(get_tree()))
	_debug_panel.add_action("Acciones", "Ver gizmos de marcha",      func(): CharacterDebugView.toggle_gait_gizmos(get_tree()))
	_debug_panel.add_action("Acciones", "Medir piernas (consola)",   _debug_measure_legs)
	_debug_panel.add_action("Acciones", "Medir velocidad (consola)", _debug_measure_speed)
	# Apariencia: también globales, y se repintan en el momento.
	_debug_panel.add_action("Acciones", "Shader on/off",             func(): CharacterAppearance.toggle_flat_geometry(get_tree()))
	_debug_panel.add_action("Acciones", "Monocromo on/off",          func(): CharacterAppearance.toggle_monochrome(get_tree()))

	# ── Arquetipos ──
	# Dos acciones por arquetipo, y son distintas: "Ser" cambia TU personaje y además deja la P pegada
	# a ese arquetipo (apretarla repetido da otra variación del mismo); "Spawnear" deja un NPC al lado
	# sin tocar la selección, para comparar dos siluetas a la vez.
	_debug_panel.add_text("Arquetipos", "P respawnea como: %s" % DebugArchetype.label())
	_debug_panel.add_action("Arquetipos", "Ser: aleatorio", func(): _respawn_as(DebugArchetype.NONE))
	for a in EntityArchetype.Archetype.values():
		var be_name := str(EntityArchetype.Archetype.keys()[a])
		_debug_panel.add_action("Arquetipos", "Ser: %s" % be_name, func(): _respawn_as(a))
	for b in EntityArchetype.Archetype.values():
		var spawn_name := str(EntityArchetype.Archetype.keys()[b])
		_debug_panel.add_action("Arquetipos", "Spawnear: %s" % spawn_name,
			func(): _debug_spawn_character(DebugArchetype.seed_for(b)))

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
		"arm       %.2f m  (reach %.2f)  k %.2f" % [sizes.arm_reach, sizes.interaction_reach, arch.arms_length],
		"leg       %.2f m                k %.2f" % [sizes.leg_height, arch.legs_length],
		"fatness   %.2f" % arch.fatness,
		"muscle    %.2f" % arch.muscularity,
	]
	return "\n".join(lines)


func _debug_spawn_pos() -> Vector3:
	var fwd := -player_camera.global_transform.basis.z
	return char_rigidbody.global_position + fwd * 2.5 + Vector3.UP


## Reporta el PICO de velocidad realmente alcanzado contra el tope teórico, y resetea el pico.
##
## Existe porque el tope es una cota, no un objetivo: el personaje acelera hasta que la fuerza aplicada
## se equilibra con lo que lo frena, y eso puede quedar por debajo del tope sin que nada avise. Mirar
## el número en movimiento es imposible (el mouse está capturado), así que se acumula el pico y se
## consulta después.
##
## Uso: apretás el botón para resetear, esprintás en línea recta unos segundos, volvés y lo apretás.
func _debug_measure_speed() -> void:
	var rb := char_rigidbody
	if not is_instance_valid(rb):
		return
	var walk: float = rb.max_speed_forward
	var top: float = walk * rb.sprint_multiplier
	print("── VELOCIDAD ────────────────────────────────────────────────────────────────")
	print("  tope caminando %.2f m/s   tope sprint %.2f m/s" % [walk, top])
	print("  PICO alcanzado %.2f m/s   (%.0f%% del tope de sprint)" % [
		rb.debug_peak_speed, 100.0 * rb.debug_peak_speed / maxf(top, 0.001)])
	print("  actual %.2f m/s   accel base %.2f m/s²   freno %.2f m/s²" % [
		Vector3(rb.linear_velocity.x, 0.0, rb.linear_velocity.z).length(),
		rb.accel_forward / maxf(rb.mass, 0.001), rb.brake_forward / maxf(rb.mass, 0.001)])
	rb.debug_peak_speed = 0.0
	print("  (pico reseteado)")


## Vuelca la geometría REAL de las piernas de todos los personajes en escena, a la consola.
##
## Existe porque la flexión de rodilla la fijan cuatro cosas a la vez —`leg_bentness`, la altura de la
## cápsula, la caída de pelvis y dónde el raycast planta el pie— y calcularla sobre el papel ya falló
## una vez: `MAX_EXTENSION` estaba por debajo del reposo pedido y la pelvis bajaba sola estando quieta.
## Acá se mide lo que efectivamente pasa, con el personaje parado en el juego.
func _debug_measure_legs() -> void:
	print("── PIERNAS ──────────────────────────────────────────────────────────────────")
	for rb in get_tree().get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		var bi := (rb as Node).get_parent() as BoneInstantiator
		if not is_instance_valid(bi) or bi.entity_instantiation == null:
			continue
		var sz := bi.skel_sizes_util
		var arch := bi.entity_instantiation.arch_final
		var name_txt := str(EntityArchetype.Archetype.keys()[bi.entity_instantiation.archetype_type])
		var hip: Node3D = bi.custom_bones_util.left_higher_leg
		var tgt: Node3D = bi.ik_util.left_leg_current_target if is_instance_valid(bi.ik_util) else null
		if not (is_instance_valid(hip) and is_instance_valid(tgt)):
			continue
		var span: float = hip.global_position.distance_to(tgt.global_position)
		var a: float = sz.higher_leg_size.y
		var b: float = sz.lower_leg_size.y
		var cosk: float = clampf((a * a + b * b - span * span) / (2.0 * a * b), -1.0, 1.0)
		var knee: float = 180.0 - rad_to_deg(acos(cosk))
		var drop: float = bi.anim_mod.pelvis_drop if is_instance_valid(bi.anim_mod) else 0.0
		print("  %-11s bent %.2f | pedido %.4f  real %.4f  (drop %.4f)  RODILLA %.1f°" % [
			name_txt, arch.leg_bentness, sz.standing_pelvis_height - sz.ankle_height, span, drop, knee])
		print("               cadera y=%.4f  pie y=%.4f  dx=%.4f dz=%.4f  |  max IK %.4f" % [
			hip.global_position.y, tgt.global_position.y,
			absf(hip.global_position.x - tgt.global_position.x),
			absf(hip.global_position.z - tgt.global_position.z),
			sz.leg_height * SkeletonSizesUtil.MAX_EXTENSION])


## Elige el arquetipo con el que respawnea la P, y respawnea ya. La elección QUEDA PEGADA: después
## alcanza con apretar P para ver otra variación del mismo arquetipo, que es el bucle de autoría.
func _respawn_as(archetype: int) -> void:
	DebugArchetype.selected = archetype
	_respawn()


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


## Deja un NPC parado al lado. No pasa por NetSpawner a propósito: es una ayuda de autoría para mirar
## dos siluetas juntas, no un objeto de la partida.
##
## Sin seed explícita usa la del arquetipo elegido en el panel; los botones "Spawnear: X" pasan la de
## un arquetipo puntual, que NO cambia la selección — así podés ser `kid` y rodearte de `giga`.
func _debug_spawn_character(character_seed: int = -1) -> void:
	var scene := load("res://Scenes/player.tscn") as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate() as BoneInstantiator
	if inst == null:
		return
	inst.is_active = false
	inst.master_seed = character_seed if character_seed >= 0 else DebugArchetype.respawn_seed()
	get_tree().current_scene.add_child(inst)
	inst.global_position = _debug_spawn_pos()


func _debug_spawn(type_name: String) -> void:
	var pos := _debug_spawn_pos()
	# Objetos de escena estáticos (no caen). El asiento se apoya en el piso; el dashboard es un panel
	# de control y va a altura de uso, sobre el piso. Las cajas son rigidbodies: caen solas.
	if type_name == "seat":
		pos = _snap_to_ground(pos)
	elif type_name == "dashboard":
		pos = _snap_to_ground(pos) + Vector3.UP * 1.5
	NetSpawner.request_spawn(type_name, Transform3D(Basis(), pos))

## Baja un punto hasta el piso con un raycast (para spawnear objetos estáticos apoyados).
func _snap_to_ground(from: Vector3) -> Vector3:
	var space := char_rigidbody.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.DOWN * 20.0)
	q.exclude = [char_rigidbody.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position if hit else from
