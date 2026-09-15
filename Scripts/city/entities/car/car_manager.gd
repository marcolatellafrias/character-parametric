# CarManager.gd — single simulation loop for the whole car fleet.
# Cars are plain Objects (see FlyingCar): no per-node _process callbacks, no
# scene-tree membership. The manager computes camera positions once per frame,
# ticks every car, despawns cars beyond the spawn ring, and owns a pool of
# MeshInstance3D visuals attached only to cars inside the fog wall — a fully
# fogged car is pure data with no node, no mesh and no transform updates.
extends Node3D
class_name CarManager

# El visual vive mientras el auto este dentro del radio de spawn, que es donde existe el auto: se sueltan
# juntos. Antes se soltaba en el corte por distancia de las mallas, que ya no existe —la ciudad se dibuja
# entera y la niebla es lo unico que esconde—.

var cars: Array[FlyingCar] = []

var _frame: int = 0
var _camera_xz: PackedVector2Array = PackedVector2Array()
var _visual_pool: Array[MeshInstance3D] = []

func _ready() -> void:
	add_to_group("car_manager")

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
	cars[index] = cars[cars.size() - 1]
	cars.pop_back()
	if car.visual:
		_set_engine(car.visual, false)
		_visual_pool.append(car.detach_visual())
	car.dispose()
	car.free()

# ============================================================================
# VISUAL POOL
# ============================================================================

func _update_visual(car: FlyingCar, dist: float) -> void:
	if dist < WorldSettings.spawn_radius:
		if car.visual == null:
			car.visual = _acquire_visual(car)
		if not car.visual.visible:
			car.visual.visible = true
			_set_engine(car.visual, true)
		car.visual.global_transform = car.sim_transform
	elif car.visual:
		_set_engine(car.visual, false)
		_visual_pool.append(car.detach_visual())

func _acquire_visual(car: FlyingCar) -> MeshInstance3D:
	var mi: MeshInstance3D
	if _visual_pool.is_empty():
		mi = MeshInstance3D.new()
		# El motor nace con el visual y se poolea con él: un auto sin visual está fuera del radio de
		# dibujado, o sea lejos, o sea que tampoco tiene que sonar. Así no hay un solo nodo de audio de más.
		mi.add_child(TestSounds.engine_player())
		add_child(mi)
	else:
		mi = _visual_pool.pop_back()
	mi.mesh = car.get_shared_mesh()
	_set_engine(mi, true)
	return mi


## Prende o apaga el motor de un visual. No hace nada si ese visual no lo tiene.
static func _set_engine(mi: MeshInstance3D, on: bool) -> void:
	if mi == null:
		return
	var player := mi.get_node_or_null("engine") as AudioStreamPlayer3D
	if player == null:
		return
	if on:
		if not player.playing:
			player.play()
	else:
		player.stop()

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
