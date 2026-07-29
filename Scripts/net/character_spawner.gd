class_name CharacterSpawner
extends Node
## Instancia los personajes por código y les asigna la identidad de red. Cada personaje es un
## BoneInstantiator reconstruido de un seed derivado del steam id (mismo en todas las máquinas):
##   - El jugador local (is_active) se spawnea al fijarse su id (session_ready).
##   - Cada peer remoto spawnea un proxy (is_active=false, is_puppet=true) cuando se conoce su
##     identidad; el CharacterNetSync maneja su cápsula. Todos se llaman char_<peer_id> para que
##     el RPC rutee. Ver Scripts/city/docs/conceptual/multiplayer.md (milestones 2-3).

## Punto de inicio temporal, hardcodeado y global. Elevado para no clipear con el suelo.
const SPAWN_POINT := Vector3(0.0, 3.0, 0.0)
const PLAYER_SCENE := preload("res://Scenes/player.tscn")

## Nodo bajo el que se cuelgan los personajes.
@export var characters_root: Node3D
## AreaInstantiator del tráfico, al que le inyectamos la cámara del jugador.
@export var area_instantiator: AreaInstantiator

var local_player: BoneInstantiator
## peer_id -> BoneInstantiator (proxies puppet).
var remote_players: Dictionary = {}

func _ready() -> void:
	add_to_group("character_spawner")
	SessionManager.session_ready.connect(_on_session_ready)
	SessionManager.local_peer_id_changed.connect(_on_local_identity_changed)
	# Los proxies se spawnean cuando se conoce la identidad (steam id) de cada peer.
	SessionManager.players_changed.connect(_sync_proxies)

	if SessionManager.session_started:
		_on_session_ready(SessionManager.local_peer_id)
	_sync_proxies()

## Seed determinístico por jugador, derivado del steam id: igual en todas las máquinas, así el
## personaje se ve igual en todos lados sin sincronizar el esqueleto (solo el seed + el transform).
func _seed_for(steam_id: int) -> int:
	return abs(hash(steam_id)) % 1000000

# ── Jugador local ─────────────────────────────────────────────────────────────

func _on_session_ready(local_peer_id: int) -> void:
	if is_instance_valid(local_player):
		return
	_spawn_local(local_peer_id)

## Al unirse a un amigo el id local cambia (overlay-join en partida): re-spawneamos el local.
func _on_local_identity_changed(new_peer_id: int) -> void:
	if is_instance_valid(local_player):
		local_player.queue_free()
	local_player = null
	_spawn_local(new_peer_id)
	_sync_proxies()

func _spawn_local(local_peer_id: int) -> void:
	local_player = _instantiate_character(true, _seed_for(SessionManager.local_identity()), "char_%d" % local_peer_id, false)
	_attach_net_sync(local_player, local_peer_id)
	# La cámara se recrea en cada respawn (reseed con P): reengancharla al AreaInstantiator.
	local_player.active_camera_changed.connect(_apply_local_camera)
	_apply_local_camera(local_player.player_camera)

## Teletransporta el jugador local al punto de inicio (botón "Go to start" del F1).
func respawn_local_at_start() -> void:
	if not is_instance_valid(local_player):
		return
	# Si está ragdolleado, la cápsula está congelada siguiendo la columna: hay que salir del
	# ragdoll o el teleport no toma.
	if is_instance_valid(local_player.ragdoll_util) and local_player.ragdoll_util.is_active:
		local_player.ragdoll_util.deactivate(local_player.char_rigidbody, local_player.custom_bones_util.lower_spine)
	var rb := local_player.char_rigidbody
	if not is_instance_valid(rb):
		return
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.global_position = SPAWN_POINT

# ── Proxies remotos ───────────────────────────────────────────────────────────

## Spawnea proxies para peers con identidad conocida y saca los que se fueron.
func _sync_proxies() -> void:
	for peer_id in SessionManager.players:
		var sp: SessionPlayer = SessionManager.players[peer_id]
		if sp.is_local or sp.steam_id == 0:
			continue  # esperamos a conocer el steam id (handshake) para el seed
		if not remote_players.has(peer_id):
			remote_players[peer_id] = _spawn_proxy(peer_id, sp.steam_id)
	for peer_id in remote_players.keys():
		if not SessionManager.players.has(peer_id):
			var proxy = remote_players[peer_id]
			if is_instance_valid(proxy):
				proxy.queue_free()
			remote_players.erase(peer_id)

func _spawn_proxy(peer_id: int, steam_id: int) -> BoneInstantiator:
	var proxy := _instantiate_character(false, _seed_for(steam_id), "char_%d" % peer_id, true)
	_attach_net_sync(proxy, peer_id)
	_attach_name_tag(proxy, peer_id)
	return proxy

# ── Helpers ───────────────────────────────────────────────────────────────────

func _instantiate_character(is_active: bool, seed_value: int, node_name: String, is_puppet: bool) -> BoneInstantiator:
	var inst := PLAYER_SCENE.instantiate() as BoneInstantiator
	inst.name = node_name  # antes de add_child: entra al árbol con el path correcto.
	inst.is_active = is_active
	inst.debug_enabled = is_active
	inst.is_puppet = is_puppet
	inst.master_seed = seed_value
	characters_root.add_child(inst)
	# La cápsula ya existe (se crea en initialize_skeleton). En proxies la posición la toma
	# la red enseguida; igual arrancamos en el punto de inicio.
	if is_instance_valid(inst.char_rigidbody):
		inst.char_rigidbody.global_position = SPAWN_POINT
	else:
		inst.global_position = SPAWN_POINT
	return inst

func _attach_net_sync(character_root: BoneInstantiator, authority_peer_id: int) -> void:
	var net := CharacterNetSync.new()
	net.name = "NetSync"  # mismo path en todas las máquinas → el RPC rutea.
	character_root.add_child(net)
	net.set_multiplayer_authority(authority_peer_id)
	# El BoneInstantiator dispara net.apply_to_puppet() al inicio de su frame (antes del solve),
	# así en proxies el transform sincronizado se aplica antes de armar los IK targets.
	character_root.net_sync = net
	# Proxy: pedirle al dueño su seed actual, por si reseedó antes de que me uniera.
	net.request_seed_if_proxy.call_deferred()

## Re-cuelga el name tag tras un rebuild del proxy (reseed): el tag viejo estaba en la cápsula
## anterior, que se liberó en initialize_skeleton. Lo llama CharacterNetSync tras reconstruir.
func reattach_name_tag(proxy: BoneInstantiator, peer_id: int) -> void:
	_attach_name_tag(proxy, peer_id)

func _attach_name_tag(proxy: BoneInstantiator, peer_id: int) -> void:
	var rb := proxy.char_rigidbody
	if not is_instance_valid(rb):
		return
	var tag := NameTag.new()
	tag.peer_id = peer_id
	tag.position = Vector3(0.0, rb._capsule_stand_y_offset + rb._capsule_stand_height * 0.5 + 0.3, 0.0)
	rb.add_child(tag)

func _apply_local_camera(camera: Camera3D) -> void:
	if not is_instance_valid(area_instantiator) or not is_instance_valid(camera):
		return
	var cams: Array[Camera3D] = [camera]
	# Deferred: en el primer spawn el AreaInstantiator puede no haber corrido su _ready todavía.
	area_instantiator.set_cameras.call_deferred(cams)
