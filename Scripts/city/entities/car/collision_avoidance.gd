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
extends RefCounted
class_name CollisionAvoidance

enum State { CRUISING, FOLLOWING, BRAKING, YIELDING, STOPPED, FOGGED, DODGING }
enum DodgeReason { NONE, OBSTACLE, OVERTAKE }

const STOPPED_EPSILON: float = 0.1
const PRIORITY_TIE_WINDOW: float = 0.3   # seconds; conflicts closer than this are a tie
const IGNORE_DURATION_MS: int = 5000     # deadlock escape: how long to ignore a car
const CROSSING_MARGIN: float = 1.0       # skip lights we are already straddling
const MIN_GHOSTS: float = 3.0
const MAX_GHOSTS: float = 15.0

# Dodge tuning (see the DODGE section). Ramps are speed-scaled but clamped so
# slow cars still commit and fast cars don't smear the ease over half a block.
const DODGE_RAMP_MIN: float = 4.0
const DODGE_RAMP_MAX: float = 18.0
const DODGE_PROBE_COOLDOWN: float = 0.5  # seconds between initiation probe rounds
const MERGE_CHECK_INTERVAL: float = 0.3  # seconds between merge-back checks
const MERGE_LEAD: float = 2.0            # merge ramp starts this far past the nose
const DODGE_MAX_HOLD: float = 60.0       # overtake: held arc before drifting back behind
const MIN_OVERTAKE_REL_SPEED: float = 1.0
const OBSTACLE_PROBE_TIERS: Array[float] = [1.0, 1.8, 2.6, 3.4]
const OVERTAKE_PROBE_TIERS: Array[float] = [1.0, 1.6]

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

# Dodge config
var enable_dodge: bool = true
var overtake_speed_ratio: float = 0.75   # leader below this fraction of base speed = worth passing
var overtake_patience: float = 1.2       # seconds stuck behind a slow leader before probing
var dodge_clearance: float = 1.5         # extra gap beyond combined radii while alongside
var dodge_ramp_time: float = 1.0         # seconds of travel per ease ramp

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
var _broadcast_buffer: PackedVector3Array = PackedVector3Array()

# Deadlock timeout bookkeeping
var blocked_time: float = 0.0
var last_blocking_car: String = ""
var ignored_cars: Dictionary = {}   # car_id -> expiry msec

# Dodge bookkeeping. The envelope itself (direction, magnitude, arcs) lives in
# PathController; this is the policy side: why we dodge and when to merge back.
var dodge_reason: int = DodgeReason.NONE
var dodged_car_ref: WeakRef = null
var _follow_slow_time: float = 0.0   # patience accumulator behind a slow leader
var _probe_cooldown: float = 0.0
var _probe_points: PackedVector3Array = PackedVector3Array()
var _probe_arcs: PackedFloat32Array = PackedFloat32Array()

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
## The point/arc buffers are reused across rebuilds to avoid per-tick churn.
func rebuild_corridor() -> void:
	corridor_points.clear()
	corridor_arcs.clear()
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

	# sample_dodged: while a dodge envelope is active the corridor follows the
	# offset path, so detection, broadcasts and other cars' reactions all see
	# the trajectory actually flown.
	var d := 0.0
	while d < end_arc:
		corridor_points.append(path_controller.sample_dodged(nose + d))
		corridor_arcs.append(d)
		d += ghost_spacing
	corridor_points.append(path_controller.sample_dodged(nose + end_arc))
	corridor_arcs.append(end_arc)

	broadcast_length = clampf(current_speed * broadcast_distance_multiplier, 0.0, end_arc)

## Slice of the corridor the car "reserves" ahead of itself (its claim).
## Returns a reused buffer, only valid until the next call.
func get_broadcast_points() -> PackedVector3Array:
	_broadcast_buffer.clear()
	if current_speed <= STOPPED_EPSILON or broadcast_length <= 0.0 or corridor_points.size() < 2:
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
	var best_claim: TrafficClaimRegistry.Claim = null

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
			best_claim = claim

	_purge_expired_ignores(now)

	if best_gap == INF:
		target_speed = base_speed
		state = State.CRUISING
		blocked_time = 0.0
		last_blocking_car = ""
		_update_dodge(delta_accum, INF, null, null, 0.0)
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
	_update_dodge(delta_accum, best_gap, best_claim, best_car, best_leader_speed)

## No avoidance beyond the fog: cruise at base speed. Any dodge is dropped —
## the snap back to the base path happens where nobody can see it.
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
	path_controller.cancel_dodge()
	dodge_reason = DodgeReason.NONE
	dodged_car_ref = null
	_follow_slow_time = 0.0

# ============================================================================
# DODGE (bezier weave around obstacles and slow leaders)
# ============================================================================
# Policy on top of PathController's offset envelope. Two triggers:
#  - OBSTACLE (bridges): the nearest constraint is a static obstacle claim —
#    probe vertical offsets (over/under) and start the weave immediately.
#  - OVERTAKE: stuck behind a leader well below our base speed — probe lateral
#    offsets (then above) after a patience delay.
# The hold phase is open-ended: every MERGE_CHECK_INTERVAL the car tests a
# hypothetical merge-back corridor against the registry and eases back to its
# ideal path as soon as that corridor is clear (condition-based exit — no
# prediction of how long a moving leader needs to be passed).

func _update_dodge(delta_accum: float, best_gap: float, best_claim: TrafficClaimRegistry.Claim,
		best_car: FlyingCar, best_leader_speed: float) -> void:
	if not enable_dodge or registry == null:
		return
	_probe_cooldown = maxf(_probe_cooldown - delta_accum, 0.0)

	if path_controller.dodge_active:
		_follow_slow_time = 0.0
		if state == State.CRUISING:
			state = State.DODGING
		if path_controller.dodge_merge_arc == INF and _probe_cooldown <= 0.0:
			_probe_cooldown = MERGE_CHECK_INTERVAL
			# Held arc derives from the envelope's own arcs, which shift with
			# the progress on segment transitions.
			var hold_start: float = path_controller.dodge_start_arc + path_controller.dodge_ramp_len
			if not _try_merge() and dodge_reason == DodgeReason.OVERTAKE \
					and path_controller.get_progress() - hold_start > DODGE_MAX_HOLD:
				# Couldn't complete the pass: drift back behind the leader at
				# the offset position; the merge check fires once we're clear.
				var leader: FlyingCar = dodged_car_ref.get_ref() if dodged_car_ref else null
				if leader:
					target_speed = minf(target_speed,
						leader.collision_avoidance.current_speed * 0.9)
		return

	if dodge_reason != DodgeReason.NONE:
		dodge_reason = DodgeReason.NONE
		dodged_car_ref = null

	if corridor_points.size() < 2:
		return

	# --- initiation ---
	if best_claim != null and best_claim.type == TrafficClaimRegistry.ClaimType.OBSTACLE:
		_follow_slow_time = 0.0
		if _probe_cooldown <= 0.0:
			_probe_cooldown = DODGE_PROBE_COOLDOWN
			_try_start_obstacle_dodge(best_gap, best_claim)
		return

	var leader_is_slow: bool = best_car != null and not is_blocked_by_broadcast \
		and not car_owner.is_blocked_by_traffic_plane \
		and best_leader_speed < base_speed * overtake_speed_ratio \
		and base_speed - best_leader_speed >= MIN_OVERTAKE_REL_SPEED
	if not leader_is_slow:
		_follow_slow_time = 0.0
		return
	_follow_slow_time += delta_accum
	if _follow_slow_time < overtake_patience or _probe_cooldown > 0.0:
		return
	_probe_cooldown = DODGE_PROBE_COOLDOWN
	_try_start_overtake(best_gap, best_car, best_leader_speed)

# Static obstacle ahead: go over or under it. Magnitude tiers escalate because
# the hit only reveals the nearest capsule of the slab, not its full extent —
# each tier is one registry query, bounded by the lane's headroom.
func _try_start_obstacle_dodge(gap: float, claim: TrafficClaimRegistry.Claim) -> void:
	var progress := path_controller.get_progress()
	var nose := progress + car_owner.depth * 0.5
	var remaining := path_controller.get_curve_length() - nose
	# Finish the ease-out before reaching the obstacle; if the car crept close,
	# accept a steeper ramp rather than not dodging at all.
	var ramp := clampf(minf(_ramp_len(), gap - dodge_clearance), DODGE_RAMP_MIN, DODGE_RAMP_MAX)
	var base_mag := claim.radius + car_radius + dodge_clearance
	var probe_len := minf(remaining, gap + ramp + 15.0)
	if probe_len <= ghost_spacing:
		return
	for dir in _ordered_dirs([Vector3.UP, Vector3.DOWN]):
		var headroom := _boundary_headroom(dir)
		for tier in OBSTACLE_PROBE_TIERS:
			var mag: float = base_mag * tier
			if mag + car_radius > headroom:
				break
			_build_probe(dir, mag, progress, ramp, INF, probe_len)
			if _probe_is_clear():
				path_controller.start_dodge(dir, mag, progress, ramp)
				dodge_reason = DodgeReason.OBSTACLE
				dodged_car_ref = null
				return

# Slow leader ahead: pass it laterally (or above as a fallback). The relative
# speed estimate is only a go/no-go filter — if the pass won't fit in the
# remaining path or would take too long, stay behind. The exit itself is
# condition-based (_try_merge).
func _try_start_overtake(gap: float, leader: FlyingCar, leader_speed: float) -> void:
	var progress := path_controller.get_progress()
	var nose := progress + car_owner.depth * 0.5
	var remaining := path_controller.get_curve_length() - nose
	var rel := base_speed - leader_speed
	var pass_dist: float = base_speed * ((gap + leader.depth + 2.0 * min_safe_distance) / rel)
	if pass_dist > DODGE_MAX_HOLD:
		return
	var ramp := _ramp_len()
	if remaining < pass_dist + 2.0 * ramp + min_safe_distance:
		return
	var forward := (corridor_points[1] - corridor_points[0]).normalized()
	var right := forward.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	var probe_len := minf(remaining, ramp + pass_dist)
	for dir in _ordered_dirs([right, -right, Vector3.UP]):
		var vertical: bool = absf(dir.y) > 0.7
		var extent: float = (leader.height + car_owner.height) * 0.5 if vertical \
			else (leader.width + car_owner.width) * 0.5
		var base_mag: float = extent + dodge_clearance
		var headroom := _boundary_headroom(dir)
		for tier in OVERTAKE_PROBE_TIERS:
			var mag: float = base_mag * tier
			if mag + car_radius > headroom:
				break
			_build_probe(dir, mag, progress, ramp, INF, probe_len)
			if _probe_is_clear():
				path_controller.start_dodge(dir, mag, progress, ramp)
				dodge_reason = DodgeReason.OVERTAKE
				dodged_car_ref = weakref(leader)
				_follow_slow_time = 0.0
				return

# Condition-based exit: build the corridor "as if we merged starting now" and
# query it. Clear means whatever we were dodging is behind (or gone) — commit.
func _try_merge() -> bool:
	var nose := path_controller.get_progress() + car_owner.depth * 0.5
	var merge_arc := nose + MERGE_LEAD
	var ramp := path_controller.dodge_ramp_len
	var probe_len: float = minf(path_controller.get_curve_length() - nose,
		MERGE_LEAD + ramp + min_safe_distance + 6.0)
	if probe_len <= ghost_spacing:
		# Path is ending; merge unconditionally rather than holding forever.
		path_controller.request_merge(merge_arc)
		return true
	_build_probe(path_controller.dodge_dir, path_controller.dodge_magnitude,
		path_controller.dodge_start_arc, ramp, merge_arc, probe_len)
	if not _probe_is_clear():
		return false
	path_controller.request_merge(merge_arc)
	return true

# Corridor along a hypothetical envelope (same math as the live one — the
# static PathController.envelope), reusing scratch buffers.
func _build_probe(dir: Vector3, mag: float, start_arc: float, ramp: float,
		merge_arc: float, probe_len: float) -> void:
	_probe_points.clear()
	_probe_arcs.clear()
	var nose := path_controller.get_progress() + car_owner.depth * 0.5
	var d := 0.0
	while d < probe_len:
		_probe_points.append(path_controller.sample_baked(nose + d)
			+ dir * (mag * PathController.envelope(nose + d, start_arc, ramp, merge_arc)))
		_probe_arcs.append(d)
		d += ghost_spacing
	_probe_points.append(path_controller.sample_baked(nose + probe_len)
		+ dir * (mag * PathController.envelope(nose + probe_len, start_arc, ramp, merge_arc)))
	_probe_arcs.append(probe_len)

# Same relevance rules as update_target: lights are ignored (they span the
# whole lane, so dodging never escapes them and the live corridor still stops
# for them), cars behind us never constrain, everything else rejects.
func _probe_is_clear() -> bool:
	if _probe_points.size() < 2:
		return false
	var hits := registry.query_corridor(_probe_points, _probe_arcs, car_radius, car_owner)
	if hits.is_empty():
		return true
	var my_pos := _probe_points[0]
	var my_forward := (_probe_points[1] - my_pos).normalized()
	for hit in hits:
		var claim: TrafficClaimRegistry.Claim = hit["claim"]
		match claim.type:
			TrafficClaimRegistry.ClaimType.TRAFFIC_LIGHT:
				continue
			TrafficClaimRegistry.ClaimType.CAR_BODY, TrafficClaimRegistry.ClaimType.CAR_BROADCAST:
				if not is_instance_valid(claim.owner_car):
					continue
				if (claim.owner_car.global_position - my_pos).dot(my_forward) < 0.0:
					continue
				return false
			_:
				return false
	return true

func _ramp_len() -> float:
	return clampf(maxf(current_speed, base_speed * 0.5) * dodge_ramp_time,
		DODGE_RAMP_MIN, DODGE_RAMP_MAX)

# Most room first, so bridge dodges prefer the open side of the canyon and
# overtakes prefer the emptier flank.
func _ordered_dirs(dirs: Array) -> Array:
	dirs.sort_custom(func(a, b): return _boundary_headroom(a) > _boundary_headroom(b))
	return dirs

# Approximate world-space distance from the car's grid position to the lane
# volume boundary along `dir`, so a dodge never leaves the street canyon into
# buildings (which have no claims). INF when the volume can't be resolved.
func _boundary_headroom(dir: Vector3) -> float:
	var vol_dict: Dictionary = car_owner.current_volume
	if car_owner.generator == null or not vol_dict.has("face_idx") or not vol_dict.has("edge_idx"):
		return INF
	var vol: LaneVolume = car_owner.generator.get_lane_volume_area(
		vol_dict["face_idx"], vol_dict["edge_idx"])
	if vol == null or not is_instance_valid(vol):
		return INF
	var u := float(car_owner.current_cell_x) / maxf(car_owner.current_width_cells, 1.0)
	var v := float(car_owner.current_cell_y) / maxf(car_owner.current_height_cells, 1.0)
	var p := vol.get_point_at_grid(u, v, true)
	var best := 0.0
	best = maxf(best, (vol.get_point_at_grid(u, 1.0, true) - p).dot(dir))
	best = maxf(best, (vol.get_point_at_grid(u, 0.0, true) - p).dot(dir))
	best = maxf(best, (vol.get_point_at_grid(1.0, v, true) - p).dot(dir))
	best = maxf(best, (vol.get_point_at_grid(0.0, v, true) - p).dot(dir))
	return best

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
	dodged_car_ref = null
	dodge_reason = DodgeReason.NONE
