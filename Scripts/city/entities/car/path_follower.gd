# PathController.gd — node-free following of an IMMUTABLE full-route curve.
#
# The car's entire route is committed at spawn: one Curve3D through every
# street it will drive (smooth bezier turns at each intersection) plus one
# Y-profile that clears every bridge on the route with bounded slope. Both are
# built once and never touched again. The car only ever advances its arc
# forward along them.
#
# Because nothing the car's position is read from is ever recomputed while it
# drives, a vertical (or any) teleport is structurally impossible — the entire
# class of "the plan changed under the car" bugs is designed out. There is no
# per-segment rebuild, no carry, no lock.
extends RefCounted
class_name PathController

# Emitted as the car's arc crosses from one route segment (street) into the
# next — used only for spawn/occupancy bookkeeping, not for any replanning.
signal segment_transition_completed(old_volume_id: String, new_volume_id: String)
signal path_ended

# Baked-point spacing. The car's transform is `sample_baked_with_rotation`,
# which linearly interpolates position AND rotation between baked points — so
# on a tight turn the car follows the chords and its facing steps between them,
# faceting the corner (worst for long, slow vehicles). Finer baking = shorter
# chords = smoother turns. Rendering fidelity only; it never changes where the
# car actually drives (the underlying Curve3D is unchanged).
const BAKE_INTERVAL: float = 0.5
const TURN_HANDLE_FRACTION: float = 0.4   # bezier handle length as a fraction of the turn gap

var curve: Curve3D
var progress: float = 0.0

# The planned vertical profile: a knot polyline (x = arc, y = world-Y offset),
# smoothstep-eased between knots, immutable once built. `route_volumes` lets
# BridgePlanner gather every bridge on the route.
var profile: PackedVector2Array = PackedVector2Array()
var route_volumes: Array = []

# Lateral offset — the horizontal analogue of the bridge profile. A signed
# sideways displacement (metres, + = the car's RIGHT) from the rail, driven at
# runtime by CollisionAvoidance so cars slide around each other. Bounded by the
# lateral room below and by a lateral slope, so it is always smooth (no teleport)
# — exactly the bridge-ramp discipline, one axis over. `lateral_slope` is the
# current d(offset)/d(arc), used only to yaw the car into its drift.
var lateral_offset: float = 0.0
var lateral_slope: float = 0.0

# The static "free tube": how far sideways the car may drift and stay on safe
# ground. A constant on open road, tapering to ~0 through a bridge passage (where
# the vertical profile is committed and the car must hold its rail), with a
# bounded run-up so an active drift is drawn home BEFORE the bridge.
const LATERAL_ROOM_BASE: float = 2.5   # metres of sideways room on open road
const BRIDGE_RUNUP: float = 12.0       # arc over which room tapers to 0 before a bridge

# Per-segment arc ranges along the baked curve, for volume/light tracking.
# Each entry: {"id": String, "volume": Dictionary, "arc_start": float,
# "arc_end": float}. Contiguous and ordered.
var segments: Array = []
var _current_seg: int = 0

var world_node: Node3D
var car_owner: FlyingCar

var _length: float = 0.0
var _ended: bool = false

# Debug
var path_debug_mesh: MeshInstance3D
var show_debug: bool = false
var debug_color: Color = Color.YELLOW
var debug_width: float = 0.05
var debug_segments: int = 30

func initialize(owner_car: FlyingCar, world: Node3D) -> void:
	car_owner = owner_car
	world_node = world

# ============================================================================
# ROUTE CONSTRUCTION (once, at spawn)
# ============================================================================

## `route` is an ordered list of {start: Vector3, end: Vector3,
## volume_data: Dictionary}. Builds the immutable curve, segment arc table and
## Y-profile. `initial_progress` is the fraction along the FIRST segment the
## car spawns at (mid-street spawns).
func create_route(route: Array, initial_progress: float) -> void:
	route_volumes.clear()
	segments.clear()
	_current_seg = 0
	_ended = false
	lateral_offset = 0.0
	lateral_slope = 0.0

	if route.is_empty():
		curve = null
		_length = 0.0
		return

	curve = Curve3D.new()
	curve.bake_interval = BAKE_INTERVAL
	_build_curve(route)
	_length = curve.get_baked_length()

	for seg in route:
		route_volumes.append(seg["volume_data"])
	_build_segment_table(route)

	# The car spawns partway along its first street.
	var first_len: float = segments[0]["arc_end"] if not segments.is_empty() else 0.0
	progress = clampf(initial_progress, 0.0, 1.0) * first_len
	_current_seg = _segment_at(progress)

	profile = BridgePlanner.plan_route(self)

	if show_debug:
		_create_path_debug()

# One Curve3D through every waypoint: each street contributes a straight
# start->end, and each intersection a bezier turn between one street's end and
# the next's start (handles along the respective flow directions).
func _build_curve(route: Array) -> void:
	for i in range(route.size()):
		var seg: Dictionary = route[i]
		var s: Vector3 = seg["start"]
		var e: Vector3 = seg["end"]
		var dir := (e - s)
		dir = dir.normalized() if dir.length_squared() > 1e-8 else Vector3.FORWARD

		# In-handle on this street's start: curve in from the previous turn.
		var in_start := Vector3.ZERO
		if i > 0:
			var prev_end: Vector3 = route[i - 1]["end"]
			in_start = -dir * (prev_end.distance_to(s) * TURN_HANDLE_FRACTION)
		curve.add_point(s, in_start, Vector3.ZERO)

		# Out-handle on this street's end: curve out toward the next turn.
		var out_end := Vector3.ZERO
		if i < route.size() - 1:
			var next_start: Vector3 = route[i + 1]["start"]
			out_end = dir * (e.distance_to(next_start) * TURN_HANDLE_FRACTION)
		curve.add_point(e, Vector3.ZERO, out_end)

func _build_segment_table(route: Array) -> void:
	# Accumulate arc monotonically along the point order (straights are exact
	# euclidean lengths; turns are sampled cubic lengths). This avoids
	# get_closest_offset, which can return the wrong pass when a route revisits
	# a node and the curve comes near itself.
	var arc := 0.0
	for i in range(route.size()):
		var seg: Dictionary = route[i]
		var s: Vector3 = curve.get_point_position(2 * i)
		var e: Vector3 = curve.get_point_position(2 * i + 1)
		var arc_start := arc
		arc += s.distance_to(e)  # street straight
		var arc_end := arc
		segments.append({
			"id": _volume_id(seg["volume_data"]),
			"volume": seg["volume_data"],
			"arc_start": arc_start,
			"arc_end": arc_end,
		})
		if i < route.size() - 1:
			# Bezier turn into the next street.
			arc += _cubic_length(e, e + curve.get_point_out(2 * i + 1),
				curve.get_point_position(2 * i + 2) + curve.get_point_in(2 * i + 2),
				curve.get_point_position(2 * i + 2))

static func _cubic_length(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> float:
	var length := 0.0
	var prev := p0
	for k in range(1, 9):
		var t := k / 8.0
		var mt := 1.0 - t
		var pt := mt * mt * mt * p0 + 3.0 * mt * mt * t * p1 \
			+ 3.0 * mt * t * t * p2 + t * t * t * p3
		length += prev.distance_to(pt)
		prev = pt
	return length

# ============================================================================
# MOTION
# ============================================================================

func get_current_transform() -> Transform3D:
	if not curve:
		return Transform3D()
	var xf := curve.sample_baked_with_rotation(progress)
	var v_off := profile_offset(progress)
	var v_slope := profile_slope(progress)
	if absf(v_off) < 1e-5 and absf(v_slope) < 1e-5 \
			and absf(lateral_offset) < 1e-5 and absf(lateral_slope) < 1e-5:
		return xf
	var base_tangent := rail_tangent(progress)
	if base_tangent.length_squared() < 1e-8:
		return xf
	var right := Vector3.UP.cross(base_tangent)
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	# Displace the origin: vertical (bridge profile) + lateral (traffic offset).
	xf.origin += Vector3.UP * v_off + right * lateral_offset
	# Heading tilts with both slopes: pitch from the climb, yaw from the drift.
	var tangent := (base_tangent + Vector3.UP * v_slope + right * lateral_slope).normalized()
	var z_axis := tangent * (1.0 if xf.basis.z.dot(base_tangent) >= 0.0 else -1.0)
	var y_axis := xf.basis.y - z_axis * xf.basis.y.dot(z_axis)
	if y_axis.length_squared() < 1e-8:
		y_axis = Vector3.UP - z_axis * Vector3.UP.dot(z_axis)
	y_axis = y_axis.normalized()
	xf.basis = Basis(y_axis.cross(z_axis), y_axis, z_axis)
	return xf

## Normalised tangent of the BASE rail (no offsets) at an arc — the frame the
## lateral offset is measured and applied in.
func rail_tangent(arc: float) -> Vector3:
	var h := 0.5
	var t := sample_baked(minf(arc + h, _length)) - sample_baked(maxf(arc - h, 0.0))
	return t.normalized() if t.length_squared() > 1e-8 else Vector3.FORWARD

## Unit vector pointing to the car's RIGHT at an arc (horizontal, ⟂ to travel).
func right_at(arc: float) -> Vector3:
	var r := Vector3.UP.cross(rail_tangent(arc))
	return r.normalized() if r.length_squared() > 1e-8 else Vector3.RIGHT

## Set the lateral offset and its current slope (from CollisionAvoidance).
func set_lateral(offset: float, slope: float) -> void:
	lateral_offset = offset
	lateral_slope = slope

## Static sideways room at an arc: full on open road, tapering to 0 approaching a
## bridge passage (where the vertical profile is active), with a bounded run-up
## so any active drift is drawn back to the rail before the slab.
func lateral_room(arc: float) -> float:
	var nearest := BRIDGE_RUNUP
	var a := 0.0
	while a <= BRIDGE_RUNUP:
		var s := arc + a
		if absf(profile_offset(s)) > 0.2 or absf(profile_slope(s)) > 0.02:
			nearest = a
			break
		a += 1.5
	return LATERAL_ROOM_BASE * clampf(nearest / BRIDGE_RUNUP, 0.0, 1.0)

func advance(delta: float, speed: float) -> void:
	advance_distance(delta * speed)

## Advance by an exact arc distance (the governor clamps travel per frame so a
## body can never be entered between decision ticks).
func advance_distance(dist: float) -> void:
	if not curve:
		return
	progress += dist

	# Segment crossing (bookkeeping only — nothing is recomputed).
	while _current_seg + 1 < segments.size() \
			and progress >= segments[_current_seg + 1]["arc_start"]:
		var old_id: String = segments[_current_seg]["id"]
		_current_seg += 1
		segment_transition_completed.emit(old_id, segments[_current_seg]["id"])

	if progress >= _length:
		progress = _length
		if not _ended:
			_ended = true
			path_ended.emit()

func get_progress() -> float:
	return progress

func get_curve_length() -> float:
	return _length

func sample_baked(p_progress: float) -> Vector3:
	if curve:
		return curve.sample_baked(p_progress)
	return Vector3.ZERO

## Normalised direction of travel at the car's current arc (always forward,
## since progress only increases). Used by the governor to tell a same-lane
## leader (follow its speed) from crossing/oncoming traffic (hard stop).
func get_heading() -> Vector3:
	if not curve:
		return Vector3.FORWARD
	var h := 1.0
	var t := sample_profiled(minf(progress + h, _length)) - sample_profiled(maxf(progress - h, 0.0))
	return t.normalized() if t.length_squared() > 1e-8 else Vector3.FORWARD

## Base curve plus the planned Y-profile AND the current lateral offset — the
## path actually flown. Corridor building and occupancy sampling use this, so the
## speed-ray looks down the line the car is drifting into (that coupling is what
## turns a sideways nudge into an overtake / head-on pass).
func sample_profiled(p_progress: float) -> Vector3:
	var p := sample_baked(p_progress)
	p.y += profile_offset(p_progress)
	if absf(lateral_offset) > 1e-5:
		p += right_at(p_progress) * lateral_offset
	return p

# ============================================================================
# SEGMENT / VOLUME TRACKING (for lights + bookkeeping)
# ============================================================================

## The volume ids the car is currently on and about to enter — a traffic light
## only applies if the car's route actually uses its lane.
func get_relevant_volume_ids() -> Array[String]:
	var ids: Array[String] = []
	if _current_seg < segments.size():
		ids.append(segments[_current_seg]["id"])
	if _current_seg + 1 < segments.size():
		ids.append(segments[_current_seg + 1]["id"])
	return ids

func current_volume_data() -> Dictionary:
	if _current_seg < segments.size():
		return segments[_current_seg]["volume"]
	return {}

func _segment_at(arc: float) -> int:
	for i in range(segments.size()):
		if arc < segments[i]["arc_end"]:
			return i
	return maxi(segments.size() - 1, 0)

func _volume_id(volume: Dictionary) -> String:
	if volume.has("face_idx") and volume.has("edge_idx"):
		return str(volume["face_idx"]) + "_" + str(volume["edge_idx"])
	return ""

# ============================================================================
# PROFILE INTERPOLATION (knot polyline, smoothstep-eased)
# ============================================================================

func profile_offset(arc: float) -> float:
	return knot_offset(profile, arc)

func profile_slope(arc: float) -> float:
	return knot_slope(profile, arc)

## The [entrance, exit] absolute arcs of the next intersection "box" strictly
## ahead of the car — the bezier turn between the current straight's end and the
## next straight's start. A car must not come to REST inside this span (it would
## block cross traffic), so the governor uses it to stop before the box when it
## cannot clear it. Returns Vector2(INF, INF) if none remains ahead.
func next_box() -> Vector2:
	for i in range(_current_seg, segments.size() - 1):
		var box_start: float = segments[i]["arc_end"]
		if box_start >= progress:
			return Vector2(box_start, segments[i + 1]["arc_start"])
	return Vector2(INF, INF)

## Smoothstep-eased interpolation over a knot polyline. Static so
## BridgePlanner's flown-path scan evaluates the exact same math.
static func knot_offset(knots: PackedVector2Array, arc: float) -> float:
	var n := knots.size()
	if n == 0:
		return 0.0
	if arc <= knots[0].x:
		return knots[0].y
	for i in range(1, n):
		if arc < knots[i].x:
			var a := knots[i - 1]
			var b := knots[i]
			if b.x - a.x < 0.001:
				return b.y
			var t := (arc - a.x) / (b.x - a.x)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(a.y, b.y, t)
	return knots[n - 1].y

static func knot_slope(knots: PackedVector2Array, arc: float) -> float:
	var n := knots.size()
	if n == 0 or arc <= knots[0].x:
		return 0.0
	for i in range(1, n):
		if arc < knots[i].x:
			var a := knots[i - 1]
			var b := knots[i]
			if b.x - a.x < 0.001:
				return 0.0
			var t := (arc - a.x) / (b.x - a.x)
			return (b.y - a.y) * (6.0 * t - 6.0 * t * t) / (b.x - a.x)
	return 0.0

# ============================================================================
# DEBUG / CLEANUP
# ============================================================================

func _create_path_debug() -> void:
	var points = []
	for i in range(curve.point_count):
		points.append({
			"pos": curve.get_point_position(i),
			"in": curve.get_point_in(i),
			"out": curve.get_point_out(i)
		})
	path_debug_mesh = DebugUtil.create_debug_path3d(
		points, debug_segments, debug_color, debug_width)
	world_node.add_child(path_debug_mesh)

func _clear_debug_meshes() -> void:
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()

func cleanup() -> void:
	_clear_debug_meshes()
