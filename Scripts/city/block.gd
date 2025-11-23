class_name BlockGenerator extends RefCounted

# Tipos de calles
enum StreetType {
	BOUNDARY = -1,
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2,
	SMALL_TUNNEL = 3,
	LARGE_TUNNEL = 4,
}

# Lados de un rectángulo
enum RectSide {
	NORTH = 0,  # z (arriba)
	EAST = 1,   # x + width (derecha)
	SOUTH = 2,  # z + height (abajo)
	WEST = 3    # x (izquierda)
}

# Estructura para representar un rectángulo en la grilla
class GridRectangle:
	var x: int  # Posición X inicial
	var z: int  # Posición Z inicial
	var width: int  # Ancho en celdas (eje X)
	var height: int  # Alto en celdas (eje Z)
	var id: int  # ID único del rectángulo
	
	func _init(p_x: int, p_z: int, p_width: int, p_height: int, p_id: int) -> void:
		x = p_x
		z = p_z
		width = p_width
		height = p_height
		id = p_id
	
	# Calcula el aspect ratio del rectángulo
	func get_aspect_ratio() -> float:
		var max_side = max(width, height)
		var min_side = min(width, height)
		if min_side == 0:
			return INF
		return float(max_side) / float(min_side)
	
	# Obtiene la dimensión más grande
	func get_max_dimension() -> int:
		return max(width, height)
	
	# Verifica si el rectángulo puede dividirse
	func can_split(min_size: int) -> bool:
		return width >= min_size * 2 or height >= min_size * 2

# Estructura para almacenar los offsets de un rectángulo
class RectangleOffsets:
	var north: int = 0  # Offset superior (z)
	var east: int = 0   # Offset derecho (x + width)
	var south: int = 0  # Offset inferior (z + height)
	var west: int = 0   # Offset izquierdo (x)
	
	func _init(p_north: int = 0, p_east: int = 0, p_south: int = 0, p_west: int = 0) -> void:
		north = p_north
		east = p_east
		south = p_south
		west = p_west

# Estructura de la grilla
var rows: int
var columns: int
var cell_height: float
var floors: int
var cells_per_floor: int

# Geometría del bloque
var vertices: Array[Vector2]  # [top_left, top_right, bottom_right, bottom_left]
var street_types: Array[int]  # [north, east, south, west]

# Grilla 3D: [x][z][y] -> int (0 = vacío/calle, >0 = ID de rectángulo)
var grid: Array = []

# Información de las celdas
var cell_positions: Array = []  # Posiciones 3D de cada celda

# Offsets de calles según tipo (en número de celdas)
const STREET_OFFSETS = {
	StreetType.BOUNDARY: 0,
	StreetType.SMALL: 3,
	StreetType.MEDIUM: 4,
	StreetType.LARGE: 5,
	StreetType.SMALL_TUNNEL: 0,
	StreetType.LARGE_TUNNEL: 0,
}

# Área disponible después de offsets
var available_min_x: int
var available_max_x: int
var available_min_z: int
var available_max_z: int

# Generación de rectángulos
var rectangles: Array[GridRectangle] = []  # Lista de rectángulos generados
var next_rectangle_id: int = 1  # Siguiente ID para asignar
var min_rectangle_size: int = 2  # Tamaño mínimo de ancho/alto para un rectángulo
var max_aspect_ratio: float = 1.5  # Aspect ratio máximo aceptable
var max_rectangle_dimension: int = 8  # Tamaño máximo absoluto de cualquier lado
var random: RandomNumberGenerator = RandomNumberGenerator.new()

# Información del "callejón" (primera división)
var first_split_position: int = -1  # Posición de la primera división
var first_split_is_horizontal: bool = false  # Si es horizontal (paralela a X) o vertical (paralela a Z)
var merged_rectangles: Dictionary = {}  # {rect_id: merged_with_rect_id} - rectángulos mergeados

# Offsets de callejones
var rectangle_offsets: Dictionary = {}  # {rect_id: RectangleOffsets} - offsets de cada rectángulo
var min_alley_offset: int = 0
var max_alley_offset: int = 2


func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_street_types: Array[int],
	p_cell_height: float,
	p_floors: int,
	p_cells_per_floor: int
) -> void:
	rows = p_rows
	columns = p_columns
	vertices = p_vertices
	street_types = p_street_types
	cell_height = p_cell_height
	floors = p_floors
	cells_per_floor = p_cells_per_floor
	
	random.randomize()
	
	_initialize_grid()
	_calculate_cell_positions()
	_calculate_available_area()


# Inicializa la grilla 3D con todas las celdas como vacías (0)
func _initialize_grid() -> void:
	grid.clear()
	var total_height = floors * cells_per_floor
	
	for x in range(columns):
		var grid_x = []
		for z in range(rows):
			var grid_z = []
			for y in range(total_height):
				grid_z.append(0)
			grid_x.append(grid_z)
		grid.append(grid_x)


# Calcula las posiciones 3D de cada celda usando interpolación bilineal
func _calculate_cell_positions() -> void:
	cell_positions.clear()
	var total_height = floors * cells_per_floor
	
	for y in range(total_height):
		var height = y * cell_height
		var positions_2d = []
		
		for z in range(rows):
			var row_positions = []
			for x in range(columns):
				# Interpolación bilineal para posición en el cuadrilátero skewed
				var u = float(x) / max(1, columns - 1)  # Normalizado [0, 1]
				var v = float(z) / max(1, rows - 1)  # Normalizado [0, 1]
				
				# Interpolación bilinear: P = (1-u)(1-v)P0 + u(1-v)P1 + uv*P2 + (1-u)v*P3
				var pos_2d = (
					vertices[0] * (1 - u) * (1 - v) +  # top_left
					vertices[1] * u * (1 - v) +  # top_right
					vertices[2] * u * v +  # bottom_right
					vertices[3] * (1 - u) * v  # bottom_left
				)
				
				var pos_3d = Vector3(pos_2d.x, height, pos_2d.y)
				row_positions.append(pos_3d)
			
			positions_2d.append(row_positions)
		cell_positions.append(positions_2d)


# Calcula el área disponible después de aplicar los offsets de las calles
func _calculate_available_area() -> void:
	# North street (z = 0)
	var north_offset = STREET_OFFSETS.get(street_types[0], 0)
	# South street (z = rows-1)
	var south_offset = STREET_OFFSETS.get(street_types[2], 0)
	# West street (x = 0)
	var west_offset = STREET_OFFSETS.get(street_types[3], 0)
	# East street (x = columns-1)
	var east_offset = STREET_OFFSETS.get(street_types[1], 0)
	
	available_min_x = west_offset
	available_max_x = columns - east_offset - 1
	available_min_z = north_offset
	available_max_z = rows - south_offset - 1


# ============================================
# GENERACIÓN DE RECTÁNGULOS (Enfoque iterativo)
# ============================================

# Genera rectángulos dividiendo iterativamente según aspect ratio y tamaño
func generate_rectangles(p_max_divisions: int = 4, p_min_size: int = 2, p_max_aspect_ratio: float = 1.5, p_max_dimension: int = 8, seed_value: int = -1) -> void:
	min_rectangle_size = p_min_size
	max_aspect_ratio = p_max_aspect_ratio
	max_rectangle_dimension = p_max_dimension
	rectangles.clear()
	merged_rectangles.clear()
	rectangle_offsets.clear()
	next_rectangle_id = 1
	first_split_position = -1
	
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	
	# Calcular área disponible
	var start_x = available_min_x
	var start_z = available_min_z
	var width = available_max_x - available_min_x + 1
	var height = available_max_z - available_min_z + 1
	
	# Crear el rectángulo inicial
	var initial_rect = GridRectangle.new(start_x, start_z, width, height, next_rectangle_id)
	next_rectangle_id += 1
	
	# Cola de rectángulos pendientes de procesar
	var pending_rects: Array[GridRectangle] = [initial_rect]
	var iterations = 0
	var max_iterations = p_max_divisions * 100  # Límite de seguridad
	var is_first_split = true
	
	while not pending_rects.is_empty() and iterations < max_iterations:
		iterations += 1
		
		# Encontrar el rectángulo que más necesita dividirse
		var worst_rect_idx = _find_rectangle_to_split(pending_rects)
		var rect_to_split = pending_rects[worst_rect_idx]
		pending_rects.remove_at(worst_rect_idx)
		
		# Verificar si el rectángulo necesita dividirse
		if not _should_split_rectangle(rect_to_split):
			rectangles.append(rect_to_split)
			continue
		
		# Intentar dividir el rectángulo
		var split_result = _split_rectangle(rect_to_split)
		
		if split_result.is_empty():
			# No se pudo dividir, agregar como está
			rectangles.append(rect_to_split)
		else:
			# Recordar la primera división como "callejón"
			if is_first_split:
				_record_first_split(rect_to_split, split_result)
				is_first_split = false
			
			# Se pudo dividir, agregar los nuevos rectángulos a la cola
			pending_rects.append(split_result[0])
			pending_rects.append(split_result[1])
	
	# Agregar cualquier rectángulo restante
	for rect in pending_rects:
		rectangles.append(rect)
	
	# Aplicar los rectángulos a la grilla
	_apply_rectangles_to_grid()
	
	# Crear conexión a través del callejón
	_create_alley_connection()
	
	# Generar offsets para callejones
	_generate_rectangle_offsets()


# Registra la información de la primera división
func _record_first_split(original_rect: GridRectangle, split_rects: Array[GridRectangle]) -> void:
	first_split_is_horizontal = original_rect.height > original_rect.width
	
	if first_split_is_horizontal:
		# División horizontal: la línea está entre los dos rectángulos en Z
		first_split_position = split_rects[0].z + split_rects[0].height
	else:
		# División vertical: la línea está entre los dos rectángulos en X
		first_split_position = split_rects[0].x + split_rects[0].width


# Encuentra el rectángulo que más necesita dividirse
func _find_rectangle_to_split(rects: Array[GridRectangle]) -> int:
	var worst_idx = 0
	var worst_score = _get_split_priority_score(rects[0])
	
	for i in range(1, rects.size()):
		var score = _get_split_priority_score(rects[i])
		if score > worst_score:
			worst_score = score
			worst_idx = i
	
	return worst_idx


# Calcula un score de prioridad para dividir un rectángulo (mayor = más urgente)
func _get_split_priority_score(rect: GridRectangle) -> float:
	var score = 0.0
	
	# Penalizar mucho si algún lado excede el tamaño máximo
	var max_side = max(rect.width, rect.height)
	if max_side > max_rectangle_dimension:
		score += (max_side - max_rectangle_dimension) * 100.0
	
	# Penalizar por mal aspect ratio
	var aspect_ratio = rect.get_aspect_ratio()
	if aspect_ratio > max_aspect_ratio:
		score += (aspect_ratio - max_aspect_ratio) * 10.0
	
	# Penalizar por área grande (para distribuir mejor)
	var area = rect.width * rect.height
	score += area * 0.1
	
	return score


# Verifica si un rectángulo debe dividirse
func _should_split_rectangle(rect: GridRectangle) -> bool:
	# Si no se puede dividir, no intentar
	if not rect.can_split(min_rectangle_size):
		return false
	
	# Si algún lado excede el máximo, DEBE dividirse
	if rect.width > max_rectangle_dimension or rect.height > max_rectangle_dimension:
		return true
	
	# Si el aspect ratio es malo, debe dividirse
	if rect.get_aspect_ratio() > max_aspect_ratio:
		return true
	
	# Si es muy grande en área, considerar dividirlo
	var area = rect.width * rect.height
	var max_area = max_rectangle_dimension * max_rectangle_dimension
	if area > max_area:
		return true
	
	# Caso contrario, está bien como está
	return false


# Divide un rectángulo en dos partes
func _split_rectangle(rect: GridRectangle) -> Array[GridRectangle]:
	var result: Array[GridRectangle] = []
	
	# Decidir dirección de división: siempre dividir el lado más largo
	var divide_horizontally = rect.height > rect.width
	
	if divide_horizontally:
		# Dividir horizontalmente
		if rect.height < min_rectangle_size * 2:
			return []  # No se puede dividir
		
		var split_z = _find_valid_split(rect.z, rect.height, true)
		if split_z == -1:
			return []
		
		var height1 = split_z - rect.z
		var height2 = rect.height - height1
		
		var rect1 = GridRectangle.new(rect.x, rect.z, rect.width, height1, next_rectangle_id)
		next_rectangle_id += 1
		
		var rect2 = GridRectangle.new(rect.x, split_z, rect.width, height2, next_rectangle_id)
		next_rectangle_id += 1
		
		result.append(rect1)
		result.append(rect2)
	else:
		# Dividir verticalmente
		if rect.width < min_rectangle_size * 2:
			return []  # No se puede dividir
		
		var split_x = _find_valid_split(rect.x, rect.width, false)
		if split_x == -1:
			return []
		
		var width1 = split_x - rect.x
		var width2 = rect.width - width1
		
		var rect1 = GridRectangle.new(rect.x, rect.z, width1, rect.height, next_rectangle_id)
		next_rectangle_id += 1
		
		var rect2 = GridRectangle.new(split_x, rect.z, width2, rect.height, next_rectangle_id)
		next_rectangle_id += 1
		
		result.append(rect1)
		result.append(rect2)
	
	return result


# Encuentra un punto de división válido
func _find_valid_split(start: int, size: int, is_horizontal: bool) -> int:
	const MAX_ATTEMPTS = 50
	
	for attempt in range(MAX_ATTEMPTS):
		var min_pos = start + min_rectangle_size
		var max_pos = start + size - min_rectangle_size
		
		if min_pos >= max_pos:
			return -1
		
		var split_pos = random.randi_range(min_pos, max_pos)
		
		var size1 = split_pos - start
		var size2 = size - size1
		
		if size1 >= min_rectangle_size and size2 >= min_rectangle_size:
			return split_pos
	
	return -1


# ============================================
# CREACIÓN DE CONEXIÓN DE CALLEJÓN
# ============================================

# Crea una conexión entre dos rectángulos a través del callejón
func _create_alley_connection() -> void:
	if first_split_position == -1:
		return  # No hay primera división registrada
	
	# Encontrar rectángulos adyacentes al callejón en ambos lados
	var side1_rects = _find_rectangles_adjacent_to_alley(true)
	var side2_rects = _find_rectangles_adjacent_to_alley(false)
	
	if side1_rects.is_empty() or side2_rects.is_empty():
		return
	
	# Encontrar todos los pares válidos donde uno contiene al otro
	var valid_pairs = _find_valid_containment_pairs(side1_rects, side2_rects)
	
	if valid_pairs.is_empty():
		# Si no hay pares que cumplan la condición de contención, usar el algoritmo anterior
		var rect1 = side1_rects[random.randi() % side1_rects.size()]
		var rect2 = _find_best_merge_candidate_by_overlap(rect1, side2_rects)
		
		if rect2 != null:
			merged_rectangles[rect1.id] = rect2.id
			merged_rectangles[rect2.id] = rect1.id
		return
	
	# Elegir un par aleatorio de los válidos
	var chosen_pair = valid_pairs[random.randi() % valid_pairs.size()]
	var rect1 = chosen_pair[0]
	var rect2 = chosen_pair[1]
	
	# Registrar el merge (bidireccional)
	merged_rectangles[rect1.id] = rect2.id
	merged_rectangles[rect2.id] = rect1.id


# Encuentra todos los pares válidos donde un lado contiene al otro
func _find_valid_containment_pairs(side1_rects: Array[GridRectangle], side2_rects: Array[GridRectangle]) -> Array:
	var valid_pairs = []
	
	for rect1 in side1_rects:
		for rect2 in side2_rects:
			# Verificar si uno contiene al otro
			if _does_edge_contain(rect1, rect2) or _does_edge_contain(rect2, rect1):
				valid_pairs.append([rect1, rect2])
	
	return valid_pairs


# Verifica si el borde compartido de rect1 contiene completamente al de rect2
func _does_edge_contain(rect1: GridRectangle, rect2: GridRectangle) -> bool:
	if first_split_is_horizontal:
		# Comparar rangos en X
		var rect1_start = rect1.x
		var rect1_end = rect1.x + rect1.width
		var rect2_start = rect2.x
		var rect2_end = rect2.x + rect2.width
		
		# rect1 contiene a rect2 si el inicio de rect1 es <= al de rect2 
		# y el final de rect1 es >= al de rect2
		return rect1_start <= rect2_start and rect1_end >= rect2_end
	else:
		# Comparar rangos en Z
		var rect1_start = rect1.z
		var rect1_end = rect1.z + rect1.height
		var rect2_start = rect2.z
		var rect2_end = rect2.z + rect2.height
		
		return rect1_start <= rect2_start and rect1_end >= rect2_end


# Encuentra rectángulos adyacentes al callejón
func _find_rectangles_adjacent_to_alley(first_side: bool) -> Array[GridRectangle]:
	var adjacent_rects: Array[GridRectangle] = []
	
	for rect in rectangles:
		var is_adjacent = false
		
		if first_split_is_horizontal:
			# El callejón es horizontal (paralelo a X)
			if first_side:
				# Lado norte del callejón (z + height == split_position)
				is_adjacent = (rect.z + rect.height == first_split_position)
			else:
				# Lado sur del callejón (z == split_position)
				is_adjacent = (rect.z == first_split_position)
		else:
			# El callejón es vertical (paralelo a Z)
			if first_side:
				# Lado oeste del callejón (x + width == split_position)
				is_adjacent = (rect.x + rect.width == first_split_position)
			else:
				# Lado este del callejón (x == split_position)
				is_adjacent = (rect.x == first_split_position)
		
		if is_adjacent:
			adjacent_rects.append(rect)
	
	return adjacent_rects


# Encuentra el mejor candidato para mergear por superposición (algoritmo anterior como fallback)
func _find_best_merge_candidate_by_overlap(rect1: GridRectangle, candidates: Array[GridRectangle]) -> GridRectangle:
	var best_candidate: GridRectangle = null
	var best_overlap = 0
	
	for rect2 in candidates:
		var overlap = _calculate_shared_edge_length(rect1, rect2)
		
		if overlap > best_overlap:
			best_overlap = overlap
			best_candidate = rect2
	
	return best_candidate


# Calcula la longitud del borde compartido entre dos rectángulos
func _calculate_shared_edge_length(rect1: GridRectangle, rect2: GridRectangle) -> int:
	if first_split_is_horizontal:
		# Calcular superposición en X
		var x1_start = rect1.x
		var x1_end = rect1.x + rect1.width
		var x2_start = rect2.x
		var x2_end = rect2.x + rect2.width
		
		var overlap_start = max(x1_start, x2_start)
		var overlap_end = min(x1_end, x2_end)
		
		return max(0, overlap_end - overlap_start)
	else:
		# Calcular superposición en Z
		var z1_start = rect1.z
		var z1_end = rect1.z + rect1.height
		var z2_start = rect2.z
		var z2_end = rect2.z + rect2.height
		
		var overlap_start = max(z1_start, z2_start)
		var overlap_end = min(z1_end, z2_end)
		
		return max(0, overlap_end - overlap_start)


# ============================================
# GENERACIÓN DE OFFSETS DE CALLEJONES
# ============================================

# Genera offsets aleatorios para cada rectángulo
func _generate_rectangle_offsets() -> void:
	rectangle_offsets.clear()
	
	for rect in rectangles:
		var offsets = RectangleOffsets.new()
		
		# Determinar qué lado(s) no pueden tener offset (si está mergeado)
		var blocked_side = _get_merged_side(rect)
		
		# Generar offsets aleatorios para cada lado
		if blocked_side != RectSide.NORTH:
			offsets.north = random.randi_range(min_alley_offset, max_alley_offset)
		
		if blocked_side != RectSide.EAST:
			offsets.east = random.randi_range(min_alley_offset, max_alley_offset)
		
		if blocked_side != RectSide.SOUTH:
			offsets.south = random.randi_range(min_alley_offset, max_alley_offset)
		
		if blocked_side != RectSide.WEST:
			offsets.west = random.randi_range(min_alley_offset, max_alley_offset)
		
		rectangle_offsets[rect.id] = offsets


# Determina qué lado del rectángulo está bloqueado por un merge
func _get_merged_side(rect: GridRectangle) -> int:
	if not is_rectangle_merged(rect.id):
		return -1  # No está mergeado, ningún lado bloqueado
	
	# Determinar en qué lado del callejón está este rectángulo
	if first_split_is_horizontal:
		# Callejón horizontal
		if rect.z + rect.height == first_split_position:
			return RectSide.SOUTH  # El lado sur está contra el callejón
		elif rect.z == first_split_position:
			return RectSide.NORTH  # El lado norte está contra el callejón
	else:
		# Callejón vertical
		if rect.x + rect.width == first_split_position:
			return RectSide.EAST  # El lado este está contra el callejón
		elif rect.x == first_split_position:
			return RectSide.WEST  # El lado oeste está contra el callejón
	
	return -1


# Obtiene los offsets de un rectángulo
func get_rectangle_offsets(rect_id: int) -> RectangleOffsets:
	return rectangle_offsets.get(rect_id, RectangleOffsets.new())


# Obtiene las coordenadas con offset aplicado de un rectángulo
func get_rectangle_bounds_with_offset(rect: GridRectangle) -> Dictionary:
	var offsets = get_rectangle_offsets(rect.id)
	
	return {
		"x_min": rect.x + offsets.west,
		"x_max": rect.x + rect.width - offsets.east,
		"z_min": rect.z + offsets.north,
		"z_max": rect.z + rect.height - offsets.south
	}


# Verifica si un rectángulo está mergeado
func is_rectangle_merged(rect_id: int) -> bool:
	return rect_id in merged_rectangles


# Obtiene el rectángulo con el que está mergeado otro
func get_merged_with(rect_id: int) -> int:
	return merged_rectangles.get(rect_id, -1)


# Aplica los rectángulos generados a la grilla 3D
func _apply_rectangles_to_grid() -> void:
	var total_height = floors * cells_per_floor
	
	for rect in rectangles:
		for y in range(total_height):
			for dx in range(rect.width):
				for dz in range(rect.height):
					var gx = rect.x + dx
					var gz = rect.z + dz
					set_cell(gx, gz, y, rect.id)


# Obtiene el rectángulo al que pertenece una celda
func get_rectangle_at(x: int, z: int) -> GridRectangle:
	for rect in rectangles:
		if x >= rect.x and x < rect.x + rect.width:
			if z >= rect.z and z < rect.z + rect.height:
				return rect
	return null


# ============================================
# MÉTODOS DE ACCESO A LA GRILLA
# ============================================

# Obtiene el ID del rectángulo en una posición
func get_cell(x: int, z: int, y: int) -> int:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return 0
	var total_height = floors * cells_per_floor
	if y < 0 or y >= total_height:
		return 0
	return grid[x][z][y]


# Establece el ID del rectángulo en una posición
func set_cell(x: int, z: int, y: int, value: int) -> void:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return
	var total_height = floors * cells_per_floor
	if y < 0 or y >= total_height:
		return
	grid[x][z][y] = value


# Obtiene la posición 3D de una celda
func get_cell_position(x: int, z: int, y: int) -> Vector3:
	if y < 0 or y >= cell_positions.size():
		return Vector3.ZERO
	if z < 0 or z >= cell_positions[y].size():
		return Vector3.ZERO
	if x < 0 or x >= cell_positions[y][z].size():
		return Vector3.ZERO
	return cell_positions[y][z][x]


# Obtiene el piso al que pertenece una celda
func get_floor_for_cell(y: int) -> int:
	return int(y / cells_per_floor)


# Verifica si una celda está al inicio de un piso
func is_floor_start(y: int) -> bool:
	return y % cells_per_floor == 0


# ============================================
# MÉTODOS PARA VISUALIZACIÓN
# ============================================

## Obtiene los 4 vértices de la base de una celda específica (en el plano XZ)
## Retorna un Array de 4 Vector3 que forman la base de la celda
func get_cell_base_vertices(x: int, z: int, y: int) -> Array:
	if y < 0 or y >= cell_positions.size():
		return []
	if z < 0 or z >= rows:
		return []
	if x < 0 or x >= columns:
		return []
	
	# Calcular los pasos de interpolación
	var u_step = 1.0 / max(1, columns) if columns > 0 else 1.0
	var v_step = 1.0 / max(1, rows) if rows > 0 else 1.0
	
	var u = float(x) / max(1, columns)
	var v = float(z) / max(1, rows)
	
	# Calcular las 4 esquinas de la celda usando los vértices del bloque
	# Esquina inferior-izquierda (u, v)
	var corner_bl_2d = (
		vertices[0] * (1 - u) * (1 - v) +
		vertices[1] * u * (1 - v) +
		vertices[2] * u * v +
		vertices[3] * (1 - u) * v
	)
	
	# Esquina inferior-derecha (u + u_step, v)
	var u_next = min(1.0, u + u_step)
	var corner_br_2d = (
		vertices[0] * (1 - u_next) * (1 - v) +
		vertices[1] * u_next * (1 - v) +
		vertices[2] * u_next * v +
		vertices[3] * (1 - u_next) * v
	)
	
	# Esquina superior-derecha (u + u_step, v + v_step)
	var v_next = min(1.0, v + v_step)
	var corner_tr_2d = (
		vertices[0] * (1 - u_next) * (1 - v_next) +
		vertices[1] * u_next * (1 - v_next) +
		vertices[2] * u_next * v_next +
		vertices[3] * (1 - u_next) * v_next
	)
	
	# Esquina superior-izquierda (u, v + v_step)
	var corner_tl_2d = (
		vertices[0] * (1 - u) * (1 - v_next) +
		vertices[1] * u * (1 - v_next) +
		vertices[2] * u * v_next +
		vertices[3] * (1 - u) * v_next
	)
	
	# Convertir a Vector3 con la altura correcta
	var height = y * cell_height
	
	return [
		Vector3(corner_bl_2d.x, height, corner_bl_2d.y),
		Vector3(corner_br_2d.x, height, corner_br_2d.y),
		Vector3(corner_tr_2d.x, height, corner_tr_2d.y),
		Vector3(corner_tl_2d.x, height, corner_tl_2d.y)
	]
