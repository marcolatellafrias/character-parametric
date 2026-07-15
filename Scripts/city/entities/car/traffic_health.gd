# TrafficHealth.gd — the heartbeat: is the city flowing or freezing?
#
# None of the incident reports (stuck/clip/discontinuity) can answer that —
# they capture events, not trends. This samples the whole fleet every
# SAMPLE_MS and appends one compact line per sample to
# `res://traffic_health.md` (overwritten each run):
#
#   t=+120s  cars=312  stopped 18% (56)  avg 7.2 m/s  done/min 41  hot: 74(9) 93(7) 47(5)
#
# Reading it: `stopped %` should oscillate with the light cycle around a
# stable value — a steady climb is congestion building; `done/min` (cars
# finishing their routes) collapsing to ~0 while cars>0 is gridlock; `hot`
# names the top nodes by stopped cars, i.e. where to look.
extends RefCounted
class_name TrafficHealth

const REPORT_PATH: String = "res://traffic_health.md"
const SAMPLE_MS: int = 10000
const STOPPED_EPSILON: float = 0.15
const HOT_NODES: int = 3
const MAX_SAMPLES: int = 240   # ~40 min; then stop appending

var completed_routes: int = 0   # incremented by CarManager on route-end despawn

var _lines: Array[String] = []
var _last_sample: int = 0
var _last_completed: int = 0
var _run_stamp: String = ""

func _init() -> void:
	_run_stamp = Time.get_datetime_string_from_system()
	_write()

func consider(cars: Array) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_sample < SAMPLE_MS or _lines.size() >= MAX_SAMPLES:
		return
	var interval_min: float = (now - _last_sample) / 60000.0 if _last_sample > 0 else (SAMPLE_MS / 60000.0)
	_last_sample = now

	var total := cars.size()
	var stopped := 0
	var speed_sum := 0.0
	var node_stopped: Dictionary = {}
	for car in cars:
		var ca = car.collision_avoidance
		if ca == null:
			continue
		speed_sum += ca.current_speed
		if ca.current_speed <= STOPPED_EPSILON:
			stopped += 1
			var node := _node_of(car)
			node_stopped[node] = node_stopped.get(node, 0) + 1

	var done := completed_routes - _last_completed
	_last_completed = completed_routes

	var hot := ""
	var keys := node_stopped.keys()
	keys.sort_custom(func(a, b): return node_stopped[a] > node_stopped[b])
	for i in range(mini(HOT_NODES, keys.size())):
		hot += "%s(%d) " % [str(keys[i]), node_stopped[keys[i]]]

	_lines.append("t=+%4.0fs  cars=%3d  stopped %2.0f%% (%d)  avg %4.1f m/s  done/min %2.0f  hot: %s" % [
		now / 1000.0, total,
		(100.0 * stopped / total) if total > 0 else 0.0, stopped,
		(speed_sum / total) if total > 0 else 0.0,
		(done / interval_min) if interval_min > 0.0 else 0.0,
		hot if hot != "" else "-"])
	_write()

func _node_of(car) -> int:
	var g = car.generator
	var vol: Dictionary = car.current_volume
	var fi: int = vol.get("face_idx", -1)
	if g == null or fi < 0:
		return -1
	return g.plain_graph.faces[fi][vol.get("edge_idx", -1)]

func _write() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# Traffic health — run %s\n" % _run_stamp)
	f.store_string("# One line per %ds. stopped%% steady = fine, climbing = congestion; done/min → 0 = gridlock; hot = nodes with most stopped cars.\n\n"
		% [SAMPLE_MS / 1000])
	if _lines.is_empty():
		f.store_string("_No samples yet._\n")
	else:
		f.store_string("\n".join(_lines))
		f.store_string("\n")
	f.close()
