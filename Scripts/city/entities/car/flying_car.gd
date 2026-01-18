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
@export var show_path_debug: bool = true
@export var path_debug_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var path_debug_width: float = 0.05
@export var path_debug_segments: int = 30

@export_group("Collision Avoidance")
@export var enable_collision_avoidance: bool = true
@export var ghost_distance_multiplier: float = 2.0
@export var ghost_spacing: float = 3.0
@export var collision_buffer_zone: float = 15.0
@export var min_safe_distance: float = 5.0
@export var timeout_enabled: bool = true  # Nueva
@export var timeout_duration: float = 3.0  # Nueva

@export_group("Broadcast")
@export var broadcast_distance_multiplier: float = 2.0
@export var broadcast_spacing: float = 3.0

@export_group("Ghost Debug")
@export var show_ghost_debug: bool = true
@export var ghost_debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var ghost_collision_color: Color = Color(1.0, 0.0, 0.0, 0.5)
@export var show_broadcast_debug: bool = true
@export var broadcast_debug_color: Color = Color(0.0, 0.5, 1.0, 0.3)

@export_group("Despawn Debug")
@export var take_frustum_into_account_when_despawning: bool = true

@export_group("Debug Info")
@export var show_debug_label: bool = true
@export var debug_label_offset: Vector3 = Vector3(0, 2, 0)

var mesh_instance: MeshInstance3D
var detection_area: Area3D
var broadcast_area: Area3D
var collision_shape: BoxShape3D
var material: StandardMaterial3D
var original_color: Color

var path_controller: PathController
var collision_avoidance: CollisionAvoidance

var current_volume: Dictionary = {}
var current_cell_x: int = 0
var current_cell_y: int = 0
var current_width_cells: int = 3
var current_height_cells: int = 10

var world_node: Node3D
var city = null
var area_instantiator = null
var rng: RandomNumberGenerator

var car_id: String = ""
var debug_label: Label3D

func _ready() -> void:
	car_id = _generate_car_id()
	
	collision_shape = BoxShape3D.new()
	collision_shape.size = Vector3(width, height, depth)
	
	_create_visual()
	_create_detection_area()
	_create_broadcast_area()
	
	if show_debug_label:
		_create_debug_label()
	
	path_controller = PathController.new()
	path_controller.initialize(self, world_node)
	path_controller.show_debug = show_path_debug
	path_controller.debug_color = path_debug_color
	path_controller.debug_width = path_debug_width
	path_controller.debug_segments = path_debug_segments
	path_controller.segment_transition_completed.connect(_on_segment_transition)
	path_controller.path_ended.connect(_on_path_ended)
	add_child(path_controller)
	
	collision_avoidance = CollisionAvoidance.new()
	collision_avoidance.initialize(self, path_controller, world_node, collision_shape, detection_area, broadcast_area)
	collision_avoidance.enabled = enable_collision_avoidance
	collision_avoidance.ghost_distance_multiplier = ghost_distance_multiplier
	collision_avoidance.ghost_spacing = ghost_spacing
	collision_avoidance.broadcast_distance_multiplier = broadcast_distance_multiplier
	collision_avoidance.broadcast_spacing = broadcast_spacing
	collision_avoidance.collision_buffer_zone = collision_buffer_zone
	collision_avoidance.min_safe_distance = min_safe_distance
	collision_avoidance.show_ghost_debug = show_ghost_debug
	collision_avoidance.ghost_debug_color = ghost_debug_color
	collision_avoidance.ghost_collision_color = ghost_collision_color
	collision_avoidance.show_broadcast_debug = show_broadcast_debug
	collision_avoidance.broadcast_debug_color = broadcast_debug_color
	collision_avoidance.timeout_enabled = timeout_enabled
	collision_avoidance.timeout_duration = timeout_duration
	add_child(collision_avoidance)
	
	rng = RandomNumberGenerator.new()
	rng.seed = seed

func _process(delta: float) -> void:
	var effective_delta = delta
	
	if DebugController.is_paused:
		effective_delta = DebugController.manual_delta
		DebugController.manual_delta = 0.0
		
		if effective_delta == 0.0:
			return
	
	var should_move = collision_avoidance.check_and_adjust_speed()
	
	if should_move:
		path_controller.advance(effective_delta, collision_avoidance.get_current_speed())
	
	var transform = path_controller.get_current_transform()
	global_position = transform.origin
	global_rotation = transform.basis.get_euler()
	
	if show_debug_label and debug_label:
		_update_debug_label()

func _exit_tree() -> void:
	if debug_label and is_instance_valid(debug_label):
		debug_label.queue_free()
	path_controller.cleanup()
	collision_avoidance.cleanup()

func _generate_car_id() -> String:
	return "Car_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)

func _create_debug_label() -> void:
	debug_label = Label3D.new()
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.no_depth_test = true
	debug_label.position = debug_label_offset
	debug_label.pixel_size = 0.005
	debug_label.font_size = 32
	debug_label.outline_size = 4
	debug_label.modulate = Color.WHITE
	add_child(debug_label)

func _update_debug_label() -> void:
	if not debug_label:
		return
	
	var blocking_info = collision_avoidance.get_blocking_info()
	
	var archetype_name = CarArchetypes.Type.keys()[car_archetype]
	
	var text = "ID: " + car_id.substr(car_id.length() - 6)
	text += "\nTipo: " + archetype_name
	
	if blocking_info["is_blocked"]:
		text += "\nDETENIDO"
		if blocking_info["blocking_car_id"] != "":
			var short_id = blocking_info["blocking_car_id"].substr(blocking_info["blocking_car_id"].length() - 6)
			if blocking_info["is_broadcast"]:
				text += "\nBroadcast: " + short_id
			else:
				text += "\nAuto: " + short_id
		else:
			text += "\nObstáculo"
	else:
		text += "\nMOVIENDO"
	
	debug_label.text = text

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
	
	if collision_shape:
		collision_shape.size = Vector3(width, height, depth)
	
	if collision_avoidance:
		collision_avoidance.base_speed = speed
		collision_avoidance.current_speed = speed

func set_path(start: Vector3, end: Vector3, initial_progress: float = 0.0, 
			  grid_u: float = 0.0, grid_v: float = 0.0, 
			  volume: Dictionary = {}, width_cells: int = 3, height_cells: int = 10) -> void:
	
	current_volume = volume
	current_cell_x = int(round(grid_u * width_cells))
	current_cell_y = int(round(grid_v * height_cells))
	current_width_cells = width_cells
	current_height_cells = height_cells
	
	var next_segment = _calculate_next_segment(end, volume)
	
	path_controller.create_path(start, end, initial_progress, volume, next_segment)

func _on_segment_transition(old_volume_id: String, new_volume_id: String) -> void:
	if area_instantiator:
		volume_changed.emit(old_volume_id, new_volume_id, car_archetype)
	
	var second_volume = path_controller.second_segment_volume
	current_volume = second_volume
	current_cell_x = second_volume.get("used_cell_x", current_cell_x)
	current_cell_y = second_volume.get("used_cell_y", current_cell_y)
	current_width_cells = second_volume.get("width_cells", current_width_cells)
	current_height_cells = second_volume.get("height_cells", current_height_cells)
	
	var current_end = path_controller.path_3d.curve.get_point_position(3)
	var next_segment = _calculate_next_segment(current_end, current_volume)
	
	path_controller.advance_to_next_segment(next_segment)

func _on_path_ended() -> void:
	queue_free()

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
	detection_area.collision_mask = 2
	detection_area.monitorable = true
	detection_area.monitoring = true
	
	var collision_shape_node = CollisionShape3D.new()
	collision_shape_node.shape = collision_shape
	
	detection_area.add_child(collision_shape_node)
	add_child(detection_area)

func _create_broadcast_area() -> void:
	broadcast_area = Area3D.new()
	broadcast_area.collision_layer = 2
	broadcast_area.collision_mask = 0
	broadcast_area.monitorable = true
	broadcast_area.monitoring = false
	
	add_child(broadcast_area)

func get_intersecting_traffic_planes() -> Array[Area3D]:
	var planes: Array[Area3D] = []
	
	if not detection_area:
		return planes
	
	var overlapping = detection_area.get_overlapping_areas()
	for area in overlapping:
		if area is TrafficPlane:
			planes.append(area)
	
	return planes

func get_relevant_volume_ids() -> Array[String]:
	var ids: Array[String] = []
	
	if not path_controller.first_segment_volume.is_empty():
		ids.append(_get_volume_id(path_controller.first_segment_volume))
	
	if not path_controller.second_segment_volume.is_empty():
		ids.append(_get_volume_id(path_controller.second_segment_volume))
	
	return ids

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

func _calculate_next_segment(current_end: Vector3, volume: Dictionary) -> Dictionary:
	if not city or not volume.has("face_idx") or not volume.has("edge_idx"):
		return {}
	
	var continuations = city.get_lane_volume_continuations(volume["face_idx"], volume["edge_idx"])
	
	if area_instantiator and continuations.is_empty():
		if not _should_continue_path():
			return {}
	
	if continuations.is_empty():
		return {}
	
	var current_direction = Vector3.FORWARD
	if path_controller.path_3d and path_controller.path_3d.curve:
		current_direction = (current_end - path_controller.path_3d.curve.get_point_position(0)).normalized()
	
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

func _should_continue_path() -> bool:
	var car_inside_cylinder = false
	for camera in area_instantiator.cameras:
		if not camera or not is_instance_valid(camera):
			continue
		
		var distance_xz = Vector2(
			global_position.x - camera.global_position.x,
			global_position.z - camera.global_position.z
		).length()
		
		if distance_xz <= area_instantiator.outer_radius:
			car_inside_cylinder = true
			break
	
	var car_visible = false
	if take_frustum_into_account_when_despawning:
		for camera in area_instantiator.cameras:
			if not camera or not is_instance_valid(camera):
				continue
			
			if camera.is_position_in_frustum(global_position):
				car_visible = true
				break
	
	return car_inside_cylinder or car_visible

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
	
	for attempt in range(5):
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
		
		var moved = _move_away_from_plane(
			validation["collision_plane"],
			current_cell_x, current_cell_y,
			cont_width_cells, cont_height_cells
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
		"bottom": new_y = current_y + 1
		"top": new_y = current_y - 1
		"left": new_x = current_x + 1
		"right": new_x = current_x - 1
	
	if new_x < 0 or new_x > max_width or new_y < 0 or new_y > max_height:
		return {}
	
	return {"cell_x": new_x, "cell_y": new_y}

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

func _get_volume_id(volume: Dictionary) -> String:
	if volume.has("face_idx") and volume.has("edge_idx"):
		return str(volume["face_idx"]) + "_" + str(volume["edge_idx"])
	return ""
