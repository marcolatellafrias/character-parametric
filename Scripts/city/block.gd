class_name BlockGenerator
extends RefCounted

# Tipos de calles
enum StreetType {
	BOUNDARY = -1,
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2,
	SMALL_TUNNEL = 3,
	LARGE_TUNNEL = 4,
}

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

# Constraints de rectángulos
var rect_min_width: int
var rect_max_width: int
var rect_min_depth: int
var rect_max_depth: int

# Área disponible después de offsets
var available_min_x: int
var available_max_x: int
var available_min_z: int
var available_max_z: int

# Rectángulos generados por piso
# Diccionario: floor -> Array de rectángulos
# Cada rectángulo: {id: int, x: int, z: int, width: int, depth: int}
var rectangles_by_floor: Dictionary = {}

# Contador de IDs de rectángulos
var next_rect_id: int = 1

func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_street_types: Array[int],
	p_cell_height: float,
	p_floors: int,
	p_cells_per_floor: int,
	p_rect_min_width: int = 1,
	p_rect_max_width: int = 5,
	p_rect_min_depth: int = 1,
	p_rect_max_depth: int = 5
) -> void:
	rows = p_rows
	columns = p_columns
	vertices = p_vertices
	street_types = p_street_types
	cell_height = p_cell_height
	floors = p_floors
	cells_per_floor = p_cells_per_floor
	rect_min_width = p_rect_min_width
	rect_max_width = p_rect_max_width
	rect_min_depth = p_rect_min_depth
	rect_max_depth = p_rect_max_depth
	
	_initialize_grid()
	_calculate_cell_positions()
	_calculate_available_area()
	_generate_rectangles_all_floors()

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
				var v = float(z) / max(1, rows - 1)     # Normalizado [0, 1]
				
				# Interpolación bilineal: P = (1-u)(1-v)P0 + u(1-v)P1 + uv*P2 + (1-u)v*P3
				var pos_2d = (
					vertices[0] * (1 - u) * (1 - v) +  # top_left
					vertices[1] * u * (1 - v) +        # top_right
					vertices[2] * u * v +              # bottom_right
					vertices[3] * (1 - u) * v          # bottom_left
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

# Genera rectángulos para todos los pisos
func _generate_rectangles_all_floors() -> void:
	rectangles_by_floor.clear()
	
	for floor in range(floors):
		var rectangles = _pack_rectangles_for_floor(floor)
		rectangles_by_floor[floor] = rectangles
		_apply_rectangles_to_grid(rectangles, floor)

# Algoritmo de rectangle packing para un piso específico
func _pack_rectangles_for_floor(floor: int) -> Array:
	var rectangles = []
	var occupied = {}  # Diccionario para marcar celdas ocupadas (key = "x,z")
	
	var available_width = available_max_x - available_min_x + 1
	var available_depth = available_max_z - available_min_z + 1
	
	# Si el área disponible es muy pequeña, no generamos rectángulos
	if available_width < rect_min_width or available_depth < rect_min_depth:
		return rectangles
	
	# Algoritmo greedy: recorrer de arriba a abajo, izquierda a derecha
	for z in range(available_min_z, available_max_z + 1):
		for x in range(available_min_x, available_max_x + 1):
			# Verificar si esta celda ya está ocupada
			var key = str(x) + "," + str(z)
			if occupied.has(key):
				continue
			
			# Encontrar el rectángulo más grande que quepa en esta posición
			var best_rect = _find_best_rectangle_at_position(x, z, occupied)
			
			if best_rect != null:
				# Colocar el rectángulo
				var rect_id = next_rect_id
				next_rect_id += 1
				
				var rectangle = {
					"id": rect_id,
					"x": best_rect["x"],
					"z": best_rect["z"],
					"width": best_rect["width"],
					"depth": best_rect["depth"]
				}
				
				rectangles.append(rectangle)
				_mark_area_occupied(best_rect["x"], best_rect["z"], best_rect["width"], best_rect["depth"], occupied)
	
	return rectangles

# Verifica si un área está libre
func _is_area_free(x: int, z: int, width: int, depth: int, occupied: Dictionary) -> bool:
	for dx in range(width):
		for dz in range(depth):
			var key = str(x + dx) + "," + str(z + dz)
			if occupied.has(key):
				return false
	return true

# Marca un área como ocupada
func _mark_area_occupied(x: int, z: int, width: int, depth: int, occupied: Dictionary) -> void:
	for dx in range(width):
		for dz in range(depth):
			var key = str(x + dx) + "," + str(z + dz)
			occupied[key] = true

# Aplica los rectángulos a la grilla 3D
func _apply_rectangles_to_grid(rectangles: Array, floor: int) -> void:
	var y_start = floor * cells_per_floor
	var y_end = y_start + cells_per_floor
	
	for rect in rectangles:
		var rect_id = rect["id"]
		var rect_x = rect["x"]
		var rect_z = rect["z"]
		var rect_width = rect["width"]
		var rect_depth = rect["depth"]
		
		# Llenar todas las celdas del rectángulo en todas las alturas del piso
		for y in range(y_start, y_end):
			for dx in range(rect_width):
				for dz in range(rect_depth):
					var cell_x = rect_x + dx
					var cell_z = rect_z + dz
					
					if cell_x >= 0 and cell_x < columns and cell_z >= 0 and cell_z < rows:
						grid[cell_x][cell_z][y] = rect_id

# Obtiene el ID del rectángulo en una posición
func get_cell(x: int, z: int, y: int) -> int:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return 0
	
	var total_height = floors * cells_per_floor
	if y < 0 or y >= total_height:
		return 0
	
	return grid[x][z][y]

# Establece el ID del rectángulo en una posición
func set_cell(x: int, z: int, y: int, rect_id: int) -> void:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return
	
	var total_height = floors * cells_per_floor
	if y < 0 or y >= total_height:
		return
	
	grid[x][z][y] = rect_id

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

# Obtiene todos los rectángulos de un piso específico
func get_rectangles_for_floor(floor: int) -> Array:
	return rectangles_by_floor.get(floor, [])

# Obtiene todos los rectángulos de todos los pisos
func get_all_rectangles() -> Array:
	var all_rects = []
	for floor in rectangles_by_floor:
		all_rects.append_array(rectangles_by_floor[floor])
	return all_rects

# Obtiene información de un rectángulo específico por su ID
func get_rectangle_info(rect_id: int) -> Dictionary:
	for floor in rectangles_by_floor:
		for rect in rectangles_by_floor[floor]:
			if rect["id"] == rect_id:
				return rect
	return {}

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

## Obtiene todos los rectángulos con su información visual
## Retorna un Array de diccionarios con formato:
## {rect_id: int, floor: int, base_vertices: Array, height: float, dimensions: Vector2i}
func get_rectangles_visual_info() -> Array:
	var result = []
	
	for floor in range(floors):
		var rectangles = rectangles_by_floor.get(floor, [])
		var y_start = floor * cells_per_floor
		var floor_height = cells_per_floor * cell_height
		
		for rect in rectangles:
			var rect_x = rect["x"]
			var rect_z = rect["z"]
			var rect_width = rect["width"]
			var rect_depth = rect["depth"]
			
			# Obtener los 4 vértices de las esquinas del rectángulo
			var corner_bl = get_cell_base_vertices(rect_x, rect_z, y_start)
			var corner_br = get_cell_base_vertices(rect_x + rect_width - 1, rect_z, y_start)
			var corner_tr = get_cell_base_vertices(rect_x + rect_width - 1, rect_z + rect_depth - 1, y_start)
			var corner_tl = get_cell_base_vertices(rect_x, rect_z + rect_depth - 1, y_start)
			
			if corner_bl.size() == 4 and corner_br.size() == 4 and corner_tr.size() == 4 and corner_tl.size() == 4:
				# Usar las esquinas externas de cada celda para formar el rectángulo completo
				var base_vertices = [
					corner_bl[0],  # bottom-left de la celda bottom-left
					corner_br[1],  # bottom-right de la celda bottom-right
					corner_tr[2],  # top-right de la celda top-right
					corner_tl[3]   # top-left de la celda top-left
				]
				
				result.append({
					"rect_id": rect["id"],
					"floor": floor,
					"base_vertices": base_vertices,
					"height": floor_height,
					"dimensions": Vector2i(rect_width, rect_depth)
				})
	
	return result

# Encuentra el mejor rectángulo que quepa en una posición dada
func _find_best_rectangle_at_position(start_x: int, start_z: int, occupied: Dictionary):
	# Calcular el máximo ancho y profundidad posible desde esta posición
	var max_possible_width = available_max_x - start_x + 1
	var max_possible_depth = available_max_z - start_z + 1
	
	# Limitar por los constraints
	max_possible_width = min(max_possible_width, rect_max_width)
	max_possible_depth = min(max_possible_depth, rect_max_depth)
	
	# Verificar que al menos quepa el tamaño mínimo
	if max_possible_width < rect_min_width or max_possible_depth < rect_min_depth:
		return null
	
	# Intentar encontrar el rectángulo más grande que quepa
	# Primero, determinar el ancho máximo real (considerando obstáculos)
	var actual_max_width = 0
	for w in range(1, max_possible_width + 1):
		var test_x = start_x + w - 1
		if test_x > available_max_x:
			break
		var key = str(test_x) + "," + str(start_z)
		if occupied.has(key):
			break
		actual_max_width = w
	
	if actual_max_width < rect_min_width:
		return null
	
	# Ahora encontrar la profundidad máxima para este ancho
	var actual_max_depth = 0
	for d in range(1, max_possible_depth + 1):
		var test_z = start_z + d - 1
		if test_z > available_max_z:
			break
		
		# Verificar que toda la fila esté libre
		var row_free = true
		for w in range(actual_max_width):
			var test_x = start_x + w
			var key = str(test_x) + "," + str(test_z)
			if occupied.has(key):
				row_free = false
				break
		
		if not row_free:
			break
		
		actual_max_depth = d
	
	if actual_max_depth < rect_min_depth:
		return null
	
	# Generar tamaño aleatorio dentro de los límites posibles
	var rect_width = randi_range(rect_min_width, actual_max_width)
	var rect_depth = randi_range(rect_min_depth, actual_max_depth)
	
	return {
		"x": start_x,
		"z": start_z,
		"width": rect_width,
		"depth": rect_depth
	}
