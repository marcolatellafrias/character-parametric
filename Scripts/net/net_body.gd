class_name NetBody
extends Node
## Sincronización de un cuerpo físico (RigidBody3D padre) por red. La AUTORIDAD simula normal y
## transmite transform+velocidad cada tick; las demás lo SIGUEN. Sin predicción ni rollback.
##
## El proxy NO se congela: sigue siendo un cuerpo DINÁMICO, manejado por velocidad hacia la pose de
## referencia. Un kinemático teleportado (lo que había antes) tiene masa infinita y velocidad
## implícita ilimitada: si aparece dentro de una cápsula, Jolt la eyecta con lo que haga falta — de
## ahí salía el jugador despedido por el aire al agarrar una caja que ya sostenía otro. Manejado por
## velocidad no puede atravesar a nadie: empuja con masa real (el contacto se resuelve por momento,
## no por despenetración), conserva el apoyo rígido contra el pecho, y se auto-corrige.
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

## Seguimiento del proxy. La velocidad que se le escribe es `vel_de_referencia + corrección`:
## la primera es momento FÍSICO real (una caja lanzada viaja rápido de verdad y debe pegar como
## tal), la segunda es artificial — la que cierra la deriva — y es la única acotada, así que el
## seguimiento nunca puede inventar momento.
const FOLLOW_TAU := 0.1             ## s — en cuánto se busca cerrar el error de pose
const FOLLOW_MAX_CORRECTION := 3.0  ## m/s — techo de la componente artificial
const FOLLOW_MAX_ANG_CORRECTION := 6.0  ## rad/s
## Deriva máxima tolerada antes de un snap duro (m): eso ya no es un contacto, es un desync real
## (la caja se cayó de una cornisa en una máquina y en otra no). A esa distancia no hay nadie
## adentro, así que teleportar es seguro.
const SNAP_DIST := 3.0
## Por debajo de esto el proxy ya está en su lugar: no le escribimos velocidad y lo dejamos asentar
## y dormirse solo (pisarle linear_velocity cada frame le impediría dormir nunca).
const SETTLE_DIST := 0.02
const SETTLE_ANG := 0.02

## [{t: int(ms local), pos: Vector3, rot: Quaternion, vel: Vector3, avel: Vector3}]
var _buffer: Array = []
## Solo en el host: peers que están agarrando este cuerpo (para promover autoridad al soltar).
var _grabbers: Array = []
## Dormancy: true cuando el cuerpo está dormido (quieto) y dejamos de transmitir. La autoridad lo
## maneja desde body.sleeping; los remotos ni lo miran (ya asentaron en el último estado recibido).
var _dormant: bool = false
## Gravedad propia del cuerpo, para restaurarla al pasar de proxy a autoridad.
var _base_gravity_scale: float = 1.0

# ── Autoridad ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	var body := get_parent() as RigidBody3D
	if body != null:
		_base_gravity_scale = body.gravity_scale

## Fija quién simula este cuerpo y lo (re)configura según corresponda.
func set_body_authority(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	var grabbable := _grabbable()  # las manos registradas eran para la autoridad anterior
	if grabbable != null:
		grabbable.clear_all_holds()
	_dormant = false  # al (re)tomar autoridad arrancamos despiertos hasta que la física duerma el cuerpo
	_configure()
	# Al TOMAR la autoridad, arrancamos con la última velocidad conocida, así un throw no se pierde
	# al cambiar de autoridad (el proxy la venía siguiendo, pero la de referencia es la buena).
	if is_multiplayer_authority() and not _buffer.is_empty():
		var body := get_parent() as RigidBody3D
		if body != null:
			var last: Dictionary = _buffer[_buffer.size() - 1]
			body.linear_velocity  = last["vel"]
			body.angular_velocity = last["avel"]

func _configure() -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	var remote := multiplayer.has_multiplayer_peer() and not is_multiplayer_authority()
	# El proxy queda DINÁMICO (masa real en los contactos) y lo maneja _follow_reference por
	# velocidad. Sin gravedad: su caída ya viene contenida en la pose de referencia que sigue, y
	# aplicarla dos veces lo haría colgar por debajo. Ver el encabezado.
	body.freeze = false
	body.gravity_scale = 0.0 if remote else _base_gravity_scale

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return  # offline: el cuerpo simula normal, nada que sincronizar.
	if is_multiplayer_authority():
		_stream_if_awake()  # el agarre lo resuelve GrabbableInteractable, no acá
	else:
		_follow_reference(delta)

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
	_receive_state.rpc(t.origin, t.basis.get_rotation_quaternion(), body.linear_velocity, body.angular_velocity)

@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_state(pos: Vector3, rot: Quaternion, vel: Vector3, avel: Vector3) -> void:
	_buffer.append({"t": Time.get_ticks_msec(), "pos": pos, "rot": rot, "vel": vel, "avel": avel})
	while _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()

## Muestrea la pose+velocidad de referencia (la del que simula) en el tiempo de render local:
## interpolación entre estados con INTERP_DELAY_MS de retraso, y extrapolación corta si el último
## paquete llegó tarde. La lógica es la de siempre; lo que cambió es qué hacemos con el resultado.
func _sample_reference() -> Dictionary:
	var render_t := float(Time.get_ticks_msec()) - INTERP_DELAY_MS
	var newest: Dictionary = _buffer[_buffer.size() - 1]

	if render_t >= float(newest["t"]):
		var ahead: float = min((render_t - float(newest["t"])) / 1000.0, MAX_EXTRAP_S)
		var extrap := (newest["pos"] as Vector3) + (newest["vel"] as Vector3) * ahead
		return {"pos": extrap, "rot": newest["rot"], "vel": newest["vel"], "avel": newest["avel"]}

	var oldest: Dictionary = _buffer[0]
	if render_t <= float(oldest["t"]):
		return oldest

	for i in range(_buffer.size() - 1):
		var a: Dictionary = _buffer[i]
		var b: Dictionary = _buffer[i + 1]
		if render_t >= float(a["t"]) and render_t <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var f: float = 0.0 if span <= 0.0 else (render_t - float(a["t"])) / span
			return {
				"pos":  (a["pos"] as Vector3).lerp(b["pos"], f),
				"rot":  (a["rot"] as Quaternion).slerp(b["rot"], f),
				"vel":  (a["vel"] as Vector3).lerp(b["vel"], f),
				"avel": (a["avel"] as Vector3).lerp(b["avel"], f)}

	return newest

## Proxy: seguimos la pose de referencia escribiendo VELOCIDAD, nunca el transform. El cuerpo sigue
## siendo dinámico, así que si algo lo bloquea (una cápsula, una pared) el contacto se resuelve por
## momento con masa real y el seguimiento simplemente pierde — que es lo correcto — en vez de
## teleportar a través y hacer que Jolt eyecte al que estorbaba.
func _follow_reference(delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null or _buffer.is_empty() or delta <= 0.0:
		return

	var ref := _sample_reference()
	var ref_pos: Vector3   = ref["pos"]
	var ref_rot: Quaternion = ref["rot"]
	var pos_err := ref_pos - body.global_position

	# Deriva enorme: ya no es un contacto sino un desync real, y a esa distancia no hay nadie
	# adentro del cuerpo. Ahí sí teleportamos.
	if pos_err.length() > SNAP_DIST:
		body.global_transform = Transform3D(Basis(ref_rot), ref_pos)
		body.linear_velocity  = ref["vel"]
		body.angular_velocity = ref["avel"]
		return

	var rot_err := (ref_rot * body.global_transform.basis.get_rotation_quaternion().inverse()).normalized()
	if rot_err.w < 0.0:
		rot_err = -rot_err  # camino corto
	var angle := rot_err.get_angle()

	# Ya está en su lugar: no le pisamos la velocidad, así asienta y se duerme como cualquier cuerpo.
	if pos_err.length() <= SETTLE_DIST and angle <= SETTLE_ANG:
		return

	var ang_correction := Vector3.ZERO
	if angle > 0.0001:
		ang_correction = (rot_err.get_axis() * angle / FOLLOW_TAU).limit_length(FOLLOW_MAX_ANG_CORRECTION)

	body.sleeping = false  # el de referencia se movió: si nos habíamos dormido, a seguirlo
	body.linear_velocity  = (ref["vel"] as Vector3) \
		+ (pos_err / FOLLOW_TAU).limit_length(FOLLOW_MAX_CORRECTION)
	body.angular_velocity = (ref["avel"] as Vector3) + ang_correction

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

## Lanza el cuerpo con un impulso, sobreviviendo el handoff de autoridad al soltar. La AUTORIDAD FINAL
## (el host, u offline el local) lo aplica a su instancia — la que se sincroniza — así no depende del
## buffer y no hay snap. El cliente NO aplica local (si lo hiciera, al pasar la autoridad al host su
## caja volvería atrás ~1 RTT). Ver conceptual/multiplayer.md (Causa B).
func throw_body(impulse: Vector3) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var body := get_parent() as RigidBody3D  # offline u host: soy (o seré) la autoridad
		if body != null:
			body.apply_central_impulse(impulse)
			_dormant = false
	else:
		_request_throw.rpc_id(1, impulse)  # cliente: que lo aplique el host cuando retome la autoridad

@rpc("any_peer", "reliable")
func _request_throw(impulse: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if get_multiplayer_authority() != 1:  # end_grab ya la devuelve; si por orden aún no, forzar
		_apply_authority.rpc(1)
	var body := get_parent() as RigidBody3D
	if body != null:
		body.apply_central_impulse(impulse)
		_dormant = false

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

## Lo llama cada frame el que agarra pero NO es la autoridad (co-grabber): manda a quien simula el
## cuerpo su MANO (grab point, a dónde tira, desde qué pecho y con qué fuerza). Quien simula la
## registra junto a las suyas y el solver del grabbable las resuelve todas de una.
func send_grab_intent(offset: Vector3, target: Vector3, origin: Vector3, strength: float) -> void:
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		return
	_receive_intent.rpc_id(get_multiplayer_authority(), offset, target, origin, strength)

@rpc("any_peer", "unreliable_ordered")
func _receive_intent(offset: Vector3, target: Vector3, origin: Vector3, strength: float) -> void:
	if not is_multiplayer_authority():
		return
	var grabbable := _grabbable()
	if grabbable != null:
		grabbable.set_hold(multiplayer.get_remote_sender_id(), offset, target, origin, strength)

## Lo llama el co-grabber al soltar, para que su mano no siga tirando hasta expirar por timeout.
func send_grab_release() -> void:
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		return
	_receive_release.rpc_id(get_multiplayer_authority())

@rpc("any_peer", "reliable")
func _receive_release() -> void:
	if not is_multiplayer_authority():
		return
	var grabbable := _grabbable()
	if grabbable != null:
		grabbable.clear_hold(multiplayer.get_remote_sender_id())

func _grabbable() -> GrabbableInteractable:
	var body := get_parent() as RigidBody3D
	if body == null:
		return null
	for child in body.get_children():
		if child is GrabbableInteractable:
			return child as GrabbableInteractable
	return null
