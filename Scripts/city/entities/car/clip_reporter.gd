# ClipReporter.gd — diagnostic capture of the first few clips of a run.
#
# Two kinds, both written to `res://clip_report.md` (overwritten each run):
#   • CAR clips — two cars' physical bodies interpenetrate (they drive through
#     each other) instead of separating.
#   • BRIDGE clips — a car's body is inside a bridge slab. This should be
#     IMPOSSIBLE (the vertical profile clears every bridge by construction), so
#     it doubles as a regression alarm: if a future change ever breaks bridge
#     avoidance, it surfaces here.
#
# Detection uses each car's TRUE body extent (unpadded), so it flags genuine
# visual overlap, not the side-padding buffer. Only rendered cars are checked —
# clips out in the fog aren't visible and aren't what we're chasing.
extends RefCounted
class_name ClipReporter

const REPORT_PATH: String = "res://clip_report.md"
const MAX_EVENTS: int = 20
const CLIP_DEPTH: float = 0.4        # min body interpenetration (m) to count (ignores grazing)
const MOVING_EPSILON: float = 0.15
const CHAIN_PREVIEW: int = 5

var _events: Array[String] = []
var _seen_pairs: Dictionary = {}     # "loId_hiId" -> true (one capture per distinct pair)
var _run_stamp: String = ""

func _init() -> void:
	_run_stamp = Time.get_datetime_string_from_system()
	_write()

## Called periodically by CarManager. O(visible²) with a cheap centre-distance
## prefilter; the rendered set is small (fog wall), so this stays light.
func consider(cars: Array) -> void:
	if _events.size() >= MAX_EVENTS:
		return
	var vis: Array = []
	for c in cars:
		if is_instance_valid(c) and c.visual != null:
			vis.append(c)
	var now := Time.get_ticks_msec()
	for i in range(vis.size()):
		if _events.size() >= MAX_EVENTS:
			return
		var a = vis[i]
		# Bridge clip (should never happen — regression alarm).
		var bc: Dictionary = _bridge_clip(a)
		if not bc.is_empty():
			var bkey: String = "bridge|" + a.car_id + "|" + _vol_id(a)
			if not _seen_pairs.has(bkey):
				_seen_pairs[bkey] = true
				_events.append(_summarize_bridge(a, bc, now))
				_write()
				if _events.size() >= MAX_EVENTS:
					return
		var ar: float = _true_radius(a)
		var aseg: Array = _body_seg(a)
		for j in range(i + 1, vis.size()):
			var b = vis[j]
			var br: float = _true_radius(b)
			var reach: float = ar + br + 1.0
			if a.global_position.distance_squared_to(b.global_position) > reach * reach:
				continue
			var key: String = _pair_key(a, b)
			if _seen_pairs.has(key):
				continue
			var bseg: Array = _body_seg(b)
			var res: Vector3 = TrafficClaimRegistry._seg_seg(aseg[0], aseg[1], bseg[0], bseg[1])
			var pen: float = (ar + br) - sqrt(res.z)
			if pen >= CLIP_DEPTH:
				_seen_pairs[key] = true
				_events.append(_summarize(a, b, pen, now))
				_write()
				if _events.size() >= MAX_EVENTS:
					return

# ============================================================================
# GEOMETRY
# ============================================================================

func _body_seg(car) -> Array:
	var half: Vector3 = car.sim_transform.basis.z * (car.depth * 0.5)
	return [car.sim_transform.origin - half, car.sim_transform.origin + half]

func _true_radius(car) -> float:
	return Vector2(car.width, car.height).length() * 0.5   # unpadded — real body

func _pair_key(a, b) -> String:
	return (a.car_id + "|" + b.car_id) if a.car_id < b.car_id else (b.car_id + "|" + a.car_id)

func _vol_id(car) -> String:
	var vol: Dictionary = car.current_volume
	return "%d_%d" % [vol.get("face_idx", -1), vol.get("edge_idx", -1)]

## True body-vs-slab overlap on the car's current street, using the TRUE half
## extents (no dodge clearance), so only a genuine slab intersection is flagged
## — a correctly-cleared car (above, below, or clearance-away) is not. Returns
## {band_lo, band_hi, y, depth} or {} if clear. Checks the body's tail, centre
## and nose so a long car poking in is caught.
func _bridge_clip(car) -> Dictionary:
	var g = car.generator
	var vol: Dictionary = car.current_volume
	var fi: int = vol.get("face_idx", -1)
	var ei: int = vol.get("edge_idx", -1)
	if g == null or fi < 0:
		return {}
	var vm: float = car.height * 0.5
	var xm: float = car.width * 0.5
	var seg: Array = _body_seg(car)
	var points := [seg[0], car.sim_transform.origin, seg[1]]
	for placed in g.get_bridges_for_lane(fi, ei):
		var geo: Dictionary = BridgePlanner._bridge_geometry(placed)
		for p in points:
			var band: Vector2 = BridgePlanner.blocked_band(geo, p, vm, xm)
			if band != Vector2.INF and p.y >= band.x and p.y <= band.y:
				return {"band_lo": band.x, "band_hi": band.y, "y": p.y,
					"depth": minf(p.y - band.x, band.y - p.y)}
	return {}

# ============================================================================
# SUMMARY
# ============================================================================

func _summarize(a, b, pen: float, now: int) -> String:
	var lines: PackedStringArray = []
	var dy: float = a.global_position.y - b.global_position.y
	var ang: float = _heading_angle(a, b)
	lines.append("## Clip %d  (t=+%.0fs, overlap %.1fm, Δalt %+.1fm)" % [
		_events.size() + 1, now / 1000.0, pen, dy])

	var na: int = _current_node(a)
	var nb: int = _current_node(b)
	if na == nb and na >= 0:
		lines.append("where: node %d (both cars there)" % na)
	else:
		lines.append("where: %s@node %d vs %s@node %d" % [_short(a.car_id), na, _short(b.car_id), nb])

	lines.append("type : %s ~%d°" % [_classify(ang), int(round(ang))])
	lines.append("cause: " + _cause(a, b, dy, ang))

	lines.append(_car_block(a))
	lines.append(_car_block(b))
	return "\n".join(lines)

# Best-guess mechanism, from the two cars' motion/altitude/heading.
func _cause(a, b, _dy: float, ang: float) -> String:
	var a_moving: bool = a.collision_avoidance.current_speed > MOVING_EPSILON
	var b_moving: bool = b.collision_avoidance.current_speed > MOVING_EPSILON
	if a_moving != b_moving:
		# There is NO body-ignore mechanism left (unstuck removed) — a moving car
		# passing through a stopped one now always means the mover's detection
		# failed to wall on the body. Where the stopped car stands is the clue.
		var mover = a if a_moving else b
		var held = b if a_moving else a
		var spot: String = "stopped car IS inside an intersection (blocking the box)" \
			if _in_intersection(held) else "stopped car is mid-street (not in a node)"
		return "DRIVE-THROUGH — %s drove through %s (governor bug: bodies are inviolable); %s" % [
			_short(mover.car_id), _short(held.car_id), spot]
	if a_moving and b_moving:
		if ang > 150.0:
			return "HEAD-ON — both cars moving into each other on opposing paths"
		if ang < 30.0:
			return "REAR-END — a follower overran its leader in the same lane"
		return "CROSSING — both cars entered the node at once and drove through each other"
	return "STATIC OVERLAP — both stopped and interpenetrating (fog-born, or an overlap that never separated)"

func _summarize_bridge(car, bc: Dictionary, now: int) -> String:
	var lines: PackedStringArray = []
	lines.append("## Bridge clip %d  (t=+%.0fs, %.1fm into slab)" % [
		_events.size() + 1, now / 1000.0, bc["depth"]])
	lines.append("where: node %d (street %s)" % [_current_node(car), _street(car, car.current_volume)])
	# The lift the profile actually applied here — 0 means the planner never
	# scheduled a climb for this bridge; nonzero-but-clipping means the ramp or
	# its timing fell short.
	var pc = car.path_controller
	var prog: float = pc.get_progress()
	lines.append("slab : y[%.1f..%.1f]  car y=%.1f  |  profile lift %.1f" % [
		bc["band_lo"], bc["band_hi"], bc["y"], pc.profile_offset(prog)])
	lines.append("cause: BRIDGE — car body is inside a slab; the vertical profile failed to clear it")
	lines.append(_car_block(car))
	return "\n".join(lines)

func _car_block(car) -> String:
	var ca = car.collision_avoidance
	var arch: String = CarArchetypes.Type.keys()[car.car_archetype]
	var chain := _route_nodes(car)
	var segs: Array = car.path_controller.segments
	var first_vol: Dictionary = segs[0]["volume"] if not segs.is_empty() else {}
	return ("  %s %s  %.1f m/s  %s  y=%.1f\n"
		+ "     spawn %s @(%d,%d,%d) head %s\n"
		+ "     route %s  →exit %s  now at node %d") % [
		_short(car.car_id), arch, ca.current_speed,
		CollisionAvoidance.State.keys()[ca.state], car.global_position.y,
		_street(car, first_vol),
		int(car.spawn_position.x), int(car.spawn_position.y), int(car.spawn_position.z),
		_compass(car.spawn_heading),
		_fmt_chain(chain), (str(chain[-1]) if not chain.is_empty() else "?"),
		_current_node(car)]

# ============================================================================
# GRAPH / DIRECTION HELPERS (compact)
# ============================================================================

## True if the car is within (or a body-length from) an intersection — i.e. its
## arc sits in a bezier turn between two straight street segments. That's the
## "conflict zone" a yielding car must NOT stop inside.
func _in_intersection(car) -> bool:
	var pc = car.path_controller
	var prog: float = pc.get_progress()
	var m: float = car.depth
	for i in range(pc.segments.size() - 1):
		if prog > pc.segments[i]["arc_end"] - m and prog < pc.segments[i + 1]["arc_start"] + m:
			return true
	return false

func _current_node(car) -> int:
	return _exit_node(car, car.current_volume)

func _exit_node(car, vol: Dictionary) -> int:
	var g = car.generator
	var fi: int = vol.get("face_idx", -1)
	if g == null or fi < 0:
		return -1
	return g.plain_graph.faces[fi][vol.get("edge_idx", -1)]

func _entry_node(car, vol: Dictionary) -> int:
	var g = car.generator
	var fi: int = vol.get("face_idx", -1)
	if g == null or fi < 0:
		return -1
	var face = g.plain_graph.faces[fi]
	return face[(vol.get("edge_idx", -1) + 1) % face.size()]

func _street(car, vol: Dictionary) -> String:
	return "%d→%d" % [_entry_node(car, vol), _exit_node(car, vol)]

func _route_nodes(car) -> Array:
	var out: Array = []
	var segs: Array = car.path_controller.segments
	if segs.is_empty():
		return out
	out.append(_entry_node(car, segs[0]["volume"]))
	for seg in segs:
		out.append(_exit_node(car, seg["volume"]))
	return out

func _fmt_chain(nodes: Array) -> String:
	if nodes.is_empty():
		return "?"
	if nodes.size() <= CHAIN_PREVIEW + 2:
		return _arrow(nodes)
	return "%s→…(%d more)→%d" % [_arrow(nodes.slice(0, CHAIN_PREVIEW)),
		nodes.size() - CHAIN_PREVIEW - 1, nodes[-1]]

func _arrow(nodes: Array) -> String:
	var parts: PackedStringArray = []
	for k in nodes:
		parts.append(str(k))
	return "→".join(parts)

func _heading_angle(a, b) -> float:
	var ha := _flat(a.path_controller.get_heading())
	var hb := _flat(b.path_controller.get_heading())
	if ha.length_squared() < 1e-6 or hb.length_squared() < 1e-6:
		return 0.0
	return rad_to_deg(acos(clampf(ha.normalized().dot(hb.normalized()), -1.0, 1.0)))

func _classify(deg: float) -> String:
	if deg < 30.0: return "SAME-DIR"
	if deg < 70.0: return "MERGING"
	if deg < 110.0: return "CROSSING"
	if deg < 150.0: return "OBLIQUE-ONCOMING"
	return "ONCOMING"

func _compass(d: Vector3) -> String:
	var f := _flat(d)
	if f.length_squared() < 1e-6:
		return "?"
	var idx := int(round(rad_to_deg(atan2(f.x, -f.z)) / 45.0)) % 8
	if idx < 0:
		idx += 8
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][idx]

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

static func _short(id: String) -> String:
	return id.substr(maxi(id.length() - 4, 0))

# ============================================================================
# FILE
# ============================================================================

func _write() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# Clip report — run %s\n" % _run_stamp)
	f.store_string("# %d clip(s) captured (cap %d), rendered cars only — car-on-car and car-in-bridge.\n\n"
		% [_events.size(), MAX_EVENTS])
	if _events.is_empty():
		f.store_string("_No clips yet._\n")
	else:
		f.store_string("\n\n".join(_events))
		f.store_string("\n")
	f.close()
