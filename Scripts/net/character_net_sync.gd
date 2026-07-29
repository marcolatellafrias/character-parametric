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
## Manda pos/yaw/velocidad (movimiento) + impacto (stagger) + crouch/jump/throw (pose). Todo lo que
## el proxy NO puede derivar solo (grounded/pasos SÍ los deriva local). El agarre (brazos a handle
## points) es aparte. Sin MultiplayerSynchronizer: el remoto interpola, no re-simula.
## Ver Scripts/city/docs/conceptual/multiplayer.md y technical/character-animation.md.

## Delay de render para la interpolación (mostramos el pasado reciente).
const INTERP_DELAY_MS := 100.0
## Tope de extrapolación cuando el último estado quedó atrás (paquete perdido/tardío).
const MAX_EXTRAPOLATION_S := 0.15
const BUFFER_MAX := 20

## [{t, pos, yaw, vel, impact_xz, impact_y, crouch, jump, throw_t, throw_push, throw_dir}]
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
	_receive_state.rpc(rb.global_position, rb.rotation.y, rb.linear_velocity, rb.impact_xz, rb.impact_y,
		bi.crouch_t, bi.jump_squat_t, throw_t, throw_push, throw_dir)

@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_state(pos: Vector3, yaw: float, vel: Vector3, impact_xz: Vector2, impact_y: float,
		crouch: float, jump: float, throw_t: float, throw_push: float, throw_dir: Vector3) -> void:
	_buffer.append({
		"t": Time.get_ticks_msec(), "pos": pos, "yaw": yaw, "vel": vel,
		"impact_xz": impact_xz, "impact_y": impact_y,
		"crouch": crouch, "jump": jump,
		"throw_t": throw_t, "throw_push": throw_push, "throw_dir": throw_dir})
	while _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()

# ── Remoto: interpolar y aplicar al puppet ────────────────────────────────────

## Aplica el estado sincronizado (transform + pose) a la cápsula puppet. Lo llama el
## BoneInstantiator al INICIO de su _physics_process, ANTES del solve del esqueleto, para que los
## IK targets (raycasts de pies, brazos, poles) se construyan con el yaw de este frame.
func apply_to_puppet() -> void:
	if is_multiplayer_authority():
		return  # el dueño no es puppet
	var rb := _rigidbody()
	var bi := get_parent() as BoneInstantiator
	if not is_instance_valid(rb) or not is_instance_valid(bi) or _buffer.is_empty():
		return

	var s := _sample_at(float(Time.get_ticks_msec()) - INTERP_DELAY_MS)

	rb.global_position = s["pos"]
	rb.rotation.y = s["yaw"]
	rb.puppet_velocity = s["vel"]   # alimenta la animación de caminado
	rb.impact_xz = s["impact_xz"]   # stagger de choques/empujes
	rb.impact_y = s["impact_y"]     # stagger de salto/aterrizaje
	bi.crouch_t = s["crouch"]
	bi.jump_squat_t = s["jump"]
	if is_instance_valid(bi.anim_mod):
		bi.anim_mod.throw_t = s["throw_t"]
		bi.anim_mod.throw_push_t = s["throw_push"]
		bi.anim_mod.throw_world_dir = s["throw_dir"]

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
		"throw_dir": (a["throw_dir"] as Vector3).lerp(b["throw_dir"], f)}

func _rigidbody() -> CharacterRigidBody3D:
	var bi := get_parent() as BoneInstantiator
	return bi.char_rigidbody if is_instance_valid(bi) else null

# ── Agarre: sincronizar qué objeto agarra cada jugador ────────────────────────
# Solo se sincroniza la REFERENCIA al grabbable (mismo path en todas las máquinas). Los brazos a los
# handle points los arma el proxy local con su propio esqueleto. Ver character-animation.md (bug 3).

## El grabbable que agarra este personaje (o null). Local = propio, proxy = sincronizado.
var grab_target: Node = null

## Lo llama el InteractionController local al agarrar/soltar (grabbable o null).
func set_grab_target(grabbable: Node) -> void:
	grab_target = grabbable
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_receive_grab.rpc(grabbable.get_path() if is_instance_valid(grabbable) else NodePath())

@rpc("authority", "reliable", "call_remote")
func _receive_grab(path: NodePath) -> void:
	grab_target = null if path.is_empty() else get_node_or_null(path)

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

## Proxy: le pide el seed actual al dueño (por si reseedó antes de que yo me uniera). Lo llama el
## CharacterSpawner al crear el proxy.
func request_seed_if_proxy() -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_request_seed.rpc_id(get_multiplayer_authority())

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
