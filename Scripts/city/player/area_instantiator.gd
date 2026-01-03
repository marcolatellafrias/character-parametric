extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 4.0
@export var inner_radius: float = 1.5
@export var height: float = 2.0
@export var segments: int = 16
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug: bool = true

@export var world: Node3D
@export var spawn_interval: float = 1.0
@export var max_spawn_attempts: int = 5

@export_group("Car Size Ranges")
@export var debug_size_factor: float = 0.1
@export var min_car_width: float = 1.5 * debug_size_factor
@export var max_car_width: float = 2.5 * debug_size_factor
@export var min_car_height: float = 0.8 * debug_size_factor
@export var max_car_height: float = 1.5 * debug_size_factor
@export var min_car_depth: float = 3.0 * debug_size_factor
@export var max_car_depth: float = 5.0 * debug_size_factor

var debug_mesh: MeshInstance3D
var city = null
var valid_segments: Array = []
var spawn_timer_accumulator: float = 0.0

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	if show_debug:
		_create_debug_visualization()

func _process(delta: float) -> void:
	if city != null:
		_update_valid_segments()
		
		if show_debug:
			_refresh_debug_visualization()
		
		# Acumular tiempo para spawn
		spawn_timer_accumulator += delta
		if spawn_timer_accumulator >= spawn_interval:
			spawn_timer_accumulator -= spawn_interval
			_spawn_car()

func _create_debug_visualization() -> void:
	_refresh_debug_visualization()

func _spawn_car() -> void:
	if not world or not city:
		return
	
	if valid_segments.is_empty():
		return
	
	# Intentar spawnear en un segmento válido
	var spawn_position = _get_random_point_from_valid_segments()
	
	if spawn_position == null:
		return
	
	# Spawn del car
	var car = FlyingCar.new()
	car.width = randf_range(min_car_width, max_car_width)
	car.height = randf_range(min_car_height, max_car_height)
	car.depth = randf_range(min_car_depth, max_car_depth)
	car.car_color = Color(randf(), randf(), randf(), 1.0)
	
	world.add_child(car)
	car.global_position = spawn_position

func _update_valid_segments() -> void:
	valid_segments.clear()
	
	# Obtener lane volumes cercanos
	var volumes = city.get_lane_volumes_in_cylindrical_area(
		global_position,
		outer_radius * 1.5,
		height
	)
	
	if volumes.is_empty():
		return
	
	# Para cada segmento del anillo, verificar si intersecta con algún lane volume
	for i in range(segments):
		var segment_vertices = _get_segment_vertices(i)
		
		for vol in volumes:
			if _segment_intersects_volume(segment_vertices, vol["start_plane_vertices"], vol["end_plane_vertices"]):
				valid_segments.append({
					"index": i,
					"vertices": segment_vertices,
					"volume": vol
				})
				break

func _refresh_debug_visualization() -> void:
	if debug_mesh:
		debug_mesh.queue_free()
	
	var valid_indices = []
	for seg in valid_segments:
		valid_indices.append(seg["index"])
	
	debug_mesh = DebugUtil.create_debug_ring_volume_wireframe(debug_color, outer_radius, inner_radius, height, segments, valid_indices)
	add_child(debug_mesh)

func _get_segment_vertices(segment_index: int) -> Array:
	var angle1 = TAU * float(segment_index) / float(segments)
	var angle2 = TAU * float(segment_index + 1) / float(segments)
	
	# 8 vértices del segmento (cubo deformado)
	var vertices = []
	
	# Bottom inner
	vertices.append(Vector3(cos(angle1) * inner_radius, 0, sin(angle1) * inner_radius))
	vertices.append(Vector3(cos(angle2) * inner_radius, 0, sin(angle2) * inner_radius))
	
	# Bottom outer
	vertices.append(Vector3(cos(angle1) * outer_radius, 0, sin(angle1) * outer_radius))
	vertices.append(Vector3(cos(angle2) * outer_radius, 0, sin(angle2) * outer_radius))
	
	# Top inner
	vertices.append(Vector3(cos(angle1) * inner_radius, height, sin(angle1) * inner_radius))
	vertices.append(Vector3(cos(angle2) * inner_radius, height, sin(angle2) * inner_radius))
	
	# Top outer
	vertices.append(Vector3(cos(angle1) * outer_radius, height, sin(angle1) * outer_radius))
	vertices.append(Vector3(cos(angle2) * outer_radius, height, sin(angle2) * outer_radius))
	
	return vertices

func _segment_intersects_volume(segment_verts: Array, plane1_verts: Array, plane2_verts: Array) -> bool:
	# Verificar si algún vértice del segmento está dentro del volume
	for vert in segment_verts:
		var global_vert = global_transform * vert
		if _is_point_inside_lane_volume(global_vert, plane1_verts, plane2_verts):
			return true
	
	# También verificar algunos puntos en el centro del segmento
	var center = Vector3.ZERO
	for vert in segment_verts:
		center += vert
	center /= segment_verts.size()
	
	var global_center = global_transform * center
	if _is_point_inside_lane_volume(global_center, plane1_verts, plane2_verts):
		return true
	
	return false

func _get_random_point_from_valid_segments():
	if valid_segments.is_empty():
		return null
	
	for attempt in range(max_spawn_attempts):
		# Elegir segmento válido aleatorio
		var segment = valid_segments[randi() % valid_segments.size()]
		var segment_index = segment["index"]
		
		# Generar punto aleatorio dentro del segmento
		var angle1 = TAU * float(segment_index) / float(segments)
		var angle2 = TAU * float(segment_index + 1) / float(segments)
		
		var random_angle = randf_range(angle1, angle2)
		var random_radius = randf_range(inner_radius, outer_radius)
		var random_height = randf_range(0, height)
		
		var local_x = cos(random_angle) * random_radius
		var local_z = sin(random_angle) * random_radius
		var local_pos = Vector3(local_x, random_height, local_z)
		var global_pos = global_transform * local_pos
		
		# Verificar que el punto esté dentro del lane volume
		var is_valid = _is_point_inside_lane_volume(global_pos, segment["volume"]["start_plane_vertices"], segment["volume"]["end_plane_vertices"])
		
		# Visualizar intento
		if show_debug:
			_show_spawn_attempt(global_pos, is_valid)
		
		if is_valid:
			return global_pos
	
	return null

func _show_spawn_attempt(position: Vector3, success: bool) -> void:
	var color = Color(0.0, 1.0, 0.0, 0.8) if success else Color(1.0, 0.0, 0.0, 0.8)
	var sphere = DebugUtil.create_debug_sphere(color, 1.0)
	world.add_child(sphere)
	sphere.global_position = position
	
	# Destruir después de 0.3 segundos
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(sphere):
		sphere.queue_free()

func _is_point_inside_lane_volume(point: Vector3, plane1_verts: Array, plane2_verts: Array) -> bool:
	if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[1], plane1_verts[2], true):
		return false
	
	if not _is_point_on_correct_side(point, plane2_verts[3], plane2_verts[2], plane2_verts[1], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[0], plane2_verts[0], plane2_verts[1], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[3], plane1_verts[2], plane2_verts[2], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[3], plane2_verts[3], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[1], plane2_verts[1], plane2_verts[2], true):
		return false
	
	return true

func _is_point_on_correct_side(point: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, inside: bool) -> bool:
	var normal = (v2 - v1).cross(v3 - v1).normalized()
	var to_point = point - v1
	var dot = normal.dot(to_point)
	
	return dot >= 0 if inside else dot <= 0
