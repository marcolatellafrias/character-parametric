class_name GridHelper
extends RefCounted

## Clase helper con funciones estáticas para geometría de grillas 2D/3D

## Interpola bilinealmente un punto en un quad 2D
## @param vertices: Array[Vector2] con 4 vértices del quad [BL, BR, TR, TL]
## @param u: Coordenada normalizada horizontal [0, 1]
## @param v: Coordenada normalizada vertical [0, 1]
## @return: Vector2 interpolado
static func bilinear_interpolation(vertices: Array[Vector2], u: float, v: float) -> Vector2:
	if vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para interpolación bilineal")
		return Vector2.ZERO
	
	# Interpolación bilineal: 
	# P = (1-u)(1-v)V0 + u(1-v)V1 + uv*V2 + (1-u)v*V3
	var result = (
		vertices[0] * (1 - u) * (1 - v) +  # Bottom-Left
		vertices[1] * u * (1 - v) +        # Bottom-Right
		vertices[2] * u * v +              # Top-Right
		vertices[3] * (1 - u) * v          # Top-Left
	)
	
	return result


## Obtiene la posición 2D de una celda en una grilla dentro de un quad
## @param vertices: Array[Vector2] con 4 vértices del quad [BL, BR, TR, TL]
## @param rows: Número de filas de la grilla
## @param columns: Número de columnas de la grilla
## @param grid_x: Índice X de la celda
## @param grid_z: Índice Z de la celda
## @return: Vector2 con la posición del centro de la celda
static func get_cell_position_2d(
	vertices: Array[Vector2],
	rows: int,
	columns: int,
	grid_x: int,
	grid_z: int
) -> Vector2:
	if vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices")
		return Vector2.ZERO
	
	# Calcular coordenadas normalizadas del centro de la celda
	var u = (float(grid_x) + 0.5) / max(1, columns)
	var v = (float(grid_z) + 0.5) / max(1, rows)
	
	return bilinear_interpolation(vertices, u, v)


## Obtiene los 4 vértices de una celda en la base de la grilla
## @param vertices: Array[Vector2] con 4 vértices del quad [BL, BR, TR, TL]
## @param rows: Número de filas de la grilla
## @param columns: Número de columnas de la grilla
## @param grid_x: Índice X de la celda
## @param grid_z: Índice Z de la celda
## @return: Array[Vector3] con los 4 vértices de la celda (y=0)
static func get_cell_base_vertices(
	vertices: Array[Vector2],
	rows: int,
	columns: int,
	grid_x: int,
	grid_z: int
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	if vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices")
		return result
	
	# Calcular coordenadas normalizadas de las 4 esquinas de la celda
	var u_min = float(grid_x) / max(1, columns)
	var u_max = float(grid_x + 1) / max(1, columns)
	var v_min = float(grid_z) / max(1, rows)
	var v_max = float(grid_z + 1) / max(1, rows)
	
	# Bottom-Left
	var bl_2d = bilinear_interpolation(vertices, u_min, v_min)
	result.append(Vector3(bl_2d.x, 0.0, bl_2d.y))
	
	# Bottom-Right
	var br_2d = bilinear_interpolation(vertices, u_max, v_min)
	result.append(Vector3(br_2d.x, 0.0, br_2d.y))
	
	# Top-Right
	var tr_2d = bilinear_interpolation(vertices, u_max, v_max)
	result.append(Vector3(tr_2d.x, 0.0, tr_2d.y))
	
	# Top-Left
	var tl_2d = bilinear_interpolation(vertices, u_min, v_max)
	result.append(Vector3(tl_2d.x, 0.0, tl_2d.y))
	
	return result


## Calcula las coordenadas de grilla con offset aplicado
## @param rows: Número de filas totales
## @param columns: Número de columnas totales
## @param street_offsets: Dictionary {tipo_calle: offset_en_celdas}
## @param street_types: Array[int] con tipos de calle [north, east, south, west]
## @return: Dictionary con {min_x, max_x, min_z, max_z}
static func calculate_available_area(
	rows: int,
	columns: int,
	street_offsets: Dictionary,
	street_types: Array[int]
) -> Dictionary:
	if street_types.size() != 4:
		push_error("Se requieren exactamente 4 tipos de calle [north, east, south, west]")
		return {}
	
	var north_offset = street_offsets.get(street_types[0], 0)
	var east_offset = street_offsets.get(street_types[1], 0)
	var south_offset = street_offsets.get(street_types[2], 0)
	var west_offset = street_offsets.get(street_types[3], 0)
	
	return {
		"min_x": west_offset,
		"max_x": columns - east_offset - 1,
		"min_z": north_offset,
		"max_z": rows - south_offset - 1
	}
