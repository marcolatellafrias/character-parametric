# LightWatchdog.gd — verifies every traffic light actually cycles.
#
# The stuck report's "at a red light forever" events have two very different
# explanations: the light itself never turned (a light bug), or the light
# turned fine but the queue couldn't drain (congestion/spillback). This
# watchdog settles it independently: it samples every TrafficPlane's
# `is_blocking` and flags any plane that stays RED beyond STUCK_RED_MS —
# comfortably longer than a full cycle, so it can only trip on a genuinely
# stuck light. Healthy output is one line saying all planes toggle.
extends RefCounted
class_name LightWatchdog

const REPORT_PATH: String = "res://light_watchdog.md"
const STUCK_RED_MS: int = 20000   # red this long = stuck (a full cycle is ~10s)
const MAX_EVENTS: int = 20

var _red_since: Dictionary = {}   # instance_id -> msec it went (or was first seen) red
var _flagged: Dictionary = {}     # instance_id -> true (reported once)
var _events: Array[String] = []
var _planes_seen: int = 0
var _toggles_seen: int = 0
var _red_now: int = 0             # planes red at the last sample (context for the header)
var _run_stamp: String = ""

func _init() -> void:
	_run_stamp = Time.get_datetime_string_from_system()
	_write()

## Called periodically by CarManager with the "traffic_planes" group nodes.
func consider(planes: Array) -> void:
	var now := Time.get_ticks_msec()
	_planes_seen = planes.size()
	_red_now = 0
	var dirty := false
	for plane in planes:
		if not is_instance_valid(plane):
			continue
		var pid: int = plane.get_instance_id()
		if plane.is_blocking:
			_red_now += 1
			if not _red_since.has(pid):
				_red_since[pid] = now
			elif not _flagged.has(pid) and now - int(_red_since[pid]) >= STUCK_RED_MS \
					and _events.size() < MAX_EVENTS:
				_flagged[pid] = true
				# traffic_index + position make a flagged plane self-explaining:
				# an index outside {0,1} can never green under a 2-phase cycle,
				# and the position says where to look in-world.
				var vs: Array = plane.get_end_vertices()
				var c: Vector3 = (vs[0] + vs[1] + vs[2] + vs[3]) / 4.0 if vs.size() == 4 else Vector3.ZERO
				_events.append("## Stuck light %d  (t=+%.0fs)\n  lane %s idx=%d — RED for %.0fs (cycle is ~10s) @(%d,%d,%d)" % [
					_events.size() + 1, now / 1000.0,
					str(plane.get_meta("lane_id", "?")), plane.traffic_index,
					(now - int(_red_since[pid])) / 1000.0,
					int(c.x), int(c.y), int(c.z)])
				dirty = true
		else:
			if _red_since.has(pid):
				_toggles_seen += 1
				_red_since.erase(pid)
			if _flagged.erase(pid):
				dirty = true   # it recovered; keep the event but note via rewrite
	# Rewrite periodically so the healthy summary stays fresh.
	if dirty or (_toggles_seen % 50) == 0:
		_write()

func _write() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# Light watchdog — run %s\n" % _run_stamp)
	f.store_string("# %d planes tracked, %d red→green toggles observed, %d red at last sample. A light red >%ds is flagged.\n\n"
		% [_planes_seen, _toggles_seen, _red_now, STUCK_RED_MS / 1000])
	if _events.is_empty():
		f.store_string("_All lights cycling normally._\n")
	else:
		f.store_string("\n\n".join(_events))
		f.store_string("\n")
	f.close()
