class_name GraphCityGenerator
extends RefCounted

var plain_graph: GraphGenerator  
var neighborhood_manager: NeighborhoodManager
var street_types: Dictionary = {}
var block_grids: Dictionary = {}
var region_size: Vector2 = Vector2.ZERO
var pedestrian_planes: Dictionary = {}

var neighborhood_height_falloff: float = 1.0

var block_rows: int
var block_columns: int
var street_offsets: Dictionary = {}

var distorted_grid_rows: int
var distorted_grid_columns: int
var wave_amplitude_x: float
var wave_amplitude_z: float
var wave_frequency_x: float
var wave_frequency_z: float
var wave_phase_x: float
var wave_phase_z: float
var edge_falloff_sharpness: float

var small_alleyways_count: int
var big_alleyways_count: int
var min_steps_before_turn: int
var grid_seed: int

var building_grid_rows: int
var building_grid_columns: int
var block_cell_height: float
var building_cell_height: float
var cells_per_floor: int

func generate_city_graph(
	smooth_steps: int,
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int,
	generation_seed: int,
	num_large_streets: int,
	num_small_streets: int,
	block_grid_rows: int,
	block_grid_columns: int,
	block_grid_floors: int,
	block_cells_per_floor: int,
	p_distorted_grid_rows: int = 10,
	p_distorted_grid_columns: int = 10,
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
	p_building_grid_rows: int = 10,
	p_building_grid_columns: int = 10,
	p_block_cell_height: float = 0.01,
	p_building_cell_height: float = 0.005,
	p_neighborhood_height_falloff: float = 1.0,
	p_num_neighborhoods: int = 3,
	p_neighborhood_seed: int = -1
) -> void:
	
	seed(generation_seed)
	self.region_size = region_size
	self.block_rows = block_grid_rows
	self.block_columns = block_grid_columns
	self.neighborhood_height_falloff = p_neighborhood_height_falloff
	
	self.distorted_grid_rows = p_distorted_grid_rows
	self.distorted_grid_columns = p_distorted_grid_columns
	self.wave_amplitude_x = p_wave_amplitude_x
	self.wave_amplitude_z = p_wave_amplitude_z
	self.wave_frequency_x = p_wave_frequency_x
	self.wave_frequency_z = p_wave_frequency_z
	self.wave_phase_x = p_wave_phase_x
	self.wave_phase_z = p_wave_phase_z
	self.edge_falloff_sharpness = p_edge_falloff_sharpness
	
	self.small_alleyways_count = p_small_alleyways_count
	self.big_alleyways_count = p_big_alleyways_count
	self.min_steps_before_turn = p_min_steps_before_turn
	self.grid_seed = p_grid_seed
	
	self.building_grid_rows = p_building_grid_rows
	self.building_grid_columns = p_building_grid_columns
	self.block_cell_height = p_block_cell_height
	self.building_cell_height = p_building_cell_height
	self.cells_per_floor = block_cells_per_floor
	
	# Generar grafo base
	plain_graph = GraphGenerator.new()
	plain_graph.generate_graph(
		smooth_steps,
		region_size,
		min_distance,
		rejection_samples,
		generation_seed,
	)
	
	# Calles
	_initialize_street_types()
	_mark_boundary_streets()
	_generate_small_streets(num_small_streets)
	_generate_large_streets(num_large_streets)
	
	# Barrios con nuevo sistema
	var neighborhood_seed = p_neighborhood_seed if p_neighborhood_seed != -1 else generation_seed
	neighborhood_manager = NeighborhoodManager.new(plain_graph, p_num_neighborhoods, neighborhood_seed)
	neighborhood_manager.generate_neighborhoods()
	
	# Grillas de manzanas
	_generate_block_grids(
		block_grid_floors,
		block_cells_per_floor,
		p_block_cell_height,
		p_building_cell_height
	)
	
	# Planos y lanes
	_generate_pedestrian_planes()
	_calculate_temporal_lane_points()
	_calculate_lane_planes()

# ============================================
# GESTIÓN DE TIPOS DE CALLES
# ============================================

func _initialize_street_types() -> void:
	street_types.clear()
	
	for edge in plain_graph.edges:
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		street_types[edge_key] = 1

func _mark_boundary_streets() -> void:
	for edge in plain_graph.edges:
		var node1_idx = edge[0]
		var node2_idx = edge[1]
		
		var node1_type = plain_graph.node_types.get(node1_idx, 0)
		var node2_type = plain_graph.node_types.get(node2_idx, 0)
		
		if node1_type == 1 and node2_type == 1:
			var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
			street_types[edge_key] = -1

func _generate_large_streets(num_large_streets: int) -> void:
	for i in range(num_large_streets):
		_generate_street_path(2)

func _generate_small_streets(num_small_streets: int) -> void:
	for i in range(num_small_streets):
		_generate_street_path(0)

func _generate_street_path(street_type: int) -> void:
	if plain_graph.edges.is_empty():
		return
	
	var initial_edge = plain_graph.edges[randi() % plain_graph.edges.size()]
	var node1 = initial_edge[0]
	var node2 = initial_edge[1]
	
	var edge_key = GraphGenerator._get_edge_key(node1, node2)
	if _can_overwrite_street(edge_key, street_type):
		street_types[edge_key] = street_type
	
	var pos1 = plain_graph.points[node1]
	var pos2 = plain_graph.points[node2]
	
	var direction1 = (pos2 - pos1).normalized()
	var direction2 = (pos1 - pos2).normalized()
	
	_expand_street_from_edge(node2, node1, street_type, direction1)
	_expand_street_from_edge(node1, node2, street_type, direction2)

func _expand_street_from_edge(current_node: int, previous_node: int, street_type: int, target_direction: Vector3) -> void:
	var max_iterations = 100
	var iterations = 0
	
	while iterations < max_iterations:
		iterations += 1
		
		var current_node_type = plain_graph.node_types.get(current_node, 0)
		if current_node_type == 1:
			break
		
		var next_edge = _get_next_edge_with_target_direction(
			current_node, 
			previous_node, 
			street_type,
			target_direction
		)
		
		if next_edge.is_empty():
			next_edge = _find_edge_towards_boundary(current_node, previous_node, street_type)
			
			if next_edge.is_empty():
				break
		
		var edge_key = GraphGenerator._get_edge_key(next_edge[0], next_edge[1])
		if _can_overwrite_street(edge_key, street_type):
			street_types[edge_key] = street_type
		
		previous_node = current_node
		current_node = next_edge[1] if next_edge[0] == current_node else next_edge[0]

func _get_next_edge_with_target_direction(
	current_node: int, 
	previous_node: int, 
	street_type: int,
	target_direction: Vector3
) -> Array:
	var connected_edges = plain_graph.get_edges_for_node(current_node)
	var current_pos = plain_graph.points[current_node]
	var previous_pos = plain_graph.points[previous_node]
	var current_direction = (current_pos - previous_pos).normalized()
	
	var best_edge: Array = []
	var best_score = -INF
	
	for edge in connected_edges:
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		
		if other_node == previous_node:
			continue
		
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		
		if not _can_overwrite_street(edge_key, street_type):
			continue
		
		var other_pos = plain_graph.points[other_node]
		var edge_direction = (other_pos - current_pos).normalized()
		
		var angle_with_current = current_direction.dot(edge_direction)
		var angle_with_target = target_direction.dot(edge_direction)
		
		var score = (angle_with_target * 0.6) + (angle_with_current * 0.4)
		
		if score > best_score:
			best_score = score
			best_edge = edge
	
	return best_edge

func _can_overwrite_street(edge_key: String, new_type: int) -> bool:
	var current_type = street_types.get(edge_key, 1)
	
	if current_type == -1:
		return false
	
	if new_type == 0:
		return current_type == 1
	
	if new_type == 2:
		return current_type == 0 or current_type == 1
	
	return false

func _find_edge_towards_boundary(current_node: int, previous_node: int, street_type: int) -> Array:
	var connected_edges = plain_graph.get_edges_for_node(current_node)
	var best_edge: Array = []
	var best_score = -INF
	
	for edge in connected_edges:
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		
		if other_node == previous_node:
			continue
		
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		
		if not _can_overwrite_street(edge_key, street_type):
			continue
		
		var score = 0.0
		var node_type = plain_graph.node_types.get(other_node, 0)
		
		if node_type == 1:
			score = 1000.0
		else:
			var node_pos = plain_graph.points[other_node]
			var dist_to_edge_x = min(node_pos.x, self.region_size.x - node_pos.x)
			var dist_to_edge_y = min(node_pos.y, self.region_size.y - node_pos.y)
			var min_dist = min(dist_to_edge_x, dist_to_edge_y)
			score = -min_dist
		
		if score > best_score:
			best_score = score
			best_edge = edge
	
	return best_edge

func get_street_type(node1_idx: int, node2_idx: int) -> int:
	var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
	return street_types.get(edge_key, 1)

func get_streets_of_type(street_type: int) -> Array:
	var result: Array = []
	
	for edge_key in street_types:
		if street_types[edge_key] == street_type:
			result.append(edge_key)
	
	return result

# ============================================
# GESTIÓN DE GRILLAS DE MANZANAS
# ============================================

func _generate_block_grids(
	floors: int,
	cells_per_floor: int,
	block_cell_height: float,
	building_cell_height: float
) -> void:
	block_grids.clear()
	
	for face_idx in range(plain_graph.faces.size()):
		var face_nodes = plain_graph.faces[face_idx]
		var face_vertices: Array[Vector2] = []
		
		for node_idx in face_nodes:
			var pos_3d = plain_graph.points[node_idx]
			face_vertices.append(Vector2(pos_3d.x, pos_3d.z))
		
		var street_types_array: Array[int] = []
		for i in range(face_nodes.size()):
			var node1 = face_nodes[i]
			var node2 = face_nodes[(i + 1) % face_nodes.size()]
			street_types_array.append(get_street_type(node1, node2))
		
		var is_clockwise = _is_face_clockwise(face_vertices)
		
		var block_seed = grid_seed
		if grid_seed == -1:
			block_seed = hash(face_idx)
		
		# Obtener barrio y calcular transición de alturas
		var neighborhood = neighborhood_manager.get_neighborhood_for_face(face_idx)
		var distance_from_seed = neighborhood_manager.get_distance_for_face(face_idx)
		var falloff_factor = pow(distance_from_seed, neighborhood_height_falloff)
		
		var min_floors = 1
		var max_floors = 8
		var block_heart_prob = 0.0
		
		if neighborhood != null:
			# Usar valores del barrio
			var target_min = neighborhood.min_floors
			var target_max = neighborhood.max_floors
			
			# Calcular promedio global de todos los barrios
			var all_neighborhoods = neighborhood_manager.get_neighborhoods()
			var global_min = 0
			var global_max = 0
			
			for n in all_neighborhoods:
				global_min += n.min_floors
				global_max += n.max_floors
			
			if all_neighborhoods.size() > 0:
				global_min = int(float(global_min) / float(all_neighborhoods.size()))
				global_max = int(float(global_max) / float(all_neighborhoods.size()))
			
			# Interpolar según distancia
			min_floors = int(lerp(float(target_min), float(global_min), falloff_factor))
			max_floors = int(lerp(float(target_max), float(global_max), falloff_factor))
			
			if min_floors > max_floors:
				min_floors = max_floors
			
			block_heart_prob = neighborhood.block_heart_probability
		
		var block = BlockGenerator.new(
			block_rows,
			block_columns,
			face_vertices,
			street_types_array,
			block_cell_height,
			floors,
			cells_per_floor,
			is_clockwise,
			street_offsets,
			distorted_grid_rows,
			distorted_grid_columns,
			wave_amplitude_x,
			wave_amplitude_z,
			wave_frequency_x,
			wave_frequency_z,
			wave_phase_x,
			wave_phase_z,
			edge_falloff_sharpness,
			small_alleyways_count,
			big_alleyways_count,
			min_steps_before_turn,
			block_seed,
			building_grid_rows,
			building_grid_columns,
			building_cell_height,
			{},
			min_floors,
			max_floors,
			block_heart_prob
		)
		
		block_grids[face_idx] = block

func _is_face_clockwise(vertices: Array[Vector2]) -> bool:
	var area = 0.0
	for i in range(vertices.size()):
		var v1 = vertices[i]
		var v2 = vertices[(i + 1) % vertices.size()]
		area += (v2.x - v1.x) * (v2.y + v1.y)
	return area > 0

func get_block_grid(face_idx: int) -> BlockGenerator:
	return block_grids.get(face_idx, null)

func get_all_block_faces() -> Array[int]:
	var faces: Array[int] = []
	for face_idx in block_grids:
		faces.append(face_idx)
	return faces

func has_block_grid(face_idx: int) -> bool:
	return face_idx in block_grids

func get_max_building_height_global() -> float:
	var max_height = 0.0
	
	for face_idx in block_grids:
		var block: BlockGenerator = block_grids[face_idx]
		var block_max_height = block.get_max_building_height()
		
		if block_max_height > max_height:
			max_height = block_max_height
	
	return max_height

# ============================================
# GESTIÓN DE PLANOS PEATONALES
# ============================================

func _generate_pedestrian_planes() -> void:
	pedestrian_planes.clear()
	
	for edge in plain_graph.edges:
		var node1_idx = edge[0]
		var node2_idx = edge[1]
		var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
		
		var adjacent_faces = _find_faces_sharing_edge(node1_idx, node2_idx)
		
		if adjacent_faces.size() != 2:
			continue
		
		var face1_idx = adjacent_faces[0]
		var face2_idx = adjacent_faces[1]
		
		var corner1_node1 = get_block_corner_with_offset(node1_idx, edge, face1_idx)
		var corner1_node2 = get_block_corner_with_offset(node2_idx, edge, face1_idx)
		
		var corner2_node1 = get_block_corner_with_offset(node1_idx, edge, face2_idx)
		var corner2_node2 = get_block_corner_with_offset(node2_idx, edge, face2_idx)
		
		if corner1_node1 == Vector2.ZERO or corner1_node2 == Vector2.ZERO or \
		   corner2_node1 == Vector2.ZERO or corner2_node2 == Vector2.ZERO:
			continue
		
		var plane1 = [corner1_node1, corner2_node1]
		var plane2 = [corner1_node2, corner2_node2]
		
		pedestrian_planes[edge_key] = [plane1, plane2]

func _find_faces_sharing_edge(node1_idx: int, node2_idx: int) -> Array[int]:
	var sharing_faces: Array[int] = []
	
	for face_idx in range(plain_graph.faces.size()):
		var face = plain_graph.faces[face_idx]
		
		if node1_idx in face and node2_idx in face:
			sharing_faces.append(face_idx)
	
	return sharing_faces

func get_pedestrian_planes_for_edge(node1_idx: int, node2_idx: int) -> Array:
	var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
	return pedestrian_planes.get(edge_key, [])

func get_all_pedestrian_planes() -> Dictionary:
	return pedestrian_planes

# ============================================
# GESTIÓN DE LANE LINES
# ============================================

func _calculate_temporal_lane_points() -> void:
	var total_points = 0
	
	for face_idx in block_grids:
		var block: BlockGenerator = block_grids[face_idx]
		var face = plain_graph.faces[face_idx]
		
		for edge_idx in range(face.size()):
			var node1 = face[edge_idx]
			var node2 = face[(edge_idx + 1) % face.size()]
			var edge = [node1, node2]
			
			var neighbor_faces = _find_faces_sharing_edge(node1, node2)
			if neighbor_faces.size() != 2:
				continue
			
			var neighbor_face_idx = neighbor_faces[0] if neighbor_faces[0] != face_idx else neighbor_faces[1]
			
			for node_local_idx in range(2):
				var node_idx = edge[node_local_idx]
				
				var point_a = get_block_corner_with_offset(node_idx, edge, face_idx)
				var point_b = get_block_corner_with_offset(node_idx, edge, neighbor_face_idx)
				
				if point_a != Vector2.ZERO and point_b != Vector2.ZERO:
					var key = "%d_%d" % [edge_idx, node_local_idx]
					block.temporal_lane_points[key] = {
						"point_a": point_a,
						"point_b": point_b
					}
					total_points += 1
	
	print("[GraphCityGenerator] Puntos temporales de lane lines calculados: %d puntos" % total_points)

func _calculate_lane_planes() -> void:
	var max_height_global = get_max_building_height_global()
	
	var total_planes = 0
	var skipped_boundary = 0
	
	for face_idx in block_grids:
		var block: BlockGenerator = block_grids[face_idx]
		var face = plain_graph.faces[face_idx]
		
		for edge_idx in range(face.size()):
			var node1_idx = face[edge_idx]
			var node2_idx = face[(edge_idx + 1) % face.size()]
			
			var edge_street_type = get_street_type(node1_idx, node2_idx)
			if edge_street_type == -1:
				skipped_boundary += 1
				continue
			
			var edge_start_3d = plain_graph.points[node1_idx]
			var edge_end_3d = plain_graph.points[node2_idx]
			var edge_start_2d = Vector2(edge_start_3d.x, edge_start_3d.z)
			var edge_end_2d = Vector2(edge_end_3d.x, edge_end_3d.z)
			
			for node_local_idx in range(2):
				var key = "%d_%d" % [edge_idx, node_local_idx]
				
				if key not in block.temporal_lane_points:
					continue
				
				var point_data = block.temporal_lane_points[key]
				var point_a: Vector2 = point_data["point_a"]
				var point_b: Vector2 = point_data["point_b"]
				
				var intersection = _line_intersection_2d(point_a, point_b, edge_start_2d, edge_end_2d)
				
				if intersection != Vector2.ZERO:
					var is_start_lane: bool
					if block.is_clockwise:
						is_start_lane = (node_local_idx == 1)
					else:
						is_start_lane = (node_local_idx == 0)
					
					block.lane_planes[key] = {
						"start": point_a,
						"end": intersection,
						"is_start_lane": is_start_lane,
						"height": max_height_global,
						"street_type": edge_street_type
					}
					total_planes += 1
	
	print("[GraphCityGenerator] Lane planes finales calculadas: %d planos (altura: %.2f, boundary edges saltados: %d)" % [total_planes, max_height_global, skipped_boundary])

func _line_intersection_2d(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Vector2:
	var x1 = p1.x
	var y1 = p1.y
	var x2 = p2.x
	var y2 = p2.y
	var x3 = p3.x
	var y3 = p3.y
	var x4 = p4.x
	var y4 = p4.y
	
	var denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
	
	if abs(denominator) < 0.0001:
		return Vector2.ZERO
	
	var t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denominator
	
	var intersection_x = x1 + t * (x2 - x1)
	var intersection_y = y1 + t * (y2 - y1)
	
	return Vector2(intersection_x, intersection_y)

# ============================================
# HELPERS DE GEOMETRÍA
# ============================================

func get_block_corner_with_offset(node_idx: int, edge: Array, face_idx: int) -> Vector2:
	if face_idx < 0 or face_idx >= plain_graph.faces.size():
		push_error("Índice de face inválido: %d" % face_idx)
		return Vector2.ZERO
	
	var face = plain_graph.faces[face_idx]
	
	var node_index_in_face = face.find(node_idx)
	if node_index_in_face == -1:
		push_error("El nodo %d no pertenece a la face %d" % [node_idx, face_idx])
		return Vector2.ZERO
	
	if edge[0] not in face or edge[1] not in face:
		push_error("El edge [%d, %d] no pertenece a la face %d" % [edge[0], edge[1], face_idx])
		return Vector2.ZERO
	
	if node_idx != edge[0] and node_idx != edge[1]:
		push_error("El nodo %d no es parte del edge [%d, %d]" % [node_idx, edge[0], edge[1]])
		return Vector2.ZERO
	
	var block: BlockGenerator = block_grids.get(face_idx, null)
	if block == null:
		push_error("No existe BlockGenerator para face %d" % face_idx)
		return Vector2.ZERO
	
	var core_vertices = block.get_core_vertices()
	
	if core_vertices.size() != 4:
		push_error("Core vertices no tiene 4 elementos para face %d" % face_idx)
		return Vector2.ZERO
	
	var corner: Vector2
	match node_index_in_face:
		0:
			corner = core_vertices[0]
		1:
			corner = core_vertices[1]
		2:
			corner = core_vertices[2]
		3:
			corner = core_vertices[3]
		_:
			push_error("Índice de nodo en face inválido: %d" % node_index_in_face)
			return Vector2.ZERO
	
	return corner

func get_lane_volume_continuations(face_idx: int, edge_idx: int) -> Array[LaneVolume]:
	var continuations: Array[LaneVolume] = []
	
	var block: BlockGenerator = block_grids.get(face_idx, null)
	if block == null:
		return continuations
	
	var face = plain_graph.faces[face_idx]
	
	var original_node1 = face[edge_idx]
	var original_node2 = face[(edge_idx + 1) % face.size()]
	
	var end_node_idx: int
	if block.is_clockwise:
		end_node_idx = original_node1
	else:
		end_node_idx = original_node2
	
	for other_face_idx in block_grids:
		var other_face = plain_graph.faces[other_face_idx]
		
		if end_node_idx not in other_face:
			continue
		
		var other_block: BlockGenerator = block_grids[other_face_idx]
		if other_block == null:
			continue
		
		for other_edge_idx in range(other_face.size()):
			var other_node1 = other_face[other_edge_idx]
			var other_node2 = other_face[(other_edge_idx + 1) % other_face.size()]
			
			if (other_node1 == original_node1 and other_node2 == original_node2) or \
			   (other_node1 == original_node2 and other_node2 == original_node1):
				continue
			
			var start_node_idx: int
			if other_block.is_clockwise:
				start_node_idx = other_node2
			else:
				start_node_idx = other_node1
			
			if start_node_idx == end_node_idx:
				var volume_data = other_block.get_edge_lane_volume(other_edge_idx)
				
				if not volume_data.is_empty():
					var street_type = volume_data.get("street_type", 0)
					var volume_height = volume_data["height"]
					
					var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(street_type, 3)
					
					var height_cells = 0
					if block_cell_height > 0 and cells_per_floor > 0:
						var floor_height = cells_per_floor * block_cell_height
						var num_floors = ceil(volume_height / floor_height)
						height_cells = int(num_floors * cells_per_floor)
					
					# Determinar barrio del edge (mayor jerarquía)
					var edge_neighborhood = get_neighborhood_for_edge(other_node1, other_node2)
					
					var enriched_data = volume_data.duplicate()
					enriched_data["face_idx"] = other_face_idx
					enriched_data["edge_idx"] = other_edge_idx
					enriched_data["width_cells"] = width_cells
					enriched_data["height_cells"] = height_cells
					enriched_data["neighborhood"] = edge_neighborhood
					enriched_data["cells_per_floor"] = cells_per_floor
					
					continuations.append(LaneVolume.new(enriched_data))
	
	return continuations

# ============================================
# GETTERS DE BARRIOS
# ============================================

func get_neighborhood_manager() -> NeighborhoodManager:
	return neighborhood_manager

func get_neighborhood_for_face(face_idx: int) -> Neighborhood:
	return neighborhood_manager.get_neighborhood_for_face(face_idx)

func get_neighborhood_type_for_face(face_idx: int) -> int:
	var neighborhood = neighborhood_manager.get_neighborhood_for_face(face_idx)
	if neighborhood != null:
		return neighborhood.type
	return -1

func get_faces_in_neighborhood(neighborhood_type: int) -> Array[int]:
	var faces: Array[int] = []
	var neighborhoods = neighborhood_manager.get_neighborhoods_by_type(neighborhood_type)
	
	for neighborhood in neighborhoods:
		faces.append_array(neighborhood.assigned_faces)
	
	return faces

func get_neighborhood_type_name(neighborhood_type: int) -> String:
	match neighborhood_type:
		Neighborhood.Type.SHANTY_TOWN:
			return "Shanty Town"
		Neighborhood.Type.RICH_RESIDENTIAL:
			return "Rich Residential"
		Neighborhood.Type.INDUSTRIAL:
			return "Industrial"
		Neighborhood.Type.DOWNTOWN:
			return "Downtown"
		_:
			return "Unknown"

# Determina el barrio de un edge basándose en las dos faces adyacentes
# Retorna el barrio de mayor jerarquía
func get_neighborhood_for_edge(node1_idx: int, node2_idx: int) -> Neighborhood:
	var adjacent_faces = _find_faces_sharing_edge(node1_idx, node2_idx)
	
	if adjacent_faces.is_empty():
		return null
	
	var neighborhood1 = neighborhood_manager.get_neighborhood_for_face(adjacent_faces[0])
	
	if adjacent_faces.size() == 1:
		return neighborhood1
	
	var neighborhood2 = neighborhood_manager.get_neighborhood_for_face(adjacent_faces[1])
	
	# Retornar el de mayor jerarquía
	return Neighborhood.get_higher_hierarchy(neighborhood1, neighborhood2)
