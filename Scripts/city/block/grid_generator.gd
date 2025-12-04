class_name GridGeometry extends RefCounted

# Estructura de la grilla
var rows: int
var columns: int
var cell_height: float
var floors: int
var cells_per_floor: int

# Geometría del bloque
var vertices: Array[Vector2]  # [top_left, top_right, bottom_right, bottom_left]

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
	
	_calculate_cell_positions()


# Calcula las posiciones 3D de cada celda usando GridHelper
func _calculate_cell_positions() -> void:
	cell_positions.clear()
	var total_height = floors * cells_per_floor
	
	for y in range(total_height):
		var height = y * cell_height
		var positions_2d = []
		
		for z in range(rows):
			var row_positions = []
			for x in range(columns):
				var pos_2d = GridHelper.get_cell_position_2d(vertices, rows, columns, x, z)
				var pos_3d = Vector3(pos_2d.x, height, pos_2d.y)
				row_positions.append(pos_3d)
			
			positions_2d.append(row_positions)
		cell_positions.append(positions_2d)


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


# Obtiene los 4 vértices de la base de una celda específica usando GridHelper
func get_cell_base_vertices(x: int, z: int, y: int) -> Array:
	if y < 0 or y >= cell_positions.size():
		return []
	if z < 0 or z >= rows:
		return []
	if x < 0 or x >= columns:
		return []
	
	var vertices_3d = GridHelper.get_cell_base_vertices(vertices, rows, columns, x, z)
	
	var height = y * cell_height
	var adjusted_vertices = []
	
	for vertex in vertices_3d:
		adjusted_vertices.append(Vector3(vertex.x, height, vertex.z))
	
	return adjusted_vertices
