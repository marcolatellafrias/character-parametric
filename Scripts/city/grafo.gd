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
var node_types: Dictionary = {}      # {node_idx: int} tipo de nodo (0=normal, 1=límite)
var boundary_edges: Dictionary = {}  # {edge_key: bool} edges que forman el límite de la cara


# ============================================
# FUNCIÓN PRINCIPAL
# ============================================
func generate_graph(
	smooth_steps: int,
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int,
	generation_seed: int,
	boundary_face: Array = []  # Opcional: [Vector2, Vector2, Vector2, Vector2]
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
	node_types.clear()
	boundary_edges.clear()
	
	var edges_dict: Dictionary = {}
	var use_boundary = not boundary_face.is_empty() and boundary_face.size() == 4
	
	# 1. Generar puntos
	if use_boundary:
		_generate_points_with_boundary(boundary_face, min_distance, rejection_samples)
	else:
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
	
	# 2.5. Detectar nodos límite ANTES de subdividir
	_detect_boundary_nodes(faces)
	
	# 3. Subdividir caras
	var subdivided = _subdivide_faces(points, faces, node_types)
	points = subdivided["points"]
	faces = subdivided["faces"]
	node_types = subdivided["node_types"]
	boundary_edges = subdivided["boundary_edges"]
	
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

# ============================================
# GENERACIÓN DE PUNTOS CON CARA LÍMITE
# ============================================

func _generate_points_with_boundary(
	boundary_face: Array,
	min_distance: float,
	rejection_samples: int
) -> void:
	# 1. Generar puntos esquina (índices 0-3)
	for i in range(4):
		var corner_2d: Vector2 = boundary_face[i]
		points.append(Vector3(corner_2d.x, 0.0, corner_2d.y))
	
	# 2. Calcular cuántos puntos por lado basado en longitud y densidad
	var side_point_indices: Array[Array] = [[], [], [], []]
	
	for i in range(4):
		var start_idx = i
		var end_idx = (i + 1) % 4
		var start_pos = points[start_idx]
		var end_pos = points[end_idx]
		var side_length = start_pos.distance_to(end_pos)
		
		# Calcular número de puntos: al menos 1, máximo basado en longitud
		var num_points = max(1, int(side_length / min_distance) - 1)
		
		# Generar puntos equidistantes en este lado
		for j in range(1, num_points + 1):
			var t = float(j) / float(num_points + 1)
			var point = start_pos.lerp(end_pos, t)
			var point_idx = points.size()
			points.append(point)
			side_point_indices[i].append(point_idx)
	
	# 3. Marcar boundary edges
	for i in range(4):
		var start_corner = i
		var end_corner = (i + 1) % 4
		
		# Edge desde esquina inicial a primer punto del lado
		if side_point_indices[i].size() > 0:
			var first_side_point = side_point_indices[i][0]
			var key1 = _get_edge_key(start_corner, first_side_point)
			boundary_edges[key1] = true
			
			# Edges entre puntos del lado
			for j in range(side_point_indices[i].size() - 1):
				var p1 = side_point_indices[i][j]
				var p2 = side_point_indices[i][j + 1]
				var key = _get_edge_key(p1, p2)
				boundary_edges[key] = true
			
			# Edge desde último punto del lado a esquina final
			var last_side_point = side_point_indices[i][side_point_indices[i].size() - 1]
			var key2 = _get_edge_key(last_side_point, end_corner)
			boundary_edges[key2] = true
		else:
			# Sin puntos intermedios, edge directo entre esquinas
			var key = _get_edge_key(start_corner, end_corner)
			boundary_edges[key] = true
	
	# 4. Generar puntos Poisson dentro de la cara límite
	var poisson_points = _generate_poisson_inside_boundary(
		boundary_face,
		min_distance,
		rejection_samples
	)
	
	points.append_array(poisson_points)

func _generate_poisson_inside_boundary(
	boundary_face: Array,
	min_distance: float,
	rejection_samples: int
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	# Calcular bounding box de la cara límite
	var min_x = boundary_face[0].x
	var max_x = boundary_face[0].x
	var min_y = boundary_face[0].y
	var max_y = boundary_face[0].y
	
	for i in range(1, 4):
		min_x = min(min_x, boundary_face[i].x)
		max_x = max(max_x, boundary_face[i].x)
		min_y = min(min_y, boundary_face[i].y)
		max_y = max(max_y, boundary_face[i].y)
	
	var region_size = Vector2(max_x - min_x, max_y - min_y)
	var offset = Vector2(min_x, min_y)
	
	# Grid para Poisson
	var cell_size: float = min_distance / sqrt(2.0)
	var grid_width: int = ceil(region_size.x / cell_size)
	var grid_height: int = ceil(region_size.y / cell_size)
	
	var grid: Array = []
	grid.resize(grid_width * grid_height)
	
	# Agregar puntos existentes al grid
	for existing_point in points:
		var grid_pos = _point_to_grid_offset(existing_point, cell_size, offset)
		if grid_pos.x >= 0 and grid_pos.x < grid_width and grid_pos.y >= 0 and grid_pos.y < grid_height:
			grid[grid_pos.x + grid_pos.y * grid_width] = existing_point
	
	var active_list: Array[Vector3] = []
	
	# Primer punto dentro de la cara
	var first_point = _generate_random_point_inside_quad(boundary_face)
	if first_point != Vector3.ZERO:
		result.append(first_point)
		active_list.append(first_point)
		var grid_pos = _point_to_grid_offset(first_point, cell_size, offset)
		if grid_pos.x >= 0 and grid_pos.x < grid_width and grid_pos.y >= 0 and grid_pos.y < grid_height:
			grid[grid_pos.x + grid_pos.y * grid_width] = first_point
	
	# Generar puntos
	while active_list.size() > 0:
		var random_index = randi() % active_list.size()
		var point = active_list[random_index]
		var found = false
		
		for i in range(rejection_samples):
			var new_point = _generate_point_around(point, min_distance)
			
			# Verificar que esté dentro de la cara límite
			if not _is_point_inside_quad(Vector2(new_point.x, new_point.z), boundary_face):
				continue
			
			if _is_valid_point_with_existing(new_point, grid, cell_size, grid_width, grid_height, min_distance, offset):
				result.append(new_point)
				active_list.append(new_point)
				var new_grid_pos = _point_to_grid_offset(new_point, cell_size, offset)
				if new_grid_pos.x >= 0 and new_grid_pos.x < grid_width and new_grid_pos.y >= 0 and new_grid_pos.y < grid_height:
					grid[new_grid_pos.x + new_grid_pos.y * grid_width] = new_point
				found = true
		
		if not found:
			active_list.remove_at(random_index)
	
	return result

func _generate_random_point_inside_quad(quad: Array) -> Vector3:
	# Generar punto aleatorio usando coordenadas baricéntricas
	for attempt in range(100):
		var s = randf()
		var t = randf()
		
		# Interpolar bilinealmente en el quad
		var p0 = quad[0]
		var p1 = quad[1]
		var p2 = quad[2]
		var p3 = quad[3]
		
		var point_2d = (1 - s) * (1 - t) * p0 + s * (1 - t) * p1 + s * t * p2 + (1 - s) * t * p3
		
		if _is_point_inside_quad(point_2d, quad):
			return Vector3(point_2d.x, 0.0, point_2d.y)
	
	return Vector3.ZERO

func _is_point_inside_quad(point: Vector2, quad: Array) -> bool:
	# Usar ray casting
	var intersections = 0
	
	for i in range(4):
		var v1 = quad[i]
		var v2 = quad[(i + 1) % 4]
		
		if ((v1.y > point.y) != (v2.y > point.y)) and \
		   (point.x < (v2.x - v1.x) * (point.y - v1.y) / (v2.y - v1.y) + v1.x):
			intersections += 1
	
	return intersections % 2 == 1

static func _point_to_grid_offset(point: Vector3, cell_size: float, offset: Vector2) -> Vector2i:
	return Vector2i(
		int((point.x - offset.x) / cell_size),
		int((point.z - offset.y) / cell_size)
	)

static func _is_valid_point_with_existing(
	point: Vector3,
	grid: Array,
	cell_size: float,
	grid_width: int,
	grid_height: int,
	min_distance: float,
	offset: Vector2
) -> bool:
	var grid_pos = _point_to_grid_offset(point, cell_size, offset)
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

# ============================================
# DETECCIÓN DE NODOS LÍMITE
# ============================================

## Detecta y marca los nodos que están en el límite del mapa
## Un nodo está en el límite si forma parte de un edge que pertenece a una sola cara
func _detect_boundary_nodes(faces_array: Array) -> void:
	node_types.clear()
	
	# Inicializar todos los nodos como normales (tipo 0)
	for i in range(points.size()):
		node_types[i] = 0
	
	# Contar cuántas caras usan cada edge
	var edge_usage: Dictionary = {}
	
	for face in faces_array:
		for i in range(face.size()):
			var next_i = (i + 1) % face.size()
			var edge_key = _get_edge_key(face[i], face[next_i])
			
			if edge_key not in edge_usage:
				edge_usage[edge_key] = 0
			edge_usage[edge_key] += 1
	
	# Los edges que aparecen solo en una cara son edges límite
	for edge_key in edge_usage:
		if edge_usage[edge_key] == 1:
			# Extraer los índices del edge_key
			var parts = edge_key.split("_")
			var idx1 = int(parts[0])
			var idx2 = int(parts[1])
			
			# Marcar ambos nodos como límite
			node_types[idx1] = 1
			node_types[idx2] = 1

	
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
func _subdivide_faces(points: Array[Vector3], faces: Array, node_types: Dictionary) -> Dictionary:
	var new_points = points.duplicate()
	var new_faces = []
	var new_node_types = node_types.duplicate()
	var new_boundary_edges = {}
	var edge_midpoints = {}
	
	# Copiar boundary_edges existentes como parent edges
	var parent_boundary_edges = boundary_edges.duplicate()
	
	for face in faces:
		var sub_faces = []
		
		if face.size() == 4:
			sub_faces = _subdivide_quad_face(face, new_points, edge_midpoints, new_node_types, parent_boundary_edges, new_boundary_edges)
		elif face.size() == 3:
			sub_faces = _subdivide_triangle_face(face, new_points, edge_midpoints, new_node_types, parent_boundary_edges, new_boundary_edges)
		
		new_faces.append_array(sub_faces)
	
	return {
		"points": new_points,
		"faces": new_faces,
		"node_types": new_node_types,
		"boundary_edges": new_boundary_edges
	}

static func _subdivide_quad_face(
	face: Array,
	points: Array[Vector3],
	edge_midpoints: Dictionary,
	node_types: Dictionary,
	parent_boundary_edges: Dictionary,
	new_boundary_edges: Dictionary
) -> Array:
	# Obtener o crear puntos medios
	var idx_mid1 = _get_or_create_midpoint(face[0], face[1], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	var idx_mid2 = _get_or_create_midpoint(face[1], face[2], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	var idx_mid3 = _get_or_create_midpoint(face[2], face[3], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	var idx_mid4 = _get_or_create_midpoint(face[3], face[0], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	
	# El centro sigue siendo único por cara y siempre es tipo 0 (normal)
	var p1 = points[face[0]]
	var p2 = points[face[1]]
	var p3 = points[face[2]]
	var p4 = points[face[3]]
	var center = (p1 + p2 + p3 + p4) / 4.0
	var idx_center = points.size()
	points.append(center)
	node_types[idx_center] = 0
	
	var result = []
	result.append([face[0], idx_mid1, idx_center, idx_mid4])
	result.append([idx_mid1, face[1], idx_mid2, idx_center])
	result.append([idx_center, idx_mid2, face[2], idx_mid3])
	result.append([idx_mid4, idx_center, idx_mid3, face[3]])
	
	return result

static func _subdivide_triangle_face(
	face: Array,
	points: Array[Vector3],
	edge_midpoints: Dictionary,
	node_types: Dictionary,
	parent_boundary_edges: Dictionary,
	new_boundary_edges: Dictionary
) -> Array:
	# Obtener o crear puntos medios
	var idx_mid1 = _get_or_create_midpoint(face[0], face[1], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	var idx_mid2 = _get_or_create_midpoint(face[1], face[2], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	var idx_mid3 = _get_or_create_midpoint(face[2], face[0], points, edge_midpoints, node_types, parent_boundary_edges, new_boundary_edges)
	
	# El centro sigue siendo único por cara y siempre es tipo 0 (normal)
	var p1 = points[face[0]]
	var p2 = points[face[1]]
	var p3 = points[face[2]]
	var center = (p1 + p2 + p3) / 3.0
	var idx_center = points.size()
	points.append(center)
	node_types[idx_center] = 0
	
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

static func _get_or_create_midpoint(
	idx1: int,
	idx2: int,
	points: Array[Vector3],
	cache: Dictionary,
	node_types: Dictionary,
	parent_boundary_edges: Dictionary,
	new_boundary_edges: Dictionary
) -> int:
	var key = _get_edge_key(idx1, idx2)
	
	if key in cache:
		return cache[key]
	
	var midpoint = (points[idx1] + points[idx2]) / 2.0
	var new_idx = points.size()
	points.append(midpoint)
	
	# Determinar el tipo del punto medio
	var type1 = node_types.get(idx1, 0)
	var type2 = node_types.get(idx2, 0)
	
	if type1 == 1 and type2 == 1:
		node_types[new_idx] = 1
	else:
		node_types[new_idx] = 0
	
	# Si el edge padre era boundary, los hijos también lo son
	if key in parent_boundary_edges:
		var key1 = _get_edge_key(idx1, new_idx)
		var key2 = _get_edge_key(new_idx, idx2)
		new_boundary_edges[key1] = true
		new_boundary_edges[key2] = true
	
	cache[key] = new_idx
	return new_idx

# ============================================
# CONSULTAS DEL GRAFO
# ============================================

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

func get_inscribed_square_for_face(face_idx: int, use_original_size: bool = false) -> Array[Vector3]:
	if face_idx < 0 or face_idx >= faces.size():
		push_error("Índice de cara inválido: ", face_idx)
		return []

	var face = faces[face_idx]
	var quad_2d: Array = []
	for idx in face:
		if idx >= points.size():
			push_error("Índice de punto inválido en cara: ", idx)
			return []
		var p = points[idx]
		quad_2d.append(Vector2(p.x, p.z))

	var override_size = null
	if use_original_size and face_idx in original_inscribed_sizes:
		override_size = original_inscribed_sizes[face_idx]

	var inscribed_2d: Array = GraphHelper.get_inscribed_square(quad_2d, override_size)

	if inscribed_2d.is_empty():
		return []

	var inscribed_3d: Array[Vector3] = []
	for p2d in inscribed_2d:
		inscribed_3d.append(Vector3(p2d.x, 0.0, p2d.y))

	return inscribed_3d

func get_average_closest_inscribed_point(node_idx: int, use_original_size: bool = false) -> Vector3:
	if node_idx < 0 or node_idx >= points.size():
		push_error("Índice de nodo inválido: ", node_idx)
		return Vector3.ZERO
	
	var connected_quads: Array[int] = get_quads_for_node(node_idx)
	
	if connected_quads.is_empty():
		push_warning("El nodo ", node_idx, " no tiene caras conectadas")
		return Vector3.ZERO
	
	var node_position: Vector3 = points[node_idx]
	var corresponding_points: Array[Vector3] = []
	
	for face_idx in connected_quads:
		var face = faces[face_idx]
		
		var face_2d: Array = []
		var center_2d := Vector2.ZERO
		for idx in face:
			var p = points[idx]
			var p2d = Vector2(p.x, p.z)
			face_2d.append(p2d)
			center_2d += p2d
		center_2d /= face.size()
		
		var centered_face: Array = []
		for p2d in face_2d:
			centered_face.append(p2d - center_2d)
		
		var sorted_indices = _get_clockwise_sorted_indices(centered_face)
		
		var clockwise_index := -1
		for i in range(sorted_indices.size()):
			if face[sorted_indices[i]] == node_idx:
				clockwise_index = i
				break
		
		if clockwise_index == -1:
			push_warning("No se pudo encontrar el nodo en la cara")
			continue
		
		var inscribed_square: Array[Vector3] = get_inscribed_square_for_face(face_idx, use_original_size)
		
		if inscribed_square.is_empty():
			continue
		
		var corresponding_point: Vector3
		if face.size() == 4:
			corresponding_point = inscribed_square[clockwise_index]
		else:
			if clockwise_index < 3:
				corresponding_point = inscribed_square[clockwise_index]
			else:
				corresponding_point = inscribed_square[0]
		
		corresponding_points.append(corresponding_point)
	
	if corresponding_points.is_empty():
		push_warning("No se pudieron calcular puntos correspondientes para las caras del nodo ", node_idx)
		return Vector3.ZERO
	
	var average_position: Vector3 = Vector3.ZERO
	for point in corresponding_points:
		average_position += point
	
	average_position /= corresponding_points.size()
	
	return average_position

static func _get_clockwise_sorted_indices(centered_vertices: Array) -> Array:
	var angles := []
	for i in range(centered_vertices.size()):
		var angle := atan2(centered_vertices[i].y, centered_vertices[i].x)
		angles.append({"index": i, "angle": angle})
	
	angles.sort_custom(func(a, b): return a["angle"] > b["angle"])
	
	var sorted_indices := []
	for item in angles:
		sorted_indices.append(item["index"])
	
	return sorted_indices

func move_nodes(node_transformations: Dictionary) -> void:
	for node_idx in node_transformations:
		if node_idx >= 0 and node_idx < points.size():
			points[node_idx] = node_transformations[node_idx]
		else:
			push_warning("move_nodes: Índice de nodo %d fuera de rango (0-%d)" % [node_idx, points.size() - 1])

func smooth_graph() -> void:
	var use_original_size: bool = (smoothing_steps > 0)
	var node_transformations: Dictionary = {}
	
	# Calcular nueva posición para cada nodo, excepto boundary nodes
	for node_idx in range(points.size()):
		# Verificar si este nodo está en algún boundary edge
		var is_boundary_node = false
		for edge_key in boundary_edges:
			var parts = edge_key.split("_")
			var idx1 = int(parts[0])
			var idx2 = int(parts[1])
			
			if node_idx == idx1 or node_idx == idx2:
				is_boundary_node = true
				break
		
		# Solo mover nodos que no están en el boundary
		if not is_boundary_node:
			var new_position = get_average_closest_inscribed_point(node_idx, use_original_size)
			node_transformations[node_idx] = new_position
	
	move_nodes(node_transformations)
	smoothing_steps += 1
	
func get_adjacent_faces(face_idx: int) -> Array[int]:
	var adjacent: Array[int] = []
	
	if face_idx < 0 or face_idx >= faces.size():
		return adjacent
	
	var face = faces[face_idx]
	var face_edges: Dictionary = {}
	for i in range(face.size()):
		var next_i = (i + 1) % face.size()
		var edge_key = _get_edge_key(face[i], face[next_i])
		face_edges[edge_key] = true
	
	for other_face_idx in range(faces.size()):
		if other_face_idx == face_idx:
			continue
		
		var other_face = faces[other_face_idx]
		
		for i in range(other_face.size()):
			var next_i = (i + 1) % other_face.size()
			var edge_key = _get_edge_key(other_face[i], other_face[next_i])
			
			if edge_key in face_edges:
				adjacent.append(other_face_idx)
				break
	
	return adjacent

func get_edges_for_node(node_idx: int) -> Array:
	var connected: Array = []
	
	for edge in edges:
		if edge[0] == node_idx or edge[1] == node_idx:
			connected.append(edge)
	
	return connected
	
func select_opposite_edges(node_idx: int, node_edges: Array) -> Array:
	if node_edges.size() < 2:
		return []
	
	var node_pos = points[node_idx]
	var directions: Array = []
	for edge in node_edges:
		var other_node = edge[1] if edge[0] == node_idx else edge[0]
		var other_pos = points[other_node]
		var direction = (other_pos - node_pos).normalized()
		directions.append({"edge": edge, "direction": direction})
	
	var best_pair = []
	var best_opposition = 0.5
	
	for i in range(directions.size()):
		for j in range(i + 1, directions.size()):
			var dot = directions[i]["direction"].dot(directions[j]["direction"])
			if dot < -best_opposition:
				best_opposition = dot
				best_pair = [directions[i]["edge"], directions[j]["edge"]]
	
	if best_pair.is_empty():
		node_edges.shuffle()
		return [node_edges[0], node_edges[1]]
	
	return best_pair
	
func is_boundary_node(node_idx: int, edge_types: Dictionary) -> bool:
	var connected_edges = get_edges_for_node(node_idx)
	
	for edge in connected_edges:
		var edge_key = _get_edge_key(edge[0], edge[1])
		if edge_types.get(edge_key, 1) == -1:
			return true
	
	return false

func get_next_edge_in_direction(
	current_node: int, 
	previous_node: int, 
	edge_types: Dictionary,
	desired_type: int
) -> Array:
	var connected_edges = get_edges_for_node(current_node)
	var current_pos = points[current_node]
	var previous_pos = points[previous_node]
	var current_direction = (current_pos - previous_pos).normalized()
	
	var best_edge: Array = []
	var best_alignment = -2.0
	
	for edge in connected_edges:
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		if other_node == previous_node:
			continue
		
		var edge_key = _get_edge_key(edge[0], edge[1])
		var current_type = edge_types.get(edge_key, 1)
		
		if current_type != desired_type and current_type != 1:
			continue
		
		var other_pos = points[other_node]
		var edge_direction = (other_pos - current_pos).normalized()
		var alignment = current_direction.dot(edge_direction)
		
		if alignment > best_alignment:
			best_alignment = alignment
			best_edge = edge
	
	return best_edge
