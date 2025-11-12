class_name GraphCityGenerator
extends RefCounted

var plain_graph: GraphGenerator  
var neighborhoods: Dictionary = {}   # {face_idx: neighborhood_id} barrio de cada cara (-1 = sin asignar)
var street_types: Dictionary = {}    # {edge_key: tipo} tipo de cada calle (-1=límite, 0=pequeña, 1=mediana, 2=grande)

func generate_city_graph(
	smooth_steps: int = 0,
	region_size: Vector2 = Vector2(10, 10),
	min_distance: float = 5.3,
	rejection_samples: int = 30,
	generation_seed: int = 12345,
	num_neighborhoods: int = 3,
	num_large_streets: int = 6,
	num_small_streets: int = 10,
) -> void:
	seed(generation_seed)
	
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
	
	# Generar calles especiales
	_generate_large_streets(num_large_streets)
	_generate_small_streets(num_small_streets)
	
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
## Expande desde un nodo aleatorio en dos direcciones opuestas hasta los bordes
func _generate_street_path(street_type: int) -> void:
	if plain_graph.points.is_empty():
		return
	
	# 1. Elegir un nodo aleatorio como punto de partida
	var start_node = randi() % plain_graph.points.size()
	
	# 2. Obtener los edges conectados a este nodo
	var connected_edges = plain_graph.get_edges_for_node(start_node)
	
	if connected_edges.size() < 2:
		return  # No hay suficientes conexiones para expandir en dos direcciones
	
	# 3. Elegir dos edges iniciales en direcciones opuestas
	var initial_edges = plain_graph.select_opposite_edges(start_node, connected_edges)
	
	if initial_edges.size() != 2:
		return  # No se pudieron encontrar direcciones opuestas adecuadas
	
	# 4. Expandir en ambas direcciones
	for initial_edge in initial_edges:
		_expand_street_direction(initial_edge, start_node, street_type)

## Expande una calle en una dirección hasta llegar a un borde
func _expand_street_direction(initial_edge: Array, start_node: int, street_type: int) -> void:
	var current_edge = initial_edge
	var current_node = initial_edge[1] if initial_edge[0] == start_node else initial_edge[0]
	var previous_node = start_node
	
	var max_iterations = 100  # Límite de seguridad
	var iterations = 0
	
	# Marcar el edge inicial (solo si no es límite)
	var edge_key = GraphGenerator._get_edge_key(current_edge[0], current_edge[1])
	var current_type = street_types.get(edge_key, 1)
	if current_type != -1:  # No sobrescribir calles límite
		street_types[edge_key] = street_type
	
	while iterations < max_iterations:
		iterations += 1
		
		# Verificar si llegamos a un nodo límite
		var current_node_type = plain_graph.node_types.get(current_node, 0)
		if current_node_type == 1:
			break  # Llegamos a un nodo límite
		
		# Obtener el siguiente edge en la dirección actual
		var next_edge = plain_graph.get_next_edge_in_direction(
			current_node, 
			previous_node, 
			street_types,
			street_type
		)
		
		if next_edge.is_empty():
			break  # No hay más camino válido
		
		# Marcar el nuevo edge (solo si no es límite)
		edge_key = GraphGenerator._get_edge_key(next_edge[0], next_edge[1])
		current_type = street_types.get(edge_key, 1)
		if current_type != -1:  # No sobrescribir calles límite
			street_types[edge_key] = street_type
		
		# Avanzar al siguiente nodo
		previous_node = current_node
		current_node = next_edge[1] if next_edge[0] == current_node else next_edge[0]
		current_edge = next_edge
		
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
