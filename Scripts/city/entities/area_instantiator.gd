# AreaInstantiator.gd
extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 60.0
@export var height: float = 200.5
@export var segments: int = 16
@export var debug_cylinder_color: Color = Color(0.0, 1.0, 0.0, 0.15)
@export var show_debug_cylinder: bool = true

@export var cameras: Array[Camera3D] = []

@export var world: Node3D

@export_group("Lane Volume Visualization")
@export var show_lane_volumes: bool = false
@export var lane_volume_color: Color = Color(1.0, 0.5, 0.0) 
@export var lane_volume_transparency: float = 0.2
@export var show_continuations: bool = false
@export var continuation_color: Color = Color(0.0, 1.0, 1.0)
@export var continuation_transparency: float = 0.3
@export var show_grid_points: bool = false
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 1

@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 0.1
@export var spawn_safety_margin: float = 3.0

var city = null
var debug_cylinder_meshes: Array[MeshInstance3D] = []
var lane_volumes_container: Node3D
var grid_points_container: Node3D

var cylinder_areas: Array[Area3D] = []
var cylinder_lane_volumes: Array[LaneVolume] = []
var volume_area_refs: Dictionary = {}

var spawn_timer: float = 0.0
var volume_car_counts: Dictionary = {}

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	_create_cylinder_areas()
	_setup_visualization_containers()
	
	if show_debug_cylinder:
		_create_debug_cylinders()

func _process(delta: float) -> void:
	_update_cylinder_positions()
	
	if not enable_car_spawning:
		return
	
	if not world:
		print("ERROR: No hay world node")
		return
	
	if not city:
		print("ERROR: No hay city")
		return
	
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_try_spawn_car()

func _exit_tree() -> void:
	_cleanup_containers()

func _setup_visualization_containers() -> void:
	if not world:
		return
	
	lane_volumes_container = Node3D.new()
	lane_volumes_container.name = "LaneVolumesDebug_" + str(get_instance_id())
	world.add_child(lane_volumes_container)
	
	grid_points_container = Node3D.new()
	grid_points_container.name = "GridPointsDebug_" + str(get_instance_id())
	world.add_child(grid_points_container)

func _cleanup_containers() -> void:
	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_points_container and is_instance_valid(grid_points_container):
		grid_points_container.queue_free()
	
	for area in cylinder_areas:
		if area and is_instance_valid(area):
			area.queue_free()
	cylinder_areas.clear()
	
	for mesh in debug_cylinder_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	debug_cylinder_meshes.clear()

func _create_cylinder_areas() -> void:
	for i in range(cameras.size()):
		var cylinder_area = Area3D.new()
		cylinder_area.name = "CylinderArea_" + str(i)
		cylinder_area.collision_layer = 0
		cylinder_area.collision_mask = 2
		cylinder_area.monitoring = true
		cylinder_area.monitorable = false
		
		var colliders = DebugUtil.create_cylinder_colliders(outer_radius, height, segments)
		for collider in colliders:
			cylinder_area.add_child(collider)
		
		var area_index = i
		cylinder_area.area_entered.connect(func(area): _on_cylinder_area_entered(area, area_index))
		cylinder_area.area_exited.connect(func(area): _on_cylinder_area_exited(area, area_index))
		
		add_child(cylinder_area)
		cylinder_areas.append(cylinder_area)

func _update_cylinder_positions() -> void:
	for i in range(min(cameras.size(), cylinder_areas.size())):
		var camera = cameras[i]
		var area = cylinder_areas[i]
		
		if camera and is_instance_valid(camera):
			area.global_position.x = camera.global_position.x
			area.global_position.z = camera.global_position.z
			area.global_position.y = 0
	
	if show_debug_cylinder:
		for i in range(min(cameras.size(), debug_cylinder_meshes.size())):
			var camera = cameras[i]
			var mesh = debug_cylinder_meshes[i]
			
			if camera and is_instance_valid(camera) and mesh and is_instance_valid(mesh):
				mesh.global_position.x = camera.global_position.x
				mesh.global_position.z = camera.global_position.z
				mesh.global_position.y = 0

func _on_cylinder_area_entered(area: Area3D, area_index: int) -> void:
	if area is LaneVolume:
		var vol_id = area.get_id()
		
		if not volume_area_refs.has(vol_id):
			volume_area_refs[vol_id] = []
		
		if not volume_area_refs[vol_id].has(area_index):
			volume_area_refs[vol_id].append(area_index)
		
		if not cylinder_lane_volumes.has(area):
			cylinder_lane_volumes.append(area)
			print("Lane volume entró a área ", area_index, ": ", vol_id)
			_update_visualization()

func _on_cylinder_area_exited(area: Area3D, area_index: int) -> void:
	if area is LaneVolume:
		var vol_id = area.get_id()
		
		if volume_area_refs.has(vol_id):
			var idx = volume_area_refs[vol_id].find(area_index)
			if idx != -1:
				volume_area_refs[vol_id].remove_at(idx)
			
			if volume_area_refs[vol_id].is_empty():
				volume_area_refs.erase(vol_id)
				
				var vol_idx = cylinder_lane_volumes.find(area)
				if vol_idx != -1:
					cylinder_lane_volumes.remove_at(vol_idx)
					print("Lane volume salió de todas las áreas: ", vol_id)
					_update_visualization()

func _create_debug_cylinders() -> void:
	for mesh in debug_cylinder_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	debug_cylinder_meshes.clear()
	
	for i in range(cameras.size()):
		var debug_mesh = DebugUtil.create_debug_cylinder(
			debug_cylinder_color, 
			outer_radius, 
			height, 
			segments
		)
		debug_mesh.name = "DebugCylinder_" + str(i)
		add_child(debug_mesh)
		debug_cylinder_meshes.append(debug_mesh)

func _update_visualization() -> void:
	if not lane_volumes_container or not grid_points_container:
		return
	
	for child in lane_volumes_container.get_children():
		child.queue_free()
	for child in grid_points_container.get_children():
		child.queue_free()
	
	var volumes_to_visualize: Array[LaneVolume] = []
	volumes_to_visualize.append_array(cylinder_lane_volumes)
	
	var continuation_volumes: Array[LaneVolume] = []
	if show_continuations and city:
		for vol in cylinder_lane_volumes:
			var continuations = city.get_lane_volume_continuations(vol.face_idx, vol.edge_idx)
			for cont in continuations:
				if not _volume_exists_in_array(cont, volumes_to_visualize):
					continuation_volumes.append(cont)
	
	if show_lane_volumes:
		for vol in cylinder_lane_volumes:
			var mesh = _create_volume_mesh(vol, lane_volume_color, lane_volume_transparency)
			if mesh:
				lane_volumes_container.add_child(mesh)
	
	if show_continuations:
		for cont_vol in continuation_volumes:
			var mesh = _create_volume_mesh(cont_vol, continuation_color, continuation_transparency)
			if mesh:
				lane_volumes_container.add_child(mesh)
	
	if show_grid_points:
		for vol in cylinder_lane_volumes:
			_create_grid_points_for_volume(vol, grid_point_color)
		
		if show_continuations:
			for cont_vol in continuation_volumes:
				_create_grid_points_for_volume(cont_vol, continuation_color)

func _volume_exists_in_array(vol: LaneVolume, array: Array[LaneVolume]) -> bool:
	var vol_id = vol.get_id()
	for existing in array:
		if existing.get_id() == vol_id:
			return true
	return false

func _create_volume_mesh(vol: LaneVolume, color: Color, transparency: float) -> Node3D:
	return DebugUtil.create_skewed_cube_from_planes(
		vol.start_plane_vertices,
		vol.end_plane_vertices,
		color,
		transparency
	)

func _create_grid_points_for_volume(vol: LaneVolume, color: Color) -> void:
	var effective_width = granularity
	var effective_height = granularity
	
	var width_steps = vol.width_cells * effective_width
	var height_steps = vol.height_cells * effective_height
	
	for i in range(width_steps + 1):
		for j in range(height_steps + 1):
			var u = float(i) / float(width_steps) if width_steps > 0 else 0.0
			var v = float(j) / float(height_steps) if height_steps > 0 else 0.0
			
			var point_start = vol.get_point_at_grid(u, v, true)
			var sphere_start = DebugUtil.create_debug_sphere_print(
				Vector2i(i, j), 
				color, 
				grid_point_size
			)
			grid_points_container.add_child(sphere_start)
			sphere_start.global_position = point_start
			
			var point_end = vol.get_point_at_grid(u, v, false)
			var sphere_end = DebugUtil.create_debug_sphere_print(
				Vector2i(i, j), 
				color, 
				grid_point_size
			)
			grid_points_container.add_child(sphere_end)
			sphere_end.global_position = point_end

func _try_spawn_car() -> void:
	var spawn_candidates: Array[LaneVolume] = []
	
	for cyl_vol in cylinder_lane_volumes:
		if _has_continuation_in_cylinder(cyl_vol) and not _is_lane_volume_visible(cyl_vol):
			spawn_candidates.append(cyl_vol)
	
	if spawn_candidates.is_empty():
		return
	
	# Intentar con diferentes volúmenes hasta spawnear o agotar candidatos
	while not spawn_candidates.is_empty():
		var selected_vol = _select_volume_by_traffic_density(spawn_candidates)
		var volume_id = str(selected_vol.face_idx) + "_" + str(selected_vol.edge_idx)
		
		var car_seed = randi()
		
		var neighborhood = selected_vol.get_neighborhood()
		var custom_weights = neighborhood.get_car_weights() if neighborhood else {}
		
		var temp_car = FlyingCar.new()
		temp_car.initialize_from_seed(car_seed, custom_weights)
		
		# Verificar si se puede spawnear este tipo de auto en este volumen
		if not _can_spawn_car_type_in_volume(volume_id, temp_car.car_archetype):
			temp_car.free()
			# Remover este volumen de candidatos y probar con otro
			spawn_candidates.erase(selected_vol)
			continue
		
		var v_max = selected_vol.get_max_spawn_v()
		
		var max_attempts = 10
		var spawned = false
		
		for attempt in range(max_attempts):
			var random_u = randf()
			var random_v = randf() * v_max
			
			var spawn_pos = selected_vol.get_point_at_grid(random_u, random_v, true)
			var end_pos = selected_vol.get_point_at_grid(random_u, random_v, false)
			
			var front_face = temp_car.get_front_face_at_segment(spawn_pos, end_pos)
			
			var validation = selected_vol.validate_face_projection(
				front_face,
				random_u,
				random_v
			)
			
			if not validation["valid"]:
				continue
			
			var direction = (end_pos - spawn_pos).normalized()
			if _check_spawn_collision(spawn_pos, direction, temp_car.width, temp_car.height, temp_car.depth):
				continue
			
			# Spawn exitoso
			temp_car.free()
			_spawn_car_at_volume(selected_vol, random_u, random_v, car_seed, custom_weights)
			spawned = true
			break
		
		if spawned:
			return
		
		# No se pudo spawnear por validación/colisión, probar con otro volumen
		temp_car.free()
		spawn_candidates.erase(selected_vol)

func _check_spawn_collision(spawn_pos: Vector3, direction: Vector3, 
							car_width: float, car_height: float, car_depth: float) -> bool:
	if not world:
		return false
	
	var half_width = car_width * 0.5
	var half_height = car_height * 0.5
	var half_depth = car_depth * 0.5
	var total_depth = half_depth + spawn_safety_margin
	
	for child in world.get_children():
		if not child is FlyingCar:
			continue
		
		var other_car = child as FlyingCar
		var to_other = other_car.global_position - spawn_pos
		var distance = to_other.length()
		
		var max_check_distance = (car_depth + other_car.depth) * 0.5 + spawn_safety_margin * 2
		if distance > max_check_distance:
			continue
		
		var projection = to_other.dot(direction)
		
		if abs(projection) < total_depth + (other_car.depth * 0.5):
			var lateral_offset = to_other - (direction * projection)
			var lateral_distance = lateral_offset.length()
			
			if lateral_distance < (half_width + other_car.width * 0.5):
				var height_diff = abs(spawn_pos.y - other_car.global_position.y)
				if height_diff < (half_height + other_car.height * 0.5):
					return true
	
	return false

func _is_lane_volume_visible(lane_vol: LaneVolume) -> bool:
	var vertices = []
	vertices.append_array(lane_vol.start_plane_vertices)
	vertices.append_array(lane_vol.end_plane_vertices)
	
	for camera in cameras:
		if not camera or not is_instance_valid(camera):
			continue
		
		for vertex in vertices:
			if camera.is_position_in_frustum(vertex):
				return true
	
	return false

func is_position_visible(position: Vector3) -> bool:
	for camera in cameras:
		if not camera or not is_instance_valid(camera):
			continue
		
		if camera.is_position_in_frustum(position):
			return true
	
	return false

func _select_volume_by_traffic_density(candidates: Array[LaneVolume]) -> LaneVolume:
	var total_weight = 0.0
	var weighted_candidates = []
	
	for vol in candidates:
		var density = vol.get_traffic_density()
		total_weight += density
		weighted_candidates.append({"volume": vol, "weight": density})
	
	var random_value = randf() * total_weight
	var cumulative = 0.0
	
	for item in weighted_candidates:
		cumulative += item["weight"]
		if random_value <= cumulative:
			return item["volume"]
	
	return candidates[0]

func _has_continuation_in_cylinder(vol: LaneVolume) -> bool:
	if not city:
		return false
	
	var continuations = city.get_lane_volume_continuations(vol.face_idx, vol.edge_idx)
	
	for cont in continuations:
		for cyl_vol in cylinder_lane_volumes:
			if cont.get_id() == cyl_vol.get_id():
				return true
	
	return false

func is_lane_volume_inside(lane_vol: LaneVolume) -> bool:
	for cyl_vol in cylinder_lane_volumes:
		if cyl_vol.get_id() == lane_vol.get_id():
			return true
	return false

func is_volume_inside_by_indices(face_idx: int, edge_idx: int) -> bool:
	for vol in cylinder_lane_volumes:
		if vol.face_idx == face_idx and vol.edge_idx == edge_idx:
			return true
	return false

func is_lane_volume_inside_by_calculation(lane_vol: LaneVolume) -> bool:
	var center = Vector3.ZERO
	for vertex in lane_vol.start_plane_vertices:
		center += vertex
	for vertex in lane_vol.end_plane_vertices:
		center += vertex
	center /= 8.0
	
	for camera in cameras:
		if not camera or not is_instance_valid(camera):
			continue
		
		var distance_xz = Vector2(
			center.x - camera.global_position.x,
			center.z - camera.global_position.z
		).length()
		
		if distance_xz <= outer_radius:
			return true
	
	return false

func _spawn_car_at_volume(vol: LaneVolume, grid_u: float, grid_v: float, 
						  car_seed: int, custom_weights: Dictionary) -> void:
	
	var path_segment = vol.get_path_segment_at_grid(grid_u, grid_v)
	
	var car = FlyingCar.new()
	car.world_node = world
	car.city = city
	car.area_instantiator = self
	car.spawn_time = Time.get_ticks_msec() / 1000.0
	
	car.initialize_from_seed(car_seed, custom_weights)
	
	var volume_id = str(vol.face_idx) + "_" + str(vol.edge_idx)
	if not _can_spawn_car_type_in_volume(volume_id, car.car_archetype):
		car.free()
		return
	
	world.add_child(car)
	
	_add_car_to_volume(volume_id, car.car_archetype)
	
	car.volume_changed.connect(_on_car_volume_changed)
	car.tree_exited.connect(func(): _remove_car_from_volume(volume_id, car.car_archetype))
	
	car.set_path(
		path_segment["start"],
		path_segment["end"],
		0.0,
		grid_u,
		grid_v,
		vol.get_raw_data(),
		vol.width_cells,
		vol.height_cells
	)

func _can_spawn_car_type_in_volume(volume_id: String, car_type: int) -> bool:
	var archetype = CarArchetypes.get_archetype(car_type)
	if archetype.max_per_volume == -1:
		return true
	
	if not volume_car_counts.has(volume_id):
		return true
	
	var type_count = volume_car_counts[volume_id].get(car_type, 0)
	return type_count < archetype.max_per_volume

func _add_car_to_volume(volume_id: String, car_type: int) -> void:
	if not volume_car_counts.has(volume_id):
		volume_car_counts[volume_id] = {}
	
	var current = volume_car_counts[volume_id].get(car_type, 0)
	volume_car_counts[volume_id][car_type] = current + 1

func _remove_car_from_volume(volume_id: String, car_type: int) -> void:
	if not volume_car_counts.has(volume_id):
		return
	
	var current = volume_car_counts[volume_id].get(car_type, 0)
	if current > 0:
		volume_car_counts[volume_id][car_type] = current - 1

func _on_car_volume_changed(old_volume_id: String, new_volume_id: String, car_type: int) -> void:
	if not old_volume_id.is_empty():
		_remove_car_from_volume(old_volume_id, car_type)
	if not new_volume_id.is_empty():
		_add_car_to_volume(new_volume_id, car_type)
