class_name TraversalGenerator extends RefCounted

var block: BlockGenerator

var delivery_doors: Array[Dictionary] = []
var stair_zones: Array[Dictionary] = []
var floating_sidewalk_zones: Array[Dictionary] = []


func _init(p_block: BlockGenerator) -> void:
	block = p_block


## Las medidas de una puerta, en metros. La puerta es RÍGIDA: estas medidas son la verdad, y en la matriz de
## la fachada ocupa las celdas que hagan falta para cubrirlas (ver City._visualize_delivery_doors). El ancho
## se convierte además a celdas de edificio, solo para decidir DÓNDE cae a lo largo de la cara.
const DOOR_WIDTH_M := 1.4
const DOOR_HEIGHT_M := 2.2
const DOOR_DEPTH_M := 0.15
## Cuánto puede subir una puerta para apoyarse sobre lo que haya delante de la fachada (la vereda). Más que
## eso no es un escalón sino un obstáculo, y la puerta no va.
const DOOR_MAX_STEP_M := 0.5


func generate(doors_per_block: int = 4) -> void:
	delivery_doors.clear()
	stair_zones.clear()
	floating_sidewalk_zones.clear()
	_generate_floor_sidewalks()
	_generate_ground_doors(doors_per_block)


## LAS PUERTAS DE PLANTA BAJA. Por ahora solo el piso 0, y acá solo el DATO —qué celda, qué lado, qué tramo
## de la cara—; la geometría la coloca City en la matriz rígida de esa fachada, encima de la pared, sin
## agujerear la malla del módulo (eso viene después, cuando los edificios tengan geometría real).
##
## Un borde sirve si da a la calle (FACADE) o a un callejón. NORMAL es interior —no da a ningún lado— y
## BOUNDARY es el límite de la ciudad.
func _generate_ground_doors(doors_per_block: int) -> void:
	if doors_per_block <= 0:
		return
	var grid = block.get_distorted_grid()
	if grid == null:
		return

	var candidates: Array[Dictionary] = []
	for z in range(grid.rows):
		for x in range(grid.columns):
			var cluster = block.get_cluster_for_cell(x, z)
			if cluster == null or cluster.floor_count <= 0:
				continue
			var module = block.get_building_module(x, z, 0)
			if module == null:
				continue
			for edge_idx in range(4):
				if not _edge_faces_outside(module, edge_idx):
					continue
				candidates.append({
					"cell": Vector2i(x, z), "edge": edge_idx, "cluster_id": cluster.id, "module": module
				})

	if candidates.is_empty():
		return

	# Del seed de la manzana, no de `randi()`: la ciudad tiene que salir idéntica en todos los peers.
	var rng := RandomNumberGenerator.new()
	rng.seed = block.cluster_seed + 4801
	var picked: Array[int] = []
	for i in candidates.size():
		picked.append(i)
	for i in range(picked.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := picked[i]
		picked[i] = picked[j]
		picked[j] = tmp

	var wanted: int = mini(doors_per_block, picked.size())
	for k in range(wanted):
		var candidate: Dictionary = candidates[picked[k]]
		var module: BuildingModule = candidate["module"]
		var span := _door_span(module, candidate["edge"], rng)
		if span.is_empty():
			continue
		delivery_doors.append({
			"cell": candidate["cell"],
			"edge": candidate["edge"],
			"floor": 0,
			"cluster_id": candidate["cluster_id"],
			"along_min": span["along_min"],
			"along_max": span["along_max"],
		})


## Si ese borde del módulo mira a la calle o a un callejón. NORMAL queda adentro de la manzana y
## BOUNDARY es el borde del mundo: en ninguno de los dos tiene sentido una puerta.
func _edge_faces_outside(module: BuildingModule, edge_idx: int) -> bool:
	var sides := ["north", "east", "south", "west"]
	var edge_type: int = module.get_edge_type(sides[edge_idx])
	if edge_type == DistortedGrid.CellType.NORMAL or edge_type == DistortedGrid.CellType.BOUNDARY:
		return false
	return true


## Dónde cae la puerta a lo largo de esa cara, en celdas de edificio. Se sortea sobre la CARA REAL —el
## tramo con pared, sin las esquinas ochavadas (`BuildingModule.get_facade_span`)— y no sobre el núcleo
## entero. El tamaño de celda se mide del módulo mismo —dos posiciones vecinas— en vez de darlo por fijo.
func _door_span(module: BuildingModule, edge_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var core = module.get_core_info()
	var span := module.get_facade_span(edge_idx)
	# `span` va en el sentido del recorrido y cubre celdas [from, to); acá se quieren índices inclusivos.
	var along_from: int = ceili(minf(span.x, span.y))
	var along_to: int = floori(maxf(span.x, span.y)) - 1
	if along_to < along_from:
		return {}

	var origin := module.get_cell_position(core["min_x"], core["min_z"], 0)
	var next_along: Vector3
	if edge_idx == 0 or edge_idx == 2:
		next_along = module.get_cell_position(core["min_x"] + 1, core["min_z"], 0)
	else:
		next_along = module.get_cell_position(core["min_x"], core["min_z"] + 1, 0)
	var cell_size: float = origin.distance_to(next_along)
	if cell_size <= 0.0:
		return {}

	var width_cells: int = maxi(1, int(round(DOOR_WIDTH_M / cell_size)))
	var available: int = along_to - along_from + 1
	if width_cells > available:
		width_cells = available
	var start: int = along_from + rng.randi_range(0, available - width_cells)
	return {
		"along_min": start,
		"along_max": start + width_cells - 1,
	}


func _generate_floor_sidewalks() -> void:
	var grid = block.get_distorted_grid()
	if grid == null:
		return

	var cols = grid.columns
	var rows = grid.rows

	# Corners: facade_offset × facade_offset at each block corner
	var corner_cells = {
		"nw": {"cell": Vector2i(0, 0), "edges": [3, 0]},
		"ne": {"cell": Vector2i(cols - 1, 0), "edges": [0, 1]},
		"se": {"cell": Vector2i(cols - 1, rows - 1), "edges": [1, 2]},
		"sw": {"cell": Vector2i(0, rows - 1), "edges": [2, 3]},
	}

	for key in corner_cells:
		var info = corner_cells[key]
		var cell: Vector2i = info["cell"]
		var module = block.get_building_module(cell.x, cell.y, 0)
		if module == null:
			continue

		var core = module.get_core_info()
		var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
		match key:
			"nw":
				bx_min = 0; bx_max = core["min_x"] - 1
				bz_min = 0; bz_max = core["min_z"] - 1
			"ne":
				bx_min = core["max_x"] + 1; bx_max = module.columns - 1
				bz_min = 0; bz_max = core["min_z"] - 1
			"se":
				bx_min = core["max_x"] + 1; bx_max = module.columns - 1
				bz_min = core["max_z"] + 1; bz_max = module.rows - 1
			"sw":
				bx_min = 0; bx_max = core["min_x"] - 1
				bz_min = core["max_z"] + 1; bz_max = module.rows - 1

		if bx_min > bx_max or bz_min > bz_max:
			continue

		var cluster = block.get_cluster_for_cell(cell.x, cell.y)
		if cluster == null:
			continue

		floating_sidewalk_zones.append({
			"cell": cell, "edge": info["edges"][0], "floor": 0,
			"cluster_id": cluster.id,
			"bx_min": bx_min, "bx_max": bx_max, "bz_min": bz_min, "bz_max": bz_max
		})

	# Sides: one strip per DG cell along each perimeter edge
	var side_edges = [
		[0, 0,       0, cols - 1],
		[1, cols - 1, 0, rows - 1],
		[2, rows - 1, 0, cols - 1],
		[3, 0,       0, rows - 1],
	]
	for side_info in side_edges:
		var edge_idx: int = side_info[0]
		var fixed: int = side_info[1]
		var range_start: int = side_info[2]
		var range_end: int = side_info[3]
		for i in range(range_start, range_end + 1):
			var coord: Vector2i
			if edge_idx == 0 or edge_idx == 2:
				coord = Vector2i(i, fixed)
			else:
				coord = Vector2i(fixed, i)
			var module = block.get_building_module(coord.x, coord.y, 0)
			if module == null:
				continue
			var core = module.get_core_info()
			var is_first = (i == range_start)
			var is_last = (i == range_end)
			var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
			match edge_idx:
				0:
					bx_min = core["min_x"] if is_first else 0
					bx_max = core["max_x"] if is_last else module.columns - 1
					bz_min = 0; bz_max = core["min_z"] - 1
				1:
					bx_min = core["max_x"] + 1; bx_max = module.columns - 1
					bz_min = core["min_z"] if is_first else 0
					bz_max = core["max_z"] if is_last else module.rows - 1
				2:
					bx_min = core["min_x"] if is_first else 0
					bx_max = core["max_x"] if is_last else module.columns - 1
					bz_min = core["max_z"] + 1; bz_max = module.rows - 1
				3:
					bx_min = 0; bx_max = core["min_x"] - 1
					bz_min = core["min_z"] if is_first else 0
					bz_max = core["max_z"] if is_last else module.rows - 1
			if bx_min > bx_max or bz_min > bz_max:
				continue

			var cluster = block.get_cluster_for_cell(coord.x, coord.y)
			if cluster == null:
				continue

			floating_sidewalk_zones.append({
				"cell": coord, "edge": edge_idx, "floor": 0,
				"cluster_id": cluster.id,
				"bx_min": bx_min, "bx_max": bx_max, "bz_min": bz_min, "bz_max": bz_max
			})
