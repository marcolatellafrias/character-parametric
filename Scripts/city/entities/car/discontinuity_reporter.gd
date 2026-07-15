# DiscontinuityReporter.gd — regression guard for teleports and orientation
# snaps. Both are meant to be IMPOSSIBLE (the route is immutable and the bridge
# profile ramps smoothly), so this should stay empty forever — but "impossible"
# bugs are exactly what the bridge-clip guard caught. So it's a cheap trip-wire
# before/after the collision rebuild.
#
# It flags neither steep curves nor fast turns (those are legitimate) — only
# DISCONTINUITY: a car moving farther in one sample than its speed allows
# (teleport), or its facing rotating a large angle while it barely moved (a
# one-frame snap, versus a smooth turn spread over many frames).
extends RefCounted
class_name DiscontinuityReporter

const REPORT_PATH: String = "res://discontinuity_report.md"
const MAX_EVENTS: int = 20
const POS_FACTOR: float = 2.0        # allowed move = speed × dt × factor + slack
const POS_SLACK: float = 3.0         # absolute slack (m) so tiny jitter never trips
# A true SNAP is rotation with essentially NO travel — an orientation glitch.
# Rotation WITH travel is curvature (a fast car on a tight corner: 60° over
# 1.5m is a ~1.4m-radius bend, legitimate path geometry), so it must not trip
# this. Field data showed the old thresholds (60° within 2m) flagged exactly
# those fast corners; tightened to near-zero travel only.
const SNAP_DEG: float = 45.0
const SNAP_MAX_MOVE: float = 0.5

var _events: Array[String] = []
var _seen: Dictionary = {}           # car_id -> true (one report per car)
var _last: Dictionary = {}           # car_id -> {pos, head, t}
var _run_stamp: String = ""

func _init() -> void:
	_run_stamp = Time.get_datetime_string_from_system()
	_write()

## Called on a short cadence (a long interval would average a teleport into
## normal motion and miss it). Uses dt, so the exact cadence doesn't matter
## for correctness, only for sensitivity.
func consider(cars: Array) -> void:
	var now := Time.get_ticks_msec()
	var fresh: Dictionary = {}
	for car in cars:
		if not is_instance_valid(car):
			continue
		var id: String = car.car_id
		var pos: Vector3 = car.sim_transform.origin
		var head: Vector3 = car.sim_transform.basis.z
		fresh[id] = {"pos": pos, "head": head, "t": now}
		if _events.size() >= MAX_EVENTS or _seen.has(id):
			continue
		var prev = _last.get(id)
		if prev == null:
			continue
		var dt: float = (now - int(prev["t"])) / 1000.0
		if dt <= 0.0:
			continue
		var moved: float = (prev["pos"] as Vector3).distance_to(pos)
		var allowed: float = car.speed * dt * POS_FACTOR + POS_SLACK
		var head_deg: float = rad_to_deg((prev["head"] as Vector3).angle_to(head))
		if moved > allowed:
			_seen[id] = true
			_events.append(_summ_teleport(car, prev["pos"], pos, moved, allowed, dt, now))
			_write()
		elif head_deg > SNAP_DEG and moved < SNAP_MAX_MOVE:
			_seen[id] = true
			_events.append(_summ_snap(car, head_deg, moved, now))
			_write()
	_last = fresh

func _summ_teleport(car, from: Vector3, to: Vector3, moved: float,
		allowed: float, dt: float, now: int) -> String:
	var pc = car.path_controller
	var prog: float = pc.get_progress()
	var j: Vector3 = to - from
	# A mostly-vertical jump implicates the bridge profile layer; a horizontal one
	# implicates the route/curve.
	var axis: String = "VERTICAL (profile layer)" if absf(j.y) > absf(j.x) + absf(j.z) \
		else "horizontal (route/curve)"
	return ("## Teleport %d  (t=+%.0fs)\n"
		+ "  %s %s — moved %.1fm in %.0fms (max ~%.1f), jump (%.1f, %.1f, %.1f) %s\n"
		+ "  speed %.1f m/s, profile lift %.1f") % [
		_events.size() + 1, now / 1000.0,
		_short(car.car_id), CarArchetypes.Type.keys()[car.car_archetype],
		moved, dt * 1000.0, allowed, j.x, j.y, j.z, axis,
		car.collision_avoidance.current_speed, pc.profile_offset(prog)]

func _summ_snap(car, deg: float, moved: float, now: int) -> String:
	var pc = car.path_controller
	var prog: float = pc.get_progress()
	# profile lift > 0 → likely a bridge-pitch snap at a profile knot;
	# ~0 → a tight bezier turn (a sharp corner). The XZ pins the location.
	return ("## Heading snap %d  (t=+%.0fs)\n"
		+ "  %s %s — facing rotated %.0f° while moving only %.2fm\n"
		+ "  speed %.1f m/s, profile lift %.1f, at %.1f,%.1f,%.1f") % [
		_events.size() + 1, now / 1000.0,
		_short(car.car_id), CarArchetypes.Type.keys()[car.car_archetype],
		deg, moved, car.collision_avoidance.current_speed,
		pc.profile_offset(prog),
		car.global_position.x, car.global_position.y, car.global_position.z]

static func _short(id: String) -> String:
	return id.substr(maxi(id.length() - 4, 0))

func _write() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# Discontinuity report — run %s\n" % _run_stamp)
	f.store_string("# %d teleport/snap event(s) captured (cap %d). Should be EMPTY — a regression alarm.\n\n"
		% [_events.size(), MAX_EVENTS])
	if _events.is_empty():
		f.store_string("_No discontinuities yet._\n")
	else:
		f.store_string("\n\n".join(_events))
		f.store_string("\n")
	f.close()
