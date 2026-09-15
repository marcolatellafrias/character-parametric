class_name BuildingCluster extends RefCounted

var id: int
var cells: Array[Vector2i] = []
var min_x: int
var max_x: int
var min_z: int
var max_z: int
## Con qué color lo dibuja el juego (del arquetipo) y con cuál la vista debug (del distrito): ver
## BuildingShell.
var color: Color
var debug_color: Color
var floor_count: int
var is_block_heart: bool = false

# Contexto urbano y arquetipo
var neighborhood_type: NeighborhoodTypes.District
var archetype: BuildingArchetype
## Qué ventana y qué puerta lleva ESTE edificio, elegidas con su semilla entre las del arquetipo.
var window: WindowArchetype
var door: DoorArchetype

# Configuración para crear BuildingModules
var distorted_grid: DistortedGrid
var path_generator: PathGenerator
var building_rows: int
var building_columns: int
var building_cell_height: float
var building_alleyway_offsets: Dictionary

## Módulos ya calculados, cacheados POR LO QUE LOS DETERMINA y no por piso: la clave lleva la celda y sus
## cuatro tipos de borde. Los bordes se siguen consultando CON el piso, así que si mañana un callejón
## cambia a cierta altura, esa celda produce una clave distinta y se recalcula sola — la capacidad de
## variar por piso queda intacta, pero solo se paga donde de verdad varía. Hoy no varía, y eso ahorra
## calcular ~13 veces el mismo módulo (sus chamfers consultan la grilla vértice por vértice).
var building_modules: Dictionary = {}
## Las esquinas de cada celda, que tampoco dependen del piso.
var _cell_vertices: Dictionary = {}

func _init(
	p_id: int,
	p_seed: int,
	p_min_floors: int = 1,
	p_max_floors: int = 8,
	p_neighborhood_type: NeighborhoodTypes.District = NeighborhoodTypes.District.POOR,
	p_floors_skew: float = 1.0
) -> void:
	id = p_id
	neighborhood_type = p_neighborhood_type
	
	var rng = RandomNumberGenerator.new()
	rng.seed = p_seed + id

	floor_count = NeighborhoodTypes.draw_floor_count(p_min_floors, p_max_floors, p_floors_skew, rng)

	# Asignar arquetipo basado en neighborhood y seed
	archetype = ArchetypeDefinitions.get_archetype_for_cluster(neighborhood_type, p_seed + id)

	color = archetype.get_color(p_seed + id)
	debug_color = NeighborhoodTypes.debug_color(neighborhood_type, p_seed + id)
	window = archetype.pick_window(p_seed + id)
	door = archetype.pick_door(p_seed + id)


func set_grid_config(
	p_distorted_grid: DistortedGrid,
	p_path_generator: PathGenerator,
	p_building_rows: int,
	p_building_columns: int,
	p_building_cell_height: float,
	p_building_alleyway_offsets: Dictionary
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
	
	# El piso 0 existe siempre, también en un corazón de manzana sin edificio (`floor_count` 0): es el
	# módulo donde se apoya lo que va a nivel de suelo —su plaza—. Quien dibuja edificios itera pisos y no
	# llega acá con 0.
	if floor < 0 or floor >= maxi(floor_count, 1):
		return null
	
	var edge_types_array: Array[int] = []
	
	if z == 0:
		edge_types_array.append(distorted_grid.edge_types[0])
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x, z, x + 1, z, floor))

	if x == distorted_grid.columns - 1:
		edge_types_array.append(distorted_grid.edge_types[1])
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x + 1, z, x + 1, z + 1, floor))

	if z == distorted_grid.rows - 1:
		edge_types_array.append(distorted_grid.edge_types[2])
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x + 1, z + 1, x, z + 1, floor))

	if x == 0:
		edge_types_array.append(distorted_grid.edge_types[3])
	else:
		edge_types_array.append(path_generator.get_path_edge_type_vertices(x, z + 1, x, z, floor))

	var key = "%d_%d_%d_%d_%d_%d" % [x, z,
		edge_types_array[0], edge_types_array[1], edge_types_array[2], edge_types_array[3]]
	if key in building_modules:
		return building_modules[key]

	var cell_key = "%d_%d" % [x, z]
	if not _cell_vertices.has(cell_key):
		_cell_vertices[cell_key] = distorted_grid.get_cell_vertices(x, z)
	var cell_vertices: Array[Vector3] = _cell_vertices[cell_key]

	if cell_vertices.size() != 4:
		return null

	var building_module = BuildingModule.new(
		cell_vertices,
		edge_types_array,
		building_rows,
		building_columns,
		building_cell_height,
		building_alleyway_offsets,
		distorted_grid,
		x,
		z,
		path_generator,
		archetype
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

func get_archetype() -> BuildingArchetype:
	return archetype

func get_neighborhood_type() -> NeighborhoodTypes.District:
	return neighborhood_type
