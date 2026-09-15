class_name Ship
extends RigidBody3D

## LA NAVE DE LA COMPAÑÍA — prototipo de un jugador.
##
## El casco —un domo de vidrio o una caja, ver ShipHull—, los asientos (ver ShipHull.seat_sides), la consola de vuelo con tres
## controles y el botón de encendido, y la compuerta trasera con un botón adentro y otro afuera (ver
## ShipDoor). Ver conceptual/ship-gameplay.md.
##
## ── ENCENDIDO ───────────────────────────────────────────────────────────────────────────────────
## Arranca apagada. Apagada no aplica ninguna fuerza propia: es un cuerpo más, apoyado donde esté, y
## apagarla en el aire la deja caer. Prendida zumba (ver TestSounds), y la meta de altura arranca en la
## altura a la que está.
##
## ── EL MODELO DE VUELO ──────────────────────────────────────────────────────────────────────────
## Viene de la nave vieja (`Scripts/common/simple.gd`, commit 6f0f288), con los mismos mecanismos:
##
##   · ALTURA POR META. La palanca no empuja la nave: mueve una altitud objetivo, y la nave va hacia
##     ella. Soltarla = la nave se queda a esa altura. Es el "ralentí" del loop: alguien baja a
##     repartir y la nave espera flotando, sin nadie en los controles.
##   · AVANCE hacia donde mira, y GIRO sobre el eje vertical.
##   · ANTI-DERRAPE: la velocidad lateral se frena, para que se sienta volar y no patinar en hielo.
##   · AUTOENDEREZADO: la nave vuelve sola a quedar horizontal.
##
## Dos cambios respecto de aquella:
##
##   · La altura es GLOBAL, no sobre el suelo. La vieja medía con un rayo hacia abajo; en una ciudad
##     de puentes y veredas flotantes, "sobre el suelo" salta cada vez que la nave pasa por encima de
##     algo.
##   · Todo se expresa como ACELERACIÓN y se multiplica por la masa. Las ganancias de la vieja eran
##     fuerzas crudas, afinadas para un cuerpo de 1 kg: cambiar la masa desafinaba todo. Así la masa
##     queda libre para lo que importa, que es que lo que la nave lleva adentro no la mueva.
##
## ⚠ SIN INCLINACIÓN AL GIRAR NI AL ACELERAR por ahora (`bank_amount` y `tilt_amount` en 0). En la
## vieja eran cosméticas porque no tenía interior. Acá inclinan el PISO, y el personaje tiene
## fricción cero: se desliza. Se pueden subir más adelante, a propósito, si queremos que la carga se
## mueva en las curvas.
##
## ⚠ NO ESTÁ EN RED. La hace aparecer el panel de debug, solo en esta máquina, y los controles de sus
## dashboards piden su `Claim` al host por el path del nodo: con otro jugador conectado, esos pedidos
## apuntan a una nave que allá no existe.

## Mucho más pesada que cualquier cosa que lleve adentro: si no, un jugador caminando hacia un costado
## la inclinaría y el autoenderezado se la pasaría peleando contra él.
const MASS := 2000.0
const SEAT_SCENE := "res://Scenes/ship/working_seat.tscn"
## Aire entre las rodillas del piloto y el plano de abajo de la consola de vuelo. Las rodillas caen en el
## borde de adelante del asiento (ver BoneInstantiator._pose_root), a la altura de la pelvis, y el
## asiento va lo más cerca que eso deja (ver `_add_seats`).
const KNEE_CLEARANCE := 0.08
## Cuánto por encima del borde de arriba del tablero va la mira del piloto (ver SeatInteractable, ALTURA).
## Así ve la ventana por encima de la consola, y todos los controles le quedan abajo: el rayo les entra
## desde arriba, nunca rasante.
const EYE_OVER_PANEL := 0.2
## Cuántos grados recorre una palanca de punta a punta.
const LEVER_TRAVEL_DEG := 70.0
## Hasta dónde gira el volante para cada lado, en radianes (~86°): ahí dobla a fondo y hace tope.
const WHEEL_FULL_LOCK := 1.5

const GROUP := "ship"

## ── PAREDES TRASLÚCIDAS — ayuda de depuración ───────────────────────────────────────────────────
## En true, la cáscara opaca de la caja (paredes, techo y compuerta) se dibuja medio transparente: desde
## afuera se ve cómo el personaje agarra las palancas y el volante. El piso y las consolas quedan opacos:
## sin piso no se lee dónde está parado nadie. El domo no se toca: ya es de vidrio, y sus partes opacas lo
## son a propósito.
##
## Estado global, como los toggles de CharacterDebugView: una nave que aparece después nace con lo que
## esté prendido. Prendido por default.
static var translucent_walls := true


static func toggle_translucent_walls(tree: SceneTree) -> void:
	translucent_walls = not translucent_walls
	for node in tree.get_nodes_in_group(GROUP):
		var ship := node as Ship
		if ship != null:
			ship.apply_wall_visibility()


## Un casco nuevo de la forma `ship_shape`, sin armar.
static func hull_for(ship_shape: Shape) -> ShipHull:
	match ship_shape:
		Shape.BOX:
			return BoxHull.large()
		Shape.SMALL_BOX:
			return BoxHull.small()
	return DomeHull.new()


## Qué casco lleva: todavía se prueban las formas (ver ShipHull) —el domo, y la caja grande y la chica (ver
## BoxHull)—. Se elige antes de meterla al árbol.
enum Shape { DOME, BOX, SMALL_BOX }
@export var shape := Shape.DOME
## Para cuántos jugadores está armada: cuántos asientos lleva y frente a qué consolas (ver
## ShipHull.seat_sides). Se elige antes de meterla al árbol.
@export var crew_size := 1

@export_group("Altura")
## Metros por segundo que sube o baja la meta con la palanca a fondo.
@export var climb_speed := 3.0
## Cuánto error de altura se convierte en velocidad vertical deseada (1/s).
@export var altitude_gain := 1.5
@export var max_vertical_speed := 4.0
## Qué tan rápido la velocidad vertical alcanza la deseada (1/s).
@export var vertical_response := 4.0
@export var max_vertical_accel := 8.0
## Altura global mínima y máxima de la meta. La mínima en 0: la nave arranca en el piso.
@export var min_altitude := 0.0
## Cuántos PISOS por debajo del límite del mundo tiene que quedar el techo de la nave. Es el número que
## importa, no los metros: el límite son 13 pisos (`City.impassable_floors`), así que con 5 de margen la
## nave llega a 8 y no lo pasa nunca — que es exactamente para lo que el límite existe. Antes esto era un
## 53,5 escrito a mano que había que recalcular cada vez que se movía la muralla; una vez estuvo en 90 m
## y la nave se escapaba por arriba. Cambiarlo obliga a revisar `NeighborhoodTypes.FLOORS`, que se
## calibra contra el techo resultante.
@export var ceiling_margin_floors := 5.0
## Techo de respaldo en metros, para cuando no hay ciudad que publique el límite (ver `_max_altitude`).
@export var fallback_max_altitude := 53.5

@export_group("Avance")
## Velocidad hacia adelante con el acelerador a fondo, en m/s.
@export var max_speed := 18.0
@export var speed_response := 1.2
@export var max_accel := 6.0
## Qué tan rápido se frena el derrape lateral (1/s).
@export var lateral_grip := 8.0
## Tope del anti-derrape, APARTE del de avance. Al girar, la velocidad tiene que rotar junto con la nave,
## y eso pide una aceleración lateral de v·ω: a 18 m/s girando a 0.9 rad/s son 16 m/s². Con el mismo
## tope que el avance (6) la nave derrapaba de costado a 15 m/s en cada curva — medido en headless.
@export var max_lateral_accel := 20.0

@export_group("Giro")
## Velocidad de giro con el volante a fondo, en rad/s.
@export var max_yaw_rate := 0.9
@export var yaw_response := 3.0
@export var max_yaw_accel := 2.0

@export_group("Estabilidad")
## Resorte y amortiguación del autoenderezado. Amortiguación crítica = 2·√resorte: con 25 y 10 la nave
## vuelve a quedar horizontal sin pasarse ni oscilar.
@export var upright_stiffness := 25.0
@export var upright_damping := 10.0
## Inclinación al girar y al acelerar, en radianes. En 0 a propósito: ver el aviso de arriba.
@export var bank_amount := 0.0
@export var tilt_amount := 0.0

## Entradas de los controles, normalizadas: vertical y giro de −1 a 1, acelerador de 0 a 1.
var input_vertical := 0.0
var input_steering := 0.0
var input_throttle := 0.0
var target_altitude := 0.0
## Ver ENCENDIDO, arriba.
var powered := false

var _altitude_ready := false
var _door: ShipDoor = null
## El casco armado: la forma, con lo que la nave le pregunta (anillo, asientos, centro de masa).
var hull: ShipHull = null
var _shell: Array[MeshInstance3D] = []
var _hum: AudioStreamPlayer3D = null


func _ready() -> void:
	mass = MASS
	can_sleep = false
	# El modelo de vuelo es lo único que frena la nave: sin damping del motor encima, lo que se ve es
	# exactamente lo que dicen las perillas de arriba.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	hull = hull_for(shape)
	# Centro de masa fijo, el del volumen del casco. Calculado de las formas se correría al abrir la
	# compuerta —que se mueve— y la nave se inclinaría sola cada vez.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = hull.center_of_mass()

	add_to_group(GROUP)

	_hum = TestSounds.hum_player()
	_hum.position = center_of_mass
	add_child(_hum)
	var parts := hull.build(self, {0: _flight_preset()})
	_shell = parts.shell
	apply_wall_visibility()

	_door = ShipDoor.new()
	_door.name = "Door"
	add_child(_door)
	_door.setup(parts.door_motion)
	for button in parts.door_buttons:
		var touch := _control(button, 0) as TouchComponent
		if touch != null:
			_door.connect_button(touch)

	_add_seats()
	_wire_flight(parts.consoles[0])
	_ignore_own_bodies(self)


func apply_wall_visibility() -> void:
	for mesh in _shell:
		if is_instance_valid(mesh):
			ShipHull.set_translucent(mesh, translucent_walls)


## Consola de vuelo: el tablero del módulo principal del frente, de 32 × 12 celdas en las dos formas (ver
## ShipHull). Todo va contra el borde de ABAJO, el más cercano al piloto (la
## grilla crece de la pared hacia él), con el volante centrado, una palanca a cada lado y el encendido
## junto al acelerador, todos pegados: el margen de cada control ya deja aire entre vecinos.
##
##   ┌────────────────────────────────────────┐  fila 0: lado de la pared
##   │        [alt][   volante   ][acel]       │
##   │        [alt][   volante   ][acel][o]    │  fila 11: lado del piloto
##   └────────────────────────────────────────┘
##
## El orden de los slots es el orden en que se crean los controles (`ctrl_0` … `ctrl_3`), y
## `_wire_flight` depende de él.
func _flight_preset() -> DashboardPreset:
	var slots: Array[DashboardSlot] = [
		_slot(Vector2i(4, 0), _lever(true, 0.5)),     # altura: vuelve al medio
		_slot(Vector2i(10, 0), _wheel()),             # giro: vuelve al centro
		_slot(Vector2i(22, 0), _lever(false, 0.0)),   # acelerador: se queda donde lo dejás
		_slot(Vector2i(28, 10), _power_button()),     # encendido: queda prendido o apagado
	]
	var preset := DashboardPreset.new()
	preset.fill_remaining_random = false
	preset.fixed_slots = slots
	return preset


func _lever(springs_back: bool, rest: float) -> ControlDefinition:
	var d := ControlArchetype.definition_of("lever")
	d.max_angle_degrees = LEVER_TRAVEL_DEG
	d.auto_return = springs_back
	d.default_value = rest
	# Que la palanca quede DERECHA en reposo: la de altura descansa en el medio del recorrido, así que
	# su rotación base se corre para atrás lo mismo que el reposo la corre para adelante.
	d.rest_rotation_deg = Vector3(-LEVER_TRAVEL_DEG * rest, 0.0, 0.0)
	return d


func _wheel() -> ControlDefinition:
	var d := ControlArchetype.definition_of("wheel")
	# Mientras se gira, la vista acompaña la mitad que con el resto de los controles.
	d.camera_sensitivity_factor = 0.15
	d.rotate_max = WHEEL_FULL_LOCK
	return d


func _power_button() -> ControlDefinition:
	return ControlArchetype.definition_of("power")


static func _slot(cell: Vector2i, definition: ControlDefinition) -> DashboardSlot:
	var s := DashboardSlot.new()
	s.cell = cell
	s.definition = definition
	return s


## El control N de un dashboard: los crea en el orden de su preset y los nombra `ctrl_N`.
static func _control(dash: ProceduralDashboard, index: int) -> ControllableInteractable:
	return dash.get_node_or_null("ctrl_%d/Control" % index) as ControllableInteractable


func _wire_flight(dash: ProceduralDashboard) -> void:
	var altitude := _control(dash, 0)
	var wheel := _control(dash, 1)
	var throttle := _control(dash, 2)
	var power := _control(dash, 3)
	if altitude != null:
		altitude.state_changed.connect(func(v: float) -> void: input_vertical = (v - 0.5) * 2.0)
	if wheel != null:
		# Horario, visto por el piloto, es valor negativo (ver RotatingComponent) y es doblar a la derecha.
		wheel.state_changed.connect(
			func(v: float) -> void: input_steering = clampf(-v / WHEEL_FULL_LOCK, -1.0, 1.0))
	if throttle != null:
		throttle.state_changed.connect(func(v: float) -> void: input_throttle = v)
	if power != null:
		power.state_changed.connect(func(v: float) -> void: set_powered(v >= 0.5))


func set_powered(on: bool) -> void:
	if on == powered:
		return
	powered = on
	# Al prender, la meta de altura se vuelve a tomar donde está la nave (ver `_integrate_forces`).
	_altitude_ready = false
	if on:
		_hum.play()
	else:
		_hum.stop()


func _add_seats() -> void:
	var scene := load(SEAT_SCENE) as PackedScene
	if scene == null:
		return
	var sides := hull.console_sides()
	for side_index in hull.seat_sides(crew_size):
		assert(side_index in hull.console_indices(), "Ship: no hay consola en el lado %d" % side_index)
		var seat := scene.instantiate() as SeatInteractable
		seat.name = "pilot_seat" if side_index == 0 else "seat_%d" % side_index
		seat.eye_height = ShipHull.panel_top_height() + EYE_OVER_PANEL
		# Las rodillas se meten bajo el tablero lo que el plano de abajo deja a su altura. Se planea con la de
		# un arquetipo medio: a los que se sientan más alto les queda menos lugar.
		var knee_room := ShipHull.knee_room_at(seat.typical_height())
		var from_hinge := seat.seat_area.z * 0.5 + KNEE_CLEARANCE - knee_room
		# Mirando a su consola: un asiento sin rotar mira a −Z (el frente), y girarlo −θ lo pone a mirar
		# hacia afuera en el rumbo θ de la consola, igual que la consola misma (ver ShipHull._build_console).
		var theta := float(side_index) * TAU / sides
		var outward := Vector3(sin(theta), 0.0, -cos(theta))
		seat.transform = Transform3D(Basis(Vector3.UP, -theta),
			outward * (hull.console_apothem() - from_hinge) + Vector3.UP * ShipHull.WALL)
		add_child(seat)


## La nave no choca con sus propias piezas móviles. Los controles de los dashboards son StaticBody3D y
## el asiento tiene su propio cuerpo, todos ADENTRO del volumen de la nave: sin esto el motor los
## resuelve como una intersección y empuja la nave desde adentro.
func _ignore_own_bodies(node: Node) -> void:
	for child in node.get_children():
		if child is PhysicsBody3D:
			add_collision_exception_with(child)
		_ignore_own_bodies(child)


## EL TECHO, derivado del límite del mundo y no escrito a mano: la ciudad publica su altura
## infranqueable y cuánto mide un piso, y la nave se queda `ceiling_margin_floors` por debajo. Sin ciudad
## —una escena de prueba, la nave suelta— cae al número de respaldo.
func _max_altitude() -> float:
	if WorldSettings.impassable_height <= 0.0 or WorldSettings.floor_height <= 0.0:
		return fallback_max_altitude
	return maxf(WorldSettings.impassable_height - ceiling_margin_floors * WorldSettings.floor_height,
		min_altitude)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Apagada, ninguna fuerza propia: la gravedad la aplica el motor, así que cae o se apoya sola.
	if not powered:
		return
	var dt := state.step
	var origin := state.transform.origin
	var b := state.transform.basis
	var v := state.linear_velocity
	var w := state.angular_velocity

	# La meta arranca donde está la nave, no en 0: aparecida sobre una vereda, iría a buscar el 0.
	if not _altitude_ready:
		target_altitude = maxf(origin.y, min_altitude)
		_altitude_ready = true
	target_altitude = clampf(target_altitude + input_vertical * climb_speed * dt, min_altitude, _max_altitude())

	# ── Traslación: altura, avance y anti-derrape ────────────────────────────────────────────────
	# Cascada: error de altura → velocidad vertical deseada → aceleración. Es el PD de la nave vieja,
	# pero con topes que se leen en m/s y m/s² en vez de en newtons.
	var vy_target := clampf((target_altitude - origin.y) * altitude_gain, -max_vertical_speed, max_vertical_speed)
	var ay := clampf((vy_target - v.y) * vertical_response, -max_vertical_accel, max_vertical_accel)

	# Adelante y costado APLANADOS: con la nave apenas inclinada, avanzar no tiene que subir ni bajar.
	var forward := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var a_forward := clampf((input_throttle * max_speed - v.dot(forward)) * speed_response, -max_accel, max_accel)
	var a_side := clampf(-v.dot(right) * lateral_grip, -max_lateral_accel, max_lateral_accel)

	var accel := Vector3.UP * ay + forward * a_forward + right * a_side
	# `- total_gravity`: el motor aplica la gravedad por su cuenta, así que compensarla acá hace que
	# flotar a altura fija no le cueste nada al controlador — la nave queda exactamente en la meta, sin
	# el hundimiento de régimen que tiene un resorte que además sostiene el peso.
	state.apply_central_force((accel - state.total_gravity) * mass)

	# ── Rotación: autoenderezado y giro ──────────────────────────────────────────────────────────
	var target_up := Vector3.UP
	if bank_amount != 0.0:
		target_up = target_up.rotated(forward, input_steering * bank_amount)
	if tilt_amount != 0.0:
		target_up = target_up.rotated(right, input_throttle * tilt_amount)
	# `up × target_up` es el eje sobre el que hay que girar para enderezarse, con largo sen(ángulo).
	var tilt_error := b.y.cross(target_up.normalized())
	var w_tilt := w - Vector3.UP * w.dot(Vector3.UP)   # todo menos el giro sobre la vertical
	var alpha := tilt_error * upright_stiffness - w_tilt * upright_damping
	# Volante positivo = giro a la derecha = velocidad angular negativa sobre +Y, como en la vieja.
	var yaw_rate_target := -input_steering * max_yaw_rate
	alpha += Vector3.UP * clampf((yaw_rate_target - w.y) * yaw_response, -max_yaw_accel, max_yaw_accel)
	# Aceleración angular → torque, con la inercia real que el motor calcula a partir de las formas.
	state.apply_torque(state.inverse_inertia_tensor.inverse() * alpha)
