class_name CharacterNetSync
extends Node
## Replicación de la cápsula de un personaje (milestone 2 de multiplayer).
##
## Se cuelga como hijo "NetSync" tanto del jugador local (un BoneInstantiator) como
## de cada proxy remoto (un RemoteCharacter), con el MISMO path en todas las máquinas
## para que el RPC rutee. Su multiplayer_authority es el peer dueño del personaje:
##   - En la máquina del dueño (is_multiplayer_authority): lee la cápsula y transmite
##     pos+yaw+velocidad por RPC unreliable cada tick físico.
##   - En las demás: bufferea los estados recibidos (con timestamp local) e interpola.
##
## Transporte-only sobre SteamMultiplayerPeer, sin MultiplayerSynchronizer, como pide
## Scripts/city/docs/conceptual/multiplayer.md (el remoto interpola, no re-simula).

## Delay de render para la interpolación: mostramos el pasado reciente para poder
## interpolar entre dos estados en vez de extrapolar a ciegas.
const INTERP_DELAY_MS := 100.0
## Tope de extrapolación cuando el último estado quedó atrás (paquete perdido/tardío).
const MAX_EXTRAPOLATION_S := 0.15
const BUFFER_MAX := 20

## [{t: int(ms local), pos: Vector3, yaw: float, vel: Vector3}]
var _buffer: Array = []

func _physics_process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return  # offline: el jugador local simula normal, no hay nada que sincronizar.
	if is_multiplayer_authority():
		_send_state()
	else:
		_apply_interpolation()

# ── Authority: transmitir ─────────────────────────────────────────────────────

func _send_state() -> void:
	var p := get_parent()
	var pos: Vector3
	var yaw: float
	var vel: Vector3
	if p is BoneInstantiator:
		var rb: CharacterRigidBody3D = (p as BoneInstantiator).char_rigidbody
		if not is_instance_valid(rb) or not is_instance_valid(rb.mesh_instance):
			return  # entre respawns la cápsula puede no existir por un frame.
		# Mandamos el centro de la cápsula en mundo: independiente del arquetipo, el
		# proxy centra su cápsula genérica ahí sin adivinar offsets.
		pos = rb.mesh_instance.global_position
		yaw = rb.rotation.y
		vel = rb.linear_velocity
	else:
		var body := p as Node3D
		pos = body.global_position
		yaw = body.rotation.y
		vel = Vector3.ZERO
	_receive_state.rpc(pos, yaw, vel)

@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_state(pos: Vector3, yaw: float, vel: Vector3) -> void:
	_buffer.append({"t": Time.get_ticks_msec(), "pos": pos, "yaw": yaw, "vel": vel})
	while _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()

# ── Remoto: interpolar ────────────────────────────────────────────────────────

func _apply_interpolation() -> void:
	var body := get_parent() as Node3D
	if body == null or _buffer.is_empty():
		return

	var render_t := float(Time.get_ticks_msec()) - INTERP_DELAY_MS
	var newest: Dictionary = _buffer[_buffer.size() - 1]

	# Render por delante del último estado: extrapolar con la velocidad, acotado.
	if render_t >= float(newest["t"]):
		var ahead: float = min((render_t - float(newest["t"])) / 1000.0, MAX_EXTRAPOLATION_S)
		body.global_position = (newest["pos"] as Vector3) + (newest["vel"] as Vector3) * ahead
		body.rotation.y = newest["yaw"]
		return

	var oldest: Dictionary = _buffer[0]
	if render_t <= float(oldest["t"]):
		body.global_position = oldest["pos"]
		body.rotation.y = oldest["yaw"]
		return

	for i in range(_buffer.size() - 1):
		var a: Dictionary = _buffer[i]
		var b: Dictionary = _buffer[i + 1]
		if render_t >= float(a["t"]) and render_t <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var f: float = 0.0 if span <= 0.0 else (render_t - float(a["t"])) / span
			body.global_position = (a["pos"] as Vector3).lerp(b["pos"], f)
			body.rotation.y = lerp_angle(a["yaw"], b["yaw"], f)
			return
