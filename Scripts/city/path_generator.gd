class_name PathGenerator extends RefCounted

enum PathDirection {
	NORTH_TO_SOUTH,
	SOUTH_TO_NORTH,
	WEST_TO_EAST,
	EAST_TO_WEST
}

class Path:
	var id: int
	var floor: int
	var direction: PathDirection
	var points: Array[Vector3i]
	var completed: bool = false
	var merged: bool = false
	var cells_in_current_direction: int = 0
	var current_movement_direction: Vector3i = Vector3i.ZERO
	
	func _init(p_id: int, p_floor: int, p_direction: PathDirection, start_point: Vector3i):
		id = p_id
		floor = p_floor
		direction = p_direction
		points = [start_point]
		cells_in_current_direction = 0
		current_movement_direction = _get_primary_direction_vector(p_direction)
	
	static func _get_primary_direction_vector(dir: PathDirection) -> Vector3i:
		match dir:
			PathDirection.NORTH_TO_SOUTH:
				return Vector3i(0, 1, 0)
			PathDirection.SOUTH_TO_NORTH:
				return Vector3i(0, -1, 0)
			PathDirection.WEST_TO_EAST:
				return Vector3i(1, 0, 0)
			PathDirection.EAST_TO_WEST:
				return Vector3i(-1, 0, 0)
		return Vector3i.ZERO
	
	func has_visited_recently(pos: Vector3i, lookback: int = 3) -> bool:
		var start_idx = max(0, points.size() - lookback)
		for i in range(start_idx, points.size()):
			if points[i] == pos:
				return true
		return false
	
	func record_movement(new_direction: Vector3i) -> void:
		if new_direction == current_movement_direction:
			cells_in_current_direction += 1
		else:
			current_movement_direction = new_direction
			cells_in_current_direction = 1
	
	func contains_point(pos: Vector3i) -> bool:
		for point in points:
			if point == pos:
				return true
		return false

var block_generator: RefCounted
var paths_by_floor: Dictionary = {}
var next_path_id: int = 1

# Grid espacial para búsqueda eficiente
var spatial_grid: Dictionary = {}
var grid_cell_size: int = 5

# Parámetros configurables
var min_path_separation: int = 3  # Distancia a bordes laterales
var min_distance_to_other_paths: int = 2  # Distancia a otros caminos
var min_cells_between_turns: int = 3  # Expansión mínima obligatoria
var edge_buffer: int = 3  # Zona de borde (por defecto igual a min_cells_between_turns)
var growth_randomness: float = 0.3  # Probabilidad de giro lateral
var lookahead_expansions: int = 2  # Cuántas expansiones simular


func _init(p_block_generator: RefCounted):
	block_generator = p_block_generator
	edge_buffer = min_cells_between_turns


# ============================================
# GRID ESPACIAL
# ============================================

func _pos_to_grid_key(pos: Vector3i) -> Vector2i:
	return Vector2i(int(pos.x / grid_cell_size), int(pos.y / grid_cell_size))


func _add_to_spatial_grid(pos: Vector3i, floor: int) -> void:
	if not spatial_grid.has(floor):
		spatial_grid[floor] = {}
	
	var key = _pos_to_grid_key(pos)
	if not spatial_grid[floor].has(key):
		spatial_grid[floor][key] = []
	
	spatial_grid[floor][key].append(pos)


func _get_nearby_points(pos: Vector3i, floor: int, radius: int = 2) -> Array[Vector3i]:
	if not spatial_grid.has(floor):
		return []
	
	var nearby: Array[Vector3i] = []
	var center_key = _pos_to_grid_key(pos)
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var check_key = Vector2i(center_key.x + dx, center_key.y + dy)
			if spatial_grid[floor].has(check_key):
				nearby.append_array(spatial_grid[floor][check_key])
	
	return nearby


# ============================================
# GENERACIÓN DE CAMINOS
# ============================================

func generate_paths(num_paths: int, direction: PathDirection, floor: int = 0) -> void:
	if not paths_by_floor.has(floor):
		paths_by_floor[floor] = []
	
	if spatial_grid.has(floor):
		spatial_grid[floor].clear()
	
	var start_points = _generate_start_points(num_paths, direction, floor)
	
	for start_point in start_points:
		var path = Path.new(next_path_id, floor, direction, start_point)
		next_path_id += 1
		paths_by_floor[floor].append(path)
		_add_to_spatial_grid(start_point, floor)
		_grow_path(path, floor)


func _generate_start_points(num_paths: int, direction: PathDirection, floor: int) -> Array[Vector3i]:
	var points: Array[Vector3i] = []
	var y = floor * block_generator.cells_per_floor
	
	match direction:
		PathDirection.NORTH_TO_SOUTH:
			var z = block_generator.available_min_z
			var usable_width = (block_generator.available_max_x - block_generator.available_min_x + 1) - (2 * min_path_separation)
			if usable_width <= 0:
				return points
			var positions = _calculate_spaced_positions(num_paths, usable_width)
			for pos in positions:
				points.append(Vector3i(block_generator.available_min_x + min_path_separation + pos, z, y))
		
		PathDirection.SOUTH_TO_NORTH:
			var z = block_generator.available_max_z
			var usable_width = (block_generator.available_max_x - block_generator.available_min_x + 1) - (2 * min_path_separation)
			if usable_width <= 0:
				return points
			var positions = _calculate_spaced_positions(num_paths, usable_width)
			for pos in positions:
				points.append(Vector3i(block_generator.available_min_x + min_path_separation + pos, z, y))
		
		PathDirection.WEST_TO_EAST:
			var x = block_generator.available_min_x
			var usable_depth = (block_generator.available_max_z - block_generator.available_min_z + 1) - (2 * min_path_separation)
			if usable_depth <= 0:
				return points
			var positions = _calculate_spaced_positions(num_paths, usable_depth)
			for pos in positions:
				points.append(Vector3i(x, block_generator.available_min_z + min_path_separation + pos, y))
		
		PathDirection.EAST_TO_WEST:
			var x = block_generator.available_max_x
			var usable_depth = (block_generator.available_max_z - block_generator.available_min_z + 1) - (2 * min_path_separation)
			if usable_depth <= 0:
				return points
			var positions = _calculate_spaced_positions(num_paths, usable_depth)
			for pos in positions:
				points.append(Vector3i(x, block_generator.available_min_z + min_path_separation + pos, y))
	
	return points


func _calculate_spaced_positions(num_points: int, available_space: int) -> Array[int]:
	var positions: Array[int] = []
	
	if num_points <= 0 or available_space <= 0:
		return positions
	
	if num_points == 1:
		positions.append(available_space / 2)
		return positions
	
	var spacing = float(available_space - 1) / float(num_points - 1)
	for i in range(num_points):
		positions.append(int(i * spacing))
	
	return positions


func _grow_path(path: Path, floor: int) -> void:
	var current_pos = path.points[0]
	var max_iterations = 1000
	var iterations = 0
	
	while not _has_reached_opposite_edge(current_pos, path.direction) and not path.merged and iterations < max_iterations:
		var next_pos = _get_next_position(current_pos, path, floor)
		
		path.points.append(next_pos)
		_add_to_spatial_grid(next_pos, floor)
		
		# Verificar merge
		if _check_merge(next_pos, path, floor):
			path.merged = true
			path.completed = true
			break
		
		current_pos = next_pos
		iterations += 1
	
	if iterations >= max_iterations:
		push_warning("Path %d alcanzó max_iterations" % path.id)
	
	if not path.merged:
		path.completed = _has_reached_opposite_edge(current_pos, path.direction)


# ============================================
# LÓGICA DE DECISIÓN DE SIGUIENTE POSICIÓN
# ============================================

func _get_next_position(current_pos: Vector3i, path: Path, floor: int) -> Vector3i:
	var primary_dir = Path._get_primary_direction_vector(path.direction)
	
	# REGLA 1: Zona de borde - SOLO dirección principal
	if _is_in_edge_zone(current_pos, path.direction):
		var next_pos = current_pos + primary_dir
		path.record_movement(primary_dir)
		return next_pos
	
	# REGLA 2: Expansión mínima incompleta - DEBE continuar en dirección actual
	if path.cells_in_current_direction < min_cells_between_turns:
		return _continue_or_merge(current_pos, path, floor)
	
	# REGLA 3: Puede cambiar de dirección - evaluar opciones
	return _evaluate_direction_change(current_pos, path, floor)


## Continúa en dirección actual o intenta merge si está atascado
func _continue_or_merge(current_pos: Vector3i, path: Path, floor: int) -> Vector3i:
	var next_pos = current_pos + path.current_movement_direction
	
	# Verificar si puede continuar
	if _is_valid_position(next_pos, path.direction) and not path.has_visited_recently(next_pos):
		path.record_movement(path.current_movement_direction)
		return next_pos
	
	# Está atascado - intentar merge
	var merge_dir = _find_merge_direction(current_pos, path, floor)
	if merge_dir != Vector3i.ZERO:
		next_pos = current_pos + merge_dir
		path.record_movement(merge_dir)
		return next_pos
	
	# Fallback: dirección principal
	var primary_dir = Path._get_primary_direction_vector(path.direction)
	next_pos = current_pos + primary_dir
	path.record_movement(primary_dir)
	return next_pos


## Evalúa todas las opciones cuando puede cambiar de dirección
func _evaluate_direction_change(current_pos: Vector3i, path: Path, floor: int) -> Vector3i:
	var primary_dir = Path._get_primary_direction_vector(path.direction)
	var valid_directions: Array[Vector3i] = []
	
	# Opción 1: Dirección principal (siempre considerar)
	if _can_expand_safely(current_pos, primary_dir, path, floor):
		valid_directions.append(primary_dir)
	
	# Opción 2: Direcciones laterales (con probabilidad)
	if randf() < growth_randomness:
		var lateral_dirs = _get_lateral_directions(path.direction)
		for lateral_dir in lateral_dirs:
			if lateral_dir != path.current_movement_direction:
				if _can_expand_safely(current_pos, lateral_dir, path, floor):
					valid_directions.append(lateral_dir)
	
	# Si hay opciones válidas, elegir una
	if valid_directions.size() > 0:
		var chosen_dir = valid_directions[randi() % valid_directions.size()]
		var next_pos = current_pos + chosen_dir
		path.record_movement(chosen_dir)
		return next_pos
	
	# No hay opciones - intentar merge
	var merge_dir = _find_merge_direction(current_pos, path, floor)
	if merge_dir != Vector3i.ZERO:
		var next_pos = current_pos + merge_dir
		path.record_movement(merge_dir)
		return next_pos
	
	# Fallback final
	var next_pos = current_pos + primary_dir
	path.record_movement(primary_dir)
	return next_pos


# ============================================
# VALIDACIÓN DE EXPANSIONES
# ============================================

## Verifica si puede expandirse de forma segura en una dirección
## Simula lookahead_expansions * min_cells_between_turns pasos
func _can_expand_safely(start_pos: Vector3i, direction: Vector3i, path: Path, floor: int) -> bool:
	var simulated_pos = start_pos
	var total_steps = min_cells_between_turns * lookahead_expansions
	
	for step in range(total_steps):
		simulated_pos += direction
		
		# Verificar validez básica
		if not _is_valid_position(simulated_pos, path.direction):
			return false
		
		# No volver sobre pasos recientes
		if path.contains_point(simulated_pos):
			return false
		
		# Verificar distancia a otros caminos
		if not _maintains_distance_from_paths(simulated_pos, path, floor):
			return false
		
		# Si llega al destino, es válido
		if _has_reached_opposite_edge(simulated_pos, path.direction):
			return true
	
	return true


## Verifica que una posición mantenga distancia de otros caminos
func _maintains_distance_from_paths(pos: Vector3i, current_path: Path, floor: int) -> bool:
	var nearby_points = _get_nearby_points(pos, floor, 2)
	
	for point in nearby_points:
		if not current_path.contains_point(point):
			var dist = _manhattan_distance(pos, point)
			if dist < min_distance_to_other_paths:
				return false
	
	return true


## Verifica que una posición esté dentro de límites y respete márgenes
func _is_valid_position(pos: Vector3i, direction: PathDirection) -> bool:
	# Límites del área disponible
	if pos.x < block_generator.available_min_x or pos.x > block_generator.available_max_x:
		return false
	if pos.y < block_generator.available_min_z or pos.y > block_generator.available_max_z:
		return false
	
	# Márgenes laterales (según dirección principal)
	match direction:
		PathDirection.NORTH_TO_SOUTH, PathDirection.SOUTH_TO_NORTH:
			var dist_to_min_x = pos.x - block_generator.available_min_x
			var dist_to_max_x = block_generator.available_max_x - pos.x
			return dist_to_min_x >= min_path_separation and dist_to_max_x >= min_path_separation
		
		PathDirection.WEST_TO_EAST, PathDirection.EAST_TO_WEST:
			var dist_to_min_z = pos.y - block_generator.available_min_z
			var dist_to_max_z = block_generator.available_max_z - pos.y
			return dist_to_min_z >= min_path_separation and dist_to_max_z >= min_path_separation
	
	return true


# ============================================
# UTILIDADES DE NAVEGACIÓN
# ============================================

func _is_in_edge_zone(pos: Vector3i, direction: PathDirection) -> bool:
	match direction:
		PathDirection.NORTH_TO_SOUTH:
			var dist_from_start = pos.y - block_generator.available_min_z
			var dist_from_end = block_generator.available_max_z - pos.y
			return dist_from_start < edge_buffer or dist_from_end < edge_buffer
		
		PathDirection.SOUTH_TO_NORTH:
			var dist_from_start = block_generator.available_max_z - pos.y
			var dist_from_end = pos.y - block_generator.available_min_z
			return dist_from_start < edge_buffer or dist_from_end < edge_buffer
		
		PathDirection.WEST_TO_EAST:
			var dist_from_start = pos.x - block_generator.available_min_x
			var dist_from_end = block_generator.available_max_x - pos.x
			return dist_from_start < edge_buffer or dist_from_end < edge_buffer
		
		PathDirection.EAST_TO_WEST:
			var dist_from_start = block_generator.available_max_x - pos.x
			var dist_from_end = pos.x - block_generator.available_min_x
			return dist_from_start < edge_buffer or dist_from_end < edge_buffer
	
	return false


func _has_reached_opposite_edge(pos: Vector3i, direction: PathDirection) -> bool:
	match direction:
		PathDirection.NORTH_TO_SOUTH:
			return pos.y >= block_generator.available_max_z
		PathDirection.SOUTH_TO_NORTH:
			return pos.y <= block_generator.available_min_z
		PathDirection.WEST_TO_EAST:
			return pos.x >= block_generator.available_max_x
		PathDirection.EAST_TO_WEST:
			return pos.x <= block_generator.available_min_x
	
	return false


func _get_lateral_directions(direction: PathDirection) -> Array[Vector3i]:
	var lateral_dirs: Array[Vector3i] = []
	
	match direction:
		PathDirection.NORTH_TO_SOUTH, PathDirection.SOUTH_TO_NORTH:
			lateral_dirs.append(Vector3i(-1, 0, 0))
			lateral_dirs.append(Vector3i(1, 0, 0))
		
		PathDirection.WEST_TO_EAST, PathDirection.EAST_TO_WEST:
			lateral_dirs.append(Vector3i(0, -1, 0))
			lateral_dirs.append(Vector3i(0, 1, 0))
	
	return lateral_dirs


func _manhattan_distance(a: Vector3i, b: Vector3i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# ============================================
# MERGE
# ============================================

func _check_merge(pos: Vector3i, current_path: Path, floor: int) -> bool:
	var nearby_points = _get_nearby_points(pos, floor, 1)
	
	for point in nearby_points:
		if point == pos and not current_path.contains_point(point):
			return true
	
	return false


func _find_merge_direction(current_pos: Vector3i, current_path: Path, floor: int) -> Vector3i:
	var nearby_points = _get_nearby_points(current_pos, floor, 3)
	
	if nearby_points.is_empty():
		return Vector3i.ZERO
	
	var closest_point = Vector3i.ZERO
	var min_dist = INF
	
	for point in nearby_points:
		if not current_path.contains_point(point):
			var dist = _manhattan_distance(current_pos, point)
			if dist > 0 and dist < min_dist:
				min_dist = dist
				closest_point = point
	
	if min_dist == INF:
		return Vector3i.ZERO
	
	# Calcular dirección hacia el punto más cercano
	var delta = closest_point - current_pos
	
	if abs(delta.x) > abs(delta.y):
		return Vector3i(1 if delta.x > 0 else -1, 0, 0)
	else:
		return Vector3i(0, 1 if delta.y > 0 else -1, 0)


# ============================================
# API PÚBLICA
# ============================================

func get_all_paths() -> Array:
	var all_paths: Array = []
	for floor in paths_by_floor.keys():
		all_paths.append_array(paths_by_floor[floor])
	return all_paths


func get_paths_for_floor(floor: int) -> Array:
	if paths_by_floor.has(floor):
		return paths_by_floor[floor]
	return []


func get_paths_by_floor() -> Dictionary:
	return paths_by_floor


func get_floors_with_paths() -> Array:
	return paths_by_floor.keys()


func get_path_by_id(path_id: int):
	for floor in paths_by_floor.keys():
		for path in paths_by_floor[floor]:
			if path.id == path_id:
				return path
	return null


func get_path_world_positions(path) -> Array[Vector3]:
	var world_positions: Array[Vector3] = []
	
	for point in path.points:
		var world_pos = block_generator.get_cell_position(point.x, point.y, point.z)
		world_positions.append(world_pos)
	
	return world_positions


func clear_paths() -> void:
	paths_by_floor.clear()
	spatial_grid.clear()
	next_path_id = 1


func clear_paths_for_floor(floor: int) -> void:
	if paths_by_floor.has(floor):
		paths_by_floor.erase(floor)
	if spatial_grid.has(floor):
		spatial_grid.erase(floor)


func get_path_info(path) -> Dictionary:
	return {
		"id": path.id,
		"floor": path.floor,
		"direction": path.direction,
		"points_count": path.points.size(),
		"completed": path.completed,
		"merged": path.merged,
		"start": path.points[0] if path.points.size() > 0 else Vector3i.ZERO,
		"end": path.points[-1] if path.points.size() > 0 else Vector3i.ZERO
	}


func get_floor_stats(floor: int) -> Dictionary:
	var paths = get_paths_for_floor(floor)
	var total_points = 0
	var completed_count = 0
	var merged_count = 0
	
	for path in paths:
		total_points += path.points.size()
		if path.completed:
			completed_count += 1
		if path.merged:
			merged_count += 1
	
	return {
		"floor": floor,
		"total_paths": paths.size(),
		"completed_paths": completed_count,
		"merged_paths": merged_count,
		"total_points": total_points,
		"avg_points_per_path": float(total_points) / max(1, paths.size())
	}


func get_global_stats() -> Dictionary:
	var total_paths = 0
	var total_points = 0
	var total_merged = 0
	var floors_count = paths_by_floor.keys().size()
	
	for floor in paths_by_floor.keys():
		var floor_paths = paths_by_floor[floor]
		total_paths += floor_paths.size()
		for path in floor_paths:
			total_points += path.points.size()
			if path.merged:
				total_merged += 1
	
	return {
		"total_floors": floors_count,
		"total_paths": total_paths,
		"total_merged_paths": total_merged,
		"total_points": total_points,
		"avg_paths_per_floor": float(total_paths) / max(1, floors_count),
		"avg_points_per_path": float(total_points) / max(1, total_paths)
	}


func set_generation_params(p_min_separation: int, p_randomness: float, p_max_deviation: int) -> void:
	min_path_separation = p_min_separation
	growth_randomness = clampf(p_randomness, 0.0, 1.0)
