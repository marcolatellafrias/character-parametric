class_name BuildingArchetype extends RefCounted

# Identificador único del arquetipo
var archetype_id: String

# Características arquitectónicas
var has_chamfered_street_corners: bool

func _init(p_archetype_id: String, p_has_chamfered_street_corners: bool = false) -> void:
	archetype_id = p_archetype_id
	has_chamfered_street_corners = p_has_chamfered_street_corners

## Determina si aplicar chamfer a una esquina de calle basado en seed
## Retorna el valor de chamfer (en celdas) o 0 si no aplica
func get_street_corner_chamfer_value(vertex_seed: int) -> int:
	if not has_chamfered_street_corners:
		return 0
	
	var rng = RandomNumberGenerator.new()
	rng.seed = vertex_seed
	
	# 100% de probabilidad (para debugging)
	if rng.randf() < 1.0:
		return 8  # Hardcoded: 4 celdas
	
	return 0

# Placeholder para futuras características
# var door_config: Dictionary
# var window_config: Dictionary
# var balcony_config: Dictionary
# etc.
