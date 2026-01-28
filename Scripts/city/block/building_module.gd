class_name BuildingModule extends RefCounted

# Vértices del quad completo [BL, BR, TR, TL]
var vertices: Array[Vector3]

# Tipos de edges [north, east, south, west]
var edge_types: Array[int]

# Geometría de la grilla del building
var rows: int
var columns: int
var cell_height: float

# Offsets de alleyways (número de celdas por tipo de edge)
var alleyway_offsets: Dictionary

# Área core del building (después de offsets)
var core_min_x: int
var core_max_x: int
var core_min_z: int
var core_max_z: int

# Piso al que pertenece este building
var floor: int


func _init(
	p_vertices: Array[Vector3],
	p_edge_types: Array[int],
	p_rows: int,
	p_columns: int,
	p_cell_height: float,
	p_alleyway_offsets: Dictionary,
	p_floor: int = 0
) -> void:
	vertices = p_vertices
	edge_types = p_edge_types
	rows = p_rows
	columns = p_columns
	cell_height = p_cell_height
	alleyway_offsets = p_alleyway_offsets
	floor = p_floor
	
	_calculate_core_area()


func _calculate_core_area() -> void:
	var north_offset = alleyway_offsets.get(edge_types[0], 0)
	var east_offset = alleyway_offsets.get(edge_types[1], 0)
	var south_offset = alleyway_offsets.get(edge_types[2], 0)
	var west_offset = alleyway_offsets.get(edge_types[3], 0)
	
	core_min_x = west_offset
	core_max_x = columns - east_offset - 1
	core_min_z = north_offset
	core_max_z = rows - south_offset - 1


func get_vertex(index: int) -> Vector3:
	if index < 0 or index >= vertices.size():
		return Vector3.ZERO
	return vertices[index]


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


func get_cell_position(grid_x: int, grid_z: int, local_floor: int = 0) -> Vector3:
	var vertices_2d = _vertices_3d_to_2d()
	var u = (float(grid_x) + 0.5) / max(1, columns)
	var v = (float(grid_z) + 0.5) / max(1, rows)
	
	var pos_2d = GridHelper.bilinear_interpolation(vertices_2d, u, v)
	var y = local_floor * cell_height
	
	return Vector3(pos_2d.x, y, pos_2d.y)


func get_cell_vertices(grid_x: int, grid_z: int, local_floor: int = 0) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var vertices_2d = _vertices_3d_to_2d()
	
	var u_min = float(grid_x) / max(1, columns)
	var u_max = float(grid_x + 1) / max(1, columns)
	var v_min = float(grid_z) / max(1, rows)
	var v_max = float(grid_z + 1) / max(1, rows)
	
	var y = local_floor * cell_height
	
	# Bottom-Left
	var bl_2d = GridHelper.bilinear_interpolation(vertices_2d, u_min, v_min)
	result.append(Vector3(bl_2d.x, y, bl_2d.y))
	
	# Bottom-Right
	var br_2d = GridHelper.bilinear_interpolation(vertices_2d, u_max, v_min)
	result.append(Vector3(br_2d.x, y, br_2d.y))
	
	# Top-Right
	var tr_2d = GridHelper.bilinear_interpolation(vertices_2d, u_max, v_max)
	result.append(Vector3(tr_2d.x, y, tr_2d.y))
	
	# Top-Left
	var tl_2d = GridHelper.bilinear_interpolation(vertices_2d, u_min, v_max)
	result.append(Vector3(tl_2d.x, y, tl_2d.y))
	
	return result


func get_core_vertices(local_floor: int = 0) -> Array[Vector3]:
	var vertices_2d = _vertices_3d_to_2d()
	var result: Array[Vector3] = []
	
	var u_min = float(core_min_x) / max(1, columns)
	var u_max = float(core_max_x + 1) / max(1, columns)
	var v_min = float(core_min_z) / max(1, rows)
	var v_max = float(core_max_z + 1) / max(1, rows)
	
	var y = local_floor * cell_height
	
	# Bottom-Left
	var bl = GridHelper.bilinear_interpolation(vertices_2d, u_min, v_min)
	result.append(Vector3(bl.x, y, bl.y))
	
	# Bottom-Right
	var br = GridHelper.bilinear_interpolation(vertices_2d, u_max, v_min)
	result.append(Vector3(br.x, y, br.y))
	
	# Top-Right
	var tr = GridHelper.bilinear_interpolation(vertices_2d, u_max, v_max)
	result.append(Vector3(tr.x, y, tr.y))
	
	# Top-Left
	var tl = GridHelper.bilinear_interpolation(vertices_2d, u_min, v_max)
	result.append(Vector3(tl.x, y, tl.y))
	
	return result


func is_cell_in_core(grid_x: int, grid_z: int) -> bool:
	return (grid_x >= core_min_x and grid_x <= core_max_x and
			grid_z >= core_min_z and grid_z <= core_max_z)


func is_cell_alleyway(grid_x: int, grid_z: int) -> bool:
	return not is_cell_in_core(grid_x, grid_z)


func get_core_info() -> Dictionary:
	return {
		"min_x": core_min_x,
		"max_x": core_max_x,
		"min_z": core_min_z,
		"max_z": core_max_z,
		"width": core_max_x - core_min_x + 1,
		"depth": core_max_z - core_min_z + 1
	}


func _vertices_3d_to_2d() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for v in vertices:
		result.append(Vector2(v.x, v.z))
	return result


func get_floor() -> int:
	return floor
