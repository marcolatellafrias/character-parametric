class_name CarBody
extends RigidBody3D

## EL CUERPO DE UN AUTO NPC MIENTRAS ALGUIEN ESTÁ CERCA — la colisión pasiva de los autos que se mueven (ver
## PassiveBodies para los quietos). El auto sigue siendo su simulación (FlyingCar: una ruta, un transform,
## nada de física, lo que se sincroniza); este cuerpo existe solo cuando un jugador o una nave están a
## `CarManager.BODY_RADIUS`, y pasa por tres fases:
##
##   · CINEMÁTICO, mientras nadie lo toca: congelado en modo cinemático y llevado cada cuadro al transform
##     del simulado. Sigue la ruta EXACTA —curvas, arranques, lo que sea—, empuja a quien se le cruce y no
##     lo mueve nadie. Un cuerpo dinámico persiguiendo al simulado con fuerzas no puede hacer esto: en una
##     curva o un arranque se queda atrás y se "pierde" sin que nadie lo haya tocado.
##   · RECUPERÁNDOSE, desde el primer contacto real con algo que puede golpearlo (una cápsula, una nave, un
##     cuerpo suelto): se vuelve dinámico con la velocidad que traía, recibe el golpe de verdad, y un
##     controlador de fuerzas lo lleva de vuelta a la ruta —tirado hacia un punto `LEAD_M` adelante—
##     mientras EL SIMULADO LO ESPERA (ver CarManager._update_body): su progreso es la proyección del cuerpo
##     sobre la ruta. Por eso un toque nunca lo "pierde": lo que persigue está siempre al lado. Cuando vuelve
##     a estar sobre la ruta y derecho, vuelve a ser cinemático y el simulado sigue.
##   · CAÍDO, si el golpe lo saca `LOST_DISTANCE` de la ruta o lo da vuelta: gravedad, sin controlador, con
##     el impulso que traía. El simulado se despide del tráfico y el cuerpo queda como chatarra hasta que
##     descansa. Se lee como "salió despedido", no como un intento de estabilizarse que falla.
##
## Es `top_level` y se coloca con su transform GLOBAL: el CarManager cuelga de un nodo que no está en el
## origen. Todo esto es local: los golpes no viajan por la red todavía.

enum Phase { KINEMATIC, RECOVERING, FALLEN }

const MASS := 900.0
## Cuánto de la distancia al objetivo se cierra por segundo, y con qué tope de aceleración. Bajos a
## propósito: un golpe tiene que verse como un golpe antes de que el auto se acomode.
const FOLLOW_GAIN := 3.0
const MAX_ACCEL := 20.0
## Torque hacia la orientación de la ruta: rigidez y amortiguación, como `Ship.upright_*`.
const TURN_STIFFNESS := 10.0
const TURN_DAMPING := 3.5
## Recuperándose, hacia qué punto de la ruta se lo tira (metros adelante de su proyección).
const LEAD_M := 3.0
## Con esto de desvío lateral y de inclinación, ya está de vuelta.
const RESUME_DISTANCE := 0.4
const RESUME_TILT := 0.15
## A partir de acá el auto ya no vuelve: distancia al objetivo, o inclinación respecto de la vertical.
const LOST_DISTANCE := 8.0
const LOST_TILT := 1.2
## Cuánto tiene que descansar la chatarra antes de irse.
const FALLEN_REST := 4.0

var phase := Phase.KINEMATIC
var target := Transform3D.IDENTITY
var target_velocity := Vector3.ZERO
## La última velocidad del simulado: con ella arranca dinámico al primer golpe.
var sim_velocity := Vector3.ZERO
var _rest := 0.0


## El cuerpo de `car`, con la caja del arquetipo y su malla. Quien lo cuelga le pone el transform GLOBAL
## del simulado después de agregarlo al árbol.
static func create(car: FlyingCar) -> CarBody:
	var body := CarBody.new()
	body.top_level = true
	body.mass = MASS
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.continuous_cd = true
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(car.width, car.height, car.depth)
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.mesh = car.get_shared_mesh()
	body.add_child(visual)
	body.target = car.sim_transform
	body.body_entered.connect(body._on_contact)
	return body


## Cinemático: adónde está el simulado este cuadro, y a qué velocidad va.
func drive(sim: Transform3D, velocity: Vector3) -> void:
	sim_velocity = velocity
	if phase == Phase.KINEMATIC:
		global_transform = sim


## Recuperándose: hacia dónde de la ruta se lo tira, y a qué velocidad va la ruta ahí.
func follow(lead: Transform3D, lead_velocity: Vector3) -> void:
	target = lead
	target_velocity = lead_velocity


## De vuelta sobre la ruta: cinemático otra vez.
func resume() -> void:
	if phase != Phase.RECOVERING:
		return
	phase = Phase.KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## El primer contacto con algo que puede golpearlo lo vuelve dinámico, con la velocidad que traía: el
## golpe lo recibe de verdad. Una pared o un auto estacionado dormido (estático) no cuentan.
func _on_contact(other: Node) -> void:
	if phase != Phase.KINEMATIC or not _can_hit(other):
		return
	phase = Phase.RECOVERING
	freeze = false
	linear_velocity = sim_velocity
	angular_velocity = Vector3.ZERO


static func _can_hit(other: Node) -> bool:
	if other.is_in_group(CharacterRigidBody3D.CHARACTER_GROUP) or other.is_in_group(Ship.GROUP):
		return true
	var rigid := other as RigidBody3D
	return rigid != null and not rigid.freeze


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if phase != Phase.RECOVERING:
		return
	var xf := state.transform
	var to_target := target.origin - xf.origin
	if to_target.length() > LOST_DISTANCE or xf.basis.y.angle_to(Vector3.UP) > LOST_TILT:
		wreck()
		return
	# Posición: la velocidad que querría tener es la de la ruta más lo que le falta para alcanzar el punto
	# de adelante, y la fuerza cierra la diferencia con esa velocidad, hasta un tope.
	var desired := target_velocity + to_target * FOLLOW_GAIN
	var accel := ((desired - state.linear_velocity) * FOLLOW_GAIN).limit_length(MAX_ACCEL)
	state.apply_central_force(accel * mass)
	# Orientación: el giro que lo lleva a la base de la ruta, como resorte con amortiguación.
	var delta := (target.basis * xf.basis.transposed()).get_rotation_quaternion()
	var angle := delta.get_angle()
	if angle > PI:
		angle -= TAU
	var axis := delta.get_axis() if absf(angle) > 0.0001 else Vector3.UP
	var alpha := axis * angle * TURN_STIFFNESS - state.angular_velocity * TURN_DAMPING
	state.apply_torque(state.inverse_inertia_tensor.inverse() * alpha)


## Chatarra: gravedad y nada más. Lo decide el cuerpo cuando se pierde, o el CarManager si el golpe lo
## metió adentro de un puente, que un cuerpo cinemático o uno tirado con fuerzas atravesaría.
func wreck() -> void:
	if phase == Phase.FALLEN:
		return
	phase = Phase.FALLEN
	freeze = false
	gravity_scale = 1.0
	can_sleep = true


func _physics_process(delta: float) -> void:
	if phase != Phase.FALLEN:
		return
	if sleeping:
		_rest += delta
		if _rest >= FALLEN_REST:
			queue_free()
	else:
		_rest = 0.0
