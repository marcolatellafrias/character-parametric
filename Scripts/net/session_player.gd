class_name SessionPlayer
extends RefCounted

# One connected peer this session. Distinct from the persistent Player account
# (conceptual/people.md) — this just maps a Godot peer id to a Steam identity for
# the current run. See conceptual/multiplayer.md.

var peer_id: int = 0
var steam_id: int = 0
var steam_name: String = ""
var is_local: bool = false

func _init(p_peer_id: int = 0, p_steam_id: int = 0, p_name: String = "") -> void:
	peer_id = p_peer_id
	steam_id = p_steam_id
	steam_name = p_name
