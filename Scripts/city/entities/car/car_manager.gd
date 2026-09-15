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

## A cuánto de un jugador o una nave un auto tiene cuerpo (ver CarBody). Más que el de los quietos
## (PassiveBodies): estos se mueven rápido, y el cuerpo tiene que existir antes del encuentro.
const BODY_RADIUS := 25.0

var _frame: int = 0
var _camera_xz: PackedVector2Array = PackedVector2Array()
var _visual_pool: Array[MeshInstance3D] = []
## Los cuerpos de los autos cercanos, por auto, y de dónde venía cada uno (para su velocidad).
var _bodies: Dictionary = {}
var _previous_origin: Dictionary = {}
var _touchers := PackedVector3Array()

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
	_touchers = PassiveBodies.toucher_positions(get_tree())

	var i := 0
	while i < cars.size():
		var car := cars[i]

		var dist := _min_camera_distance_xz(car.sim_transform.origin)
		if dist > WorldSettings.spawn_radius:
			_despawn_at(i)
			continue

		car.tick(effective_delta, dist, _frame)
		_update_body(car, effective_delta)
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
	var body: CarBody = _bodies.get(car)
	if body != null:
		_bodies.erase(car)
		_previous_origin.erase(car)
		# La chatarra se queda hasta descansar; un cuerpo sano se va con su auto.
		if body.phase != CarBody.Phase.FALLEN:
			body.queue_free()
	car.dispose()
	car.free()


## LA COLISIÓN PASIVA DE LOS AUTOS QUE SE MUEVEN (ver CarBody): un cuerpo mientras alguien está a
## `BODY_RADIUS`; ninguno cuando no hay nadie. Cinemático, va donde va el simulado. Recuperándose de un
## golpe, EL SIMULADO LO ESPERA: su progreso es la proyección del cuerpo sobre la ruta y el cuerpo es
## tirado hacia un punto un poco más adelante en ella; de vuelta sobre la ruta, cinemático otra vez y el
## simulado sigue. Caído, el simulado se despide del tráfico y la chatarra queda donde cayó.
func _update_body(car: FlyingCar, delta: float) -> void:
	var origin := car.sim_transform.origin
	var body: CarBody = _bodies.get(car)
	if body != null and body.phase == CarBody.Phase.FALLEN:
		_bodies.erase(car)
		_previous_origin.erase(car)
		car.recovering = false
		car.pending_despawn = true
		return
	var near := false
	for t in _touchers:
		if origin.distance_squared_to(t) < BODY_RADIUS * BODY_RADIUS:
			near = true
			break
	if near and body == null:
		body = CarBody.create(car)
		add_child(body)
		body.global_transform = car.sim_transform
		_bodies[car] = body
		_previous_origin[car] = origin
	elif not near and body != null and body.phase == CarBody.Phase.KINEMATIC:
		_bodies.erase(car)
		_previous_origin.erase(car)
		body.queue_free()
		return
	if body == null:
		return
	var previous: Vector3 = _previous_origin.get(car, origin)
	var sim_velocity := (origin - previous) / maxf(delta, 0.0001)
	_previous_origin[car] = origin
	match body.phase:
		CarBody.Phase.KINEMATIC:
			car.recovering = false
			body.drive(car.sim_transform, sim_velocity)
		CarBody.Phase.RECOVERING:
			car.recovering = true
			# Adentro de un puente no se recupera nadie: el golpe lo metió ahí, y de ahí sale como chatarra. Un
			# cuerpo tirado con fuerzas contra la losa la terminaría atravesando.
			if car.generator != null and BridgePlanner.point_blocked(car.generator, int(car.current_volume.get("face_idx", -1)),
					int(car.current_volume.get("edge_idx", -1)), body.global_position, car.height * 0.5):
				body.wreck()
				return
			var arc := car.path_controller.snap_to(body.global_position)
			car.sim_transform = car.path_controller.get_current_transform()
			var lead_arc := minf(arc + CarBody.LEAD_M, car.path_controller.get_curve_length())
			var lead := Transform3D(car.sim_transform.basis, car.path_controller.sample_profiled(lead_arc))
			body.follow(lead, car.path_controller.get_heading() * car.collision_avoidance.base_speed)
			if body.global_position.distance_to(car.sim_transform.origin) < CarBody.RESUME_DISTANCE \
					and body.global_transform.basis.y.angle_to(Vector3.UP) < CarBody.RESUME_TILT:
				body.resume()
				car.recovering = false

# ============================================================================
# VISUAL POOL
# ============================================================================

func _update_visual(car: FlyingCar, dist: float) -> void:
	# Con cuerpo, el que se ve es el cuerpo (trae su propia malla): el visual del pool vuelve al pool.
	if _bodies.has(car):
		if car.visual:
			_set_engine(car.visual, false)
			_visual_pool.append(car.detach_visual())
		return
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
