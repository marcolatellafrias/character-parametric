extends Node

## PRUEBA HEADLESS DEL LOCKOUT (ver CollisionAvoidance), sin ciudad: un registro de reclamos, un obstáculo
## fijo cruzando un carril recto y dos autos con ruta de un solo tramo, en cola. Corre con
##
##     godot --headless --path . res://Scenes/tests/traffic_lockout.tscn --quit-after 2000
##
## y escribe `[LockoutTest] PASS` o `FAIL` en la consola. Lo que verifica:
##   1. El de adelante se para ante el obstáculo, espera `LOCKOUT_AFTER` y sigue de largo.
##   2. El de atrás, en cola detrás de un auto parado, NO se destraba por su cuenta: drena cuando el de
##      adelante sigue, y recién ante el obstáculo se destraba él.
## Existe porque estos casos son imposibles de reproducir a mano en la ciudad: hay que esperar a que pasen.

const DT := 1.0 / 60.0
const LANE_END := Vector3(0.0, 1.0, 200.0)
const OBSTACLE_Z := 100.0
const DEADLINE := 25.0

var _registry: TrafficClaimRegistry
var _leader: FlyingCar
var _follower: FlyingCar
var _t := 0.0
var _frame := 0
var _done := false


func _ready() -> void:
	_registry = TrafficClaimRegistry.new()
	add_child(_registry)
	_registry.register_obstacle(PackedVector3Array([Vector3(-10.0, 1.0, OBSTACLE_Z), Vector3(10.0, 1.0, OBSTACLE_Z)]), 2.0)
	_leader = _car(Vector3(0.0, 1.0, 60.0))
	_follower = _car(Vector3(0.0, 1.0, 40.0))


func _car(at: Vector3) -> FlyingCar:
	var car := FlyingCar.new()
	car.claim_registry = _registry
	car.initialize_from_seed(7)
	car.setup()
	car.set_path(at, LANE_END, 0.0, 0.5, 0.0, {"face_idx": 0, "edge_idx": 0}, 3, 10)
	return car


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	_t += DT
	_leader.tick(DT, 0.0, _frame)
	_follower.tick(DT, 0.0, _frame)

	var leader_lockouts: int = _leader.collision_avoidance.lockouts
	var follower_lockouts: int = _follower.collision_avoidance.lockouts
	if leader_lockouts == 0 and follower_lockouts > 0:
		_finish(false, "el de atrás se destrabó antes que el de adelante (t=%.1f)" % _t)
		return
	var leader_past := _leader.sim_transform.origin.z > OBSTACLE_Z + 4.0
	var follower_past := _follower.sim_transform.origin.z > OBSTACLE_Z + 4.0
	if leader_past and follower_past:
		_finish(true, "los dos pasaron el obstáculo a t=%.1f · lockouts: líder %d, seguidor %d"
			% [_t, leader_lockouts, follower_lockouts])
	elif _t > DEADLINE:
		_finish(false, "a t=%.1f: líder z=%.1f (lockouts %d) · seguidor z=%.1f (lockouts %d)"
			% [_t, _leader.sim_transform.origin.z, leader_lockouts, _follower.sim_transform.origin.z, follower_lockouts])


func _finish(passed: bool, detail: String) -> void:
	_done = true
	print("[LockoutTest] %s — %s" % ["PASS" if passed else "FAIL", detail])
	_leader.dispose()
	_leader.free()
	_follower.dispose()
	_follower.free()
	get_tree().quit()
