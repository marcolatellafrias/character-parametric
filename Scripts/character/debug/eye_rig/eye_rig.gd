class_name EyeRig
extends Node

## OJOS 3D — PRUEBA TEMPORAL. Se borra entero si el look no convence.
##
## Anima las mallas de ojo que vinieron del .glb —parpadeo y mirada— en TODOS los personajes de la
## escena.
##
## Solo MOVIMIENTO: el material de los párpados y de la nariz lo pone `CharacterAppearance.MESH_ROLE`,
## que es donde vive esa decisión. Acá hubo un rato una copia del material de la cabeza; se sacó al
## registrarlos como piel, porque dos dueños del mismo material terminan peleándose.
##
## Para borrarlo: esta carpeta + las dos líneas que lo instancian en `player_controller.gd`.
##
## ── UN SOLO NODO PARA TODOS ───────────────────────────────────────────────────────────────────────
## Los personajes se descubren solos recorriendo el grupo de cápsulas, así que los que spawneen después
## quedan incluidos sin que nadie los registre. Es el mismo patrón que `CharacterDebugView`, y evita
## meterle un nodo a `BoneInstantiator` — que además implicaría `add_child` durante la construcción del
## personaje, cosa que ya rompió el juego dos veces.
##
## **Cada personaje lleva su propio reloj.** Con uno compartido, una calle entera parpadea al unísono y
## eso se lee como un error de motor, no como un grupo de personas.
##
## ── POR QUÉ LES SACA EL SKIN ──────────────────────────────────────────────────────────────────────
## Las ocho mallas vienen skinneadas y pesadas **100% al hueso `head`** (medido). O sea que se mueven
## rígidas con la cabeza: el skinning no aporta deformación, solo las ata.
##
## Pero mientras tengan skin las posiciona el esqueleto, y escribirles el transform no hace nada. Como
## el rig no tiene huesos de párpado ni de ojo (53 huesos, ninguno), tampoco hay qué animar desde ahí.
## La salida es sacarles el skin y colocarlas por transform. Si mañana se les ponen huesos propios,
## esto se borra y la animación pasa al rig, que es donde corresponde.
##
## ── LA REFERENCIA ES EL BIND DEL SKIN ─────────────────────────────────────────────────────────────
## Godot dibuja una malla skinneada como `pose_del_hueso · bind_pose · vértice`, y el `bind_pose` lo
## trae el `Skin` del .glb. **No** es lo mismo que `get_bone_global_rest()`, aunque se parezcan: usando
## el reposo del hueso los ojos se iban fuera de la cabeza. Tomando el bind, la fórmula reproduce
## exactamente lo que hacía el skinning y en reposo no se mueve ni un milímetro.

const MESHES := {
	"left eyeball":        ["L", "ball"],
	"left pupil":          ["L", "pupil"],
	"left higher eyelid":  ["L", "upper"],
	"left lower eyelid":   ["L", "lower"],
	"right eyeball":       ["R", "ball"],
	"right pupil":         ["R", "pupil"],
	"right higher eyelid": ["R", "upper"],
	"right lower eyelid":  ["R", "lower"],
}

const HEAD_BONE := "head"

## La ceja es UN solo plano para las dos, asi que va aparte de las partes por lado.
const BROWS_MESH := "brows_plane_mesh"
## Cuanto sube y baja la ceja, en radianes. Chico: una ceja que se mueve mucho se lee como una mueca.
const BROW_RAISE := 0.085
const BROW_SPEED := 0.55
## Cuanto acompana la ceja a la mirada vertical. Mirar arriba levanta la ceja sin pensarlo, y es lo que
## hace que la cara se lea viva en vez de tener dos partes independientes.
const BROW_FOLLOW_GAZE := 0.55

## Cuánto gira cada párpado al cerrar, en radianes. El de arriba hace casi todo el trabajo, como en una
## cara real, y van con signos opuestos porque uno baja y el otro sube.
##
## El signo del par salió invertido en la primera versión —el "parpadeo" abría los ojos de más— porque
## el sentido depende de cómo quedó orientado el eje izquierda-derecha que se deduce de la geometría, y
## eso no se puede saber sin mirarlo.
const UPPER_CLOSE := 0.62
const LOWER_CLOSE := -0.22

## Cuanta autoridad tiene `eye_openness` sobre el parpado. Sin esto, la apertura de reposo compartia
## escala con el parpadeo y la diferencia entre arquetipos casi no se leia: el rango util completo
## quedaba en unos pocos grados.
const REST_SCALE := 1.7
## Cuanto puede ABRIR de mas un arquetipo con `eye_openness` > 1, en las mismas unidades que el cierre.
const REST_OPEN_MAX := 0.7

const BLINK_TIME := 0.13
## ⚠ ACELERADO PARA PROBAR. Los realistas son 2.0 y 6.5 — a ese ritmo, con un parpadeo de 0.13 s, es
## fácil no verlo nunca. Subilos cuando el movimiento te guste.
const BLINK_MIN := 0.7
const BLINK_MAX := 1.8

## Cuánto se mueve el ojo, en radianes de giro del globo. La pupila va pegada porque son la misma
## esfera: se les aplica la MISMA rotación alrededor del mismo centro.
const LOOK_YAW := 0.30
const LOOK_PITCH := 0.16
## Los ojos se mueven a SALTOS (sacadas), no suave: el viaje es corto y la espera larga.
const LOOK_HOLD_MIN := 0.35
const LOOK_HOLD_MAX := 1.2
const LOOK_MOVE := 0.07

## Vagabundeo lento por encima de las sacadas. Un ojo nunca está perfectamente quieto, y sin esto entre
## salto y salto la mirada queda congelada — que es lo que delata que hay una máquina atrás.
const DRIFT_AMOUNT := 0.22
const DRIFT_SPEED := 0.8

## Cada cuánto se buscan personajes nuevos. No hace falta por frame: un personaje que aparece con los
## ojos quietos durante medio segundo no se nota.
const SCAN_EVERY := 0.5

static var VERBOSE := false


## El estado de UN personaje. Todo lo que sigue es por instancia, incluidos los relojes.
class Eyes:
	var bi: BoneInstantiator
	var skel: Skeleton3D
	var head_idx := -1
	var parts := {}          # "L"/"R" -> {"ball": MeshInstance3D, ...}
	var offsets := {}        # MeshInstance3D -> bind pose
	var pivots := {}         # "L"/"R" -> centro del globo, en espacio de hueso de cabeza
	var axis_right := Vector3.RIGHT
	var axis_up := Vector3.UP
	var ok := false

	# Ceja: un solo plano, con su propio bind y su pivote en el medio de los dos ojos.
	var brows: MeshInstance3D = null
	var brows_bind := Transform3D.IDENTITY
	var brow_pivot := Vector3.ZERO

	# Del arquetipo. Ver EntityArchetype.eye_openness y compania.
	var openness := 1.0
	var restless := 1.0
	var blink_mult := 1.0

	var blink := 0.0
	var blink_t := 0.0
	var next_blink := 0.0
	var look := Vector2.ZERO
	var look_target := Vector2.ZERO
	var look_t := 0.0
	var next_look := 0.0
	# Fase propia del vagabundeo: sin esto dos personajes al lado derivan idéntico.
	var phase := 0.0


var _rigs: Dictionary = {}     # id del BoneInstantiator -> Eyes
var _scan_t := 0.0
var _time := 0.0


func _log(msg: String) -> void:
	if VERBOSE:
		print("[EyeRig] ", msg)


func _process(delta: float) -> void:
	_time += delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		_scan()

	for key in _rigs.keys():
		var e: Eyes = _rigs[key]
		if not is_instance_valid(e.bi) or not is_instance_valid(e.skel):
			_rigs.erase(key)
			continue
		if e.ok:
			_animate(e, delta)


## Busca personajes sin rig y los prepara. El grupo de cápsulas es el mismo que usa
## `CharacterDebugView.apply_all`, así que incluye al jugador y a todo lo que spawnee.
func _scan() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for rb in tree.get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		var bi := (rb as Node).get_parent() as BoneInstantiator
		if not is_instance_valid(bi):
			continue
		var key := bi.get_instance_id()
		if _rigs.has(key):
			continue
		var e := Eyes.new()
		e.bi = bi
		_rigs[key] = e
		_setup(e)


func _setup(e: Eyes) -> void:
	if not is_instance_valid(e.bi) or not is_instance_valid(e.bi.skinned_body):
		return
	e.skel = e.bi.skinned_body.skeleton
	if not is_instance_valid(e.skel):
		return
	e.head_idx = e.skel.find_bone(HEAD_BONE)
	if e.head_idx < 0:
		return

	var found := _collect(e.skel)
	if found.is_empty():
		return

	for mi in found:
		var bind := _bind_pose_of(e, mi)
		# Sin skin, la malla se dibuja donde diga su transform, que de acá en más lo escribimos nosotros.
		mi.skin = null
		mi.skeleton = NodePath("")

		var entry: Array = MESHES[mi.name]
		var side: String = entry[0]
		if not e.parts.has(side):
			e.parts[side] = {}
		e.parts[side][entry[1]] = mi
		e.offsets[mi] = bind

	for side in e.parts:
		var ball: MeshInstance3D = e.parts[side].get("ball")
		if is_instance_valid(ball):
			e.pivots[side] = e.offsets[ball] * ball.get_aabb().get_center()

	_setup_brows(e)
	_derive_axes(e)

	# Personalidad por arquetipo. Un viejo entrecerrado y un nene inquieto se distinguen mas por esto
	# que por cualquier otra cosa de la cara.
	var arch := e.bi.entity_instantiation.arch_final if e.bi.entity_instantiation != null else null
	if arch != null:
		e.openness = arch.eye_openness
		e.restless = arch.gaze_restlessness
		e.blink_mult = maxf(arch.blink_rate, 0.05)

	# Relojes desfasados desde el arranque, para que no parpadeen todos juntos.
	e.next_blink = randf_range(0.0, BLINK_MAX)
	e.next_look = randf_range(0.0, LOOK_HOLD_MAX)
	e.phase = randf() * TAU
	e.ok = not e.pivots.is_empty()
	_log("personaje listo: %d mallas, lados %s" % [found.size(), str(e.parts.keys())])


## ── LOS EJES SE DEDUCEN DE LA GEOMETRÍA, NO SE ASUMEN ─────────────────────────────────────────────
## Una versión anterior giraba sobre `Vector3.RIGHT` en espacio de cabeza, dando por sentado que ese
## era el eje izquierda-derecha. No lo es: el hueso de cabeza tiene su propia orientación, así que los
## párpados giraban sobre un eje cualquiera y se iban para el costado en vez de cerrar.
##
##   derecha  = del ojo izquierdo al derecho
##   adelante = del centro del globo al centro de la pupila — la pupila está adelante por definición
##   arriba   = el producto cruz de los dos
## La ceja se maneja igual que los parpados: sin skin y colocada por transform. Su pivote es el punto
## medio entre los dos ojos, para que suba y baje como una sola pieza en vez de girar sobre un extremo.
func _setup_brows(e: Eyes) -> void:
	var found := _find_named(e.skel, BROWS_MESH)
	if found == null:
		return
	e.brows_bind = _bind_pose_of(e, found)
	found.skin = null
	found.skeleton = NodePath("")
	e.brows = found
	if e.pivots.has("L") and e.pivots.has("R"):
		e.brow_pivot = (e.pivots["L"] + e.pivots["R"]) * 0.5
	elif not e.pivots.is_empty():
		e.brow_pivot = e.pivots.values()[0]


func _find_named(node: Node, wanted: String) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == wanted:
		return node
	for c in node.get_children():
		var r := _find_named(c, wanted)
		if r != null:
			return r
	return null


func _derive_axes(e: Eyes) -> void:
	if e.pivots.has("L") and e.pivots.has("R"):
		var d: Vector3 = e.pivots["R"] - e.pivots["L"]
		if d.length_squared() > 1e-8:
			e.axis_right = d.normalized()

	var side: String = "L" if e.parts.has("L") else ("R" if e.parts.has("R") else "")
	if side == "" or not e.pivots.has(side):
		return
	var pupil: MeshInstance3D = e.parts[side].get("pupil")
	if not is_instance_valid(pupil):
		return
	var pc: Vector3 = e.offsets[pupil] * pupil.get_aabb().get_center()
	var fwd: Vector3 = pc - e.pivots[side]
	if fwd.length_squared() > 1e-8:
		e.axis_up = e.axis_right.cross(fwd.normalized()).normalized()


## La matriz de bind que el Skin asocia al hueso de cabeza. Es la que Godot usa para dibujar la malla
## skinneada, así que es la única referencia correcta para reemplazarla por un transform propio.
func _bind_pose_of(e: Eyes, mi: MeshInstance3D) -> Transform3D:
	var sk: Skin = mi.skin
	if sk == null:
		return Transform3D.IDENTITY
	for k in sk.get_bind_count():
		var b: int = sk.get_bind_bone(k)
		if b < 0:
			var nm: String = sk.get_bind_name(k)
			if nm != "":
				b = e.skel.find_bone(nm)
		if b == e.head_idx:
			return sk.get_bind_pose(k)
	if sk.get_bind_count() == 1:
		return sk.get_bind_pose(0)
	_log("no encontré el bind del hueso de cabeza en '%s'" % mi.name)
	return Transform3D.IDENTITY


func _collect(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and MESHES.has(node.name):
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect(c))
	return out


func _animate(e: Eyes, delta: float) -> void:
	_tick_blink(e, delta)
	_tick_look(e, delta)

	# Dos frecuencias que no encajan, para que el patrón no se repita a un ritmo que el ojo aprenda.
	var t := _time + e.phase
	var drift := Vector2(sin(t * DRIFT_SPEED), sin(t * DRIFT_SPEED * 0.61 + 1.7)) * DRIFT_AMOUNT
	var aim := (e.look + drift) * e.restless

	# EL PARPADEO ARRANCA DESDE LA APERTURA DE REPOSO, no desde el ojo abierto: un arquetipo
	# entrecerrado tiene el parpado a medio bajar todo el tiempo y el parpadeo lo termina de cerrar.
	#
	# El piso del clamp es NEGATIVO a proposito. Con el piso en 0, un `eye_openness` por encima de 1
	# no hacia absolutamente nada —el nene no podia abrir mas que el resto— porque el valor de reposo
	# le quedaba por debajo y se recortaba. Ahora abrir de mas es tan posible como cerrar de mas.
	var rest: float = (1.0 - e.openness) * REST_SCALE
	var lid: float = clampf(rest + e.blink, -REST_OPEN_MAX, 1.0)

	var head_now := e.skel.global_transform * e.skel.get_bone_global_pose(e.head_idx)
	for side in e.parts:
		var pivot: Vector3 = e.pivots[side]
		# El globo y la pupila giran juntos: son la misma esfera.
		var look := Basis(e.axis_up, aim.x * LOOK_YAW) * Basis(e.axis_right, aim.y * LOOK_PITCH)
		_place(e, side, "ball", head_now, pivot, look)
		_place(e, side, "pupil", head_now, pivot, look)
		_place(e, side, "upper", head_now, pivot, Basis(e.axis_right, lid * UPPER_CLOSE))
		_place(e, side, "lower", head_now, pivot, Basis(e.axis_right, lid * LOWER_CLOSE))

	_place_brows(e, head_now, t, aim)


## Coloca una parte: gira `rot` alrededor de `pivot` (en espacio de hueso de cabeza) y la lleva al mundo.
##
## "Rotar alrededor de un punto" es trasladar al pivote, rotar y volver. Se escribe como una sola
## composición porque el origen de estas mallas es (0,0,0) y no sirve de pivote.
func _place(e: Eyes, side: String, role: String, head_now: Transform3D, pivot: Vector3, rot: Basis) -> void:
	var mi: MeshInstance3D = e.parts[side].get(role)
	if not is_instance_valid(mi):
		return
	var about := Transform3D(rot, pivot - rot * pivot)
	mi.global_transform = head_now * about * e.offsets[mi]


## La ceja combina tres cosas: un vaiven lento propio, el acompanamiento de la mirada vertical, y un
## tiron hacia arriba al abrir despues de parpadear. Sin ese tercero, el parpadeo se ve como si solo
## los parpados estuvieran vivos.
func _place_brows(e: Eyes, head_now: Transform3D, t: float, aim: Vector2) -> void:
	if not is_instance_valid(e.brows):
		return
	var idle: float = sin(t * BROW_SPEED) * 0.5 + sin(t * BROW_SPEED * 0.43 + 2.1) * 0.5
	var raise_amt: float = idle * 0.6 + aim.y * BROW_FOLLOW_GAZE - e.blink * 0.4
	var rot := Basis(e.axis_right, raise_amt * BROW_RAISE * e.restless)
	var about := Transform3D(rot, e.brow_pivot - rot * e.brow_pivot)
	e.brows.global_transform = head_now * about * e.brows_bind


func _tick_blink(e: Eyes, delta: float) -> void:
	if e.blink_t > 0.0:
		e.blink_t = maxf(0.0, e.blink_t - delta)
		# Medio parpadeo bajando y medio subiendo: un seno sobre medio ciclo da eso sin guardar estado.
		e.blink = sin((1.0 - e.blink_t / BLINK_TIME) * PI)
		if e.blink_t <= 0.0:
			e.blink = 0.0
		return
	e.next_blink -= delta
	if e.next_blink <= 0.0:
		e.blink_t = BLINK_TIME
		e.next_blink = randf_range(BLINK_MIN, BLINK_MAX) / e.blink_mult


func _tick_look(e: Eyes, delta: float) -> void:
	if e.look_t > 0.0:
		e.look_t = maxf(0.0, e.look_t - delta)
		e.look = e.look.lerp(e.look_target, clampf(1.0 - e.look_t / LOOK_MOVE, 0.0, 1.0))
		return
	e.next_look -= delta
	if e.next_look <= 0.0:
		e.look_target = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		e.look_t = LOOK_MOVE
		e.next_look = randf_range(LOOK_HOLD_MIN, LOOK_HOLD_MAX) / maxf(e.restless, 0.05)

