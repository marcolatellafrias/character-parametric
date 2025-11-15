class_name BlockGenerator
extends RefCounted

# Tipos de celdas
enum CellType {
	EMPTY = 0,
	DELIVERY_FACILITY = 1,
	DELIVERY_POINT = 2,
	GAS_STATION = 3,
	STORE = 4,
}

# Tipos de calles (para referencia)
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

# Grilla 3D: [x][z][y] -> CellType
var grid: Array = []

# Información de las celdas
var cell_positions: Array = []  # Posiciones 3D de cada celda
var street_cells: Array = []    # Celdas ocupadas por calles (no edificables)

# Anchos de calles según tipo (en porcentaje del lado de la manzana)
const STREET_WIDTHS = {
	StreetType.BOUNDARY: 0.0,
	StreetType.SMALL: 0.15,
	StreetType.MEDIUM: 0.25,
	StreetType.LARGE: 0.35,
	StreetType.SMALL_TUNNEL: 0.10,
	StreetType.LARGE_TUNNEL: 0.20,
}

func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_street_types: Array[int],
	p_cell_height: float,
	p_floors: int,
	p_cells_per_floor: int,
	p_interest_points: Dictionary = {}
) -> void:
	rows = p_rows
	columns = p_columns
	vertices = p_vertices
	street_types = p_street_types
	cell_height = p_cell_height
	floors = p_floors
	cells_per_floor = p_cells_per_floor
	
	_initialize_grid()
	_calculate_cell_positions()
	_mark_street_cells()
	_place_interest_points(p_interest_points)

# Inicializa la grilla 3D con celdas vacías
func _initialize_grid() -> void:
	grid.clear()
	var total_height = floors * cells_per_floor
	
	for x in range(columns):
		var grid_x = []
		for z in range(rows):
			var grid_z = []
			for y in range(total_height):
				grid_z.append(CellType.EMPTY)
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

# Marca las celdas que están ocupadas por calles (mitad del ancho de cada calle)
func _mark_street_cells() -> void:
	street_cells.clear()
	
	# North street (z = 0)
	var north_width = STREET_WIDTHS.get(street_types[0], 0.15)
	var north_cells = max(1, int(rows * north_width * 0.5))
	
	# South street (z = rows-1)
	var south_width = STREET_WIDTHS.get(street_types[2], 0.15)
	var south_cells = max(1, int(rows * south_width * 0.5))
	
	# West street (x = 0)
	var west_width = STREET_WIDTHS.get(street_types[3], 0.15)
	var west_cells = max(1, int(columns * west_width * 0.5))
	
	# East street (x = columns-1)
	var east_width = STREET_WIDTHS.get(street_types[1], 0.15)
	var east_cells = max(1, int(columns * east_width * 0.5))
	
	# Marcar celdas de calles
	for x in range(columns):
		for z in range(rows):
			var is_street = false
			
			# North border
			if z < north_cells:
				is_street = true
			# South border
			elif z >= rows - south_cells:
				is_street = true
			# West border
			elif x < west_cells:
				is_street = true
			# East border
			elif x >= columns - east_cells:
				is_street = true
			
			if is_street:
				street_cells.append(Vector2i(x, z))

# Coloca los puntos de interés en la grilla
func _place_interest_points(interest_points: Dictionary) -> void:
	if interest_points.is_empty():
		return
	
	# Obtener celdas disponibles (no calles) en el inicio de cada piso
	var available_cells = _get_available_cells_at_floor_starts()
	
	if available_cells.is_empty():
		push_warning("BlockGenerator: No hay celdas disponibles para puntos de interés")
		return
	
	# Colocar cada tipo de punto de interés
	for point_type in interest_points:
		var count = interest_points[point_type]
		
		for i in range(count):
			if available_cells.is_empty():
				push_warning("BlockGenerator: Se acabaron las celdas disponibles")
				break
			
			# Seleccionar celda aleatoria
			var random_idx = randi() % available_cells.size()
			var cell_pos = available_cells[random_idx]
			available_cells.remove_at(random_idx)
			
			# Colocar punto de interés (mapear desde InterestPointType a CellType)
			var cell_type = _map_interest_point_to_cell_type(point_type)
			grid[cell_pos.x][cell_pos.z][cell_pos.y] = cell_type

# Obtiene las celdas disponibles en el inicio de cada piso
func _get_available_cells_at_floor_starts() -> Array:
	var available = []
	
	for floor in range(floors):
		var y = floor * cells_per_floor  # Inicio de cada piso
		
		for x in range(columns):
			for z in range(rows):
				# Verificar que no sea una celda de calle
				if not Vector2i(x, z) in street_cells:
					available.append(Vector3i(x, z, y))
	
	return available

# Mapea InterestPointType a CellType
func _map_interest_point_to_cell_type(interest_point_type: int) -> CellType:
	match interest_point_type:
		0: return CellType.DELIVERY_FACILITY  # DELIVERY_FACILITY
		1: return CellType.DELIVERY_POINT     # DELIVERY_POINT
		2: return CellType.GAS_STATION        # GAS_STATION
		3: return CellType.STORE              # STORE
		_: return CellType.EMPTY

# Obtiene el tipo de celda en una posición
func get_cell(x: int, z: int, y: int) -> CellType:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return CellType.EMPTY
	
	var total_height = floors * cells_per_floor
	if y < 0 or y >= total_height:
		return CellType.EMPTY
	
	return grid[x][z][y]

# Establece el tipo de celda en una posición
func set_cell(x: int, z: int, y: int, cell_type: CellType) -> void:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return
	
	var total_height = floors * cells_per_floor
	if y < 0 or y >= total_height:
		return
	
	grid[x][z][y] = cell_type

# Obtiene la posición 3D de una celda
func get_cell_position(x: int, z: int, y: int) -> Vector3:
	if y < 0 or y >= cell_positions.size():
		return Vector3.ZERO
	if z < 0 or z >= cell_positions[y].size():
		return Vector3.ZERO
	if x < 0 or x >= cell_positions[y][z].size():
		return Vector3.ZERO
	
	return cell_positions[y][z][x]

# Verifica si una celda es una calle
func is_street_cell(x: int, z: int) -> bool:
	return Vector2i(x, z) in street_cells

# Obtiene todas las celdas de un tipo específico
func get_cells_by_type(cell_type: CellType) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var total_height = floors * cells_per_floor
	
	for x in range(columns):
		for z in range(rows):
			for y in range(total_height):
				if grid[x][z][y] == cell_type:
					cells.append(Vector3i(x, z, y))
	
	return cells

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

## Obtiene todas las celdas no vacías con su información
## Retorna un Array de diccionarios con formato:
## {cell_type: CellType, position: Vector3i, base_vertices: Array, height: float}
func get_non_empty_cells() -> Array:
	var result = []
	var total_height = floors * cells_per_floor
	
	for x in range(columns):
		for z in range(rows):
			for y in range(total_height):
				var cell_type = grid[x][z][y]
				
				if cell_type != CellType.EMPTY:
					var base_verts = get_cell_base_vertices(x, z, y)
					
					result.append({
						"cell_type": cell_type,
						"position": Vector3i(x, z, y),
						"base_vertices": base_verts,
						"height": cell_height
					})
	
	return result

## Obtiene información de una celda específica para visualización
## Retorna un diccionario con la información de la celda o un diccionario vacío si no existe
func get_cell_visual_info(x: int, z: int, y: int) -> Dictionary:
	var cell_type = get_cell(x, z, y)
	
	if cell_type == CellType.EMPTY:
		return {}
	
	var base_verts = get_cell_base_vertices(x, z, y)
	
	return {
		"cell_type": cell_type,
		"position": Vector3i(x, z, y),
		"base_vertices": base_verts,
		"height": cell_height
	}
