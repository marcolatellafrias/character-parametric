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
	p_edge_falloff_sharpness: float = 1.0
) -> void:
	rows = p_rows
	columns = p_columns
	vertices = p_vertices
	cell_height = p_cell_height
	
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
	_calculate_distorted_positions()


func _initialize_grid() -> void:
	grid.clear()
	
	for x in range(columns):
		var grid_x = []
		for z in range(rows):
			grid_x.append(CellType.NORMAL)
		grid.append(grid_x)


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
