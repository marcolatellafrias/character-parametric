class_name GraphGenerator
extends RefCounted

# ============================================
# ESTADO DEL GRAFO
# ============================================
var points: Array[Vector3] = []
var edges: Array[Array] = []
var faces: Array = []
var smoothing_steps: int = 0
var original_inscribed_sizes: Dictionary = {}
var node_types: Dictionary = {}
var boundary_edges: Dictionary = {}


# ============================================
# FUNCIÓN PRINCIPAL
# ============================================
func generate_graph(
	smooth_steps: int,
	region_size: Vector2,
	min_distance: float,
	rejection_samples: int,
	generation_seed: int
) -> void:
	var max_angle_threshold: float = 0.825 * PI
	var min_quad_angle: float = 0.2 * PI
	var max_quad_angle: float = 0.9 * PI
	
	seed(generation_seed)
	
	points.clear()
	edges.clear()
	faces.clear()
	smoothing_steps = 0
	original_inscribed_sizes.clear()
	node_types.clear()
	boundary_edges.clear()
	
	var edges_dict: Dictionary = {}
	
	points = _generate_poisson_points_standard(region_size, min_distance, rejection_samples)
	
	var graph_data = _build_graph_from_delaunay(points, max_angle_threshold, min_quad_angle, max_quad_angle)
	points = graph_data["points"]
	edges_dict = graph_data["edges"]
	faces = graph_data["faces"]
	
	_detect_boundary_nodes(faces)
	
	var subdivided = _subdivide_faces(points, faces, node_types, boundary_edges)
	points = subdivided["points"]
	faces = subdivided["faces"]
	node_types = subdivided["node_types"]
	boundary_edges = subdivided["boundary_edges"]
	
	_normalize_face_orientation(faces, true)
	
	edges_dict.clear()
	for face in faces:
		for i in range(face.size()):
			var next_i = (i + 1) % face.size()
			var key = _get_edge_key(face[i], face[next_i])
			edges_dict[key] = [face[i], face[next_i]]
	
	for edge in edges_dict.values():
		edges.append(edge)
	
	_calculate_original_inscribed_sizes()
	
	for i in range(smooth_steps):
		smooth_graph()


# ============================================
# DETECCIÓN DE NODOS LÍMITE
# ============================================
func _detect_boundary_nodes(faces_array: Array) -> void:
	for i in range(points.size()):
		if i not in node_types:
			node_types[i] = 0
	
	var edge_usage: Dictionary = {}
	
	for face in faces_array:
		for i in range(face.size()):
			var next_i = (i + 1) % face.size()
			var edge_key = _get_edge_key(face[i], face[next_i])
			
			if edge_key not in edge_usage:
				edge_usage[edge_key] = 0
			edge_usage[edge_key] += 1
	
	for edge_key in edge_usage:
		if edge_usage[edge_key] == 1:
			var parts = edge_key.split("_")
			var idx1 = int(parts[0])
			var idx2 = int(parts[1])
			
			node_types[idx1] = 1
			node_types[idx2] = 1
			boundary_edges[edge_key] = true


func _calculate_original_inscribed_sizes() -> void:
	original_inscribed_sizes.clear()
	
	for face_idx in range(faces.size()):
		var inscribed_square: Array[Vector3] = get_inscribed_square_for_face(face_idx)
		
		if inscribed_square.size() >= 2:
			var size: float = inscribed_square[0].distance_to(inscribed_square[1])
			original_inscribed_sizes[face_idx] = size


# ============================================
# POISSON DISK SAMPLING
# ============================================
func _generate_poisson_points_standard(
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
	
	var first_point = Vector3(
		randf() * region_size.x,
		0.0,
		randf() * region_size.y
	)
	points.append(first_point)
	active_list.append(first_point)
	var grid_pos = _point_to_grid(first_point, cell_size)
	grid[grid_pos.x + grid_pos.y * grid_width] = first_point
	
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
				if point.distance_to(neighbor) < min_distance:
					return false
	
	return true

static func _point_to_grid(point: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(int(point.x / cell_size), int(point.z / cell_size))


# ============================================
# CONSTRUCCIÓN DEL GRAFO DESDE DELAUNAY
# ============================================
func _build_graph_from_delaunay(
	points: Array[Vector3],
	max_angle_threshold: float,
	min_quad_angle: float,
	max_quad_angle: float
) -> Dictionary:
	
	var edges: Dictionary = {}
	var faces: Array = []
	
	if points.size() < 3:
		return {"points": points, "edges": edges, "faces": faces}
	
	var points_2d: PackedVector2Array = PackedVector2Array()
	for point in points:
		points_2d.append(Vector2(point.x, point.z))
	
	var indices: PackedInt32Array = Geometry2D.triangulate_delaunay(points_2d)
	
	var triangles = []
	for i in range(0, indices.size(), 3):
		triangles.append([indices[i], indices[i + 1], indices[i + 2]])
	
	var filtered_triangles = []
	for tri in triangles:
		if _is_valid_triangle(tri, points, max_angle_threshold):
			filtered_triangles.append(tri)
	
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
static func _subdivide_faces(
	points: Array[Vector3],
	faces: Array,
	node_types: Dictionary,
	boundary_edges_dict: Dictionary
) -> Dictionary:
	var new_points = points.duplicate()
	var new_faces = []
	var new_node_types = node_types.duplicate()
	var new_boundary_edges = boundary_edges_dict.duplicate()
	var edge_midpoints = {}
	
	for face in faces:
		var sub_faces = []
		
		if face.size() == 4:
			sub_faces = _subdivide_quad_face(face, new_points, edge_midpoints, new_node_types, new_boundary_edges)
		elif face.size() == 3:
			sub_faces = _subdivide_triangle_face(face, new_points, edge_midpoints, new_node_types, new_boundary_edges)
		
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
	boundary_edges: Dictionary
) -> Array:
	var idx_mid1 = _get_or_create_midpoint(face[0], face[1], points, edge_midpoints, node_types, boundary_edges)
	var idx_mid2 = _get_or_create_midpoint(face[1], face[2], points, edge_midpoints, node_types, boundary_edges)
	var idx_mid3 = _get_or_create_midpoint(face[2], face[3], points, edge_midpoints, node_types, boundary_edges)
	var idx_mid4 = _get_or_create_midpoint(face[3], face[0], points, edge_midpoints, node_types, boundary_edges)
	
	var center = (points[face[0]] + points[face[1]] + points[face[2]] + points[face[3]]) / 4.0
	var idx_center = points.size()
	points.append(center)
	node_types[idx_center] = 0
	
	return [
		[face[0], idx_mid1, idx_center, idx_mid4],
		[idx_mid1, face[1], idx_mid2, idx_center],
		[idx_center, idx_mid2, face[2], idx_mid3],
		[idx_mid4, idx_center, idx_mid3, face[3]]
	]

static func _subdivide_triangle_face(
	face: Array,
	points: Array[Vector3],
	edge_midpoints: Dictionary,
	node_types: Dictionary,
	boundary_edges: Dictionary
) -> Array:
	var idx_mid1 = _get_or_create_midpoint(face[0], face[1], points, edge_midpoints, node_types, boundary_edges)
	var idx_mid2 = _get_or_create_midpoint(face[1], face[2], points, edge_midpoints, node_types, boundary_edges)
	var idx_mid3 = _get_or_create_midpoint(face[2], face[0], points, edge_midpoints, node_types, boundary_edges)
	
	var center = (points[face[0]] + points[face[1]] + points[face[2]]) / 3.0
	var idx_center = points.size()
	points.append(center)
	node_types[idx_center] = 0
	
	return [
		[face[0], idx_mid1, idx_center, idx_mid3],
		[idx_mid1, face[1], idx_mid2, idx_center],
		[idx_center, idx_mid2, face[2], idx_mid3]
	]


# ============================================
# UTILIDADES
# ============================================
static func _get_edge_key(idx1: int, idx2: int) -> String:
	return str(min(idx1, idx2)) + "_" + str(max(idx1, idx2))

static func _calculate_angle(vertex: Vector3, p1: Vector3, p2: Vector3) -> float:
	var v1 = (p1 - vertex).normalized()
	var v2 = (p2 - vertex).normalized()
	return acos(clamp(v1.dot(v2), -1.0, 1.0))

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
	boundary_edges: Dictionary
) -> int:
	var key = _get_edge_key(idx1, idx2)
	
	if key in cache:
		return cache[key]
	
	var midpoint = (points[idx1] + points[idx2]) / 2.0
	var new_idx = points.size()
	points.append(midpoint)
	
	var is_boundary_edge = boundary_edges.get(key, false)
	var type1 = node_types.get(idx1, 0)
	var type2 = node_types.get(idx2, 0)
	
	if is_boundary_edge or (type1 == 1 and type2 == 1):
		node_types[new_idx] = 1
		boundary_edges[_get_edge_key(idx1, new_idx)] = true
		boundary_edges[_get_edge_key(new_idx, idx2)] = true
	else:
		node_types[new_idx] = 0
	
	cache[key] = new_idx
	return new_idx


# ============================================
# CONSULTAS DEL GRAFO
# ============================================
func get_quads_for_node(node_idx: int) -> Array[int]:
	var connected_quads: Array[int] = []
	for i in range(faces.size()):
		if node_idx in faces[i]:
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
	
	if node_types.get(node_idx, 0) == 1:
		return points[node_idx]
	
	var connected_quads: Array[int] = get_quads_for_node(node_idx)
	
	if connected_quads.is_empty():
		push_warning("El nodo ", node_idx, " no tiene caras conectadas")
		return Vector3.ZERO
	
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
			push_warning("No se pudo encontrar el nodo en la cara (esto no debería pasar)")
			continue
		
		var inscribed_square: Array[Vector3] = get_inscribed_square_for_face(face_idx, use_original_size)
		
		if inscribed_square.is_empty():
			continue
		
		var corresponding_point: Vector3
		if face.size() == 4:
			corresponding_point = inscribed_square[clockwise_index]
		else:
			corresponding_point = inscribed_square[clockwise_index if clockwise_index < 3 else 0]
		
		corresponding_points.append(corresponding_point)
	
	if corresponding_points.is_empty():
		push_warning("No se pudieron calcular puntos correspondientes para las caras del nodo ", node_idx)
		return Vector3.ZERO
	
	var average_position := Vector3.ZERO
	for point in corresponding_points:
		average_position += point
	
	return average_position / corresponding_points.size()


static func _get_clockwise_sorted_indices(centered_vertices: Array) -> Array:
	var angles := []
	for i in range(centered_vertices.size()):
		angles.append({"index": i, "angle": atan2(centered_vertices[i].y, centered_vertices[i].x)})
	
	angles.sort_custom(func(a, b): return a["angle"] > b["angle"])
	
	var sorted_indices := []
	for item in angles:
		sorted_indices.append(item["index"])
	
	return sorted_indices


func move_nodes(node_transformations: Dictionary) -> void:
	for node_idx in node_transformations:
		if node_idx >= 0 and node_idx < points.size():
			if node_types.get(node_idx, 0) != 1:
				points[node_idx] = node_transformations[node_idx]
		else:
			push_warning("move_nodes: Índice de nodo %d fuera de rango (0-%d)" % [node_idx, points.size() - 1])

func smooth_graph() -> void:
	var use_original_size: bool = (smoothing_steps > 0)
	var node_transformations: Dictionary = {}
	
	for node_idx in range(points.size()):
		if node_types.get(node_idx, 0) == 0:
			node_transformations[node_idx] = get_average_closest_inscribed_point(node_idx, use_original_size)
	
	move_nodes(node_transformations)
	smoothing_steps += 1

func get_adjacent_faces(face_idx: int) -> Array[int]:
	var adjacent: Array[int] = []
	
	if face_idx < 0 or face_idx >= faces.size():
		return adjacent
	
	var face = faces[face_idx]
	var face_edges: Dictionary = {}
	for i in range(face.size()):
		face_edges[_get_edge_key(face[i], face[(i + 1) % face.size()])] = true
	
	for other_face_idx in range(faces.size()):
		if other_face_idx == face_idx:
			continue
		
		var other_face = faces[other_face_idx]
		for i in range(other_face.size()):
			if _get_edge_key(other_face[i], other_face[(i + 1) % other_face.size()]) in face_edges:
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
		directions.append({"edge": edge, "direction": (points[other_node] - node_pos).normalized()})
	
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
	for edge in get_edges_for_node(node_idx):
		if edge_types.get(_get_edge_key(edge[0], edge[1]), 1) == -1:
			return true
	return false

func get_next_edge_in_direction(
	current_node: int,
	previous_node: int,
	edge_types: Dictionary,
	desired_type: int
) -> Array:
	var current_pos = points[current_node]
	var current_direction = (current_pos - points[previous_node]).normalized()
	
	var best_edge: Array = []
	var best_alignment = -2.0
	
	for edge in get_edges_for_node(current_node):
		var other_node = edge[1] if edge[0] == current_node else edge[0]
		if other_node == previous_node:
			continue
		
		var current_type = edge_types.get(_get_edge_key(edge[0], edge[1]), 1)
		if current_type != desired_type and current_type != 1:
			continue
		
		var alignment = current_direction.dot((points[other_node] - current_pos).normalized())
		if alignment > best_alignment:
			best_alignment = alignment
			best_edge = edge
	
	return best_edge

func _normalize_face_orientation(faces_array: Array, desired_clockwise: bool = true) -> void:
	for i in range(faces_array.size()):
		var face = faces_array[i]
		if _is_face_clockwise_3d(face) != desired_clockwise:
			face.reverse()
			faces_array[i] = face

func _is_face_clockwise_3d(face: Array) -> bool:
	var area := 0.0
	var n := face.size()
	for i in range(n):
		var a := points[face[i]]
		var b := points[face[(i + 1) % n]]
		area += (b.x - a.x) * (b.z + a.z)
	return area > 0.0
