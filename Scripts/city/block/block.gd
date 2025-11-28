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
var subdivider: RectangleSubdivider

# Geometría del bloque
var street_types: Array[int]  # [north, east, south, west]

# Offsets de calles según tipo (en número de celdas)
const STREET_OFFSETS = {
	StreetType.BOUNDARY: 0,
	StreetType.SMALL: 7,
	StreetType.MEDIUM: 12,
	StreetType.LARGE: 17,
	StreetType.SMALL_TUNNEL: 0,
	StreetType.LARGE_TUNNEL: 0,
}

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
	p_cells_per_floor: int
) -> void:
	street_types = p_street_types
	
	grid_geometry = GridGeometry.new(
		p_rows,
		p_columns,
		p_vertices,
		p_cell_height,
		p_floors,
		p_cells_per_floor
	)
	
	subdivider = RectangleSubdivider.new()
	
	_calculate_available_area()
	subdivider.setup_area(available_min_x, available_max_x, available_min_z, available_max_z)
	_calculate_lanes()


# Calcula el área disponible después de aplicar los offsets de las calles
func _calculate_available_area() -> void:
	var north_offset = STREET_OFFSETS.get(street_types[0], 0)
	var south_offset = STREET_OFFSETS.get(street_types[2], 0)
	var west_offset = STREET_OFFSETS.get(street_types[3], 0)
	var east_offset = STREET_OFFSETS.get(street_types[1], 0)
	
	available_min_x = west_offset
	available_max_x = grid_geometry.columns - east_offset - 1
	available_min_z = north_offset
	available_max_z = grid_geometry.rows - south_offset - 1


# Calcula los carriles para cada lado de la manzana
func _calculate_lanes() -> void:
	lanes["north"] = _get_lane_offsets_for_street_type(street_types[0])
	lanes["east"] = _get_lane_offsets_for_street_type(street_types[1])
	lanes["south"] = _get_lane_offsets_for_street_type(street_types[2])
	lanes["west"] = _get_lane_offsets_for_street_type(street_types[3])


# Retorna los offsets de carriles según el tipo de calle
static func _get_lane_offsets_for_street_type(street_type: int) -> Array[int]:
	var offsets: Array[int] = []
	
	match street_type:
		StreetType.SMALL:  # 7 celdas: xxxxOxx
			offsets = [4]
		StreetType.MEDIUM:  # 12 celdas: xxxxOxxxxOxx
			offsets = [4, 9]
		StreetType.LARGE:  # 17 celdas: xxxxOxxxxOxxxxOxx
			offsets = [4, 9, 14]
		_:  # BOUNDARY, SMALL_TUNNEL, LARGE_TUNNEL
			offsets = []
	
	return offsets


# Genera rectángulos y los aplica a la grilla
func generate_rectangles(
	p_max_divisions: int,
	p_min_size: int,
	p_max_aspect_ratio: float,
	p_max_dimension: int,
	seed_value: int
) -> void:
	var rectangles = subdivider.generate_rectangles(
		p_max_divisions,
		p_min_size,
		p_max_aspect_ratio,
		p_max_dimension,
		seed_value
	)
	
	_apply_rectangles_to_grid(rectangles)


# Aplica los rectángulos generados a la grilla 3D
func _apply_rectangles_to_grid(rectangles: Array) -> void:
	var total_height = grid_geometry.floors * grid_geometry.cells_per_floor
	
	for rect in rectangles:
		for y in range(total_height):
			for dx in range(rect.width):
				for dz in range(rect.height):
					var gx = rect.x + dx
					var gz = rect.z + dz
					grid_geometry.set_cell(gx, gz, y, rect.id)


# Obtiene el rectángulo al que pertenece una celda
func get_rectangle_at(x: int, z: int) -> RectangleSubdivider.GridRectangle:
	for rect in subdivider.rectangles:
		if x >= rect.x and x < rect.x + rect.width:
			if z >= rect.z and z < rect.z + rect.height:
				return rect
	return null


# Obtiene las posiciones de inicio y fin de un carril
# side: "north", "south", "east", "west"
# lane_index: índice del carril en ese lado
func get_lane_endpoints(side: String, lane_index: int) -> Dictionary:
	if side not in lanes or lane_index >= lanes[side].size():
		return {}
	
	var offset = lanes[side][lane_index]
	var start_pos: Vector3
	var end_pos: Vector3
	
	match side:
		"north":
			var z = available_min_z - offset
			start_pos = grid_geometry.get_cell_position(0, z, 0)
			end_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
		"south":
			var z = available_max_z + offset
			start_pos = grid_geometry.get_cell_position(0, z, 0)
			end_pos = grid_geometry.get_cell_position(grid_geometry.columns - 1, z, 0)
		"west":
			var x = available_min_x - offset
			start_pos = grid_geometry.get_cell_position(x, 0, 0)
			end_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
		"east":
			var x = available_max_x + offset
			start_pos = grid_geometry.get_cell_position(x, 0, 0)
			end_pos = grid_geometry.get_cell_position(x, grid_geometry.rows - 1, 0)
		_:
			return {}
	
	return {
		"start": start_pos,
		"end": end_pos
	}


# Obtiene todos los carriles de la manzana
func get_all_lanes() -> Array[Dictionary]:
	var all_lanes: Array[Dictionary] = []
	
	for side in ["north", "south", "east", "west"]:
		for lane_idx in range(lanes[side].size()):
			var endpoints = get_lane_endpoints(side, lane_idx)
			if not endpoints.is_empty():
				endpoints["side"] = side
				endpoints["index"] = lane_idx
				all_lanes.append(endpoints)
	
	return all_lanes


# Acceso a datos de grilla (delegación)
func get_cell(x: int, z: int, y: int) -> int:
	return grid_geometry.get_cell(x, z, y)

func get_cell_position(x: int, z: int, y: int) -> Vector3:
	return grid_geometry.get_cell_position(x, z, y)

func get_floor_for_cell(y: int) -> int:
	return grid_geometry.get_floor_for_cell(y)

func is_floor_start(y: int) -> bool:
	return grid_geometry.is_floor_start(y)

func get_cell_base_vertices(x: int, z: int, y: int) -> Array:
	return grid_geometry.get_cell_base_vertices(x, z, y)


# Acceso a datos de rectángulos (delegación)
func get_rectangles() -> Array:
	return subdivider.rectangles

func get_rectangle_offsets(rect_id: int) -> RectangleSubdivider.RectangleOffsets:
	return subdivider.get_rectangle_offsets(rect_id)

func get_rectangle_bounds_with_offset(rect: RectangleSubdivider.GridRectangle) -> Dictionary:
	return subdivider.get_rectangle_bounds_with_offset(rect)

func is_rectangle_merged(rect_id: int) -> bool:
	return subdivider.is_rectangle_merged(rect_id)

func get_merged_with(rect_id: int) -> int:
	return subdivider.get_merged_with(rect_id)


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
