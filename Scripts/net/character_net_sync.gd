class_name CharacterNetSync
extends Node
## Replicación del estado de animación de un personaje (milestones 2/3 de multiplayer).
##
## Se cuelga como hijo "NetSync" del personaje (un BoneInstantiator) tanto en el jugador local como
## en cada proxy remoto, con el MISMO path en todas las máquinas para que el RPC rutee. Su
## multiplayer_authority es el peer dueño:
##   - En la máquina del dueño: lee la cápsula/controllers y transmite el estado cada tick físico.
##   - En las demás: bufferea (con timestamp local) e interpola, y lo aplica a la cápsula puppet.
##
## Manda pos/yaw/velocidad (movimiento) + impacto (stagger) + crouch/jump/throw + head pitch (pose).
## Todo lo que el proxy NO puede derivar solo (grounded/pasos SÍ los deriva local). El agarre (brazos
## a handle points) es aparte. Sin MultiplayerSynchronizer: el remoto interpola, no re-simula.
## Ver Scripts/city/docs/conceptual/multiplayer.md y technical/character-animation.md.

## Delay de render para la interpolación (mostramos el pasado reciente).
const INTERP_DELAY_MS := 100.0
## Tope de extrapolación cuando el último estado quedó atrás (paquete perdido/tardío).
const MAX_EXTRAPOLATION_S := 0.15
const BUFFER_MAX := 20

## [{t, pos, yaw, vel, impact_xz, impact_y, crouch, jump, throw_t, throw_push, throw_dir, pitch, ragdoll}]
var _buffer: Array = []

func _physics_process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return  # offline: el jugador local simula normal, nada que sincronizar.
	# La autoridad transmite acá. Los proxies NO aplican en este _physics_process: como NetSync es
	# hijo del BoneInstantiator, correría DESPUÉS de su solve y los IK targets quedarían un frame
	# atrás del cuerpo (raycasts/brazos desfasados al girar). Por eso el BoneInstantiator llama a
	# apply_to_puppet() al INICIO de su frame, antes del solve.
	if is_multiplayer_authority():
		_send_state()

# ── Authority: transmitir ─────────────────────────────────────────────────────

func _send_state() -> void:
	var rb := _rigidbody()
	if not is_instance_valid(rb):
		return  # entre respawns la cápsula puede no existir por un frame.
	var bi := get_parent() as BoneInstantiator
	var throw_t := 0.0
	var throw_push := 0.0
	var throw_dir := Vector3.FORWARD
	if is_instance_valid(bi.anim_mod):
		throw_t = bi.anim_mod.throw_t
		throw_push = bi.anim_mod.throw_push_t
		throw_dir = bi.anim_mod.throw_world_dir
	var ragdoll := is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_active
	_receive_state.rpc(rb.global_position, rb.rotation.y, rb.linear_velocity, rb.impact_xz, rb.impact_y,
		bi.crouch_t, bi.jump_squat_t, throw_t, throw_push, throw_dir, bi.head_pitch, ragdoll)

@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_state(pos: Vector3, yaw: float, vel: Vector3, impact_xz: Vector2, impact_y: float,
		crouch: float, jump: float, throw_t: float, throw_push: float, throw_dir: Vector3,
		pitch: float, ragdoll: bool) -> void:
	_buffer.append({
		"t": Time.get_ticks_msec(), "pos": pos, "yaw": yaw, "vel": vel,
		"impact_xz": impact_xz, "impact_y": impact_y,
		"crouch": crouch, "jump": jump,
		"throw_t": throw_t, "throw_push": throw_push, "throw_dir": throw_dir,
		"pitch": pitch, "ragdoll": ragdoll})
	while _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()

# ── Remoto: interpolar y aplicar al puppet ────────────────────────────────────

## Aplica el estado sincronizado (transform + pose) a la cápsula puppet. Lo llama el
## BoneInstantiator al INICIO de su _physics_process, ANTES del solve del esqueleto, para que los
## IK targets (raycasts de pies, brazos, poles) se construyan con el yaw de este frame.
func apply_to_puppet() -> void:
	if is_multiplayer_authority():
		return  # el dueño no es puppet
	if not _pending_grab_path.is_empty() or not _pending_seat_path.is_empty():
		_resolve_pending()  # el objeto referenciado pudo llegar recién ahora (join)
	var rb := _rigidbody()
	var bi := get_parent() as BoneInstantiator
	if not is_instance_valid(rb) or not is_instance_valid(bi) or _buffer.is_empty():
		return

	var s := _sample_at(float(Time.get_ticks_msec()) - INTERP_DELAY_MS)

	# Ragdoll: replicamos el estado y el proxy corre su PROPIO ragdoll local. La física no es
	# determinística entre máquinas → es una aproximación (un cuerpo flojo cerca de la posición
	# correcta), no un calco. Durante el ragdoll ACTIVO el sim local maneja la cápsula/pose, así que
	# no pisamos con el transform sincronizado; en la recuperación sí (para volver a la pos del dueño).
	# Ver conceptual/multiplayer.md (Causa C).
	_drive_proxy_ragdoll(bi, rb, s["ragdoll"])
	if is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_active:
		return

	rb.global_position = s["pos"]
	rb.rotation.y = s["yaw"]
	rb.puppet_velocity = s["vel"]   # alimenta la animación de caminado
	rb.impact_xz = s["impact_xz"]   # stagger de choques/empujes
	rb.impact_y = s["impact_y"]     # stagger de salto/aterrizaje
	bi.crouch_t = s["crouch"]
	bi.jump_squat_t = s["jump"]
	bi.head_pitch = s["pitch"]      # mirar arriba/abajo (el productor lo copia a AnimationInputs)
	if is_instance_valid(bi.anim_mod):
		bi.anim_mod.throw_t = s["throw_t"]
		bi.anim_mod.throw_push_t = s["throw_push"]
		bi.anim_mod.throw_world_dir = s["throw_dir"]

## Enciende/apaga el ragdoll LOCAL del proxy según el flag sincronizado (en flancos). El proxy no
## detecta impactos (es puppet), así que su ragdoll solo lo dispara esto. Al salir, deactivate arranca
## la recuperación local y hay que restaurar el estado puppet (deactivate des-congela la cápsula).
func _drive_proxy_ragdoll(bi: BoneInstantiator, rb: CharacterRigidBody3D, want: bool) -> void:
	var rd := bi.ragdoll_util
	if not is_instance_valid(rd):
		return
	if want and not rd.is_active:
		rd.activate(rb, bi.custom_bones_util.lower_spine)
	elif not want and rd.is_active:
		rd.deactivate(rb, bi.custom_bones_util.lower_spine)
		rb.setup_as_puppet()  # restaurar puppet (kinemático, sin gravedad): deactivate lo des-congeló

## Estado interpolado al tiempo de render (extrapola con la velocidad si va por delante del buffer).
func _sample_at(render_t: float) -> Dictionary:
	var newest: Dictionary = _buffer[_buffer.size() - 1]
	if render_t >= float(newest["t"]):
		var ahead: float = min((render_t - float(newest["t"])) / 1000.0, MAX_EXTRAPOLATION_S)
		var s := newest.duplicate()
		s["pos"] = (newest["pos"] as Vector3) + (newest["vel"] as Vector3) * ahead
		return s
	var oldest: Dictionary = _buffer[0]
	if render_t <= float(oldest["t"]):
		return oldest
	for i in range(_buffer.size() - 1):
		var a: Dictionary = _buffer[i]
		var b: Dictionary = _buffer[i + 1]
		if render_t >= float(a["t"]) and render_t <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var f: float = 0.0 if span <= 0.0 else (render_t - float(a["t"])) / span
			return _lerp_state(a, b, f)
	return newest

func _lerp_state(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	return {
		"pos": (a["pos"] as Vector3).lerp(b["pos"], f),
		"yaw": lerp_angle(a["yaw"], b["yaw"], f),
		"vel": (a["vel"] as Vector3).lerp(b["vel"], f),
		"impact_xz": (a["impact_xz"] as Vector2).lerp(b["impact_xz"], f),
		"impact_y": lerpf(a["impact_y"], b["impact_y"], f),
		"crouch": lerpf(a["crouch"], b["crouch"], f),
		"jump": lerpf(a["jump"], b["jump"], f),
		"throw_t": lerpf(a["throw_t"], b["throw_t"], f),
		"throw_push": lerpf(a["throw_push"], b["throw_push"], f),
		"throw_dir": (a["throw_dir"] as Vector3).lerp(b["throw_dir"], f),
		"pitch": lerpf(a["pitch"], b["pitch"], f),
		"ragdoll": a["ragdoll"]}  # bool: tomamos el del estado más viejo (mismo delay que la posición)

func _rigidbody() -> CharacterRigidBody3D:
	var bi := get_parent() as BoneInstantiator
	return bi.char_rigidbody if is_instance_valid(bi) else null

# ── Agarre: sincronizar qué objeto agarra cada jugador ────────────────────────
# Solo se sincroniza la REFERENCIA al grabbable (mismo path en todas las máquinas). Los brazos a los
# handle points los arma el proxy local con su propio esqueleto. Ver character-animation.md (bug 3).

## El objeto de interacción cuyos handle/grab points alcanzan los brazos: un grabbable agarrado o un
## controllable que se está manejando (o null). Local = propio, proxy = sincronizado.
var grab_target: Node = null
## Path pendiente de resolver (proxy): el objeto puede no existir aún al unirse. Vacío = nada pendiente.
var _pending_grab_path: NodePath = NodePath()

## Lo llama el InteractionController local al agarrar/controlar/soltar (el interactuable o null).
func set_grab_target(grabbable: Node) -> void:
	grab_target = grabbable
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_receive_grab.rpc(grabbable.get_path() if is_instance_valid(grabbable) else NodePath())

@rpc("authority", "reliable", "call_remote")
func _receive_grab(path: NodePath) -> void:
	_pending_grab_path = path
	grab_target = null
	_resolve_pending()  # resuelve ya si el objeto existe; si no, se reintenta cada frame

# ── Empuje: aplicar un impulso a un compañero (Causa B) ───────────────────────
# La cápsula del compañero es un proxy congelado en MI máquina, así que el impulso se lo mando a SU
# máquina (donde es dinámica y él es la autoridad), que lo aplica y lo replica de vuelta.

## Empujá a este personaje con un impulso. Lo aplica su dueño (autoridad); si no soy yo, se lo mando.
func push(impulse: Vector3) -> void:
	if not multiplayer.has_multiplayer_peer():
		return  # offline solo existe el jugador local; no hay compañero que empujar
	if is_multiplayer_authority():
		_apply_push(impulse)
	else:
		_receive_push.rpc_id(get_multiplayer_authority(), impulse)

@rpc("any_peer", "reliable")
func _receive_push(impulse: Vector3) -> void:
	if is_multiplayer_authority():
		_apply_push(impulse)

func _apply_push(impulse: Vector3) -> void:
	var rb := _rigidbody()
	if is_instance_valid(rb) and not rb.is_puppet:
		rb.apply_central_impulse(impulse)

# ── Sentado: sincronizar en qué asiento está cada jugador ──────────────────────
# Análogo al grab: solo viaja la REFERENCIA al asiento (mismo path en todas las máquinas, spawn con
# nombre estable). El pose sentado lo arma cada proxy corriendo el mismo _solve_seated_frame con su
# propio esqueleto. Ver technical/character-animation.md.

## El asiento que ocupa este personaje (o null). Local = propio, proxy = sincronizado.
var seat_target: Node = null
## Path pendiente de resolver (proxy): el asiento puede no existir aún al unirse. Vacío = nada pendiente.
var _pending_seat_path: NodePath = NodePath()

## Lo llama el SeatInteractable local al sentarse/pararse (el asiento o null).
func set_seat_target(seat: Node) -> void:
	seat_target = seat
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_receive_seat.rpc(seat.get_path() if is_instance_valid(seat) else NodePath())

@rpc("authority", "reliable", "call_remote")
func _receive_seat(path: NodePath) -> void:
	_pending_seat_path = path
	seat_target = null
	_resolve_pending()  # resuelve ya si el asiento existe; si no, se reintenta cada frame

## Resuelve los paths pendientes de grab/seat. El estado (grab/seat) puede llegar ANTES de que el
## objeto exista acá: al unirse, el snapshot de objetos (NetSpawner) y el estado del personaje son
## async. Reintentamos cada frame hasta que el nodo aparezca, así el orden deja de importar. Lo llama
## apply_to_puppet mientras haya algo pendiente.
func _resolve_pending() -> void:
	if not _pending_grab_path.is_empty():
		var g := get_node_or_null(_pending_grab_path)
		if is_instance_valid(g):
			grab_target = g
			_pending_grab_path = NodePath()
	if not _pending_seat_path.is_empty():
		var st := get_node_or_null(_pending_seat_path)
		if is_instance_valid(st):
			seat_target = st
			_pending_seat_path = NodePath()

# ── Seed / aspecto: sincronizar el reseed (respawn con P) ──────────────────────
# El aspecto normalmente sale del seed derivado del steam_id (igual en todas las máquinas, sin
# sincronizar). Pero el reseed local rompe ese supuesto, así que el dueño transmite su seed nuevo.

## Dueño: transmite su seed actual a todos. Se llama al reseedear.
func broadcast_seed() -> void:
	if not multiplayer.has_multiplayer_peer() or not is_multiplayer_authority():
		return
	var bi := get_parent() as BoneInstantiator
	if is_instance_valid(bi):
		_receive_seed.rpc(bi.master_seed)

## Proxy: al crear el proxy (join), le pide al dueño su estado actual que no viaja continuo — el seed
## (por si reseedó antes de que me uniera) y las referencias de sentado/grab (por si ya estaba
## sentado o sosteniendo algo). Lo llama el CharacterSpawner. Las refs se resuelven lazy (ver
## _resolve_pending): el objeto referenciado puede llegar después por el snapshot de NetSpawner.
func request_state_if_proxy() -> void:
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		return
	_request_seed.rpc_id(get_multiplayer_authority())
	_request_interaction_state.rpc_id(get_multiplayer_authority())

@rpc("any_peer", "reliable")
func _request_interaction_state() -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	_receive_grab.rpc_id(sender, grab_target.get_path() if is_instance_valid(grab_target) else NodePath())
	_receive_seat.rpc_id(sender, seat_target.get_path() if is_instance_valid(seat_target) else NodePath())

@rpc("any_peer", "reliable")
func _request_seed() -> void:
	if not is_multiplayer_authority():
		return
	var bi := get_parent() as BoneInstantiator
	if is_instance_valid(bi):
		_receive_seed.rpc_id(multiplayer.get_remote_sender_id(), bi.master_seed)

## Proxy: recibe el seed del dueño y reconstruye el esqueleto si cambió.
@rpc("authority", "reliable", "call_remote")
func _receive_seed(seed_value: int) -> void:
	var bi := get_parent() as BoneInstantiator
	if not is_instance_valid(bi) or bi.master_seed == seed_value:
		return
	bi.master_seed = seed_value
	bi.initialize_skeleton()  # reconstruye el aspecto; net_sync sobrevive (es hijo directo del bi)
	apply_to_puppet()         # reposiciona la cápsula nueva ya, evita el flash en el origen
	var spawner := get_tree().get_first_node_in_group("character_spawner") as CharacterSpawner
	if is_instance_valid(spawner):
		spawner.reattach_name_tag(bi, get_multiplayer_authority())  # el tag viejo se fue con la cápsula
