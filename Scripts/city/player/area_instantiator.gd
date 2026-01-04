extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 6.0
@export var inner_radius: float = 2.5
@export var height: float = 4.0
@export var segments: int = 64
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug: bool = true

@export var world: Node3D

@export_group("Lane Volume Visualization")
@export var show_lane_volumes: bool = true
@export var lane_volume_color: Color = Color(1.0, 0.5, 0.0)
@export var lane_volume_transparency: float = 0.3
@export var show_grid_points: bool = true
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 2 # Multiplicador para filas y columnas

@export_group("Performance")
@export var update_interval: float = 0.1
@export var position_threshold: float = 0.5
@export var rotation_threshold: float = 0.1

var debug_mesh: Node3D
var city = null
var valid_segments: Array = []
var lane_volumes_container: Node3D
var grid_points_container: Node3D

var cached_volumes: Array = []
var cached_position: Vector3 = Vector3.ZERO
var cached_rotation: Vector3 = Vector3.ZERO
var update_timer: float = 0.0

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	if world:
		lane_volumes_container = Node3D.new()
		lane_volumes_container.name = "LaneVolumesDebug_" + str(get_instance_id())
		world.add_child(lane_volumes_container)
		
		grid_points_container = Node3D.new()
		grid_points_container.name = "GridPointsDebug_" + str(get_instance_id())
		world.add_child(grid_points_container)
	
	if show_debug:
		_create_debug_visualization()

func _exit_tree() -> void:
	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_points_container and is_instance_valid(grid_points_container):
		grid_points_container.queue_free()

func _process(delta: float) -> void:
	if city == null:
		return
	
	update_timer += delta
	
	if update_timer >= update_interval:
		update_timer = 0.0
		
		var position_changed = global_position.distance_to(cached_position) > position_threshold
		var rotation_changed = _rotation_changed()
		
		if position_changed or rotation_changed:
			cached_position = global_position
			cached_rotation = global_rotation
			_update_valid_segments()
			
			if show_debug:
				_refresh_debug_visualization()
			
			var volumes = city.get_lane_volumes_in_cylindrical_area(
				global_position,
				outer_radius,
				height
			)
			
			if _volumes_changed(volumes):
				# Detectar nuevos volumes ANTES de actualizar el caché
				_detect_new_volumes(volumes)
				
				cached_volumes = volumes
				
				if show_lane_volumes and lane_volumes_container:
					_update_lane_volumes(volumes)
				
				if show_grid_points and grid_points_container:
					_update_grid_points(volumes)

func _rotation_changed() -> bool:
	var current_rotation = global_rotation
	var delta_x = abs(current_rotation.x - cached_rotation.x)
	var delta_y = abs(current_rotation.y - cached_rotation.y)
	var delta_z = abs(current_rotation.z - cached_rotation.z)
	
	return delta_x > rotation_threshold or delta_y > rotation_threshold or delta_z > rotation_threshold

func _volumes_changed(new_volumes: Array) -> bool:
	if new_volumes.size() != cached_volumes.size():
		return true
	
	for i in range(new_volumes.size()):
		if i >= cached_volumes.size():
			return true
		
		var new_vol = new_volumes[i]
		var old_vol = cached_volumes[i]
		
		if new_vol.get("face_idx") != old_vol.get("face_idx"):
			return true
		if new_vol.get("edge_idx") != old_vol.get("edge_idx"):
			return true
	
	return false

func _detect_new_volumes(new_volumes: Array) -> void:
	for vol in new_volumes:
		var face_idx = vol.get("face_idx", -1)
		var edge_idx = vol.get("edge_idx", -1)
		
		# Verificar si es un volume nuevo
		var is_new_volume = true
		for cached_vol in cached_volumes:
			if cached_vol.get("face_idx") == face_idx and cached_vol.get("edge_idx") == edge_idx:
				is_new_volume = false
				break
		
		if is_new_volume:
			var width_cells = vol.get("width_cells", 3)
			var height_cells = vol.get("height_cells", 10)
			var effective_width = width_cells * granularity
			var effective_height = height_cells * granularity
			print("NUEVO VOLUME - Face: %d, Edge: %d | Grilla base: %dx%d | Con granularidad %d: %dx%d" % [face_idx, edge_idx, width_cells, height_cells, granularity, effective_width, effective_height])

func _create_debug_visualization() -> void:
	_refresh_debug_visualization()

func _update_valid_segments() -> void:
	valid_segments.clear()
	
	var volumes = city.get_lane_volumes_in_cylindrical_area(
		global_position,
		outer_radius,
		height
	)
	
	if volumes.is_empty():
		return
	
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

func _update_lane_volumes(volumes: Array) -> void:
	for child in lane_volumes_container.get_children():
		child.queue_free()
	
	for vol in volumes:
		var volume_mesh = DebugUtil.create_skewed_cube_from_planes(
			vol["start_plane_vertices"],
			vol["end_plane_vertices"],
			lane_volume_color,
			lane_volume_transparency
		)
		
		if volume_mesh:
			lane_volumes_container.add_child(volume_mesh)

func _update_grid_points(volumes: Array) -> void:
	# Limpiar puntos anteriores
	for child in grid_points_container.get_children():
		child.queue_free()
	
	for vol in volumes:
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		# Aplicar granularidad
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		# Crear puntos para el plano inicial (start_plane)
		_create_grid_for_plane(vol["start_plane_vertices"], effective_width, effective_height)
		
		# Crear puntos para el plano final (end_plane)
		_create_grid_for_plane(vol["end_plane_vertices"], effective_width, effective_height)

func _create_grid_for_plane(plane_verts: Array, width_cells: int, height_cells: int) -> void:
	# plane_verts = [v1_base, v2_base, v3_top, v4_top]
	# Crear grilla de width_cells x height_cells puntos
	
	for i in range(width_cells + 1):  # +1 para incluir ambos extremos
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)  # 0.0 a 1.0 en ancho
			var v = float(j) / float(height_cells)  # 0.0 a 1.0 en altura
			
			# Interpolación bilineal
			var bottom = plane_verts[0].lerp(plane_verts[1], u)
			var top = plane_verts[3].lerp(plane_verts[2], u)
			var point = bottom.lerp(top, v)
			
			# Crear esfera en el punto
			var sphere = DebugUtil.create_debug_sphere(grid_point_color, grid_point_size)
			grid_points_container.add_child(sphere)
			sphere.global_position = point

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
	
	var vertices = []
	
	vertices.append(Vector3(cos(angle1) * inner_radius, 0, sin(angle1) * inner_radius))
	vertices.append(Vector3(cos(angle2) * inner_radius, 0, sin(angle2) * inner_radius))
	vertices.append(Vector3(cos(angle1) * outer_radius, 0, sin(angle1) * outer_radius))
	vertices.append(Vector3(cos(angle2) * outer_radius, 0, sin(angle2) * outer_radius))
	vertices.append(Vector3(cos(angle1) * inner_radius, height, sin(angle1) * inner_radius))
	vertices.append(Vector3(cos(angle2) * inner_radius, height, sin(angle2) * inner_radius))
	vertices.append(Vector3(cos(angle1) * outer_radius, height, sin(angle1) * inner_radius))
	vertices.append(Vector3(cos(angle2) * outer_radius, height, sin(angle2) * outer_radius))
	
	return vertices

func _segment_intersects_volume(segment_verts: Array, plane1_verts: Array, plane2_verts: Array) -> bool:
	for vert in segment_verts:
		var global_vert = global_transform * vert
		if _is_point_inside_lane_volume(global_vert, plane1_verts, plane2_verts):
			return true
	
	var center = Vector3.ZERO
	for vert in segment_verts:
		center += vert
	center /= segment_verts.size()
	
	var global_center = global_transform * center
	if _is_point_inside_lane_volume(global_center, plane1_verts, plane2_verts):
		return true
	
	return false

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
