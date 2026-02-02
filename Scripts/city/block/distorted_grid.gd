class_name DistortedGrid extends RefCounted

# Tipos de celdas
enum CellType {
	NORMAL = 0,
	SMALL = 1,
	BIG = 2,
	FACADE = -1,  # CAMBIO: era BOUNDARY
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


## Retorna los 4 vértices de una celda en orden: [BL, BR, TR, TL]
func get_cell_vertices(x: int, z: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return result
	
	# Calcular explícitamente cada vértice en el orden correcto
	# Bottom-Left: (x, z)
	var bl_pos = _calculate_vertex_at(x, z)
	result.append(Vector3(bl_pos.x, 0.0, bl_pos.y))
	
	# Bottom-Right: (x+1, z)
	var br_pos = _calculate_vertex_at(x + 1, z)
	result.append(Vector3(br_pos.x, 0.0, br_pos.y))
	
	# Top-Right: (x+1, z+1)
	var tr_pos = _calculate_vertex_at(x + 1, z + 1)
	result.append(Vector3(tr_pos.x, 0.0, tr_pos.y))
	
	# Top-Left: (x, z+1)
	var tl_pos = _calculate_vertex_at(x, z + 1)
	result.append(Vector3(tl_pos.x, 0.0, tl_pos.y))
	
	return result


## Calcula la posición distorsionada de un vértice en coordenadas de grilla
func _calculate_vertex_at(grid_x: int, grid_z: int) -> Vector2:
	var u = float(grid_x) / max(1, columns)
	var v = float(grid_z) / max(1, rows)
	
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
	
	return base_pos + local_u_dir * wave_offset_u + local_v_dir * wave_offset_v

## Retorna información sobre los edges conectados a un vértice específico de una celda
## vertex_index: 0=BL, 1=BR, 2=TR, 3=TL
## Retorna Dictionary con:
##   - vertex: Vector2i (posición del vértice en coordenadas de grilla)
##   - corner_edges: Array[Dictionary] (edges que son parte de la celda)
##   - secondary_edges: Array[Dictionary] (edges conectados al vértice pero no parte de la celda)
## Cada edge es: {"v1": Vector2i, "v2": Vector2i}
func get_vertex_edges_info(cell_x: int, cell_z: int, vertex_index: int) -> Dictionary:
	if cell_x < 0 or cell_x >= columns or cell_z < 0 or cell_z >= rows:
		return {"vertex": Vector2i(-1, -1), "corner_edges": [], "secondary_edges": []}
	
	if vertex_index < 0 or vertex_index > 3:
		return {"vertex": Vector2i(-1, -1), "corner_edges": [], "secondary_edges": []}
	
	var vertex_pos = _get_vertex_grid_position(cell_x, cell_z, vertex_index)
	var all_edges = _get_edges_connected_to_vertex(vertex_pos)
	
	var corner_edges: Array = []
	var secondary_edges: Array = []
	
	for edge in all_edges:
		if _is_edge_part_of_cell(edge, cell_x, cell_z):
			corner_edges.append(edge)
		else:
			secondary_edges.append(edge)
	
	return {
		"vertex": vertex_pos,
		"corner_edges": corner_edges,
		"secondary_edges": secondary_edges
	}


## Convierte el índice de vértice a posición en coordenadas de grilla
func _get_vertex_grid_position(cell_x: int, cell_z: int, vertex_index: int) -> Vector2i:
	match vertex_index:
		0:  # BL
			return Vector2i(cell_x, cell_z)
		1:  # BR
			return Vector2i(cell_x + 1, cell_z)
		2:  # TR
			return Vector2i(cell_x + 1, cell_z + 1)
		3:  # TL
			return Vector2i(cell_x, cell_z + 1)
		_:
			return Vector2i(-1, -1)


## Retorna todos los edges que conectan a un vértice (hasta 4: arriba, abajo, izquierda, derecha)
func _get_edges_connected_to_vertex(vertex: Vector2i) -> Array:
	var edges: Array = []
	
	# Edge horizontal izquierda: de (x-1, z) a (x, z)
	if vertex.x > 0:
		edges.append({
			"v1": Vector2i(vertex.x - 1, vertex.y),
			"v2": vertex
		})
	
	# Edge horizontal derecha: de (x, z) a (x+1, z)
	if vertex.x < columns:
		edges.append({
			"v1": vertex,
			"v2": Vector2i(vertex.x + 1, vertex.y)
		})
	
	# Edge vertical arriba: de (x, z-1) a (x, z)
	if vertex.y > 0:
		edges.append({
			"v1": Vector2i(vertex.x, vertex.y - 1),
			"v2": vertex
		})
	
	# Edge vertical abajo: de (x, z) a (x, z+1)
	if vertex.y < rows:
		edges.append({
			"v1": vertex,
			"v2": Vector2i(vertex.x, vertex.y + 1)
		})
	
	return edges


## Verifica si un edge es parte de los 4 edges de una celda específica
func _is_edge_part_of_cell(edge: Dictionary, cell_x: int, cell_z: int) -> bool:
	var v1: Vector2i = edge["v1"]
	var v2: Vector2i = edge["v2"]
	
	# Edge norte: de (x, z) a (x+1, z)
	if v1 == Vector2i(cell_x, cell_z) and v2 == Vector2i(cell_x + 1, cell_z):
		return true
	if v2 == Vector2i(cell_x, cell_z) and v1 == Vector2i(cell_x + 1, cell_z):
		return true
	
	# Edge este: de (x+1, z) a (x+1, z+1)
	if v1 == Vector2i(cell_x + 1, cell_z) and v2 == Vector2i(cell_x + 1, cell_z + 1):
		return true
	if v2 == Vector2i(cell_x + 1, cell_z) and v1 == Vector2i(cell_x + 1, cell_z + 1):
		return true
	
	# Edge sur: de (x, z+1) a (x+1, z+1)
	if v1 == Vector2i(cell_x, cell_z + 1) and v2 == Vector2i(cell_x + 1, cell_z + 1):
		return true
	if v2 == Vector2i(cell_x, cell_z + 1) and v1 == Vector2i(cell_x + 1, cell_z + 1):
		return true
	
	# Edge oeste: de (x, z) a (x, z+1)
	if v1 == Vector2i(cell_x, cell_z) and v2 == Vector2i(cell_x, cell_z + 1):
		return true
	if v2 == Vector2i(cell_x, cell_z) and v1 == Vector2i(cell_x, cell_z + 1):
		return true
	
	return false

## Determina si un vértice en coordenadas de grilla es una esquina de calle
## Un vértice se considera esquina de calle si no tiene edges secundarios
## (es decir, está en el perímetro exterior del grid)
## grid_x, grid_z: coordenadas del vértice (no de celda)
func is_street_corner_vertex(grid_x: int, grid_z: int) -> bool:
	if grid_x < 0 or grid_x > columns or grid_z < 0 or grid_z > rows:
		return false
	
	# Un vértice (grid_x, grid_z) puede ser esquina de hasta 4 celdas:
	# - BL (0) de celda (grid_x, grid_z)
	# - BR (1) de celda (grid_x-1, grid_z)
	# - TR (2) de celda (grid_x-1, grid_z-1)
	# - TL (3) de celda (grid_x, grid_z-1)
	
	# Encontrar la primera celda válida
	var cell_x: int = -1
	var cell_z: int = -1
	var vertex_index: int = -1
	
	# Prioridad: BL -> BR -> TR -> TL
	if grid_x < columns and grid_z < rows:
		# Vértice es BL de esta celda
		cell_x = grid_x
		cell_z = grid_z
		vertex_index = 0
	elif grid_x > 0 and grid_z < rows:
		# Vértice es BR de esta celda
		cell_x = grid_x - 1
		cell_z = grid_z
		vertex_index = 1
	elif grid_x > 0 and grid_z > 0:
		# Vértice es TR de esta celda
		cell_x = grid_x - 1
		cell_z = grid_z - 1
		vertex_index = 2
	elif grid_x < columns and grid_z > 0:
		# Vértice es TL de esta celda
		cell_x = grid_x
		cell_z = grid_z - 1
		vertex_index = 3
	
	if cell_x < 0 or cell_z < 0 or vertex_index < 0:
		return false
	
	var info = get_vertex_edges_info(cell_x, cell_z, vertex_index)
	
	# Es esquina de calle si no tiene secondary edges
	return info["secondary_edges"].is_empty()
	
## Determina si un vértice en coordenadas de grilla es una esquina de callejón
## Un vértice se considera esquina de callejón si tiene exactamente 2 edges secundarios
## (es decir, está en una esquina interior del grid donde se encuentran callejones)
## grid_x, grid_z: coordenadas del vértice (no de celda)
func is_alleyway_corner_vertex(grid_x: int, grid_z: int) -> bool:
	if grid_x < 0 or grid_x > columns or grid_z < 0 or grid_z > rows:
		return false
	
	# Encontrar una celda adyacente válida para consultar
	var cell_x = grid_x
	var cell_z = grid_z
	var vertex_index = 0  # BL por defecto
	
	# Ajustar para encontrar una celda válida y el índice de vértice correcto
	if grid_x == columns:
		cell_x = columns - 1
		vertex_index = 1 if grid_z < rows else 2  # BR o TR
	
	if grid_z == rows:
		cell_z = rows - 1
		vertex_index = 3 if grid_x == 0 else 2  # TL o TR
	
	if grid_x == columns and grid_z == rows:
		cell_x = columns - 1
		cell_z = rows - 1
		vertex_index = 2  # TR
	elif grid_x == 0 and grid_z == rows:
		cell_x = 0
		cell_z = rows - 1
		vertex_index = 3  # TL
	elif grid_x == columns and grid_z == 0:
		cell_x = columns - 1
		cell_z = 0
		vertex_index = 1  # BR
	
	# Verificar que la celda sea válida
	if cell_x < 0 or cell_x >= columns or cell_z < 0 or cell_z >= rows:
		return false
	
	var info = get_vertex_edges_info(cell_x, cell_z, vertex_index)
	
	# Es esquina de callejón si tiene exactamente 2 secondary edges
	return info["secondary_edges"].size() == 2
