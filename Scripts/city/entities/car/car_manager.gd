# CarManager.gd — single simulation loop for the whole car fleet.
# Cars are plain Objects (see FlyingCar): no per-node _process callbacks, no
# scene-tree membership. The manager computes camera positions once per frame,
# ticks every car, despawns cars beyond the spawn ring, and owns a pool of
# MeshInstance3D visuals attached only to cars inside the fog wall — a fully
# fogged car is pure data with no node, no mesh and no transform updates.
extends Node3D
class_name CarManager

# Visuals are released a margin past the fog wall (where they are invisible
# anyway) so a car oscillating on the boundary doesn't churn the pool.
const VISUAL_RELEASE_MARGIN: float = 10.0
# Diagnostics cadence (frames). Deadlocks persist for seconds → coarse scan;
# clips are transient (a car passes through in ~1s) → finer scan.
const STUCK_SCAN_INTERVAL: int = 15
const CLIP_SCAN_INTERVAL: int = 5
const DISC_SCAN_INTERVAL: int = 2    # short: a long gap would hide a teleport in normal motion
const HEALTH_SCAN_INTERVAL: int = 60 # heartbeat samples itself every 10s anyway
const LIGHT_SCAN_INTERVAL: int = 30

## Diagnostic reports, one file each in the project root, overwritten per run:
## stuck_report.md (permanently stuck roots), clip_report.md (car/bridge
## clips), discontinuity_report.md (teleports/snaps), traffic_health.md
## (flow heartbeat), light_watchdog.md (lights that stop cycling).
@export var record_diagnostics: bool = true

var cars: Array[FlyingCar] = []

var _frame: int = 0
var _camera_xz: PackedVector2Array = PackedVector2Array()
var _visual_pool: Array[MeshInstance3D] = []
var _stuck_reporter: StuckReporter = null
var _clip_reporter: ClipReporter = null
var _disc_reporter: DiscontinuityReporter = null
var _health: TrafficHealth = null
var _light_watchdog: LightWatchdog = null

func _ready() -> void:
	add_to_group("car_manager")
	if record_diagnostics:
		_stuck_reporter = StuckReporter.new()
		_clip_reporter = ClipReporter.new()
		_disc_reporter = DiscontinuityReporter.new()
		_health = TrafficHealth.new()
		_light_watchdog = LightWatchdog.new()

func _process(delta: float) -> void:
	var effective_delta := delta
	if DebugController.is_paused:
		effective_delta = DebugController.frame_delta
		if effective_delta == 0.0:
			return

	_frame += 1
	_gather_camera_positions()

	var i := 0
	while i < cars.size():
		var car := cars[i]

		var dist := _min_camera_distance_xz(car.sim_transform.origin)
		if dist > WorldSettings.spawn_radius:
			_despawn_at(i)
			continue

		car.tick(effective_delta, dist, _frame)
		if car.pending_despawn:
			_despawn_at(i)
			continue

		_update_visual(car, dist)
		i += 1

	if _stuck_reporter != null and _frame % STUCK_SCAN_INTERVAL == 0:
		_stuck_reporter.consider(cars)
	if _clip_reporter != null and _frame % CLIP_SCAN_INTERVAL == 0:
		_clip_reporter.consider(cars)
	if _disc_reporter != null and _frame % DISC_SCAN_INTERVAL == 0:
		_disc_reporter.consider(cars)
	if _health != null and _frame % HEALTH_SCAN_INTERVAL == 0:
		_health.consider(cars)
	if _light_watchdog != null and _frame % LIGHT_SCAN_INTERVAL == 0:
		_light_watchdog.consider(get_tree().get_nodes_in_group("traffic_planes"))

func _exit_tree() -> void:
	for car in cars:
		car.dispose()
		car.free()
	cars.clear()

## Register a freshly spawned car; attach a visual immediately if it is inside
## the fog wall (bootstrap spawns can be in full view of the player).
func add_car(car: FlyingCar) -> void:
	cars.append(car)
	_gather_camera_positions()
	var dist := _min_camera_distance_xz(car.sim_transform.origin)
	if dist <= WorldSettings.spawn_radius:
		_update_visual(car, dist)

# Swap-remove: publish order within a frame doesn't matter because cars query
# the registry's completed read buffer from the previous frame.
func _despawn_at(index: int) -> void:
	var car := cars[index]
	if _health != null and car.pending_despawn:
		_health.completed_routes += 1   # finished its route (vs. distance-culled)
	cars[index] = cars[cars.size() - 1]
	cars.pop_back()
	if car.visual:
		_visual_pool.append(car.detach_visual())
	car.dispose()
	car.free()

# ============================================================================
# VISUAL POOL
# ============================================================================

func _update_visual(car: FlyingCar, dist: float) -> void:
	if dist < WorldSettings.render_distance:
		if car.visual == null:
			car.visual = _acquire_visual(car)
		if not car.visual.visible:
			car.visual.visible = true
		car.visual.global_transform = car.sim_transform
	elif car.visual:
		if dist >= WorldSettings.render_distance + VISUAL_RELEASE_MARGIN:
			_visual_pool.append(car.detach_visual())
		elif car.visual.visible:
			car.visual.visible = false

func _acquire_visual(car: FlyingCar) -> MeshInstance3D:
	var mi: MeshInstance3D
	if _visual_pool.is_empty():
		mi = MeshInstance3D.new()
		add_child(mi)
	else:
		mi = _visual_pool.pop_back()
	mi.mesh = car.get_shared_mesh()
	return mi

# ============================================================================
# CAMERAS
# ============================================================================

# Camera positions are gathered once per frame from every AreaInstantiator, so
# a car near ANY player is kept alive (per-car camera lookups disappear).
func _gather_camera_positions() -> void:
	_camera_xz.clear()
	for node in get_tree().get_nodes_in_group("area_instantiator"):
		for camera in node.cameras:
			if camera and is_instance_valid(camera):
				var p: Vector3 = camera.global_position
				_camera_xz.append(Vector2(p.x, p.z))

func _min_camera_distance_xz(pos: Vector3) -> float:
	var min_dist := INF
	var p := Vector2(pos.x, pos.z)
	for c in _camera_xz:
		min_dist = minf(min_dist, p.distance_to(c))
	return min_dist
