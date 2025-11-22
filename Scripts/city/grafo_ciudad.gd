class_name GraphCityGenerator
extends RefCounted

var plain_graph: GraphGenerator  
var neighborhoods: Dictionary = {}   # {face_idx: neighborhood_id} barrio de cada cara (-1 = sin asignar)
var street_types: Dictionary = {}    # {edge_key: tipo} tipo de cada calle (-1=límite, 0=pequeña, 1=mediana, 2=grande, 3=túnel chico, 4=túnel grande)
var block_grids: Dictionary = {}     # {face_idx: BlockGenerator} grilla 3D de cada manzana
var region_size: Vector2 = Vector2.ZERO  # Tamaño de la región

func generate_city_graph(
	smooth_steps: int,
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int,
	generation_seed: int,
	num_neighborhoods: int,
	num_large_streets: int,
	num_small_streets: int,
	num_small_tunnels: int = 0,
	num_large_tunnels: int = 0,
	tunnel_min_length: int = 2,
	tunnel_max_length: int = 6,
	tunnel_max_angle_degrees: float = 30.0,
	tunnel_min_gap: int = 3,
	block_grid_rows: int = 20,
	block_grid_columns: int = 20,
	block_grid_floors: int = 3,
	block_cells_per_floor: int = 4,
	rect_max_divisions: int = 4,
	rect_min_size: int = 2,
) -> void:
	
	seed(generation_seed)
	self.region_size = region_size
	
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
	_assign_neighborhoods(num_neighborhoods)
	
	var block_cell_height = min_distance / block_grid_rows
	_generate_block_grids(
		block_grid_rows,
		block_grid_columns,
		block_grid_floors,
		block_cells_per_floor,
		block_cell_height,
		rect_max_divisions,
		rect_min_size
	)

# ============================================
# GESTIÓN DE TIPOS DE CALLES
# ============================================

func _initialize_street_types() -> void:
	street_types.clear()
	
	for edge in plain_graph.edges:
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		street_types[edge_key] = 1  # Mediana por defecto

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
		_generate_street_path(2)  # Tipo 2 = grande

func _generate_small_streets(num_small_streets: int) -> void:
	for i in range(num_small_streets):
		_generate_street_path(0)  # Tipo 0 = pequeña

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
# GESTIÓN DE BARRIOS
# ============================================

func _initialize_neighborhoods() -> void:
	neighborhoods.clear()
	for face_idx in range(plain_graph.faces.size()):
		neighborhoods[face_idx] = -1

func _assign_neighborhoods(num_neighborhoods: int) -> void:
	if num_neighborhoods <= 0:
		push_warning("Número de barrios debe ser mayor a 0")
		return
	
	var total_faces = plain_graph.faces.size()
	if total_faces == 0:
		push_warning("No hay caras en el grafo para asignar barrios")
		return
	
	var actual_neighborhoods = min(num_neighborhoods, total_faces)
	
	var available_faces = range(total_faces)
	available_faces.shuffle()
	
	var expansion_fronts: Array[Array] = []
	
	for neighborhood_id in range(actual_neighborhoods):
		var seed_face = available_faces[neighborhood_id]
		neighborhoods[seed_face] = neighborhood_id
		var queue: Array = [seed_face]
		expansion_fronts.append(queue)
	
	var active_fronts = true
	
	while active_fronts:
		active_fronts = false
		
		for neighborhood_id in range(actual_neighborhoods):
			var queue = expansion_fronts[neighborhood_id]
			
			if queue.is_empty():
				continue
			
			active_fronts = true
			var current_front_size = queue.size()
			
			for i in range(current_front_size):
				var current_face = queue.pop_front()
				var adjacent_faces = plain_graph.get_adjacent_faces(current_face)
				
				for adj_face in adjacent_faces:
					if neighborhoods[adj_face] == -1:
						neighborhoods[adj_face] = neighborhood_id
						queue.append(adj_face)

func get_neighborhood_for_face(face_idx: int) -> int:
	if face_idx in neighborhoods:
		return neighborhoods[face_idx]
	return -1

func get_faces_in_neighborhood(neighborhood_id: int) -> Array[int]:
	var faces_in_neighborhood: Array[int] = []
	
	for face_idx in neighborhoods:
		if neighborhoods[face_idx] == neighborhood_id:
			faces_in_neighborhood.append(face_idx)
	
	return faces_in_neighborhood

# ============================================
# GESTIÓN DE GRILLAS DE MANZANAS
# ============================================

func _generate_block_grids(
	rows: int,
	columns: int,
	floors: int,
	cells_per_floor: int,
	cell_height: float,
	max_divisions: int,
	min_size: int
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
		
		var block = BlockGenerator.new(
			rows,
			columns,
			face_vertices,
			street_types_array,
			cell_height,
			floors,
			cells_per_floor
		)
		
		# Generar los rectángulos para este bloque
		block.generate_rectangles(max_divisions, min_size, face_idx)
		
		block_grids[face_idx] = block

func get_block_grid(face_idx: int)->BlockGenerator:
	return block_grids.get(face_idx, null)

func get_all_block_faces() -> Array[int]:
	var faces: Array[int] = []
	for face_idx in block_grids:
		faces.append(face_idx)
	return faces

func has_block_grid(face_idx: int) -> bool:
	return face_idx in block_grids
