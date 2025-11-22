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
	StreetType.SMALL: 1,
	StreetType.MEDIUM: 2,
	StreetType.LARGE: 3,
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
var max_divisions: int = 4  # Número máximo de divisiones recursivas
var random: RandomNumberGenerator = RandomNumberGenerator.new()


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
# GENERACIÓN DE RECTÁNGULOS (BSP)
# ============================================

# Genera rectángulos dividiendo recursivamente el área disponible
func generate_rectangles(p_max_divisions: int = 4, p_min_size: int = 2, seed_value: int = -1) -> void:
	max_divisions = p_max_divisions
	min_rectangle_size = p_min_size
	rectangles.clear()
	next_rectangle_id = 1
	
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	
	# Calcular área disponible
	var start_x = available_min_x
	var start_z = available_min_z
	var width = available_max_x - available_min_x + 1
	var height = available_max_z - available_min_z + 1
	
	# Comenzar la división recursiva
	_divide_space(start_x, start_z, width, height, 0)
	
	# Aplicar los rectángulos a la grilla (en todos los pisos)
	_apply_rectangles_to_grid()


# Divide recursivamente un espacio en rectángulos
func _divide_space(x: int, z: int, width: int, height: int, depth: int) -> void:
	# Si alcanzamos la profundidad máxima o el espacio es muy pequeño, crear un rectángulo
	if depth >= max_divisions or width < min_rectangle_size * 2 or height < min_rectangle_size * 2:
		var rect = GridRectangle.new(x, z, width, height, next_rectangle_id)
		rectangles.append(rect)
		next_rectangle_id += 1
		return
	
	# Decidir si dividir horizontal o verticalmente
	var divide_horizontally: bool
	
	if width > height * 1.25:
		divide_horizontally = false  # Dividir verticalmente si es muy ancho
	elif height > width * 1.25:
		divide_horizontally = true  # Dividir horizontalmente si es muy alto
	else:
		divide_horizontally = random.randf() > 0.5  # Aleatorio si es similar
	
	if divide_horizontally:
		# Dividir horizontalmente (línea paralela al eje X)
		var split_z = _find_valid_split(z, height, true)
		if split_z == -1:
			# No se pudo dividir, crear rectángulo
			var rect = GridRectangle.new(x, z, width, height, next_rectangle_id)
			rectangles.append(rect)
			next_rectangle_id += 1
			return
		
		var height1 = split_z - z
		var height2 = height - height1
		
		_divide_space(x, z, width, height1, depth + 1)
		_divide_space(x, split_z, width, height2, depth + 1)
	else:
		# Dividir verticalmente (línea paralela al eje Z)
		var split_x = _find_valid_split(x, width, false)
		if split_x == -1:
			# No se pudo dividir, crear rectángulo
			var rect = GridRectangle.new(x, z, width, height, next_rectangle_id)
			rectangles.append(rect)
			next_rectangle_id += 1
			return
		
		var width1 = split_x - x
		var width2 = width - width1
		
		_divide_space(x, z, width1, height, depth + 1)
		_divide_space(split_x, z, width2, height, depth + 1)


# Encuentra un punto de división válido (que deje al menos min_rectangle_size en cada lado)
func _find_valid_split(start: int, size: int, is_horizontal: bool) -> int:
	const MAX_ATTEMPTS = 50
	
	for attempt in range(MAX_ATTEMPTS):
		# Rango válido: [start + min_size, start + size - min_size]
		var min_pos = start + min_rectangle_size
		var max_pos = start + size - min_rectangle_size
		
		if min_pos >= max_pos:
			return -1  # No hay espacio suficiente para dividir
		
		var split_pos = random.randi_range(min_pos, max_pos)
		
		# Verificar que ambos lados tengan al menos min_rectangle_size
		var size1 = split_pos - start
		var size2 = size - size1
		
		if size1 >= min_rectangle_size and size2 >= min_rectangle_size:
			return split_pos
	
	return -1  # No se encontró un punto válido después de MAX_ATTEMPTS


# Aplica los rectángulos generados a la grilla 3D
func _apply_rectangles_to_grid() -> void:
	var total_height = floors * cells_per_floor
	
	for rect in rectangles:
		# Aplicar el rectángulo en todos los niveles de altura
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
