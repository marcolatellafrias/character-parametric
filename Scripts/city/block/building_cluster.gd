class_name BuildingCluster extends RefCounted

var id: int
var cells: Array[Vector2i] = []
var min_x: int
var max_x: int
var min_z: int
var max_z: int
var color: Color
var floor_count: int
var is_block_heart: bool = false

# Configuración para crear BuildingModules
var distorted_grid: DistortedGrid
var path_generator: PathGenerator
var building_rows: int
var building_columns: int
var building_cell_height: float
var building_alleyway_offsets: Dictionary

# Cache de BuildingModules creados bajo demanda
var building_modules: Dictionary = {}

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
	
	floor_count = rng.randi_range(p_min_floors, p_max_floors)


func set_grid_config(
	p_distorted_grid: DistortedGrid,
	p_path_generator: PathGenerator,
	p_building_rows: int,
	p_building_columns: int,
	p_building_cell_height: float,
	p_building_alleyway_offsets: Dictionary
	# ELIMINAR: p_is_clockwise
) -> void:
	if not p_path_generator.is_generated:
		push_error("PathGenerator debe ser generado antes de configurar BuildingCluster. Llama a path_generator.generate() primero.")
		return
	
	distorted_grid = p_distorted_grid
	path_generator = p_path_generator
	building_rows = p_building_rows
	building_columns = p_building_columns
	building_cell_height = p_building_cell_height
	building_alleyway_offsets = p_building_alleyway_offsets


func get_building_module(x: int, z: int, floor: int) -> BuildingModule:
	if not path_generator or not path_generator.is_generated:
		push_error("PathGenerator no está generado")
		return null
	
	if not contains_cell(x, z):
		return null
	
	if floor < 0 or floor >= floor_count:
		return null
	
	var key = "%d_%d_%d" % [x, z, floor]
	if key in building_modules:
		return building_modules[key]
	
	var cell_vertices = distorted_grid.get_cell_vertices(x, z)
	
	if cell_vertices.size() != 4:
		return null
	
	var edge_types_array: Array[int] = []
	
	if z == 0:
		edge_types_array.append(-1)
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x, z, x + 1, z, floor))
	
	if x == distorted_grid.columns - 1:
		edge_types_array.append(-1)
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x + 1, z, x + 1, z + 1, floor))
	
	if z == distorted_grid.rows - 1:
		edge_types_array.append(-1)
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x + 1, z + 1, x, z + 1, floor))
	
	if x == 0:
		edge_types_array.append(-1)
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x, z + 1, x, z, floor))
	
	var building_module = BuildingModule.new(
		cell_vertices,
		edge_types_array,
		building_rows,
		building_columns,
		building_cell_height,
		building_alleyway_offsets,
		floor,
		distorted_grid,
		x,
		z,
		path_generator
	)
	
	building_modules[key] = building_module
	return building_module


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


func set_block_heart(value: bool) -> void:
	is_block_heart = value


func is_interior_cluster(distorted_grid_rows: int, distorted_grid_columns: int) -> bool:
	for cell in cells:
		if cell.x == 0 or cell.x == distorted_grid_columns - 1:
			return false
		if cell.y == 0 or cell.y == distorted_grid_rows - 1:
			return false
	return true


func get_is_block_heart() -> bool:
	return is_block_heart
