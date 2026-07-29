class_name NameTag
extends Label3D
## Cartel con el nombre de un jugador remoto, encima de su personaje. Se actualiza con
## players_changed del SessionManager. Lo posiciona quien lo crea (CharacterSpawner).

var peer_id: int = 0

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	pixel_size = 0.006
	outline_size = 8
	SessionManager.players_changed.connect(_update)
	_update()

func _update() -> void:
	var display := "Jugador %d" % peer_id
	if SessionManager.players.has(peer_id):
		var sp: SessionPlayer = SessionManager.players[peer_id]
		if sp.steam_name != "":
			display = sp.steam_name
	text = display
