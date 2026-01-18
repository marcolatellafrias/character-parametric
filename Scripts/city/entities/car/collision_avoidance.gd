# CollisionAvoidance.gd - COMPLETO
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

# Smooth speed transitions
var max_deceleration: float = 15.0
var max_acceleration: float = 8.0
var reaction_distance: float = 30.0

# Timeout system
var timeout_enabled: bool = true
var timeout_duration: float = 3.0
var blocked_time: float = 0.0
var last_blocking_car: String = ""
var ignored_cars: Dictionary = {}

# Movement tracking for timeout
var blocked_start_progress: float = 0.0
var blocked_start_blocking_car_position: Vector3 = Vector3.ZERO
var blocking_car_reference: WeakRef = null
var movement_threshold: float = 2.0

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
	
	var previous_blocking_car = blocking_car_id
	var previous_is_broadcast = is_blocked_by_broadcast
	
	blocking_car_id = ""
	is_blocked_by_broadcast = false
	
	if not enabled:
		current_speed = base_speed
		blocked_time = 0.0
		last_blocking_car = ""
		blocking_car_reference = null
		return true
	
	var ghost_positions = _get_detection_positions()
	
	if ghost_positions.is_empty():
		var target_speed = base_speed
		current_speed = _smooth_speed_transition(current_speed, target_speed, get_process_delta_time())
		blocked_time = 0.0
		last_blocking_car = ""
		blocking_car_reference = null
		if show_ghost_debug:
			_update_detection_debug_meshes([])
		return true
	
	var obstacle_info = _scan_for_obstacles(ghost_positions)
	var closest_obstacle = obstacle_info["distance"]
	blocking_car_id = obstacle_info["blocking_car_id"]
	is_blocked_by_broadcast = obstacle_info["is_broadcast"]
	var blocking_car_node = obstacle_info.get("blocking_car_node", null)
	
	# Actualizar tiempo de bloqueo y verificar movimiento
	if timeout_enabled and blocking_car_id != "" and not is_blocked_by_broadcast:
		if blocking_car_id == last_blocking_car:
			blocked_time += get_process_delta_time()
			
			if blocked_time >= timeout_duration:
				# Verificar si ambos autos están estancados
				var current_progress = path_controller.get_progress()
				var self_moved = abs(current_progress - blocked_start_progress) >= movement_threshold
				
				var other_moved = false
				if blocking_car_reference and blocking_car_reference.get_ref():
					var blocking_car = blocking_car_reference.get_ref()
					var current_blocking_position = blocking_car.global_position
					other_moved = current_blocking_position.distance_to(blocked_start_blocking_car_position) >= movement_threshold
				
				# Verificar si la cadena está esperando un semáforo
				var waiting_for_light = false
				if blocking_car_node:
					waiting_for_light = _is_blocked_by_traffic_light_chain(blocking_car_node)
				
				# Solo ignorar si NINGUNO se movió Y NO está esperando semáforo
				if not self_moved and not other_moved and not waiting_for_light:
					ignored_cars[blocking_car_id] = true
					blocked_time = 0.0
					blocking_car_reference = null
				else:
					# Al menos uno se movió o están esperando luz, resetear tracking
					blocked_time = 0.0
					blocked_start_progress = current_progress
					if blocking_car_node:
						blocked_start_blocking_car_position = blocking_car_node.global_position
		else:
			# Nuevo auto bloqueante, iniciar tracking
			blocked_time = 0.0
			last_blocking_car = blocking_car_id
			blocked_start_progress = path_controller.get_progress()
			
			if blocking_car_node:
				blocked_start_blocking_car_position = blocking_car_node.global_position
				blocking_car_reference = weakref(blocking_car_node)
			else:
				blocking_car_reference = null
	else:
		blocked_time = 0.0
		last_blocking_car = ""
		blocking_car_reference = null
	
	_cleanup_ignored_cars(ghost_positions)
	
	# Calcular velocidad objetivo basada en distancia
	var target_speed = _calculate_target_speed(closest_obstacle)
	
	# Aplicar transición suave con límites de aceleración
	current_speed = _smooth_speed_transition(current_speed, target_speed, get_process_delta_time())
	
	# Limpiar blocking_car_id si ya no está bloqueado
	if current_speed >= base_speed * 0.95:
		blocking_car_id = ""
		is_blocked_by_broadcast = false
	
	return current_speed > 0.0

func _is_blocked_by_traffic_light_chain(car_node: FlyingCar, depth: int = 0, max_depth: int = 20) -> bool:
	if depth >= max_depth:
		return false
	
	# Verificar si este auto está esperando directamente un semáforo
	if car_node.is_blocked_by_traffic_plane:
		return true
	
	# Verificar si está bloqueado por otro auto y seguir la cadena
	if car_node.collision_avoidance.blocking_car_reference:
		var ref = car_node.collision_avoidance.blocking_car_reference.get_ref()
		if ref and ref is FlyingCar:
			return _is_blocked_by_traffic_light_chain(ref, depth + 1, max_depth)
	
	return false

func _calculate_target_speed(distance: float) -> float:
	if distance == INF:
		return base_speed
	
	if distance < min_safe_distance:
		return 0.0
	
	if distance < reaction_distance:
		var t = (distance - min_safe_distance) / (reaction_distance - min_safe_distance)
		t = clamp(t, 0.0, 1.0)
		t = 1.0 - (1.0 - t) * (1.0 - t)
		return base_speed * t
	
	return base_speed

func _smooth_speed_transition(current: float, target: float, delta: float) -> float:
	var speed_diff = target - current
	
	var max_change = max_acceleration * delta if speed_diff > 0 else max_deceleration * delta
	
	var actual_change = clamp(speed_diff, -max_change, max_change)
	
	return current + actual_change

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
	var closest_car_node = null
	var found_traffic_plane = false
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
			if collision_info["blocked_by_plane"]:
				found_traffic_plane = true
			
			var distance = car_owner.global_position.distance_to(ghost_transform.origin)
			if distance < closest_distance:
				closest_distance = distance
				closest_car_id = collision_info["car_id"]
				closest_is_broadcast = collision_info["is_broadcast"]
				closest_car_node = collision_info["car_node"]
		
		if show_ghost_debug:
			debug_data.append({
				"progress": ghost_data["progress"],
				"has_collision": collision_info["has_collision"]
			})
	
	# Actualizar flag en el auto
	car_owner.is_blocked_by_traffic_plane = found_traffic_plane
	
	if show_ghost_debug:
		_update_detection_debug_meshes(debug_data)
	elif not detection_debug_meshes.is_empty():
		_clear_detection_debug_meshes()
	
	return {
		"distance": closest_distance,
		"blocking_car_id": closest_car_id,
		"is_broadcast": closest_is_broadcast,
		"blocking_car_node": closest_car_node
	}

func _evaluate_collisions(results: Array, relevant_ids: Array[String], 
						  intersecting_planes: Array[Area3D]) -> Dictionary:
	var blocked_by_plane = false
	
	for result in results:
		var collider = result.get("collider")
		
		if collider is Area3D:
			if collider is TrafficPlane and collider in intersecting_planes:
				continue
			
			if collider is TrafficPlane:
				var lane_id = collider.get_meta("lane_id", "")
				if lane_id in relevant_ids:
					# Verificar si es un semáforo en rojo
					if collider.collision_layer == 2:
						blocked_by_plane = true
					
					return {
						"has_collision": true,
						"car_id": "",
						"is_broadcast": false,
						"car_node": null,
						"blocked_by_plane": blocked_by_plane
					}
			else:
				var other_car = _find_car_from_area(collider)
				if other_car:
					if ignored_cars.has(other_car.car_id):
						continue
					
					var is_broadcast = (collider == other_car.broadcast_area)
					return {
						"has_collision": true,
						"car_id": other_car.car_id,
						"is_broadcast": is_broadcast,
						"car_node": other_car,
						"blocked_by_plane": false
					}
				return {
					"has_collision": true,
					"car_id": "",
					"is_broadcast": false,
					"car_node": null,
					"blocked_by_plane": false
				}
	
	return {
		"has_collision": false,
		"car_id": "",
		"is_broadcast": false,
		"car_node": null,
		"blocked_by_plane": false
	}

func _find_car_from_area(area: Area3D) -> FlyingCar:
	var parent = area.get_parent()
	if parent is FlyingCar:
		return parent
	return null

func _cleanup_ignored_cars(ghost_positions: Array[Dictionary]) -> void:
	if ignored_cars.is_empty():
		return
	
	var space_state = car_owner.get_world_3d().direct_space_state
	var cars_to_remove = []
	
	for car_id in ignored_cars.keys():
		var still_detected = false
		
		for ghost_data in ghost_positions:
			var ghost_transform = path_controller.sample_baked_with_rotation(ghost_data["progress"])
			
			var query = PhysicsShapeQueryParameters3D.new()
			query.shape = collision_shape
			query.transform = ghost_transform
			query.collision_mask = 2
			query.collide_with_areas = true
			query.exclude = [detection_area, broadcast_area]
			
			var results = space_state.intersect_shape(query, 32)
			
			for result in results:
				var collider = result.get("collider")
				if collider is Area3D and not (collider is TrafficPlane):
					var other_car = _find_car_from_area(collider)
					if other_car and other_car.car_id == car_id:
						still_detected = true
						break
			
			if still_detected:
				break
		
		if not still_detected:
			cars_to_remove.append(car_id)
	
	for car_id in cars_to_remove:
		ignored_cars.erase(car_id)

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
	ignored_cars.clear()
	blocked_time = 0.0
	last_blocking_car = ""
	blocking_car_reference = null
