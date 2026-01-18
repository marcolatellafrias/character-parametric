# CollisionAvoidance.gd
extends Node
class_name CollisionAvoidance

var enabled: bool = true
var ghost_distance_multiplier: float = 2.0
var ghost_spacing: float = 3.0
var collision_buffer_zone: float = 15.0
var min_safe_distance: float = 5.0

var current_speed: float = 10.0
var base_speed: float = 10.0

# Debug
var show_ghost_debug: bool = false
var ghost_debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
var ghost_collision_color: Color = Color(1.0, 0.0, 0.0, 0.5)
var ghost_debug_meshes: Array[MeshInstance3D] = []
var ghost_debug_materials: Array[StandardMaterial3D] = []

var car_owner: FlyingCar
var path_controller: PathController
var world_node: Node3D
var collision_shape: BoxShape3D
var detection_area: Area3D

func initialize(owner_car: FlyingCar, path_ctrl: PathController, 
				world: Node3D, shape: BoxShape3D, area: Area3D) -> void:
	car_owner = owner_car
	path_controller = path_ctrl
	world_node = world
	collision_shape = shape
	detection_area = area
	base_speed = owner_car.speed
	current_speed = base_speed

func check_and_adjust_speed() -> bool:
	if not enabled:
		current_speed = base_speed
		return true
	
	var ghost_positions = _get_future_positions()
	
	if ghost_positions.is_empty():
		current_speed = base_speed
		if show_ghost_debug:
			_update_ghost_meshes([])
		return true
	
	var closest_obstacle = _scan_for_obstacles(ghost_positions)
	
	if closest_obstacle < min_safe_distance:
		current_speed = 0.0
		return false
	elif closest_obstacle < collision_buffer_zone:
		current_speed = base_speed * 0.5
		return true
	else:
		current_speed = base_speed
		return true

func get_current_speed() -> float:
	return current_speed

func _get_future_positions() -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	var current_progress = path_controller.get_progress()
	var curve_length = path_controller.get_curve_length()
	
	var check_distance = current_speed * ghost_distance_multiplier
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

func _scan_for_obstacles(ghost_positions: Array[Dictionary]) -> float:
	var space_state = car_owner.get_world_3d().direct_space_state
	var closest_distance = INF
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
		query.exclude = [detection_area]
		
		var results = space_state.intersect_shape(query, 32)
		var has_collision = _evaluate_collisions(results, relevant_ids, intersecting_planes)
		
		if has_collision:
			var distance = car_owner.global_position.distance_to(ghost_transform.origin)
			closest_distance = min(closest_distance, distance)
		
		if show_ghost_debug:
			debug_data.append({
				"progress": ghost_data["progress"],
				"has_collision": has_collision
			})
	
	if show_ghost_debug:
		_update_ghost_meshes(debug_data)
	
	return closest_distance

func _evaluate_collisions(results: Array, relevant_ids: Array[String], 
						  intersecting_planes: Array[Area3D]) -> bool:
	for result in results:
		var collider = result.get("collider")
		
		if collider is Area3D:
			if collider is TrafficPlane and collider in intersecting_planes:
				continue
			
			if collider is TrafficPlane:
				var lane_id = collider.get_meta("lane_id", "")
				if lane_id in relevant_ids:
					return true
			else:
				return true
	
	return false

func _update_ghost_meshes(debug_data: Array) -> void:
	if not world_node:
		_clear_ghost_meshes()
		return
	
	while ghost_debug_meshes.size() < debug_data.size():
		var mesh = _create_ghost_mesh()
		world_node.add_child(mesh)
		ghost_debug_meshes.append(mesh)
	
	while ghost_debug_meshes.size() > debug_data.size():
		var mesh = ghost_debug_meshes.pop_back()
		var mat = ghost_debug_materials.pop_back()
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	
	for i in range(debug_data.size()):
		var mesh = ghost_debug_meshes[i]
		var mat = ghost_debug_materials[i]
		var data = debug_data[i]
		
		var ghost_transform = path_controller.sample_baked_with_rotation(data["progress"])
		mesh.global_transform = ghost_transform
		
		mat.albedo_color = ghost_collision_color if data["has_collision"] else ghost_debug_color

func _create_ghost_mesh() -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(car_owner.width, car_owner.height, car_owner.depth)
	mesh_instance.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ghost_debug_color
	mesh_instance.material_override = mat
	
	ghost_debug_materials.append(mat)
	
	return mesh_instance

func _clear_ghost_meshes() -> void:
	for mesh in ghost_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	ghost_debug_meshes.clear()
	ghost_debug_materials.clear()

func cleanup() -> void:
	_clear_ghost_meshes()
