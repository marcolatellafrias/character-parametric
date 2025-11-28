class_name LaneGenerator
extends RefCounted

# Información de un carril individual
class LaneInfo:
	var direction: Vector3  # Dirección del carril (normalizada)
	var offset: float  # Distancia desde el centro de la calle (perpendicular)
	var side: int  # 0 = forward (misma dirección que el edge), 1 = backward (dirección opuesta)
	
	func _init(p_direction: Vector3, p_offset: float, p_side: int) -> void:
		direction = p_direction
		offset = p_offset
		side = p_side

# Información de carriles para una calle (edge)
class StreetLanes:
	var lanes: Array[LaneInfo] = []
	var forward_count: int = 0
	var backward_count: int = 0
	var street_width: float = 0.0
	
	func _init() -> void:
		pass

# Ancho de carril por defecto
const DEFAULT_LANE_WIDTH: float = 3.5

# Offsets de calles (copiado de BlockGenerator para referencia)
const STREET_OFFSETS = {
	-1: 0,  # BOUNDARY
	0: 4,   # SMALL
	1: 5,   # MEDIUM
	2: 6,   # LARGE
	3: 0,   # SMALL_TUNNEL
	4: 0,   # LARGE_TUNNEL
}

var lane_width: float = DEFAULT_LANE_WIDTH
var lanes_data: Dictionary = {}  # {edge_key: StreetLanes}


func _init(p_lane_width: float = DEFAULT_LANE_WIDTH) -> void:
	lane_width = p_lane_width


# Genera carriles para todas las calles del grafo
func generate_lanes_for_graph(
	graph: GraphGenerator,
	street_types: Dictionary,
	cell_size: float
) -> void:
	lanes_data.clear()
	
	for edge in graph.edges:
		var edge_key = GraphGenerator._get_edge_key(edge[0], edge[1])
		var street_type = street_types.get(edge_key, 1)
		
		# Obtener el ancho disponible para esta calle
		var street_width = _calculate_street_width(street_type, cell_size)
		
		# Generar carriles para este edge
		var street_lanes = _generate_lanes_for_edge(
			graph.points[edge[0]],
			graph.points[edge[1]],
			street_width
		)
		
		lanes_data[edge_key] = street_lanes


# Calcula el ancho físico de una calle según su tipo
func _calculate_street_width(street_type: int, cell_size: float) -> float:
	var offset_cells = STREET_OFFSETS.get(street_type, 0)
	
	# El ancho de la calle es el offset en ambos lados
	# Para túneles (offset 0), usamos un ancho mínimo de 2 carriles
	if offset_cells == 0:
		return lane_width * 2.0
	
	return offset_cells * cell_size * 2.0


# Genera carriles para un edge específico
func _generate_lanes_for_edge(
	point1: Vector3,
	point2: Vector3,
	street_width: float
) -> StreetLanes:
	var street_lanes = StreetLanes.new()
	street_lanes.street_width = street_width
	
	# Calcular dirección del edge
	var edge_direction = (point2 - point1).normalized()
	
	# Calcular vector perpendicular (hacia la derecha del edge)
	var perpendicular = Vector3(-edge_direction.z, 0, edge_direction.x)
	
	# Calcular cuántos carriles caben
	var total_lanes = max(1, int(street_width / lane_width))
	
	# Dividir carriles entre ambas direcciones
	var forward_lanes = int(total_lanes / 2.0)
	var backward_lanes = total_lanes - forward_lanes
	
	# Si es impar, alternar cuál dirección tiene más (determinista)
	if total_lanes % 2 == 1:
		# Usar hash del ancho para decidir de forma determinista
		if int(street_width * 100) % 2 == 0:
			forward_lanes += 1
		else:
			backward_lanes += 1
	
	street_lanes.forward_count = forward_lanes
	street_lanes.backward_count = backward_lanes
	
	# Calcular el espacio usado por los carriles
	var used_width = total_lanes * lane_width
	var margin = (street_width - used_width) / 2.0
	
	# Generar carriles forward (lado derecho, dirección del edge)
	var forward_start = margin + lane_width * 0.5
	for i in range(forward_lanes):
		var offset_distance = forward_start + (i * lane_width)
		var lateral_offset = offset_distance - (street_width * 0.5)
		
		var lane = LaneInfo.new(edge_direction, lateral_offset, 0)
		street_lanes.lanes.append(lane)
	
	# Generar carriles backward (lado izquierdo, dirección opuesta)
	var backward_start = forward_start + (forward_lanes * lane_width)
	for i in range(backward_lanes):
		var offset_distance = backward_start + (i * lane_width)
		var lateral_offset = offset_distance - (street_width * 0.5)
		
		var lane = LaneInfo.new(-edge_direction, lateral_offset, 1)
		street_lanes.lanes.append(lane)
	
	return street_lanes


# Obtiene los carriles de una calle
func get_lanes(edge_key: String) -> StreetLanes:
	return lanes_data.get(edge_key, null)


# Obtiene información de carriles de un edge específico
func get_lanes_for_edge(node1_idx: int, node2_idx: int) -> StreetLanes:
	var edge_key = GraphGenerator._get_edge_key(node1_idx, node2_idx)
	return get_lanes(edge_key)


# Calcula las posiciones 3D de las líneas de carril para visualización
func get_lane_line_positions(
	point1: Vector3,
	point2: Vector3,
	lane: LaneInfo
) -> Array[Vector3]:
	var edge_direction = (point2 - point1).normalized()
	var perpendicular = Vector3(-edge_direction.z, 0, edge_direction.x)
	
	# Calcular puntos desplazados por el offset del carril
	var offset_vector = perpendicular * lane.offset
	var start = point1 + offset_vector
	var end = point2 + offset_vector
	
	return [start, end]
