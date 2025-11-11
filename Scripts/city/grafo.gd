class_name GraphGenerator
extends RefCounted

# ============================================
# ESTRUCTURA DE RETORNO
# ============================================
# {
#   "points": Array[Vector3],        # Nodos del grafo
#   "edges": Array[Array],           # [[idx1, idx2], ...] aristas
#   "faces": Array[Array]            # [[idx1, idx2, idx3, ...], ...] caras
# }

# ============================================
# FUNCIÓN PRINCIPAL
# ============================================
static func generate_graph(
	region_size: Vector2 = Vector2(10, 10),
	min_distance: float = 5.3,
	rejection_samples: int = 30,
	max_angle_threshold: float = 0.825 * PI,
	min_quad_angle: float = 0.2 * PI,
	max_quad_angle: float = 0.9 * PI,
	use_seed: bool = true,
	generation_seed: int = 12345
) -> Dictionary:
	
	if use_seed:
		seed(generation_seed)
	
	var points: Array[Vector3] = []
	var edges_dict: Dictionary = {}
	var faces: Array = []
	
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
	var edges: Array[Array] = []
	for edge in edges_dict.values():
		edges.append(edge)
	
	return {
		"points": points,
		"edges": edges,
		"faces": faces
	}

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

# Función helper
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


# ============================================
# CONSULTAS DEL GRAFO
# ============================================

## Retorna los índices de las caras (quads) que contienen el nodo especificado
## @param node_idx: Índice del nodo a consultar
## @param faces: Array de caras del grafo
## @return: Array[int] con los índices de las caras que contienen el nodo
static func get_quads_for_node(node_idx: int, faces: Array) -> Array[int]:
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
## @param points: Array[Vector3] con todos los puntos del grafo
## @param faces: Array de caras del grafo
## @return: Array[Vector3] con los 4 vértices del cuadrado inscrito (o vacío si la cara no es válida)
static func get_inscribed_square_for_face(face_idx: int, points: Array[Vector3], faces: Array) -> Array[Vector3]:
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

	# Obtener el cuadrado inscrito (en 2D)
	var inscribed_2d: Array = GraphHelper.get_inscribed_square(quad_2d)

	if inscribed_2d.is_empty():
		return []

	# Convertir de vuelta a Vector3 (con y = 0)
	var inscribed_3d: Array[Vector3] = []
	for p2d in inscribed_2d:
		inscribed_3d.append(Vector3(p2d.x, 0.0, p2d.y))

	return inscribed_3d
