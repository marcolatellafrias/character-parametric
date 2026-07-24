class_name CharacterSpawner
extends Node
## Instancia los personajes por código en lugar de tenerlos puestos a mano en la
## escena, y les asigna la identidad de red (milestone 2 de multiplayer):
##   - El jugador local se spawnea cuando SessionManager fija su id (session_ready),
##     nombrado char_<id> y con ese peer como multiplayer_authority.
##   - Cada peer remoto spawnea un RemoteCharacter (cápsula liviana) con el MISMO
##     nombre char_<id> en todas las máquinas, para que el CharacterNetSync rutee.
## También le pasa la cámara del jugador local al AreaInstantiator para que el
## tráfico y la niebla lo sigan. Ver Scripts/city/docs/conceptual/multiplayer.md.

## Punto de inicio temporal, hardcodeado y en coordenadas globales. Elevado en Y
## para que la cápsula no clipee con el suelo al spawnear (misma altura que usa el
## respawn con P). En el futuro se adaptará a la ciudad.
const SPAWN_POINT := Vector3(0.0, 3.0, 0.0)
const PLAYER_SCENE := preload("res://Scenes/player.tscn")
## Seed del jugador local (equivale al viejo "fat" con master_seed por defecto).
## Los seeds todavía no se sincronizan entre máquinas — eso es milestone 3.
const LOCAL_SEED := 0

## Nodo bajo el que se cuelgan los personajes.
@export var characters_root: Node3D
## AreaInstantiator del tráfico, al que le inyectamos la cámara del jugador.
@export var area_instantiator: AreaInstantiator

var local_player: BoneInstantiator
## peer_id -> RemoteCharacter (proxies remotos).
var remote_players: Dictionary = {}

func _ready() -> void:
	add_to_group("character_spawner")
	SessionManager.session_ready.connect(_on_session_ready)
	SessionManager.local_peer_id_changed.connect(_on_local_identity_changed)
	SessionManager.remote_player_joined.connect(_on_remote_joined)
	SessionManager.remote_player_left.connect(_on_remote_left)

	# Si la sesión ya arrancó antes de que existiéramos, spawnear ahora (la señal
	# session_ready pudo emitirse antes de que nos conectáramos).
	if SessionManager.session_started:
		_on_session_ready(SessionManager.local_peer_id)
	for peer_id in SessionManager.players:
		var sp: SessionPlayer = SessionManager.players[peer_id]
		if not sp.is_local:
			_on_remote_joined(peer_id)

# ── Jugador local ─────────────────────────────────────────────────────────────

func _on_session_ready(local_peer_id: int) -> void:
	if is_instance_valid(local_player):
		return
	_spawn_local(local_peer_id)

## Al unirse a un amigo el id local cambia (solo/host → cliente): re-spawneamos el
## jugador local con la nueva authority y limpiamos los proxies de la sesión anterior.
func _on_local_identity_changed(new_peer_id: int) -> void:
	if is_instance_valid(local_player):
		local_player.queue_free()
	local_player = null
	for pid in remote_players.keys():
		var proxy = remote_players[pid]
		if is_instance_valid(proxy):
			proxy.queue_free()
	remote_players.clear()

	_spawn_local(new_peer_id)
	# Re-spawnear proxies de peers ya conectados (por si peer_connected llegó primero).
	for pid in SessionManager.players:
		var sp: SessionPlayer = SessionManager.players[pid]
		if not sp.is_local:
			_on_remote_joined(pid)

func _spawn_local(local_peer_id: int) -> void:
	local_player = _instantiate_character(true, LOCAL_SEED, "char_%d" % local_peer_id)
	_attach_net_sync(local_player, local_peer_id)
	# La cámara del jugador se recrea en cada respawn (reseed con P): reengancharla
	# cada vez para que el tráfico no siga apuntando a una cámara ya liberada.
	local_player.active_camera_changed.connect(_apply_local_camera)
	_apply_local_camera(local_player.player_camera)

## Teletransporta el jugador local al punto de inicio (botón de spawn).
func respawn_local_at_start() -> void:
	if is_instance_valid(local_player) and is_instance_valid(local_player.char_rigidbody):
		local_player.char_rigidbody.global_position = SPAWN_POINT

# ── Proxies remotos ───────────────────────────────────────────────────────────

func _on_remote_joined(peer_id: int) -> void:
	if remote_players.has(peer_id):
		return
	var proxy := RemoteCharacter.new()
	proxy.name = "char_%d" % peer_id
	proxy.peer_id = peer_id
	characters_root.add_child(proxy)
	proxy.global_position = SPAWN_POINT
	_attach_net_sync(proxy, peer_id)
	remote_players[peer_id] = proxy

func _on_remote_left(peer_id: int) -> void:
	var proxy = remote_players.get(peer_id)
	if is_instance_valid(proxy):
		proxy.queue_free()
	remote_players.erase(peer_id)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _instantiate_character(is_active: bool, seed_value: int, node_name: String) -> BoneInstantiator:
	var inst := PLAYER_SCENE.instantiate() as BoneInstantiator
	inst.name = node_name  # antes de add_child: entra al árbol con el path correcto.
	inst.is_active = is_active
	inst.debug_enabled = is_active
	inst.master_seed = seed_value
	characters_root.add_child(inst)
	# char_rigidbody ya existe (se crea en initialize_skeleton durante _ready).
	if is_instance_valid(inst.char_rigidbody):
		inst.char_rigidbody.global_position = SPAWN_POINT
	else:
		inst.global_position = SPAWN_POINT
	return inst

func _attach_net_sync(character_root: Node, authority_peer_id: int) -> void:
	var net := CharacterNetSync.new()
	net.name = "NetSync"  # mismo path en todas las máquinas → el RPC rutea.
	character_root.add_child(net)
	net.set_multiplayer_authority(authority_peer_id)

func _apply_local_camera(camera: Camera3D) -> void:
	if not is_instance_valid(area_instantiator) or not is_instance_valid(camera):
		return
	var cams: Array[Camera3D] = [camera]
	# Deferred: en el primer spawn el AreaInstantiator puede no haber corrido su
	# _ready todavía; diferir garantiza que reconstruya los cilindros una sola vez
	# con la cámara ya presente.
	area_instantiator.set_cameras.call_deferred(cams)
