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

# Valores posibles para las celdas
enum CellType {
	EMPTY = 0,
	DELIVERY_FACILITY = 1,
	DELIVERY_POINT = 1,
	GAS_STATION = 2,
	STORE = 3,
}


func generate_block_grid(
	grid_size: int,  # para columnas y filas
	floors: int = 1,  # cantidad de pisos (por defecto 1)
	generation_seed: int = 0,
	predefined_counts: Dictionary = {}  # CellType -> int (cantidad de cada tipo)
) -> void:
	seed(generation_seed)
	
	# Configurar dimensiones
	grid_columns = grid_size
	grid_rows = grid_size
	grid_floors = floors
	
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
	
	# Colocar puntos predefinidos aleatoriamente
	_place_predefined_cells(predefined_counts)
	
	# Aquí irá tu lógica de Wave Function Collapse
	# _wave_function_collapse()


func _place_predefined_cells(counts: Dictionary) -> void:
	"""Coloca aleatoriamente la cantidad especificada de cada tipo de celda"""
	# Crear lista de todas las posiciones disponibles
	var available_positions: Array[Vector3i] = []
	for floor in range(grid_floors):
		for row in range(grid_rows):
			for col in range(grid_columns):
				available_positions.append(Vector3i(col, row, floor))
	
	# Mezclar aleatoriamente las posiciones
	available_positions.shuffle()
	
	var position_index: int = 0
	
	# Colocar cada tipo de celda
	for cell_type in counts:
		var count: int = counts[cell_type]
		
		for i in range(count):
			if position_index >= available_positions.size():
				push_warning("No hay suficientes posiciones disponibles para todos los puntos predefinidos")
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
