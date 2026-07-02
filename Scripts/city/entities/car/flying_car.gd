# FlyingCar.gd — a car is a plain simulation object, not a scene node.
# CarManager ticks the whole fleet in one loop (no per-node _process) and
# attaches a pooled MeshInstance3D visual only while the car is inside the fog
# wall. A fully fogged car is pure data — curve progress, speed, claims — with
# no node, no mesh and no transform propagation.
extends Object
class_name FlyingCar

signal volume_changed(old_volume_id: String, new_volume_id: String)
signal despawned

var width: float = 2.0
var height: float = 1.0
var depth: float = 4.0
var car_color: Color = Color(1.0, 0.0, 0.0, 1.0)
var speed: float = 10.0
var spawn_time: float = 0.0
var seed: int = 0
var car_archetype: CarArchetypes.Type = CarArchetypes.Type.POOR_CAR

# Path debug
var show_path_debug: bool = false
var path_debug_color: Color = Color(1.0, 1.0, 0.0, 1.0)
var path_debug_width: float = 0.05
var path_debug_segments: int = 30

# Collision avoidance config
var enable_collision_avoidance: bool = true
var ghost_distance_multiplier: float = 2.0
var ghost_spacing: float = 3.0
var broadcast_distance_multiplier: float = 2.0
var min_safe_distance: float = 5.0
var comfortable_deceleration: float = 10.0
var max_deceleration: float = 15.0
var max_acceleration: float = 8.0
var timeout_enabled: bool = true
var timeout_duration: float = 3.0

# Dodge/overtake config (see CollisionAvoidance DODGE section)
var enable_dodge: bool = true
var overtake_speed_ratio: float = 0.75
var overtake_patience: float = 1.2
var dodge_clearance: float = 1.5
var dodge_ramp_time: float = 1.0

# Fogged cars tick at this fraction of the frame rate; motion is analytic so
# batching the accumulated delta is exact, not an approximation.
const FOG_TICK_INTERVAL: int = 4
# Avoidance decision cadence (frames) scaled by camera distance: braking
# latency is invisible at fog range, so far cars decide less often.
const DECISION_INTERVAL_NEAR: int = 2
const DECISION_INTERVAL_MID: int = 4
const DECISION_INTERVAL_FAR: int = 8

var is_blocked_by_traffic_plane: bool = false

# World-space pose, sampled from the path. Exposed under the Node3D property
# names it replaces so readers (avoidance, debug drawer) are unchanged.
var sim_transform: Transform3D = Transform3D.IDENTITY
var global_transform: Transform3D:
	get: return sim_transform
	set(value): sim_transform = value
var global_position: Vector3:
	get: return sim_transform.origin

## Pooled visual, owned and attached/detached by CarManager. Null while fogged.
var visual: MeshInstance3D = null
## Set by path end; CarManager frees the car after the tick.
var pending_despawn: bool = false

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
var _stagger: int = 0
var _move_accum: float = 0.0
var _ca_accum: float = 0.0
var _is_fogged: bool = false
var _body_claims: Array = []
var _broadcast_claims: Array = []
var _body_points: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _relevant_volume_ids: Array[String] = []
var _tint_material: StandardMaterial3D = null

# All cars of an archetype share one mesh+material (keyed by size and color),
# so the renderer sees a handful of resources instead of one per car.
static var _shared_meshes: Dictionary = {}

## Called once by the spawner after configuration (replaces Node._ready).
func setup() -> void:
	car_id = _generate_car_id()
	_stagger = int(get_instance_id() % 4096)

	path_controller = PathController.new()
	path_controller.initialize(self, world_node)
	path_controller.show_debug = show_path_debug
	path_controller.debug_color = path_debug_color
	path_controller.debug_width = path_debug_width
	path_controller.debug_segments = path_debug_segments
	path_controller.segment_transition_completed.connect(_on_segment_transition)
	path_controller.path_ended.connect(_on_path_ended)

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
	collision_avoidance.enable_dodge = enable_dodge
	collision_avoidance.overtake_speed_ratio = overtake_speed_ratio
	collision_avoidance.overtake_patience = overtake_patience
	collision_avoidance.dodge_clearance = dodge_clearance
	collision_avoidance.dodge_ramp_time = dodge_ramp_time

	rng = RandomNumberGenerator.new()
	rng.seed = seed

	if claim_registry:
		claim_registry.register_car(self)
		_body_claims = claim_registry.create_claim_pair(TrafficClaimRegistry.ClaimType.CAR_BODY, self)
		_broadcast_claims = claim_registry.create_claim_pair(TrafficClaimRegistry.ClaimType.CAR_BROADCAST, self)

## True when this fully fogged car batches this frame's work into a later tick.
func is_fog_skip_frame(frame: int) -> bool:
	return _is_fogged and (frame + _stagger) % FOG_TICK_INTERVAL != 0

## Skipped fogged frame: accumulate time and republish the body claim from the
## last transform, because the registry's double buffer clears every frame.
func tick_skipped(delta: float) -> void:
	_move_accum += delta
	_publish_claims()

## Full simulation step; `dist` is the XZ distance to the nearest camera.
func tick(delta: float, dist: float, frame: int) -> void:
	_move_accum += delta
	var move_delta := _move_accum
	_move_accum = 0.0

	_is_fogged = dist >= WorldSettings.render_distance

	_ca_accum += move_delta
	if _is_fogged:
		# Fully fogged — no avoidance, cruise at base speed
		collision_avoidance.set_fogged()
		_ca_accum = 0.0
	else:
		# Decision step at a distance-scaled cadence (staggered by instance
		# id); motion smoothing still runs every frame below.
		var interval := DECISION_INTERVAL_NEAR
		if dist >= WorldSettings.fog_start_distance:
			var mid: float = (WorldSettings.fog_start_distance + WorldSettings.render_distance) * 0.5
			interval = DECISION_INTERVAL_MID if dist < mid else DECISION_INTERVAL_FAR
		if (frame + _stagger) % interval == 0:
			collision_avoidance.rebuild_corridor()
			collision_avoidance.update_target(_ca_accum)
			_ca_accum = 0.0

	var should_move = collision_avoidance.integrate_speed(move_delta)
	if should_move:
		path_controller.advance(move_delta, collision_avoidance.current_speed)

	sim_transform = path_controller.get_current_transform()

	_publish_claims()

func _publish_claims() -> void:
	if claim_registry == null:
		return
	# Body claim: one segment through the car along its facing axis
	# (symmetric, so the sign of the basis axis does not matter).
	var half: Vector3 = sim_transform.basis.z * (depth * 0.5)
	_body_points[0] = sim_transform.origin - half
	_body_points[1] = sim_transform.origin + half
	claim_registry.publish_capsule(_body_claims, _body_points,
		collision_avoidance.car_radius)

	if collision_avoidance.state == CollisionAvoidance.State.FOGGED:
		return
	var broadcast_points = collision_avoidance.get_broadcast_points()
	if broadcast_points.size() >= 2:
		claim_registry.publish_capsule(_broadcast_claims, broadcast_points,
			collision_avoidance.car_radius)

## Tear-down before free() (replaces Node._exit_tree). Emits `despawned` while
## the object is still alive so listeners can read its fields.
func dispose() -> void:
	despawned.emit()
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
	if path_controller.dodge_active:
		var reason = CollisionAvoidance.DodgeReason.keys()[ca.dodge_reason]
		var phase = "merging" if path_controller.dodge_merge_arc != INF else "holding"
		text += "\ndodge %s %s  off %.1f" % [reason, phase, path_controller.dodge_magnitude]
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
	_update_relevant_volume_ids()

	# Snap to the path immediately and claim the space, so spawn checks made
	# later in this same tick already see this car.
	sim_transform = path_controller.get_current_transform()
	_publish_claims()

func _on_segment_transition(old_volume_id: String, new_volume_id: String) -> void:
	if area_instantiator:
		volume_changed.emit(old_volume_id, new_volume_id)

	var second_volume = path_controller.second_segment_volume
	current_volume = second_volume
	current_cell_x = second_volume.get("used_cell_x", current_cell_x)
	current_cell_y = second_volume.get("used_cell_y", current_cell_y)
	current_width_cells = second_volume.get("width_cells", current_width_cells)
	current_height_cells = second_volume.get("height_cells", current_height_cells)

	var current_end = path_controller.curve.get_point_position(3)
	var next_segment = _calculate_next_segment(current_end, current_volume)
	path_controller.advance_to_next_segment(next_segment)
	_update_relevant_volume_ids()

func _on_path_ended() -> void:
	pending_despawn = true

# ============================================================================
# VISUAL (pooled MeshInstance3D, managed by CarManager)
# ============================================================================

## The archetype's shared mesh, assigned by CarManager when a visual attaches.
func get_shared_mesh() -> BoxMesh:
	return _get_shared_box_mesh(width, height, depth, car_color)

## Hand the pooled visual back to the manager, stripping per-car state.
func detach_visual() -> MeshInstance3D:
	var mi := visual
	visual = null
	_tint_material = null
	if mi:
		mi.material_override = null
		mi.visible = false
	return mi

static func _get_shared_box_mesh(w: float, h: float, d: float, color: Color) -> BoxMesh:
	var key := "%.2f_%.2f_%.2f_%s" % [w, h, d, color.to_html()]
	var box: BoxMesh = _shared_meshes.get(key)
	if box == null:
		box = BoxMesh.new()
		box.size = Vector3(w, h, d)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		box.material = mat
		_shared_meshes[key] = box
	return box

## Debug-only per-car tint: lazily overrides the shared material so tinting
## one car never recolors its whole archetype. No-op while the car has no
## visual (fogged) — the drawer re-tints every frame anyway.
func set_debug_tint(color: Color) -> void:
	if visual == null:
		return
	if _tint_material == null:
		_tint_material = StandardMaterial3D.new()
		visual.material_override = _tint_material
	_tint_material.albedo_color = color

func clear_debug_tint() -> void:
	if _tint_material == null:
		return
	_tint_material = null
	if visual and is_instance_valid(visual):
		visual.material_override = null

## Cached: only changes on set_path / segment transitions, and the avoidance
## decision step reads it every tick.
func get_relevant_volume_ids() -> Array[String]:
	return _relevant_volume_ids

func _update_relevant_volume_ids() -> void:
	_relevant_volume_ids.clear()

	if not path_controller.first_segment_volume.is_empty():
		_relevant_volume_ids.append(_get_volume_id(path_controller.first_segment_volume))

	if not path_controller.second_segment_volume.is_empty():
		_relevant_volume_ids.append(_get_volume_id(path_controller.second_segment_volume))

# Continuations are weighted by their street's traffic density (the same
# constant the spawner uses for targets, so routing and spawning push toward
# the same distribution). The seeded draw itself provides the variation into
# less dense routes. U-turns are structurally excluded by the graph query.
#
# The draw happens BEFORE validation: only the selected volume is validated
# (falling back to the next draw if it fails), instead of paying the
# projection checks for every candidate and then discarding all but one.
func _calculate_next_segment(_current_end: Vector3, volume: Dictionary) -> Dictionary:
	if not generator or not volume.has("face_idx") or not volume.has("edge_idx"):
		return {}

	var remaining: Array = generator.get_lane_volume_continuations(volume["face_idx"], volume["edge_idx"]).duplicate()

	while not remaining.is_empty():
		var idx = _draw_weighted_index(remaining)
		var lane_vol: LaneVolume = remaining[idx]
		var result = _get_validated_continuation_path(lane_vol, current_cell_x, current_cell_y)

		if result != null and result.has("start") and result.has("end"):
			return {
				"path": result,
				"volume_data": {
					"face_idx": lane_vol.face_idx,
					"edge_idx": lane_vol.edge_idx,
					"used_cell_x": result["used_cell_x"],
					"used_cell_y": result["used_cell_y"],
					"width_cells": lane_vol.width_cells,
					"height_cells": lane_vol.height_cells
				}
			}

		remaining.remove_at(idx)

	return {}

func _draw_weighted_index(lane_vols: Array) -> int:
	var total_weight = 0.0
	for lane_vol in lane_vols:
		total_weight += maxf(lane_vol.get_traffic_density(), 0.01)

	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0

	for i in range(lane_vols.size()):
		cumulative_weight += maxf(lane_vols[i].get_traffic_density(), 0.01)
		if random_value <= cumulative_weight:
			return i

	return lane_vols.size() - 1

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
