class_name BlockGenerator
extends RefCounted

# Estructura de la grilla 3D
var grid_data: Array = []  # Array[Array[Array[int]]] - [floor][row][column]

# Dimensiones de la manzana
var grid_columns: int = 0
var grid_rows: int = 0
var grid_floors: int = 0  # Cantidad de pisos

# Puntos predefinidos colocados
var predefined_cells: Dictionary = {}  # Vector3i -> int

# Información de la cara (quad skewed)
var face_index: int = -1
var face_vertices: Array[Vector3] = []  # 4 vértices del quad en orden: [v0, v1, v2, v3]
var edge_types: Array[int] = []  # Tipos de los 4 edges: [tipo_edge0, tipo_edge1, tipo_edge2, tipo_edge3]
var floor_height: float = 3.0  # Altura de cada piso en unidades del mundo

# Valores posibles para las celdas
enum CellType {
	EMPTY = 0,
	DELIVERY_FACILITY = 1,
	DELIVERY_POINT = 2,
	GAS_STATION = 3,
	STORE = 4,
}


func generate_block_grid(
	grid_size: int,  # para columnas y filas
	floors: int = 1,  # cantidad de pisos (por defecto 1)
	generation_seed: int = 0,
	predefined_counts: Dictionary = {},  # CellType -> int (cantidad de cada tipo)
	predefined_floor: int = 0,  # Piso donde colocar los puntos predefinidos (por defecto planta baja)
	# Nuevos parámetros para información de la cara
	p_face_index: int = -1,
	p_face_vertices: Array = [],  # Array de Vector3
	p_edge_types: Array = [],  # Array de int
	p_floor_height: float = 3.0
) -> void:
	seed(generation_seed)
	
	# Configurar dimensiones
	grid_columns = grid_size
	grid_rows = grid_size
	grid_floors = floors
	
	# Guardar información de la cara
	face_index = p_face_index
	floor_height = p_floor_height
	
	# Convertir y guardar vértices
	face_vertices.clear()
	for vertex in p_face_vertices:
		if vertex is Vector3:
			face_vertices.append(vertex)
	
	# Guardar tipos de edges
	edge_types.clear()
	for edge_type in p_edge_types:
		edge_types.append(edge_type)
	
	# Inicializar la grilla 3D con valores vacíos
	grid_data.clear()
	predefined_cells.clear()
	
	for floor in range(grid_floors):
		var floor_grid: Array = []
		for row in range(grid_rows):
			var row_array: Array = []
			for col in range(grid_columns):
				row_array.append(CellType.EMPTY)
			floor_grid.append(row_array)
		grid_data.append(floor_grid)
	
	# Colocar puntos predefinidos aleatoriamente en el piso especificado
	_place_predefined_cells(predefined_counts, predefined_floor)
	
	# Aquí irá tu lógica de Wave Function Collapse
	# _wave_function_collapse()


func _place_predefined_cells(counts: Dictionary, target_floor: int) -> void:
	"""Coloca aleatoriamente la cantidad especificada de cada tipo de celda en un piso específico"""
	# Validar que el piso objetivo esté dentro de los límites
	if target_floor < 0 or target_floor >= grid_floors:
		push_warning("El piso objetivo ", target_floor, " está fuera de los límites (0-", grid_floors - 1, ")")
		return
	
	# Crear lista de todas las posiciones disponibles SOLO en el piso objetivo
	var available_positions: Array[Vector3i] = []
	for row in range(grid_rows):
		for col in range(grid_columns):
			available_positions.append(Vector3i(col, row, target_floor))
	
	# Mezclar aleatoriamente las posiciones
	available_positions.shuffle()
	
	var position_index: int = 0
	
	# Colocar cada tipo de celda
	for cell_type in counts:
		var count: int = counts[cell_type]
		
		for i in range(count):
			if position_index >= available_positions.size():
				push_warning("No hay suficientes posiciones disponibles en el piso ", target_floor, " para todos los puntos predefinidos")
				return
			
			var pos: Vector3i = available_positions[position_index]
			set_cell(pos, cell_type)
			predefined_cells[pos] = cell_type
			position_index += 1


func set_cell(coord: Vector3i, value: int) -> void:
	"""Establece el valor de una celda en la posición dada"""
	if _is_valid_position(coord):
		grid_data[coord.z][coord.y][coord.x] = value


func get_cell(coord: Vector3i) -> int:
	"""Obtiene el valor de una celda en la posición dada"""
	if _is_valid_position(coord):
		return grid_data[coord.z][coord.y][coord.x]
	return -1  # Valor inválido


func _is_valid_position(coord: Vector3i) -> bool:
	"""Verifica si una posición está dentro de los límites de la grilla"""
	return (coord.x >= 0 and coord.x < grid_columns and
			coord.y >= 0 and coord.y < grid_rows and
			coord.z >= 0 and coord.z < grid_floors)


func get_neighbors(coord: Vector3i, include_vertical: bool = false) -> Array[Vector3i]:
	"""Obtiene las celdas vecinas (útil para Wave Function Collapse)"""
	var neighbors: Array[Vector3i] = []
	
	# Vecinos horizontales (misma altura)
	var horizontal_offsets = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0)
	]
	
	for offset in horizontal_offsets:
		var neighbor_pos = coord + offset
		if _is_valid_position(neighbor_pos):
			neighbors.append(neighbor_pos)
	
	# Vecinos verticales (piso arriba/abajo)
	if include_vertical:
		for dz in [-1, 1]:
			var neighbor_pos = coord + Vector3i(0, 0, dz)
			if _is_valid_position(neighbor_pos):
				neighbors.append(neighbor_pos)
	
	return neighbors


func get_predefined_positions() -> Dictionary:
	"""Retorna un diccionario con las posiciones de las celdas predefinidas"""
	return predefined_cells.duplicate()


func is_cell_predefined(coord: Vector3i) -> bool:
	"""Verifica si una celda fue colocada como predefinida"""
	return predefined_cells.has(coord)


func get_cells_on_floor(floor: int) -> Array[Vector3i]:
	"""Retorna todas las posiciones de celdas en un piso específico"""
	var cells: Array[Vector3i] = []
	
	if floor < 0 or floor >= grid_floors:
		return cells
	
	for row in range(grid_rows):
		for col in range(grid_columns):
			cells.append(Vector3i(col, row, floor))
	
	return cells


func get_occupied_cells_on_floor(floor: int) -> Array[Vector3i]:
	"""Retorna todas las posiciones de celdas ocupadas (no EMPTY) en un piso específico"""
	var cells: Array[Vector3i] = []
	
	if floor < 0 or floor >= grid_floors:
		return cells
	
	for row in range(grid_rows):
		for col in range(grid_columns):
			var coord = Vector3i(col, row, floor)
			if get_cell(coord) != CellType.EMPTY:
				cells.append(coord)
	
	return cells


func count_cells_by_type_on_floor(floor: int) -> Dictionary:
	"""Cuenta cuántas celdas de cada tipo hay en un piso específico"""
	var counts = {
		CellType.EMPTY: 0,
		CellType.DELIVERY_FACILITY: 0,
		CellType.DELIVERY_POINT: 0,
		CellType.GAS_STATION: 0,
		CellType.STORE: 0,
	}
	
	if floor < 0 or floor >= grid_floors:
		return counts
	
	for row in range(grid_rows):
		for col in range(grid_columns):
			var cell_type = get_cell(Vector3i(col, row, floor))
			if cell_type in counts:
				counts[cell_type] += 1
	
	return counts


## Obtiene las 4 esquinas de la cara inferior de una celda en el espacio 3D
## Retorna un Array[Vector3] con las posiciones en orden: [v0, v1, v2, v3]
## donde v0 es esquina inferior-izquierda, v1 inferior-derecha, v2 superior-derecha, v3 superior-izquierda
func get_cell_bottom_corners(col: int, row: int, floor: int) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	
	# Verificar que tenemos información de la cara
	if face_vertices.size() != 4:
		push_warning("No hay información de vértices de la cara")
		return corners
	
	# Verificar que la celda está dentro de los límites
	if not _is_valid_position(Vector3i(col, row, floor)):
		push_warning("Posición de celda fuera de límites")
		return corners
	
	# Calcular las coordenadas normalizadas (u, v) de las 4 esquinas de la celda
	# u va de 0 a 1 en la dirección de las columnas (X)
	# v va de 0 a 1 en la dirección de las filas (Y)
	var u0 = float(col) / float(grid_columns)
	var u1 = float(col + 1) / float(grid_columns)
	var v0 = float(row) / float(grid_rows)
	var v1 = float(row + 1) / float(grid_rows)
	
	# Altura base de este piso
	var base_height = floor * floor_height
	
	# Calcular las 4 esquinas usando interpolación bilineal en el quad skewed
	# Orden: v0 (bottom-left), v1 (bottom-right), v2 (top-right), v3 (top-left)
	var corner_bottom_left = _interpolate_quad(u0, v0)
	var corner_bottom_right = _interpolate_quad(u1, v0)
	var corner_top_right = _interpolate_quad(u1, v1)
	var corner_top_left = _interpolate_quad(u0, v1)
	
	# Ajustar la altura Z de cada esquina
	corner_bottom_left.z += base_height
	corner_bottom_right.z += base_height
	corner_top_right.z += base_height
	corner_top_left.z += base_height
	
	# Agregar en orden
	corners.append(corner_bottom_left)
	corners.append(corner_bottom_right)
	corners.append(corner_top_right)
	corners.append(corner_top_left)
	
	return corners


## Interpola un punto dentro del quad skewed usando coordenadas normalizadas (u, v)
## u, v están en el rango [0, 1]
## Asume que face_vertices tiene 4 vértices en orden: [v0, v1, v2, v3]
## donde v0 es bottom-left, v1 es bottom-right, v2 es top-right, v3 es top-left
func _interpolate_quad(u: float, v: float) -> Vector3:
	var v0 = face_vertices[0]  # bottom-left
	var v1 = face_vertices[1]  # bottom-right
	var v2 = face_vertices[2]  # top-right
	var v3 = face_vertices[3]  # top-left
	
	# Interpolación bilineal:
	# P(u,v) = (1-u)(1-v)v0 + u(1-v)v1 + uv*v2 + (1-u)v*v3
	var result = Vector3.ZERO
	result += v0 * (1.0 - u) * (1.0 - v)
	result += v1 * u * (1.0 - v)
	result += v2 * u * v
	result += v3 * (1.0 - u) * v
	
	return result


## Obtiene el tipo de edge de un lado específico de la cara
## side: 0 (bottom), 1 (right), 2 (top), 3 (left)
func get_edge_type(side: int) -> int:
	if side >= 0 and side < edge_types.size():
		return edge_types[side]
	return -1


## Obtiene todos los tipos de edges de la cara
func get_all_edge_types() -> Array[int]:
	return edge_types.duplicate()


## Obtiene el índice de la cara asociada a este BlockGenerator
func get_face_index() -> int:
	return face_index


## Obtiene los vértices de la cara
func get_face_vertices() -> Array[Vector3]:
	return face_vertices.duplicate()


## Calcula el área aproximada de una celda
## Útil para determinar el tamaño relativo de las celdas
func get_cell_area(col: int, row: int, floor: int) -> float:
	var corners = get_cell_bottom_corners(col, row, floor)
	
	if corners.size() != 4:
		return 0.0
	
	# Calcular área del quad usando la fórmula del producto cruzado
	# Dividir el quad en dos triángulos y sumar sus áreas
	var v0 = corners[0]
	var v1 = corners[1]
	var v2 = corners[2]
	var v3 = corners[3]
	
	# Triángulo 1: v0, v1, v2
	var edge1_1 = v1 - v0
	var edge1_2 = v2 - v0
	var area1 = edge1_1.cross(edge1_2).length() * 0.5
	
	# Triángulo 2: v0, v2, v3
	var edge2_1 = v2 - v0
	var edge2_2 = v3 - v0
	var area2 = edge2_1.cross(edge2_2).length() * 0.5
	
	return area1 + area2


## Obtiene el centro de una celda en el espacio 3D
func get_cell_center(col: int, row: int, floor: int) -> Vector3:
	var corners = get_cell_bottom_corners(col, row, floor)
	
	if corners.size() != 4:
		return Vector3.ZERO
	
	# El centro es el promedio de las 4 esquinas
	var center = Vector3.ZERO
	for corner in corners:
		center += corner
	center /= 4.0
	
	# Ajustar al centro vertical de la celda (medio del piso)
	center.z += floor_height * 0.5
	
	return center
