class_name BlockGenerator extends RefCounted

enum StreetType {
	BOUNDARY = -1,
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2
}

# Ancho de media calle en celdas por tipo
const STREET_HALF_WIDTH_CELLS: Dictionary = {
	StreetType.BOUNDARY: 0,
	StreetType.SMALL: 4,
	StreetType.MEDIUM: 6,
	StreetType.LARGE: 9
}

var grid_geometry: GridGeometry
var distorted_grid: DistortedGrid
var path_generator: PathGenerator

var street_types: Array[int]
var is_clockwise: bool
var street_offsets: Dictionary = {}

var available_min_x: int
var available_max_x: int
var available_min_z: int
var available_max_z: int

var buildings: Dictionary = {}
var building_clusters: Array[BuildingCluster] = []
var cell_to_cluster: Dictionary = {}

var min_floors_per_cluster: int
var max_floors_per_cluster: int
var block_heart_probability: float = 0.0

var building_rows: int
var building_columns: int
var building_cell_height: float
var building_alleyway_offsets: Dictionary

var cluster_seed: int

# Lane lines - puntos temporales para visualización
# key: "edge_idx_node_idx" -> {point_a: Vector2, point_b: Vector2}
var temporal_lane_points: Dictionary = {}

# Lane planes finales
# key: "edge_idx_node_idx" -> {start: Vector2, end: Vector2, is_start_lane: bool, height: float}
var lane_planes: Dictionary = {}

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
	p_min_floors_per_cluster: int = 1,
	p_max_floors_per_cluster: int = 8,
	p_block_heart_probability: float = 0.0
) -> void:
	street_types = p_street_types
	is_clockwise = p_is_clockwise
	street_offsets = p_street_offsets
	
	building_rows = p_building_rows
	building_columns = p_building_columns
	building_cell_height = p_building_cell_height
	
	min_floors_per_cluster = p_min_floors_per_cluster
	max_floors_per_cluster = p_max_floors_per_cluster
	block_heart_probability = p_block_heart_probability
	
	if p_building_alleyway_offsets.is_empty():
		building_alleyway_offsets = {
			-1: 3,
			0: 0,
			1: 4,
			2: 4,
			10: 4,
			11: 4
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
	
	cluster_seed = p_grid_seed if p_grid_seed != -1 else randi()
	_create_building_clusters()
	_assign_block_hearts()

func _calculate_available_area() -> void:
	street_offsets = _calculate_street_offsets()
	
	var north_offset = street_offsets.get(street_types[0], 0)
	var south_offset = street_offsets.get(street_types[2], 0)
	var west_offset = street_offsets.get(street_types[3], 0)
	var east_offset = street_offsets.get(street_types[1], 0)
	
	available_min_x = west_offset
	available_max_x = grid_geometry.columns - east_offset - 1
	available_min_z = north_offset
	available_max_z = grid_geometry.rows - south_offset - 1

func _calculate_street_offsets() -> Dictionary:
	var offsets: Dictionary = {}
	
	for street_type in STREET_HALF_WIDTH_CELLS.keys():
		offsets[street_type] = STREET_HALF_WIDTH_CELLS[street_type]
	
	return offsets

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
		grid_geometry.floors
	)
	
	path_generator.generate()

func _create_buildings() -> void:
	buildings.clear()
	
	for floor in range(grid_geometry.floors):
		for z in range(distorted_grid.rows):
			for x in range(distorted_grid.columns):
				var cell_vertices = distorted_grid.get_cell_vertices(x, z)
				
				if cell_vertices.size() != 4:
					continue
				
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
	
	var sections = _identify_sections()
	
	print("[BlockGenerator] Secciones identificadas: %d (compartidas por todos los pisos)" % sections.size())
	
	for section in sections:
		var section_clusters = _subdivide_section_into_clusters(section, rng, cluster_id)
		cluster_id += section_clusters
	
	print("[BlockGenerator] Clusters totales generados: %d (compartidos por todos los pisos)" % building_clusters.size())

func _identify_sections() -> Array[Array]:
	var sections: Array[Array] = []
	var visited: Dictionary = {}
	
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
		
		var neighbors = [
			Vector2i(current.x, current.y - 1),
			Vector2i(current.x + 1, current.y),
			Vector2i(current.x, current.y + 1),
			Vector2i(current.x - 1, current.y)
		]
		
		for neighbor in neighbors:
			if neighbor.x < 0 or neighbor.x >= distorted_grid.columns or \
			   neighbor.y < 0 or neighbor.y >= distorted_grid.rows:
				continue
			
			var neighbor_key = "%d_%d" % [neighbor.x, neighbor.y]
			if neighbor_key in visited:
				continue
			
			if not _is_separated_by_alleyway(current, neighbor):
				queue.append(neighbor)

func _is_separated_by_alleyway(cell1: Vector2i, cell2: Vector2i) -> bool:
	var diff = cell2 - cell1
	
	if diff.x == 0:
		var min_z = min(cell1.y, cell2.y)
		var x = cell1.x
		var edge_z = min_z if diff.y < 0 else min_z + 1
		
		var edge_type = path_generator.get_path_edge_type_vertices(
			x, edge_z, x + 1, edge_z, 0
		)
		
		return _is_alleyway_type(edge_type)
	
	elif diff.y == 0:
		var min_x = min(cell1.x, cell2.x)
		var z = cell1.y
		var edge_x = min_x if diff.x < 0 else min_x + 1
		
		var edge_type = path_generator.get_path_edge_type_vertices(
			edge_x, z, edge_x, z + 1, 0
		)
		
		return _is_alleyway_type(edge_type)
	
	return false

func _is_alleyway_type(edge_type: int) -> bool:
	return edge_type in [
		DistortedGrid.CellType.SMALL,
		DistortedGrid.CellType.BIG,
		DistortedGrid.CellType.SMALL_ORIGIN,
		DistortedGrid.CellType.BIG_ORIGIN,
		DistortedGrid.CellType.FACADE  # CAMBIO: era BOUNDARY
	]

func _subdivide_section_into_clusters(section: Array, rng: RandomNumberGenerator, start_cluster_id: int) -> int:
	var unassigned_cells = section.duplicate()
	var clusters_created = 0
	
	while unassigned_cells.size() > 0:
		var cluster = BuildingCluster.new(
			start_cluster_id + clusters_created, 
			cluster_seed,
			min_floors_per_cluster,
			max_floors_per_cluster
		)
		
		var start_cell = unassigned_cells[rng.randi_range(0, unassigned_cells.size() - 1)]
		var target_size = rng.randi_range(1, 8)
		_grow_cluster(cluster, start_cell, unassigned_cells, target_size, rng)
		
		building_clusters.append(cluster)
		
		for cell in cluster.cells:
			cell_to_cluster["%d_%d" % [cell.x, cell.y]] = cluster.id
		
		clusters_created += 1
	
	return clusters_created

func _grow_cluster(cluster: BuildingCluster, start_cell: Vector2i, unassigned: Array, target_size: int, rng: RandomNumberGenerator) -> void:
	cluster.add_cell(start_cell.x, start_cell.y)
	unassigned.erase(start_cell)
	
	var frontier: Array[Vector2i] = _get_unassigned_neighbors(start_cell, unassigned)
	
	while cluster.get_cell_count() < target_size and frontier.size() > 0:
		var next_cell = frontier[rng.randi_range(0, frontier.size() - 1)]
		frontier.erase(next_cell)
		
		if next_cell not in unassigned:
			continue
		
		cluster.add_cell(next_cell.x, next_cell.y)
		unassigned.erase(next_cell)
		
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

func _assign_block_hearts() -> void:
	if block_heart_probability <= 0.0:
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = cluster_seed + 9999
	
	var candidates_count = 0
	var hearts_count = 0
	
	for cluster in building_clusters:
		if cluster.is_interior_cluster(distorted_grid.rows, distorted_grid.columns):
			candidates_count += 1
			
			if rng.randf() < block_heart_probability:
				cluster.set_block_heart(true)
				cluster.floor_count = 0
				hearts_count += 1
	
	if candidates_count > 0:
		print("[BlockGenerator] Corazones de manzana: %d de %d candidatos (%.1f%%) - sin altura" % 
			[hearts_count, candidates_count, (float(hearts_count) / float(candidates_count)) * 100.0])

func _get_core_block_vertices() -> Array[Vector2]:
	var vertices: Array[Vector2] = []
	
	var full_vertices = grid_geometry.vertices
	var columns = grid_geometry.columns
	var rows = grid_geometry.rows
	
	var u_min = float(available_min_x) / max(1, columns)
	var u_max = float(available_max_x + 1) / max(1, columns)
	var v_min = float(available_min_z) / max(1, rows)
	var v_max = float(available_max_z + 1) / max(1, rows)
	
	var bl = GridHelper.bilinear_interpolation(full_vertices, u_min, v_min)
	vertices.append(bl)
	
	var br = GridHelper.bilinear_interpolation(full_vertices, u_max, v_min)
	vertices.append(br)
	
	var tr = GridHelper.bilinear_interpolation(full_vertices, u_max, v_max)
	vertices.append(tr)
	
	var tl = GridHelper.bilinear_interpolation(full_vertices, u_min, v_max)
	vertices.append(tl)
	
	return vertices

func get_block_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	
	var vertices = grid_geometry.vertices
	var columns = grid_geometry.columns
	var rows = grid_geometry.rows
	
	var u_min = float(available_min_x) / max(1, columns)
	var u_max = float(available_max_x + 1) / max(1, columns)
	var v_min = float(available_min_z) / max(1, rows)
	var v_max = float(available_max_z + 1) / max(1, rows)
	
	var corner_bl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_min) +
		vertices[1] * u_min * (1 - v_min) +
		vertices[2] * u_min * v_min +
		vertices[3] * (1 - u_min) * v_min
	)
	corners.append(Vector3(corner_bl_2d.x, 0.0, corner_bl_2d.y))
	
	var corner_br_2d = (
		vertices[0] * (1 - u_max) * (1 - v_min) +
		vertices[1] * u_max * (1 - v_min) +
		vertices[2] * u_max * v_min +
		vertices[3] * (1 - u_max) * v_min
	)
	corners.append(Vector3(corner_br_2d.x, 0.0, corner_br_2d.y))
	
	var corner_tr_2d = (
		vertices[0] * (1 - u_max) * (1 - v_max) +
		vertices[1] * u_max * (1 - v_max) +
		vertices[2] * u_max * v_max +
		vertices[3] * (1 - u_max) * v_max
	)
	corners.append(Vector3(corner_tr_2d.x, 0.0, corner_tr_2d.y))
	
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

func get_street_offset(street_type: int) -> int:
	return street_offsets.get(street_type, 0)

func get_max_building_height() -> float:
	var max_height = 0.0
	
	for cluster in building_clusters:
		var cluster_floors = cluster.get_floor_count()
		var actual_floors = min(cluster_floors, grid_geometry.floors)
		
		# CAMBIO: Usar building_cell_height en vez de grid_geometry.cell_height
		var cluster_height = actual_floors * grid_geometry.cells_per_floor * building_cell_height
		
		if cluster_height > max_height:
			max_height = cluster_height
	
	return max_height



# ============================================
# LANE LINES - ACCESO A PUNTOS TEMPORALES
# ============================================

func get_temporal_lane_points() -> Dictionary:
	return temporal_lane_points

func get_core_vertices() -> Array[Vector2]:
	return _get_core_block_vertices()

func get_lane_planes() -> Dictionary:
	return lane_planes

func get_is_clockwise() -> bool:
	return is_clockwise

# ============================================
# LANE PLANES - HELPERS
# ============================================

# Obtiene el volumen formado por las dos lane planes de un edge específico
# Retorna un Dictionary con los 8 vértices que forman el "skewed cube"
# edge_idx: índice del edge (0, 1, 2, o 3)
# Retorna: {
#   "vertices": Array[Vector3] (8 vértices),
#   "start_plane_vertices": Array[Vector3] (4 vértices de la start lane plane),
#   "end_plane_vertices": Array[Vector3] (4 vértices de la end lane plane)
# }
# Retorna Dictionary vacío si el edge es boundary o no tiene ambas lane planes
func get_edge_lane_volume(edge_idx: int) -> Dictionary:
	if edge_idx < 0 or edge_idx > 3:
		push_error("Edge index debe estar entre 0 y 3, recibido: %d" % edge_idx)
		return {}
	
	# Buscar las dos lane planes del edge (una start y una end)
	var start_lane_key = "%d_0" % edge_idx
	var end_lane_key = "%d_1" % edge_idx
	
	# Dependiendo de clockwiseness, determinar cuál es start y cuál es end
	var start_plane_data = null
	var end_plane_data = null
	
	# Verificar ambas posibilidades ya que la asignación de start/end depende del clockwiseness
	if start_lane_key in lane_planes:
		var plane_data = lane_planes[start_lane_key]
		if plane_data["is_start_lane"]:
			start_plane_data = plane_data
		else:
			end_plane_data = plane_data
	
	if end_lane_key in lane_planes:
		var plane_data = lane_planes[end_lane_key]
		if plane_data["is_start_lane"]:
			start_plane_data = plane_data
		else:
			end_plane_data = plane_data
	
	# Si no se encontraron ambas lane planes, retornar vacío silenciosamente
	# Esto es normal para edges boundary (límites de la ciudad)
	if start_plane_data == null or end_plane_data == null:
		return {}
	
	var height = start_plane_data["height"]
	var street_type = start_plane_data.get("street_type", 0)  # Default a SMALL si no existe
	
	# Crear los 4 vértices de la start lane plane
	var start_plane_v1 = Vector3(start_plane_data["start"].x, 0.0, start_plane_data["start"].y)
	var start_plane_v2 = Vector3(start_plane_data["end"].x, 0.0, start_plane_data["end"].y)
	var start_plane_v3 = Vector3(start_plane_data["end"].x, height, start_plane_data["end"].y)
	var start_plane_v4 = Vector3(start_plane_data["start"].x, height, start_plane_data["start"].y)
	
	# Crear los 4 vértices de la end lane plane
	var end_plane_v1 = Vector3(end_plane_data["start"].x, 0.0, end_plane_data["start"].y)
	var end_plane_v2 = Vector3(end_plane_data["end"].x, 0.0, end_plane_data["end"].y)
	var end_plane_v3 = Vector3(end_plane_data["end"].x, height, end_plane_data["end"].y)
	var end_plane_v4 = Vector3(end_plane_data["start"].x, height, end_plane_data["start"].y)
	
	# Array con los 8 vértices del volumen
	# Orden: 4 vértices de start plane + 4 vértices de end plane
	var all_vertices: Array[Vector3] = [
		start_plane_v1, start_plane_v2, start_plane_v3, start_plane_v4,
		end_plane_v1, end_plane_v2, end_plane_v3, end_plane_v4
	]
	
	return {
		"vertices": all_vertices,
		"start_plane_vertices": [start_plane_v1, start_plane_v2, start_plane_v3, start_plane_v4],
		"end_plane_vertices": [end_plane_v1, end_plane_v2, end_plane_v3, end_plane_v4],
		"height": height,
		"street_type": street_type
	}
