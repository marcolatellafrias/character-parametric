class_name BlockGenerator extends RefCounted

# Tipos de calles
enum StreetType {
	BOUNDARY = -1,
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2,
	SMALL_TUNNEL = 3,
	LARGE_TUNNEL = 4,
}

# Componentes
var grid_geometry: GridGeometry
var distorted_grid: DistortedGrid
var path_generator: PathGenerator

# Geometría del bloque
var street_types: Array[int]
var is_clockwise: bool

# Offsets de calles
var street_offsets: Dictionary = {}

# Área disponible después de offsets
var available_min_x: int
var available_max_x: int
var available_min_z: int
var available_max_z: int

# Carriles por lado de la manzana
var lanes: Dictionary = {}

# Buildings
var buildings: Dictionary = {}

# Building Clusters (edificios como conjuntos de celdas)
var building_clusters: Array[BuildingCluster] = []
var cell_to_cluster: Dictionary = {}  # "x_z" -> cluster_id

# Parámetros de grilla de buildings
var building_rows: int
var building_columns: int
var building_cell_height: float
var building_alleyway_offsets: Dictionary

# Root floors
var root_floors: Array[int] = []

# Seed para generación de clusters
var cluster_seed: int


func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_street_types: Array[int],
	p_cell_height: float,
	p_floors: int,
	p_cells_per_floor: int,
	p_is_clockwise: bool,
	p_street_offsets: Dictionary,
	p_distorted_rows: int = 10,
	p_distorted_columns: int = 10,
	p_wave_amplitude_x: float = 0.1,
	p_wave_amplitude_z: float = 0.1,
	p_wave_frequency_x: float = 2.0,
	p_wave_frequency_z: float = 2.0,
	p_wave_phase_x: float = 0.0,
	p_wave_phase_z: float = 0.0,
	p_edge_falloff_sharpness: float = 1.0,
	p_small_alleyways_count: int = 2,
	p_big_alleyways_count: int = 1,
	p_min_steps_before_turn: int = 2,
	p_grid_seed: int = -1,
	p_building_rows: int = 10,
	p_building_columns: int = 10,
	p_building_cell_height: float = 0.005,
	p_building_alleyway_offsets: Dictionary = {},
	p_root_floors: Array[int] = []
) -> void:
	street_types = p_street_types
	is_clockwise = p_is_clockwise
	street_offsets = p_street_offsets
	root_floors = p_root_floors
	
	building_rows = p_building_rows
	building_columns = p_building_columns
	building_cell_height = p_building_cell_height
	
	# Configurar offsets de alleyways con valores por defecto si no se proporcionan
	if p_building_alleyway_offsets.is_empty():
		building_alleyway_offsets = {
			-1: 4,  # BOUNDARY
			0: 0,   # NORMAL
			1: 2,   # SMALL
			2: 4,   # BIG
			10: 2,  # SMALL_ORIGIN
			11: 4   # BIG_ORIGIN
		}
	else:
		building_alleyway_offsets = p_building_alleyway_offsets
	
	grid_geometry = GridGeometry.new(
		p_rows,
		p_columns,
		p_vertices,
		p_cell_height,
		p_floors,
		p_cells_per_floor
	)
	
	_calculate_available_area()
	_calculate_lanes()
	
	_create_distorted_grid(
		p_distorted_rows,
		p_distorted_columns,
		p_cell_height,
		p_wave_amplitude_x,
		p_wave_amplitude_z,
		p_wave_frequency_x,
		p_wave_frequency_z,
		p_wave_phase_x,
		p_wave_phase_z,
		p_edge_falloff_sharpness
	)
	
	_create_path_generator(
		p_small_alleyways_count,
		p_big_alleyways_count,
		p_min_steps_before_turn,
		p_grid_seed
	)
	
	_create_buildings()
	
	# Generar clusters de buildings
	cluster_seed = p_grid_seed if p_grid_seed != -1 else randi()
	_create_building_clusters()


func _calculate_available_area() -> void:
	var north_offset = street_offsets.get(street_types[0], 0)
	var south_offset = street_offsets.get(street_types[2], 0)
	var west_offset = street_offsets.get(street_types[3], 0)
	var east_offset = street_offsets.get(street_types[1], 0)
	
	available_min_x = west_offset
	available_max_x = grid_geometry.columns - east_offset - 1
	available_min_z = north_offset
	available_max_z = grid_geometry.rows - south_offset - 1


func _create_distorted_grid(
	distorted_rows: int,
	distorted_columns: int,
	cell_height: float,
	wave_amplitude_x: float,
	wave_amplitude_z: float,
	wave_frequency_x: float,
	wave_frequency_z: float,
	wave_phase_x: float,
	wave_phase_z: float,
	edge_falloff_sharpness: float
) -> void:
	var core_vertices = _get_core_block_vertices()
	
	distorted_grid = DistortedGrid.new(
		distorted_rows,
		distorted_columns,
		core_vertices,
		cell_height,
		wave_amplitude_x,
		wave_amplitude_z,
		wave_frequency_x,
		wave_frequency_z,
		wave_phase_x,
		wave_phase_z,
		edge_falloff_sharpness
	)


func _create_path_generator(
	small_alleyways_count: int,
	big_alleyways_count: int,
	min_steps_before_turn: int,
	grid_seed: int
) -> void:
	path_generator = PathGenerator.new(
		distorted_grid,
		small_alleyways_count,
		big_alleyways_count,
		min_steps_before_turn,
		grid_seed,
		0.5,
		root_floors,
		grid_geometry.floors
	)
	
	path_generator.generate()

func _create_buildings() -> void:
	buildings.clear()
	
	# NOTA: Aunque creamos buildings para cada piso (para mantener meshes separados),
	# todos los pisos usan la MISMA configuración de alleyways (del piso 0)
	for floor in range(grid_geometry.floors):
		for z in range(distorted_grid.rows):
			for x in range(distorted_grid.columns):
				var cell_vertices = distorted_grid.get_cell_vertices(x, z)
				
				if cell_vertices.size() != 4:
					continue
				
				var edge_types_array: Array[int] = []
				
				# North edge: (x, z) -> (x+1, z)
				if z == 0:
					edge_types_array.append(-1)  # BOUNDARY
				else:
					edge_types_array.append(path_generator.get_path_edge_type_vertices(x, z, x + 1, z, floor))
				
				# East edge: (x+1, z) -> (x+1, z+1)
				if x == distorted_grid.columns - 1:
					edge_types_array.append(-1)  # BOUNDARY
				else:
					edge_types_array.append(path_generator.get_path_edge_type_vertices(x + 1, z, x + 1, z + 1, floor))
				
				# South edge: (x+1, z+1) -> (x, z+1)
				if z == distorted_grid.rows - 1:
					edge_types_array.append(-1)  # BOUNDARY
				else:
					edge_types_array.append(path_generator.get_path_edge_type_vertices(x + 1, z + 1, x, z + 1, floor))
				
				# West edge: (x, z+1) -> (x, z)
				if x == 0:
					edge_types_array.append(-1)  # BOUNDARY
				else:
					edge_types_array.append(path_generator.get_path_edge_type_vertices(x, z + 1, x, z, floor))
				
				var building = Building.new(
					cell_vertices,
					edge_types_array,
					building_rows,
					building_columns,
					building_cell_height,
					building_alleyway_offsets,
					floor
				)
				
				buildings["%d_%d_%d" % [x, z, floor]] = building


func _create_building_clusters() -> void:
	building_clusters.clear()
	cell_to_cluster.clear()
	
	var cluster_id = 0
	var rng = RandomNumberGenerator.new()
	rng.seed = cluster_seed
	
	# Identificar secciones separadas por alleyways
	# NOTA: Todos los pisos usan la misma configuración de alleyways
	var sections = _identify_sections()
	
	print("[BlockGenerator] Secciones identificadas: %d (compartidas por todos los pisos)" % sections.size())
	
	# Para cada sección, subdividirla en clusters
	for section in sections:
		var section_clusters = _subdivide_section_into_clusters(section, rng, cluster_id)
		cluster_id += section_clusters
	
	print("[BlockGenerator] Clusters totales generados: %d (compartidos por todos los pisos)" % building_clusters.size())


func _identify_sections() -> Array[Array]:
	var sections: Array[Array] = []
	var visited: Dictionary = {}
	
	# Flood fill para encontrar todas las celdas conectadas (no separadas por alleyways)
	for z in range(distorted_grid.rows):
		for x in range(distorted_grid.columns):
			var key = "%d_%d" % [x, z]
			
			if key in visited:
				continue
			
			var section: Array[Vector2i] = []
			_flood_fill_section(x, z, visited, section)
			
			if section.size() > 0:
				sections.append(section)
	
	return sections


func _flood_fill_section(start_x: int, start_z: int, visited: Dictionary, section: Array) -> void:
	var queue: Array[Vector2i] = [Vector2i(start_x, start_z)]
	
	while queue.size() > 0:
		var current = queue.pop_front()
		var key = "%d_%d" % [current.x, current.y]
		
		if key in visited:
			continue
		
		if current.x < 0 or current.x >= distorted_grid.columns or \
		   current.y < 0 or current.y >= distorted_grid.rows:
			continue
		
		visited[key] = true
		section.append(current)
		
		# Verificar vecinos (norte, este, sur, oeste)
		var neighbors = [
			Vector2i(current.x, current.y - 1),  # Norte
			Vector2i(current.x + 1, current.y),  # Este
			Vector2i(current.x, current.y + 1),  # Sur
			Vector2i(current.x - 1, current.y)   # Oeste
		]
		
		for neighbor in neighbors:
			if neighbor.x < 0 or neighbor.x >= distorted_grid.columns or \
			   neighbor.y < 0 or neighbor.y >= distorted_grid.rows:
				continue
			
			var neighbor_key = "%d_%d" % [neighbor.x, neighbor.y]
			if neighbor_key in visited:
				continue
			
			# Verificar si hay un alleyway entre current y neighbor
			if not _is_separated_by_alleyway(current, neighbor):
				queue.append(neighbor)


func _is_separated_by_alleyway(cell1: Vector2i, cell2: Vector2i) -> bool:
	# Determinar el edge entre las dos celdas
	var diff = cell2 - cell1
	
	# Norte/Sur (vertical)
	if diff.x == 0:
		var min_z = min(cell1.y, cell2.y)
		var x = cell1.x
		
		# Edge entre (x, min_z) y (x+1, min_z) si diff.y < 0
		# Edge entre (x, min_z+1) y (x+1, min_z+1) si diff.y > 0
		var edge_z = min_z if diff.y < 0 else min_z + 1
		
		var edge_type = path_generator.get_path_edge_type_vertices(
			x, edge_z, x + 1, edge_z, 0  # Piso 0 - todos los pisos usan la misma configuración
		)
		
		return _is_alleyway_type(edge_type)
	
	# Este/Oeste (horizontal)
	elif diff.y == 0:
		var min_x = min(cell1.x, cell2.x)
		var z = cell1.y
		
		# Edge entre (min_x, z) y (min_x, z+1) si diff.x < 0
		# Edge entre (min_x+1, z) y (min_x+1, z+1) si diff.x > 0
		var edge_x = min_x if diff.x < 0 else min_x + 1
		
		var edge_type = path_generator.get_path_edge_type_vertices(
			edge_x, z, edge_x, z + 1, 0  # Piso 0 - todos los pisos usan la misma configuración
		)
		
		return _is_alleyway_type(edge_type)
	
	return false


func _is_alleyway_type(edge_type: int) -> bool:
	return edge_type in [
		DistortedGrid.CellType.SMALL,
		DistortedGrid.CellType.BIG,
		DistortedGrid.CellType.SMALL_ORIGIN,
		DistortedGrid.CellType.BIG_ORIGIN,
		DistortedGrid.CellType.BOUNDARY
	]


func _subdivide_section_into_clusters(section: Array, rng: RandomNumberGenerator, start_cluster_id: int) -> int:
	var unassigned_cells = section.duplicate()
	var clusters_created = 0
	
	while unassigned_cells.size() > 0:
		var cluster = BuildingCluster.new(start_cluster_id + clusters_created, cluster_seed)
		
		# Elegir celda inicial aleatoria
		var start_cell = unassigned_cells[rng.randi_range(0, unassigned_cells.size() - 1)]
		
		# Hacer crecer el cluster desde esta celda
		var target_size = rng.randi_range(1, 8)  # Tamaño objetivo del cluster
		_grow_cluster(cluster, start_cell, unassigned_cells, target_size, rng)
		
		building_clusters.append(cluster)
		
		# Registrar celdas en el mapa
		for cell in cluster.cells:
			cell_to_cluster["%d_%d" % [cell.x, cell.y]] = cluster.id
		
		clusters_created += 1
	
	return clusters_created


func _grow_cluster(cluster: BuildingCluster, start_cell: Vector2i, unassigned: Array, target_size: int, rng: RandomNumberGenerator) -> void:
	cluster.add_cell(start_cell.x, start_cell.y)
	unassigned.erase(start_cell)
	
	var frontier: Array[Vector2i] = _get_unassigned_neighbors(start_cell, unassigned)
	
	while cluster.get_cell_count() < target_size and frontier.size() > 0:
		# Elegir celda aleatoria del frontier
		var next_cell = frontier[rng.randi_range(0, frontier.size() - 1)]
		frontier.erase(next_cell)
		
		if next_cell not in unassigned:
			continue
		
		cluster.add_cell(next_cell.x, next_cell.y)
		unassigned.erase(next_cell)
		
		# Agregar nuevos vecinos al frontier
		var new_neighbors = _get_unassigned_neighbors(next_cell, unassigned)
		for neighbor in new_neighbors:
			if neighbor not in frontier:
				frontier.append(neighbor)


func _get_unassigned_neighbors(cell: Vector2i, unassigned: Array) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	
	var candidates = [
		Vector2i(cell.x, cell.y - 1),
		Vector2i(cell.x + 1, cell.y),
		Vector2i(cell.x, cell.y + 1),
		Vector2i(cell.x - 1, cell.y)
	]
	
	for candidate in candidates:
		if candidate in unassigned:
			neighbors.append(candidate)
	
	return neighbors


func get_cluster_for_cell(x: int, z: int) -> BuildingCluster:
	var key = "%d_%d" % [x, z]
	var cluster_id = cell_to_cluster.get(key, -1)
	
	if cluster_id == -1:
		return null
	
	for cluster in building_clusters:
		if cluster.id == cluster_id:
			return cluster
	
	return null


func get_all_clusters() -> Array[BuildingCluster]:
	return building_clusters


func _get_core_block_vertices() -> Array[Vector2]:
	var vertices: Array[Vector2] = []
	
	var full_vertices = grid_geometry.vertices
	var columns = grid_geometry.columns
	var rows = grid_geometry.rows
	
	var u_min = float(available_min_x) / max(1, columns)
	var u_max = float(available_max_x + 1) / max(1, columns)
	var v_min = float(available_min_z) / max(1, rows)
	var v_max = float(available_max_z + 1) / max(1, rows)
	
	# Bottom-Left
	var bl = GridHelper.bilinear_interpolation(full_vertices, u_min, v_min)
	vertices.append(bl)
	
	# Bottom-Right
	var br = GridHelper.bilinear_interpolation(full_vertices, u_max, v_min)
	vertices.append(br)
	
	# Top-Right
	var tr = GridHelper.bilinear_interpolation(full_vertices, u_max, v_max)
	vertices.append(tr)
	
	# Top-Left
	var tl = GridHelper.bilinear_interpolation(full_vertices, u_min, v_max)
	vertices.append(tl)
	
	return vertices


func _calculate_lanes() -> void:
	lanes["north"] = _get_lane_offsets_for_street_type(street_types[0])
	lanes["east"] = _get_lane_offsets_for_street_type(street_types[1])
	lanes["south"] = _get_lane_offsets_for_street_type(street_types[2])
	lanes["west"] = _get_lane_offsets_for_street_type(street_types[3])


func _get_lane_offsets_for_street_type(street_type: int) -> Array[int]:
	var offsets: Array[int] = []
	var total_offset = street_offsets.get(street_type, 0)
	
	if total_offset == 0:
		return offsets
	
	match street_type:
		StreetType.SMALL:
			offsets = [4]
		StreetType.MEDIUM:
			offsets = [4, 9]
		StreetType.LARGE:
			offsets = [4, 9, 14]
		_:
			offsets = []
	
	return offsets


func get_lane_endpoints(side: String, lane_index: int) -> Dictionary:
	if side not in lanes or lane_index >= lanes[side].size():
		return {}
	
	var offset = lanes[side][lane_index]
	var start_pos: Vector3
	var end_pos: Vector3
	var from_pos: Vector3
	var to_pos: Vector3
	
	if is_clockwise:
		match side:
			"north":
				var z = available_min_z - offset
				start_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				end_pos = grid_geometry.get_cell_position(0, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"south":
				var z = available_max_z + offset
				start_pos = grid_geometry.get_cell_position(0, z, 0)
				end_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"west":
				var x = available_min_x - offset
				start_pos = grid_geometry.get_cell_position(x, 0, 0)
				end_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"east":
				var x = available_max_x + offset
				start_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				end_pos = grid_geometry.get_cell_position(x, 0, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			_:
				return {}
	else:
		match side:
			"north":
				var z = available_min_z - offset
				start_pos = grid_geometry.get_cell_position(0, z, 0)
				end_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"south":
				var z = available_max_z + offset
				start_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				end_pos = grid_geometry.get_cell_position(0, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"west":
				var x = available_min_x - offset
				start_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				end_pos = grid_geometry.get_cell_position(x, 0, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"east":
				var x = available_max_x + offset
				start_pos = grid_geometry.get_cell_position(x, 0, 0)
				end_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			_:
				return {}
	
	return {
		"start": start_pos,
		"end": end_pos,
		"from": from_pos,
		"to": to_pos,
		"side": side
	}


func get_all_lanes() -> Array[Dictionary]:
	var all_lanes: Array[Dictionary] = []
	
	for side in ["north", "south", "east", "west"]:
		for lane_idx in range(lanes[side].size()):
			var endpoints = get_lane_endpoints(side, lane_idx)
			if not endpoints.is_empty():
				endpoints["index"] = lane_idx
				all_lanes.append(endpoints)
	
	return all_lanes


func get_block_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	
	var vertices = grid_geometry.vertices
	var columns = grid_geometry.columns
	var rows = grid_geometry.rows
	
	var u_min = float(available_min_x) / max(1, columns)
	var u_max = float(available_max_x) / max(1, columns)
	var v_min = float(available_min_z) / max(1, rows)
	var v_max = float(available_max_z) / max(1, rows)
	
	# Bottom-Left
	var corner_bl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_min) +
		vertices[1] * u_min * (1 - v_min) +
		vertices[2] * u_min * v_min +
		vertices[3] * (1 - u_min) * v_min
	)
	corners.append(Vector3(corner_bl_2d.x, 0.0, corner_bl_2d.y))
	
	# Bottom-Right
	var corner_br_2d = (
		vertices[0] * (1 - u_max) * (1 - v_min) +
		vertices[1] * u_max * (1 - v_min) +
		vertices[2] * u_max * v_min +
		vertices[3] * (1 - u_max) * v_min
	)
	corners.append(Vector3(corner_br_2d.x, 0.0, corner_br_2d.y))
	
	# Top-Right
	var corner_tr_2d = (
		vertices[0] * (1 - u_max) * (1 - v_max) +
		vertices[1] * u_max * (1 - v_max) +
		vertices[2] * u_max * v_max +
		vertices[3] * (1 - u_max) * v_max
	)
	corners.append(Vector3(corner_tr_2d.x, 0.0, corner_tr_2d.y))
	
	# Top-Left
	var corner_tl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_max) +
		vertices[1] * u_min * (1 - v_max) +
		vertices[2] * u_min * v_max +
		vertices[3] * (1 - u_min) * v_max
	)
	corners.append(Vector3(corner_tl_2d.x, 0.0, corner_tl_2d.y))
	
	return corners


func get_building(x: int, z: int, floor: int = 0) -> Building:
	var key = "%d_%d_%d" % [x, z, floor]
	return buildings.get(key, null)


func get_rows() -> int:
	return grid_geometry.rows

func get_columns() -> int:
	return grid_geometry.columns

func get_cell_height() -> float:
	return grid_geometry.cell_height

func get_floors() -> int:
	return grid_geometry.floors

func get_cells_per_floor() -> int:
	return grid_geometry.cells_per_floor

func get_distorted_grid() -> DistortedGrid:
	return distorted_grid

func get_path_generator() -> PathGenerator:
	return path_generator

func get_building_rows() -> int:
	return building_rows

func get_building_columns() -> int:
	return building_columns

func get_building_cell_height() -> float:
	return building_cell_height

func get_root_floors() -> Array[int]:
	return root_floors
