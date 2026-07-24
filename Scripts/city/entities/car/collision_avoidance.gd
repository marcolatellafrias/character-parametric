# CollisionAvoidance.gd — one continuous speed governor over the immutable path.
#
# There is a SINGLE rule and nothing else:
#
#   Every car continuously broadcasts a ray ahead of itself along the route it
#   will drive, whose length is simply SPEED × a look-ahead time — long when
#   fast, nothing when stopped. Every car reads the rays and bodies of others,
#   takes the nearest one crossing its own path ahead, and sets its speed so it
#   can always ease to a halt just short of it. That is the whole system.
#
# No claims, no priority, no id tie-breaks, no "stop before the box", no hard
# travel clamp, no inviolable walls, no unstuck hatch — none of the discrete
# "this car is BLOCKED by that car" machinery. Slowing is a smooth function of
# how far the nearest thing ahead is, recomputed every frame, so a stopped car
# is merely a car whose target speed is momentarily zero: the instant the space
# ahead opens it moves again. A permanent deadlock has nothing to latch onto.
#
# Crossings resolve themselves. As two cars near an intersection their rays
# reach across it and both slow; whichever is faster keeps the longer ray while
# the other yields — and because a slowing car's ray SHRINKS (it is speed×time),
# yielding frees the faster car, which speeds up, extends its ray and holds the
# yielder back. The asymmetry feeds itself. The one unresolved case is a
# perfectly symmetric arrival, which may briefly CLIP rather than deadlock — the
# deliberate trade: a transient overlap, never a permanent stall.
extends RefCounted
class_name CollisionAvoidance

enum State { CRUISING, FOLLOWING, BRAKING, YIELDING, STOPPED }

const STOPPED_EPSILON: float = 0.1
const CROSSING_MARGIN: float = 1.0       # ignore a light plane we already straddle
# Near a full stop the sqrt braking curve is vertical, so a hair of residual gap
# would command a hair of speed and the car hunts (creep-stop-creep). Within this
# gap of the stop point, command 0 outright for a clean halt.
const STOP_DEADBAND: float = 0.5

var enabled: bool = true
var ghost_spacing: float = 3.0
# The one length knob. A car LOOKS speed × LOOKAHEAD_TIME ahead, and its
# broadcast ray reaches the same distance — long when fast, ~nothing when
# stopped: a continuous, natural ray, not a claim. The look corridor is floored
# (MIN_LOOKAHEAD) so even a slow car sees the light/leader right in front; the
# broadcast ray is NOT floored, so a stopped car declares no forward intention
# and never suppresses a car crossing ahead of it.
const LOOKAHEAD_TIME: float = 3.0     # seconds of travel looked/broadcast ahead
const MIN_LOOKAHEAD: float = 12.0     # floor for the LOOK corridor (metres)
const MAX_LOOKAHEAD: float = 60.0     # ceiling in metres
var min_safe_distance: float = 5.0    # gap kept short of the nearest thing ahead
var comfortable_deceleration: float = 10.0
var max_deceleration: float = 15.0
var max_acceleration: float = 8.0

var base_speed: float = 10.0
var current_speed: float = 10.0
var target_speed: float = 10.0
var state: int = State.CRUISING
var car_radius: float = 1.0

# Current constraint (debug + drawer)
var blocking_car_id: String = ""
var is_blocked_by_broadcast: bool = false
var blocking_car_ref: WeakRef = null
var stop_gap: float = INF
var hit_point: Vector3 = Vector3.ZERO
var has_hit_point: bool = false

# Corridor cache: world-space polyline starting at the car's nose.
var corridor_points: PackedVector3Array = PackedVector3Array()
var corridor_arcs: PackedFloat32Array = PackedFloat32Array()
var broadcast_length: float = 0.0    # the ray I publish ahead = speed × look-ahead
var _broadcast_buffer: PackedVector3Array = PackedVector3Array()

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
	car_radius = Vector2(owner_car.width, owner_car.height).length() * 0.5 + FlyingCar.SIDE_PADDING

# ============================================================================
# CORRIDOR + BROADCAST
# ============================================================================

func rebuild_corridor() -> void:
	corridor_points.clear()
	corridor_arcs.clear()

	var curve_length := path_controller.get_curve_length()
	if curve_length <= 0.0:
		broadcast_length = 0.0
		return

	var nose: float = path_controller.get_progress() + car_owner.depth * 0.5
	# LOOK corridor: how far I sample ahead for obstacles. Floored so a slow car
	# still sees the leader/light right in front and can stop cleanly.
	var detect_len := clampf(current_speed * LOOKAHEAD_TIME, MIN_LOOKAHEAD, MAX_LOOKAHEAD)
	var end_arc := minf(detect_len, curve_length - nose)
	if end_arc <= ghost_spacing * 0.5:
		broadcast_length = 0.0
		return

	var d := 0.0
	while d < end_arc:
		corridor_points.append(path_controller.sample_profiled(nose + d))
		corridor_arcs.append(d)
		d += ghost_spacing
	corridor_points.append(path_controller.sample_profiled(nose + end_arc))
	corridor_arcs.append(end_arc)

	# The BROADCAST ray is pure speed × time — NOT floored, NOT capped at whatever
	# is ahead. It is just "how far I will travel in the next few seconds": long
	# at speed, zero when stopped. That, and only that, is what other cars read.
	broadcast_length = minf(current_speed * LOOKAHEAD_TIME, end_arc)

## The car's broadcast ray: the front slice of the LOOK corridor, out to
## `broadcast_length` (= speed × look-ahead). Empty when stopped — a halted car
## declares no forward intention, so it never holds back a car crossing ahead.
func get_broadcast_points() -> PackedVector3Array:
	_broadcast_buffer.clear()
	if broadcast_length <= 0.0 or corridor_points.size() < 2:
		return _broadcast_buffer
	_broadcast_buffer.append(corridor_points[0])
	for i in range(1, corridor_points.size()):
		if corridor_arcs[i] >= broadcast_length:
			var seg_len := corridor_arcs[i] - corridor_arcs[i - 1]
			var t := (broadcast_length - corridor_arcs[i - 1]) / seg_len if seg_len > 0.0 else 0.0
			_broadcast_buffer.append(corridor_points[i - 1].lerp(corridor_points[i], t))
			return _broadcast_buffer
		_broadcast_buffer.append(corridor_points[i])
	return _broadcast_buffer

# ============================================================================
# DECISION (staggered, expensive step)
# ============================================================================

func update_target() -> void:
	has_hit_point = false
	stop_gap = INF
	blocking_car_id = ""
	is_blocked_by_broadcast = false
	blocking_car_ref = null
	car_owner.is_blocked_by_traffic_plane = false

	if not enabled or registry == null or corridor_points.size() < 2:
		target_speed = base_speed
		state = State.CRUISING
		return

	var relevant_ids := car_owner.get_relevant_volume_ids()
	var my_pos := corridor_points[0]
	var my_forward := (corridor_points[1] - corridor_points[0]).normalized()

	# Find the nearest thing crossing my path ahead — another car (its body or its
	# ray) or a red light. Just a distance `gap`. No priority, no claims, no
	# same-lane/crossing distinction: anything ahead on my path that isn't my own
	# follower is something I ease to a stop behind.
	var gap := INF
	var b_car: FlyingCar = null
	var b_light := false
	var b_broadcast := false
	var b_point := Vector3.ZERO

	for hit in registry.query_corridor(corridor_points, corridor_arcs, car_radius, car_owner):
		var claim: TrafficClaimRegistry.Claim = hit["claim"]
		var arc: float = hit["my_arc"]
		if arc >= gap:
			continue  # already have something nearer

		var this_car: FlyingCar = null
		var this_light := false
		var this_broadcast := false

		match claim.type:
			TrafficClaimRegistry.ClaimType.TRAFFIC_LIGHT:
				if claim.plane_node == null or not is_instance_valid(claim.plane_node):
					continue
				if not claim.plane_node.is_blocking:
					continue
				if not (claim.lane_id in relevant_ids):
					continue
				if arc < CROSSING_MARGIN:
					continue  # already straddling the plane
				this_light = true
			TrafficClaimRegistry.ClaimType.CAR_BODY, TrafficClaimRegistry.ClaimType.CAR_BROADCAST:
				if not is_instance_valid(claim.owner_car):
					continue
				this_car = claim.owner_car as FlyingCar
				if this_car == null:
					continue
				# The only filter: ignore anything owned by a car BEHIND my nose.
				# That is my follower, not an obstacle ahead — its body/ray
				# spilling forward past me must not slow me down. Pure geometry,
				# not a priority vote.
				if (this_car.global_position - my_pos).dot(my_forward) < 0.0:
					continue
				this_broadcast = (claim.type == TrafficClaimRegistry.ClaimType.CAR_BROADCAST)
			_:
				pass  # generic obstacle

		gap = arc
		b_car = this_car
		b_light = this_light
		b_broadcast = this_broadcast
		b_point = hit["point"]

	if b_light:
		car_owner.is_blocked_by_traffic_plane = true

	if gap == INF:
		target_speed = base_speed
		state = State.CRUISING
		return

	# KEEP THE BOX CLEAR. Never come to rest inside a junction. If braking for
	# whatever is ahead would leave my body stopped in the next intersection box,
	# hold before the box instead — so cross traffic is never walled by a car
	# parked in the crossing (the gridlock that manufactures stuck rings). This
	# only bites when the thing ahead is PAST the box AND I could not fully clear
	# it; if I can sail through, or the obstacle is before the box, nothing
	# changes. Pure geometry off the route — no priority, no claims.
	var nose_arc := path_controller.get_progress() + car_owner.depth * 0.5
	var box := path_controller.next_box()
	if box.x != INF:
		var entrance_gap := box.x - nose_arc
		var rest_tail := nose_arc + gap - min_safe_distance - car_owner.depth
		if entrance_gap >= 0.0 and entrance_gap < gap and rest_tail < box.y:
			gap = entrance_gap
			b_car = null
			b_broadcast = false
			b_point = path_controller.sample_profiled(nose_arc + gap)

	blocking_car_id = b_car.car_id if b_car else ""
	is_blocked_by_broadcast = b_broadcast
	blocking_car_ref = weakref(b_car) if b_car else null
	stop_gap = gap
	hit_point = b_point
	has_hit_point = true

	# The one continuous law: pick the speed from which I can still ease to a halt
	# `min_safe_distance` short of the nearest thing ahead. Far → full speed;
	# closing in → smoothly less; at the margin → 0. Recomputed every frame, so
	# the moment `gap` grows (the thing ahead moved, or its ray shrank as it
	# slowed) the target rises again and the car resumes on its own — no clamp,
	# no lock, nothing to stay stuck on.
	var free := gap - min_safe_distance
	if free <= STOP_DEADBAND:
		target_speed = 0.0
	else:
		target_speed = minf(base_speed, sqrt(2.0 * comfortable_deceleration * free))

	if target_speed >= base_speed * 0.999:
		state = State.CRUISING
	elif target_speed <= STOPPED_EPSILON:
		state = State.BRAKING
	else:
		state = State.FOLLOWING

# ============================================================================
# MOTION (every frame, cheap)
# ============================================================================

func integrate_speed(delta: float) -> bool:
	var diff := target_speed - current_speed
	var max_change := (max_acceleration if diff > 0.0 else max_deceleration) * delta
	current_speed = maxf(current_speed + clampf(diff, -max_change, max_change), 0.0)
	if current_speed <= STOPPED_EPSILON and target_speed <= STOPPED_EPSILON:
		current_speed = 0.0
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

func cleanup() -> void:
	blocking_car_ref = null
