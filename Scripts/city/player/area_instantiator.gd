extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 8.0
@export var inner_radius: float = 4.5
@export var height: float = 4.5
@export var segments: int = 32
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug: bool = true

@export var world: Node3D

@export_group("Lane Volume Visualization")
@export var show_lane_volumes: bool = true
@export var lane_volume_color: Color = Color(1.0, 0.5, 0.0)
@export var lane_volume_transparency: float = 0.3
@export var show_continuations: bool = true
@export var continuation_color: Color = Color(0.0, 1.0, 1.0)
@export var continuation_transparency: float = 0.2
@export var show_grid_points: bool = true
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 1
@export var show_flow_arrows: bool = true
@export var flow_arrow_color: Color = Color(0.0, 0.5, 1.0)
@export var flow_arrow_width: float = 0.02

@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 1.0
@export_subgroup("Spawn Weights")
@export_range(0.0, 1.0) var car_weight: float = 0.7
@export_range(0.0, 1.0) var truck_weight: float = 0.1
@export_range(0.0, 1.0) var motorcycle_weight: float = 0.2

@export_group("Performance")
@export var update_interval: float = 0.01
@export var position_threshold: float = 0.01
@export var rotation_threshold: float = 0.01

var debug_mesh: Node3D
var city = null
var lane_volumes_container: Node3D
var grid_points_container: Node3D
var flow_arrows_container: Node3D
var destruction_area: Area3D

var cached_volumes: Array = []
var cached_position: Vector3 = Vector3.ZERO
var cached_rotation: Vector3 = Vector3.ZERO
var update_timer: float = 0.0
var spawn_timer: float = 0.0

var valid_spawn_segments: Array = []

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	_create_destruction_area()
	
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
	if destruction_area and is_instance_valid(destruction_area):
		destruction_area.queue_free()

func _create_destruction_area() -> void:
	destruction_area = Area3D.new()
	destruction_area.collision_layer = 0   # No está en ningún layer
	destruction_area.collision_mask = 1    # Detecta layer 1 (los autos)
	destruction_area.monitoring = true     # Activa el monitoreo
	destruction_area.monitorable = false   # No necesita ser detectada
	
	var collision_shape = CollisionShape3D.new()
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = outer_radius
	cylinder_shape.height = height
	collision_shape.shape = cylinder_shape
	
	destruction_area.add_child(collision_shape)
	destruction_area.area_exited.connect(_on_area_exited_area)
	add_child(destruction_area)

func _on_area_exited_area(area: Area3D) -> void:
	var parent = area.get_parent()
	if parent is FlyingCar:
		print("Auto salió del área, destruyendo: ", parent.name)
		parent.queue_free()

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
			
			if show_flow_arrows and flow_arrows_container:
				_update_flow_arrows(volumes)
			
			if _volumes_changed(volumes):
				cached_volumes = volumes
				
				if show_lane_volumes and lane_volumes_container:
					_update_lane_volumes(volumes)
				
				if show_grid_points and grid_points_container:
					_update_grid_points(volumes)
	
	if enable_car_spawning:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_try_spawn_car()

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
	
	var visualized_volumes: Dictionary = {}
	
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		
		var volume_mesh = DebugUtil.create_skewed_cube_from_planes(
			vol["start_plane_vertices"],
			vol["end_plane_vertices"],
			lane_volume_color,
			lane_volume_transparency
		)
		
		if volume_mesh:
			lane_volumes_container.add_child(volume_mesh)
			visualized_volumes[key] = true
	
	if show_continuations:
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				if cont_key in visualized_volumes:
					continue
				
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
				var cont_volume_data = cont_block.get_edge_lane_volume(cont["edge_idx"])
				
				if cont_volume_data.is_empty():
					continue
				
				var cont_mesh = DebugUtil.create_skewed_cube_from_planes(
					cont_volume_data["start_plane_vertices"],
					cont_volume_data["end_plane_vertices"],
					continuation_color,
					continuation_transparency
				)
				
				if cont_mesh:
					lane_volumes_container.add_child(cont_mesh)
					visualized_volumes[cont_key] = true

func _update_grid_points(volumes: Array) -> void:
	for child in grid_points_container.get_children():
		child.queue_free()
	
	var visualized_volumes: Dictionary = {}
	
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		visualized_volumes[key] = true
		
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_grid_for_plane(vol["start_plane_vertices"], effective_width, effective_height)
		_create_grid_for_plane(vol["end_plane_vertices"], effective_width, effective_height)
	
	if show_continuations and city:
		var gen = city.get_generator()
		if gen == null:
			return
		
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				if cont_key in visualized_volumes:
					continue
				
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
				var cont_volume_data = cont_block.get_edge_lane_volume(cont["edge_idx"])
				
				if cont_volume_data.is_empty():
					continue
				
				var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(cont_volume_data.get("street_type", 0), 3)
				var height_cells = 0
				if city_block_cell_height > 0 and city_cells_per_floor > 0:
					var floor_height = city_cells_per_floor * city_block_cell_height
					var num_floors = ceil(cont_volume_data["height"] / floor_height)
					height_cells = int(num_floors * city_cells_per_floor)
				
				var effective_width = width_cells * granularity
				var effective_height = height_cells * granularity
				
				_create_grid_for_plane(cont_volume_data["start_plane_vertices"], effective_width, effective_height)
				_create_grid_for_plane(cont_volume_data["end_plane_vertices"], effective_width, effective_height)
				
				visualized_volumes[cont_key] = true

func _update_flow_arrows(volumes: Array) -> void:
	for child in flow_arrows_container.get_children():
		child.queue_free()
	
	valid_spawn_segments.clear()
	
	var visualized_volumes: Dictionary = {}
	
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		visualized_volumes[key] = true
		
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_flow_arrows_for_volume(vol["start_plane_vertices"], vol["end_plane_vertices"], effective_width, effective_height, vol)
	
	if show_continuations and city:
		var gen = city.get_generator()
		if gen == null:
			return
		
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				if cont_key in visualized_volumes:
					continue
				
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
				var cont_volume_data = cont_block.get_edge_lane_volume(cont["edge_idx"])
				
				if cont_volume_data.is_empty():
					continue
				
				var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(cont_volume_data.get("street_type", 0), 3)
				var height_cells = 0
				if city_block_cell_height > 0 and city_cells_per_floor > 0:
					var floor_height = city_cells_per_floor * city_block_cell_height
					var num_floors = ceil(cont_volume_data["height"] / floor_height)
					height_cells = int(num_floors * city_cells_per_floor)
				
				var effective_width = width_cells * granularity
				var effective_height = height_cells * granularity
				
				_create_flow_arrows_for_volume(cont_volume_data["start_plane_vertices"], cont_volume_data["end_plane_vertices"], effective_width, effective_height, cont_volume_data)
				
				visualized_volumes[cont_key] = true

func _create_flow_arrows_for_volume(start_plane: Array, end_plane: Array, width_cells: int, height_cells: int, volume: Dictionary) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			var bottom_start = start_plane[0].lerp(start_plane[1], u)
			var top_start = start_plane[3].lerp(start_plane[2], u)
			var point_start = bottom_start.lerp(top_start, v)
			
			var bottom_end = end_plane[0].lerp(end_plane[1], u)
			var top_end = end_plane[3].lerp(end_plane[2], u)
			var point_end = bottom_end.lerp(top_end, v)
			
			var segments_array = GeometryUtils.clip_line_to_ring_volume(
				point_start, 
				point_end, 
				global_transform, 
				inner_radius, 
				outer_radius, 
				height
			)
			
			for segment in segments_array:
				var arrow = DebugUtil.create_debug_arrow_to_from(segment[0], segment[1], flow_arrow_color, flow_arrow_width)
				flow_arrows_container.add_child(arrow)
				
				valid_spawn_segments.append({
					"start": segment[0],
					"end": segment[1],
					"original_start": point_start,
					"original_end": point_end,
					"volume": volume
				})

func _try_spawn_car() -> void:
	print("=== Intentando spawnear auto ===")
	print("Valid spawn segments: ", valid_spawn_segments.size())
	print("World exists: ", world != null)
	
	if valid_spawn_segments.is_empty() or not world:
		print("ABORTADO: No hay segmentos válidos o no hay world")
		return
	
	var max_attempts = 10
	for attempt in range(max_attempts):
		print("  Intento ", attempt + 1, "/", max_attempts)
		var custom_weights = {
			CarArchetypes.Type.CAR: car_weight,
			CarArchetypes.Type.TRUCK: truck_weight,
			CarArchetypes.Type.MOTORCYCLE: motorcycle_weight
		}
		var archetype = CarArchetypes.get_weighted_random_archetype(custom_weights)

		var dims = archetype.get_random_dimensions()
		
		var car_width = dims["width"]
		var car_height = dims["height"]
		var car_depth = dims["depth"]
		var car_speed = dims["speed"]
		
		print("    Arquetipo: ", archetype.name)
		print("    Dimensiones: w=%.2f h=%.2f d=%.2f speed=%.2f" % [car_width, car_height, car_depth, car_speed])
		
		var suitable_segments = []
		for seg_data in valid_spawn_segments:
			var seg_length = seg_data["start"].distance_to(seg_data["end"])
			if seg_length >= car_depth:
				suitable_segments.append(seg_data)
		
		print("    Segmentos adecuados (>= %.2f): %d" % [car_depth, suitable_segments.size()])
		
		if suitable_segments.is_empty():
			print("    ✗ No hay segmentos lo suficientemente largos")
			continue
		
		var spawn_data = suitable_segments[randi() % suitable_segments.size()]
		
		print("    Spawn path original: ", spawn_data["start"], " -> ", spawn_data["end"])
		
		var valid_spawn_path = _calculate_valid_subpath(spawn_data["start"], spawn_data["end"], car_width, car_height, car_depth, spawn_data["volume"])
		
		if valid_spawn_path != null:
			# Calcular el progreso inicial basado en la posición de spawn
			var full_path_length = spawn_data["original_start"].distance_to(spawn_data["original_end"])
			var distance_to_spawn = spawn_data["original_start"].distance_to(valid_spawn_path["start"])
			var initial_progress = distance_to_spawn / full_path_length if full_path_length > 0 else 0.0
			
			print("    ✓ AUTO SPAWNEADO EXITOSAMENTE")
			print("    Spawn position: ", valid_spawn_path["start"])
			print("    Full path: ", spawn_data["original_start"], " -> ", spawn_data["original_end"])
			print("    Initial progress: %.2f%%" % (initial_progress * 100.0))
			
			var car = FlyingCar.new()
			car.width = car_width
			car.height = car_height
			car.depth = car_depth
			car.speed = car_speed
			car.car_color = archetype.get_random_color()
			car.world_node = world
			
			world.add_child(car)
			car.set_path(spawn_data["original_start"], spawn_data["original_end"], initial_progress)
			
			return
		else:
			print("    ✗ No se pudo encontrar un subtramo válido para spawn")
	
	print("FALLO: No se pudo spawnear después de ", max_attempts, " intentos")

func _can_car_fit_in_path(start: Vector3, end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary) -> bool:
	var direction = (end - start).normalized()
	
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	var half_extents = [
		Vector3(-car_width/2, -car_height/2, -car_depth/2),
		Vector3(car_width/2, -car_height/2, -car_depth/2),
		Vector3(-car_width/2, car_height/2, -car_depth/2),
		Vector3(car_width/2, car_height/2, -car_depth/2),
		Vector3(-car_width/2, -car_height/2, car_depth/2),
		Vector3(car_width/2, -car_height/2, car_depth/2),
		Vector3(-car_width/2, car_height/2, car_depth/2),
		Vector3(car_width/2, car_height/2, car_depth/2)
	]
	
	var num_samples = 10
	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var pos = start.lerp(end, t)
		
		for corner_idx in range(half_extents.size()):
			var corner_local = half_extents[corner_idx]
			var corner_global = pos + right * corner_local.x + up * corner_local.y + forward * corner_local.z
			
			var local_corner = global_transform.affine_inverse() * corner_global
			if not GeometryUtils.is_point_in_ring_volume(local_corner, inner_radius, outer_radius, height):
				print("      Fallo en anillo: sample=%d corner=%d" % [i, corner_idx])
				return false
			
			if not GeometryUtils.is_point_inside_lane_volume(corner_global, volume["start_plane_vertices"], volume["end_plane_vertices"]):
				print("      Fallo en lane volume: sample=%d corner=%d" % [i, corner_idx])
				return false
	
	return true

func _calculate_travel_path(original_start: Vector3, original_end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary):
	var direction = (original_end - original_start).normalized()
	var path_length = original_start.distance_to(original_end)
	
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	var half_extents = [
		Vector3(-car_width/2, -car_height/2, -car_depth/2),
		Vector3(car_width/2, -car_height/2, -car_depth/2),
		Vector3(-car_width/2, car_height/2, -car_depth/2),
		Vector3(car_width/2, car_height/2, -car_depth/2),
		Vector3(-car_width/2, -car_height/2, car_depth/2),
		Vector3(car_width/2, -car_height/2, car_depth/2),
		Vector3(-car_width/2, car_height/2, car_depth/2),
		Vector3(car_width/2, car_height/2, car_depth/2)
	]
	
	var valid_t_min = 0.0
	var valid_t_max = 1.0
	
	for corner_local in half_extents:
		var corner_at_start = original_start + right * corner_local.x + up * corner_local.y + forward * corner_local.z
		var corner_direction = direction
		
		var local_corner_start = global_transform.affine_inverse() * corner_at_start
		var local_corner_direction = global_transform.affine_inverse().basis * corner_direction
		
		var t_outer = GeometryUtils.intersect_cylinder_normalized(local_corner_start, local_corner_direction, outer_radius, path_length)
		
		var corner_t_min = 0.0
		var corner_t_max = 1.0
		
		if t_outer.size() >= 2:
			corner_t_min = max(corner_t_min, t_outer[0])
			corner_t_max = min(corner_t_max, t_outer[1])
		elif t_outer.size() == 1:
			var test_t = clamp(0.5, corner_t_min, corner_t_max)
			var test_pos = local_corner_start + local_corner_direction * test_t * path_length
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null
		else:
			var test_pos = local_corner_start
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null
		
		var half_height = height / 2.0
		if abs(local_corner_direction.y) > 0.001:
			var t_bottom = (-half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			var t_top = (half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			
			var t_y_min = min(t_bottom, t_top)
			var t_y_max = max(t_bottom, t_top)
			
			corner_t_min = max(corner_t_min, t_y_min)
			corner_t_max = min(corner_t_max, t_y_max)
		else:
			if local_corner_start.y < -half_height or local_corner_start.y > half_height:
				return null
		
		valid_t_min = max(valid_t_min, corner_t_min)
		valid_t_max = min(valid_t_max, corner_t_max)
		
		if valid_t_min >= valid_t_max:
			return null
	
	var valid_start = original_start.lerp(original_end, valid_t_min)
	var valid_end = original_start.lerp(original_end, valid_t_max)
	
	for i in range(5):
		var t = float(i) / 4.0
		var sample_t = valid_t_min + (valid_t_max - valid_t_min) * t
		var sample_pos = original_start.lerp(original_end, sample_t)
		
		if not GeometryUtils.is_point_inside_lane_volume(sample_pos, volume["start_plane_vertices"], volume["end_plane_vertices"]):
			return null
	
	return {
		"start": valid_start,
		"end": valid_end
	}

func _calculate_valid_subpath(start: Vector3, end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary):
	var direction = (end - start).normalized()
	var path_length = start.distance_to(end)
	
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	var half_extents = [
		Vector3(-car_width/2, -car_height/2, -car_depth/2),
		Vector3(car_width/2, -car_height/2, -car_depth/2),
		Vector3(-car_width/2, car_height/2, -car_depth/2),
		Vector3(car_width/2, car_height/2, -car_depth/2),
		Vector3(-car_width/2, -car_height/2, car_depth/2),
		Vector3(car_width/2, -car_height/2, car_depth/2),
		Vector3(-car_width/2, car_height/2, car_depth/2),
		Vector3(car_width/2, car_height/2, car_depth/2)
	]
	
	var valid_t_min = 0.0
	var valid_t_max = 1.0
	
	for corner_local in half_extents:
		var corner_at_start = start + right * corner_local.x + up * corner_local.y + forward * corner_local.z
		var corner_direction = direction
		
		var local_corner_start = global_transform.affine_inverse() * corner_at_start
		var local_corner_direction = global_transform.affine_inverse().basis * corner_direction
		
		var t_outer = GeometryUtils.intersect_cylinder_normalized(local_corner_start, local_corner_direction, outer_radius, path_length)
		var t_inner = GeometryUtils.intersect_cylinder_normalized(local_corner_start, local_corner_direction, inner_radius, path_length)
		
		var corner_t_min = 0.0
		var corner_t_max = 1.0
		
		if t_outer.size() >= 2:
			corner_t_min = max(corner_t_min, t_outer[0])
			corner_t_max = min(corner_t_max, t_outer[1])
		elif t_outer.size() == 1:
			var test_t = clamp(0.5, corner_t_min, corner_t_max)
			var test_pos = local_corner_start + local_corner_direction * test_t * path_length
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null
		else:
			var test_pos = local_corner_start
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null
		
		if t_inner.size() >= 2:
			if t_inner[1] < corner_t_max:
				corner_t_min = max(corner_t_min, t_inner[1])
			elif t_inner[0] > corner_t_min:
				corner_t_max = min(corner_t_max, t_inner[0])
			else:
				return null
		
		var half_height = height / 2.0
		if abs(local_corner_direction.y) > 0.001:
			var t_bottom = (-half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			var t_top = (half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			
			var t_y_min = min(t_bottom, t_top)
			var t_y_max = max(t_bottom, t_top)
			
			corner_t_min = max(corner_t_min, t_y_min)
			corner_t_max = min(corner_t_max, t_y_max)
		else:
			if local_corner_start.y < -half_height or local_corner_start.y > half_height:
				return null
		
		valid_t_min = max(valid_t_min, corner_t_min)
		valid_t_max = min(valid_t_max, corner_t_max)
		
		if valid_t_min >= valid_t_max:
			return null
	
	var valid_length = (valid_t_max - valid_t_min) * path_length
	if valid_length < car_depth:
		print("      Subpath válido muy corto: %.2f < %.2f" % [valid_length, car_depth])
		return null
	
	var valid_start = start.lerp(end, valid_t_min)
	var valid_end = start.lerp(end, valid_t_max)
	
	for i in range(5):
		var t = float(i) / 4.0
		var sample_t = valid_t_min + (valid_t_max - valid_t_min) * t
		var sample_pos = start.lerp(end, sample_t)
		
		if not GeometryUtils.is_point_inside_lane_volume(sample_pos, volume["start_plane_vertices"], volume["end_plane_vertices"]):
			print("      Subpath sale del lane volume")
			return null
	
	return {
		"start": valid_start,
		"end": valid_end
	}

# En AreaInstantiator
func _create_grid_for_plane(plane_verts: Array, width_cells: int, height_cells: int) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			var bottom = plane_verts[0].lerp(plane_verts[1], u)
			var top = plane_verts[3].lerp(plane_verts[2], u)
			var point = bottom.lerp(top, v)
			
			var grid_coords = Vector2i(i, j)
			var sphere = DebugUtil.create_debug_sphere_print(grid_coords, grid_point_color, grid_point_size)
			sphere.set_meta("grid_coords", grid_coords)
			sphere.set_meta("world_position", point)
			grid_points_container.add_child(sphere)
			sphere.global_position = point

func _refresh_debug_visualization() -> void:
	if debug_mesh:
		debug_mesh.queue_free()
	
	debug_mesh = DebugUtil.create_debug_ring_volume_wireframe(debug_color, outer_radius, inner_radius, height, segments)
	add_child(debug_mesh)
