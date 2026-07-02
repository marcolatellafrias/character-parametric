# CollisionAvoidance.gd — corridor-based, mathematical avoidance.
# Replaces the per-ghost physics shape queries with one query against the
# TrafficClaimRegistry, and the distance-only speed curve with a leader-aware
# controller: match the leader's speed at a safe gap, or brake analytically
# toward a stop point (red light, stopped car, reserved corridor).
#
# Claims carry their owner, so evaluation is directional: another car's
# broadcast only applies if that car is ahead of us — a follower's broadcast
# spilling past us can no longer stop us. Converging corridors (merges) are
# resolved by time-to-conflict priority instead of mutual braking.
extends Node
class_name CollisionAvoidance

enum State { CRUISING, FOLLOWING, BRAKING, YIELDING, STOPPED, FOGGED }

const STOPPED_EPSILON: float = 0.1
const PRIORITY_TIE_WINDOW: float = 0.3   # seconds; conflicts closer than this are a tie
const IGNORE_DURATION_MS: int = 5000     # deadlock escape: how long to ignore a car
const CROSSING_MARGIN: float = 1.0       # skip lights we are already straddling
const MIN_GHOSTS: float = 3.0
const MAX_GHOSTS: float = 15.0

var enabled: bool = true
var ghost_distance_multiplier: float = 2.0
var ghost_spacing: float = 3.0
var broadcast_distance_multiplier: float = 2.0
var min_safe_distance: float = 5.0
var comfortable_deceleration: float = 10.0
var max_deceleration: float = 15.0
var max_acceleration: float = 8.0
var timeout_enabled: bool = true
var timeout_duration: float = 3.0

var base_speed: float = 10.0
var current_speed: float = 10.0
var target_speed: float = 10.0
var state: int = State.CRUISING
var car_radius: float = 1.0

# Current constraint (debug + light-chain checks)
var blocking_car_id: String = ""
var is_blocked_by_broadcast: bool = false
var blocking_car_ref: WeakRef = null
var stop_gap: float = INF
var hit_point: Vector3 = Vector3.ZERO
var has_hit_point: bool = false

# Corridor cache: world-space polyline starting at the car's nose.
var corridor_points: PackedVector3Array = PackedVector3Array()
var corridor_arcs: PackedFloat32Array = PackedFloat32Array()
var broadcast_length: float = 0.0

# Deadlock timeout bookkeeping
var blocked_time: float = 0.0
var last_blocking_car: String = ""
var ignored_cars: Dictionary = {}   # car_id -> expiry msec

var car_owner: FlyingCar
var path_controller: PathController
var registry: TrafficClaimRegistry

func initialize(owner_car: FlyingCar, path_ctrl: PathController, p_registry: TrafficClaimRegistry) -> void:
	car_owner = owner_car
	path_controller = path_ctrl
	registry = p_registry
	base_speed = owner_car.speed
	current_speed = base_speed
	target_speed = base_speed
	car_radius = Vector2(owner_car.width, owner_car.height).length() * 0.5

# ============================================================================
# CORRIDOR
# ============================================================================

## Sample the car's future path once; both detection and broadcast use it.
func rebuild_corridor() -> void:
	corridor_points = PackedVector3Array()
	corridor_arcs = PackedFloat32Array()
	broadcast_length = 0.0

	var curve_length := path_controller.get_curve_length()
	if curve_length <= 0.0:
		return

	var nose: float = path_controller.get_progress() + car_owner.depth * 0.5
	var detect_len := clampf(base_speed * ghost_distance_multiplier,
							 ghost_spacing * MIN_GHOSTS, ghost_spacing * MAX_GHOSTS)
	var end_arc := minf(detect_len, curve_length - nose)
	if end_arc <= ghost_spacing * 0.5:
		return

	var d := 0.0
	while d < end_arc:
		corridor_points.append(path_controller.sample_baked(nose + d))
		corridor_arcs.append(d)
		d += ghost_spacing
	corridor_points.append(path_controller.sample_baked(nose + end_arc))
	corridor_arcs.append(end_arc)

	broadcast_length = clampf(current_speed * broadcast_distance_multiplier, 0.0, end_arc)

## Slice of the corridor the car "reserves" ahead of itself (its claim).
func get_broadcast_points() -> PackedVector3Array:
	if current_speed <= STOPPED_EPSILON or broadcast_length <= 0.0 or corridor_points.size() < 2:
		return PackedVector3Array()
	var pts := PackedVector3Array()
	pts.append(corridor_points[0])
	for i in range(1, corridor_points.size()):
		if corridor_arcs[i] >= broadcast_length:
			var seg_len := corridor_arcs[i] - corridor_arcs[i - 1]
			var t := (broadcast_length - corridor_arcs[i - 1]) / seg_len if seg_len > 0.0 else 0.0
			pts.append(corridor_points[i - 1].lerp(corridor_points[i], t))
			return pts
		pts.append(corridor_points[i])
	return pts

# ============================================================================
# DECISION (staggered, expensive step)
# ============================================================================

func update_target(delta_accum: float) -> void:
	has_hit_point = false
	stop_gap = INF
	blocking_car_id = ""
	is_blocked_by_broadcast = false
	blocking_car_ref = null
	car_owner.is_blocked_by_traffic_plane = false

	if not enabled or registry == null or corridor_points.size() < 2:
		target_speed = base_speed
		state = State.CRUISING
		blocked_time = 0.0
		last_blocking_car = ""
		return

	var relevant_ids := car_owner.get_relevant_volume_ids()
	var my_pos := corridor_points[0]
	var my_forward := (corridor_points[1] - corridor_points[0]).normalized()
	var now := Time.get_ticks_msec()

	var best_gap := INF
	var best_leader_speed := 0.0
	var best_car: FlyingCar = null
	var best_is_broadcast := false
	var best_is_light := false
	var best_point := Vector3.ZERO

	var hits := registry.query_corridor(corridor_points, corridor_arcs, car_radius, car_owner)
	for hit in hits:
		var claim: TrafficClaimRegistry.Claim = hit["claim"]
		var arc: float = hit["my_arc"]
		var leader_speed := 0.0
		var other: FlyingCar = null
		var is_broadcast := false
		var is_light := false

		match claim.type:
			TrafficClaimRegistry.ClaimType.TRAFFIC_LIGHT:
				if claim.plane_node == null or not is_instance_valid(claim.plane_node):
					continue
				if not claim.plane_node.is_blocking:
					continue
				if not (claim.lane_id in relevant_ids):
					continue
				if arc < CROSSING_MARGIN:
					continue  # already committed/crossing the plane
				car_owner.is_blocked_by_traffic_plane = true
				is_light = true
			TrafficClaimRegistry.ClaimType.CAR_BODY, TrafficClaimRegistry.ClaimType.CAR_BROADCAST:
				if not is_instance_valid(claim.owner_car):
					continue
				other = claim.owner_car as FlyingCar
				if other == null:
					continue
				# Directionality: claims owned by cars behind us never apply.
				if (other.global_position - my_pos).dot(my_forward) < 0.0:
					continue
				if ignored_cars.get(other.car_id, 0) > now:
					continue
				leader_speed = other.collision_avoidance.current_speed
				if claim.type == TrafficClaimRegistry.ClaimType.CAR_BROADCAST:
					# Converging corridors: whoever reaches the conflict point
					# first has priority; ties break deterministically by id.
					var my_time := arc / maxf(current_speed, 1.0)
					var their_time: float = hit["other_arc"] / maxf(leader_speed, 1.0)
					if my_time < their_time - PRIORITY_TIE_WINDOW:
						continue
					if absf(my_time - their_time) <= PRIORITY_TIE_WINDOW and car_owner.car_id < other.car_id:
						continue
					is_broadcast = true
					leader_speed = 0.0  # reserved space: stop before entering it
			_:
				pass  # generic OBSTACLE: hard constraint, leader_speed stays 0

		if arc < best_gap:
			best_gap = arc
			best_leader_speed = leader_speed
			best_car = other
			best_is_broadcast = is_broadcast
			best_is_light = is_light
			best_point = hit["point"]

	_purge_expired_ignores(now)

	if best_gap == INF:
		target_speed = base_speed
		state = State.CRUISING
		blocked_time = 0.0
		last_blocking_car = ""
		return

	blocking_car_id = best_car.car_id if best_car else ""
	is_blocked_by_broadcast = best_is_broadcast
	blocking_car_ref = weakref(best_car) if best_car else null
	stop_gap = best_gap
	hit_point = best_point
	has_hit_point = true

	# Leader-aware target: we may exceed the leader's speed only by what we
	# can shed over the remaining gap at comfortable deceleration. Converges
	# to matching the leader at min_safe_distance; with a stopped leader or a
	# red light it is exactly the analytic braking curve.
	var gap := best_gap - min_safe_distance
	if gap <= 0.0:
		target_speed = clampf(best_leader_speed, 0.0, base_speed)
	else:
		target_speed = minf(base_speed, best_leader_speed + sqrt(2.0 * comfortable_deceleration * gap))

	if target_speed >= base_speed * 0.999:
		state = State.CRUISING
	elif best_is_broadcast:
		state = State.YIELDING
	elif best_is_light or best_leader_speed <= STOPPED_EPSILON:
		state = State.BRAKING
	else:
		state = State.FOLLOWING

	_update_timeout(delta_accum, best_car, best_is_light, best_is_broadcast, now)

## No avoidance beyond the fog: cruise at base speed.
func set_fogged() -> void:
	state = State.FOGGED
	target_speed = base_speed
	current_speed = base_speed
	blocked_time = 0.0
	last_blocking_car = ""
	blocking_car_id = ""
	blocking_car_ref = null
	is_blocked_by_broadcast = false
	has_hit_point = false
	stop_gap = INF
	car_owner.is_blocked_by_traffic_plane = false

# ============================================================================
# MOTION (every frame, cheap)
# ============================================================================

func integrate_speed(delta: float) -> bool:
	var diff := target_speed - current_speed
	var max_change := (max_acceleration if diff > 0.0 else max_deceleration) * delta
	current_speed = maxf(current_speed + clampf(diff, -max_change, max_change), 0.0)
	if current_speed <= STOPPED_EPSILON and target_speed <= STOPPED_EPSILON:
		current_speed = 0.0
		if state != State.FOGGED:
			state = State.STOPPED
	return current_speed > 0.0

func get_current_speed() -> float:
	return current_speed

func get_blocking_info() -> Dictionary:
	return {
		"is_blocked": current_speed == 0.0,
		"blocking_car_id": blocking_car_id,
		"is_broadcast": is_blocked_by_broadcast
	}

# ============================================================================
# DEADLOCK TIMEOUT
# ============================================================================

# Directional evaluation makes same-lane mutual blocks impossible and merges
# resolve by priority, so this only remains for genuine geometric standoffs:
# both cars stopped, neither waiting on a red light.
func _update_timeout(delta_accum: float, best_car: FlyingCar, is_light: bool,
					 is_broadcast: bool, now: int) -> void:
	if not timeout_enabled or best_car == null or is_light or is_broadcast:
		blocked_time = 0.0
		last_blocking_car = ""
		return
	if current_speed > STOPPED_EPSILON:
		blocked_time = 0.0
		last_blocking_car = best_car.car_id
		return
	if best_car.car_id != last_blocking_car:
		last_blocking_car = best_car.car_id
		blocked_time = 0.0
		return
	blocked_time += delta_accum
	if blocked_time < timeout_duration:
		return
	blocked_time = 0.0
	var other_stopped: bool = best_car.collision_avoidance.current_speed <= STOPPED_EPSILON
	if other_stopped and not _is_blocked_by_traffic_light_chain(best_car):
		ignored_cars[best_car.car_id] = now + IGNORE_DURATION_MS

func _is_blocked_by_traffic_light_chain(car_node: FlyingCar, max_depth: int = 20) -> bool:
	var node := car_node
	var depth := 0
	while node != null and depth < max_depth:
		if node.is_blocked_by_traffic_plane:
			return true
		var ref: WeakRef = node.collision_avoidance.blocking_car_ref
		node = ref.get_ref() as FlyingCar if ref else null
		depth += 1
	return false

func _purge_expired_ignores(now: int) -> void:
	if ignored_cars.is_empty():
		return
	for car_id in ignored_cars.keys():
		if ignored_cars[car_id] <= now:
			ignored_cars.erase(car_id)

func cleanup() -> void:
	ignored_cars.clear()
	blocked_time = 0.0
	last_blocking_car = ""
	blocking_car_ref = null
