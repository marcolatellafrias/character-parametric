class_name GraphCityGenerator
extends RefCounted

enum NeighborhoodType {
	INDUSTRIAL = 0,
	RESIDENTIAL = 1,
	FINANCIAL = 2
}

var plain_graph: GraphGenerator  
var neighborhoods: Dictionary = {}
var neighborhood_distances: Dictionary = {}
var street_types: Dictionary = {}
var block_grids: Dictionary = {}
var region_size: Vector2 = Vector2.ZERO
var pedestrian_planes: Dictionary = {}
var root_floors: Array[int] = []

var neighborhood_floor_ranges: Dictionary = {}
var neighborhood_height_falloff: float = 1.0
var neighborhood_block_heart_probabilities: Dictionary = {}

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
	p_industrial_min_floors: int = 1,
	p_industrial_max_floors: int = 3,
	p_residential_min_floors: int = 4,
	p_residential_max_floors: int = 8,
	p_financial_min_floors: int = 6,
	p_financial_max_floors: int = 12,
	p_neighborhood_height_falloff: float = 1.0,
	p_industrial_block_heart_probability: float = 0.2,
	p_residential_block_heart_probability: float = 0.3,
	p_financial_block_heart_probability: float = 0.1
) -> void:
	
	seed(generation_seed)
	self.region_size = region_size
	self.block_rows = block_grid_rows
	self.block_columns = block_grid_columns
	self.neighborhood_height_falloff = p_neighborhood_height_falloff
	
	neighborhood_floor_ranges = {
		NeighborhoodType.INDUSTRIAL: {"min": p_industrial_min_floors, "max": p_industrial_max_floors},
		NeighborhoodType.RESIDENTIAL: {"min": p_residential_min_floors, "max": p_residential_max_floors},
		NeighborhoodType.FINANCIAL: {"min": p_financial_min_floors, "max": p_financial_max_floors}
	}
	
	neighborhood_block_heart_probabilities = {
		NeighborhoodType.INDUSTRIAL: p_industrial_block_heart_probability,
		NeighborhoodType.RESIDENTIAL: p_residential_block_heart_probability,
		NeighborhoodType.FINANCIAL: p_financial_block_heart_probability
	}
	
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
	
	plain_graph = GraphGenerator.new()
	plain_graph.generate_graph(
		smooth_steps,
		region_size,
		min_distance,
		rejection_samples,
		generation_seed,
	)
	
	_initialize_street_types()
	_mark_boundary_streets()
	_generate_small_streets(num_small_streets)
	_generate_large_streets(num_large_streets)
	_initialize_neighborhoods()
	_assign_neighborhoods()
	
	_generate_block_grids(
		block_grid_floors,
		block_cells_per_floor,
		p_block_cell_height,
		p_building_cell_height
	)
	
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
# GESTIÓN DE BARRIOS
# ============================================

func _initialize_neighborhoods() -> void:
	neighborhoods.clear()
	for face_idx in range(plain_graph.faces.size()):
		neighborhoods[face_idx] = -1

func _assign_neighborhoods() -> void:
	var total_faces = plain_graph.faces.size()
	if total_faces == 0:
		push_warning("No hay caras en el grafo para asignar barrios")
		return
	
	var num_neighborhood_types = 3
	
	var available_faces = range(total_faces)
	available_faces.shuffle()
	
	neighborhood_distances.clear()
	for face_idx in range(total_faces):
		neighborhood_distances[face_idx] = 999999
	
	var expansion_fronts: Array[Array] = []
	var seed_faces: Array[int] = []
	
	for neighborhood_type in range(num_neighborhood_types):
		if neighborhood_type < total_faces:
			var seed_face = available_faces[neighborhood_type]
			neighborhoods[seed_face] = neighborhood_type
			neighborhood_distances[seed_face] = 0
			seed_faces.append(seed_face)
			var queue: Array = [[seed_face, 0]]
			expansion_fronts.append(queue)
	
	var active_fronts = true
	
	while active_fronts:
		active_fronts = false
		
		for neighborhood_type in range(num_neighborhood_types):
			if neighborhood_type >= expansion_fronts.size():
				continue
				
			var queue = expansion_fronts[neighborhood_type]
			
			if queue.is_empty():
				continue
			
			active_fronts = true
			var current_front_size = queue.size()
			
			for i in range(current_front_size):
				var current_data = queue.pop_front()
				var current_face = current_data[0]
				var current_distance = current_data[1]
				
				var adjacent_faces = plain_graph.get_adjacent_faces(current_face)
				
				for adj_face in adjacent_faces:
					if neighborhoods[adj_face] == -1:
						neighborhoods[adj_face] = neighborhood_type
						neighborhood_distances[adj_face] = current_distance + 1
						queue.append([adj_face, current_distance + 1])
	
	var max_distance = 0
	for face_idx in neighborhood_distances:
		if neighborhood_distances[face_idx] > max_distance and neighborhood_distances[face_idx] < 999999:
			max_distance = neighborhood_distances[face_idx]
	
	for face_idx in neighborhood_distances:
		if neighborhood_distances[face_idx] < 999999 and max_distance > 0:
			neighborhood_distances[face_idx] = float(neighborhood_distances[face_idx]) / float(max_distance)
		else:
			neighborhood_distances[face_idx] = 1.0
	
	print("[GraphCityGenerator] Barrios asignados:")
	print("  Industrial (0): %d manzanas" % get_faces_in_neighborhood(NeighborhoodType.INDUSTRIAL).size())
	print("  Residential (1): %d manzanas" % get_faces_in_neighborhood(NeighborhoodType.RESIDENTIAL).size())
	print("  Financial (2): %d manzanas" % get_faces_in_neighborhood(NeighborhoodType.FINANCIAL).size())
	print("  Distancia máxima: %d pasos" % max_distance)

func get_neighborhood_for_face(face_idx: int) -> int:
	if face_idx in neighborhoods:
		return neighborhoods[face_idx]
	return -1

func get_faces_in_neighborhood(neighborhood_type: int) -> Array[int]:
	var faces_in_neighborhood: Array[int] = []
	
	for face_idx in neighborhoods:
		if neighborhoods[face_idx] == neighborhood_type:
			faces_in_neighborhood.append(face_idx)
	
	return faces_in_neighborhood

func get_neighborhood_type_name(neighborhood_type: int) -> String:
	match neighborhood_type:
		NeighborhoodType.INDUSTRIAL:
			return "Industrial"
		NeighborhoodType.RESIDENTIAL:
			return "Residential"
		NeighborhoodType.FINANCIAL:
			return "Financial"
		_:
			return "Unknown"

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
		
		var neighborhood_type = get_neighborhood_for_face(face_idx)
		var distance_from_seed = neighborhood_distances.get(face_idx, 1.0)
		var falloff_factor = pow(distance_from_seed, neighborhood_height_falloff)
		
		var min_floors = 1
		var max_floors = 8
		var block_heart_prob = 0.0
		
		if neighborhood_type in neighborhood_floor_ranges:
			var range_data = neighborhood_floor_ranges[neighborhood_type]
			var target_min = range_data["min"]
			var target_max = range_data["max"]
			
			var global_min = 0
			var global_max = 0
			var type_count = 0
			
			for type_key in neighborhood_floor_ranges:
				var type_range = neighborhood_floor_ranges[type_key]
				global_min += type_range["min"]
				global_max += type_range["max"]
				type_count += 1
			
			if type_count > 0:
				global_min = int(float(global_min) / float(type_count))
				global_max = int(float(global_max) / float(type_count))
			
			min_floors = int(lerp(float(target_min), float(global_min), falloff_factor))
			max_floors = int(lerp(float(target_max), float(global_max), falloff_factor))
			
			if min_floors > max_floors:
				min_floors = max_floors
		
		if neighborhood_type in neighborhood_block_heart_probabilities:
			block_heart_prob = neighborhood_block_heart_probabilities[neighborhood_type]
		
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
		
		# Cada face tiene 4 edges
		for edge_idx in range(face.size()):
			var node1 = face[edge_idx]
			var node2 = face[(edge_idx + 1) % face.size()]
			var edge = [node1, node2]
			
			# Encontrar face vecino
			var neighbor_faces = _find_faces_sharing_edge(node1, node2)
			if neighbor_faces.size() != 2:
				continue
			
			var neighbor_face_idx = neighbor_faces[0] if neighbor_faces[0] != face_idx else neighbor_faces[1]
			
			# Calcular puntos para cada nodo del edge
			for node_local_idx in range(2):
				var node_idx = edge[node_local_idx]
				
				# Punto A: usando el face actual
				var point_a = get_block_corner_with_offset(node_idx, edge, face_idx)
				
				# Punto B: usando el face vecino
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
	# Primero, calcular la altura máxima global de todos los edificios
	var max_height_global = get_max_building_height_global()
	
	var total_planes = 0
	var skipped_boundary = 0
	
	for face_idx in block_grids:
		var block: BlockGenerator = block_grids[face_idx]
		var face = plain_graph.faces[face_idx]
		
		# Cada face tiene 4 edges
		for edge_idx in range(face.size()):
			var node1_idx = face[edge_idx]
			var node2_idx = face[(edge_idx + 1) % face.size()]
			
			# Verificar si este edge es boundary (tipo -1)
			# Los edges boundary no tienen 2 faces adyacentes, solo tienen 1
			# Por lo tanto no pueden generar lane planes correctamente
			var edge_street_type = get_street_type(node1_idx, node2_idx)
			if edge_street_type == -1:
				skipped_boundary += 1
				continue
			
			# Obtener posiciones 3D de los nodos del edge original
			var edge_start_3d = plain_graph.points[node1_idx]
			var edge_end_3d = plain_graph.points[node2_idx]
			var edge_start_2d = Vector2(edge_start_3d.x, edge_start_3d.z)
			var edge_end_2d = Vector2(edge_end_3d.x, edge_end_3d.z)
			
			# Calcular lane planes para cada nodo del edge
			for node_local_idx in range(2):
				var key = "%d_%d" % [edge_idx, node_local_idx]
				
				if key not in block.temporal_lane_points:
					continue
				
				var point_data = block.temporal_lane_points[key]
				var point_a: Vector2 = point_data["point_a"]
				var point_b: Vector2 = point_data["point_b"]
				
				# Calcular intersección entre línea temporal (point_a -> point_b) y edge original
				var intersection = _line_intersection_2d(point_a, point_b, edge_start_2d, edge_end_2d)
				
				if intersection != Vector2.ZERO:
					# Determinar si esta lane plane es "start" o "end"
					# Esto depende de si el face es clockwise o counter-clockwise
					var is_start_lane: bool
					if block.is_clockwise:
						# Face clockwise: node_local_idx 0 es end, 1 es start
						is_start_lane = (node_local_idx == 1)
					else:
						# Face counter-clockwise: node_local_idx 0 es start, 1 es end
						is_start_lane = (node_local_idx == 0)
					
					# Lane plane final: desde point_a hasta el punto de intersección, con altura máxima
					block.lane_planes[key] = {
						"start": point_a,
						"end": intersection,
						"is_start_lane": is_start_lane,
						"height": max_height_global,
						"street_type": edge_street_type
					}
					total_planes += 1
	
	print("[GraphCityGenerator] Lane planes finales calculadas: %d planos (altura: %.2f, boundary edges saltados: %d)" % [total_planes, max_height_global, skipped_boundary])

# Calcula la intersección entre dos líneas 2D
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
	
	# Líneas paralelas o coincidentes
	if abs(denominator) < 0.0001:
		return Vector2.ZERO
	
	var t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denominator
	
	# Calcular punto de intersección
	var intersection_x = x1 + t * (x2 - x1)
	var intersection_y = y1 + t * (y2 - y1)
	
	return Vector2(intersection_x, intersection_y)

# ============================================
# HELPERS - SELECCIÓN POR ÁREA
# ============================================

# Obtiene todos los BlockGenerators que intersectan con un disco circular
# center: Vector2 o Vector3 (centro del disco en el espacio global, Y es ignorada si es Vector3)
# radius: Radio del disco
# segments: Número de segmentos para discretizar el perímetro del círculo (mayor = más preciso)
# Retorna: Array[int] con los índices de los faces cuyos BlockGenerators intersectan el disco
func get_blocks_in_circular_area(center, radius: float, segments: int = 32) -> Array[int]:
	var center_2d: Vector2
	
	# Convertir center a Vector2 si es Vector3 (proyectar al plano XZ)
	if center is Vector3:
		center_2d = Vector2(center.x, center.z)
	elif center is Vector2:
		center_2d = center
	else:
		push_error("get_blocks_in_circular_area: center debe ser Vector2 o Vector3")
		return []
	
	if segments < 3:
		push_error("get_blocks_in_circular_area: segments debe ser al menos 3")
		return []
	
	var intersecting_faces: Array[int] = []
	
	for face_idx in block_grids:
		var face = plain_graph.faces[face_idx]
		
		# Obtener los vértices 2D de este face
		var face_vertices_2d: Array[Vector2] = []
		for node_idx in face:
			var pos_3d = plain_graph.points[node_idx]
			face_vertices_2d.append(Vector2(pos_3d.x, pos_3d.z))
		
		# Verificar si el disco circular intersecta con este quad
		if _circle_intersects_quad(center_2d, radius, face_vertices_2d, segments):
			intersecting_faces.append(face_idx)
	
	return intersecting_faces

# Obtiene todos los lane volumes que intersectan con un volumen cilíndrico
# center: Vector3 (centro del cilindro en el espacio global - centro del volumen, no de la base)
# radius: Radio del cilindro
# height: Altura del cilindro
# Retorna: Array[Dictionary] donde cada Dictionary contiene:
#   - face_idx: int
#   - edge_idx: int
#   - start_plane_vertices: Array[Vector3] (4 vértices)
#   - end_plane_vertices: Array[Vector3] (4 vértices)
#   - height: float
#   - street_type: int (0=SMALL, 1=MEDIUM, 2=LARGE)
#   - width_cells: int (celdas de ancho de este lane)
#   - height_cells: int (celdas de altura total)
func get_lane_volumes_in_cylindrical_area(center: Vector3, radius: float, height: float) -> Array[Dictionary]:
	# Calcular el rango Y del cilindro
	# El centro está en el medio del cilindro, no en la base
	var cylinder_y_min = center.y - height / 2.0
	var cylinder_y_max = center.y + height / 2.0
	
	var intersecting_volumes: Array[Dictionary] = []
	
	# Primero obtener los bloques en el área circular (proyección 2D)
	var blocks_in_area = get_blocks_in_circular_area(center, radius)
	
	# Para cada bloque, verificar sus lane volumes
	for face_idx in blocks_in_area:
		var block: BlockGenerator = block_grids.get(face_idx, null)
		if block == null:
			continue
		
		# Cada bloque tiene 4 edges
		for edge_idx in range(4):
			var volume_data = block.get_edge_lane_volume(edge_idx)
			
			if volume_data.is_empty():
				continue
			
			var volume_height = volume_data["height"]
			
			# Verificar si el lane volume intersecta con el rango Y del cilindro
			# Lane volume va de y=0 a y=volume_height
			if volume_height < cylinder_y_min or 0.0 > cylinder_y_max:
				# No hay intersección en Y
				continue
			
			var start_plane_verts = volume_data["start_plane_vertices"]
			var end_plane_verts = volume_data["end_plane_vertices"]
			
			# Verificar si alguno de los vértices del volumen está dentro del cilindro 2D
			var intersects = false
			var center_2d = Vector2(center.x, center.z)
			
			# Verificar vértices del start plane
			for vertex in start_plane_verts:
				var vertex_2d = Vector2(vertex.x, vertex.z)
				if center_2d.distance_to(vertex_2d) <= radius:
					intersects = true
					break
			
			# Si no intersectó con start plane, verificar end plane
			if not intersects:
				for vertex in end_plane_verts:
					var vertex_2d = Vector2(vertex.x, vertex.z)
					if center_2d.distance_to(vertex_2d) <= radius:
						intersects = true
						break
			
			# También verificar si el cilindro intersecta los edges del volumen
			if not intersects:
				# Obtener los edges del volumen en 2D y verificar intersección con círculo
				var volume_edges_2d = [
					[Vector2(start_plane_verts[0].x, start_plane_verts[0].z), Vector2(start_plane_verts[1].x, start_plane_verts[1].z)],
					[Vector2(start_plane_verts[1].x, start_plane_verts[1].z), Vector2(end_plane_verts[1].x, end_plane_verts[1].z)],
					[Vector2(end_plane_verts[1].x, end_plane_verts[1].z), Vector2(end_plane_verts[0].x, end_plane_verts[0].z)],
					[Vector2(end_plane_verts[0].x, end_plane_verts[0].z), Vector2(start_plane_verts[0].x, start_plane_verts[0].z)]
				]
				
				for edge_2d in volume_edges_2d:
					if _circle_intersects_line_segment(center_2d, radius, edge_2d[0], edge_2d[1]):
						intersects = true
						break
			
			if intersects:
				var street_type = volume_data.get("street_type", 0)
				
				# Calcular ancho en celdas
				# Cada lane es media calle, así que usamos STREET_HALF_WIDTH_CELLS directamente
				var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(street_type, 3)
				
				# Calcular altura en celdas
				# La altura del volumen se calcula como: floors * cells_per_floor * block_cell_height
				# Entonces: floors = altura / (cells_per_floor * block_cell_height)
				# Y height_cells = floors * cells_per_floor
				var height_cells = 0
				if block_cell_height > 0 and cells_per_floor > 0:
					var floor_height = cells_per_floor * block_cell_height
					var num_floors = ceil(volume_height / floor_height)
					height_cells = int(num_floors * cells_per_floor)
				
				intersecting_volumes.append({
					"face_idx": face_idx,
					"edge_idx": edge_idx,
					"start_plane_vertices": start_plane_verts,
					"end_plane_vertices": end_plane_verts,
					"height": volume_height,
					"street_type": street_type,
					"width_cells": width_cells,
					"height_cells": height_cells
				})
	
	return intersecting_volumes

# Verifica si un círculo intersecta con un quad (polígono de 4 vértices)
# segments: Número de segmentos para discretizar el perímetro del círculo
func _circle_intersects_quad(circle_center: Vector2, circle_radius: float, quad_vertices: Array[Vector2], segments: int) -> bool:
	if quad_vertices.size() != 4:
		return false
	
	# Test 1: Verificar si el centro del círculo está dentro del quad
	if _point_in_quad(circle_center, quad_vertices):
		return true
	
	# Test 2: Verificar si algún vértice del quad está dentro del círculo
	for vertex in quad_vertices:
		if circle_center.distance_to(vertex) <= circle_radius:
			return true
	
	# Test 3: Verificar si algún edge del quad intersecta con el círculo
	for i in range(4):
		var v1 = quad_vertices[i]
		var v2 = quad_vertices[(i + 1) % 4]
		
		if _circle_intersects_line_segment(circle_center, circle_radius, v1, v2):
			return true
	
	# Test 4: Verificar si algún punto del perímetro del círculo está dentro del quad
	# Esto captura casos donde el quad está completamente dentro del círculo
	# o casos donde ninguno de los tests anteriores detecta la intersección
	var angle_step = TAU / segments
	for i in range(segments):
		var angle = i * angle_step
		var point_on_circle = circle_center + Vector2(cos(angle), sin(angle)) * circle_radius
		
		if _point_in_quad(point_on_circle, quad_vertices):
			return true
	
	return false

# Verifica si un punto está dentro de un quad usando el algoritmo de ray casting
func _point_in_quad(point: Vector2, quad_vertices: Array[Vector2]) -> bool:
	var inside = false
	var j = quad_vertices.size() - 1
	
	for i in range(quad_vertices.size()):
		var vi = quad_vertices[i]
		var vj = quad_vertices[j]
		
		if ((vi.y > point.y) != (vj.y > point.y)) and \
		   (point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x):
			inside = !inside
		
		j = i
	
	return inside

# Verifica si un círculo intersecta con un segmento de línea
func _circle_intersects_line_segment(circle_center: Vector2, circle_radius: float, line_start: Vector2, line_end: Vector2) -> bool:
	# Calcular el punto más cercano en el segmento de línea al centro del círculo
	var line_vec = line_end - line_start
	var line_len_squared = line_vec.length_squared()
	
	if line_len_squared == 0:
		# El segmento es un punto
		return circle_center.distance_to(line_start) <= circle_radius
	
	# Parámetro t que representa la proyección del centro del círculo sobre la línea
	var t = ((circle_center - line_start).dot(line_vec)) / line_len_squared
	t = clamp(t, 0.0, 1.0)
	
	# Punto más cercano en el segmento
	var closest_point = line_start + t * line_vec
	
	# Verificar si la distancia es menor o igual al radio
	return circle_center.distance_to(closest_point) <= circle_radius

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
	
	# Obtener el BlockGenerator para esta face
	var block: BlockGenerator = block_grids.get(face_idx, null)
	if block == null:
		push_error("No existe BlockGenerator para face %d" % face_idx)
		return Vector2.ZERO
	
	# Usar directamente las esquinas del core block
	# Las esquinas están ordenadas: [bottom-left, bottom-right, top-right, top-left]
	var core_vertices = block.get_core_vertices()
	
	if core_vertices.size() != 4:
		push_error("Core vertices no tiene 4 elementos para face %d" % face_idx)
		return Vector2.ZERO
	
	# Mapear el índice del nodo en la face a la esquina correspondiente del core block
	# Asumiendo que la face está ordenada como: [BL, BR, TR, TL]
	var corner: Vector2
	match node_index_in_face:
		0:  # Bottom-left
			corner = core_vertices[0]
		1:  # Bottom-right
			corner = core_vertices[1]
		2:  # Top-right
			corner = core_vertices[2]
		3:  # Top-left
			corner = core_vertices[3]
		_:
			push_error("Índice de nodo en face inválido: %d" % node_index_in_face)
			return Vector2.ZERO
	
	return corner

# Obtiene todos los lane volumes que continúan desde el lane volume dado
# face_idx: ID de la manzana (face) del lane volume origen
# edge_idx: ID del edge (0-3) dentro de esa face
# Retorna: Array[Dictionary] con {face_idx: int, edge_idx: int} de las continuaciones
# NOTA: Excluye lane volumes que compartan el mismo edge (no son continuaciones)
func get_lane_volume_continuations(face_idx: int, edge_idx: int) -> Array[Dictionary]:
	var continuations: Array[Dictionary] = []
	
	# Validar que existe el block
	var block: BlockGenerator = block_grids.get(face_idx, null)
	if block == null:
		return continuations
	
	var face = plain_graph.faces[face_idx]
	
	# Obtener los dos nodos que forman el edge original
	var original_node1 = face[edge_idx]
	var original_node2 = face[(edge_idx + 1) % face.size()]
	
	# Determinar cuál nodo corresponde al end plane del lane volume dado
	var end_node_idx: int
	if block.is_clockwise:
		# En clockwise: node_local_idx=0 es end plane
		end_node_idx = original_node1
	else:
		# En counter-clockwise: node_local_idx=1 es end plane
		end_node_idx = original_node2
	
	# Buscar en todas las faces que contengan este nodo
	for other_face_idx in block_grids:
		var other_face = plain_graph.faces[other_face_idx]
		
		# Si esta face no contiene el nodo, skip
		if end_node_idx not in other_face:
			continue
		
		var other_block: BlockGenerator = block_grids[other_face_idx]
		if other_block == null:
			continue
		
		# Revisar cada edge de esta face
		for other_edge_idx in range(other_face.size()):
			var other_node1 = other_face[other_edge_idx]
			var other_node2 = other_face[(other_edge_idx + 1) % other_face.size()]
			
			# Verificar que NO sea el mismo edge (no comparten ambos nodos)
			if (other_node1 == original_node1 and other_node2 == original_node2) or \
			   (other_node1 == original_node2 and other_node2 == original_node1):
				continue
			
			# Determinar cuál nodo es el start plane de este edge
			var start_node_idx: int
			if other_block.is_clockwise:
				# En clockwise: node_local_idx=1 es start plane
				start_node_idx = other_node2
			else:
				# En counter-clockwise: node_local_idx=0 es start plane
				start_node_idx = other_node1
			
			# Si el start plane de este volume coincide con el end plane del original
			if start_node_idx == end_node_idx:
				# Verificar que este edge tiene un lane volume válido (no boundary)
				var volume_data = other_block.get_edge_lane_volume(other_edge_idx)
				
				if not volume_data.is_empty():
					continuations.append({
						"face_idx": other_face_idx,
						"edge_idx": other_edge_idx
					})
	
	return continuations
