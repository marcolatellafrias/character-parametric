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

# Chamfers de las esquinas: {vertex_index: [c1, c2]}
# donde c1 y c2 son el número de celdas chamfereadas
var chamfers: Dictionary = {}

# Flag para manejar orientación
var is_clockwise: bool = false


func _init(
	p_vertices: Array[Vector3],
	p_edge_types: Array[int],
	p_rows: int,
	p_columns: int,
	p_cell_height: float,
	p_alleyway_offsets: Dictionary,
	p_floor: int = 0,
	p_distorted_grid: DistortedGrid = null,
	p_grid_x: int = -1,
	p_grid_z: int = -1,
	p_path_generator: PathGenerator = null,
	p_is_clockwise: bool = false
) -> void:
	vertices = p_vertices
	edge_types = p_edge_types
	rows = p_rows
	columns = p_columns
	cell_height = p_cell_height
	alleyway_offsets = p_alleyway_offsets
	floor = p_floor
	is_clockwise = p_is_clockwise
	
	_calculate_core_area()
	
	# Calcular chamfers si se proporcionó la información necesaria
	if p_distorted_grid and p_grid_x >= 0 and p_grid_z >= 0 and p_path_generator:
		_calculate_chamfers(p_distorted_grid, p_grid_x, p_grid_z, p_path_generator)


func _calculate_core_area() -> void:
	var north_offset = alleyway_offsets.get(edge_types[0], 0)
	var east_offset = alleyway_offsets.get(edge_types[1], 0)
	var south_offset = alleyway_offsets.get(edge_types[2], 0)
	var west_offset = alleyway_offsets.get(edge_types[3], 0)
	
	core_min_x = west_offset
	core_max_x = columns - east_offset - 1
	core_min_z = north_offset
	core_max_z = rows - south_offset - 1


func _calculate_chamfers(
	distorted_grid: DistortedGrid,
	grid_x: int,
	grid_z: int,
	path_generator: PathGenerator
) -> void:
	# Para cada vértice del building module
	for vertex_index in range(4):
		# Si es clockwise, necesitamos mapear el índice al equivalente normalizado
		var normalized_vertex_index = vertex_index
		if is_clockwise:
			# El swap es 1 ↔ 3, así que mapeamos al revés para obtener la topología correcta
			if vertex_index == 1:
				normalized_vertex_index = 3
			elif vertex_index == 3:
				normalized_vertex_index = 1
		
		var info = distorted_grid.get_vertex_edges_info(grid_x, grid_z, normalized_vertex_index)
		
		# Verificar que tenga exactamente 2 corner edges y 2 secondary edges
		if info["corner_edges"].size() != 2 or info["secondary_edges"].size() != 2:
			continue
		
		# Verificar que los corner edges NO tengan offset
		var corner_edges_valid = true
		for corner_edge in info["corner_edges"]:
			var edge_type = _get_edge_type_from_vertices(
				corner_edge["v1"], corner_edge["v2"], path_generator
			)
			# Si tiene offset (no es NORMAL ni FACADE), no es válido
			if edge_type != DistortedGrid.CellType.NORMAL and edge_type != DistortedGrid.CellType.FACADE:
				corner_edges_valid = false
				break
		
		if not corner_edges_valid:
			continue
		
		# Obtener offsets de los secondary edges
		var secondary_edge_data: Array = []
		var all_secondary_valid = true
		
		for secondary_edge in info["secondary_edges"]:
			var edge_type = _get_edge_type_from_vertices(
				secondary_edge["v1"], secondary_edge["v2"], path_generator
			)
			# Los secondary edges DEBEN tener offset
			if edge_type == DistortedGrid.CellType.NORMAL or edge_type == DistortedGrid.CellType.FACADE:
				all_secondary_valid = false
				break
			
			# Sin ajuste - el offset ya es correcto para las dimensiones del core
			var offset = alleyway_offsets.get(edge_type, 0)
			
			secondary_edge_data.append({
				"edge": secondary_edge,
				"offset": offset
			})
		
		if not all_secondary_valid or secondary_edge_data.size() != 2:
			continue
		
		# Determinar c1 y c2 basándose en la orientación del vértice NORMALIZADO
		var chamfer_values = _determine_chamfer_values(
			normalized_vertex_index, info["vertex"], secondary_edge_data
		)
		
		if chamfer_values.size() == 2:
			# Guardar usando el índice del VÉRTICE DESPUÉS DEL SWAP (el que se usa en visualización)
			chamfers[vertex_index] = chamfer_values
	
	# YA NO NECESITAMOS AJUSTAR - los chamfers ya están en la orientación correcta


func _adjust_chamfers_for_clockwise() -> void:
	# Cuando hacemos el swap de vértices (1 ↔ 3) para clockwise,
	# los chamfers también deben ajustarse de dos formas:
	# 1. Los índices de vértices deben intercambiarse
	# 2. Los valores [c1, c2] deben invertirse a [c2, c1] porque la orientación cambia
	var adjusted_chamfers: Dictionary = {}
	
	for vertex_idx in chamfers:
		var new_idx = vertex_idx
		
		# El swap que se hace en visualización es: vertices[1] ↔ vertices[3]
		if vertex_idx == 1:
			new_idx = 3
		elif vertex_idx == 3:
			new_idx = 1
		
		# Invertir los valores [c1, c2] → [c2, c1] porque la orientación se invierte
		var original_values = chamfers[vertex_idx]
		adjusted_chamfers[new_idx] = [original_values[1], original_values[0]]
	
	chamfers = adjusted_chamfers


func _get_edge_type_from_vertices(
	v1: Vector2i,
	v2: Vector2i,
	path_generator: PathGenerator
) -> int:
	return path_generator.get_path_edge_type_vertices(v1.x, v1.y, v2.x, v2.y)


func _determine_chamfer_values(
	vertex_index: int,
	vertex_pos: Vector2i,
	secondary_edge_data: Array
) -> Array:
	# Mapeo de vértice index a las direcciones de c1 y c2
	# c1: hacia el edge que conecta con el vértice anterior (clockwise)
	# c2: hacia el edge que conecta con el vértice siguiente (clockwise)
	
	# Direcciones para cada vértice:
	# V0 (BL): c1 hacia west (-x o +z según la orientación), c2 hacia north (+x)
	# V1 (BR): c1 hacia north (+x o -x), c2 hacia east (+z)
	# V2 (TR): c1 hacia east (+z o -z), c2 hacia south (-x o +x)
	# V3 (TL): c1 hacia south (-x o +x), c2 hacia west (-z o +z)
	
	var c1_offset = 0
	var c2_offset = 0
	
	# Identificar qué edge secundario corresponde a cada dirección
	for edge_data in secondary_edge_data:
		var edge = edge_data["edge"]
		var offset = edge_data["offset"]
		var v1: Vector2i = edge["v1"]
		var v2: Vector2i = edge["v2"]
		var other_v = v2 if v1 == vertex_pos else v1
		var direction = other_v - vertex_pos
		
		# Determinar si este edge corresponde a c1 o c2 según el vértice
		match vertex_index:
			0:  # BL
				if direction.y > 0:  # Hacia +z (west en términos de la celda, hacia TL)
					c1_offset = offset
				elif direction.x > 0:  # Hacia +x (north, hacia BR)
					c2_offset = offset
				elif direction.y < 0:  # Hacia -z (norte absoluto)
					c2_offset = offset
				elif direction.x < 0:  # Hacia -x (oeste absoluto)
					c1_offset = offset
			1:  # BR
				if direction.x < 0:  # Hacia -x (north, hacia BL)
					c1_offset = offset
				elif direction.y > 0:  # Hacia +z (east, hacia TR)
					c2_offset = offset
				elif direction.x > 0:  # Hacia +x (este absoluto)
					c2_offset = offset
				elif direction.y < 0:  # Hacia -z (norte absoluto)
					c1_offset = offset
			2:  # TR
				if direction.y < 0:  # Hacia -z (east, hacia BR)
					c1_offset = offset
				elif direction.x < 0:  # Hacia -x (south, hacia TL)
					c2_offset = offset
				elif direction.y > 0:  # Hacia +z (sur absoluto)
					c2_offset = offset
				elif direction.x > 0:  # Hacia +x (este absoluto)
					c1_offset = offset
			3:  # TL
				if direction.x > 0:  # Hacia +x (south, hacia TR)
					c1_offset = offset
				elif direction.y < 0:  # Hacia -z (west, hacia BL)
					c2_offset = offset
				elif direction.x < 0:  # Hacia -x (oeste absoluto)
					c2_offset = offset
				elif direction.y > 0:  # Hacia +z (sur absoluto)
					c1_offset = offset
	
	if c1_offset > 0 and c2_offset > 0:
		return [c1_offset, c2_offset]
	return []


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


func get_chamfers() -> Dictionary:
	return chamfers


func _vertices_3d_to_2d() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for v in vertices:
		result.append(Vector2(v.x, v.z))
	return result


func get_floor() -> int:
	return floor
