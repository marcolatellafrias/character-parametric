class_name GraphGenerator
extends RefCounted

# ============================================
# ESTADO DEL GRAFO
# ============================================
var points: Array[Vector3] = []      # Nodos del grafo
var edges: Array[Array] = []         # [[idx1, idx2], ...] aristas
var faces: Array = []                # [[idx1, idx2, idx3, ...], ...] caras
var smoothing_steps: int = 0         # Cantidad de pasos de smoothing realizados
var original_inscribed_sizes: Dictionary = {}  # {face_idx: float} tamaño original del cuadrado inscrito


# ============================================
# FUNCIÓN PRINCIPAL
# ============================================
func generate_graph(
	smooth_steps: int,
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int,
	generation_seed: int,

) -> void:
	var max_angle_threshold: float = 0.825 * PI
	var min_quad_angle: float = 0.2 * PI
	var max_quad_angle: float = 0.9 * PI
	
	seed(generation_seed)
	
	# Limpiar estado anterior
	points.clear()
	edges.clear()
	faces.clear()
	smoothing_steps = 0
	original_inscribed_sizes.clear()
	
	var edges_dict: Dictionary = {}
	
	# 1. Generar puntos con Poisson Disk Sampling
	points = _generate_poisson_points(region_size, min_distance, rejection_samples)
	
	# 2. Construir grafo desde Delaunay
	var graph_data = _build_graph_from_delaunay(
		points, 
		max_angle_threshold, 
		min_quad_angle, 
		max_quad_angle
	)
	points = graph_data["points"]
	edges_dict = graph_data["edges"]
	faces = graph_data["faces"]
	
	# 3. Subdividir caras
	var subdivided = _subdivide_faces(points, faces)
	points = subdivided["points"]
	faces = subdivided["faces"]
	
	# 4. Reconstruir aristas desde las caras
	edges_dict.clear()
	for face in faces:
		for i in range(face.size()):
			var next_i = (i + 1) % face.size()
			var key = _get_edge_key(face[i], face[next_i])
			edges_dict[key] = [face[i], face[next_i]]
	
	# Convertir aristas a array
	for edge in edges_dict.values():
		edges.append(edge)
	
	# 5. Calcular y guardar los tamaños originales de los cuadrados inscritos
	_calculate_original_inscribed_sizes()
	# 6. Aplicar smoothing (si se solicitó)
	for i in range(smooth_steps):
		smooth_graph()
	
func _calculate_original_inscribed_sizes() -> void:
	original_inscribed_sizes.clear()
	
	for face_idx in range(faces.size()):
		var inscribed_square: Array[Vector3] = get_inscribed_square_for_face(face_idx)
		
		if inscribed_square.size() >= 2:
			# Calcular el tamaño del cuadrado como la distancia entre dos vértices consecutivos
			var size: float = inscribed_square[0].distance_to(inscribed_square[1])
			original_inscribed_sizes[face_idx] = size

# ============================================
# POISSON DISK SAMPLING
# ============================================
static func _generate_poisson_points(
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int
) -> Array[Vector3]:
	
	var points: Array[Vector3] = []
	var cell_size: float = min_distance / sqrt(2.0)
	var grid_width: int = ceil(region_size.x / cell_size)
	var grid_height: int = ceil(region_size.y / cell_size)
	
	var grid: Array = []
	grid.resize(grid_width * grid_height)
	
	var active_list: Array[Vector3] = []
	
	# Primer punto
	var first_point = Vector3(
		randf() * region_size.x,
		0.0,
		randf() * region_size.y
	)
	points.append(first_point)
	active_list.append(first_point)
	var grid_pos = _point_to_grid(first_point, cell_size)
	grid[grid_pos.x + grid_pos.y * grid_width] = first_point
	
	# Generar puntos
	while active_list.size() > 0:
		var random_index = randi() % active_list.size()
		var point = active_list[random_index]
		var found = false
		
		for i in range(rejection_samples):
			var new_point = _generate_point_around(point, min_distance)
			
			if _is_valid_point(new_point, grid, cell_size, grid_width, grid_height, region_size, min_distance):
				points.append(new_point)
				active_list.append(new_point)
				var new_grid_pos = _point_to_grid(new_point, cell_size)
				grid[new_grid_pos.x + new_grid_pos.y * grid_width] = new_point
				found = true
		
		if not found:
			active_list.remove_at(random_index)
	
	return points

static func _generate_point_around(point: Vector3, min_distance: float) -> Vector3:
	var angle = randf() * TAU
	var radius = min_distance + randf() * min_distance
	
	return Vector3(
		point.x + cos(angle) * radius,
		0.0,
		point.z + sin(angle) * radius
	)

static func _is_valid_point(
	point: Vector3, 
	grid: Array, 
	cell_size: float, 
	grid_width: int, 
	grid_height: int,
	region_size: Vector2,
	min_distance: float
) -> bool:
	
	if point.x < 0 or point.x >= region_size.x or point.z < 0 or point.z >= region_size.y:
		return false
	
	var grid_pos = _point_to_grid(point, cell_size)
	var search_start_x = max(0, grid_pos.x - 2)
	var search_end_x = min(grid_width - 1, grid_pos.x + 2)
	var search_start_y = max(0, grid_pos.y - 2)
	var search_end_y = min(grid_height - 1, grid_pos.y + 2)
	
	for y in range(search_start_y, search_end_y + 1):
		for x in range(search_start_x, search_end_x + 1):
			var index = x + y * grid_width
			var neighbor = grid[index]
			if neighbor != null:
				var distance = point.distance_to(neighbor)
				if distance < min_distance:
					return false
	
	return true

static func _point_to_grid(point: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(
		int(point.x / cell_size),
		int(point.z / cell_size)
	)

# ============================================
# CONSTRUCCIÓN DEL GRAFO DESDE DELAUNAY
# ============================================
static func _build_graph_from_delaunay(
	points: Array[Vector3],
	max_angle_threshold: float,
	min_quad_angle: float,
	max_quad_angle: float
) -> Dictionary:
	
	var edges: Dictionary = {}
	var faces: Array = []
	
	if points.size() < 3:
		return {"points": points, "edges": edges, "faces": faces}
	
	# Triangulación de Delaunay
	var points_2d: PackedVector2Array = PackedVector2Array()
	for point in points:
		points_2d.append(Vector2(point.x, point.z))
	
	var indices: PackedInt32Array = Geometry2D.triangulate_delaunay(points_2d)
	
	var triangles = []
	for i in range(0, indices.size(), 3):
		triangles.append([indices[i], indices[i + 1], indices[i + 2]])
	
	# Filtrar triángulos obtusos
	var filtered_triangles = []
	for tri in triangles:
		if _is_valid_triangle(tri, points, max_angle_threshold):
			filtered_triangles.append(tri)
	
	# Intentar fusionar triángulos en quads
	var quads = []
	var used_triangles = {}
	
	for i in range(filtered_triangles.size()):
		if i in used_triangles:
			continue
		
		var tri1 = filtered_triangles[i]
		var merged = false
		
		for j in range(i + 1, filtered_triangles.size()):
			if j in used_triangles:
				continue
			
			var tri2 = filtered_triangles[j]
			var shared_edge = _find_shared_edge(tri1, tri2)
			
			if shared_edge.size() == 2:
				var quad = _create_quad_from_triangles(tri1, tri2, shared_edge)
				
				if quad.size() == 4 and _is_valid_quad(quad, points, min_quad_angle, max_quad_angle):
					quads.append(quad)
					used_triangles[i] = true
					used_triangles[j] = true
					merged = true
					break
	
	# Construir caras del grafo
	for quad in quads:
		faces.append(quad)
		for i in range(quad.size()):
			var next_i = (i + 1) % quad.size()
			var key = _get_edge_key(quad[i], quad[next_i])
			edges[key] = [quad[i], quad[next_i]]
	
	for i in range(filtered_triangles.size()):
		if not (i in used_triangles):
			var tri = filtered_triangles[i]
			faces.append(tri)
			for j in range(tri.size()):
				var next_j = (j + 1) % tri.size()
				var key = _get_edge_key(tri[j], tri[next_j])
				edges[key] = [tri[j], tri[next_j]]
	
	return {"points": points, "edges": edges, "faces": faces}

static func _is_valid_triangle(tri: Array, points: Array[Vector3], max_angle_threshold: float) -> bool:
	var p1 = points[tri[0]]
	var p2 = points[tri[1]]
	var p3 = points[tri[2]]
	
	var angle1 = _calculate_angle(p1, p2, p3)
	var angle2 = _calculate_angle(p2, p3, p1)
	var angle3 = _calculate_angle(p3, p1, p2)
	
	return (angle1 <= max_angle_threshold and 
			angle2 <= max_angle_threshold and 
			angle3 <= max_angle_threshold)

static func _find_shared_edge(tri1: Array, tri2: Array) -> Array:
	var shared = []
	for v1 in tri1:
		for v2 in tri2:
			if v1 == v2:
				shared.append(v1)
	
	if shared.size() == 2:
		return shared
	return []

static func _create_quad_from_triangles(tri1: Array, tri2: Array, shared_edge: Array) -> Array:
	var v1 = -1
	var v2 = -1
	
	for v in tri1:
		if v not in shared_edge:
			v1 = v
			break
	
	for v in tri2:
		if v not in shared_edge:
			v2 = v
			break
	
	if v1 == -1 or v2 == -1:
		return []
	
	return [shared_edge[0], v1, shared_edge[1], v2]

static func _is_valid_quad(
	quad: Array, 
	points: Array[Vector3],
	min_quad_angle: float,
	max_quad_angle: float
) -> bool:
	
	if quad.size() != 4:
		return false
	
	var p1 = points[quad[0]]
	var p2 = points[quad[1]]
	var p3 = points[quad[2]]
	var p4 = points[quad[3]]
	
	if not _is_convex_quad(p1, p2, p3, p4):
		return false
	
	var angle1 = _calculate_angle(p1, p2, p4)
	var angle2 = _calculate_angle(p2, p3, p1)
	var angle3 = _calculate_angle(p3, p4, p2)
	var angle4 = _calculate_angle(p4, p1, p3)
	
	return (angle1 >= min_quad_angle and angle1 <= max_quad_angle and
			angle2 >= min_quad_angle and angle2 <= max_quad_angle and
			angle3 >= min_quad_angle and angle3 <= max_quad_angle and
			angle4 >= min_quad_angle and angle4 <= max_quad_angle)

static func _is_convex_quad(p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> bool:
	var cross1 = _cross_product_2d(p1, p2, p3)
	var cross2 = _cross_product_2d(p2, p3, p4)
	var cross3 = _cross_product_2d(p3, p4, p1)
	var cross4 = _cross_product_2d(p4, p1, p2)
	
	return ((cross1 > 0 and cross2 > 0 and cross3 > 0 and cross4 > 0) or
			(cross1 < 0 and cross2 < 0 and cross3 < 0 and cross4 < 0))

# ============================================
# SUBDIVISIÓN DE CARAS
# ============================================
static func _subdivide_faces(points: Array[Vector3], faces: Array) -> Dictionary:
	var new_points = points.duplicate()
	var new_faces = []
	var edge_midpoints = {}  # <-- Caché de puntos medios
	
	for face in faces:
		var sub_faces = []
		
		if face.size() == 4:
			sub_faces = _subdivide_quad_face(face, new_points, edge_midpoints)
		elif face.size() == 3:
			sub_faces = _subdivide_triangle_face(face, new_points, edge_midpoints)
		
		new_faces.append_array(sub_faces)
	
	return {"points": new_points, "faces": new_faces}

static func _subdivide_quad_face(face: Array, points: Array[Vector3], edge_midpoints: Dictionary) -> Array:
	# Obtener o crear puntos medios
	var idx_mid1 = _get_or_create_midpoint(face[0], face[1], points, edge_midpoints)
	var idx_mid2 = _get_or_create_midpoint(face[1], face[2], points, edge_midpoints)
	var idx_mid3 = _get_or_create_midpoint(face[2], face[3], points, edge_midpoints)
	var idx_mid4 = _get_or_create_midpoint(face[3], face[0], points, edge_midpoints)
	
	# El centro sigue siendo único por cara
	var p1 = points[face[0]]
	var p2 = points[face[1]]
	var p3 = points[face[2]]
	var p4 = points[face[3]]
	var center = (p1 + p2 + p3 + p4) / 4.0
	var idx_center = points.size()
	points.append(center)
	
	var result = []
	result.append([face[0], idx_mid1, idx_center, idx_mid4])
	result.append([idx_mid1, face[1], idx_mid2, idx_center])
	result.append([idx_center, idx_mid2, face[2], idx_mid3])
	result.append([idx_mid4, idx_center, idx_mid3, face[3]])
	
	return result

static func _subdivide_triangle_face(face: Array, points: Array[Vector3], edge_midpoints: Dictionary) -> Array:
	# Obtener o crear puntos medios (reutilizando si ya existen)
	var idx_mid1 = _get_or_create_midpoint(face[0], face[1], points, edge_midpoints)
	var idx_mid2 = _get_or_create_midpoint(face[1], face[2], points, edge_midpoints)
	var idx_mid3 = _get_or_create_midpoint(face[2], face[0], points, edge_midpoints)
	
	# El centro sigue siendo único por cara
	var p1 = points[face[0]]
	var p2 = points[face[1]]
	var p3 = points[face[2]]
	var center = (p1 + p2 + p3) / 3.0
	var idx_center = points.size()
	points.append(center)
	
	# Crear 3 caras hijas (quads)
	var result = []
	result.append([face[0], idx_mid1, idx_center, idx_mid3])
	result.append([idx_mid1, face[1], idx_mid2, idx_center])
	result.append([idx_center, idx_mid2, face[2], idx_mid3])
	
	return result

# ============================================
# UTILIDADES
# ============================================
static func _get_edge_key(idx1: int, idx2: int) -> String:
	var min_idx = min(idx1, idx2)
	var max_idx = max(idx1, idx2)
	return str(min_idx) + "_" + str(max_idx)

static func _calculate_angle(vertex: Vector3, p1: Vector3, p2: Vector3) -> float:
	var v1 = (p1 - vertex).normalized()
	var v2 = (p2 - vertex).normalized()
	var dot_product = clamp(v1.dot(v2), -1.0, 1.0)
	return acos(dot_product)

static func _cross_product_2d(p1: Vector3, p2: Vector3, p3: Vector3) -> float:
	var v1 = Vector2(p2.x - p1.x, p2.z - p1.z)
	var v2 = Vector2(p3.x - p2.x, p3.z - p2.z)
	return v1.x * v2.y - v1.y * v2.x

static func _get_or_create_midpoint(idx1: int, idx2: int, points: Array[Vector3], cache: Dictionary) -> int:
	var key = _get_edge_key(idx1, idx2)
	
	if key in cache:
		return cache[key]
	
	var midpoint = (points[idx1] + points[idx2]) / 2.0
	var new_idx = points.size()
	points.append(midpoint)
	cache[key] = new_idx
	
	return new_idx

# ============================================
# CONSULTAS DEL GRAFO
# ============================================

## Retorna los índices de las caras (quads) que contienen el nodo especificado
## @param node_idx: Índice del nodo a consultar
## @return: Array[int] con los índices de las caras que contienen el nodo
func get_quads_for_node(node_idx: int) -> Array[int]:
	var connected_quads: Array[int] = []
	
	for i in range(faces.size()):
		var face = faces[i]
		if node_idx in face:
			connected_quads.append(i)
	
	return connected_quads


# ============================================
# GEOMETRÍA DE CARAS
# ============================================

## Obtiene el cuadrado inscrito en una cara del grafo
## @param face_idx: Índice de la cara en el array de faces
## @param use_original_size: Si es true, usa el tamaño original guardado para el override
## @return: Array[Vector3] con los 4 vértices del cuadrado inscrito (o vacío si la cara no es válida)
func get_inscribed_square_for_face(face_idx: int, use_original_size: bool = false) -> Array[Vector3]:
	if face_idx < 0 or face_idx >= faces.size():
		push_error("Índice de cara inválido: ", face_idx)
		return []

	var face = faces[face_idx]

	# Convertir los puntos de la cara de Vector3 a Vector2
	var quad_2d: Array = []
	for idx in face:
		if idx >= points.size():
			push_error("Índice de punto inválido en cara: ", idx)
			return []
		var p = points[idx]
		quad_2d.append(Vector2(p.x, p.z))

	# Determinar si debemos usar el tamaño original
	var override_size = null
	if use_original_size and face_idx in original_inscribed_sizes:
		override_size = original_inscribed_sizes[face_idx]

	# Obtener el cuadrado inscrito (en 2D)
	var inscribed_2d: Array = GraphHelper.get_inscribed_square(quad_2d, override_size)

	if inscribed_2d.is_empty():
		return []

	# Convertir de vuelta a Vector3 (con y = 0)
	var inscribed_3d: Array[Vector3] = []
	for p2d in inscribed_2d:
		inscribed_3d.append(Vector3(p2d.x, 0.0, p2d.y))

	return inscribed_3d

## Calcula el promedio de los puntos correspondientes (por índice clockwise) 
## de los cuadrados inscritos en todas las caras conectadas a un nodo
## @param node_idx: Índice del nodo a consultar
## @param use_original_size: Si es true, usa los tamaños originales para calcular los cuadrados inscritos
## @return: Vector3 con la posición promedio, o Vector3.ZERO si no hay caras conectadas
func get_average_closest_inscribed_point(node_idx: int, use_original_size: bool = false) -> Vector3:
	# Validar índice del nodo
	if node_idx < 0 or node_idx >= points.size():
		push_error("Índice de nodo inválido: ", node_idx)
		return Vector3.ZERO
	
	# 1. Obtener todas las caras conectadas al nodo
	var connected_quads: Array[int] = get_quads_for_node(node_idx)
	
	if connected_quads.is_empty():
		push_warning("El nodo ", node_idx, " no tiene caras conectadas")
		return Vector3.ZERO
	
	var node_position: Vector3 = points[node_idx]
	var corresponding_points: Array[Vector3] = []
	
	# 2-3. Por cada cara, encontrar el punto correspondiente por índice clockwise
	for face_idx in connected_quads:
		var face = faces[face_idx]
		
		# Convertir la cara a 2D y calcular centro de masa
		var face_2d: Array = []
		var center_2d := Vector2.ZERO
		for idx in face:
			var p = points[idx]
			var p2d = Vector2(p.x, p.z)
			face_2d.append(p2d)
			center_2d += p2d
		center_2d /= face.size()
		
		# Centrar los vértices
		var centered_face: Array = []
		for p2d in face_2d:
			centered_face.append(p2d - center_2d)
		
		# Ordenar en sentido horario usando la misma función que get_inscribed_square
		var sorted_indices = _get_clockwise_sorted_indices(centered_face)
		
		# Encontrar en qué posición clockwise está nuestro nodo
		var clockwise_index := -1
		for i in range(sorted_indices.size()):
			if face[sorted_indices[i]] == node_idx:
				clockwise_index = i
				break
		
		if clockwise_index == -1:
			push_warning("No se pudo encontrar el nodo en la cara (esto no debería pasar)")
			continue
		
		# Obtener el cuadrado inscrito
		var inscribed_square: Array[Vector3] = get_inscribed_square_for_face(face_idx, use_original_size)
		
		if inscribed_square.is_empty():
			continue
		
		# Usar el mismo índice clockwise para obtener el punto correspondiente
		# Nota: Si la cara es un triángulo (3 vértices), el cuadrado inscrito sigue teniendo 4 vértices
		# En ese caso, necesitamos mapear correctamente
		var corresponding_point: Vector3
		if face.size() == 4:
			# Para quads, mapeo directo
			corresponding_point = inscribed_square[clockwise_index]
		else:
			# Para triángulos, mapear los 3 índices a 4 vértices del cuadrado
			# Usamos los vértices 0, 1, 2 del cuadrado (ignorando el 3)
			if clockwise_index < 3:
				corresponding_point = inscribed_square[clockwise_index]
			else:
				# Esto no debería pasar con triángulos
				corresponding_point = inscribed_square[0]
		
		corresponding_points.append(corresponding_point)
	
	# 4. Calcular el promedio de todos los puntos correspondientes
	if corresponding_points.is_empty():
		push_warning("No se pudieron calcular puntos correspondientes para las caras del nodo ", node_idx)
		return Vector3.ZERO
	
	var average_position: Vector3 = Vector3.ZERO
	for point in corresponding_points:
		average_position += point
	
	average_position /= corresponding_points.size()
	
	return average_position


## Función auxiliar: Ordena vértices centrados en sentido horario y retorna los índices ordenados
static func _get_clockwise_sorted_indices(centered_vertices: Array) -> Array:
	# Calcular ángulo de cada vértice respecto al origen
	var angles := []
	for i in range(centered_vertices.size()):
		var angle := atan2(centered_vertices[i].y, centered_vertices[i].x)
		angles.append({"index": i, "angle": angle})
	
	# Ordenar por ángulo (sentido horario = ángulo decreciente)
	angles.sort_custom(func(a, b): return a["angle"] > b["angle"])
	
	var sorted_indices := []
	for item in angles:
		sorted_indices.append(item["index"])
	
	return sorted_indices


## Mueve uno o varios nodos del grafo a nuevas posiciones
## @param node_transformations: Diccionario con formato {node_idx: nueva_posicion (Vector3)}
func move_nodes(node_transformations: Dictionary) -> void:
	# Aplicar las transformaciones de posición directamente
	for node_idx in node_transformations:
		if node_idx >= 0 and node_idx < points.size():
			points[node_idx] = node_transformations[node_idx]
		else:
			push_warning("move_nodes: Índice de nodo %d fuera de rango (0-%d)" % [node_idx, points.size() - 1])

## Suaviza el grafo moviendo cada nodo hacia su punto inscrito promedio
func smooth_graph() -> void:
	# Usar tamaños originales solo después del primer paso de smoothing
	var use_original_size: bool = (smoothing_steps > 0)
	
	var node_transformations: Dictionary = {}
	
	# Calcular la nueva posición objetivo para cada nodo
	for node_idx in range(points.size()):
		var new_position = get_average_closest_inscribed_point(node_idx, use_original_size)
		node_transformations[node_idx] = new_position
	
	# Aplicar todas las transformaciones de una vez
	move_nodes(node_transformations)
	
	# Incrementar contador de pasos de smoothing
	smoothing_steps += 1
	
## Obtiene los índices de las caras adyacentes a una cara dada
## (caras que comparten al menos una arista, es decir, dos vértices consecutivos)
## @param face_idx: Índice de la cara a consultar
## @return: Array[int] con los índices de las caras adyacentes
func get_adjacent_faces(face_idx: int) -> Array[int]:
	var adjacent: Array[int] = []
	
	if face_idx < 0 or face_idx >= faces.size():
		return adjacent
	
	var face = faces[face_idx]
	
	# Crear conjunto de aristas de esta cara
	var face_edges: Dictionary = {}
	for i in range(face.size()):
		var next_i = (i + 1) % face.size()
		var edge_key = _get_edge_key(face[i], face[next_i])
		face_edges[edge_key] = true
	
	# Buscar otras caras que compartan al menos una arista
	for other_face_idx in range(faces.size()):
		if other_face_idx == face_idx:
			continue
		
		var other_face = faces[other_face_idx]
		
		# Verificar si comparten alguna arista
		for i in range(other_face.size()):
			var next_i = (i + 1) % other_face.size()
			var edge_key = _get_edge_key(other_face[i], other_face[next_i])
			
			if edge_key in face_edges:
				adjacent.append(other_face_idx)
				break  # Ya encontramos que son adyacentes, no seguir verificando
	
	return adjacent


## Obtiene todos los edges conectados a un nodo
## @param node_idx: Índice del nodo a consultar
## @return: Array con los edges conectados (cada edge es [idx1, idx2])
func get_edges_for_node(node_idx: int) -> Array:
	var connected: Array = []
	
	for edge in edges:
		if edge[0] == node_idx or edge[1] == node_idx:
			connected.append(edge)
	
	return connected
	
## Selecciona dos edges que apunten en direcciones aproximadamente opuestas
## @param node_idx: Nodo central desde el cual comparar direcciones
## @param node_edges: Array de edges conectados al nodo
## @return: Array con dos edges opuestos, o array vacío si no se encuentran
func select_opposite_edges(node_idx: int, node_edges: Array) -> Array:
	if node_edges.size() < 2:
		return []
	
	var node_pos = points[node_idx]
	
	# Calcular direcciones de todos los edges
	var directions: Array = []
	for edge in node_edges:
		var other_node = edge[1] if edge[0] == node_idx else edge[0]
		var other_pos = points[other_node]
		var direction = (other_pos - node_pos).normalized()
		directions.append({"edge": edge, "direction": direction})
	
	# Encontrar el par con mayor oposición (dot product más negativo)
	var best_pair = []
	var best_opposition = 0.5  # Umbral mínimo para considerar opuestos
	
	for i in range(directions.size()):
		for j in range(i + 1, directions.size()):
			var dot = directions[i]["direction"].dot(directions[j]["direction"])
			if dot < -best_opposition:
				best_opposition = dot
				best_pair = [directions[i]["edge"], directions[j]["edge"]]
	
	# Si no se encontró un buen par, elegir dos aleatorios
	if best_pair.is_empty():
		node_edges.shuffle()
		return [node_edges[0], node_edges[1]]
	
	return best_pair
	
## Verifica si un nodo está en el límite del mapa
## @param node_idx: Índice del nodo a verificar
## @param edge_types: Diccionario con tipos de edges {edge_key: tipo}
## @return: true si el nodo tiene al menos un edge de tipo -1 (límite)
func is_boundary_node(node_idx: int, edge_types: Dictionary) -> bool:
	var connected_edges = get_edges_for_node(node_idx)
	
	for edge in connected_edges:
		var edge_key = _get_edge_key(edge[0], edge[1])
		if edge_types.get(edge_key, 1) == -1:  # Tipo -1 = límite
			return true
	
	return false

## Obtiene el siguiente edge que mejor continúa una dirección dada
## @param current_node: Nodo actual
## @param previous_node: Nodo anterior (para calcular dirección)
## @param edge_types: Diccionario con tipos de edges
## @param desired_type: Tipo de edge que estamos buscando
## @return: Edge que mejor continúa la dirección, o null si no hay ninguno válido
func get_next_edge_in_direction(
	current_node: int, 
	previous_node: int, 
	edge_types: Dictionary,
	desired_type: int
) -> Array:
	var connected_edges = get_edges_for_node(current_node)
	
	# Calcular la dirección actual
	var current_pos = points[current_node]
	var previous_pos = points[previous_node]
	var current_direction = (current_pos - previous_pos).normalized()
	
	# Buscar el edge que mejor se alinee con la dirección actual
	var best_edge: Array = []  # Inicializar como array vacío en lugar de null
	var best_alignment = -2.0  # Peor caso posible
	
	for edge in connected_edges:
		# No volver atrás
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		if other_node == previous_node:
			continue
		
		# Verificar si este edge ya tiene un tipo incompatible
		var edge_key = _get_edge_key(edge[0], edge[1])
		var current_type = edge_types.get(edge_key, 1)
		
		# Si el edge ya es del mismo tipo o mediana, puede ser usado
		# Si es de otro tipo especial (grande o pequeña diferente), saltarlo
		if current_type != desired_type and current_type != 1:
			continue
		
		# Calcular alineación con la dirección actual
		var other_pos = points[other_node]
		var edge_direction = (other_pos - current_pos).normalized()
		var alignment = current_direction.dot(edge_direction)
		
		if alignment > best_alignment:
			best_alignment = alignment
			best_edge = edge
	
	return best_edge  # Ahora retorna array vacío si no encuentra nada
