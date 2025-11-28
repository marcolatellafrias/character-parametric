class_name GridGeometry extends RefCounted

# Estructura de la grilla
var rows: int
var columns: int
var cell_height: float
var floors: int
var cells_per_floor: int

# Geometría del bloque
var vertices: Array[Vector2]  # [top_left, top_right, bottom_right, bottom_left]

# Grilla 3D: [x][z][y] -> int (0 = vacío/calle, >0 = ID de rectángulo)
var grid: Array = []

# Información de las celdas
var cell_positions: Array = []  # Posiciones 3D de cada celda


func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_cell_height: float,
	p_floors: int,
	p_cells_per_floor: int
) -> void:
	rows = p_rows
	columns = p_columns
	vertices = p_vertices
	cell_height = p_cell_height
	floors = p_floors
	cells_per_floor = p_cells_per_floor
	
	_initialize_grid()
	_calculate_cell_positions()


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
				var u = float(x) / max(1, columns - 1)
				var v = float(z) / max(1, rows - 1)
				
				var pos_2d = (
					vertices[0] * (1 - u) * (1 - v) +
					vertices[1] * u * (1 - v) +
					vertices[2] * u * v +
					vertices[3] * (1 - u) * v
				)
				
				var pos_3d = Vector3(pos_2d.x, height, pos_2d.y)
				row_positions.append(pos_3d)
			
			positions_2d.append(row_positions)
		cell_positions.append(positions_2d)


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


# Obtiene los 4 vértices de la base de una celda específica
func get_cell_base_vertices(x: int, z: int, y: int) -> Array:
	if y < 0 or y >= cell_positions.size():
		return []
	if z < 0 or z >= rows:
		return []
	if x < 0 or x >= columns:
		return []
	
	var u_step = 1.0 / max(1, columns) if columns > 0 else 1.0
	var v_step = 1.0 / max(1, rows) if rows > 0 else 1.0
	
	var u = float(x) / max(1, columns)
	var v = float(z) / max(1, rows)
	
	var corner_bl_2d = (
		vertices[0] * (1 - u) * (1 - v) +
		vertices[1] * u * (1 - v) +
		vertices[2] * u * v +
		vertices[3] * (1 - u) * v
	)
	
	var u_next = min(1.0, u + u_step)
	var corner_br_2d = (
		vertices[0] * (1 - u_next) * (1 - v) +
		vertices[1] * u_next * (1 - v) +
		vertices[2] * u_next * v +
		vertices[3] * (1 - u_next) * v
	)
	
	var v_next = min(1.0, v + v_step)
	var corner_tr_2d = (
		vertices[0] * (1 - u_next) * (1 - v_next) +
		vertices[1] * u_next * (1 - v_next) +
		vertices[2] * u_next * v_next +
		vertices[3] * (1 - u_next) * v_next
	)
	
	var corner_tl_2d = (
		vertices[0] * (1 - u) * (1 - v_next) +
		vertices[1] * u * (1 - v_next) +
		vertices[2] * u * v_next +
		vertices[3] * (1 - u) * v_next
	)
	
	var height = y * cell_height
	
	return [
		Vector3(corner_bl_2d.x, height, corner_bl_2d.y),
		Vector3(corner_br_2d.x, height, corner_br_2d.y),
		Vector3(corner_tr_2d.x, height, corner_tr_2d.y),
		Vector3(corner_tl_2d.x, height, corner_tl_2d.y)
	]
