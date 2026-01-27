class_name BridgeGridHelper extends RefCounted

## Helper para obtener vértices de volúmenes en el building grid distorsionado
## Útil para colocar objetos procedurales (ventanas, ACs, etc.)

var block: BlockGenerator
var distorted_rows: int
var distorted_columns: int
var building_rows: int
var building_columns: int

## Tamaño total de la mega-grid absoluta
var absolute_rows: int
var absolute_columns: int


func _init(p_block: BlockGenerator) -> void:
	block = p_block
	
	var distorted = block.get_distorted_grid()
	distorted_rows = distorted.rows
	distorted_columns = distorted.columns
	
	building_rows = block.get_building_rows()
	building_columns = block.get_building_columns()
	
	# Calcular tamaño de mega-grid
	absolute_rows = distorted_rows * building_rows
	absolute_columns = distorted_columns * building_columns


## Obtiene los 8 vértices de un volumen usando coordenadas absolutas de mega-grid
## @param abs_x: Coordenada X absoluta en mega-grid (0 a absolute_columns-1)
## @param abs_z: Coordenada Z absoluta en mega-grid (0 a absolute_rows-1)
## @param abs_y: Coordenada Y absoluta en altura (índice de celda vertical)
## @param width: Ancho en celdas (dirección X)
## @param depth: Profundidad en celdas (dirección Z)
## @param height: Altura en celdas (dirección Y)
## @return: Dictionary con {bottom_vertices: Array[Vector3], top_vertices: Array[Vector3]}
func get_volume_vertices_absolute(
	abs_x: int,
	abs_z: int,
	abs_y: int,
	width: int = 1,
	depth: int = 1,
	height: int = 1
) -> Dictionary:
	# Convertir coordenadas absolutas a distorted + building local
	var coords = _absolute_to_local(abs_x, abs_z)
	
	return get_volume_vertices(
		coords.distorted_x,
		coords.distorted_z,
		coords.building_x,
		coords.building_z,
		abs_y,
		width,
		depth,
		height
	)


## Obtiene los 8 vértices de un volumen usando coordenadas locales
## @param distorted_x: Coordenada X en distorted_grid
## @param distorted_z: Coordenada Z en distorted_grid
## @param building_x: Coordenada X local en building_grid de esa celda
## @param building_z: Coordenada Z local en building_grid de esa celda
## @param building_y: Coordenada Y en altura (índice de celda vertical)
## @param width: Ancho en celdas (dirección X)
## @param depth: Profundidad en celdas (dirección Z)
## @param height: Altura en celdas (dirección Y)
## @return: Dictionary con {bottom_vertices: Array[Vector3], top_vertices: Array[Vector3]}
func get_volume_vertices(
	distorted_x: int,
	distorted_z: int,
	building_x: int,
	building_z: int,
	building_y: int,
	width: int = 1,
	depth: int = 1,
	height: int = 1
) -> Dictionary:
	# Validar coordenadas
	if not _validate_distorted_coords(distorted_x, distorted_z):
		push_error("Coordenadas distorted_grid inválidas: (%d, %d)" % [distorted_x, distorted_z])
		return {}
	
	if not _validate_building_coords(building_x, building_z, width, depth):
		push_error("Coordenadas building_grid inválidas: (%d, %d) con tamaño (%d, %d)" % [building_x, building_z, width, depth])
		return {}
	
	# Obtener el building de la celda distorted
	var building: Building = block.get_building(distorted_x, distorted_z, 0)
	
	if building == null:
		push_error("No existe building en distorted_grid (%d, %d)" % [distorted_x, distorted_z])
		return {}
	
	# Obtener vértices de la base (bottom)
	var bottom_vertices = _get_quad_vertices(
		building,
		building_x,
		building_z,
		width,
		depth,
		building_y
	)
	
	# Obtener vértices del techo (top)
	var top_vertices = _get_quad_vertices(
		building,
		building_x,
		building_z,
		width,
		depth,
		building_y + height
	)
	
	return {
		"bottom_vertices": bottom_vertices,
		"top_vertices": top_vertices
	}


## NUEVO: Obtiene los 4 vértices de una pared específica de un volumen
## @param distorted_x: Coordenada X en distorted_grid
## @param distorted_z: Coordenada Z en distorted_grid
## @param building_x: Coordenada X local en building_grid
## @param building_z: Coordenada Z local en building_grid
## @param building_y: Coordenada Y en altura
## @param width: Ancho del volumen (relevante para north/south)
## @param depth: Profundidad del volumen (relevante para east/west)
## @param height: Altura del volumen
## @param wall: "north", "south", "east", "west"
## @return: Array[Vector3] con 4 vértices [v1, v2, v3, v4] o vacío si error
func get_wall_vertices(
	distorted_x: int,
	distorted_z: int,
	building_x: int,
	building_z: int,
	building_y: int,
	width: int,
	depth: int,
	height: int,
	wall: String
) -> Array[Vector3]:
	
	var volume = get_volume_vertices(
		distorted_x, distorted_z,
		building_x, building_z, building_y,
		width, depth, height
	)
	
	if volume.is_empty():
		return []
	
	var bottom = volume.bottom_vertices
	var top = volume.top_vertices
	
	if bottom.size() != 4 or top.size() != 4:
		return []
	
	var result: Array[Vector3] = []
	
	match wall:
		"north":
			# Cara norte (z mínimo): bottom[0], bottom[1], top[1], top[0]
			result.append(bottom[0])
			result.append(bottom[1])
			result.append(top[1])
			result.append(top[0])
		
		"south":
			# Cara sur (z máximo): bottom[3], bottom[2], top[2], top[3]
			result.append(bottom[3])
			result.append(bottom[2])
			result.append(top[2])
			result.append(top[3])
		
		"east":
			# Cara este (x máximo): bottom[1], bottom[2], top[2], top[1]
			result.append(bottom[1])
			result.append(bottom[2])
			result.append(top[2])
			result.append(top[1])
		
		"west":
			# Cara oeste (x mínimo): bottom[0], bottom[3], top[3], top[0]
			result.append(bottom[0])
			result.append(bottom[3])
			result.append(top[3])
			result.append(top[0])
		
		_:
			push_error("Dirección de pared inválida: %s (debe ser north/south/east/west)" % wall)
			return []
	
	return result


## Obtiene los 4 vértices de un quad rectangular en el building grid
## @param building: Building de referencia
## @param start_x: Coordenada X inicial en building_grid
## @param start_z: Coordenada Z inicial en building_grid
## @param width: Ancho en celdas
## @param depth: Profundidad en celdas
## @param local_floor: Altura en celdas
## @return: Array[Vector3] con 4 vértices [BL, BR, TR, TL]
func _get_quad_vertices(
	building: Building,
	start_x: int,
	start_z: int,
	width: int,
	depth: int,
	local_floor: int
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	# Obtener vértices de las 4 esquinas del volumen rectangular
	# Bottom-Left: (start_x, start_z)
	var bl_cell = building.get_cell_vertices(start_x, start_z, local_floor)
	if bl_cell.size() == 4:
		result.append(bl_cell[0])  # Vértice BL de la celda BL
	
	# Bottom-Right: (start_x + width, start_z)
	var br_cell = building.get_cell_vertices(start_x + width - 1, start_z, local_floor)
	if br_cell.size() == 4:
		result.append(br_cell[1])  # Vértice BR de la celda BR
	
	# Top-Right: (start_x + width, start_z + depth)
	var tr_cell = building.get_cell_vertices(start_x + width - 1, start_z + depth - 1, local_floor)
	if tr_cell.size() == 4:
		result.append(tr_cell[2])  # Vértice TR de la celda TR
	
	# Top-Left: (start_x, start_z + depth)
	var tl_cell = building.get_cell_vertices(start_x, start_z + depth - 1, local_floor)
	if tl_cell.size() == 4:
		result.append(tl_cell[3])  # Vértice TL de la celda TL
	
	return result


## Convierte coordenadas absolutas de mega-grid a locales (distorted + building)
## @param abs_x: Coordenada X absoluta
## @param abs_z: Coordenada Z absoluta
## @return: Dictionary con {distorted_x, distorted_z, building_x, building_z}
func _absolute_to_local(abs_x: int, abs_z: int) -> Dictionary:
	var distorted_x = int(abs_x / building_columns)
	var distorted_z = int(abs_z / building_rows)
	
	var building_x = abs_x % building_columns
	var building_z = abs_z % building_rows
	
	return {
		"distorted_x": distorted_x,
		"distorted_z": distorted_z,
		"building_x": building_x,
		"building_z": building_z
	}


## Convierte coordenadas locales a absolutas de mega-grid
## @param distorted_x: Coordenada X en distorted_grid
## @param distorted_z: Coordenada Z en distorted_grid
## @param building_x: Coordenada X local en building_grid
## @param building_z: Coordenada Z local en building_grid
## @return: Dictionary con {abs_x, abs_z}
func _local_to_absolute(
	distorted_x: int,
	distorted_z: int,
	building_x: int,
	building_z: int
) -> Dictionary:
	return {
		"abs_x": distorted_x * building_columns + building_x,
		"abs_z": distorted_z * building_rows + building_z
	}


## Valida que las coordenadas distorted estén dentro de rango
func _validate_distorted_coords(x: int, z: int) -> bool:
	return x >= 0 and x < distorted_columns and z >= 0 and z < distorted_rows


## Valida que las coordenadas building + tamaño estén dentro de rango
func _validate_building_coords(x: int, z: int, width: int, depth: int) -> bool:
	return (x >= 0 and 
			z >= 0 and 
			x + width <= building_columns and 
			z + depth <= building_rows)


## Obtiene el tamaño de la mega-grid absoluta
## @return: Dictionary con {rows, columns}
func get_absolute_grid_size() -> Dictionary:
	return {
		"rows": absolute_rows,
		"columns": absolute_columns
	}


## Obtiene información de debug sobre una coordenada absoluta
## @param abs_x: Coordenada X absoluta
## @param abs_z: Coordenada Z absoluta
## @return: Dictionary con información de debug
func get_debug_info(abs_x: int, abs_z: int) -> Dictionary:
	var coords = _absolute_to_local(abs_x, abs_z)
	
	var building: Building = block.get_building(
		coords.distorted_x, 
		coords.distorted_z, 
		0
	)
	
	var is_valid = building != null
	var is_in_core = false
	
	if is_valid:
		is_in_core = building.is_cell_in_core(
			coords.building_x, 
			coords.building_z
		)
	
	return {
		"absolute": {"x": abs_x, "z": abs_z},
		"distorted": {"x": coords.distorted_x, "z": coords.distorted_z},
		"building": {"x": coords.building_x, "z": coords.building_z},
		"is_valid": is_valid,
		"is_in_core": is_in_core
	}
	
## NUEVO: Determina qué edges de una celda son exteriores al cluster
## @param cluster: BuildingCluster de referencia
## @param x: Coordenada X de la celda en distorted_grid
## @param z: Coordenada Z de la celda en distorted_grid
## @return: Array de dictionaries con {direction: String, x: int, z: int}
func get_exterior_edges(cluster: BuildingCluster, x: int, z: int) -> Array:
	var exterior: Array = []
	
	# Norte (z - 1)
	if not cluster.contains_cell(x, z - 1) or z == 0:
		exterior.append({"direction": "north", "x": x, "z": z})
	
	# Este (x + 1)
	if not cluster.contains_cell(x + 1, z) or x == distorted_columns - 1:
		exterior.append({"direction": "east", "x": x, "z": z})
	
	# Sur (z + 1)
	if not cluster.contains_cell(x, z + 1) or z == distorted_rows - 1:
		exterior.append({"direction": "south", "x": x, "z": z})
	
	# Oeste (x - 1)
	if not cluster.contains_cell(x - 1, z) or x == 0:
		exterior.append({"direction": "west", "x": x, "z": z})
	
	return exterior
