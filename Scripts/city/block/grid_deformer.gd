class_name DistortedGrid extends RefCounted

# Grilla distorsionada con ondas sinusoidales
# 
# IMPORTANTE: La distorsión se aplica en coordenadas LOCALES del quad, no absolutas.
# Esto asegura que la distorsión sea consistente independientemente de:
# - El tamaño del quad
# - La orientación del quad
# - El skew/deformación del quad
#
# Las amplitudes son relativas al tamaño promedio del quad (valores 0.0-1.0)
# Las ondas se aplican siguiendo las direcciones locales U y V del quad
#
# FALLOFF DE BORDES:
# La distorsión se atenúa gradualmente hacia los bordes del quad.
# 
# falloff_strength controla la intensidad de esta atenuación:
# - 1.0 (default): Los bordes no se mueven (distorsión = 0), máxima en el centro
# - 0.5: Los bordes tienen 50% de distorsión, el centro tiene 100%
# - 0.0: Sin falloff, todos los puntos tienen 100% de distorsión (los bordes se mueven)
#
# Esto permite:
# - Mantener los límites exactos del quad (1.0) para que bloques adyacentes encajen
# - O crear efectos más orgánicos con bordes distorsionados (valores menores)

# Estructura de la grilla
var rows: int
var columns: int
var cell_height: float

# Geometría del bloque (core block)
var vertices: Array[Vector2]  # [BL, BR, TR, TL]

# Parámetros de distorsión (amplitudes normalizadas por tamaño del quad)
var wave_amplitude_x: float
var wave_amplitude_z: float
var wave_frequency_x: float
var wave_frequency_z: float
var wave_phase_x: float
var wave_phase_z: float
var edge_falloff_sharpness: float  # Controla qué tan rápido se atenúa hacia los bordes (1.0 = lineal, >1.0 = más abrupto, <1.0 = más suave)

# Tipos de bordes [north, east, south, west]
# -1 = boundary, 0 = normal
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
	# Considerar todos los lados para quads skewed
	var bottom_width = (vertices[1] - vertices[0]).length()  # BL -> BR
	var top_width = (vertices[2] - vertices[3]).length()     # TL -> TR
	var left_height = (vertices[3] - vertices[0]).length()   # BL -> TL
	var right_height = (vertices[2] - vertices[1]).length()  # BR -> TR
	
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


# Inicializa la grilla 2D
func _initialize_grid() -> void:
	grid.clear()
	
	for x in range(columns):
		var grid_x = []
		for z in range(rows):
			grid_x.append(0)
		grid.append(grid_x)


# Calcula posiciones con distorsión sinusoidal en coordenadas locales del quad
func _calculate_distorted_positions() -> void:
	cell_positions.clear()
	
	for z in range(rows):
		var row_positions = []
		
		for x in range(columns):
			# Posición normalizada
			var u = (float(x) + 0.5) / max(1, columns)
			var v = (float(z) + 0.5) / max(1, rows)
			
			# Posición base usando interpolación bilineal
			var base_pos = GridHelper.bilinear_interpolation(vertices, u, v)
			
			# Calcular direcciones locales del quad en este punto
			# Dirección U (horizontal local): interpolar entre bordes inferior y superior
			var bottom_u_dir = (vertices[1] - vertices[0]).normalized()  # BL -> BR
			var top_u_dir = (vertices[2] - vertices[3]).normalized()     # TL -> TR
			var local_u_dir = bottom_u_dir.lerp(top_u_dir, v)
			
			# Dirección V (vertical local): interpolar entre bordes izquierdo y derecho
			var left_v_dir = (vertices[3] - vertices[0]).normalized()   # BL -> TL
			var right_v_dir = (vertices[2] - vertices[1]).normalized()  # BR -> TR
			var local_v_dir = left_v_dir.lerp(right_v_dir, u)
			
			# Calcular falloff para mantener los bordes del quad fijos
			# u_falloff: 0 en bordes izquierdo/derecho (u=0, u=1), 1.0 en el centro (u=0.5)
			# v_falloff: 0 en bordes superior/inferior (v=0, v=1), 1.0 en el centro (v=0.5)
			# edge_falloff_sharpness controla la curva: 1.0 = lineal, >1.0 = más abrupto, <1.0 = más suave
			var u_falloff = pow(min(u, 1.0 - u) * 2.0, edge_falloff_sharpness)
			var v_falloff = pow(min(v, 1.0 - v) * 2.0, edge_falloff_sharpness)
			
			# Calcular desplazamientos ondulatorios con falloff
			var wave_offset_u = sin(v * wave_frequency_z * TAU + wave_phase_z) * wave_amplitude_x * u_falloff
			var wave_offset_v = sin(u * wave_frequency_x * TAU + wave_phase_x) * wave_amplitude_z * v_falloff
			
			# Aplicar desplazamientos en direcciones locales
			var distorted_pos_2d = base_pos + local_u_dir * wave_offset_u + local_v_dir * wave_offset_v
			
			var distorted_pos = Vector3(
				distorted_pos_2d.x,
				0.0,
				distorted_pos_2d.y
			)
			
			row_positions.append(distorted_pos)
		
		cell_positions.append(row_positions)


# Obtiene el tipo de celda
func get_cell(x: int, z: int) -> int:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return -1
	return grid[x][z]


# Establece el tipo de celda
func set_cell(x: int, z: int, value: int) -> void:
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return
	grid[x][z] = value


# Obtiene la posición 3D distorsionada de una celda
func get_cell_position(x: int, z: int) -> Vector3:
	if z < 0 or z >= cell_positions.size():
		return Vector3.ZERO
	if x < 0 or x >= cell_positions[z].size():
		return Vector3.ZERO
	return cell_positions[z][x]


# Verifica si una celda está en el borde
func is_boundary_cell(x: int, z: int) -> bool:
	# Norte (z = 0)
	if z == 0 and edge_types[0] == -1:
		return true
	
	# Este (x = columns - 1)
	if x == columns - 1 and edge_types[1] == -1:
		return true
	
	# Sur (z = rows - 1)
	if z == rows - 1 and edge_types[2] == -1:
		return true
	
	# Oeste (x = 0)
	if x == 0 and edge_types[3] == -1:
		return true
	
	return false


# Obtiene el tipo de borde para un lado específico
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


# Obtiene los 4 vértices de una celda distorsionada
func get_cell_vertices(x: int, z: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	if x < 0 or x >= columns or z < 0 or z >= rows:
		return result
	
	# Calcular esquinas de la celda con distorsión
	for dz in [0, 1]:
		for dx in [0, 1]:
			var cell_x = clamp(x + dx, 0, columns)
			var cell_z = clamp(z + dz, 0, rows)
			
			var u = float(cell_x) / max(1, columns)
			var v = float(cell_z) / max(1, rows)
			var base_pos = GridHelper.bilinear_interpolation(vertices, u, v)
			
			# Calcular direcciones locales
			var bottom_u_dir = (vertices[1] - vertices[0]).normalized()
			var top_u_dir = (vertices[2] - vertices[3]).normalized()
			var local_u_dir = bottom_u_dir.lerp(top_u_dir, v)
			
			var left_v_dir = (vertices[3] - vertices[0]).normalized()
			var right_v_dir = (vertices[2] - vertices[1]).normalized()
			var local_v_dir = left_v_dir.lerp(right_v_dir, u)
			
			# Calcular falloff
			var u_falloff = pow(min(u, 1.0 - u) * 2.0, edge_falloff_sharpness)
			var v_falloff = pow(min(v, 1.0 - v) * 2.0, edge_falloff_sharpness)
			
			# Calcular desplazamientos con falloff
			var wave_offset_u = sin(v * wave_frequency_z * TAU + wave_phase_z) * wave_amplitude_x * u_falloff
			var wave_offset_v = sin(u * wave_frequency_x * TAU + wave_phase_x) * wave_amplitude_z * v_falloff
			
			# Aplicar en direcciones locales
			var distorted_pos_2d = base_pos + local_u_dir * wave_offset_u + local_v_dir * wave_offset_v
			
			result.append(Vector3(
				distorted_pos_2d.x,
				0.0,
				distorted_pos_2d.y
			))
	
	return result
