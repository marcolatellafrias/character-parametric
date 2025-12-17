class_name BuildingCluster extends RefCounted

# ID único del cluster
var id: int

# Celdas que pertenecen a este cluster (posiciones en la grilla)
var cells: Array[Vector2i] = []

# Bounding box del cluster
var min_x: int
var max_x: int
var min_z: int
var max_z: int

# Color único para visualización
var color: Color

# Número de pisos que tiene este cluster
var floor_count: int


func _init(p_id: int, p_seed: int, p_min_floors: int = 1, p_max_floors: int = 8) -> void:
	id = p_id
	
	var rng = RandomNumberGenerator.new()
	rng.seed = p_seed + id
	
	color = Color.from_hsv(
		rng.randf(),
		rng.randf_range(0.5, 0.8),
		rng.randf_range(0.6, 0.9),
		1.0
	)
	
	# Asignar altura aleatoria al cluster
	floor_count = rng.randi_range(p_min_floors, p_max_floors)


func add_cell(x: int, z: int) -> void:
	cells.append(Vector2i(x, z))
	
	if cells.size() == 1:
		min_x = x
		max_x = x
		min_z = z
		max_z = z
	else:
		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_z = min(min_z, z)
		max_z = max(max_z, z)


func contains_cell(x: int, z: int) -> bool:
	return Vector2i(x, z) in cells


func get_cell_count() -> int:
	return cells.size()


func get_floor_count() -> int:
	return floor_count
