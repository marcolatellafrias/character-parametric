extends Area3D
class_name LaneVolume

# ============================================================================
# TRAFFIC DENSITY POR TIPO DE CALLE
# ============================================================================
const STREET_TYPE_TRAFFIC_DENSITY = {
	-1: 0.0,  # Boundary - sin tráfico (borde del mapa)
	0: 0.4,   # Small street - tráfico bajo
	1: 0.7,   # Medium street - tráfico medio
	2: 1.0    # Large street - tráfico alto
}

var face_idx: int
var edge_idx: int
var start_plane_vertices: Array
var end_plane_vertices: Array
var width_cells: int
var height_cells: int
var street_type: int
var volume_height: float

var neighborhood: Neighborhood

var raw_data: Dictionary

var collision_shape: CollisionShape3D

var cells_per_floor: int

var traffic_light_index: int = -1  # -1 = sin semáforo, 0 o 1 = índice de grupo
var is_traffic_light_active: bool = true  # Estado actual del semáforo
var traffic_light_body: StaticBody3D = null

func _init(volume_data: Dictionary) -> void:
	raw_data = volume_data
	face_idx = volume_data.get("face_idx", -1)
	edge_idx = volume_data.get("edge_idx", -1)
	start_plane_vertices = volume_data.get("start_plane_vertices", [])
	end_plane_vertices = volume_data.get("end_plane_vertices", [])
	width_cells = volume_data.get("width_cells", 3)
	height_cells = volume_data.get("height_cells", 10)
	street_type = volume_data.get("street_type", 0)
	volume_height = volume_data.get("height", 0.0)
	neighborhood = volume_data.get("neighborhood", null)
	cells_per_floor = volume_data.get("cells_per_floor", 5)
	traffic_light_index = volume_data.get("traffic_light_index", -1)
	
	_setup_area()
	_generate_collision()

func _setup_area() -> void:
	monitoring = true
	monitorable = true
	
	collision_layer = 2
	collision_mask = 0
	
	add_to_group("lane_volumes")
	
	set_meta("face_idx", face_idx)
	set_meta("edge_idx", edge_idx)
	set_meta("street_type", street_type)
	set_meta("lane_id", get_id())
	
	if neighborhood:
		set_meta("neighborhood_type", neighborhood.type)
		set_meta("neighborhood_name", neighborhood.get_type_name())
		set_meta("neighborhood_base_density", neighborhood.traffic_density)
	
	set_meta("traffic_density", get_traffic_density())

func _generate_collision() -> void:
	collision_shape = DebugUtil.create_collision_shape_from_planes(
		start_plane_vertices,
		end_plane_vertices
	)
	
	if collision_shape:
		add_child(collision_shape)

func setup_traffic_light_body() -> void:
	if traffic_light_index == -1:
		print("[LaneVolume %s] Sin semáforo (index -1)" % get_id())
		return
	
	if traffic_light_body != null:
		print("[LaneVolume %s] Traffic light body ya existe" % get_id())
		return
	
	traffic_light_body = StaticBody3D.new()
	traffic_light_body.name = "TrafficLight_" + get_id()
	traffic_light_body.collision_mask = 0
	
	var collision = DebugUtil.create_collision_shape_from_plane(end_plane_vertices)
	if collision:
		traffic_light_body.add_child(collision)
		print("[LaneVolume %s] Traffic light body creado (index %d)" % [get_id(), traffic_light_index])
	else:
		print("[LaneVolume %s] ERROR: No se pudo crear collision shape" % get_id())
		return
	
	add_child(traffic_light_body)
	
	if is_traffic_light_active:
		traffic_light_body.collision_layer = 0
		print("[LaneVolume %s] Semáforo VERDE (layer 0)" % get_id())
	else:
		traffic_light_body.collision_layer = 2
		print("[LaneVolume %s] Semáforo ROJO (layer 2)" % get_id())

# ============================================================================
# MÉTODOS DE BARRIO
# ============================================================================

func get_neighborhood() -> Neighborhood:
	return neighborhood

func get_traffic_density() -> float:
	# Factor 1: Densidad base del tipo de calle
	var street_density = STREET_TYPE_TRAFFIC_DENSITY.get(street_type, 0.5)
	
	# Factor 2: Densidad del barrio
	var neighborhood_density = 0.5  # Default neutral
	if neighborhood:
		neighborhood_density = neighborhood.traffic_density
	
	# Combinar ambos factores (multiplicación para que se influencien mutuamente)
	# Una small street en downtown tendrá menos tráfico que una large street en downtown
	# Una large street en shanty town tendrá menos tráfico que una large street en downtown
	return street_density * neighborhood_density

func get_neighborhood_type() -> int:
	if neighborhood:
		return neighborhood.type
	return -1

func get_neighborhood_name() -> String:
	if neighborhood:
		return neighborhood.get_type_name()
	return "Unknown"

# ============================================================================
# MÉTODOS DE SEMÁFOROS
# ============================================================================

func get_end_node_index(plain_graph) -> int:
	if plain_graph == null or face_idx < 0 or face_idx >= plain_graph.faces.size():
		return -1
	
	var face = plain_graph.faces[face_idx]
	# El end_node es el segundo nodo del edge en sentido clockwise
	return face[(edge_idx + 1) % face.size()]

func set_traffic_light_active(active: bool) -> void:
	is_traffic_light_active = active
	
	if traffic_light_body:
		if active:
			# Verde - sin colisión (layer 0 = ninguna layer)
			traffic_light_body.collision_layer = 0
			print("[LaneVolume %s] Semáforo cambiado a VERDE (layer 0)" % get_id())
		else:
			# Rojo - con colisión (layer 2 = detectado por ghosts)
			traffic_light_body.collision_layer = 2
			print("[LaneVolume %s] Semáforo cambiado a ROJO (layer 2)" % get_id())

func is_allowed_to_spawn() -> bool:
	# Si no tiene semáforo (índice -1), siempre puede spawnear
	if traffic_light_index == -1:
		return true
	
	return is_traffic_light_active

# ============================================================================
# MÉTODOS DE GEOMETRÍA Y PATH
# ============================================================================

func get_point_at_grid(u: float, v: float, use_start_plane: bool = true) -> Vector3:
	var plane = start_plane_vertices if use_start_plane else end_plane_vertices
	
	var bottom = plane[0].lerp(plane[1], u)
	var top = plane[3].lerp(plane[2], u)
	
	return bottom.lerp(top, v)

func get_path_segment_at_grid(u: float, v: float) -> Dictionary:
	return {
		"start": get_point_at_grid(u, v, true),
		"end": get_point_at_grid(u, v, false)
	}

func get_lateral_planes() -> Dictionary:
	return {
		"bottom": _plane_from_points(start_plane_vertices[0], start_plane_vertices[1], end_plane_vertices[1]),
		"right": _plane_from_points(start_plane_vertices[1], start_plane_vertices[2], end_plane_vertices[2]),
		"top": _plane_from_points(start_plane_vertices[2], start_plane_vertices[3], end_plane_vertices[3]),
		"left": _plane_from_points(start_plane_vertices[3], start_plane_vertices[0], end_plane_vertices[0])
	}

func get_flow_direction() -> Vector3:
	var center_start = get_point_at_grid(0.5, 0.5, true)
	var center_end = get_point_at_grid(0.5, 0.5, false)
	return (center_end - center_start).normalized()

func get_center() -> Vector3:
	var center_start = get_point_at_grid(0.5, 0.5, true)
	var center_end = get_point_at_grid(0.5, 0.5, false)
	return (center_start + center_end) * 0.5

func get_path_length() -> float:
	var center_start = get_point_at_grid(0.5, 0.5, true)
	var center_end = get_point_at_grid(0.5, 0.5, false)
	return center_start.distance_to(center_end)

func _plane_from_points(p1: Vector3, p2: Vector3, p3: Vector3) -> Array:
	var v1 = p2 - p1
	var v2 = p3 - p1
	var normal = v1.cross(v2).normalized()
	return [normal, p1]

func get_id() -> String:
	return "%d_%d" % [face_idx, edge_idx]

func get_raw_data() -> Dictionary:
	return raw_data

# ============================================================================
# MÉTODOS DE VISUALIZACIÓN DEBUG
# ============================================================================

func create_volume_mesh(color: Color, transparency: float, container: Node3D) -> void:
	var mesh = DebugUtil.create_skewed_cube_from_planes(
		start_plane_vertices,
		end_plane_vertices,
		color,
		transparency
	)
	if mesh:
		container.add_child(mesh)

func create_grid_points(width_steps: int, height_steps: int, container: Node3D, 
						color: Color, size: float) -> void:
	for i in range(width_steps + 1):
		for j in range(height_steps + 1):
			var u = float(i) / float(width_steps)
			var v = float(j) / float(height_steps)
			
			var point_start = get_point_at_grid(u, v, true)
			var grid_coords = Vector2i(i, j)
			var sphere = DebugUtil.create_debug_sphere_print(grid_coords, color, size)
			sphere.set_meta("grid_coords", grid_coords)
			sphere.set_meta("world_position", point_start)
			container.add_child(sphere)
			sphere.global_position = point_start
			
			var point_end = get_point_at_grid(u, v, false)
			var sphere_end = DebugUtil.create_debug_sphere_print(grid_coords, color, size)
			sphere_end.set_meta("grid_coords", grid_coords)
			sphere_end.set_meta("world_position", point_end)
			container.add_child(sphere_end)
			sphere_end.global_position = point_end

func validate_face_projection(face_vertices: Array, grid_u: float, grid_v: float) -> Dictionary:
	var path_start = get_point_at_grid(grid_u, grid_v, true)
	var path_end = get_point_at_grid(grid_u, grid_v, false)
	
	var lateral_planes = get_lateral_planes()
	
	for plane_name in lateral_planes.keys():
		var plane = lateral_planes[plane_name]
		var plane_normal = plane[0]
		var plane_point = plane[1]
		
		var has_positive_start = false
		var has_negative_start = false
		var has_positive_end = false
		var has_negative_end = false
		
		for vertex_offset in face_vertices:
			var vertex_at_start = path_start + vertex_offset
			var dist_start = plane_normal.dot(vertex_at_start - plane_point)
			if dist_start > 0.001:
				has_positive_start = true
			elif dist_start < -0.001:
				has_negative_start = true
			
			var vertex_at_end = path_end + vertex_offset
			var dist_end = plane_normal.dot(vertex_at_end - plane_point)
			if dist_end > 0.001:
				has_positive_end = true
			elif dist_end < -0.001:
				has_negative_end = true
		
		if (has_positive_start and has_negative_start) or (has_positive_end and has_negative_end):
			return {
				"valid": false,
				"collision_plane": plane_name
			}
	
	return {"valid": true, "collision_plane": ""}

# Calcula el v_max basándose en el número máximo de pisos del barrio
func get_max_spawn_v() -> float:
	if not neighborhood:
		return 1.0
	
	var max_floors = neighborhood.max_floors
	var max_height_cells = max_floors * cells_per_floor
	
	# Limitar al rango [0.0, 1.0]
	return min(1.0, float(max_height_cells) / float(height_cells))
