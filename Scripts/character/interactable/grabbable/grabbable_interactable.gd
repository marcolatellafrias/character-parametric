class_name GrabbableInteractable
extends Interactable
## Los puntos de agarre del cuerpo que cuelga de este nodo, y el SOLVER del agarre: acá se juntan
## todas las manos que lo sostienen y se resuelve una sola vez, en vez de que cada agarrador aplique
## su propia fuerza por su cuenta.
##
## El modelo prioriza ESTABILIDAD sobre realismo (ver conceptual/multiplayer.md, "Grab rework"), y
## son dos sistemas de segundo orden DESACOPLADOS, ambos críticamente amortiguados:
##
## - **Posición**: la fuerza va siempre al centro del cuerpo (`apply_central_force`), nunca al grab
##   point. Aplicarla off-center acopla traslación y rotación en un lazo realimentado (la fuerza
##   rota el cuerpo → el grab point se mueve → cambia la fuerza) y ese lazo es el que hacía oscilar
##   la caja larga para siempre. Cada mano implica una posición del cuerpo (su target menos su
##   offset rotado); el objetivo es el promedio.
## - **Orientación**: explícita, no emergente, y siempre la MISMA restricción: alinear un eje del
##   cuerpo con un eje que definen los agarres. Con dos o más manos, el eje entre los dos grab
##   points más separados se alinea con el eje entre sus targets. Con una sola mano, el eje
##   centro→grab point se alinea apuntando de vuelta al pecho del agarrador: **lo que agarraste es
##   lo que te queda de frente**, y el resto del objeto se extiende para el otro lado. Agarrar una
##   caja larga de la punta la deja apuntando en tu dirección de vista; agarrarla del medio la deja
##   de costado. Así el grab point importa también con un solo agarrador, y sin caso especial.
##
## Por eso dos agarradores dejan de ser un problema: sobre la posición son dos resortes tirando de
## UN punto, y un punto no tiene orientación que sobre-determinar.

var grab_points: Array[Node3D] = []

const CELL_SIZE      := 0.15
## Una celda de grab points cada tantas celdas del objeto: más chico = más puntos. A 3, una caja
## cúbica de 6 celdas tiene 8 puntos en vez de 1, así que el punto que engancha el agarre queda
## mucho más cerca de donde apuntaste — y por eso cuesta más perder el grip (el agarre se suelta
## cuando ESE punto se va del cono o de la distancia de grip, no el objeto entero).
const GRAB_DENSITY   := 3
const HANDLE_DENSITY := 4

## Constante de tiempo del seguimiento (s): cuánto tarda el objeto en llegar a donde apuntás. Es el
## único parámetro de "feel" — la rigidez y la amortiguación se DERIVAN de él y de la masa
## (k = m·ω², c = 2·m·ω), así que el sistema es crítico siempre: no hay overshoot ni oscilación, y
## no hay ganancias que tunear por objeto. Más chico = más firme.
const RESPONSE_TIME     := 0.08
const ANG_RESPONSE_TIME := 0.12
## Fuerza (N) y torque (N·m) por unidad de `strenght` del arquetipo. Como la rigidez escala con la
## masa, todo objeto responde igual de rápido: lo que hace que el peso SE SIENTA es este techo. La
## fuerza incluye sostener el propio peso del objeto, así que si la fuerza combinada de los
## agarradores no llega a m·g el objeto cuelga — que es el feedback legible de "vení a ayudarme".
##
## Con `strenght` entre 0.3 (el pibe) y 1.2 (el fuerte) y las cajas de debug (4/8/40/80 kg), 1600
## da: las livianas las mueve cualquiera; la pesada cuadrada (40 kg = 392 N) la sostiene uno solo
## con margen para maniobrar; la pesada larga (80 kg = 784 N) deja a un arquetipo medio justo en el
## límite (la sostiene pero no la maneja) y entre dos va cómoda. Es EL número a tocar si el peso no
## se siente bien: son newtons por unidad de fuerza, nada más.
const FORCE_PER_STRENGTH  := 1600.0
const TORQUE_PER_STRENGTH := 300.0
## Una mano se descarta si dejó de refrescarse (el agarrador se desconectó o perdió el stream).
const HOLD_TIMEOUT_MS := 200
## Clave de la mano local cuando no hay red (offline no hay peer id).
const LOCAL_HOLD := 0

## Manos que sostienen el cuerpo. key (peer id, o LOCAL_HOLD) ->
## {offset: Vector3 local, target: Vector3 mundo, origin: Vector3 mundo (el pecho), strength, t}
var _holds: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)  # sólo corre mientras alguien lo sostiene

# ── Manos ─────────────────────────────────────────────────────────────────────

## Registra/refresca una mano. La llama cada frame quien agarra: el agarrador local directo, o
## NetBody al recibir la intención de un co-grabber remoto.
func set_hold(key: int, offset_local: Vector3, target_world: Vector3, origin_world: Vector3, strength: float) -> void:
	_holds[key] = {"offset": offset_local, "target": target_world, "origin": origin_world,
		"strength": strength, "t": Time.get_ticks_msec()}
	set_physics_process(true)

func clear_hold(key: int) -> void:
	_holds.erase(key)

func clear_all_holds() -> void:
	_holds.clear()

func hold_count() -> int:
	return _holds.size()

# ── Solver ────────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	_expire_holds()
	if _holds.is_empty():
		set_physics_process(false)
		return
	var body := get_parent() as RigidBody3D
	if not is_instance_valid(body) or not _simulates(body):
		return
	body.sleeping = false
	_solve_position(body)
	_solve_orientation(body)

func _expire_holds() -> void:
	var now := Time.get_ticks_msec()
	for key in _holds.keys():
		if now - int((_holds[key] as Dictionary)["t"]) > HOLD_TIMEOUT_MS:
			_holds.erase(key)

## Sólo resuelve quien simula el cuerpo: offline siempre, en red la autoridad de su NetBody. Los
## demás lo siguen (NetBody._follow_reference) y no tocan las fuerzas.
func _simulates(body: RigidBody3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	for child in body.get_children():
		if child is NetBody:
			return (child as NetBody).is_multiplayer_authority()
	return true  # sin NetBody (p.ej. la cápsula de un compañero): lo maneja su propio sistema

func _solve_position(body: RigidBody3D) -> void:
	var basis := body.global_transform.basis
	var desired := Vector3.ZERO
	for h in _holds.values():
		desired += (h["target"] as Vector3) - basis * (h["offset"] as Vector3)
	desired /= float(_holds.size())

	var omega := 1.0 / RESPONSE_TIME
	var m     := body.mass
	var force := (desired - body.global_position) * (m * omega * omega) \
		- body.linear_velocity * (2.0 * m * omega)
	force -= body.get_gravity() * m  # sostener el peso propio; cuenta contra el techo
	body.apply_central_force(force.limit_length(_total_strength() * FORCE_PER_STRENGTH))

func _solve_orientation(body: RigidBody3D) -> void:
	# Si el error es identidad (p.ej. dos manos en el mismo punto) igual seguimos: el término de
	# amortiguación solo ya frena cualquier giro suelto, que es lo que queremos.
	var err := _orientation_error(body)
	if err.w < 0.0:
		err = -err  # camino corto
	var angle := err.get_angle()
	var axis  := err.get_axis() if angle > 0.0001 else Vector3.ZERO

	var omega     := 1.0 / ANG_RESPONSE_TIME
	# El término de amortiguación pega sobre TODA la velocidad angular, así que el giro que la
	# restricción no fija (el roll alrededor del eje entre las dos manos) queda frenado, no libre.
	var ang_accel := axis * angle * (omega * omega) - body.angular_velocity * (2.0 * omega)

	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null:
		return
	var inv_inertia := state.inverse_inertia_tensor
	if is_zero_approx(inv_inertia.determinant()):
		return  # ejes bloqueados / inercia degenerada: sin torque
	var torque := inv_inertia.inverse() * ang_accel  # τ = I·α
	body.apply_torque(torque.limit_length(_total_strength() * TORQUE_PER_STRENGTH))

## Rotación que falta aplicarle al cuerpo: siempre la que alinea un eje del cuerpo con un eje que
## definen los agarres. El giro que la restricción no fija queda amortiguado, no libre.
func _orientation_error(body: RigidBody3D) -> Quaternion:
	var basis := body.global_transform.basis

	# Una sola mano: el eje centro→grab point apunta de vuelta al pecho, así que la parte que
	# agarraste te queda de frente y el resto del objeto se extiende para el otro lado.
	if _holds.size() < 2:
		var only: Dictionary = _holds.values()[0]
		return _swing(basis * (only["offset"] as Vector3),
			(only["origin"] as Vector3) - (only["target"] as Vector3))

	var a: Dictionary = {}
	var b: Dictionary = {}
	var best := -1.0
	var vals := _holds.values()
	for i in range(vals.size()):
		for j in range(i + 1, vals.size()):
			var d: float = ((vals[i]["offset"] as Vector3) - (vals[j]["offset"] as Vector3)).length_squared()
			if d > best:
				best = d
				a = vals[i]
				b = vals[j]
	return _swing(basis * ((b["offset"] as Vector3) - (a["offset"] as Vector3)),
		(b["target"] as Vector3) - (a["target"] as Vector3))

## Rotación mínima que lleva `from_axis` sobre `to_axis`. Identidad si alguno es degenerado (agarre
## justo en el centro del cuerpo, o dos manos en el mismo punto): ahí no hay eje que definir y la
## orientación queda sólo amortiguada.
func _swing(from_axis: Vector3, to_axis: Vector3) -> Quaternion:
	if from_axis.length_squared() < 0.0001 or to_axis.length_squared() < 0.0001:
		return Quaternion.IDENTITY
	return Quaternion(from_axis.normalized(), to_axis.normalized())

func _total_strength() -> float:
	var total := 0.0
	for h in _holds.values():
		total += h["strength"] as float
	return total

func add_grab_point_local(local_pos: Vector3) -> void:
	var pt := Node3D.new()
	pt.position = local_pos
	add_child(pt)
	grab_points.append(pt)

func get_nearest_grab_point(world_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for pt in grab_points:
		if not is_instance_valid(pt):
			continue
		var d := pt.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = pt
	return best

func setup_from_cells(cells_x: int, cells_y: int, cells_z: int) -> void:
	var sx := cells_x * CELL_SIZE
	var sy := cells_y * CELL_SIZE
	var sz := cells_z * CELL_SIZE
	_generate_grab_points(cells_x, cells_y, cells_z, sx, sy, sz)
	_generate_handle_points(cells_x, cells_y, cells_z, sx, sy, sz)

func get_prompt() -> String:
	return "[LMB] to grab"

## El grabbable cuelga del cuerpo que representa; se contornea el objeto entero, no el grabbable
## (que solo contiene puntos de grab/handle, no la malla visible).
func get_outline_targets() -> Array[Node]:
	var parent := get_parent()
	var targets: Array[Node] = [parent if is_instance_valid(parent) else self]
	return targets

func _generate_grab_points(cx: int, cy: int, cz: int, sx: float, sy: float, sz: float) -> void:
	var nx := ceili(cx / float(GRAB_DENSITY))
	var ny := ceili(cy / float(GRAB_DENSITY))
	var nz := ceili(cz / float(GRAB_DENSITY))
	for ix in nx:
		for iy in ny:
			for iz in nz:
				add_grab_point_local(Vector3(
					-sx * 0.5 + (ix + 0.5) * sx / nx,
					-sy * 0.5 + (iy + 0.5) * sy / ny,
					-sz * 0.5 + (iz + 0.5) * sz / nz
				))

func _generate_handle_points(cx: int, cy: int, cz: int, sx: float, sy: float, sz: float) -> void:
	var faces: Array = [
		[ sx * 0.5, cy, cz, sy, sz, 0],
		[-sx * 0.5, cy, cz, sy, sz, 0],
		[ sy * 0.5, cx, cz, sx, sz, 1],
		[-sy * 0.5, cx, cz, sx, sz, 1],
		[ sz * 0.5, cx, cy, sx, sy, 2],
		[-sz * 0.5, cx, cy, sx, sy, 2],
	]
	for face in faces:
		var fc: float  = face[0]
		var na         := ceili((face[1] as int) / float(HANDLE_DENSITY))
		var nb         := ceili((face[2] as int) / float(HANDLE_DENSITY))
		var sa: float  = face[3]
		var sb: float  = face[4]
		var axis: int  = face[5]
		for ia in na:
			for ib in nb:
				var pa  := -sa * 0.5 + (ia + 0.5) * sa / na
				var pb  := -sb * 0.5 + (ib + 0.5) * sb / nb
				var pos := Vector3.ZERO
				match axis:
					0: pos = Vector3(fc, pa, pb)
					1: pos = Vector3(pa, fc, pb)
					2: pos = Vector3(pa, pb, fc)
				add_handle_point_local(pos)

func show_debug_points() -> void:
	for pt in grab_points:
		if not is_instance_valid(pt):
			continue
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.CYAN
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # visibles atravesando el mesh
		mi.material_override = mat
		mi.set_meta("no_outline", true)  # nunca contornear los puntos de debug
		pt.add_child(mi)

	for pt in handle_points:
		if not is_instance_valid(pt):
			continue
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.YELLOW
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # visibles atravesando el mesh
		mi.material_override = mat
		mi.set_meta("no_outline", true)  # nunca contornear los puntos de debug
		pt.add_child(mi)
