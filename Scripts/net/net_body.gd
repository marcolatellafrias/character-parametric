class_name NetBody
extends Node
## Sincronización de un cuerpo físico (RigidBody3D padre) por red. Generaliza el patrón de la
## cápsula puppet: la AUTORIDAD simula normal y transmite transform+velocidad cada tick; las
## demás congelan el cuerpo (freeze kinematic) e interpolan. Sin predicción ni rollback.
##
## Agarre co-op (M4): el host lleva el registro de quiénes agarran el cuerpo. El primer
## agarrador se vuelve autoridad (lo simula local, responsivo); los demás quedan de co-grabbers
## y mandan su INTENCIÓN (grab point + a dónde tiran) a la autoridad, que suma esas fuerzas. Al
## soltar la autoridad, se promueve al siguiente que quede agarrando (o vuelve al host). La
## velocidad se transfiere al cambiar de autoridad para no perder un throw.
## Ver Scripts/city/docs/conceptual/multiplayer.md.

const INTERP_DELAY_MS := 100.0
const MAX_EXTRAP_S := 0.15
const BUFFER_MAX := 20
const INTENT_TIMEOUT_MS := 200

## [{t: int(ms local), pos: Vector3, rot: Quaternion, vel: Vector3}]
var _buffer: Array = []
## Intenciones de agarre de co-grabbers (solo se usan si somos autoridad).
## peer_id -> {offset: Vector3(local), target: Vector3, stiffness: float, damping: float, t: int}
var _intents: Dictionary = {}
## Solo en el host: peers que están agarrando este cuerpo (para promover autoridad al soltar).
var _grabbers: Array = []
## Dormancy: true cuando el cuerpo está dormido (quieto) y dejamos de transmitir. La autoridad lo
## maneja desde body.sleeping; los remotos ni lo miran (ya asentaron en el último estado recibido).
var _dormant: bool = false

# ── Autoridad / freeze ────────────────────────────────────────────────────────

## Fija quién simula este cuerpo y (re)configura el freeze según corresponda.
func set_body_authority(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	_intents.clear()  # las intenciones eran para la autoridad anterior
	_dormant = false  # al (re)tomar autoridad arrancamos despiertos hasta que la física duerma el cuerpo
	_configure()
	# Al TOMAR la autoridad, arrancamos con la última velocidad conocida, así un throw no se
	# pierde al cambiar de autoridad (los cuerpos freeze reportan velocidad 0).
	if is_multiplayer_authority() and not _buffer.is_empty():
		var body := get_parent() as RigidBody3D
		if body != null:
			body.linear_velocity = _buffer[_buffer.size() - 1]["vel"]

func _configure() -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	var remote := multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()
	if remote:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = remote

func _physics_process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return  # offline: el cuerpo simula normal, nada que sincronizar.
	if is_multiplayer_authority():
		_apply_intents()  # co-grabbers empujando este cuerpo
		_stream_if_awake()
	else:
		_apply_interpolation()

# ── Transmisión / interpolación ───────────────────────────────────────────────

## Dormancy: mientras el cuerpo se mueve o lo agarran, transmitimos cada tick; cuando la física lo
## duerme (quieto), mandamos UN último estado en reposo (vel ~0, así los remotos asientan y no
## extrapolan) y dejamos de transmitir — 0 bytes. Al despertar (choque, empuje, agarre) volvemos a
## streamear. Es lo que escala a cientos de objetos: los estáticos no cuestan ancho de banda.
func _stream_if_awake() -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	if body.sleeping:
		if not _dormant:
			_dormant = true
			_send_state()
		return
	_dormant = false
	_send_state()

func _send_state() -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	var t := body.global_transform
	_receive_state.rpc(t.origin, t.basis.get_rotation_quaternion(), body.linear_velocity)

@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_state(pos: Vector3, rot: Quaternion, vel: Vector3) -> void:
	_buffer.append({"t": Time.get_ticks_msec(), "pos": pos, "rot": rot, "vel": vel})
	while _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()

func _apply_interpolation() -> void:
	var body := get_parent() as RigidBody3D
	if body == null or _buffer.is_empty():
		return

	var render_t := float(Time.get_ticks_msec()) - INTERP_DELAY_MS
	var newest: Dictionary = _buffer[_buffer.size() - 1]

	var pos: Vector3
	var rot: Quaternion

	if render_t >= float(newest["t"]):
		var ahead: float = min((render_t - float(newest["t"])) / 1000.0, MAX_EXTRAP_S)
		pos = (newest["pos"] as Vector3) + (newest["vel"] as Vector3) * ahead
		rot = newest["rot"]
	else:
		var oldest: Dictionary = _buffer[0]
		if render_t <= float(oldest["t"]):
			pos = oldest["pos"]
			rot = oldest["rot"]
		else:
			pos = newest["pos"]
			rot = newest["rot"]
			for i in range(_buffer.size() - 1):
				var a: Dictionary = _buffer[i]
				var b: Dictionary = _buffer[i + 1]
				if render_t >= float(a["t"]) and render_t <= float(b["t"]):
					var span := float(b["t"]) - float(a["t"])
					var f: float = 0.0 if span <= 0.0 else (render_t - float(a["t"])) / span
					pos = (a["pos"] as Vector3).lerp(b["pos"], f)
					rot = (a["rot"] as Quaternion).slerp(b["rot"], f)
					break

	body.global_transform = Transform3D(Basis(rot), pos)

# ── Agarre: registro de grabbers y promoción de autoridad ─────────────────────

## Lo llama quien empieza a agarrar. El host lo registra y, si el cuerpo está libre, lo hace
## autoridad; si ya lo tiene otro, queda de co-grabber (manda intención).
func begin_grab() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_host_add_grabber(multiplayer.get_unique_id())
	else:
		_add_grabber.rpc_id(1, multiplayer.get_unique_id())

## Lo llama quien suelta. Si era la autoridad, el host promueve al siguiente que quede.
func end_grab() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_host_remove_grabber(multiplayer.get_unique_id())
	else:
		_remove_grabber.rpc_id(1, multiplayer.get_unique_id())

@rpc("any_peer", "reliable")
func _add_grabber(peer: int) -> void:
	if multiplayer.is_server():
		_host_add_grabber(peer)

@rpc("any_peer", "reliable")
func _remove_grabber(peer: int) -> void:
	if multiplayer.is_server():
		_host_remove_grabber(peer)

func _host_add_grabber(peer: int) -> void:
	if not _grabbers.has(peer):
		_grabbers.append(peer)
	# Libre (autoridad = host) → el primero que agarra se vuelve la autoridad.
	if get_multiplayer_authority() == 1:
		_grant_authority(peer)

func _host_remove_grabber(peer: int) -> void:
	_grabbers.erase(peer)
	# Si el que soltó era la autoridad, promovemos al siguiente que quede (o al host).
	if get_multiplayer_authority() == peer:
		_grant_authority(_grabbers[0] if not _grabbers.is_empty() else 1)

## Host-only: transmite la nueva autoridad a todos (incluido el host, call_local).
func _grant_authority(peer_id: int) -> void:
	_apply_authority.rpc(peer_id)

@rpc("any_peer", "reliable", "call_local")
func _apply_authority(peer_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return  # solo el host reasigna (0 = call_local en el host, 1 = el host por red)
	set_body_authority(peer_id)

# ── Co-agarre: canal de intención ─────────────────────────────────────────────

## Lo llama cada frame el que agarra pero NO es la autoridad (co-grabber): manda a la autoridad
## su grab point (offset local), a dónde tira y con qué fuerza. La autoridad las suma.
func send_grab_intent(offset: Vector3, target: Vector3, stiffness: float, damping: float) -> void:
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		return
	_receive_intent.rpc_id(get_multiplayer_authority(), offset, target, stiffness, damping)

@rpc("any_peer", "unreliable_ordered")
func _receive_intent(offset: Vector3, target: Vector3, stiffness: float, damping: float) -> void:
	if not is_multiplayer_authority():
		return
	_intents[multiplayer.get_remote_sender_id()] = {
		"offset": offset, "target": target, "stiffness": stiffness, "damping": damping,
		"t": Time.get_ticks_msec()}

## Autoridad: aplica las intenciones de los co-grabbers como fuerzas en sus grab points.
func _apply_intents() -> void:
	if _intents.is_empty():
		return
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	var now := Time.get_ticks_msec()
	for peer in _intents.keys():
		var it: Dictionary = _intents[peer]
		if now - int(it["t"]) > INTENT_TIMEOUT_MS:
			_intents.erase(peer)
			continue
		var grab_world := body.to_global(it["offset"] as Vector3)
		var force := (it["target"] as Vector3 - grab_world) * float(it["stiffness"]) \
			- body.linear_velocity * float(it["damping"])
		body.apply_force(force, grab_world - body.global_position)

## True si hay co-grabbers activos (para desactivar el yaw-follow cuando agarran varios).
func has_cograbbers() -> bool:
	return not _intents.is_empty()
