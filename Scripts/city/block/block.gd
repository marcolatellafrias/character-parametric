class_name BlockGenerator extends RefCounted

enum StreetType {
	BOUNDARY = -1,
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2
}

const LANES_PER_STREET_TYPE: Dictionary = {
	StreetType.BOUNDARY: 0,
	StreetType.SMALL: 2,
	StreetType.MEDIUM: 4,
	StreetType.LARGE: 6
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

var lanes: Dictionary = {}
var lane_additional_width: int = 0
var lane_height_cells: int = 1

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

var root_floors: Array[int] = []
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
	p_root_floors: Array[int] = [],
	p_min_floors_per_cluster: int = 1,
	p_max_floors_per_cluster: int = 8,
	p_block_heart_probability: float = 0.0,
	p_lane_additional_width: int = 0,
	p_lane_height_cells: int = 2
) -> void:
	street_types = p_street_types
	is_clockwise = p_is_clockwise
	street_offsets = p_street_offsets
	root_floors = p_root_floors
	lane_additional_width = p_lane_additional_width
	lane_height_cells = p_lane_height_cells
	
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
	
	for street_type in LANES_PER_STREET_TYPE.keys():
		var num_lanes = LANES_PER_STREET_TYPE[street_type]
		var lane_width = _get_lane_width()
		
		var total_offset = (num_lanes * lane_width) / 2
		offsets[street_type] = total_offset
	
	return offsets

func _get_lane_width() -> int:
	return 1 + (2 * lane_additional_width)

func _get_lane_center_offsets(street_type: int) -> Array[int]:
	var centers: Array[int] = []
	var num_lanes = LANES_PER_STREET_TYPE.get(street_type, 0)
	
	if num_lanes == 0:
		return centers
	
	var lane_width = _get_lane_width()
	var lanes_per_half = num_lanes / 2
	var offset_total = street_offsets.get(street_type, 0)
	
	for i in range(lanes_per_half):
		var center_from_edge = int((i * lane_width) + float(lane_width) / 2.0)
		var center_offset = offset_total - center_from_edge
		centers.append(center_offset)
	
	return centers

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
		DistortedGrid.CellType.BOUNDARY
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

func _calculate_lanes() -> void:
	lanes["north"] = _get_lane_cells_for_street_type(street_types[0], "north")
	lanes["east"] = _get_lane_cells_for_street_type(street_types[1], "east")
	lanes["south"] = _get_lane_cells_for_street_type(street_types[2], "south")
	lanes["west"] = _get_lane_cells_for_street_type(street_types[3], "west")

func _get_lane_cells_for_street_type(street_type: int, side: String) -> Array[Dictionary]:
	var lane_cells: Array[Dictionary] = []
	var center_offsets = _get_lane_center_offsets(street_type)
	
	for offset in center_offsets:
		var cell1: Vector2i
		var cell2: Vector2i
		
		match side:
			"north":
				var z = available_min_z - offset
				cell1 = Vector2i(0, z)
				cell2 = Vector2i(grid_geometry.columns - 1, z)
			"south":
				var z = available_max_z + offset
				cell1 = Vector2i(0, z)
				cell2 = Vector2i(grid_geometry.columns - 1, z)
			"west":
				var x = available_min_x - offset
				cell1 = Vector2i(x, 0)
				cell2 = Vector2i(x, grid_geometry.rows - 1)
			"east":
				var x = available_max_x + offset
				cell1 = Vector2i(x, 0)
				cell2 = Vector2i(x, grid_geometry.rows - 1)
		
		var needs_swap = false
		
		match side:
			"north":
				needs_swap = is_clockwise
			"south":
				needs_swap = not is_clockwise
			"west":
				needs_swap = not is_clockwise
			"east":
				needs_swap = is_clockwise
		
		if needs_swap:
			var temp = cell1
			cell1 = cell2
			cell2 = temp
		
		lane_cells.append({
			"cell1": cell1,
			"cell2": cell2,
			"additional_width": lane_additional_width
		})
	
	return lane_cells

func get_all_lanes() -> Array[Dictionary]:
	var all_lanes: Array[Dictionary] = []
	
	for side in ["north", "south", "east", "west"]:
		var side_lanes = lanes.get(side, [])
		for lane_idx in range(side_lanes.size()):
			var lane_data = side_lanes[lane_idx]
			all_lanes.append({
				"cell1": lane_data["cell1"],
				"cell2": lane_data["cell2"],
				"additional_width": lane_data["additional_width"],
				"side": side,
				"index": lane_idx
			})
	
	return all_lanes

func get_lane_edges(cell1: Vector2i, cell2: Vector2i, additional_width: int, side: String) -> Dictionary:
	var result = {
		"start_edge": [],
		"end_edge": []
	}
	
	match side:
		"north", "south":
			var west_x = min(cell1.x, cell2.x)
			var east_x = max(cell1.x, cell2.x)
			var start_is_west = (cell1.x == west_x)
			
			var z_min = min(cell1.y, cell2.y) - additional_width
			var z_max = max(cell1.y, cell2.y) + additional_width
			
			var cell_sw = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				west_x, z_min
			)
			var cell_nw = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				west_x, z_max
			)
			var west_edge = [cell_sw[0], cell_nw[3]]
			
			var cell_se = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				east_x, z_min
			)
			var cell_ne = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				east_x, z_max
			)
			var east_edge = [cell_se[1], cell_ne[2]]
			
			if start_is_west:
				result["start_edge"] = west_edge
				result["end_edge"] = east_edge
			else:
				result["start_edge"] = east_edge
				result["end_edge"] = west_edge
		
		"west", "east":
			var north_z = min(cell1.y, cell2.y)
			var south_z = max(cell1.y, cell2.y)
			var start_is_north = (cell1.y == north_z)
			
			var x_min = min(cell1.x, cell2.x) - additional_width
			var x_max = max(cell1.x, cell2.x) + additional_width
			
			var cell_nw = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				x_min, north_z
			)
			var cell_ne = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				x_max, north_z
			)
			var north_edge = [cell_nw[0], cell_ne[1]]
			
			var cell_sw = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				x_min, south_z
			)
			var cell_se = GridHelper.get_cell_base_vertices(
				grid_geometry.vertices, grid_geometry.rows, grid_geometry.columns,
				x_max, south_z
			)
			var south_edge = [cell_sw[3], cell_se[2]]
			
			if start_is_north:
				result["start_edge"] = north_edge
				result["end_edge"] = south_edge
			else:
				result["start_edge"] = south_edge
				result["end_edge"] = north_edge
	
	return result

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

func get_root_floors() -> Array[int]:
	return root_floors

func get_street_offset(street_type: int) -> int:
	return street_offsets.get(street_type, 0)

func get_lane_width() -> int:
	return _get_lane_width()

func get_lane_height() -> float:
	return lane_height_cells * grid_geometry.cell_height

func get_max_building_height() -> float:
	var max_height = 0.0
	
	for cluster in building_clusters:
		var cluster_floors = cluster.get_floor_count()
		var cluster_height = cluster_floors * grid_geometry.cells_per_floor * grid_geometry.cell_height
		
		if cluster_height > max_height:
			max_height = cluster_height
	
	return max_height

func get_lanes_per_street_type(street_type: int) -> int:
	return LANES_PER_STREET_TYPE.get(street_type, 0)
