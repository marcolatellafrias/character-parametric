class_name BuildingArchetype extends RefCounted

# Identificador único del arquetipo
var archetype_id: String

# Características arquitectónicas
var has_chamfered_street_corners: bool

func _init(p_archetype_id: String, p_has_chamfered_street_corners: bool = false) -> void:
	archetype_id = p_archetype_id
	has_chamfered_street_corners = p_has_chamfered_street_corners

# Placeholder para futuras características
# var door_config: Dictionary
# var window_config: Dictionary
# var balcony_config: Dictionary
# etc.
