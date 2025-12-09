class_name BlockGenerator extends RefCounted

# Tipos de calles
enum StreetType {
	BOUNDARY = -1,
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2,
	SMALL_TUNNEL = 3,
	LARGE_TUNNEL = 4,
}

# Componentes
var grid_geometry: GridGeometry
var distorted_grid: DistortedGrid
var path_generator: PathGenerator

# Geometría del bloque
var street_types: Array[int]  # [north, east, south, west]
var is_clockwise: bool

# Offsets de calles (recibidos desde GraphCityGenerator)
var street_offsets: Dictionary = {}

# Área disponible después de offsets
var available_min_x: int
var available_max_x: int
var available_min_z: int
var available_max_z: int

# Carriles por lado de la manzana
var lanes: Dictionary = {}  # {side: Array[int]} offsets de carriles por lado


func _init(
	p_rows: int,
	p_columns: int,
	p_vertices: Array[Vector2],
	p_street_types: Array[int],
	p_cell_height: float,
	p_floors: int,
	p_cells_per_floor: int,
	p_is_clockwise: bool,
	p_street_offsets: Dictionary,
	# Parámetros de grilla distorsionada
	p_distorted_rows: int = 10,
	p_distorted_columns: int = 10,
	p_wave_amplitude_x: float = 0.1,
	p_wave_amplitude_z: float = 0.1,
	p_wave_frequency_x: float = 2.0,
	p_wave_frequency_z: float = 2.0,
	p_wave_phase_x: float = 0.0,
	p_wave_phase_z: float = 0.0,
	p_edge_falloff_sharpness: float = 1.0,
	# Parámetros de generación de alleyways
	p_small_alleyways_count: int = 2,
	p_big_alleyways_count: int = 1,
	p_min_steps_before_turn: int = 2,
	p_grid_seed: int = -1
) -> void:
	street_types = p_street_types
	is_clockwise = p_is_clockwise
	street_offsets = p_street_offsets
	
	grid_geometry = GridGeometry.new(
		p_rows,
		p_columns,
		p_vertices,
		p_cell_height,
		p_floors,
		p_cells_per_floor
	)
	
	_calculate_available_area()
	_calculate_lanes()
	
	# Crear grilla distorsionada
	_create_distorted_grid(
		p_distorted_rows,
		p_distorted_columns,
		p_cell_height,
		p_wave_amplitude_x,
		p_wave_amplitude_z,
		p_wave_frequency_x,
		p_wave_frequency_z,
		p_wave_phase_x,
		p_wave_phase_z,
		p_edge_falloff_sharpness
	)
	
	# Crear generador de paths
	_create_path_generator(
		p_small_alleyways_count,
		p_big_alleyways_count,
		p_min_steps_before_turn,
		p_grid_seed
	)


func _calculate_available_area() -> void:
	var north_offset = street_offsets.get(street_types[0], 0)
	var south_offset = street_offsets.get(street_types[2], 0)
	var west_offset = street_offsets.get(street_types[3], 0)
	var east_offset = street_offsets.get(street_types[1], 0)
	
	available_min_x = west_offset
	available_max_x = grid_geometry.columns - east_offset - 1
	available_min_z = north_offset
	available_max_z = grid_geometry.rows - south_offset - 1


func _create_distorted_grid(
	distorted_rows: int,
	distorted_columns: int,
	cell_height: float,
	wave_amplitude_x: float,
	wave_amplitude_z: float,
	wave_frequency_x: float,
	wave_frequency_z: float,
	wave_phase_x: float,
	wave_phase_z: float,
	edge_falloff_sharpness: float
) -> void:
	var core_vertices = _get_core_block_vertices()
	
	distorted_grid = DistortedGrid.new(
		distorted_rows,
		distorted_columns,
		core_vertices,
		cell_height,
		wave_amplitude_x,
		wave_amplitude_z,
		wave_frequency_x,
		wave_frequency_z,
		wave_phase_x,
		wave_phase_z,
		edge_falloff_sharpness
	)


func _create_path_generator(
	small_alleyways_count: int,
	big_alleyways_count: int,
	min_steps_before_turn: int,
	grid_seed: int
) -> void:
	path_generator = PathGenerator.new(
		distorted_grid,
		small_alleyways_count,
		big_alleyways_count,
		min_steps_before_turn,
		grid_seed
	)
	
	# Generar los alleyways
	path_generator.generate()


func _get_core_block_vertices() -> Array[Vector2]:
	var vertices: Array[Vector2] = []
	
	var full_vertices = grid_geometry.vertices
	var columns = grid_geometry.columns
	var rows = grid_geometry.rows
	
	var u_min = float(available_min_x) / max(1, columns)
	var u_max = float(available_max_x + 1) / max(1, columns)
	var v_min = float(available_min_z) / max(1, rows)
	var v_max = float(available_max_z + 1) / max(1, rows)
	
	# Bottom-Left
	var bl = GridHelper.bilinear_interpolation(full_vertices, u_min, v_min)
	vertices.append(bl)
	
	# Bottom-Right
	var br = GridHelper.bilinear_interpolation(full_vertices, u_max, v_min)
	vertices.append(br)
	
	# Top-Right
	var tr = GridHelper.bilinear_interpolation(full_vertices, u_max, v_max)
	vertices.append(tr)
	
	# Top-Left
	var tl = GridHelper.bilinear_interpolation(full_vertices, u_min, v_max)
	vertices.append(tl)
	
	return vertices


func _calculate_lanes() -> void:
	lanes["north"] = _get_lane_offsets_for_street_type(street_types[0])
	lanes["east"] = _get_lane_offsets_for_street_type(street_types[1])
	lanes["south"] = _get_lane_offsets_for_street_type(street_types[2])
	lanes["west"] = _get_lane_offsets_for_street_type(street_types[3])


func _get_lane_offsets_for_street_type(street_type: int) -> Array[int]:
	var offsets: Array[int] = []
	var total_offset = street_offsets.get(street_type, 0)
	
	if total_offset == 0:
		return offsets
	
	match street_type:
		StreetType.SMALL:
			offsets = [4]
		StreetType.MEDIUM:
			offsets = [4, 9]
		StreetType.LARGE:
			offsets = [4, 9, 14]
		_:
			offsets = []
	
	return offsets


func get_lane_endpoints(side: String, lane_index: int) -> Dictionary:
	if side not in lanes or lane_index >= lanes[side].size():
		return {}
	
	var offset = lanes[side][lane_index]
	var start_pos: Vector3
	var end_pos: Vector3
	var from_pos: Vector3
	var to_pos: Vector3
	
	if is_clockwise:
		match side:
			"north":
				var z = available_min_z - offset
				start_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				end_pos = grid_geometry.get_cell_position(0, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"south":
				var z = available_max_z + offset
				start_pos = grid_geometry.get_cell_position(0, z, 0)
				end_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"west":
				var x = available_min_x - offset
				start_pos = grid_geometry.get_cell_position(x, 0, 0)
				end_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"east":
				var x = available_max_x + offset
				start_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				end_pos = grid_geometry.get_cell_position(x, 0, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			_:
				return {}
	else:
		match side:
			"north":
				var z = available_min_z - offset
				start_pos = grid_geometry.get_cell_position(0, z, 0)
				end_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"south":
				var z = available_max_z + offset
				start_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
				end_pos = grid_geometry.get_cell_position(0, z, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"west":
				var x = available_min_x - offset
				start_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				end_pos = grid_geometry.get_cell_position(x, 0, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			"east":
				var x = available_max_x + offset
				start_pos = grid_geometry.get_cell_position(x, 0, 0)
				end_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
				from_pos = start_pos
				to_pos = end_pos
				
			_:
				return {}
	
	return {
		"start": start_pos,
		"end": end_pos,
		"from": from_pos,
		"to": to_pos,
		"side": side
	}


func get_all_lanes() -> Array[Dictionary]:
	var all_lanes: Array[Dictionary] = []
	
	for side in ["north", "south", "east", "west"]:
		for lane_idx in range(lanes[side].size()):
			var endpoints = get_lane_endpoints(side, lane_idx)
			if not endpoints.is_empty():
				endpoints["index"] = lane_idx
				all_lanes.append(endpoints)
	
	return all_lanes


func get_block_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	
	var vertices = grid_geometry.vertices
	var columns = grid_geometry.columns
	var rows = grid_geometry.rows
	
	var u_min = float(available_min_x) / max(1, columns)
	var u_max = float(available_max_x) / max(1, columns)
	var v_min = float(available_min_z) / max(1, rows)
	var v_max = float(available_max_z) / max(1, rows)
	
	# Bottom-Left
	var corner_bl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_min) +
		vertices[1] * u_min * (1 - v_min) +
		vertices[2] * u_min * v_min +
		vertices[3] * (1 - u_min) * v_min
	)
	corners.append(Vector3(corner_bl_2d.x, 0.0, corner_bl_2d.y))
	
	# Bottom-Right
	var corner_br_2d = (
		vertices[0] * (1 - u_max) * (1 - v_min) +
		vertices[1] * u_max * (1 - v_min) +
		vertices[2] * u_max * v_min +
		vertices[3] * (1 - u_max) * v_min
	)
	corners.append(Vector3(corner_br_2d.x, 0.0, corner_br_2d.y))
	
	# Top-Right
	var corner_tr_2d = (
		vertices[0] * (1 - u_max) * (1 - v_max) +
		vertices[1] * u_max * (1 - v_max) +
		vertices[2] * u_max * v_max +
		vertices[3] * (1 - u_max) * v_max
	)
	corners.append(Vector3(corner_tr_2d.x, 0.0, corner_tr_2d.y))
	
	# Top-Left
	var corner_tl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_max) +
		vertices[1] * u_min * (1 - v_max) +
		vertices[2] * u_min * v_max +
		vertices[3] * (1 - u_min) * v_max
	)
	corners.append(Vector3(corner_tl_2d.x, 0.0, corner_tl_2d.y))
	
	return corners


# Propiedades de acceso directo
func get_rows() -> int:
	return grid_geometry.rows

func get_columns() -> int:
	return grid_geometry.columns

func get_cell_height() -> float:
	return grid_geometry.cell_height

func get_floors() -> int:
	return grid_geometry.floors

func get_cells_per_floor() -> int:
	return grid_geometry.cells_per_floor

func get_distorted_grid() -> DistortedGrid:
	return distorted_grid

func get_path_generator() -> PathGenerator:
	return path_generator
