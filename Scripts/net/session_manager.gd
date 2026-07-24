extends Node
## SessionManager (autoload). On launch the game shows the **main menu** (no world loaded);
## from there the player picks **host()** or **join_by_code()**. Join-by-code uses a public
## lobby + a filtered lobby-list search (short alphanumeric code stored as lobby data).
## Friends can also join via the Steam overlay ("Join Game"), and if Steam launched us with
## +connect_lobby we join that lobby directly, skipping the menu. Testing runs under Spacewar
## (app id 480, see steam_appid.txt). See conceptual/multiplayer.md and technical/ui.md.
##
## API names are verified against the bundled GodotSteam build. If Steam isn't available, host()
## still starts a **local-only** session (play alone, nobody can join) so dev iteration works.

const MAX_MEMBERS := 4
const VIRTUAL_PORT := 0

## Caracteres del código de partida (sin O/0/I/1 para no confundir).
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
## Escena del menú principal (para volver desde la pausa).
const MAIN_MENU_SCENE := "res://Scenes/main_menu.tscn"

var enabled: bool = false
var is_host: bool = false
var lobby_id: int = 0
var local_steam_id: int = 0

## Código corto de la partida hosteada (lobby data "code"). Vacío si sos cliente/solo.
var lobby_code: String = ""

## Id de red (Godot) del peer local: 1 host/solo, único en clientes. Se conoce recién cuando
## la conexión se establece (o de inmediato al hostear/solo).
var local_peer_id: int = 0
## True una vez que la identidad local quedó fijada y se emitió session_ready.
var session_started: bool = false

## peer_id -> SessionPlayer
var players: Dictionary = {}

## Código que estamos resolviendo por lobby-list (vacío si no hay join-by-code en curso).
var _pending_join_code: String = ""

signal players_changed()
## Emitida una sola vez cuando el peer local ya tiene su id inicial (host/solo = 1, o el id de
## cliente al unirse). El CharacterSpawner la espera; el main menu la usa para entrar al juego.
signal session_ready(local_peer_id: int)
## Emitida cuando el id local CAMBIA tras arrancar la sesión (raro: overlay-join estando ya en
## partida). El CharacterSpawner re-spawnea el jugador local con la nueva authority.
signal local_peer_id_changed(new_peer_id: int)
## Emitidas solo para peers de red (no para el jugador local). El CharacterSpawner
## las escucha para instanciar/eliminar el personaje del peer.
signal remote_player_joined(peer_id: int)
signal remote_player_left(peer_id: int)
## Emitida cuando host/join falla (Steam ausente para join, código no encontrado, conexión
## caída). El main menu la muestra y se queda en el menú.
signal session_failed(reason: String)

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("[Session] GodotSteam not available — host() will run local-only.")
		return

	_ensure_steam_appid_file()

	var init: Dictionary = Steam.steamInitEx()
	if int(init.get("status", 1)) != 0:
		push_warning("[Session] Steam init failed: %s" % str(init.get("verbal", "unknown")))
		return

	enabled = true
	local_steam_id = Steam.getSteamID()
	print("[Session] Steam OK — %s (%d)" % [Steam.getPersonaName(), local_steam_id])

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.join_requested.connect(_on_join_requested)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Si Steam nos lanzó para unirnos a un lobby, nos unimos directo (salteando el menú).
	# Si no, no arrancamos nada: el main menu maneja Host/Join.
	var launch_lobby := _lobby_from_args(OS.get_cmdline_args())
	if launch_lobby != 0:
		_join_lobby(launch_lobby)

func _process(_delta: float) -> void:
	if enabled:
		Steam.run_callbacks()

# ── Session lifecycle ─────────────────────────────────────────────────────────

## Fija la identidad local y avisa una sola vez. Host/solo: peer id 1. Cliente: su id único.
func _start_session(peer_id: int) -> void:
	if session_started:
		return
	session_started = true
	local_peer_id = peer_id
	# Registrar al jugador local en el registro (el host ya se agregó en lobby_created).
	if not players.has(peer_id):
		var my_name := Steam.getPersonaName() if enabled else "Vos"
		_add_player(peer_id, local_steam_id, my_name, true)
	session_ready.emit(peer_id)
	print("[Session] Session ready — local peer %d" % peer_id)

## Host sin Steam (dev): sesión local, peer 1, sin red — jugás solo y nadie se puede unir.
func _start_local_session() -> void:
	_start_session(1)

## En builds exportados Steam lee steam_appid.txt del working dir (el del exe al hacer doble
## clic). Lo generamos si falta, así el exe compartido a mano arranca sin copiarlo. En el editor
## ya existe en el root del proyecto.
func _ensure_steam_appid_file() -> void:
	if OS.has_feature("editor"):
		return
	var path := OS.get_executable_path().get_base_dir().path_join("steam_appid.txt")
	if FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("480")
		f.close()

## Re-fija la identidad local si cambia tras arrancar (overlay-join ya en partida). El
## CharacterSpawner re-spawnea el jugador local con la nueva authority.
func _set_local_identity(peer_id: int) -> void:
	if peer_id == local_peer_id:
		return
	local_peer_id = peer_id
	local_peer_id_changed.emit(peer_id)
	print("[Session] Local identity changed — peer %d" % peer_id)

func _on_connected_to_server() -> void:
	if session_started:
		_set_local_identity(multiplayer.get_unique_id())
	else:
		_start_session(multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	push_warning("[Session] Connection to host failed.")
	session_failed.emit("No se pudo conectar al host")

func _on_server_disconnected() -> void:
	# El host se cayó: si somos cliente, volvemos al menú.
	if session_started and not is_host:
		return_to_menu()

## Deja la sesión y limpia todo el estado (peer, lobby, registro, identidad).
func leave_session() -> void:
	_leave_current()
	_pending_join_code = ""
	lobby_code = ""
	local_peer_id = 0
	session_started = false

## Deja la sesión y vuelve al main menu (botón "Salir de la partida", o host caído).
func return_to_menu() -> void:
	leave_session()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

# ── Public API (main menu / Steam overlay) ────────────────────────────────────

## Hostea una partida. Con Steam: lobby público con código corto (amigos por overlay, y
## cualquiera con el código por join_by_code). Sin Steam: sesión local-only.
func host() -> void:
	if is_host or session_started:
		return
	if not enabled:
		_start_local_session()
		return
	_leave_current()
	lobby_code = _generate_code()
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_MEMBERS)

## Se une por código corto: busca el lobby público con ese "code" y se conecta.
func join_by_code(code: String) -> void:
	if not enabled:
		session_failed.emit("Steam no disponible")
		return
	var clean := code.strip_edges().to_upper()
	if clean == "":
		return
	_pending_join_code = clean
	Steam.addRequestLobbyListStringFilter("code", clean, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	if _pending_join_code == "":
		return
	_pending_join_code = ""
	if lobbies.is_empty():
		session_failed.emit("Código no encontrado")
		return
	_join_lobby(int(lobbies[0]))

## Se une a un lobby por id (código resuelto, overlay de Steam, o +connect_lobby).
func _join_lobby(target_lobby: int) -> void:
	if not enabled or target_lobby == 0:
		return
	_leave_current()
	Steam.joinLobby(target_lobby)

## Cierra peer y lobby actuales para cambiar de rol/sesión, avisando la baja de cada proxy.
func _leave_current() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if enabled and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	for pid in players.keys():
		var sp: SessionPlayer = players[pid]
		if not sp.is_local:
			remote_player_left.emit(pid)
	players.clear()

func _generate_code() -> String:
	var code := ""
	for i in range(CODE_LENGTH):
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code

# ── Host ──────────────────────────────────────────────────────────────────────

func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if result != 1:  # k_EResultOK
		push_warning("[Session] Lobby create failed (%d)" % result)
		lobby_code = ""
		session_failed.emit("No se pudo crear la partida")
		return
	lobby_id = new_lobby_id
	is_host = true
	Steam.setLobbyData(lobby_id, "host_steam_id", str(local_steam_id))
	Steam.setLobbyData(lobby_id, "code", lobby_code)
	Steam.setLobbyJoinable(lobby_id, true)
	# Rich presence so friends see "Join Game" on our profile.
	Steam.setRichPresence("connect", "+connect_lobby %d" % lobby_id)

	var peer := SteamMultiplayerPeer.new()
	peer.create_host(VIRTUAL_PORT)
	multiplayer.multiplayer_peer = peer
	_add_player(1, local_steam_id, Steam.getPersonaName(), true)
	_start_session(multiplayer.get_unique_id())
	print("[Session] Hosting lobby %d (code %s)" % [lobby_id, lobby_code])

# ── Join ──────────────────────────────────────────────────────────────────────

func _on_join_requested(connect_info: Variant, _friend_id: int) -> void:
	var target := _lobby_from_connect(connect_info)
	if target != 0:
		_join_lobby(target)

func _on_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:  # k_EChatRoomEnterResponseSuccess
		push_warning("[Session] Lobby join failed (%d)" % response)
		session_failed.emit("No se pudo entrar al lobby")
		return
	lobby_id = joined_lobby
	if is_host:
		return
	var host_id := int(Steam.getLobbyData(lobby_id, "host_steam_id"))
	if host_id == 0:
		push_warning("[Session] No host_steam_id in lobby %d" % lobby_id)
		session_failed.emit("Lobby inválido")
		return
	var peer := SteamMultiplayerPeer.new()
	peer.create_client(host_id, VIRTUAL_PORT)
	multiplayer.multiplayer_peer = peer
	print("[Session] Joining host %d (lobby %d)" % [host_id, lobby_id])

# ── Peer registry ─────────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	# Registramos el peer ahora (nombre vacío) y le mandamos NUESTRA identidad. Como
	# peer_connected dispara para cada par de peers, todos terminan conociendo a todos.
	_add_player(peer_id, 0, "", false)
	remote_player_joined.emit(peer_id)
	if enabled:
		_register_identity.rpc_id(peer_id, local_steam_id, Steam.getPersonaName())
	print("[Session] Peer connected: %d" % peer_id)

## Handshake de identidad: el emisor nos dice su steam id + nombre. Reliable porque es
## un evento discreto que no se puede perder.
@rpc("any_peer", "reliable")
func _register_identity(steam_id: int, steam_name: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		_add_player(sender, steam_id, steam_name, false)
		return
	var sp: SessionPlayer = players[sender]
	sp.steam_id = steam_id
	sp.steam_name = steam_name
	players_changed.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	players_changed.emit()
	remote_player_left.emit(peer_id)
	print("[Session] Peer disconnected: %d" % peer_id)

func _add_player(peer_id: int, steam_id: int, steam_name: String, local: bool) -> void:
	var sp := SessionPlayer.new(peer_id, steam_id, steam_name)
	sp.is_local = local
	players[peer_id] = sp
	players_changed.emit()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _lobby_from_args(args: PackedStringArray) -> int:
	for i in range(args.size() - 1):
		if args[i] == "+connect_lobby":
			return int(args[i + 1])
	return 0

func _lobby_from_connect(info: Variant) -> int:
	if info is int:
		return info
	var s := str(info)  # e.g. "+connect_lobby 12345"
	var parts := s.split(" ", false)
	for i in range(parts.size() - 1):
		if parts[i] == "+connect_lobby":
			return int(parts[i + 1])
	if s.is_valid_int():
		return int(s)
	return 0
