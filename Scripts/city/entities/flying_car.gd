# FlyingCar.gd
extends Node3D
class_name FlyingCar

signal volume_changed(old_volume_id: String, new_volume_id: String, car_type: int)

@export var width: float = 2.0
@export var height: float = 1.0
@export var depth: float = 4.0
@export var car_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var speed: float = 10.0
@export var spawn_time: float = 0.0
@export var seed: int = 0
@export var car_archetype: CarArchetypes.Type = CarArchetypes.Type.POOR_CAR

@export_group("Path Debug")
@export var show_path_debug: bool = false
@export var path_debug_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var path_debug_width: float = 0.05
@export var path_debug_segments: int = 30
@export var continuation_exact_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var continuation_approx_color: Color = Color(0.0, 1.0, 1.0, 1.0)

@export_group("Collision Avoidance")
@export var enable_collision_avoidance: bool = true
@export var ghost_distance_multiplier: float = 2.0
@export var ghost_spacing: float = 3.0
@export var collision_buffer_zone: float = 15.0
@export var min_safe_distance: float = 5.0
@export var reaction_time: float = 1.5
@export var car_collision_layer: int = 2

@export_group("Ghost Debug")
@export var show_ghost_debug: bool = false
@export var ghost_debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var ghost_collision_color: Color = Color(1.0, 0.0, 0.0, 0.5)

@export_group("Despawn Debug")
@export var take_frustum_into_account_when_despawning: bool = true

var mesh_instance: MeshInstance3D
var path_debug_mesh: MeshInstance3D
var continuation_debug_meshes: Array[MeshInstance3D] = []
var ghost_debug_meshes: Array[MeshInstance3D] = []
var ghost_debug_materials: Array[StandardMaterial3D] = []
var detection_area: Area3D
var path_3d: Path3D
var path_follow: PathFollow3D
var has_path: bool = false
var world_node: Node3D
var city = null
var area_instantiator = null

var current_volume: Dictionary = {}
var current_cell_x: int = 0
var current_cell_y: int = 0
var current_width_cells: int = 3
var current_height_cells: int = 10

var rng: RandomNumberGenerator

var is_transitioning: bool = false
var transition_point: float = 0.0
var first_segment_volume: Dictionary = {}
var second_segment_volume: Dictionary = {}

var original_color: Color
var material: StandardMaterial3D

var current_speed: float = 0.0
var collision_shape: BoxShape3D


func _ready() -> void:
	# Crear el collision_shape PRIMERO
	collision_shape = BoxShape3D.new()
	collision_shape.size = Vector3(width, height, depth)
	
	_create_visual()
	_create_detection_area()  # Ahora collision_shape ya existe
	
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	
	current_speed = speed

func _process(delta: float) -> void:
	if has_path and path_follow:
		if enable_collision_avoidance:
			var should_move = _check_forward_collisions()
			
			# Solo avanzar si está permitido
			if should_move:
				path_follow.progress += delta * current_speed
		else:
			current_speed = speed 
			path_follow.progress += delta * current_speed
		
		global_position = path_follow.global_position
		global_rotation = path_follow.global_rotation
		
		if area_instantiator:
			var is_visible = area_instantiator.is_position_visible(global_position)
			if false:#is_visible:
				material.albedo_color = Color.WHITE
			else:
				material.albedo_color = original_color

func _exit_tree() -> void:
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
	
	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()
	
	_clear_ghost_debug_meshes()
	
	if path_3d and is_instance_valid(path_3d):
		path_3d.queue_free()

func initialize_from_seed(p_seed: int, archetype_weights: Dictionary = {}) -> void:
	seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	
	car_archetype = _select_archetype_from_seed(rng, archetype_weights)
	
	var archetype = CarArchetypes.get_archetype(car_archetype)
	
	width = archetype.width
	height = archetype.height
	depth = archetype.depth
	speed = rng.randf_range(archetype.min_speed, archetype.max_speed)
	car_color = archetype.color
	original_color = archetype.color
	
	# Actualizar el collision_shape con las nuevas dimensiones
	if collision_shape:
		collision_shape.size = Vector3(width, height, depth)
	
	current_speed = speed

func _select_archetype_from_seed(rng: RandomNumberGenerator, custom_weights: Dictionary) -> CarArchetypes.Type:
	var total_weight = 0.0
	var weighted_types = []
	
	for type in CarArchetypes.Type.values():
		var archetype = CarArchetypes.get_archetype(type)
		var weight = custom_weights.get(type, archetype.weight)
		total_weight += weight
		weighted_types.append({"type": type, "weight": weight})
	
	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0
	
	for item in weighted_types:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return item["type"]
	
	return CarArchetypes.Type.POOR_CAR

func _create_visual() -> void:
	mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mesh_instance.mesh = box
	
	material = StandardMaterial3D.new()
	material.albedo_color = car_color
	mesh_instance.material_override = material
	
	add_child(mesh_instance)

func _create_detection_area() -> void:
	detection_area = Area3D.new()
	detection_area.collision_layer = 2
	detection_area.collision_mask = 2  # Cambiar de 0 a 2 para detectar TrafficPlanes
	detection_area.monitorable = true
	detection_area.monitoring = true  # Habilitar monitoreo
	
	var collision_shape_node = CollisionShape3D.new()
	collision_shape_node.shape = collision_shape
	
	detection_area.add_child(collision_shape_node)
	add_child(detection_area)

func _get_intersecting_traffic_planes() -> Array[Area3D]:
	var planes: Array[Area3D] = []
	
	if not detection_area:
		return planes
	
	var overlapping = detection_area.get_overlapping_areas()
	for area in overlapping:
		if area is TrafficPlane:
			planes.append(area)
	
	return planes

func set_path(start: Vector3, end: Vector3, initial_progress: float = 0.0, 
			  grid_u: float = 0.0, grid_v: float = 0.0, 
			  volume: Dictionary = {}, width_cells: int = 3, height_cells: int = 10) -> void:
	
	first_segment_volume = volume
	current_volume = volume
	current_cell_x = int(round(grid_u * width_cells))
	current_cell_y = int(round(grid_v * height_cells))
	current_width_cells = width_cells
	current_height_cells = height_cells
	
	var next_segment = _calculate_next_segment(end, volume)
	
	if next_segment.is_empty():
		_create_simple_path(start, end, initial_progress)
		second_segment_volume = {}
	else:
		_create_double_segment_path(start, end, next_segment, initial_progress)
		second_segment_volume = next_segment["volume_data"]
	
	has_path = true
	is_transitioning = false
	
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_check_segment_transition)
	add_child(timer)
	timer.start()

func _create_double_segment_path(start: Vector3, end: Vector3, next_segment: Dictionary, initial_progress: float = 0.0) -> void:
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	
	var first_direction = (end - start).normalized()
	var next_start = next_segment["path"]["start"]
	var next_end = next_segment["path"]["end"]
	var next_direction = (next_end - next_start).normalized()
	
	var connection_distance = (next_start - end).length()
	var handle_length = connection_distance * 0.4
	
	var out_handle = first_direction * handle_length
	var in_handle = -next_direction * handle_length
	
	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, out_handle)
	curve.add_point(next_start, in_handle, Vector3.ZERO)
	curve.add_point(next_end, Vector3.ZERO, Vector3.ZERO)
	
	path_3d.curve = curve
	
	transition_point = curve.get_closest_offset(next_start)
	
	if world_node:
		world_node.add_child(path_3d)
	else:
		get_parent().add_child(path_3d)
	
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	var curve_length = curve.get_baked_length()
	path_follow.progress = initial_progress * curve_length
	
	global_position = path_follow.global_position
	global_rotation = path_follow.global_rotation
	
	if show_path_debug and world_node:
		_create_path_debug()

func _create_simple_path(start: Vector3, end: Vector3, initial_progress: float = 0.0) -> void:
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, Vector3.ZERO)
	path_3d.curve = curve
	
	transition_point = -1.0
	
	if world_node:
		world_node.add_child(path_3d)
	else:
		get_parent().add_child(path_3d)
	
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	var curve_length = curve.get_baked_length()
	path_follow.progress = initial_progress * curve_length
	
	global_position = path_follow.global_position
	global_rotation = path_follow.global_rotation
	
	if show_path_debug and world_node:
		_create_path_debug()

func _create_path_debug() -> void:
	var points = []
	for i in range(path_3d.curve.point_count):
		points.append({
			"pos": path_3d.curve.get_point_position(i),
			"in": path_3d.curve.get_point_in(i),
			"out": path_3d.curve.get_point_out(i)
		})
	
	path_debug_mesh = DebugUtil.create_debug_path3d(
		points,
		path_debug_segments,
		path_debug_color,
		path_debug_width
	)
	world_node.add_child(path_debug_mesh)

func _check_segment_transition() -> void:
	if not path_follow or not path_3d:
		return
	
	var current_progress = path_follow.progress
	var curve_length = path_3d.curve.get_baked_length()
	
	if current_progress >= curve_length:
		queue_free()
		return
	
	if transition_point > 0 and current_progress >= transition_point and not is_transitioning:
		is_transitioning = true
		_advance_to_next_segment()

func _advance_to_next_segment() -> void:
	var old_volume_id = _get_volume_id(first_segment_volume)
	var new_volume_id = _get_volume_id(second_segment_volume)
	
	first_segment_volume = second_segment_volume
	current_volume = first_segment_volume
	current_cell_x = second_segment_volume.get("used_cell_x", current_cell_x)
	current_cell_y = second_segment_volume.get("used_cell_y", current_cell_y)
	current_width_cells = second_segment_volume.get("width_cells", current_width_cells)
	current_height_cells = second_segment_volume.get("height_cells", current_height_cells)
	
	if area_instantiator:
		volume_changed.emit(old_volume_id, new_volume_id, car_archetype)
	
	var current_end = path_3d.curve.get_point_position(3)
	var next_segment = _calculate_next_segment(current_end, first_segment_volume)
	
	if next_segment.is_empty():
		var current_start = path_3d.curve.get_point_position(2)
		_regenerate_path_from_segment(current_start, current_end)
		second_segment_volume = {}
		is_transitioning = false
		return
	
	var current_start = path_3d.curve.get_point_position(2)
	_regenerate_double_segment_path(current_start, current_end, next_segment)
	second_segment_volume = next_segment["volume_data"]
	
	is_transitioning = false

func _regenerate_double_segment_path(start: Vector3, end: Vector3, next_segment: Dictionary) -> void:
	var current_position = global_position
	var current_rotation = global_rotation
	
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
	
	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()
	
	var old_path = path_3d
	
	_create_double_segment_path(start, end, next_segment, 0.0)
	
	var closest_offset = path_3d.curve.get_closest_offset(current_position)
	path_follow.progress = closest_offset
	
	global_position = path_follow.global_position
	global_rotation = path_follow.global_rotation
	
	if old_path and is_instance_valid(old_path):
		old_path.queue_free()

func _regenerate_path_from_segment(start: Vector3, end: Vector3) -> void:
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
	
	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()
	
	var old_path = path_3d
	_create_simple_path(start, end, 0.0)
	
	if old_path and is_instance_valid(old_path):
		old_path.queue_free()

func _calculate_next_segment(current_end: Vector3, volume: Dictionary) -> Dictionary:
	if not city or not volume.has("face_idx") or not volume.has("edge_idx"):
		return {}
	
	var face_idx = volume["face_idx"]
	var edge_idx = volume["edge_idx"]
	
	var continuations = city.get_lane_volume_continuations(face_idx, edge_idx)
	
	if area_instantiator and continuations.is_empty():
		var car_inside_any_cylinder = false
		for camera in area_instantiator.cameras:
			if not camera or not is_instance_valid(camera):
				continue
			
			var distance_xz = Vector2(
				global_position.x - camera.global_position.x,
				global_position.z - camera.global_position.z
			).length()
			
			if distance_xz <= area_instantiator.outer_radius:
				car_inside_any_cylinder = true
				break
		
		var car_visible = false
		if take_frustum_into_account_when_despawning:
			for camera in area_instantiator.cameras:
				if not camera or not is_instance_valid(camera):
					continue
				
				if camera.is_position_in_frustum(global_position):
					car_visible = true
					break
		
		if not car_inside_any_cylinder and not car_visible:
			return {}
	
	if continuations.is_empty():
		return {}
	
	var current_direction = (current_end - path_3d.curve.get_point_position(0)).normalized() if path_3d else Vector3.FORWARD
	var valid_continuations = []
	
	for cont_vol in continuations:
		var result = _get_validated_continuation_path(cont_vol, current_cell_x, current_cell_y)
		
		if result != null and result.has("start") and result.has("end"):
			var cont_direction = (result["end"] - result["start"]).normalized()
			var angle_diff = abs(current_direction.angle_to(cont_direction))
			
			valid_continuations.append({
				"volume": cont_vol,
				"path": result,
				"angle_diff": angle_diff
			})
	
	if valid_continuations.is_empty():
		return {}
	
	var selected = _select_continuation_by_angle(valid_continuations)
	
	if selected:
		return {
			"path": selected["path"],
			"volume_data": {
				"face_idx": selected["volume"].face_idx,
				"edge_idx": selected["volume"].edge_idx,
				"used_cell_x": selected["path"]["used_cell_x"],
				"used_cell_y": selected["path"]["used_cell_y"],
				"width_cells": selected["volume"].width_cells,
				"height_cells": selected["volume"].height_cells
			}
		}
	
	return {}

func _get_volume_id(volume: Dictionary) -> String:
	if volume.has("face_idx") and volume.has("edge_idx"):
		return str(volume["face_idx"]) + "_" + str(volume["edge_idx"])
	return ""

func _select_continuation_by_angle(continuations: Array) -> Dictionary:
	var total_weight = 0.0
	var weighted_continuations = []
	
	for cont in continuations:
		var lane_vol = cont["volume"]
		var angle_diff = cont["angle_diff"]
		
		var angle_weight = PI - angle_diff
		var traffic_weight = lane_vol.get_traffic_density()
		var affinity_weight = _get_neighborhood_affinity(lane_vol)
		
		var combined_weight = (angle_weight * 0.3) + (traffic_weight * 0.35) + (affinity_weight * 0.35)
		
		total_weight += combined_weight
		weighted_continuations.append({
			"continuation": cont,
			"weight": combined_weight
		})
	
	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0
	
	for item in weighted_continuations:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return item["continuation"]
	
	return continuations[0] if not continuations.is_empty() else {}

func _get_neighborhood_affinity(lane_vol: LaneVolume) -> float:
	var neighborhood = lane_vol.get_neighborhood()
	if not neighborhood:
		return 0.5
	
	return CarArchetypes.get_neighborhood_affinity(car_archetype, neighborhood.type)

func _get_validated_continuation_path(lane_vol: LaneVolume, target_cell_x: int, target_cell_y: int) -> Variant:
	var cont_width_cells = lane_vol.width_cells
	var cont_height_cells = lane_vol.height_cells
	
	var x_in_range = (target_cell_x >= 0 and target_cell_x <= cont_width_cells)
	var y_in_range = (target_cell_y >= 0 and target_cell_y <= cont_height_cells)
	
	var current_cell_x = target_cell_x
	var current_cell_y = target_cell_y
	var is_exact = true
	
	if not x_in_range or not y_in_range:
		current_cell_x = clampi(target_cell_x, 0, cont_width_cells)
		current_cell_y = clampi(target_cell_y, 0, cont_height_cells)
		is_exact = false
	
	var max_tries = 5
	for attempt in range(max_tries):
		var u = float(current_cell_x) / float(cont_width_cells) if cont_width_cells > 0 else 0.0
		var v = float(current_cell_y) / float(cont_height_cells) if cont_height_cells > 0 else 0.0
		
		var path_segment = lane_vol.get_path_segment_at_grid(u, v)
		
		var front_face = get_front_face_at_segment(path_segment["start"], path_segment["end"])
		
		var validation = lane_vol.validate_face_projection(front_face, u, v)
		
		if validation["valid"]:
			return {
				"start": path_segment["start"],
				"end": path_segment["end"],
				"is_exact": is_exact and (attempt == 0),
				"used_cell_x": current_cell_x,
				"used_cell_y": current_cell_y,
				"attempts": attempt + 1
			}
		
		var collision_plane = validation["collision_plane"]
		var moved = _move_away_from_plane(
			collision_plane, 
			current_cell_x, 
			current_cell_y, 
			cont_width_cells, 
			cont_height_cells
		)
		
		if moved.has("cell_x") and moved.has("cell_y"):
			current_cell_x = moved["cell_x"]
			current_cell_y = moved["cell_y"]
			is_exact = false
		else:
			break
	
	return null

func _move_away_from_plane(plane_name: String, current_x: int, current_y: int, 
						   max_width: int, max_height: int) -> Dictionary:
	var new_x = current_x
	var new_y = current_y
	
	match plane_name:
		"bottom":
			new_y = current_y + 1
		"top":
			new_y = current_y - 1
		"left":
			new_x = current_x + 1
		"right":
			new_x = current_x - 1
	
	if new_x < 0 or new_x > max_width or new_y < 0 or new_y > max_height:
		return {}
	
	return {
		"cell_x": new_x,
		"cell_y": new_y
	}

func build_front_face() -> Array:
	var direction = -global_transform.basis.z.normalized()
	
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	
	var right = direction.cross(up).normalized()
	var true_up = right.cross(direction).normalized()
	
	var half_width = width * 0.5
	var half_height = height * 0.5
	
	return [
		-right * half_width - true_up * half_height,
		right * half_width - true_up * half_height,
		right * half_width + true_up * half_height,
		-right * half_width + true_up * half_height
	]

func get_front_face_at_segment(start: Vector3, end: Vector3) -> Array:
	var direction = (end - start).normalized()
	
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	
	var right = direction.cross(up).normalized()
	var true_up = right.cross(direction).normalized()
	
	var half_width = width * 0.5
	var half_height = height * 0.5
	
	return [
		-right * half_width - true_up * half_height,
		right * half_width - true_up * half_height,
		right * half_width + true_up * half_height,
		-right * half_width + true_up * half_height
	]

# === COLLISION AVOIDANCE ===

func _get_future_path_positions() -> Array[Dictionary]:
	if not path_follow or not path_3d:
		return []
	
	var positions: Array[Dictionary] = []
	var current_progress = path_follow.progress
	var curve_length = path_3d.curve.get_baked_length()
	
	var check_distance = current_speed * ghost_distance_multiplier
	var num_ghosts = int(check_distance / ghost_spacing)
	num_ghosts = clampi(num_ghosts, 3, 15)
	
	for i in range(1, num_ghosts + 1):
		var future_progress = current_progress + (ghost_spacing * i)
		
		if future_progress >= curve_length:
			break
		
		var position = path_3d.curve.sample_baked(future_progress)
		positions.append({
			"position": position,
			"distance": ghost_spacing * i,
			"progress": future_progress
		})
	
	return positions

# FlyingCar.gd

func _check_forward_collisions() -> bool:
	var ghost_positions = _get_future_path_positions()
	
	if ghost_positions.is_empty():
		current_speed = speed
		if show_ghost_debug:
			_update_ghost_debug_meshes([])
		return true
	
	var space_state = get_world_3d().direct_space_state
	var closest_obstacle_distance = INF
	var collision_detected = false
	
	var debug_data = []
	var relevant_ids = _get_relevant_volume_ids()
	var intersecting_planes = _get_intersecting_traffic_planes()  # NUEVO
	
	for ghost_data in ghost_positions:
		var ghost_transform = path_3d.curve.sample_baked_with_rotation(ghost_data["progress"])
		
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = collision_shape
		query.transform = ghost_transform
		query.collision_mask = 2
		query.collide_with_areas = true
		query.exclude = [detection_area]
		
		var results = space_state.intersect_shape(query, 32)
		
		var has_collision = false
		
		for result in results:
			var collider = result.get("collider")
			
			if collider is Area3D:
				# NUEVO: Ignorar TrafficPlanes que ya estamos tocando
				if collider is TrafficPlane and collider in intersecting_planes:
					continue
				
				if collider is TrafficPlane:
					var lane_id = collider.get_meta("lane_id", "")
					if lane_id in relevant_ids:
						has_collision = true
						break
				else:
					has_collision = true
					break
		
		if has_collision:
			var distance = global_position.distance_to(ghost_transform.origin)
			closest_obstacle_distance = min(closest_obstacle_distance, distance)
			collision_detected = true
		
		if show_ghost_debug:
			debug_data.append({
				"progress": ghost_data["progress"],
				"has_collision": has_collision
			})
	
	if show_ghost_debug:
		_update_ghost_debug_meshes(debug_data)
	
	if closest_obstacle_distance < min_safe_distance:
		current_speed = 0.0
		return false
	elif closest_obstacle_distance < collision_buffer_zone:
		current_speed = speed * 0.5
		return true
	else:
		current_speed = speed
		return true

func _create_ghost_mesh() -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mesh_instance.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ghost_debug_color
	mesh_instance.material_override = mat
	
	ghost_debug_materials.append(mat)
	
	return mesh_instance

func _update_ghost_debug_meshes(debug_data: Array) -> void:
	if not world_node or not path_3d:
		_clear_ghost_debug_meshes()
		return
	
	# Ajustar cantidad de meshes solo si es necesario
	while ghost_debug_meshes.size() < debug_data.size():
		var mesh = _create_ghost_mesh()
		world_node.add_child(mesh)
		ghost_debug_meshes.append(mesh)
	
	while ghost_debug_meshes.size() > debug_data.size():
		var mesh = ghost_debug_meshes.pop_back()
		var mat = ghost_debug_materials.pop_back()
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	
	# Solo actualizar transformación y color de meshes existentes
	for i in range(debug_data.size()):
		var mesh = ghost_debug_meshes[i]
		var mat = ghost_debug_materials[i]
		var data = debug_data[i]
		
		var ghost_transform = path_3d.curve.sample_baked_with_rotation(data["progress"])
		mesh.global_transform = ghost_transform
		
		mat.albedo_color = ghost_collision_color if data["has_collision"] else ghost_debug_color

func _clear_ghost_debug_meshes() -> void:
	for mesh in ghost_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	ghost_debug_meshes.clear()
	ghost_debug_materials.clear()

func _get_relevant_volume_ids() -> Array[String]:
	var ids: Array[String] = []
	
	if not first_segment_volume.is_empty():
		ids.append(_get_volume_id(first_segment_volume))
	
	if not second_segment_volume.is_empty():
		ids.append(_get_volume_id(second_segment_volume))
	
	return ids
