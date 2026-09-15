class_name PlayerController
extends Node

var head_bone: CustomBone
var head_size: Vector3
var char_rigidbody: CharacterRigidBody3D
var player_camera: Camera3D
var is_ready: bool = false

var camera_pitch: float = 0.0
var camera_yaw: float = 0.0

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

## Tercera persona de debug, con el numpad: ver DebugOrbitCamera. Solo visual — el rayo de interacción
## sale siempre de `player_camera`.
var _third_person: bool = false
var _debug_camera: DebugOrbitCamera = null

var _hud: PlayerHUD = null
var _impact_debug_hud: ImpactDebugHUD = null
var _prev_fall_rb: CharacterRigidBody3D = null

var interaction_controller: InteractionController = null
var arms_controller: ArmsController = null

var _creative: bool = false
var _debug_panel: DebugPanel = null
## El identificador de piezas de la ciudad del F1 (ver CityInspector). Se usa con el panel CERRADO: el
## panel libera el mouse y entonces no se puede apuntar.
var _inspector: CityInspector = null
## Si el inspector está prendido. Vive acá y no en el inspector porque el inspector se rehace en cada
## respawn; así el modo sobrevive a morir, que es cuando más se lo quiere seguir usando.
var _inspector_on := false
var _inspector_toggle: CheckButton = null
var _map_overlay: CityMapOverlay = null
var _weather_tuner: WeatherTuner = null
var _terrain_tuner: TerrainTuner = null
var _view_tuner: ViewTuner = null

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
	_set_third_person(_third_person)
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

	_debug_camera = DebugOrbitCamera.new()
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
		player_camera.current  = not _third_person

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

	# F6, el afinador del clima y las nubes. Este SI libera el mouse (se anota en UIState): hay que
	# arrastrar sliders.
	if is_instance_valid(_weather_tuner) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F6:
		_weather_tuner.toggle()
		return

	# F7, el afinador del terreno y las afueras. Igual que el de clima: libera el mouse.
	if is_instance_valid(_terrain_tuner) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F7:
		_terrain_tuner.toggle()
		return

	# F3, el afinador de vista de la ciudad. Como los otros dos: libera el mouse.
	if is_instance_valid(_view_tuner) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		_view_tuner.toggle()
		return

	# I prende/apaga el inspector. Va antes del corte de gameplay a propósito: se usa todo el tiempo, y el
	# inspector ya funciona sin robar el mouse. Es una letra y no una F porque se aprieta mientras se juega.
	if is_instance_valid(_inspector) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_I:
		_set_inspector(not _inspector_on)
		if is_instance_valid(_inspector_toggle):
			_inspector_toggle.set_pressed_no_signal(_inspector_on)
		return

	# LA RUEDITA PRESIONADA copia al portapapeles lo que se está mirando, para pegarlo en un chat. Es el mouse
	# y no una tecla porque va con el gesto de apuntar: se mira y se hace clic. Solo se la come con el
	# inspector prendido, así con el inspector apagado queda libre para cualquier otro uso.
	if _inspector_on and is_instance_valid(_inspector) and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_inspector.copy_to_clipboard()
		return

	# F2, el mapa de al lado: a diferencia del panel, no bloquea el gameplay —se mira en movimiento—.
	if is_instance_valid(_map_overlay) and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F2:
		_map_overlay.toggle()
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

				# Cámara de debug (numpad): ver DebugOrbitCamera
				KEY_KP_5: _set_third_person(not _third_person)
				_:
					if is_instance_valid(_debug_camera) and _debug_camera.handle_key(event.keycode, camera_yaw):
						_set_third_person(true)

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

	# La cámara del jugador se mueve también en tercera persona, aunque no esté en pantalla: de ella sale
	# el rayo de interacción, que tiene que ser el mismo en las dos vistas.
	# Va exacta a la cabeza, sin suavizar: suavizada en el mundo, todo lo que te lleva (la nave subiendo)
	# le parecía una sacudida y la vista quedaba atrasada.
	player_camera.global_position.y = head_bone.global_position.y + head_size.y * 0.5
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
	if rd != null and is_instance_valid(rd.head_body):
		player_camera.global_position = rd.head_body.global_position
	player_camera.global_rotation = Vector3(camera_pitch, camera_yaw, 0.0)
	if rd != null and rd.is_recovering:
		char_rigidbody.rotation.y = camera_yaw


## true cuando la cámara activa es la del jugador (no una de debug), o sea cuando hay que esconderle
## la cabeza y el torso. Lo lee BoneInstantiator al final de initialize_skeleton para aplicar el
## estado correcto en el build/respawn, no solo cuando cambiás de cámara.
func is_first_person_view() -> bool:
	return not _third_person

func _set_third_person(on: bool) -> void:
	_third_person = on
	if on:
		_debug_camera.ensure_view(camera_yaw)
		_debug_camera.set_active(true)
		player_camera.current = false
	else:
		player_camera.current = true
		_debug_camera.set_active(false)
	var bi := _get_bi()
	if is_instance_valid(bi):
		bi.set_first_person_visibility(not on)


func _update_debug_camera(delta: float) -> void:
	if not _third_person or not is_instance_valid(_debug_camera):
		return
	# Encuadre derivado del personaje, no de constantes en metros: la cámara mira a su CENTRO.
	var sizes  := _get_bi().skel_sizes_util
	var ground := char_rigidbody.global_position.y - sizes.standing_pelvis_height
	var center := Vector3(char_rigidbody.global_position.x, ground + sizes.total_height * 0.5, char_rigidbody.global_position.z)
	_debug_camera.follow(delta, center, sizes.total_height, interaction_controller.detector.get_aim_point())


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

	_set_third_person(_third_person)
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


func _set_inspector(on: bool) -> void:
	_inspector_on = on
	if is_instance_valid(_inspector):
		_inspector.set_enabled(on)


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
	_debug_panel.add_action("Acciones", "Ver wireframe",             func(): CharacterDebugView.toggle_wireframe(get_tree()))
	_debug_panel.add_action("Acciones", "Indicadores de tráfico",    func(): TrafficDebugDrawer.ENABLED = not TrafficDebugDrawer.ENABLED)
	_debug_panel.add_action("Acciones", "Nave: paredes traslúcidas", func(): Ship.toggle_translucent_walls(get_tree()))
	_debug_panel.add_action("Acciones", "Neblina", func(): CityDebugView.toggle_fog(get_tree()))

	# Identificar lo que se apunta. Se prende acá y se USA con el panel cerrado, porque el panel libera el
	# mouse y sin mouse capturado no se puede apuntar.
	if is_instance_valid(_inspector):
		_inspector.queue_free()
	_inspector = CityInspector.new()
	add_child(_inspector)
	_inspector.setup(player_camera, char_rigidbody)
	_inspector.set_enabled(_inspector_on)
	_inspector_toggle = _debug_panel.add_toggle("Acciones", "Apuntar para identificar (I · ruedita copia)",
		_inspector_on, _set_inspector)

	# ── Arquetipos ──
	# Dos acciones por arquetipo, y son distintas: "Ser" cambia TU personaje y además deja la P pegada
	# a ese arquetipo (apretarla repetido da otra variación del mismo); "Spawnear" deja un NPC al lado
	# sin tocar la selección, para comparar dos siluetas a la vez.
	_debug_panel.add_text("Arquetipos", "P respawnea como: %s" % DebugArchetype.label())
	_debug_panel.add_action("Arquetipos", "Ser: aleatorio", func(): _respawn_as(DebugArchetype.NONE))
	for a in EntityArchetype.Archetype.values():
		var be_name := str(EntityArchetype.Archetype.keys()[a])
		_debug_panel.add_action("Arquetipos", "Ser: %s" % be_name, func(): _respawn_as(a))
	_debug_panel.add_action("Arquetipos", "Spawnear: aleatorio",
		func(): _debug_spawn_character(DebugArchetype.free_seed()))
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
	_debug_panel.add_action("Spawn", "Nave domo (1 jugador)",     func(): _debug_spawn_ship(Ship.Shape.DOME, 1))
	_debug_panel.add_action("Spawn", "Nave domo (4 jugadores)",   func(): _debug_spawn_ship(Ship.Shape.DOME, 4))
	_debug_panel.add_action("Spawn", "Nave cúbica (1 jugador)",   func(): _debug_spawn_ship(Ship.Shape.BOX, 1))
	_debug_panel.add_action("Spawn", "Nave cúbica (4 jugadores)", func(): _debug_spawn_ship(Ship.Shape.BOX, 4))
	_debug_panel.add_action("Spawn", "Nave cúbica chica (3 jugadores)", func(): _debug_spawn_ship(Ship.Shape.SMALL_BOX, 3))
	_debug_panel.add_action("Spawn", "Limpiar spawns",     _clear_spawns)

	# ── Mapa ──
	# El mapa se centra y se teletransporta sobre la cápsula propia (ver CityMap).
	var map := CityMap.new()
	map.player = char_rigidbody
	_debug_panel.add_action("Mapa", "Centrar en mí", map.center_on_player)
	_debug_panel.add_control("Mapa", map)

	# Y el mismo mapa, chico y en la esquina, para mirar en movimiento (F2).
	if is_instance_valid(_map_overlay):
		_map_overlay.queue_free()
	_map_overlay = CityMapOverlay.new()
	_map_overlay.setup(char_rigidbody)
	add_child(_map_overlay)

	# ── Clima ── el afinador de F6: clima, alcance de la niebla y nubes.
	if is_instance_valid(_weather_tuner):
		_weather_tuner.queue_free()
	_weather_tuner = WeatherTuner.new()
	add_child(_weather_tuner)
	_weather_tuner.setup_panel()

	# Y el del terreno y las afueras (F7).
	if is_instance_valid(_terrain_tuner):
		_terrain_tuner.queue_free()
	_terrain_tuner = TerrainTuner.new()
	add_child(_terrain_tuner)
	_terrain_tuner.setup_panel()

	# Y el de vista (F3).
	if is_instance_valid(_view_tuner):
		_view_tuner.queue_free()
	_view_tuner = ViewTuner.new()
	add_child(_view_tuner)
	_view_tuner.setup_panel()

	# ── Performance ──
	PerformanceToggles.build_tab(_debug_panel, get_tree())


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

## Cuánto aire queda entre el jugador y la nave que spawnea: su centro va a su medio ancho más esto, así el
## casco no nace encima de nadie y la compuerta queda a mano.
const SHIP_SPAWN_GAP := 1.5

## Deja la nave prototipo adelante del jugador, apoyada en el piso, con la compuerta mirándolo.
##
## Como el NPC de `_debug_spawn_character`, NO pasa por NetSpawner: NetSpawner le cuelga sync de red
## y un Grabbable a todo RigidBody3D que spawnea, y la nave terminaría siendo algo que se puede agarrar.
## Pueden convivir varias: la nueva nace sin tocar a las demás.
func _debug_spawn_ship(shape: Ship.Shape, crew: int) -> void:
	var scene_root := get_tree().current_scene
	var fwd := -player_camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	# Las naves conviven: la nueva se corre hacia adelante hasta no tocar ninguna. Si naciera encima de otra,
	# el rayo que busca el piso le pegaría a su techo; si naciera adentro, el motor las separaría de golpe.
	var hull := Ship.hull_for(shape)
	var at := char_rigidbody.global_position + fwd * (hull.half_extent() + SHIP_SPAWN_GAP)
	for _step in 50:
		var clear := true
		for other in get_tree().get_nodes_in_group(Ship.GROUP):
			var o := (other as Node3D).global_position
			var separation := hull.bounding_radius() + (other as Ship).hull.bounding_radius() + 0.5
			if Vector2(o.x - at.x, o.z - at.z).length() < separation:
				clear = false
				break
		if clear:
			break
		at += fwd
	var ground := _snap_to_ground(at)
	var ship := Ship.new()
	ship.name = "ship_debug"
	ship.shape = shape
	ship.crew_size = crew
	# El frente de la nave (−Z) apunta para donde mira el jugador: la compuerta queda de su lado. El
	# transform va ANTES de entrar al árbol, así la nave arranca con su altura real.
	ship.transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), ground)
	# Con nombre legible y único: "ship_debug", "ship_debug2"…
	scene_root.add_child(ship, true)


## Limpia todo lo spawneado: lo del NetSpawner y las naves, que se crean aparte (ver `_debug_spawn_ship`).
## Una nave con alguien sentado lo suelta sola al salir del árbol (ver SeatInteractable._exit_tree).
func _clear_spawns() -> void:
	NetSpawner.request_clear_all()
	for ship in get_tree().get_nodes_in_group(Ship.GROUP):
		ship.queue_free()

## Baja un punto hasta el piso con un raycast (para spawnear objetos estáticos apoyados).
func _snap_to_ground(from: Vector3) -> Vector3:
	var space := char_rigidbody.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.DOWN * 20.0)
	q.exclude = [char_rigidbody.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position if hit else from
