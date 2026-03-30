extends Node

const PORT = 7777
var _spawned_players: Dictionary = {}  # player_id -> {pos, seed}

func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT)
	if error != OK:
		printerr("Error al alojar: ", error)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_on_peer_connected(1)

func join_game(ip: String = "127.0.0.1") -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, PORT)
	if error != OK:
		printerr("Error al unirse: ", error)
		return
	multiplayer.multiplayer_peer = peer

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var spawn_pos := _get_random_spawn_point()
	var seed_val  := randi() % 100000
	_spawned_players[id] = {pos = spawn_pos, seed = seed_val}

	# Spawnea el nuevo jugador para todos (incluido él mismo)
	_spawn_player.rpc(id, spawn_pos, seed_val)

	# Informa al nuevo peer sobre los jugadores ya existentes
	for existing_id in _spawned_players:
		if existing_id != id:
			var data = _spawned_players[existing_id]
			_spawn_player.rpc_id(id, existing_id, data.pos, data.seed)

func _on_peer_disconnected(id: int) -> void:
	_spawned_players.erase(id)
	var p := get_tree().current_scene.get_node_or_null(str(id))
	if p:
		p.queue_free()

@rpc("authority", "call_local", "reliable")
func _spawn_player(player_id: int, spawn_pos: Vector3, seed_val: int) -> void:
	# Evita doble spawn si el RPC llega dos veces
	if get_tree().current_scene.get_node_or_null(str(player_id)):
		return
	var new_player       := BoneInstantiator.new()
	new_player.name      = str(player_id)
	new_player.player_id = player_id
	new_player.master_seed = seed_val
	new_player.is_active   = (player_id == multiplayer.get_unique_id())
	new_player.set_multiplayer_authority(player_id)
	get_tree().current_scene.add_child(new_player)
	new_player.global_position = spawn_pos

func _get_random_spawn_point() -> Vector3:
	var spawn_points := get_tree().get_nodes_in_group("spawn_points")
	if spawn_points.size() > 0:
		return spawn_points.pick_random().global_position
	return Vector3(0, 5, 0)
