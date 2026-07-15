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
var ghost_spacing: float = 3.0
var min_safe_distance: float = 5.0
# Extra lateral half-padding, applied ONLY to the sides (it inflates the claim
# capsule's radius — perpendicular to travel — never its length, so the
# speed-dependent front/back gap is untouched). The SAME amount is reserved in
# path validation (below), so across a two-way boundary the fatter claim and
# the extra reserved clearance cancel: opposing lanes are unaffected, while
# same-lane cars gain a side gap and won't drive abreast.
const SIDE_PADDING: float = 0.6
var comfortable_deceleration: float = 10.0
var max_deceleration: float = 15.0
var max_acceleration: float = 8.0

# Vertical clearance the bridge profile keeps between the car and a slab
# (BridgePlanner reads it).
var dodge_clearance: float = 1.5

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
# Spawn pose, kept for the stuck-diagnostics report (StuckReporter).
var spawn_position: Vector3 = Vector3.ZERO
var spawn_heading: Vector3 = Vector3.FORWARD
var _move_accum: float = 0.0
var _body_claims: Array = []
var _broadcast_claims: Array = []
var _body_points: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _tint_material: StandardMaterial3D = null

# All cars of an archetype share one mesh+material (keyed by size and color),
# so the renderer sees a handful of resources instead of one per car.
static var _shared_meshes: Dictionary = {}

## Called once by the spawner after configuration (replaces Node._ready).
func setup() -> void:
	car_id = _generate_car_id()

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
	collision_avoidance.ghost_spacing = ghost_spacing
	collision_avoidance.min_safe_distance = min_safe_distance
	collision_avoidance.comfortable_deceleration = comfortable_deceleration
	collision_avoidance.max_deceleration = max_deceleration
	collision_avoidance.max_acceleration = max_acceleration

	rng = RandomNumberGenerator.new()
	rng.seed = seed

	if claim_registry:
		claim_registry.register_car(self)
		_body_claims = claim_registry.create_claim_pair(TrafficClaimRegistry.ClaimType.CAR_BODY, self)
		_broadcast_claims = claim_registry.create_claim_pair(TrafficClaimRegistry.ClaimType.CAR_BROADCAST, self)

## Full simulation step; `_dist` (XZ distance to the nearest camera) is no
## `_dist` (XZ distance to the nearest camera) is only used by CarManager for
## despawning. Every car runs full avoidance every frame — NO fog shortcut.
## (Both fog optimisations were field-tested and removed: blind-cruising fog
## cars clipped at the boundary and ran lights, muddying every diagnosis.
## Correctness first; optimise again once the system is proven.)
func tick(delta: float, _dist: float, _frame: int) -> void:
	_move_accum += delta
	var move_delta := _move_accum
	_move_accum = 0.0

	collision_avoidance.rebuild_corridor()
	collision_avoidance.update_target()

	var should_move = collision_avoidance.integrate_speed(move_delta)
	var step := 0.0
	if should_move:
		step = collision_avoidance.current_speed * move_delta
		if step > 0.0:
			path_controller.advance_distance(step)

	# Slide sideways by the distance just driven (bounded slope), then pose the
	# car — so its published body/ray reflect the new offset this frame.
	collision_avoidance.update_lateral(step)
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
		text += "\nblocked: %s%s" % [short_id, " (claim)" if ca.is_blocked_by_broadcast else ""]
		if ca.stop_gap != INF:
			text += "  gap %.1f" % ca.stop_gap
	elif is_blocked_by_traffic_plane:
		text += "\nred light"
		if ca.stop_gap != INF:
			text += "  gap %.1f" % ca.stop_gap
	if not path_controller.profile.is_empty():
		var alt = path_controller.profile_offset(path_controller.get_progress())
		if absf(alt) > 0.05:
			text += "\nbridge alt %+.1f" % alt
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
		collision_avoidance.car_radius = Vector2(width, height).length() * 0.5 + SIDE_PADDING

func set_path(start: Vector3, end: Vector3, initial_progress: float = 0.0,
			  grid_u: float = 0.0, grid_v: float = 0.0,
			  volume: Dictionary = {}, width_cells: int = 3, height_cells: int = 10) -> void:

	current_volume = volume
	current_cell_x = int(round(grid_u * width_cells))
	current_cell_y = int(round(grid_v * height_cells))
	current_width_cells = width_cells
	current_height_cells = height_cells

	spawn_position = start
	var sh := end - start
	spawn_heading = sh.normalized() if sh.length_squared() > 1e-6 else Vector3.FORWARD

	# Commit the WHOLE route now: a seeded, weighted, no-repeat walk to the
	# city boundary. The path controller freezes it into one immutable curve +
	# Y-profile, so nothing the car flies is ever recomputed (no teleports).
	var first_vol := volume.duplicate()
	first_vol["used_cell_x"] = current_cell_x
	first_vol["used_cell_y"] = current_cell_y
	var route := _build_route(start, end, first_vol)
	path_controller.create_route(route, initial_progress)

	# Snap to the path immediately and claim the space, so spawn checks made
	# later in this same tick already see this car.
	sim_transform = path_controller.get_current_transform()
	_publish_claims()

# Arc crossed into the next street: bookkeeping only (the route never changes).
func _on_segment_transition(old_volume_id: String, new_volume_id: String) -> void:
	if area_instantiator:
		volume_changed.emit(old_volume_id, new_volume_id)
	current_volume = path_controller.current_volume_data()
	current_cell_x = current_volume.get("used_cell_x", current_cell_x)
	current_cell_y = current_volume.get("used_cell_y", current_cell_y)
	current_width_cells = current_volume.get("width_cells", current_width_cells)
	current_height_cells = current_volume.get("height_cells", current_height_cells)

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

func get_relevant_volume_ids() -> Array[String]:
	return path_controller.get_relevant_volume_ids()

# ============================================================================
# ROUTE BUILDING (once, at spawn)
# ============================================================================

const ROUTE_MAX_SEGMENTS: int = 60
# Arterials pull more traffic: continuation weight scales with street type
# (0 = small, 1 = medium, 2 = large) on top of the street's traffic density.
const STREET_TYPE_BIAS: Dictionary = {0: 1.0, 1: 2.5, 2: 6.0}

# Seeded, weighted, no-repeat walk to the city boundary. Returns an ordered
# list of {start, end, volume_data}. Finite by construction — a trail can't
# repeat a street, and a hard cap backstops the rare relaxed-repeat case — and
# it terminates at a boundary node, so the car despawns off-screen at the city
# edge rather than popping mid-view.
func _build_route(spawn_start: Vector3, first_end: Vector3, first_vol: Dictionary) -> Array:
	var route: Array = [{"start": spawn_start, "end": first_end, "volume_data": first_vol}]
	if generator == null:
		return route
	var visited: Dictionary = {}
	visited[_edge_key_of(first_vol)] = true
	var cur := first_vol
	for _i in range(ROUTE_MAX_SEGMENTS):
		if _is_boundary_exit(cur):
			break
		var nxt := _draw_next_volume(cur, visited)
		if nxt.is_empty():
			break
		route.append({"start": nxt["start"], "end": nxt["end"], "volume_data": nxt["volume_data"]})
		visited[nxt["edge_key"]] = true
		cur = nxt["volume_data"]
	return route

# Continuations weighted by traffic density AND street type, excluding streets
# already driven. If every option is used (local dead-end), the no-repeat
# filter is relaxed so the walk keeps heading out — finiteness holds via the
# caller's cap. Validation may shift the target grid cell (falls back to the
# next draw on failure).
func _draw_next_volume(vol: Dictionary, visited: Dictionary) -> Dictionary:
	var all: Array = generator.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"]).duplicate()
	if all.is_empty():
		return {}
	var candidates: Array = []
	for lv in all:
		if not visited.has(_edge_key_of_lane(lv)):
			candidates.append(lv)
	if candidates.is_empty():
		candidates = all
	var tx: int = vol.get("used_cell_x", current_cell_x)
	var ty: int = vol.get("used_cell_y", current_cell_y)
	while not candidates.is_empty():
		var idx := _draw_weighted_index(candidates)
		var lane_vol: LaneVolume = candidates[idx]
		var result = _get_validated_continuation_path(lane_vol, tx, ty)
		if result != null and result.has("start") and result.has("end"):
			return {
				"start": result["start"],
				"end": result["end"],
				"edge_key": _edge_key_of_lane(lane_vol),
				"volume_data": {
					"face_idx": lane_vol.face_idx,
					"edge_idx": lane_vol.edge_idx,
					"used_cell_x": result["used_cell_x"],
					"used_cell_y": result["used_cell_y"],
					"width_cells": lane_vol.width_cells,
					"height_cells": lane_vol.height_cells,
					"street_type": lane_vol.street_type,
				}
			}
		candidates.remove_at(idx)
	return {}

func _draw_weighted_index(lane_vols: Array) -> int:
	var total := 0.0
	for lv in lane_vols:
		total += _route_weight(lv)
	var r := rng.randf() * total
	var acc := 0.0
	for i in range(lane_vols.size()):
		acc += _route_weight(lane_vols[i])
		if r <= acc:
			return i
	return lane_vols.size() - 1

func _route_weight(lv: LaneVolume) -> float:
	return maxf(lv.get_traffic_density(), 0.01) * STREET_TYPE_BIAS.get(lv.street_type, 1.0)

func _edge_key_of(vol: Dictionary) -> String:
	return _edge_key(vol.get("face_idx", -1), vol.get("edge_idx", -1))

func _edge_key_of_lane(lv: LaneVolume) -> String:
	return _edge_key(lv.face_idx, lv.edge_idx)

func _edge_key(face_idx: int, edge_idx: int) -> String:
	if generator == null or face_idx < 0:
		return "%d_%d" % [face_idx, edge_idx]
	var face = generator.plain_graph.faces[face_idx]
	var n1 = face[edge_idx]
	var n2 = face[(edge_idx + 1) % face.size()]
	return GraphGenerator._get_edge_key(n1, n2)

# The car exits a volume at its flow end-node (face[edge_idx]); a boundary node
# there means the route has reached the edge of the city.
func _is_boundary_exit(vol: Dictionary) -> bool:
	if generator == null:
		return true
	var fi: int = vol.get("face_idx", -1)
	var ei: int = vol.get("edge_idx", -1)
	if fi < 0:
		return true
	var face = generator.plain_graph.faces[fi]
	var end_node = face[ei]
	return generator.plain_graph.node_types.get(end_node, 0) == 1

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

# The cross-section used for PATH VALIDATION — widened by the side padding so a
# car only ever commits to lane positions where its full padded claim fits
# within the lane, for the whole route. Height (vertical) is left as-is; the
# padding is lateral only.
func get_front_face_at_segment(start: Vector3, end: Vector3) -> Array:
	return compute_cross_section_face(start, end, width + 2.0 * SIDE_PADDING, height)

func _get_volume_id(volume: Dictionary) -> String:
	if volume.has("face_idx") and volume.has("edge_idx"):
		return str(volume["face_idx"]) + "_" + str(volume["edge_idx"])
	return ""
