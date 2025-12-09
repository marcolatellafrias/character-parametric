class_name DistortedGrid extends RefCounted

# Tipos de celdas
enum CellType {
	NORMAL = 0,
	SMALL = 1,
	BIG = 2,
	BOUNDARY = -1,
	SMALL_ORIGIN = 10,
	BIG_ORIGIN = 11
}

# Estructura de la grilla
var rows: int
var columns: int
var cell_height: float

# Geometría del bloque (core block)
var vertices: Array[Vector2]  # [BL, BR, TR, TL]

# Parámetros de distorsión
var wave_amplitude_x: float
var wave_amplitude_z: float
var wave_frequency_x: float
var wave_frequency_z: float
var wave_phase_x: float
var wave_phase_z: float
var edge_falloff_sharpness: float

# Tipos de bordes [north, east, south, west]
var edge_types: Array[int]

# Grilla 2D: [x][z] -> int (tipo de celda)
var grid: Array = []

# Posiciones distorsionadas de cada celda
var cell_positions: Array = []  # [z][x] -> Vector3

# Edges de los callejones
var path_edges: Dictionary = {}

# Parámetros para generar callejones internos
var small_alleyways_count: int
var big_alleyways_count: int
var min_steps_before_turn: int  # Turn ratio
var rng: RandomNumberGenerator


func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_cell_height: float,
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
	p_seed: int = -1
) -> void:
	rows = p_rows
	columns = p_columns
	vertices = p_vertices
	cell_height = p_cell_height
	small_alleyways_count = p_small_alleyways_count
	big_alleyways_count = p_big_alleyways_count
	min_steps_before_turn = p_min_steps_before_turn
	
	# Inicializar RNG
	rng = RandomNumberGenerator.new()
	if p_seed == -1:
		rng.randomize()
	else:
		rng.seed = p_seed
	
	# Calcular el tamaño característico del quad irregular
	var bottom_width = (vertices[1] - vertices[0]).length()
	var top_width = (vertices[2] - vertices[3]).length()
	var left_height = (vertices[3] - vertices[0]).length()
	var right_height = (vertices[2] - vertices[1]).length()
	
	var avg_width = (bottom_width + top_width) / 2.0
	var avg_height = (left_height + right_height) / 2.0
	
	# Normalizar amplitudes según las dimensiones del quad
	wave_amplitude_x = p_wave_amplitude_x * avg_width
	wave_amplitude_z = p_wave_amplitude_z * avg_height
	wave_frequency_x = p_wave_frequency_x
	wave_frequency_z = p_wave_frequency_z
	wave_phase_x = p_wave_phase_x
	wave_phase_z = p_wave_phase_z
	edge_falloff_sharpness = p_edge_falloff_sharpness
	
	# Todos los bordes exteriores son boundary
	edge_types = [-1, -1, -1, -1]
	
	_initialize_grid()
	_generate_internal_alleyways()
	_calculate_distorted_positions()


func _initialize_grid() -> void:
	grid.clear()
	
	for x in range(columns):
		var grid_x = []
		for z in range(rows):
			grid_x.append(CellType.NORMAL)
		grid.append(grid_x)


func _generate_internal_alleyways() -> void:
	path_edges.clear()
	
	print("\n=== GENERANDO ALLEYWAYS ===")
	print("Grilla: %dx%d (columns x rows)" % [columns, rows])
	print("Turn ratio: %d pasos mínimos antes de girar" % min_steps_before_turn)
	
	# Array de seed edges para cada tipo
	var small_seeds: Array = []
	var big_seeds: Array = []
	
	# Generar todos los seed edges de SMALL
	print("\n--- Generando %d SEED EDGES de SMALL ---" % small_alleyways_count)
	for i in range(small_alleyways_count):
		var seed = _get_random_seed_edge(CellType.SMALL, small_seeds)
		if not seed.is_empty():
			small_seeds.append(seed)
			var origin_type = CellType.SMALL_ORIGIN
			_add_path_edge_vertices(seed[0], seed[1], origin_type)
			print("  SMALL seed %d: v1=%s, v2=%s, dir=%s" % [i + 1, seed[0], seed[1], seed[2]])
		else:
			print("  ✗ No se pudo encontrar seed válido para SMALL %d" % (i + 1))
	
	# Generar todos los seed edges de BIG
	print("\n--- Generando %d SEED EDGES de BIG ---" % big_alleyways_count)
	for i in range(big_alleyways_count):
		var seed = _get_random_seed_edge(CellType.BIG, big_seeds)
		if not seed.is_empty():
			big_seeds.append(seed)
			var origin_type = CellType.BIG_ORIGIN
			_add_path_edge_vertices(seed[0], seed[1], origin_type)
			print("  BIG seed %d: v1=%s, v2=%s, dir=%s" % [i + 1, seed[0], seed[1], seed[2]])
		else:
			print("  ✗ No se pudo encontrar seed válido para BIG %d" % (i + 1))
	
	# Expandir todos los SMALL seeds
	print("\n--- Expandiendo SMALL alleyways ---")
	for i in range(small_seeds.size()):
		print("\n=== SMALL ALLEYWAY %d ===" % (i + 1))
		_expand_alleyway(small_seeds[i], CellType.SMALL)
	
	# Expandir todos los BIG seeds
	print("\n--- Expandiendo BIG alleyways ---")
	for i in range(big_seeds.size()):
		print("\n=== BIG ALLEYWAY %d ===" % (i + 1))
		_expand_alleyway(big_seeds[i], CellType.BIG)


func _get_random_seed_edge(alleyway_type: int, existing_seeds: Array) -> Array:
	var valid_edges: Array = []
	
	# Edges horizontales
	for z in range(1, rows):
		for x in range(1, columns - 1):
			var v1 = Vector2i(x, z)
			var v2 = Vector2i(x + 1, z)
			
			if _is_seed_too_close_to_others(v1, v2, existing_seeds):
				continue
			
			valid_edges.append([v1, v2, "horizontal"])
	
	# Edges verticales
	for z in range(1, rows - 1):
		for x in range(1, columns):
			var v1 = Vector2i(x, z)
			var v2 = Vector2i(x, z + 1)
			
			if _is_seed_too_close_to_others(v1, v2, existing_seeds):
				continue
			
			valid_edges.append([v1, v2, "vertical"])
	
	if valid_edges.is_empty():
		print("    No hay seed edges válidos disponibles")
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
	
	print("Expandiendo seed: v1=%s, v2=%s, dirección=%s" % [v1, v2, direction])
	
	# Determinar boundaries y direcciones prohibidas
	var forbidden_boundaries: Array[String] = []
	var target_boundary_v1: String = ""
	var target_boundary_v2: String = ""
	var forbidden_direction_v1: Vector2i
	var forbidden_direction_v2: Vector2i
	
	if direction == "horizontal":
		forbidden_boundaries = ["north", "south"]
		target_boundary_v1 = "west"
		target_boundary_v2 = "east"
		forbidden_direction_v1 = Vector2i(1, 0)
		forbidden_direction_v2 = Vector2i(-1, 0)
		print("Edge horizontal → v1 hacia WEST, v2 hacia EAST, prohibido: north/south")
	else:
		forbidden_boundaries = ["west", "east"]
		target_boundary_v1 = "north"
		target_boundary_v2 = "south"
		forbidden_direction_v1 = Vector2i(0, 1)
		forbidden_direction_v2 = Vector2i(0, -1)
		print("Edge vertical → v1 hacia NORTH, v2 hacia SOUTH, prohibido: west/east")
	
	# Set de vértices visitados para este alleyway
	var visited_vertices: Dictionary = {}
	visited_vertices[_get_vertex_key(v1)] = true
	visited_vertices[_get_vertex_key(v2)] = true
	
	# Estados de expansión para ambos lados
	var current_v1 = v1
	var previous_v1 = v2
	var active_v1 = true
	var steps_in_current_direction_v1 = 0  # Contador de pasos en dirección actual
	
	var current_v2 = v2
	var previous_v2 = v1
	var active_v2 = true
	var steps_in_current_direction_v2 = 0  # Contador de pasos en dirección actual
	
	var max_iterations = rows + columns
	var iteration = 0
	
	print("\n=== Expansión alternada ===")
	
	# Expandir alternadamente
	while (active_v1 or active_v2) and iteration < max_iterations:
		iteration += 1
		
		# Expandir desde v1
		if active_v1:
			print("\n[Iter %d] Lado v1: expandiendo desde %s (pasos en dir actual: %d)" % [
				iteration, current_v1, steps_in_current_direction_v1
			])
			
			if _is_vertex_on_boundary(current_v1, target_boundary_v1):
				print("  v1 llegó a boundary %s" % target_boundary_v1)
				active_v1 = false
			else:
				var result = _get_next_vertex_with_turn_ratio(
					current_v1,
					previous_v1,
					alleyway_type,
					target_boundary_v1,
					forbidden_boundaries,
					forbidden_direction_v1,
					visited_vertices,
					steps_in_current_direction_v1
				)
				
				if result["vertex"] == Vector2i(-1, -1):
					print("  v1 no tiene más opciones válidas")
					active_v1 = false
				else:
					var next_v1 = result["vertex"]
					var is_turn = result["is_turn"]
					
					print("  v1: %s → %s (%s)" % [current_v1, next_v1, "TURN" if is_turn else "STRAIGHT"])
					visited_vertices[_get_vertex_key(next_v1)] = true
					_add_path_edge_vertices(current_v1, next_v1, alleyway_type)
					previous_v1 = current_v1
					current_v1 = next_v1
					
					# Actualizar contador de pasos
					if is_turn:
						steps_in_current_direction_v1 = 1  # Reiniciar contador
					else:
						steps_in_current_direction_v1 += 1
		
		# Expandir desde v2
		if active_v2:
			print("\n[Iter %d] Lado v2: expandiendo desde %s (pasos en dir actual: %d)" % [
				iteration, current_v2, steps_in_current_direction_v2
			])
			
			if _is_vertex_on_boundary(current_v2, target_boundary_v2):
				print("  v2 llegó a boundary %s" % target_boundary_v2)
				active_v2 = false
			else:
				var result = _get_next_vertex_with_turn_ratio(
					current_v2,
					previous_v2,
					alleyway_type,
					target_boundary_v2,
					forbidden_boundaries,
					forbidden_direction_v2,
					visited_vertices,
					steps_in_current_direction_v2
				)
				
				if result["vertex"] == Vector2i(-1, -1):
					print("  v2 no tiene más opciones válidas")
					active_v2 = false
				else:
					var next_v2 = result["vertex"]
					var is_turn = result["is_turn"]
					
					print("  v2: %s → %s (%s)" % [current_v2, next_v2, "TURN" if is_turn else "STRAIGHT"])
					visited_vertices[_get_vertex_key(next_v2)] = true
					_add_path_edge_vertices(current_v2, next_v2, alleyway_type)
					previous_v2 = current_v2
					current_v2 = next_v2
					
					# Actualizar contador de pasos
					if is_turn:
						steps_in_current_direction_v2 = 1  # Reiniciar contador
					else:
						steps_in_current_direction_v2 += 1
	
	print("\n=== Expansión completada en %d iteraciones ===" % iteration)


func _get_direction_to_boundary(boundary: String) -> Vector2:
	match boundary:
		"north":
			return Vector2(0, -1)
		"south":
			return Vector2(0, 1)
		"west":
			return Vector2(-1, 0)
		"east":
			return Vector2(1, 0)
		_:
			return Vector2.ZERO


func _is_vertex_on_boundary(vertex: Vector2i, boundary: String) -> bool:
	match boundary:
		"north":
			return vertex.y == 0
		"south":
			return vertex.y == rows
		"west":
			return vertex.x == 0
		"east":
			return vertex.x == columns
		_:
			return false


func _get_next_vertex_with_turn_ratio(
	current: Vector2i,
	previous: Vector2i,
	alleyway_type: int,
	target_boundary: String,
	forbidden_boundaries: Array[String],
	forbidden_toward_origin: Vector2i,
	visited_vertices: Dictionary,
	steps_in_current_direction: int
) -> Dictionary:
	# Dirección absoluta actual
	var current_direction_vec = Vector2i(current.x - previous.x, current.y - previous.y)
	
	# Dirección objetivo
	var target_direction = _get_direction_to_boundary(target_boundary)
	
	# Las 4 direcciones absolutas posibles
	var all_directions = {
		"north": Vector2i(0, -1),
		"south": Vector2i(0, 1),
		"west": Vector2i(-1, 0),
		"east": Vector2i(1, 0)
	}
	
	# Dirección opuesta
	var opposite_direction = Vector2i(-current_direction_vec.x, -current_direction_vec.y)
	
	print("    Dir actual: %s, Pasos: %d/%d" % [
		current_direction_vec, steps_in_current_direction, min_steps_before_turn
	])
	
	# Generar opciones
	var options: Array = []
	
	for dir_name in all_directions:
		var dir_vec = all_directions[dir_name]
		
		# No ir en dirección opuesta
		if dir_vec == opposite_direction:
			print("      ✗ %s: Dirección opuesta" % dir_name)
			continue
		
		# No ir hacia el origen
		if dir_vec == forbidden_toward_origin:
			print("      ✗ %s: Hacia origen" % dir_name)
			continue
		
		var next_v = current + dir_vec
		var is_turn = (dir_vec != current_direction_vec)
		
		# Si es un turn, verificar que hayamos caminado suficiente en la dirección actual
		if is_turn and steps_in_current_direction < min_steps_before_turn:
			print("      ✗ %s: Turn requiere %d pasos (actual: %d)" % [
				dir_name, min_steps_before_turn, steps_in_current_direction
			])
			continue
		
		var priority = 3 if not is_turn else 1
		
		options.append({
			"vertex": next_v,
			"direction": dir_vec,
			"dir_name": dir_name,
			"is_turn": is_turn,
			"priority": priority
		})
	
	print("    Evaluando %d direcciones" % options.size())
	
	# Filtrar y evaluar opciones
	var valid_options: Array = []
	
	for option in options:
		var next_v: Vector2i = option["vertex"]
		var dir_name: String = option["dir_name"]
		var dir_vec: Vector2i = option["direction"]
		var is_turn: bool = option["is_turn"]
		
		# Verificar límites
		if next_v.x < 0 or next_v.x > columns or next_v.y < 0 or next_v.y > rows:
			print("      ✗ %s (%s): Fuera de límites" % [dir_name, next_v])
			continue
		
		# No visitar vértices ya visitados
		if _get_vertex_key(next_v) in visited_vertices:
			print("      ✗ %s (%s): Ya visitado" % [dir_name, next_v])
			continue
		
		# Verificar si está en boundary prohibido
		if _is_vertex_on_forbidden_boundary(next_v, forbidden_boundaries):
			print("      ✗ %s (%s): Boundary prohibido" % [dir_name, next_v])
			continue
		
		# Si es un turn, verificar colisión con mismo tipo
		if is_turn:
			var edge_key = _get_edge_key(current, next_v)
			if edge_key in path_edges:
				var existing_type = path_edges[edge_key]
				var same_type = false
				if alleyway_type == CellType.SMALL:
					same_type = (existing_type == CellType.SMALL or existing_type == CellType.SMALL_ORIGIN)
				elif alleyway_type == CellType.BIG:
					same_type = (existing_type == CellType.BIG or existing_type == CellType.BIG_ORIGIN)
				
				if same_type:
					print("      ✗ %s (%s): Colisión con mismo tipo" % [dir_name, next_v])
					continue
		
		# Verificar disponibilidad del edge
		if not _can_add_edge_vertices(current, next_v, alleyway_type):
			print("      ✗ %s (%s): Edge no disponible" % [dir_name, next_v])
			continue
		
		# SI ES UN TURN: Hacer lookahead para verificar que se pueden dar min_steps_before_turn pasos
		if is_turn:
			var can_continue = _lookahead_can_continue(
				next_v,
				current,
				dir_vec,
				min_steps_before_turn,
				alleyway_type,
				target_boundary,
				forbidden_boundaries,
				forbidden_toward_origin,
				visited_vertices
			)
			
			if not can_continue:
				print("      ✗ %s (%s): Lookahead falló - no puede continuar %d pasos" % [
					dir_name, next_v, min_steps_before_turn
				])
				continue
		
		# Calcular score
		var edge_direction = Vector2(dir_vec.x, dir_vec.y).normalized()
		var dot_with_target = edge_direction.dot(target_direction)
		var score = dot_with_target * option["priority"]
		
		print("      ✓ %s (%s): %s, score=%.2f" % [
			dir_name, next_v, "TURN" if is_turn else "STRAIGHT", score
		])
		
		valid_options.append({
			"vertex": next_v,
			"score": score,
			"is_turn": is_turn,
			"dir_name": dir_name
		})
	
	if valid_options.is_empty():
		print("    No hay opciones válidas")
		return {"vertex": Vector2i(-1, -1), "is_turn": false}
	
	# Ordenar por score
	valid_options.sort_custom(func(a, b): return a["score"] > b["score"])
	
	print("    Mejor: %s (%s, score=%.2f)" % [
		valid_options[0]["dir_name"],
		valid_options[0]["vertex"],
		valid_options[0]["score"]
	])
	
	# 70% probabilidad de elegir la mejor opción
	var chosen: Dictionary
	if rng.randf() < 0.7:
		chosen = valid_options[0]
	else:
		var idx = rng.randi_range(0, valid_options.size() - 1)
		chosen = valid_options[idx]
		print("    Aleatorio: %s (%s)" % [chosen["dir_name"], chosen["vertex"]])
	
	return {
		"vertex": chosen["vertex"],
		"is_turn": chosen["is_turn"]
	}


func _lookahead_can_continue(
	start_vertex: Vector2i,
	previous_vertex: Vector2i,
	direction: Vector2i,
	steps_needed: int,
	alleyway_type: int,
	target_boundary: String,
	forbidden_boundaries: Array[String],
	forbidden_toward_origin: Vector2i,
	visited_vertices: Dictionary
) -> bool:
	print("        [Lookahead] Verificando %d pasos desde %s en dirección %s" % [
		steps_needed, start_vertex, direction
	])
	
	var current = start_vertex
	var previous = previous_vertex
	
	for step in range(steps_needed):
		var next_v = current + direction
		
		print("          Paso %d: %s → %s" % [step + 1, current, next_v])
		
		# Verificar límites
		if next_v.x < 0 or next_v.x > columns or next_v.y < 0 or next_v.y > rows:
			print("          ✗ Fuera de límites")
			return false
		
		# Si llegamos al boundary objetivo, está bien
		if _is_vertex_on_boundary(next_v, target_boundary):
			print("          ✓ Llegó a boundary objetivo")
			return true
		
		# Verificar si ya fue visitado
		if _get_vertex_key(next_v) in visited_vertices:
			print("          ✗ Ya visitado")
			return false
		
		# Verificar boundary prohibido
		if _is_vertex_on_forbidden_boundary(next_v, forbidden_boundaries):
			print("          ✗ Boundary prohibido")
			return false
		
		# Verificar que no vaya hacia el origen
		if direction == forbidden_toward_origin:
			print("          ✗ Hacia origen")
			return false
		
		# Verificar edge disponible
		if not _can_add_edge_vertices(current, next_v, alleyway_type):
			print("          ✗ Edge no disponible")
			return false
		
		# Avanzar
		previous = current
		current = next_v
		
		print("          ✓ Paso válido")
	
	print("        [Lookahead] ✓ Todos los pasos son válidos")
	return true


func _is_vertex_on_forbidden_boundary(vertex: Vector2i, forbidden_boundaries: Array[String]) -> bool:
	if vertex.y == 0 and "north" in forbidden_boundaries:
		return true
	if vertex.y == rows and "south" in forbidden_boundaries:
		return true
	if vertex.x == 0 and "west" in forbidden_boundaries:
		return true
	if vertex.x == columns and "east" in forbidden_boundaries:
		return true
	return false


func _can_add_edge_vertices(v1: Vector2i, v2: Vector2i, alleyway_type: int) -> bool:
	var edge_key = _get_edge_key(v1, v2)
	
	if not edge_key in path_edges:
		return true
	
	var existing_type = path_edges[edge_key]
	
	if alleyway_type == CellType.BIG and (existing_type == CellType.SMALL or existing_type == CellType.SMALL_ORIGIN):
		return true
	
	return false


func _add_path_edge_vertices(v1: Vector2i, v2: Vector2i, alleyway_type: int) -> void:
	var edge_key = _get_edge_key(v1, v2)
	
	if not edge_key in path_edges or alleyway_type == CellType.BIG or alleyway_type == CellType.BIG_ORIGIN:
		path_edges[edge_key] = alleyway_type


func _get_edge_key(v1: Vector2i, v2: Vector2i) -> String:
	var min_x = min(v1.x, v2.x)
	var min_z = min(v1.y, v2.y)
	var max_x = max(v1.x, v2.x)
	var max_z = max(v1.y, v2.y)
	return "%d_%d_%d_%d" % [min_x, min_z, max_x, max_z]


func _get_vertex_key(vertex: Vector2i) -> String:
	return "%d_%d" % [vertex.x, vertex.y]


func get_path_edge_type_vertices(v1_x: int, v1_z: int, v2_x: int, v2_z: int) -> int:
	var edge_key = _get_edge_key(Vector2i(v1_x, v1_z), Vector2i(v2_x, v2_z))
	return path_edges.get(edge_key, CellType.NORMAL)


func _set_cell_if_allowed(x: int, z: int, alleyway_type: int) -> void:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return
	
	var current_type = grid[x][z]
	
	if current_type == CellType.BOUNDARY:
		return
	
	if alleyway_type == CellType.BIG:
		grid[x][z] = alleyway_type
		return
	
	if alleyway_type == CellType.SMALL and current_type == CellType.NORMAL:
		grid[x][z] = alleyway_type


func _calculate_distorted_positions() -> void:
	cell_positions.clear()
	
	for z in range(rows):
		var row_positions = []
		
		for x in range(columns):
			var u = (float(x) + 0.5) / max(1, columns)
			var v = (float(z) + 0.5) / max(1, rows)
			
			var base_pos = GridHelper.bilinear_interpolation(vertices, u, v)
			
			var bottom_u_dir = (vertices[1] - vertices[0]).normalized()
			var top_u_dir = (vertices[2] - vertices[3]).normalized()
			var local_u_dir = bottom_u_dir.lerp(top_u_dir, v)
			
			var left_v_dir = (vertices[3] - vertices[0]).normalized()
			var right_v_dir = (vertices[2] - vertices[1]).normalized()
			var local_v_dir = left_v_dir.lerp(right_v_dir, u)
			
			var u_falloff = pow(min(u, 1.0 - u) * 2.0, edge_falloff_sharpness)
			var v_falloff = pow(min(v, 1.0 - v) * 2.0, edge_falloff_sharpness)
			
			var wave_offset_u = sin(v * wave_frequency_z * TAU + wave_phase_z) * wave_amplitude_x * u_falloff
			var wave_offset_v = sin(u * wave_frequency_x * TAU + wave_phase_x) * wave_amplitude_z * v_falloff
			
			var distorted_pos_2d = base_pos + local_u_dir * wave_offset_u + local_v_dir * wave_offset_v
			
			var distorted_pos = Vector3(
				distorted_pos_2d.x,
				0.0,
				distorted_pos_2d.y
			)
			
			row_positions.append(distorted_pos)
		
		cell_positions.append(row_positions)


func get_cell(x: int, z: int) -> int:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return -1
	return grid[x][z]


func set_cell(x: int, z: int, value: int) -> void:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return
	grid[x][z] = value


func get_cell_position(x: int, z: int) -> Vector3:
	if z < 0 or z >= cell_positions.size():
		return Vector3.ZERO
	if x < 0 or x >= cell_positions[z].size():
		return Vector3.ZERO
	return cell_positions[z][x]


func is_boundary_cell(x: int, z: int) -> bool:
	if z == 0 and edge_types[0] == -1:
		return true
	if x == columns - 1 and edge_types[1] == -1:
		return true
	if z == rows - 1 and edge_types[2] == -1:
		return true
	if x == 0 and edge_types[3] == -1:
		return true
	return false


func get_edge_type(side: String) -> int:
	match side:
		"north":
			return edge_types[0]
		"east":
			return edge_types[1]
		"south":
			return edge_types[2]
		"west":
			return edge_types[3]
		_:
			return 0


func get_cell_vertices(x: int, z: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return result
	
	for dz in [0, 1]:
		for dx in [0, 1]:
			var cell_x = clamp(x + dx, 0, columns)
			var cell_z = clamp(z + dz, 0, rows)
			
			var u = float(cell_x) / max(1, columns)
			var v = float(cell_z) / max(1, rows)
			var base_pos = GridHelper.bilinear_interpolation(vertices, u, v)
			
			var bottom_u_dir = (vertices[1] - vertices[0]).normalized()
			var top_u_dir = (vertices[2] - vertices[3]).normalized()
			var local_u_dir = bottom_u_dir.lerp(top_u_dir, v)
			
			var left_v_dir = (vertices[3] - vertices[0]).normalized()
			var right_v_dir = (vertices[2] - vertices[1]).normalized()
			var local_v_dir = left_v_dir.lerp(right_v_dir, u)
			
			var u_falloff = pow(min(u, 1.0 - u) * 2.0, edge_falloff_sharpness)
			var v_falloff = pow(min(v, 1.0 - v) * 2.0, edge_falloff_sharpness)
			
			var wave_offset_u = sin(v * wave_frequency_z * TAU + wave_phase_z) * wave_amplitude_x * u_falloff
			var wave_offset_v = sin(u * wave_frequency_x * TAU + wave_phase_x) * wave_amplitude_z * v_falloff
			
			var distorted_pos_2d = base_pos + local_u_dir * wave_offset_u + local_v_dir * wave_offset_v
			
			result.append(Vector3(
				distorted_pos_2d.x,
				0.0,
				distorted_pos_2d.y
			))
	
	return result
