extends Node
class_name CollisionAvoidance

var enabled: bool = true
var ghost_distance_multiplier: float = 2.0
var ghost_spacing: float = 3.0
var collision_buffer_zone: float = 15.0
var min_safe_distance: float = 5.0

var broadcast_distance_multiplier: float = 2.0
var broadcast_spacing: float = 3.0

var current_speed: float = 10.0
var base_speed: float = 10.0

# Debug
var show_ghost_debug: bool = false
var show_broadcast_debug: bool = false
var ghost_debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
var ghost_collision_color: Color = Color(1.0, 0.0, 0.0, 0.5)
var broadcast_debug_color: Color = Color(0.0, 0.5, 1.0, 0.3)

var detection_debug_meshes: Array[MeshInstance3D] = []
var detection_debug_materials: Array[StandardMaterial3D] = []
var broadcast_debug_meshes: Array[MeshInstance3D] = []
var broadcast_debug_materials: Array[StandardMaterial3D] = []

var car_owner: FlyingCar
var path_controller: PathController
var world_node: Node3D
var collision_shape: BoxShape3D
var detection_area: Area3D
var broadcast_area: Area3D

var broadcast_shapes: Array[CollisionShape3D] = []

# Estado de bloqueo
var blocking_car_id: String = ""
var is_blocked_by_broadcast: bool = false

func initialize(owner_car: FlyingCar, path_ctrl: PathController, 
				world: Node3D, shape: BoxShape3D, det_area: Area3D, broad_area: Area3D) -> void:
	car_owner = owner_car
	path_controller = path_ctrl
	world_node = world
	collision_shape = shape
	detection_area = det_area
	broadcast_area = broad_area
	base_speed = owner_car.speed
	current_speed = base_speed

func check_and_adjust_speed() -> bool:
	_update_broadcast_ghosts()
	
	blocking_car_id = ""
	is_blocked_by_broadcast = false
	
	if not enabled:
		current_speed = base_speed
		return true
	
	var ghost_positions = _get_detection_positions()
	
	if ghost_positions.is_empty():
		current_speed = base_speed
		if show_ghost_debug:
			_update_detection_debug_meshes([])
		return true
	
	var obstacle_info = _scan_for_obstacles(ghost_positions)
	var closest_obstacle = obstacle_info["distance"]
	blocking_car_id = obstacle_info["blocking_car_id"]
	is_blocked_by_broadcast = obstacle_info["is_broadcast"]
	
	if closest_obstacle < min_safe_distance:
		current_speed = 0.0
		return false
	elif closest_obstacle < collision_buffer_zone:
		current_speed = base_speed * 0.5
		return true
	else:
		current_speed = base_speed
		blocking_car_id = ""
		is_blocked_by_broadcast = false
		return true

func get_current_speed() -> float:
	return current_speed

func get_blocking_info() -> Dictionary:
	return {
		"is_blocked": current_speed == 0.0,
		"blocking_car_id": blocking_car_id,
		"is_broadcast": is_blocked_by_broadcast
	}

# ============ DETECTION GHOSTS ============

func _get_detection_positions() -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	var current_progress = path_controller.get_progress()
	var curve_length = path_controller.get_curve_length()
	
	var check_distance = base_speed * ghost_distance_multiplier
	var num_ghosts = int(check_distance / ghost_spacing)
	num_ghosts = clampi(num_ghosts, 3, 15)
	
	for i in range(1, num_ghosts + 1):
		var future_progress = current_progress + (ghost_spacing * i)
		
		if future_progress >= curve_length:
			break
		
		positions.append({
			"progress": future_progress,
			"distance": ghost_spacing * i
		})
	
	return positions

func _scan_for_obstacles(ghost_positions: Array[Dictionary]) -> Dictionary:
	var space_state = car_owner.get_world_3d().direct_space_state
	var closest_distance = INF
	var closest_car_id = ""
	var closest_is_broadcast = false
	var debug_data = []
	
	var relevant_ids = car_owner.get_relevant_volume_ids()
	var intersecting_planes = car_owner.get_intersecting_traffic_planes()
	
	for ghost_data in ghost_positions:
		var ghost_transform = path_controller.sample_baked_with_rotation(ghost_data["progress"])
		
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = collision_shape
		query.transform = ghost_transform
		query.collision_mask = 2
		query.collide_with_areas = true
		query.exclude = [detection_area, broadcast_area]
		
		var results = space_state.intersect_shape(query, 32)
		var collision_info = _evaluate_collisions(results, relevant_ids, intersecting_planes)
		
		if collision_info["has_collision"]:
			var distance = car_owner.global_position.distance_to(ghost_transform.origin)
			if distance < closest_distance:
				closest_distance = distance
				closest_car_id = collision_info["car_id"]
				closest_is_broadcast = collision_info["is_broadcast"]
		
		if show_ghost_debug:
			debug_data.append({
				"progress": ghost_data["progress"],
				"has_collision": collision_info["has_collision"]
			})
	
	if show_ghost_debug:
		_update_detection_debug_meshes(debug_data)
	elif not detection_debug_meshes.is_empty():
		_clear_detection_debug_meshes()
	
	return {
		"distance": closest_distance,
		"blocking_car_id": closest_car_id,
		"is_broadcast": closest_is_broadcast
	}

func _evaluate_collisions(results: Array, relevant_ids: Array[String], 
						  intersecting_planes: Array[Area3D]) -> Dictionary:
	for result in results:
		var collider = result.get("collider")
		
		if collider is Area3D:
			if collider is TrafficPlane and collider in intersecting_planes:
				continue
			
			if collider is TrafficPlane:
				var lane_id = collider.get_meta("lane_id", "")
				if lane_id in relevant_ids:
					return {
						"has_collision": true,
						"car_id": "",
						"is_broadcast": false
					}
			else:
				# Colisión con área de detección o broadcast de otro auto
				var other_car = _find_car_from_area(collider)
				if other_car:
					var is_broadcast = (collider == other_car.broadcast_area)
					return {
						"has_collision": true,
						"car_id": other_car.car_id,
						"is_broadcast": is_broadcast
					}
				return {
					"has_collision": true,
					"car_id": "",
					"is_broadcast": false
				}
	
	return {
		"has_collision": false,
		"car_id": "",
		"is_broadcast": false
	}

func _find_car_from_area(area: Area3D) -> FlyingCar:
	var parent = area.get_parent()
	if parent is FlyingCar:
		return parent
	return null

# ============ BROADCAST GHOSTS ============

func _update_broadcast_ghosts() -> void:
	if current_speed <= 0.0:
		_clear_broadcast_shapes()
		if show_broadcast_debug:
			_clear_broadcast_debug_meshes()
		return
	
	var broadcast_positions = _get_broadcast_positions()
	_update_broadcast_shapes(broadcast_positions)
	
	if show_broadcast_debug:
		_update_broadcast_debug_meshes(broadcast_positions)
	elif not broadcast_debug_meshes.is_empty():
		_clear_broadcast_debug_meshes()

func _get_broadcast_positions() -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	var current_progress = path_controller.get_progress()
	var curve_length = path_controller.get_curve_length()
	
	var check_distance = current_speed * broadcast_distance_multiplier
	var num_ghosts = int(check_distance / broadcast_spacing)
	num_ghosts = clampi(num_ghosts, 1, 15)
	
	for i in range(1, num_ghosts + 1):
		var future_progress = current_progress + (broadcast_spacing * i)
		
		if future_progress >= curve_length:
			break
		
		positions.append({
			"progress": future_progress
		})
	
	return positions

func _update_broadcast_shapes(positions: Array[Dictionary]) -> void:
	var needed = positions.size()
	
	while broadcast_shapes.size() < needed:
		var shape_node = CollisionShape3D.new()
		shape_node.shape = collision_shape
		broadcast_area.add_child(shape_node)
		broadcast_shapes.append(shape_node)
	
	while broadcast_shapes.size() > needed:
		var shape_node = broadcast_shapes.pop_back()
		shape_node.queue_free()
	
	for i in range(positions.size()):
		var shape_node = broadcast_shapes[i]
		var ghost_transform = path_controller.sample_baked_with_rotation(positions[i]["progress"])
		shape_node.global_transform = ghost_transform

func _clear_broadcast_shapes() -> void:
	for shape_node in broadcast_shapes:
		if shape_node and is_instance_valid(shape_node):
			shape_node.queue_free()
	broadcast_shapes.clear()

# ============ DEBUG VISUALIZATION ============

func _update_detection_debug_meshes(debug_data: Array) -> void:
	if not world_node:
		_clear_detection_debug_meshes()
		return
	
	while detection_debug_meshes.size() < debug_data.size():
		var mesh = _create_debug_mesh(ghost_debug_color)
		world_node.add_child(mesh)
		detection_debug_meshes.append(mesh)
		detection_debug_materials.append(mesh.material_override)
	
	while detection_debug_meshes.size() > debug_data.size():
		var mesh = detection_debug_meshes.pop_back()
		detection_debug_materials.pop_back()
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	
	for i in range(debug_data.size()):
		var mesh = detection_debug_meshes[i]
		var mat = detection_debug_materials[i]
		var data = debug_data[i]
		
		var ghost_transform = path_controller.sample_baked_with_rotation(data["progress"])
		mesh.global_transform = ghost_transform
		
		mat.albedo_color = ghost_collision_color if data["has_collision"] else ghost_debug_color

func _update_broadcast_debug_meshes(positions: Array[Dictionary]) -> void:
	if not world_node:
		_clear_broadcast_debug_meshes()
		return
	
	while broadcast_debug_meshes.size() < positions.size():
		var mesh = _create_debug_mesh(broadcast_debug_color)
		world_node.add_child(mesh)
		broadcast_debug_meshes.append(mesh)
		broadcast_debug_materials.append(mesh.material_override)
	
	while broadcast_debug_meshes.size() > positions.size():
		var mesh = broadcast_debug_meshes.pop_back()
		broadcast_debug_materials.pop_back()
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	
	for i in range(positions.size()):
		var mesh = broadcast_debug_meshes[i]
		var ghost_transform = path_controller.sample_baked_with_rotation(positions[i]["progress"])
		mesh.global_transform = ghost_transform

func _create_debug_mesh(color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(car_owner.width, car_owner.height, car_owner.depth)
	mesh_instance.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mesh_instance.material_override = mat
	
	return mesh_instance

func _clear_detection_debug_meshes() -> void:
	for mesh in detection_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	detection_debug_meshes.clear()
	detection_debug_materials.clear()

func _clear_broadcast_debug_meshes() -> void:
	for mesh in broadcast_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	broadcast_debug_meshes.clear()
	broadcast_debug_materials.clear()

func cleanup() -> void:
	_clear_broadcast_shapes()
	_clear_detection_debug_meshes()
	_clear_broadcast_debug_meshes()
