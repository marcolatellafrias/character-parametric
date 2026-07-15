# StuckReporter.gd — capture of PERMANENTLY stuck cars: only the originators.
#
# Ground truth is MOVEMENT, not cause: a car is a candidate only after it has
# not moved MOVE_EPS meters for STUCK_MS — longer than a full light cycle, so
# a normal red-light wait can never qualify. From a candidate we walk the chain
# of stationary blockers (bodies AND ghosts — `blocking_car_ref` covers both)
# and record only the ROOT:
#   • a CYCLE (mutual deadlock) — the true originators; or
#   • a terminal HEAD (stopped with no car ahead) — classified below.
# Followers merely queued behind a root are never recorded (their chain leads
# into the root, which is recorded once), and a chain that reaches a recently-
# MOVING car is a draining queue and is ignored entirely.
#
# Because a queue member's instantaneous cause oscillates (red light during the
# red phase, body-of-the-car-ahead during green), each stationary car also
# remembers the last NON-light cause it had (`_nonlight_cause`). That is what
# lets a head "stopped at a red for 20s" be split into its two real meanings:
#   - during green it was body-blocked → the queue isn't draining (spillback;
#     the root is elsewhere — the remembered blocker is named), vs
#   - it NEVER had another constraint → it ignored a green: governor or light
#     bug (cross-check light_watchdog.md).
#
# A bootstrap grace period skips the opening congestion wave, and events are
# capped per node so one hotspot can't burn the whole cap.
extends RefCounted
class_name StuckReporter

const REPORT_PATH: String = "res://stuck_report.md"
const MAX_EVENTS: int = 20
const MAX_PER_NODE: int = 2           # cap events per node — hotspots repeat
const MAX_PER_CLASS: int = 6          # cap events per failure class — one systemic
                                      # cause (e.g. frozen lights) can't hog the cap
const GRACE_MS: int = 90000           # ignore the bootstrap congestion wave
const STUCK_MS: int = 15000           # no movement this long = candidate (> a full light cycle)
const ROOT_STUCK_MS: int = 8000       # chain members must be stationary this long
const MOVE_EPS: float = 1.0           # movement below this doesn't count as moving
const CHAIN_MAX: int = 12
const CHAIN_PREVIEW: int = 5

var _events: Array[String] = []
var _recorded: Dictionary = {}        # car_id -> true (roots; followers reaching them skip)
var _node_count: Dictionary = {}      # node -> events already recorded there
var _class_count: Dictionary = {}     # failure class -> events already recorded
var _last_moved: Dictionary = {}      # car_id -> {"pos": Vector3, "t": msec}
var _nonlight_cause: Dictionary = {}  # car_id -> last non-light cause while stationary
var _run_stamp: String = ""

func _init() -> void:
	_run_stamp = Time.get_datetime_string_from_system()
	_write()   # clear any stale report from the previous run

## Called periodically by CarManager with the live fleet.
func consider(cars: Array) -> void:
	var now := Time.get_ticks_msec()

	# --- movement + cause tracking (all cars, every pass) ---
	var alive: Dictionary = {}
	for car in cars:
		var id: String = car.car_id
		alive[id] = true
		var rec = _last_moved.get(id)
		if rec == null or (rec["pos"] as Vector3).distance_to(car.global_position) > MOVE_EPS:
			_last_moved[id] = {"pos": car.global_position, "t": now}
			_nonlight_cause.erase(id)   # moving: forget stale causes
		else:
			# Stationary: remember the latest NON-light cause (a queue member's
			# cause flips light↔body with the phases; the body one is the truth).
			var ca = car.collision_avoidance
			if ca != null and not car.is_blocked_by_traffic_plane:
				var ref: WeakRef = ca.blocking_car_ref
				var b = ref.get_ref() if ref != null else null
				if b is FlyingCar:
					_nonlight_cause[id] = ("ghost:" if ca.is_blocked_by_broadcast else "body:") + b.car_id
	for id in _last_moved.keys():
		if not alive.has(id):
			_last_moved.erase(id)
			_nonlight_cause.erase(id)

	if _events.size() >= MAX_EVENTS or now < GRACE_MS:
		return

	# --- root hunting ---
	for car in cars:
		if _events.size() >= MAX_EVENTS:
			return
		if _recorded.has(car.car_id) or _stationary_ms(car, now) < STUCK_MS:
			continue
		var root := _find_root(car, now)
		if root.is_empty():
			continue
		var fresh := true
		for c in root:
			if _recorded.has(c.car_id):
				fresh = false
				break
		var node := _current_node(root[0])
		var cls := _class_of(root)
		if fresh and _node_count.get(node, 0) < MAX_PER_NODE \
				and _class_count.get(cls, 0) < MAX_PER_CLASS:
			_node_count[node] = _node_count.get(node, 0) + 1
			_class_count[cls] = _class_count.get(cls, 0) + 1
			_record(root, now)

# ============================================================================
# DETECTION
# ============================================================================

func _stationary_ms(car, now: int) -> int:
	var rec = _last_moved.get(car.car_id)
	return (now - int(rec["t"])) if rec != null else 0

## Failure class of a root, for the per-class cap.
func _class_of(root: Array) -> String:
	if root.size() > 1:
		return "cycle"
	var car = root[0]
	if car.is_blocked_by_traffic_plane:
		return "queue_not_draining" if _nonlight_cause.has(car.car_id) else "ignored_green"
	if car.collision_avoidance.is_blocked_by_broadcast:
		return "ghost_stall"
	return "no_constraint"

# Walk the chain of stationary blockers. Cycle → its members (the originators).
# Terminal head (no car ahead) → [head]. A recently-moving car anywhere in the
# chain → [] (a draining queue, not pathology).
func _find_root(start, now: int) -> Array:
	var seen: Array = []
	var pos: Dictionary = {}
	var node = start
	var depth := 0
	while node != null and is_instance_valid(node) and depth < CHAIN_MAX:
		if _stationary_ms(node, now) < ROOT_STUCK_MS:
			return []                        # something ahead still moves → transient
		var id: String = node.car_id
		if pos.has(id):
			return seen.slice(pos[id])       # cycle
		pos[id] = seen.size()
		seen.append(node)
		var ref: WeakRef = node.collision_avoidance.blocking_car_ref
		var nxt = ref.get_ref() if ref != null else null
		if not (nxt is FlyingCar):
			return [node]                    # head: stopped with no car ahead of it
		node = nxt
		depth += 1
	return []

# ============================================================================
# RECORDING
# ============================================================================

func _record(root: Array, now: int) -> void:
	for c in root:
		_recorded[c.car_id] = true
	_events.append(_summarize_head(root[0], now) if root.size() == 1 else _summarize(root, now))
	_write()

## A single stationary car with no car ahead of it — classify what pins it.
func _summarize_head(car, now: int) -> String:
	var ca = car.collision_avoidance
	var stuck: float = _stationary_ms(car, now) / 1000.0
	var remembered: String = _nonlight_cause.get(car.car_id, "")
	var reason: String
	if car.is_blocked_by_traffic_plane:
		if remembered != "":
			reason = ("LIGHT QUEUE NOT DRAINING — hasn't moved in %.0fs (≥%d light cycles); "
				+ "during green it was blocked by %s, so the real root is downstream (spillback)") \
				% [stuck, int(stuck / 10.0), remembered]
		else:
			reason = ("IGNORED GREEN — stopped at a light %.0fs (≥%d cycles) with NO other "
				+ "constraint ever seen: a governor bug, or the light never turned "
				+ "(cross-check light_watchdog.md)") % [stuck, int(stuck / 10.0)]
	elif ca.is_blocked_by_broadcast:
		reason = "GHOST STALL — yielding to a claim that never clears"
	else:
		reason = "NO CONSTRAINT — stopped with nothing blocking it (governor bug)"
	var lines: PackedStringArray = []
	lines.append("## Stuck head %d  (t=+%.0fs, unmoved %.1fs, 1 car)" % [
		_events.size() + 1, now / 1000.0, stuck])
	lines.append("where: node %d (street %s)" % [_current_node(car), _street(car, car.current_volume)])
	lines.append("why  : %s" % reason)
	lines.append(_car_block(car, now))
	return "\n".join(lines)

func _summarize(cycle: Array, now: int) -> String:
	var n := cycle.size()
	var lines: PackedStringArray = []
	var max_stuck := 0.0
	for c in cycle:
		max_stuck = maxf(max_stuck, _stationary_ms(c, now) / 1000.0)

	lines.append("## Deadlock %d  (t=+%.0fs, unmoved %.1fs, %d cars)" % [
		_events.size() + 1, now / 1000.0, max_stuck, n])

	# Where: the intersection each car is entering; note if they share one.
	var nodes: Array = []
	for c in cycle:
		nodes.append(_current_node(c))
	var same := true
	for k in nodes:
		if k != nodes[0]:
			same = false
			break
	if same and nodes[0] >= 0:
		lines.append("where: node %d (all cars entering it)" % nodes[0])
	else:
		var parts: PackedStringArray = []
		for i in range(n):
			parts.append("%s@node %d" % [_short(cycle[i].car_id), nodes[i]])
		lines.append("where: " + ", ".join(parts))

	# ISOLATED (one node) should be impossible under total-order priority +
	# stop-before-the-box — a regression to chase. A multi-node cycle is
	# spillback gridlock, the documented distributed-rules edge case.
	if same:
		lines.append("kind : ISOLATED (all at one node) — should be impossible; a rule regression")
	else:
		var span: Dictionary = {}
		for k in nodes:
			span[k] = true
		lines.append("kind : SPILLBACK gridlock — cycle spans %d nodes (a jammed ring)" % span.size())

	# Type + why. Two-car cycles get the full geometry read.
	if n == 2:
		var a = cycle[0]
		var b = cycle[1]
		var ang: float = _heading_angle(a, b)
		var apart: float = a.global_position.distance_to(b.global_position)
		lines.append("type : %s ~%d°   apart %.1fm" % [_classify(ang), int(round(ang)), apart])
		lines.append("why  : mutual block — each waits on the other (see per-car diag: body vs ghost)")
	else:
		lines.append("type : %d-car cycle (each blocked by the next)" % n)
		lines.append("why  : circular wait — no member can move until the one ahead does")

	for c in cycle:
		lines.append(_car_block(c, now))
	return "\n".join(lines)

func _car_block(car, now: int) -> String:
	var ca = car.collision_avoidance
	var arch: String = CarArchetypes.Type.keys()[car.car_archetype]
	var blocker := ""
	var blocker_car = null
	var ref: WeakRef = ca.blocking_car_ref
	if ref != null and ref.get_ref() is FlyingCar:
		blocker_car = ref.get_ref()
		blocker = _short(blocker_car.car_id)
	var stuck := _stationary_ms(car, now) / 1000.0
	var chain := _route_nodes(car)
	var segs: Array = car.path_controller.segments
	var first_vol: Dictionary = segs[0]["volume"] if not segs.is_empty() else {}
	# Governor internals — decisive when the block "should" be moving: `gap` is
	# the distance to the nearest thing ahead that set the target speed (~0 with
	# target 0 = eased to a halt right behind something), `ray` the broadcast
	# length the car is publishing.
	var gov := "gov  state=%s target=%.1f gap=%s ray=%.1f" % [
		CollisionAvoidance.State.keys()[ca.state], ca.target_speed,
		("inf" if ca.stop_gap == INF else "%.2f" % ca.stop_gap),
		ca.broadcast_length]
	return ("  %s %s  spawn %s @(%d,%d,%d) head %s\n"
		+ "     route %s  →exit %s\n"
		+ "     now  at node %d, %.1f m/s, unmoved %.1fs, waits→%s\n"
		+ "     %s\n"
		+ "     %s") % [
		_short(car.car_id), arch,
		_street(car, first_vol),
		int(car.spawn_position.x), int(car.spawn_position.y), int(car.spawn_position.z),
		_compass(car.spawn_heading),
		_fmt_chain(chain), (str(chain[-1]) if not chain.is_empty() else "?"),
		_current_node(car), ca.current_speed, stuck, blocker,
		gov,
		_diag(car, blocker_car)]

# Geometry read of the car vs its blocker, so the failed rule is identifiable:
#   ghost      — blocked by a claim (true) or a physical body (false)
#   blocker    — ahead / behind / beside, with the along-track offset
#   d          — centre distance vs summed contact radii
#   same_dir   — leader-follow branch vs crossing branch
func _diag(car, b) -> String:
	if not (b is FlyingCar):
		return "diag (no blocker)"
	var ca = car.collision_avoidance
	var to_other: Vector3 = b.global_position - car.global_position
	var fwd: Vector3 = car.path_controller.get_heading()
	var along: float = to_other.dot(fwd)
	var d: float = to_other.length()
	var r_sum: float = ca.car_radius + b.collision_avoidance.car_radius
	var same_dir: bool = fwd.dot(b.path_controller.get_heading()) > 0.5
	var rel: String = "ahead" if along > 0.5 else ("behind" if along < -0.5 else "beside")
	return "diag ghost=%s  blocker %s(along %+.1f)  d %.1f/r_sum %.1f %s  same_dir=%s" % [
		str(ca.is_blocked_by_broadcast), rel, along, d, r_sum,
		("OVERLAP" if d < r_sum else "apart"), str(same_dir)]

# ============================================================================
# GEOMETRY / GRAPH HELPERS (compact, words over numbers)
# ============================================================================

func _current_node(car) -> int:
	return _exit_node(car, car.current_volume)

func _exit_node(car, vol: Dictionary) -> int:
	var g = car.generator
	var fi: int = vol.get("face_idx", -1)
	var ei: int = vol.get("edge_idx", -1)
	if g == null or fi < 0:
		return -1
	return g.plain_graph.faces[fi][ei]

func _entry_node(car, vol: Dictionary) -> int:
	var g = car.generator
	var fi: int = vol.get("face_idx", -1)
	var ei: int = vol.get("edge_idx", -1)
	if g == null or fi < 0:
		return -1
	var face = g.plain_graph.faces[fi]
	return face[(ei + 1) % face.size()]

func _street(car, vol: Dictionary) -> String:
	return "%d→%d" % [_entry_node(car, vol), _exit_node(car, vol)]

# The route as its sequence of graph nodes (entry, then each street's exit).
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
	var head := nodes.slice(0, CHAIN_PREVIEW)
	return "%s→…(%d more)→%d" % [_arrow(head), nodes.size() - CHAIN_PREVIEW - 1, nodes[-1]]

func _arrow(nodes: Array) -> String:
	var parts: PackedStringArray = []
	for k in nodes:
		parts.append(str(k))
	return "→".join(parts)

# Angle between two cars' current travel directions, in degrees (0 = same way).
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
	var deg := rad_to_deg(atan2(f.x, -f.z))
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx := int(round(deg / 45.0)) % 8
	if idx < 0:
		idx += 8
	return dirs[idx]

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
	f.store_string("# Stuck report — run %s\n" % _run_stamp)
	f.store_string(("# %d permanently-stuck root(s) captured (cap %d, max %d per node, "
		+ "first %ds ignored). Followers/queues excluded; normal light waits can't qualify.\n\n")
		% [_events.size(), MAX_EVENTS, MAX_PER_NODE, GRACE_MS / 1000])
	if _events.is_empty():
		f.store_string("_No permanently stuck cars yet._\n")
	else:
		f.store_string("\n\n".join(_events))
		f.store_string("\n")
	f.close()
