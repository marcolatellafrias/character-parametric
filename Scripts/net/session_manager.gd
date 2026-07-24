extends Node
## SessionManager (autoload). Milestone 1: init Steam, auto-host, and let friends join
## via the Steam overlay ("Join Game"). No menu — on launch we host (unless Steam launched
## us to join a lobby). Testing runs under Spacewar (app id 480, see steam_appid.txt).
## See conceptual/multiplayer.md.
##
## API names are verified against the bundled GodotSteam build. Everything is guarded so the
## game still runs offline if Steam isn't available (e.g. the Steam client isn't running).

const MAX_MEMBERS := 4
const VIRTUAL_PORT := 0

var enabled: bool = false
var is_host: bool = false
var lobby_id: int = 0
var local_steam_id: int = 0

## Id de red (Godot) del peer local: 1 offline/host, único en clientes. Se conoce
## recién cuando la conexión se establece (o de inmediato offline/host).
var local_peer_id: int = 0
## True una vez que la identidad local quedó fijada y se emitió session_ready.
var session_started: bool = false

## peer_id -> SessionPlayer
var players: Dictionary = {}

signal players_changed()
## Emitida una sola vez cuando el peer local ya tiene su id definitivo. El
## CharacterSpawner la espera para instanciar el jugador local con la authority
## correcta (si spawneara antes, un cliente usaría el id 1 y chocaría con el host).
signal session_ready(local_peer_id: int)
## Emitidas solo para peers de red (no para el jugador local). El CharacterSpawner
## las escucha para instanciar/eliminar el personaje del peer.
signal remote_player_joined(peer_id: int)
signal remote_player_left(peer_id: int)

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("[Session] GodotSteam not available — running offline.")
		_ensure_solo_session.call_deferred()
		return

	var init: Dictionary = Steam.steamInitEx()
	if int(init.get("status", 1)) != 0:
		push_warning("[Session] Steam init failed: %s" % str(init.get("verbal", "unknown")))
		_ensure_solo_session.call_deferred()
		return

	enabled = true
	local_steam_id = Steam.getSteamID()
	print("[Session] Steam OK — %s (%d)" % [Steam.getPersonaName(), local_steam_id])

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# No menu: join the lobby Steam launched us for, else auto-host.
	var launch_lobby := _lobby_from_args(OS.get_cmdline_args())
	if launch_lobby != 0:
		Steam.joinLobby(launch_lobby)
	else:
		Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_MEMBERS)

# ── Session lifecycle ─────────────────────────────────────────────────────────

## Fija la identidad local y avisa una sola vez. Offline/host: peer id 1. Cliente:
## su id único, ya conectado.
func _start_session(peer_id: int) -> void:
	if session_started:
		return
	session_started = true
	local_peer_id = peer_id
	session_ready.emit(peer_id)
	print("[Session] Session ready — local peer %d" % peer_id)

## Sin red (Steam ausente, init falló, o falló crear/unirse el lobby): jugamos solo
## con peer id 1 para que igual spawnee el jugador local.
func _ensure_solo_session() -> void:
	_start_session(1)

func _on_connected_to_server() -> void:
	_start_session(multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	push_warning("[Session] Connection to host failed — running solo.")
	_ensure_solo_session()

func _process(_delta: float) -> void:
	if enabled:
		Steam.run_callbacks()

# ── Host ────────────────────────────────────────────────────────────────────

func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if result != 1:  # k_EResultOK
		push_warning("[Session] Lobby create failed (%d)" % result)
		_ensure_solo_session()
		return
	lobby_id = new_lobby_id
	is_host = true
	Steam.setLobbyData(lobby_id, "host_steam_id", str(local_steam_id))
	Steam.setLobbyJoinable(lobby_id, true)
	# Rich presence so friends see "Join Game" on our profile.
	Steam.setRichPresence("connect", "+connect_lobby %d" % lobby_id)

	var peer := SteamMultiplayerPeer.new()
	peer.create_host(VIRTUAL_PORT)
	multiplayer.multiplayer_peer = peer
	_add_player(1, local_steam_id, Steam.getPersonaName(), true)
	# El host es el peer 1 y su id ya es definitivo: arrancamos la sesión.
	_start_session(multiplayer.get_unique_id())
	print("[Session] Hosting lobby %d" % lobby_id)

# ── Join ────────────────────────────────────────────────────────────────────

func _on_join_requested(connect_info: Variant, _friend_id: int) -> void:
	var target := _lobby_from_connect(connect_info)
	if target != 0:
		Steam.joinLobby(target)

func _on_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:  # k_EChatRoomEnterResponseSuccess
		push_warning("[Session] Lobby join failed (%d)" % response)
		_ensure_solo_session()
		return
	lobby_id = joined_lobby
	if is_host:
		return
	var host_id := int(Steam.getLobbyData(lobby_id, "host_steam_id"))
	if host_id == 0:
		push_warning("[Session] No host_steam_id in lobby %d" % lobby_id)
		_ensure_solo_session()
		return
	var peer := SteamMultiplayerPeer.new()
	peer.create_client(host_id, VIRTUAL_PORT)
	multiplayer.multiplayer_peer = peer
	print("[Session] Joining host %d (lobby %d)" % [host_id, lobby_id])

# ── Peer registry ───────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	# Their Steam identity arrives via a handshake in a later milestone; register the peer now.
	_add_player(peer_id, 0, "", false)
	remote_player_joined.emit(peer_id)
	print("[Session] Peer connected: %d" % peer_id)

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

# ── Helpers ─────────────────────────────────────────────────────────────────

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
