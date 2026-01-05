extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 4.0
@export var inner_radius: float = 2.5
@export var height: float = 2.0
@export var segments: int = 64  # Solo para fidelidad visual
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
@export_range(1, 10) var granularity: int = 1
@export var show_flow_arrows: bool = true
@export var flow_arrow_color: Color = Color(0.0, 0.5, 1.0)
@export var flow_arrow_width: float = 0.02

@export_group("Performance")
@export var update_interval: float = 0.01
@export var position_threshold: float = 0.01
@export var rotation_threshold: float = 0.01

var debug_mesh: Node3D
var city = null
var lane_volumes_container: Node3D
var grid_points_container: Node3D
var flow_arrows_container: Node3D

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
		
		flow_arrows_container = Node3D.new()
		flow_arrows_container.name = "FlowArrowsDebug_" + str(get_instance_id())
		world.add_child(flow_arrows_container)
	
	if show_debug:
		_create_debug_visualization()

func _exit_tree() -> void:
	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_points_container and is_instance_valid(grid_points_container):
		grid_points_container.queue_free()
	if flow_arrows_container and is_instance_valid(flow_arrows_container):
		flow_arrows_container.queue_free()

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
			
			if show_debug:
				_refresh_debug_visualization()
			
			var volumes = city.get_lane_volumes_in_cylindrical_area(
				global_position,
				outer_radius,
				height
			)
			
			# Actualizar flechas siempre que haya movimiento/rotación
			if show_flow_arrows and flow_arrows_container:
				_update_flow_arrows(volumes)
			
			if _volumes_changed(volumes):
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

func _create_debug_visualization() -> void:
	_refresh_debug_visualization()

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
	for child in grid_points_container.get_children():
		child.queue_free()
	
	for vol in volumes:
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_grid_for_plane(vol["start_plane_vertices"], effective_width, effective_height)
		_create_grid_for_plane(vol["end_plane_vertices"], effective_width, effective_height)

func _update_flow_arrows(volumes: Array) -> void:
	for child in flow_arrows_container.get_children():
		child.queue_free()
	
	for vol in volumes:
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_flow_arrows_for_volume(vol["start_plane_vertices"], vol["end_plane_vertices"], effective_width, effective_height)

func _create_flow_arrows_for_volume(start_plane: Array, end_plane: Array, width_cells: int, height_cells: int) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			# Obtener puntos correspondientes en ambos planos
			var bottom_start = start_plane[0].lerp(start_plane[1], u)
			var top_start = start_plane[3].lerp(start_plane[2], u)
			var point_start = bottom_start.lerp(top_start, v)
			
			var bottom_end = end_plane[0].lerp(end_plane[1], u)
			var top_end = end_plane[3].lerp(end_plane[2], u)
			var point_end = bottom_end.lerp(top_end, v)
			
			# Obtener segmentos de la línea que están dentro del anillo
			var segments_array = _get_line_segments_in_ring(point_start, point_end)
			
			# Crear flechas para cada segmento
			for segment in segments_array:
				var arrow = DebugUtil.create_debug_arrow_to_from(segment[0], segment[1], flow_arrow_color, flow_arrow_width)
				flow_arrows_container.add_child(arrow)

func _get_line_segments_in_ring(line_start: Vector3, line_end: Vector3) -> Array:
	# Convertir a coordenadas locales
	var local_start = global_transform.affine_inverse() * line_start
	var local_end = global_transform.affine_inverse() * line_end
	
	var half_height = height / 2.0
	var direction = local_end - local_start
	
	# Calcular intersecciones con cilindro exterior
	var t_outer = _intersect_cylinder(local_start, direction, outer_radius)
	
	# Calcular intersecciones con cilindro interior
	var t_inner = _intersect_cylinder(local_start, direction, inner_radius)
	
	# Recopilar todos los puntos de intersección relevantes
	var intersections = []
	
	# Añadir intersecciones con cilindro exterior
	for t in t_outer:
		if t >= 0.0 and t <= 1.0:
			var point = local_start + t * direction
			if point.y >= -half_height and point.y <= half_height:
				intersections.append({"t": t, "type": "outer"})
	
	# Añadir intersecciones con cilindro interior
	for t in t_inner:
		if t >= 0.0 and t <= 1.0:
			var point = local_start + t * direction
			if point.y >= -half_height and point.y <= half_height:
				intersections.append({"t": t, "type": "inner"})
	
	# Añadir extremos de la línea si están dentro del anillo
	if _is_point_in_ring(local_start):
		intersections.append({"t": 0.0, "type": "start"})
	if _is_point_in_ring(local_end):
		intersections.append({"t": 1.0, "type": "end"})
	
	# Ordenar por t
	intersections.sort_custom(func(a, b): return a["t"] < b["t"])
	
	# Construir segmentos que están dentro del anillo
	var segments_result = []
	var i = 0
	while i < intersections.size():
		var t1 = intersections[i]["t"]
		
		# Buscar el siguiente punto de intersección
		if i + 1 < intersections.size():
			var t2 = intersections[i + 1]["t"]
			var mid_t = (t1 + t2) / 2.0
			var mid_point = local_start + mid_t * direction
			
			# Verificar si el punto medio está en el anillo
			if _is_point_in_ring(mid_point):
				var global_p1 = global_transform * (local_start + t1 * direction)
				var global_p2 = global_transform * (local_start + t2 * direction)
				segments_result.append([global_p1, global_p2])
		
		i += 1
	
	return segments_result

func _intersect_cylinder(origin: Vector3, direction: Vector3, radius: float) -> Array:
	var a = direction.x * direction.x + direction.z * direction.z
	var b = 2.0 * (origin.x * direction.x + origin.z * direction.z)
	var c = origin.x * origin.x + origin.z * origin.z - radius * radius
	
	# Línea vertical
	if abs(a) < 0.0001:
		return []
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return []
	
	if abs(discriminant) < 0.0001:
		# Una intersección (tangente)
		return [(-b) / (2.0 * a)]
	
	# Dos intersecciones
	var sqrt_disc = sqrt(discriminant)
	return [
		(-b - sqrt_disc) / (2.0 * a),
		(-b + sqrt_disc) / (2.0 * a)
	]

func _is_point_in_ring(local_point: Vector3) -> bool:
	var half_height = height / 2.0
	var r = sqrt(local_point.x * local_point.x + local_point.z * local_point.z)
	return r >= inner_radius and r <= outer_radius and local_point.y >= -half_height and local_point.y <= half_height

func _create_grid_for_plane(plane_verts: Array, width_cells: int, height_cells: int) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			var bottom = plane_verts[0].lerp(plane_verts[1], u)
			var top = plane_verts[3].lerp(plane_verts[2], u)
			var point = bottom.lerp(top, v)
			
			var sphere = DebugUtil.create_debug_sphere(grid_point_color, grid_point_size)
			grid_points_container.add_child(sphere)
			sphere.global_position = point

func _refresh_debug_visualization() -> void:
	if debug_mesh:
		debug_mesh.queue_free()
	
	debug_mesh = DebugUtil.create_debug_ring_volume_wireframe(debug_color, outer_radius, inner_radius, height, segments)
	add_child(debug_mesh)
