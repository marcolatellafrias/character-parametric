class_name NeighborhoodManager
extends RefCounted

var neighborhoods: Array[Neighborhood] = []
var face_to_neighborhood: Dictionary = {}  # face_idx -> Neighborhood
var face_distances: Dictionary = {}  # face_idx -> float (0.0 - 1.0)

var graph: GraphGenerator
var num_neighborhoods: int
var base_seed: int

func _init(p_graph: GraphGenerator, p_num_neighborhoods: int, p_seed: int) -> void:
	graph = p_graph
	num_neighborhoods = p_num_neighborhoods
	base_seed = p_seed

func generate_neighborhoods() -> void:
	_create_neighborhood_instances()
	_assign_neighborhoods_to_faces()
	_normalize_distances()
	_print_stats()

func _create_neighborhood_instances() -> void:
	neighborhoods.clear()
	
	var num_types = 4  # Shanty Town, Rich Residential, Industrial, Downtown
	
	for i in range(num_neighborhoods):
		var type = (i % num_types) as Neighborhood.Type
		var neighborhood_seed = base_seed + i
		
		# Neighborhood ya aplica su configuración por defecto en _init
		var neighborhood = Neighborhood.new(type, neighborhood_seed, i)
		
		neighborhoods.append(neighborhood)

func _assign_neighborhoods_to_faces() -> void:
	var total_faces = graph.faces.size()
	if total_faces == 0:
		push_warning("[NeighborhoodManager] No hay faces en el grafo")
		return
	
	if num_neighborhoods > total_faces:
		push_warning("[NeighborhoodManager] Más barrios (%d) que manzanas (%d), ajustando" % [num_neighborhoods, total_faces])
		num_neighborhoods = total_faces
	
	# Inicializar
	face_to_neighborhood.clear()
	face_distances.clear()
	
	for face_idx in range(total_faces):
		face_distances[face_idx] = 999999
	
	# Seleccionar semillas aleatorias
	var rng = RandomNumberGenerator.new()
	rng.seed = base_seed
	
	var available_faces = range(total_faces)
	available_faces.shuffle()
	
	# Asignar semillas y crear frentes de expansión
	var expansion_fronts: Array = []
	
	for i in range(num_neighborhoods):
		var seed_face = available_faces[i]
		var neighborhood = neighborhoods[i]
		
		neighborhood.seed_face_idx = seed_face
		neighborhood.add_face(seed_face)
		face_to_neighborhood[seed_face] = neighborhood
		face_distances[seed_face] = 0
		
		var queue: Array = [[seed_face, 0]]
		expansion_fronts.append(queue)
	
	# Expansión BFS simultánea
	var active_fronts = true
	
	while active_fronts:
		active_fronts = false
		
		for i in range(num_neighborhoods):
			var queue = expansion_fronts[i]
			
			if queue.is_empty():
				continue
			
			active_fronts = true
			var current_front_size = queue.size()
			
			for j in range(current_front_size):
				var current_data = queue.pop_front()
				var current_face = current_data[0]
				var current_distance = current_data[1]
				
				var adjacent_faces = graph.get_adjacent_faces(current_face)
				
				for adj_face in adjacent_faces:
					if adj_face not in face_to_neighborhood:
						var neighborhood = neighborhoods[i]
						neighborhood.add_face(adj_face)
						face_to_neighborhood[adj_face] = neighborhood
						face_distances[adj_face] = current_distance + 1
						queue.append([adj_face, current_distance + 1])

func _normalize_distances() -> void:
	var max_distance = 0
	
	for face_idx in face_distances:
		if face_distances[face_idx] > max_distance and face_distances[face_idx] < 999999:
			max_distance = face_distances[face_idx]
	
	if max_distance > 0:
		for face_idx in face_distances:
			if face_distances[face_idx] < 999999:
				face_distances[face_idx] = float(face_distances[face_idx]) / float(max_distance)
			else:
				face_distances[face_idx] = 1.0

func _print_stats() -> void:
	print("[NeighborhoodManager] Generación completada:")
	print("  Total de barrios: %d" % num_neighborhoods)
	
	var type_counts = {
		Neighborhood.Type.SHANTY_TOWN: 0,
		Neighborhood.Type.RICH_RESIDENTIAL: 0,
		Neighborhood.Type.INDUSTRIAL: 0,
		Neighborhood.Type.DOWNTOWN: 0
	}
	
	for neighborhood in neighborhoods:
		type_counts[neighborhood.type] += 1
		print("  Barrio %d (%s): %d manzanas, tránsito: %.2f (seed: %d)" % [
			neighborhood.index,
			neighborhood.get_type_name(),
			neighborhood.get_face_count(),
			neighborhood.traffic_density,
			neighborhood.seed
		])
	
	print("  Distribución por tipo:")
	print("    Shanty Town: %d barrios" % type_counts[Neighborhood.Type.SHANTY_TOWN])
	print("    Rich Residential: %d barrios" % type_counts[Neighborhood.Type.RICH_RESIDENTIAL])
	print("    Industrial: %d barrios" % type_counts[Neighborhood.Type.INDUSTRIAL])
	print("    Downtown: %d barrios" % type_counts[Neighborhood.Type.DOWNTOWN])

# ============================================
# GETTERS
# ============================================

func get_neighborhood_for_face(face_idx: int) -> Neighborhood:
	return face_to_neighborhood.get(face_idx, null)

func get_distance_for_face(face_idx: int) -> float:
	return face_distances.get(face_idx, 1.0)

func get_neighborhoods() -> Array[Neighborhood]:
	return neighborhoods

func get_neighborhoods_by_type(type: Neighborhood.Type) -> Array[Neighborhood]:
	var result: Array[Neighborhood] = []
	
	for neighborhood in neighborhoods:
		if neighborhood.type == type:
			result.append(neighborhood)
	
	return result
