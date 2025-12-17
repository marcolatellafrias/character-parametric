class_name GraphCityGenerator
extends RefCounted

# Tipos de barrios
enum NeighborhoodType {
	INDUSTRIAL = 0,
	RESIDENTIAL = 1,
	FINANCIAL = 2
}

var plain_graph: GraphGenerator  
var neighborhoods: Dictionary = {}
var neighborhood_distances: Dictionary = {}  # {face_idx: distance_from_seed}
var street_types: Dictionary = {}
var block_grids: Dictionary = {}
var region_size: Vector2 = Vector2.ZERO
var pedestrian_planes: Dictionary = {}
var root_floors: Array[int] = []

# Rangos de altura por tipo de barrio
var neighborhood_floor_ranges: Dictionary = {}  # {NeighborhoodType: {min: int, max: int}}
var neighborhood_height_falloff: float = 1.0  # Controla qué tan rápido disminuyen las alturas

# Configuración de grillas
var block_rows: int
var block_columns: int

# Offsets de calles
var street_offsets: Dictionary = {}

# Configuración de DistortedGrid
var distorted_grid_rows: int
var distorted_grid_columns: int
var wave_amplitude_x: float
var wave_amplitude_z: float
var wave_frequency_x: float
var wave_frequency_z: float
var wave_phase_x: float
var wave_phase_z: float
var edge_falloff_sharpness: float

# Configuración de PathGenerator
var small_alleyways_count: int
var big_alleyways_count: int
var min_steps_before_turn: int
var grid_seed: int

# Configuración de grilla de Buildings
var building_grid_rows: int
var building_grid_columns: int

func generate_city_graph(
	smooth_steps: int,
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int,
	generation_seed: int,
	num_large_streets: int,
	num_small_streets: int,
	num_small_tunnels: int,
	num_large_tunnels: int,
	tunnel_min_length: int,
	tunnel_max_length: int,
	tunnel_max_angle_degrees: float,
	tunnel_min_gap: int,
	block_grid_rows: int,
	block_grid_columns: int,
	block_grid_floors: int,
	block_cells_per_floor: int,
	boundary_offset: int,
	small_street_offset: int,
	medium_street_offset: int,
	large_street_offset: int,
	small_tunnel_offset: int,
	large_tunnel_offset: int,
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
	p_root_floors: Array[int] = [],
	p_industrial_min_floors: int = 1,
	p_industrial_max_floors: int = 3,
	p_residential_min_floors: int = 4,
	p_residential_max_floors: int = 8,
	p_financial_min_floors: int = 6,
	p_financial_max_floors: int = 12,
	p_neighborhood_height_falloff: float = 1.0
) -> void:
	
	seed(generation_seed)
	self.region_size = region_size
	self.block_rows = block_grid_rows
	self.block_columns = block_grid_columns
	self.root_floors = p_root_floors
	self.neighborhood_height_falloff = p_neighborhood_height_falloff
	
	# Configurar rangos de altura por tipo de barrio
	neighborhood_floor_ranges = {
		NeighborhoodType.INDUSTRIAL: {"min": p_industrial_min_floors, "max": p_industrial_max_floors},
		NeighborhoodType.RESIDENTIAL: {"min": p_residential_min_floors, "max": p_residential_max_floors},
		NeighborhoodType.FINANCIAL: {"min": p_financial_min_floors, "max": p_financial_max_floors}
	}
	
	# Guardar configuración de DistortedGrid
	self.distorted_grid_rows = p_distorted_grid_rows
	self.distorted_grid_columns = p_distorted_grid_columns
	self.wave_amplitude_x = p_wave_amplitude_x
	self.wave_amplitude_z = p_wave_amplitude_z
	self.wave_frequency_x = p_wave_frequency_x
	self.wave_frequency_z = p_wave_frequency_z
	self.wave_phase_x = p_wave_phase_x
	self.wave_phase_z = p_wave_phase_z
	self.edge_falloff_sharpness = p_edge_falloff_sharpness
	
	# Guardar configuración de PathGenerator
	self.small_alleyways_count = p_small_alleyways_count
	self.big_alleyways_count = p_big_alleyways_count
	self.min_steps_before_turn = p_min_steps_before_turn
	self.grid_seed = p_grid_seed
	
	# Guardar configuración de grilla de Buildings
	self.building_grid_rows = p_building_grid_rows
	self.building_grid_columns = p_building_grid_columns
	
	# Configurar offsets de calles
	street_offsets = {
		-1: boundary_offset,
		0: small_street_offset,
		1: medium_street_offset,
		2: large_street_offset,
		3: small_tunnel_offset,
		4: large_tunnel_offset
	}
	
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
	_generate_small_tunnels(num_small_tunnels, tunnel_min_length, tunnel_max_length, tunnel_max_angle_degrees, tunnel_min_gap)
	_generate_large_tunnels(num_large_tunnels, tunnel_min_length, tunnel_max_length, tunnel_max_angle_degrees, tunnel_min_gap)
	_initialize_neighborhoods()
	_assign_neighborhoods()  # Ya no necesita num_neighborhoods
	
	_generate_block_grids(
		block_grid_floors,
		block_cells_per_floor,
		p_block_cell_height,
		p_building_cell_height
	)
	
	_generate_pedestrian_planes()

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
	
	if current_type == 3 or current_type == 4:
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
# GESTIÓN DE TÚNELES
# ============================================

func _generate_small_tunnels(
	num_tunnels: int, 
	min_length: int, 
	max_length: int, 
	max_angle_degrees: float, 
	min_gap: int
) -> void:
	for i in range(num_tunnels):
		_generate_tunnel_path(0, 3, min_length, max_length, max_angle_degrees, min_gap)

func _generate_large_tunnels(
	num_tunnels: int, 
	min_length: int, 
	max_length: int, 
	max_angle_degrees: float, 
	min_gap: int
) -> void:
	for i in range(num_tunnels):
		_generate_tunnel_path(2, 4, min_length, max_length, max_angle_degrees, min_gap)

func _generate_tunnel_path(
	base_street_type: int,
	tunnel_type: int,
	min_length: int,
	max_length: int,
	max_angle_degrees: float,
	min_gap: int
) -> void:
	var candidate_edges: Array = []
	
	for edge in plain_graph.edges:
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		var current_type = street_types.get(edge_key, 1)
		
		if current_type == base_street_type:
			if _has_nearby_tunnels(edge[0], edge[1], min_gap):
				continue
			
			candidate_edges.append(edge)
	
	if candidate_edges.is_empty():
		return
	
	var initial_edge = candidate_edges[randi() % candidate_edges.size()]
	var node1 = initial_edge[0]
	var node2 = initial_edge[1]
	
	var tunnel_length = randi_range(min_length, max_length)
	
	var edge_key = GraphGenerator._get_edge_key(node1, node2)
	street_types[edge_key] = tunnel_type
	
	var pos1 = plain_graph.points[node1]
	var pos2 = plain_graph.points[node2]
	var initial_direction = (pos2 - pos1).normalized()
	
	_expand_tunnel_from_edge(
		node2, 
		node1, 
		base_street_type, 
		tunnel_type, 
		initial_direction, 
		tunnel_length - 1,
		max_angle_degrees
	)

func _expand_tunnel_from_edge(
	current_node: int,
	previous_node: int,
	base_street_type: int,
	tunnel_type: int,
	previous_direction: Vector3,
	remaining_length: int,
	max_angle_degrees: float
) -> void:
	if remaining_length <= 0:
		return
	
	var connected_edges = plain_graph.get_edges_for_node(current_node)
	var current_pos = plain_graph.points[current_node]
	
	var best_edge: Array = []
	var best_score = -INF
	
	for edge in connected_edges:
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		
		if other_node == previous_node:
			continue
		
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		var current_type = street_types.get(edge_key, 1)
		
		if current_type != base_street_type:
			continue
		
		var other_pos = plain_graph.points[other_node]
		var edge_direction = (other_pos - current_pos).normalized()
		
		var dot_product = previous_direction.dot(edge_direction)
		dot_product = clamp(dot_product, -1.0, 1.0)
		var angle_radians = acos(dot_product)
		var angle_degrees = rad_to_deg(angle_radians)
		
		if angle_degrees > max_angle_degrees:
			continue
		
		var score = dot_product
		
		if score > best_score:
			best_score = score
			best_edge = edge
	
	if best_edge.is_empty():
		return
	
	var edge_key = GraphGenerator._get_edge_key(best_edge[0], best_edge[1])
	street_types[edge_key] = tunnel_type
	
	var next_node = best_edge[1] if best_edge[0] == current_node else best_edge[0]
	var next_pos = plain_graph.points[next_node]
	var new_direction = (next_pos - current_pos).normalized()
	
	_expand_tunnel_from_edge(
		next_node,
		current_node,
		base_street_type,
		tunnel_type,
		new_direction,
		remaining_length - 1,
		max_angle_degrees
	)

func _has_nearby_tunnels(node1: int, node2: int, min_gap: int) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [[node1, node2, 0]]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_node = current[0]
		var previous_node = current[1]
		var distance = current[2]
		
		if distance >= min_gap:
			continue
		
		var visit_key = str(current_node) + "_" + str(previous_node)
		if visit_key in visited:
			continue
		visited[visit_key] = true
		
		var connected_edges = plain_graph.get_edges_for_node(current_node)
		
		for edge in connected_edges:
			var other_node = edge[1] if edge[0] == current_node else edge[0]
			
			var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
			var edge_type = street_types.get(edge_key, 1)
			
			if edge_type == 3 or edge_type == 4:
				return true
			
			if other_node != previous_node:
				queue.append([other_node, current_node, distance + 1])
	
	return false

func get_all_tunnels() -> Array:
	var result: Array = []
	
	for edge_key in street_types:
		var street_type = street_types[edge_key]
		if street_type == 3 or street_type == 4:
			result.append(edge_key)
	
	return result

func is_tunnel(node1_idx: int, node2_idx: int) -> bool:
	var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
	var street_type = street_types.get(edge_key, 1)
	return street_type == 3 or street_type == 4

# ============================================
# GESTIÓN DE BARRIOS (3 TIPOS)
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
	
	# Siempre hay 3 tipos de barrios
	var num_neighborhood_types = 3
	
	var available_faces = range(total_faces)
	available_faces.shuffle()
	
	# Inicializar distancias
	neighborhood_distances.clear()
	for face_idx in range(total_faces):
		neighborhood_distances[face_idx] = 999999  # Distancia infinita inicial
	
	# Elegir semillas para cada tipo de barrio
	var expansion_fronts: Array[Array] = []
	var seed_faces: Array[int] = []
	
	for neighborhood_type in range(num_neighborhood_types):
		if neighborhood_type < total_faces:
			var seed_face = available_faces[neighborhood_type]
			neighborhoods[seed_face] = neighborhood_type
			neighborhood_distances[seed_face] = 0  # Las semillas tienen distancia 0
			seed_faces.append(seed_face)
			var queue: Array = [[seed_face, 0]]  # [face_idx, distance]
			expansion_fronts.append(queue)
	
	var active_fronts = true
	
	# Expansión BFS para los 3 tipos, guardando distancias
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
	
	# Calcular distancia máxima para normalización
	var max_distance = 0
	for face_idx in neighborhood_distances:
		if neighborhood_distances[face_idx] > max_distance and neighborhood_distances[face_idx] < 999999:
			max_distance = neighborhood_distances[face_idx]
	
	# Normalizar distancias (0.0 = semilla, 1.0 = borde más lejano)
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
		
		# Generar seed único por bloque si grid_seed es -1
		var block_seed = grid_seed
		if grid_seed == -1:
			block_seed = hash(face_idx)
		
		# Obtener tipo de barrio para esta cara
		var neighborhood_type = get_neighborhood_for_face(face_idx)
		
		# Obtener distancia normalizada desde la semilla (0.0 = semilla, 1.0 = borde)
		var distance_from_seed = neighborhood_distances.get(face_idx, 1.0)
		
		# Aplicar falloff (curva de potencia)
		var falloff_factor = pow(distance_from_seed, neighborhood_height_falloff)
		
		# Obtener rangos de altura según el tipo de barrio
		var min_floors = 1
		var max_floors = 8
		
		if neighborhood_type in neighborhood_floor_ranges:
			var range_data = neighborhood_floor_ranges[neighborhood_type]
			var target_min = range_data["min"]
			var target_max = range_data["max"]
			
			# Calcular promedio global de todos los tipos (punto de convergencia)
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
			
			# Interpolar entre el rango del barrio y el rango global
			min_floors = int(lerp(float(target_min), float(global_min), falloff_factor))
			max_floors = int(lerp(float(target_max), float(global_max), falloff_factor))
			
			# Asegurar que min <= max
			if min_floors > max_floors:
				min_floors = max_floors
		
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
			root_floors,
			min_floors,
			max_floors
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
	
	var face_vertices: Array[Vector2] = []
	for node_idx_in_face in face:
		var pos_3d = plain_graph.points[node_idx_in_face]
		face_vertices.append(Vector2(pos_3d.x, pos_3d.z))
	
	var street_types_array: Array[int] = []
	for i in range(face.size()):
		var node1 = face[i]
		var node2 = face[(i + 1) % face.size()]
		street_types_array.append(get_street_type(node1, node2))
	
	var available_area = GridHelper.calculate_available_area(
		block_rows,
		block_columns,
		street_offsets,
		street_types_array
	)
	
	if available_area.is_empty():
		push_error("No se pudo calcular el área disponible para la face %d" % face_idx)
		return Vector2.ZERO
	
	var grid_x: int
	var grid_z: int
	
	match node_index_in_face:
		0:
			grid_x = available_area.min_x
			grid_z = available_area.min_z
		1:
			grid_x = available_area.max_x
			grid_z = available_area.min_z
		2:
			grid_x = available_area.max_x
			grid_z = available_area.max_z
		3:
			grid_x = available_area.min_x
			grid_z = available_area.max_z
		_:
			push_error("Índice de nodo en face inválido: %d" % node_index_in_face)
			return Vector2.ZERO
	
	var cell_vertices = GridHelper.get_cell_base_vertices(
		face_vertices,
		block_rows,
		block_columns,
		grid_x,
		grid_z
	)
	
	if cell_vertices.is_empty():
		push_error("No se pudieron obtener vértices para la celda (%d, %d)" % [grid_x, grid_z])
		return Vector2.ZERO
	
	var node_pos = plain_graph.points[node_idx]
	
	var closest_vertex = cell_vertices[0]
	var min_distance = node_pos.distance_to(cell_vertices[0])
	
	for i in range(1, cell_vertices.size()):
		var distance = node_pos.distance_to(cell_vertices[i])
		if distance < min_distance:
			min_distance = distance
			closest_vertex = cell_vertices[i]
	
	return Vector2(closest_vertex.x, closest_vertex.z)
