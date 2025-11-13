class_name GraphCityGenerator
extends RefCounted

var plain_graph: GraphGenerator  
var neighborhoods: Dictionary = {}   # {face_idx: neighborhood_id} barrio de cada cara (-1 = sin asignar)
var street_types: Dictionary = {}    # {edge_key: tipo} tipo de cada calle (-1=límite, 0=pequeña, 1=mediana, 2=grande, 3=túnel chico, 4=túnel grande)
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
	# Nuevos parámetros para túneles
	num_small_tunnels: int = 0,
	num_large_tunnels: int = 0,
	tunnel_min_length: int = 2,
	tunnel_max_length: int = 6,
	tunnel_max_angle_degrees: float = 30.0,
	tunnel_min_gap: int = 3,
) -> void:
	seed(generation_seed)
	
	# Guardar el tamaño de la región
	self.region_size = region_size
	
	# Generar el grafo base
	plain_graph = GraphGenerator.new()
	plain_graph.generate_graph(
		smooth_steps,
		region_size,
		min_distance,
		rejection_samples,
		generation_seed,
	)
	
	# Inicializar tipos de calles
	_initialize_street_types()
	_mark_boundary_streets()
	
	# Generar calles especiales: PRIMERO pequeñas, LUEGO grandes
	_generate_small_streets(num_small_streets)
	_generate_large_streets(num_large_streets)
	
	# Generar túneles: DESPUÉS de las calles
	_generate_small_tunnels(num_small_tunnels, tunnel_min_length, tunnel_max_length, tunnel_max_angle_degrees, tunnel_min_gap)
	_generate_large_tunnels(num_large_tunnels, tunnel_min_length, tunnel_max_length, tunnel_max_angle_degrees, tunnel_min_gap)
	
	# Inicializar y asignar barrios
	_initialize_neighborhoods()
	_assign_neighborhoods(num_neighborhoods)

# ============================================
# GESTIÓN DE TIPOS DE CALLES
# ============================================

## Inicializa todos los edges como calles medianas (tipo 1) por defecto
func _initialize_street_types() -> void:
	street_types.clear()
	
	for edge in plain_graph.edges:
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		street_types[edge_key] = 1  # Mediana por defecto

## Marca las calles que conectan dos nodos límite como tipo -1 (calle límite)
func _mark_boundary_streets() -> void:
	for edge in plain_graph.edges:
		var node1_idx = edge[0]
		var node2_idx = edge[1]
		
		# Obtener los tipos de ambos nodos
		var node1_type = plain_graph.node_types.get(node1_idx, 0)
		var node2_type = plain_graph.node_types.get(node2_idx, 0)
		
		# Si ambos nodos son límite (tipo 1), la calle es límite (tipo -1)
		if node1_type == 1 and node2_type == 1:
			var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
			street_types[edge_key] = -1

## Genera calles grandes mediante expansión desde nodos aleatorios
func _generate_large_streets(num_large_streets: int) -> void:
	for i in range(num_large_streets):
		_generate_street_path(2)  # Tipo 2 = grande

## Genera calles pequeñas mediante expansión desde nodos aleatorios
func _generate_small_streets(num_small_streets: int) -> void:
	for i in range(num_small_streets):
		_generate_street_path(0)  # Tipo 0 = pequeña

## Genera un camino de calle del tipo especificado
## Expande desde un edge aleatorio en ambas direcciones hasta los bordes
func _generate_street_path(street_type: int) -> void:
	if plain_graph.edges.is_empty():
		return
	
	# 1. Elegir un edge aleatorio como punto de partida
	var initial_edge = plain_graph.edges[randi() % plain_graph.edges.size()]
	var node1 = initial_edge[0]
	var node2 = initial_edge[1]
	
	# 2. Marcar el edge inicial si es posible
	var edge_key = GraphGenerator._get_edge_key(node1, node2)
	if _can_overwrite_street(edge_key, street_type):
		street_types[edge_key] = street_type
	
	# 3. Calcular las direcciones opuestas basadas en la orientación del edge
	var pos1 = plain_graph.points[node1]
	var pos2 = plain_graph.points[node2]
	
	# Dirección 1: de node1 hacia node2
	var direction1 = (pos2 - pos1).normalized()
	
	# Dirección 2: de node2 hacia node1 (opuesta)
	var direction2 = (pos1 - pos2).normalized()
	
	# 4. Expandir desde node2 en la dirección 1 (continuando más allá de node2)
	_expand_street_from_edge(node2, node1, street_type, direction1)
	
	# 5. Expandir desde node1 en la dirección 2 (continuando más allá de node1)
	_expand_street_from_edge(node1, node2, street_type, direction2)

## Expande una calle desde un edge inicial en una dirección hasta llegar a un borde
func _expand_street_from_edge(current_node: int, previous_node: int, street_type: int, target_direction: Vector3) -> void:
	var max_iterations = 100  # Límite de seguridad
	var iterations = 0
	
	while iterations < max_iterations:
		iterations += 1
		
		# Verificar si llegamos a un nodo límite
		var current_node_type = plain_graph.node_types.get(current_node, 0)
		if current_node_type == 1:
			break  # Llegamos a un nodo límite
		
		# Obtener el siguiente edge considerando TANTO el ángulo actual COMO la dirección objetivo
		var next_edge = _get_next_edge_with_target_direction(
			current_node, 
			previous_node, 
			street_type,
			target_direction
		)
		
		if next_edge.is_empty():
			# Si no hay camino válido, intentar encontrar CUALQUIER edge 
			# que nos lleve más cerca del borde
			next_edge = _find_edge_towards_boundary(current_node, previous_node, street_type)
			
			if next_edge.is_empty():
				break  # Realmente no hay más camino
		
		# Marcar el nuevo edge si es posible
		var edge_key = GraphGenerator._get_edge_key(next_edge[0], next_edge[1])
		if _can_overwrite_street(edge_key, street_type):
			street_types[edge_key] = street_type
		
		# Avanzar al siguiente nodo
		previous_node = current_node
		current_node = next_edge[1] if next_edge[0] == current_node else next_edge[0]

## Encuentra el siguiente edge considerando tanto la dirección actual como la dirección objetivo
## Esto evita que las calles hagan loops y mantiene una trayectoria más recta
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
		
		# No retroceder
		if other_node == previous_node:
			continue
		
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		
		# Solo considerar edges que podamos sobreescribir
		if not _can_overwrite_street(edge_key, street_type):
			continue
		
		var other_pos = plain_graph.points[other_node]
		var edge_direction = (other_pos - current_pos).normalized()
		
		# Calcular ángulo con la dirección actual (para suavidad)
		var angle_with_current = current_direction.dot(edge_direction)
		
		# Calcular ángulo con la dirección objetivo (para evitar loops)
		var angle_with_target = target_direction.dot(edge_direction)
		
		# Score combinado: 60% dirección objetivo, 40% suavidad
		# Esto prioriza mantener el curso pero permite cierta curvatura natural
		var score = (angle_with_target * 0.6) + (angle_with_current * 0.4)
		
		if score > best_score:
			best_score = score
			best_edge = edge
	
	return best_edge

## Verifica si un tipo de calle puede sobreescribir otro
func _can_overwrite_street(edge_key: String, new_type: int) -> bool:
	var current_type = street_types.get(edge_key, 1)
	
	# Nunca sobrescribir calles límite
	if current_type == -1:
		return false
	
	# Nunca sobrescribir túneles
	if current_type == 3 or current_type == 4:
		return false
	
	# Calles pequeñas (0) solo sobrescriben medianas (1)
	if new_type == 0:
		return current_type == 1
	
	# Calles grandes (2) sobrescriben pequeñas (0) y medianas (1)
	if new_type == 2:
		return current_type == 0 or current_type == 1
	
	# Por defecto, no sobrescribir
	return false

## Encuentra un edge hacia el borde del mapa cuando no hay camino directo
func _find_edge_towards_boundary(current_node: int, previous_node: int, street_type: int) -> Array:
	var connected_edges = plain_graph.get_edges_for_node(current_node)
	var best_edge: Array = []
	var best_score = -INF
	
	for edge in connected_edges:
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		
		# No retroceder
		if other_node == previous_node:
			continue
		
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		
		# Solo considerar edges que podamos sobreescribir
		if not _can_overwrite_street(edge_key, street_type):
			continue
		
		# Calcular score: preferir nodos límite o más cercanos al borde
		var score = 0.0
		var node_type = plain_graph.node_types.get(other_node, 0)
		
		if node_type == 1:
			score = 1000.0  # Prioridad máxima para nodos límite
		else:
			# Calcular distancia al borde más cercano usando self.region_size
			var node_pos = plain_graph.points[other_node]
			var dist_to_edge_x = min(node_pos.x, self.region_size.x - node_pos.x)
			var dist_to_edge_y = min(node_pos.y, self.region_size.y - node_pos.y)
			var min_dist = min(dist_to_edge_x, dist_to_edge_y)
			score = -min_dist  # Menor distancia = mayor score
		
		if score > best_score:
			best_score = score
			best_edge = edge
	
	return best_edge

## Obtiene el tipo de una calle (edge)
func get_street_type(node1_idx: int, node2_idx: int) -> int:
	var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
	return street_types.get(edge_key, 1)  # Retorna 1 (mediana) por defecto

## Obtiene todas las calles de un tipo específico
func get_streets_of_type(street_type: int) -> Array:
	var result: Array = []
	
	for edge_key in street_types:
		if street_types[edge_key] == street_type:
			result.append(edge_key)
	
	return result

# ============================================
# GESTIÓN DE TÚNELES
# ============================================

## Genera túneles chicos a partir de calles chicas existentes
func _generate_small_tunnels(
	num_tunnels: int, 
	min_length: int, 
	max_length: int, 
	max_angle_degrees: float, 
	min_gap: int
) -> void:
	for i in range(num_tunnels):
		_generate_tunnel_path(0, 3, min_length, max_length, max_angle_degrees, min_gap)

## Genera túneles grandes a partir de calles grandes existentes
func _generate_large_tunnels(
	num_tunnels: int, 
	min_length: int, 
	max_length: int, 
	max_angle_degrees: float, 
	min_gap: int
) -> void:
	for i in range(num_tunnels):
		_generate_tunnel_path(2, 4, min_length, max_length, max_angle_degrees, min_gap)

## Genera un camino de túnel del tipo especificado
## base_street_type: tipo de calle base (0 para chicas, 2 para grandes)
## tunnel_type: tipo de túnel resultante (3 para chicos, 4 para grandes)
func _generate_tunnel_path(
	base_street_type: int,
	tunnel_type: int,
	min_length: int,
	max_length: int,
	max_angle_degrees: float,
	min_gap: int
) -> void:
	# 1. Encontrar todos los edges del tipo de calle base
	var candidate_edges: Array = []
	
	for edge in plain_graph.edges:
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		var current_type = street_types.get(edge_key, 1)
		
		# Solo considerar calles del tipo base
		if current_type == base_street_type:
			# Verificar que no hay túneles cerca
			if _has_nearby_tunnels(edge[0], edge[1], min_gap):
				continue
			
			candidate_edges.append(edge)
	
	if candidate_edges.is_empty():
		return
	
	# 2. Elegir un edge aleatorio como punto de partida
	var initial_edge = candidate_edges[randi() % candidate_edges.size()]
	var node1 = initial_edge[0]
	var node2 = initial_edge[1]
	
	# 3. Determinar largo aleatorio del túnel
	var tunnel_length = randi_range(min_length, max_length)
	
	# 4. Marcar el edge inicial como túnel
	var edge_key = GraphGenerator._get_edge_key(node1, node2)
	street_types[edge_key] = tunnel_type
	
	# 5. Calcular la dirección inicial
	var pos1 = plain_graph.points[node1]
	var pos2 = plain_graph.points[node2]
	var initial_direction = (pos2 - pos1).normalized()
	
	# 6. Expandir el túnel desde node2
	_expand_tunnel_from_edge(
		node2, 
		node1, 
		base_street_type, 
		tunnel_type, 
		initial_direction, 
		tunnel_length - 1,  # Ya usamos 1 edge
		max_angle_degrees
	)

## Expande un túnel desde un edge inicial
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
		
		# No retroceder
		if other_node == previous_node:
			continue
		
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		var current_type = street_types.get(edge_key, 1)
		
		# Solo expandir sobre calles del tipo base (no túneles u otros tipos)
		if current_type != base_street_type:
			continue
		
		var other_pos = plain_graph.points[other_node]
		var edge_direction = (other_pos - current_pos).normalized()
		
		# Calcular el ángulo entre la dirección previa y la nueva
		var dot_product = previous_direction.dot(edge_direction)
		dot_product = clamp(dot_product, -1.0, 1.0)
		var angle_radians = acos(dot_product)
		var angle_degrees = rad_to_deg(angle_radians)
		
		# Si el ángulo es mayor al threshold, no podemos continuar por este edge
		if angle_degrees > max_angle_degrees:
			continue
		
		# Score: preferir edges más rectos (menor ángulo)
		var score = dot_product  # Mayor dot = menor ángulo = mejor
		
		if score > best_score:
			best_score = score
			best_edge = edge
	
	# Si no encontramos un edge válido, terminar el túnel
	if best_edge.is_empty():
		return
	
	# Marcar el nuevo edge como túnel
	var edge_key = GraphGenerator._get_edge_key(best_edge[0], best_edge[1])
	street_types[edge_key] = tunnel_type
	
	# Continuar expandiendo
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

## Verifica si hay túneles (tipo 3 o 4) dentro de min_gap edges desde el edge dado
func _has_nearby_tunnels(node1: int, node2: int, min_gap: int) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [[node1, node2, 0]]  # [nodo_actual, nodo_previo, distancia]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_node = current[0]
		var previous_node = current[1]
		var distance = current[2]
		
		# Si llegamos al límite de distancia, no seguir expandiendo desde aquí
		if distance >= min_gap:
			continue
		
		# Marcar como visitado
		var visit_key = str(current_node) + "_" + str(previous_node)
		if visit_key in visited:
			continue
		visited[visit_key] = true
		
		var connected_edges = plain_graph.get_edges_for_node(current_node)
		
		for edge in connected_edges:
			var other_node = edge[1] if edge[0] == current_node else edge[0]
			
			var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
			var edge_type = street_types.get(edge_key, 1)
			
			# Si encontramos un túnel (tipo 3 o 4), retornar true
			if edge_type == 3 or edge_type == 4:
				return true
			
			# Continuar explorando si no es el nodo previo
			if other_node != previous_node:
				queue.append([other_node, current_node, distance + 1])
	
	return false

## Obtiene todas las calles de túnel (tipo 3 o 4)
func get_all_tunnels() -> Array:
	var result: Array = []
	
	for edge_key in street_types:
		var street_type = street_types[edge_key]
		if street_type == 3 or street_type == 4:
			result.append(edge_key)
	
	return result

## Verifica si un edge es un túnel
func is_tunnel(node1_idx: int, node2_idx: int) -> bool:
	var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
	var street_type = street_types.get(edge_key, 1)
	return street_type == 3 or street_type == 4

# ============================================
# GESTIÓN DE BARRIOS
# ============================================

## Inicializa el diccionario de barrios con -1 (sin asignar) para todas las caras
func _initialize_neighborhoods() -> void:
	neighborhoods.clear()
	for face_idx in range(plain_graph.faces.size()):
		neighborhoods[face_idx] = -1

## Asigna barrios a las caras del grafo mediante expansión desde semillas aleatorias
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

## Obtiene el barrio de una cara específica
func get_neighborhood_for_face(face_idx: int) -> int:
	if face_idx in neighborhoods:
		return neighborhoods[face_idx]
	return -1

## Obtiene todas las caras que pertenecen a un barrio específico
func get_faces_in_neighborhood(neighborhood_id: int) -> Array[int]:
	var faces_in_neighborhood: Array[int] = []
	
	for face_idx in neighborhoods:
		if neighborhoods[face_idx] == neighborhood_id:
			faces_in_neighborhood.append(face_idx)
	
	return faces_in_neighborhood
