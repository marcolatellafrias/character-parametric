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

@export_group("Collision Avoidance")
@export var enable_collision_avoidance: bool = true
@export var ghost_distance_multiplier: float = 2.0
@export var ghost_spacing: float = 3.0
@export var broadcast_distance_multiplier: float = 2.0
@export var min_safe_distance: float = 5.0
@export var comfortable_deceleration: float = 10.0
@export var max_deceleration: float = 15.0
@export var max_acceleration: float = 8.0
@export var timeout_enabled: bool = true
@export var timeout_duration: float = 3.0

var is_blocked_by_traffic_plane: bool = false

var mesh_instance: MeshInstance3D
var material: StandardMaterial3D
var original_color: Color

var path_controller: PathController
var collision_avoidance: CollisionAvoidance
var claim_registry: TrafficClaimRegistry = null

var current_volume: Dictionary = {}
var current_cell_x: int = 0
var current_cell_y: int = 0
var current_width_cells: int = 3
var current_height_cells: int = 10

var world_node: Node3D
var generator: GraphCityGenerator = null
var area_instantiator = null
var rng: RandomNumberGenerator

var car_id: String = ""
var _ca_frame: int = 0
var _ca_accum: float = 0.0
var _body_claims: Array = []
var _broadcast_claims: Array = []

func _ready() -> void:
	car_id = _generate_car_id()

	_create_visual()

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
	collision_avoidance.initialize(self, path_controller, claim_registry)
	collision_avoidance.enabled = enable_collision_avoidance
	collision_avoidance.ghost_distance_multiplier = ghost_distance_multiplier
	collision_avoidance.ghost_spacing = ghost_spacing
	collision_avoidance.broadcast_distance_multiplier = broadcast_distance_multiplier
	collision_avoidance.min_safe_distance = min_safe_distance
	collision_avoidance.comfortable_deceleration = comfortable_deceleration
	collision_avoidance.max_deceleration = max_deceleration
	collision_avoidance.max_acceleration = max_acceleration
	collision_avoidance.timeout_enabled = timeout_enabled
	collision_avoidance.timeout_duration = timeout_duration
	add_child(collision_avoidance)

	rng = RandomNumberGenerator.new()
	rng.seed = seed

	if claim_registry:
		claim_registry.register_car(self)
		_body_claims = claim_registry.create_claim_pair(TrafficClaimRegistry.ClaimType.CAR_BODY, self)
		_broadcast_claims = claim_registry.create_claim_pair(TrafficClaimRegistry.ClaimType.CAR_BROADCAST, self)

func _process(delta: float) -> void:
	var effective_delta = delta

	if DebugController.is_paused:
		effective_delta = DebugController.frame_delta
		if effective_delta == 0.0:
			return

	var dist: float = area_instantiator.get_min_camera_distance_xz(global_position) if area_instantiator else 0.0

	if dist > WorldSettings.spawn_radius:
		queue_free()
		return

	_ca_accum += effective_delta
	if dist >= WorldSettings.render_distance:
		# Fully fogged — no avoidance, cruise at base speed
		collision_avoidance.set_fogged()
		_ca_accum = 0.0
	else:
		# Decision step every other frame (staggered by instance id);
		# motion smoothing still runs every frame below.
		_ca_frame += 1
		if _ca_frame % 2 == get_instance_id() % 2:
			collision_avoidance.rebuild_corridor()
			collision_avoidance.update_target(_ca_accum)
			_ca_accum = 0.0

	var should_move = collision_avoidance.integrate_speed(effective_delta)
	if should_move:
		path_controller.advance(effective_delta, collision_avoidance.current_speed)

	var transform = path_controller.get_current_transform()
	global_position = transform.origin
	global_rotation = transform.basis.get_euler()

	_publish_claims()

func _publish_claims() -> void:
	if claim_registry == null:
		return
	# Body claim: one segment through the car along its facing axis
	# (symmetric, so the sign of the basis axis does not matter).
	var half: Vector3 = global_transform.basis.z * (depth * 0.5)
	claim_registry.publish_capsule(_body_claims,
		PackedVector3Array([global_position - half, global_position + half]),
		collision_avoidance.car_radius)

	if collision_avoidance.state == CollisionAvoidance.State.FOGGED:
		return
	var broadcast_points = collision_avoidance.get_broadcast_points()
	if broadcast_points.size() >= 2:
		claim_registry.publish_capsule(_broadcast_claims, broadcast_points,
			collision_avoidance.car_radius)

func _exit_tree() -> void:
	if claim_registry:
		claim_registry.unregister_car(self)
	path_controller.cleanup()
	collision_avoidance.cleanup()

func _generate_car_id() -> String:
	return "Car_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)

func get_debug_info() -> String:
	var ca = collision_avoidance
	var text = "%s  %s" % [car_id.substr(car_id.length() - 6), CarArchetypes.Type.keys()[car_archetype]]
	text += "\n%s  v %.1f > %.1f" % [CollisionAvoidance.State.keys()[ca.state], ca.current_speed, ca.target_speed]
	if ca.blocking_car_id != "":
		var short_id = ca.blocking_car_id.substr(ca.blocking_car_id.length() - 6)
		text += "\nblocked: %s%s" % [short_id, " (broadcast)" if ca.is_blocked_by_broadcast else ""]
		if ca.stop_gap != INF:
			text += "  gap %.1f" % ca.stop_gap
	elif is_blocked_by_traffic_plane:
		text += "\nred light"
		if ca.stop_gap != INF:
			text += "  gap %.1f" % ca.stop_gap
	return text

func initialize_from_seed(p_seed: int, archetype_weights: Dictionary = {}) -> void:
	seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = seed

	car_archetype = CarArchetypes.select_type_seeded(rng, archetype_weights)

	var archetype = CarArchetypes.get_archetype(car_archetype)

	width = archetype.width
	height = archetype.height
	depth = archetype.depth
	speed = rng.randf_range(archetype.min_speed, archetype.max_speed)
	car_color = archetype.color
	original_color = archetype.color

	if collision_avoidance:
		collision_avoidance.base_speed = speed
		collision_avoidance.current_speed = speed
		collision_avoidance.car_radius = Vector2(width, height).length() * 0.5

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

	# Snap to the path immediately and claim the space, so spawn checks made
	# later in this same tick already see this car.
	var transform = path_controller.get_current_transform()
	global_position = transform.origin
	global_rotation = transform.basis.get_euler()
	_publish_claims()

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
	if original_color == Color():
		original_color = car_color
	mesh_instance.material_override = material

	add_child(mesh_instance)

func get_relevant_volume_ids() -> Array[String]:
	var ids: Array[String] = []

	if not path_controller.first_segment_volume.is_empty():
		ids.append(_get_volume_id(path_controller.first_segment_volume))

	if not path_controller.second_segment_volume.is_empty():
		ids.append(_get_volume_id(path_controller.second_segment_volume))

	return ids

func _calculate_next_segment(current_end: Vector3, volume: Dictionary) -> Dictionary:
	if not generator or not volume.has("face_idx") or not volume.has("edge_idx"):
		return {}

	var continuations = generator.get_lane_volume_continuations(volume["face_idx"], volume["edge_idx"])

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

func _get_validated_continuation_path(lane_vol: LaneVolume, target_cell_x: int, target_cell_y: int) -> Variant:
	var cont_width_cells = lane_vol.width_cells
	var cont_height_cells = lane_vol.height_cells

	var current_cell_x = clampi(target_cell_x, 0, cont_width_cells)
	var current_cell_y = clampi(target_cell_y, 0, cont_height_cells)
	var is_exact = (current_cell_x == target_cell_x and current_cell_y == target_cell_y)

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
		"top":    new_y = current_y - 1
		"left":   new_x = current_x + 1
		"right":  new_x = current_x - 1

	if new_x < 0 or new_x > max_width or new_y < 0 or new_y > max_height:
		return {}

	return {"cell_x": new_x, "cell_y": new_y}

func _select_continuation_by_angle(continuations: Array) -> Dictionary:
	var total_weight = 0.0
	var weighted_continuations = []

	for cont in continuations:
		var lane_vol = cont["volume"]
		var angle_weight = (PI - cont["angle_diff"]) / PI
		var affinity_weight = _get_neighborhood_affinity(lane_vol)

		var combined_weight = (angle_weight * 0.6) + (affinity_weight * 0.4)
		total_weight += combined_weight
		weighted_continuations.append({"continuation": cont, "weight": combined_weight})

	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0

	for item in weighted_continuations:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return item["continuation"]

	return continuations[0] if not continuations.is_empty() else {}

func _get_neighborhood_affinity(lane_vol: LaneVolume) -> float:
	return CarArchetypes.get_neighborhood_affinity(car_archetype, lane_vol.get_neighborhood_type())

static func compute_cross_section_face(start: Vector3, end: Vector3,
									   p_width: float, p_height: float) -> Array:
	var direction = (end - start).normalized()

	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT

	var right = direction.cross(up).normalized()
	var true_up = right.cross(direction).normalized()

	var half_width = p_width * 0.5
	var half_height = p_height * 0.5

	return [
		-right * half_width - true_up * half_height,
		right * half_width - true_up * half_height,
		right * half_width + true_up * half_height,
		-right * half_width + true_up * half_height
	]

func get_front_face_at_segment(start: Vector3, end: Vector3) -> Array:
	return compute_cross_section_face(start, end, width, height)

func _get_volume_id(volume: Dictionary) -> String:
	if volume.has("face_idx") and volume.has("edge_idx"):
		return str(volume["face_idx"]) + "_" + str(volume["edge_idx"])
	return ""
