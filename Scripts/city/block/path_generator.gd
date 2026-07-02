class_name PathGenerator extends RefCounted

# Referencia a la grilla
var grid: DistortedGrid

# Edges de los callejones - AHORA SOLO UNA CONFIGURACIÓN PARA TODOS LOS PISOS
var path_edges: Dictionary = {}  # edge_key: type

# Parámetros para generar callejones internos
var small_alleyways_count: int
var big_alleyways_count: int
var min_steps_before_turn: int
var straight_probability: float
var rng: RandomNumberGenerator

var total_floors: int = 0

# Flag para verificar que generate() fue llamado
var is_generated: bool = false


func _init(
	p_grid: DistortedGrid,
	p_small_alleyways_count: int = 2,
	p_big_alleyways_count: int = 1,
	p_min_steps_before_turn: int = 2,
	p_seed: int = -1,
	p_straight_probability: float = 0.5,
	p_total_floors: int = 1
) -> void:
	grid = p_grid
	small_alleyways_count = p_small_alleyways_count
	big_alleyways_count = p_big_alleyways_count
	min_steps_before_turn = p_min_steps_before_turn
	straight_probability = p_straight_probability
	total_floors = p_total_floors
	
	rng = RandomNumberGenerator.new()
	if p_seed == -1:
		rng.randomize()
	else:
		rng.seed = p_seed


func generate() -> void:
	_generate_alleyways()
	
	is_generated = true


func _generate_alleyways() -> void:
	var small_seeds: Array = []
	var big_seeds: Array = []
	for i in range(small_alleyways_count):
		var seed = _get_random_seed_edge(DistortedGrid.CellType.SMALL, small_seeds)
		if not seed.is_empty():
			small_seeds.append(seed)
			_add_path_edge_vertices(seed[0], seed[1], DistortedGrid.CellType.SMALL_ORIGIN)
	
	# Generar seed edges de BIG
	for i in range(big_alleyways_count):
		var seed = _get_random_seed_edge(DistortedGrid.CellType.BIG, big_seeds)
		if not seed.is_empty():
			big_seeds.append(seed)
			_add_path_edge_vertices(seed[0], seed[1], DistortedGrid.CellType.BIG_ORIGIN)
	
	# Expandir SMALL alleyways
	for i in range(small_seeds.size()):
		_expand_alleyway(small_seeds[i], DistortedGrid.CellType.SMALL)
	
	# Expandir BIG alleyways
	for i in range(big_seeds.size()):
		_expand_alleyway(big_seeds[i], DistortedGrid.CellType.BIG)


func _get_random_seed_edge(alleyway_type: int, existing_seeds: Array) -> Array:
	var valid_edges: Array = []
	
	# Edges horizontales
	for z in range(1, grid.rows):
		for x in range(1, grid.columns - 1):
			var v1 = Vector2i(x, z)
			var v2 = Vector2i(x + 1, z)
			
			if _is_seed_too_close_to_others(v1, v2, existing_seeds):
				continue
			
			valid_edges.append([v1, v2, "horizontal"])
	
	# Edges verticales
	for z in range(1, grid.rows - 1):
		for x in range(1, grid.columns):
			var v1 = Vector2i(x, z)
			var v2 = Vector2i(x, z + 1)
			
			if _is_seed_too_close_to_others(v1, v2, existing_seeds):
				continue
			
			valid_edges.append([v1, v2, "vertical"])
	
	if valid_edges.is_empty():
		return []
	
	return valid_edges[rng.randi_range(0, valid_edges.size() - 1)]


func _is_seed_too_close_to_others(v1: Vector2i, v2: Vector2i, existing_seeds: Array) -> bool:
	for seed in existing_seeds:
		var seed_v1: Vector2i = seed[0]
		var seed_v2: Vector2i = seed[1]
		
		var dist_v1_to_seed_v1 = abs(v1.x - seed_v1.x) + abs(v1.y - seed_v1.y)
		var dist_v1_to_seed_v2 = abs(v1.x - seed_v2.x) + abs(v1.y - seed_v2.y)
		var dist_v2_to_seed_v1 = abs(v2.x - seed_v1.x) + abs(v2.y - seed_v1.y)
		var dist_v2_to_seed_v2 = abs(v2.x - seed_v2.x) + abs(v2.y - seed_v2.y)
		
		if dist_v1_to_seed_v1 <= 1 or dist_v1_to_seed_v2 <= 1 or \
		   dist_v2_to_seed_v1 <= 1 or dist_v2_to_seed_v2 <= 1:
			return true
	
	return false


func _expand_alleyway(seed: Array, alleyway_type: int) -> void:
	var v1 = seed[0]
	var v2 = seed[1]
	var direction = seed[2]
	
	# Determinar boundaries y direcciones prohibidas
	var forbidden_boundaries: Array[String] = []
	var target_boundary_v1: String
	var target_boundary_v2: String
	var forbidden_direction_v1: Vector2i
	var forbidden_direction_v2: Vector2i
	
	if direction == "horizontal":
		forbidden_boundaries = ["north", "south"]
		target_boundary_v1 = "west"
		target_boundary_v2 = "east"
		forbidden_direction_v1 = Vector2i(1, 0)
		forbidden_direction_v2 = Vector2i(-1, 0)
	else:
		forbidden_boundaries = ["west", "east"]
		target_boundary_v1 = "north"
		target_boundary_v2 = "south"
		forbidden_direction_v1 = Vector2i(0, 1)
		forbidden_direction_v2 = Vector2i(0, -1)
	
	# Vértices visitados
	var visited_vertices: Dictionary = {}
	visited_vertices[_get_vertex_key(v1)] = true
	visited_vertices[_get_vertex_key(v2)] = true
	
	# Expandir lado v1
	_expand_side(v1, v2, target_boundary_v1, forbidden_boundaries, forbidden_direction_v1, 
				 alleyway_type, visited_vertices)
	
	# Expandir lado v2
	_expand_side(v2, v1, target_boundary_v2, forbidden_boundaries, forbidden_direction_v2, 
				 alleyway_type, visited_vertices)


func _expand_side(
	start: Vector2i,
	previous: Vector2i,
	target_boundary: String,
	forbidden_boundaries: Array[String],
	forbidden_direction: Vector2i,
	alleyway_type: int,
	visited_vertices: Dictionary
) -> void:
	var current = start
	var prev = previous
	var steps_in_current_direction = 0
	var current_direction = _get_direction_to_boundary_vec(target_boundary)
	
	while not _is_vertex_on_boundary(current, target_boundary):
		var result = _get_next_vertex_with_turn_ratio(
			current, prev, alleyway_type, target_boundary,
			forbidden_boundaries, forbidden_direction,
			visited_vertices, steps_in_current_direction, current_direction
		)
		
		if result["vertex"] == Vector2i(-1, -1):
			break
		
		var next_v = result["vertex"]
		var new_direction = next_v - current
		var is_direction_change = new_direction != current_direction
		
		# Verificar si next_v ya es parte de un path del mismo tipo ANTES de visitarlo
		var is_merge = _is_vertex_in_same_type_path(next_v, alleyway_type, visited_vertices)
		
		# Agregar el edge de conexión
		_add_path_edge_vertices(current, next_v, alleyway_type)
		visited_vertices[_get_vertex_key(next_v)] = true
		
		# Si era un merge, detener después de crear el edge de conexión
		if is_merge:
			break
		
		prev = current
		current = next_v
		
		if is_direction_change:
			current_direction = new_direction
			steps_in_current_direction = 1
		else:
			steps_in_current_direction += 1


func _get_next_vertex_with_turn_ratio(
	current: Vector2i,
	previous: Vector2i,
	alleyway_type: int,
	target_boundary: String,
	forbidden_boundaries: Array[String],
	forbidden_direction: Vector2i,
	visited_vertices: Dictionary,
	steps_in_current_direction: int,
	current_direction: Vector2i
) -> Dictionary:
	# Dirección hacia el boundary destino
	var target_dir = _get_direction_to_boundary_vec(target_boundary)
	
	# Direcciones perpendiculares al target
	var perp_dirs: Array[Vector2i] = []
	if target_dir.x == 0:  # Target es vertical
		perp_dirs = [Vector2i(-1, 0), Vector2i(1, 0)]
	else:  # Target es horizontal
		perp_dirs = [Vector2i(0, -1), Vector2i(0, 1)]
	
	# Verificar si debe mantener la dirección actual (no ha cumplido min_steps_before_turn)
	var must_continue_straight = steps_in_current_direction < min_steps_before_turn
	
	if must_continue_straight:
		# Debe seguir en la dirección actual
		var straight_option = current + current_direction
		if _is_move_valid(current, straight_option, alleyway_type, 
						  forbidden_boundaries, visited_vertices,
						  current_direction, target_dir):
			return {"vertex": straight_option, "is_turn": false}
		else:
			# No puede seguir recto pero debe hacerlo - sin opciones
			return {"vertex": Vector2i(-1, -1), "is_turn": false}
	
	# Ya cumplió min_steps_before_turn, puede cambiar de dirección
	
	# Determinar qué direcciones son consideradas "giros"
	var is_going_toward_target = current_direction == target_dir
	var possible_directions: Array = []
	
	if is_going_toward_target:
		# Actualmente yendo hacia el target, puede:
		# 1. Seguir hacia el target (straight_probability%)
		# 2. Girar a perpendiculares (1 - straight_probability%)
		
		# Evaluar seguir recto
		var straight_option = current + target_dir
		var can_go_straight = _is_move_valid(current, straight_option, alleyway_type, 
											  forbidden_boundaries, visited_vertices,
											  target_dir, target_dir)
		
		# Evaluar perpendiculares con lookup
		var valid_perp_dirs: Array = []
		for perp_dir in perp_dirs:
			var perp_option = current + perp_dir
			if _is_move_valid(current, perp_option, alleyway_type, 
							  forbidden_boundaries, visited_vertices,
							  perp_dir, target_dir):
				if _is_perpendicular_turn_viable(perp_option, perp_dir, target_dir, 
												 forbidden_boundaries, visited_vertices):
					valid_perp_dirs.append(perp_dir)
		
		# Decidir con probabilidades
		if can_go_straight and valid_perp_dirs.is_empty():
			return {"vertex": straight_option, "is_turn": false}
		elif not can_go_straight and not valid_perp_dirs.is_empty():
			var chosen_dir = valid_perp_dirs[rng.randi_range(0, valid_perp_dirs.size() - 1)]
			return {"vertex": current + chosen_dir, "is_turn": true}
		elif can_go_straight and not valid_perp_dirs.is_empty():
			if rng.randf() < straight_probability:
				return {"vertex": straight_option, "is_turn": false}
			else:
				var chosen_dir = valid_perp_dirs[rng.randi_range(0, valid_perp_dirs.size() - 1)]
				return {"vertex": current + chosen_dir, "is_turn": true}
	else:
		# Actualmente en dirección perpendicular, puede:
		# 1. Seguir en perpendicular
		# 2. Girar hacia el target
		# 3. Girar a la otra perpendicular
		
		# Evaluar seguir en la misma perpendicular
		var straight_option = current + current_direction
		var can_go_straight = _is_move_valid(current, straight_option, alleyway_type, 
											  forbidden_boundaries, visited_vertices,
											  current_direction, target_dir)
		if can_go_straight:
			possible_directions.append({"dir": current_direction, "is_turn": false})
		
		# Evaluar girar hacia el target
		var toward_target_option = current + target_dir
		if _is_move_valid(current, toward_target_option, alleyway_type, 
						  forbidden_boundaries, visited_vertices,
						  target_dir, target_dir):
			possible_directions.append({"dir": target_dir, "is_turn": true})
		
		# Evaluar girar a la otra perpendicular con lookup
		for perp_dir in perp_dirs:
			if perp_dir == current_direction:
				continue  # Ya evaluado
			var perp_option = current + perp_dir
			if _is_move_valid(current, perp_option, alleyway_type, 
							  forbidden_boundaries, visited_vertices,
							  perp_dir, target_dir):
				if _is_perpendicular_turn_viable(perp_option, perp_dir, target_dir, 
												 forbidden_boundaries, visited_vertices):
					possible_directions.append({"dir": perp_dir, "is_turn": true})
		
		# Elegir aleatoriamente entre las opciones válidas
		if not possible_directions.is_empty():
			var chosen = possible_directions[rng.randi_range(0, possible_directions.size() - 1)]
			return {"vertex": current + chosen["dir"], "is_turn": chosen["is_turn"]}
	
	# Sin opciones válidas
	return {"vertex": Vector2i(-1, -1), "is_turn": false}


func _is_move_valid(
	from: Vector2i,
	to: Vector2i,
	alleyway_type: int,
	forbidden_boundaries: Array[String],
	visited_vertices: Dictionary,
	current_direction: Vector2i = Vector2i.ZERO,
	target_direction: Vector2i = Vector2i.ZERO
) -> bool:
	# Verificar límites de grilla
	if to.x < 0 or to.x > grid.columns or to.y < 0 or to.y > grid.rows:
		return false
	
	# No revisitar vértices de este mismo alleyway
	if _get_vertex_key(to) in visited_vertices:
		return false
	
	# No acercarse a boundaries prohibidos
	if _is_vertex_on_forbidden_boundary(to, forbidden_boundaries):
		return false
	
	# Verificar que el edge puede ser agregado
	if not _can_add_edge_vertices(from, to, alleyway_type):
		return false
	
	return true


func _is_vertex_in_same_type_path(vertex: Vector2i, alleyway_type: int, visited_vertices: Dictionary) -> bool:
	# Verificar si el vértice ya es parte de un path del mismo tipo
	# (excluyendo los vértices ya visitados en esta expansión)
	
	for edge_key in path_edges:
		var existing_type = path_edges[edge_key]
		
		# Solo verificar edges del mismo tipo
		if not _is_same_alleyway_type(alleyway_type, existing_type):
			continue
		
		# Parsear el edge_key
		var parts = edge_key.split("_")
		var e_v1 = Vector2i(int(parts[0]), int(parts[1]))
		var e_v2 = Vector2i(int(parts[2]), int(parts[3]))
		
		# Si el vértice es parte de este edge Y no está en visited (no es del mismo alleyway actual)
		if (vertex == e_v1 or vertex == e_v2) and not (_get_vertex_key(vertex) in visited_vertices):
			return true
	
	return false


func _is_same_alleyway_type(type1: int, type2: int) -> bool:
	# SMALL y SMALL_ORIGIN son del mismo tipo
	if (type1 == DistortedGrid.CellType.SMALL or type1 == DistortedGrid.CellType.SMALL_ORIGIN) and \
	   (type2 == DistortedGrid.CellType.SMALL or type2 == DistortedGrid.CellType.SMALL_ORIGIN):
		return true
	
	# BIG y BIG_ORIGIN son del mismo tipo
	if (type1 == DistortedGrid.CellType.BIG or type1 == DistortedGrid.CellType.BIG_ORIGIN) and \
	   (type2 == DistortedGrid.CellType.BIG or type2 == DistortedGrid.CellType.BIG_ORIGIN):
		return true
	
	return false


func _is_perpendicular_turn_viable(
	start_pos: Vector2i,
	perp_direction: Vector2i,
	target_direction: Vector2i,
	forbidden_boundaries: Array[String],
	visited_vertices: Dictionary
) -> bool:
	# Simular min_steps_before_turn pasos en la dirección perpendicular
	var current_pos = start_pos
	
	for step in range(min_steps_before_turn):
		current_pos = current_pos + perp_direction
		
		# Verificar límites
		if current_pos.x < 0 or current_pos.x > grid.columns or \
		   current_pos.y < 0 or current_pos.y > grid.rows:
			return false
		
		# Verificar si se acerca a boundary prohibido
		if _is_vertex_on_forbidden_boundary(current_pos, forbidden_boundaries):
			return false
		
		# Verificar si el siguiente paso hacia el target también es válido
		# (necesario para poder retomar la dirección correcta después del turn)
		var next_toward_target = current_pos + target_direction
		if next_toward_target.x < 0 or next_toward_target.x > grid.columns or \
		   next_toward_target.y < 0 or next_toward_target.y > grid.rows:
			return false
		
		if _is_vertex_on_forbidden_boundary(next_toward_target, forbidden_boundaries):
			return false
	
	return true


func _is_vertex_on_boundary(vertex: Vector2i, boundary: String) -> bool:
	match boundary:
		"north":
			return vertex.y == 0
		"south":
			return vertex.y == grid.rows
		"west":
			return vertex.x == 0
		"east":
			return vertex.x == grid.columns
		_:
			return false


func _is_vertex_on_forbidden_boundary(vertex: Vector2i, forbidden_boundaries: Array[String]) -> bool:
	if vertex.y == 0 and "north" in forbidden_boundaries:
		return true
	if vertex.y == grid.rows and "south" in forbidden_boundaries:
		return true
	if vertex.x == 0 and "west" in forbidden_boundaries:
		return true
	if vertex.x == grid.columns and "east" in forbidden_boundaries:
		return true
	return false


func _get_direction_to_boundary_vec(boundary: String) -> Vector2i:
	match boundary:
		"north":
			return Vector2i(0, -1)
		"south":
			return Vector2i(0, 1)
		"west":
			return Vector2i(-1, 0)
		"east":
			return Vector2i(1, 0)
		_:
			return Vector2i.ZERO


func _can_add_edge_vertices(v1: Vector2i, v2: Vector2i, alleyway_type: int) -> bool:
	var edge_key = _get_edge_key(v1, v2)
	
	if not edge_key in path_edges:
		return true
	
	var existing_type = path_edges[edge_key]
	
	if alleyway_type == DistortedGrid.CellType.BIG and (existing_type == DistortedGrid.CellType.SMALL or existing_type == DistortedGrid.CellType.SMALL_ORIGIN):
		return true
	
	return false


func _add_path_edge_vertices(v1: Vector2i, v2: Vector2i, alleyway_type: int) -> void:
	var edge_key = _get_edge_key(v1, v2)
	
	if not edge_key in path_edges or alleyway_type == DistortedGrid.CellType.BIG or alleyway_type == DistortedGrid.CellType.BIG_ORIGIN:
		path_edges[edge_key] = alleyway_type


func _get_edge_key(v1: Vector2i, v2: Vector2i) -> String:
	var min_x = min(v1.x, v2.x)
	var min_z = min(v1.y, v2.y)
	var max_x = max(v1.x, v2.x)
	var max_z = max(v1.y, v2.y)
	return "%d_%d_%d_%d" % [min_x, min_z, max_x, max_z]


func _get_vertex_key(vertex: Vector2i) -> String:
	return "%d_%d" % [vertex.x, vertex.y]


# Método simplificado - ya no recibe parámetro floor
func get_path_edge_type_vertices(v1_x: int, v1_z: int, v2_x: int, v2_z: int, floor: int = 0) -> int:
	# Ignorar el parámetro floor - todos los pisos usan la misma configuración
	var edge_key = _get_edge_key(Vector2i(v1_x, v1_z), Vector2i(v2_x, v2_z))
	return path_edges.get(edge_key, DistortedGrid.CellType.NORMAL)
