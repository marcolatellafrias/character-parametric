class_name SkinnedBodyUtil
extends Node3D

## ESPEJO del rig lógico sobre un Skeleton3D skinneado.
##
## El árbol de CustomBone sigue siendo la ÚNICA fuente de verdad del pose: la IK, el animador
## procedural, anim_mod, el solve sentado y el ragdoll lo siguen manejando como Node3Ds igual que
## antes. Esta clase no anima nada — solo copia ese pose a un Skeleton3D real cada frame, para que
## las mallas skinneadas del modelo de Blender lo sigan.
##
## Ver technical/skinned-character-migration.md. FASE 1: el mesh no se deforma NUNCA (todas las
## escalas de hueso en 1, todos los blend shapes en 0). Si ves algo torcido, es un bug de este
## archivo, no una proporción para tunear.

## Modelo de Blender: las mallas skinneadas + el armature. Mientras el archivo no exista, create()
## devuelve null y el personaje sigue dibujándose con los meshes de CustomBone (cero cambio).
const MODEL_PATH := "res://Models/character.glb"

## CustomBone (Godot) → hueso del rig de Blender. Los nombres del lado de Godot se renombraron para
## seguir a Blender (`higher_spine`, `higher_leg`, `foot`), así que lo único que queda por traducir es
## la convención de lado: Blender usa el sufijo .L/.R porque tiene significado funcional ahí
## (X-mirror, Flip Names) y GDScript no acepta puntos en un identificador.
##
## wrist.L/R y los 30 huesos de dedos NO están: van rígidos colgando del antebrazo y no los maneja
## nadie todavía (ver "Deferred — hands and fingers" en el doc).
const BONE_MAP := {
	"lower_spine":      "lower.spine",
	"middle_spine":     "middle.spine",
	"higher_spine":     "higher.spine",
	"chest":            "chest",
	"neck":             "neck",
	"head":             "head",
	"left_shoulder":    "shoulder.L",
	"right_shoulder":   "shoulder.R",
	"left_upper_arm":   "upper.arm.L",
	"right_upper_arm":  "upper.arm.R",
	"left_lower_arm":   "lower.arm.L",
	"right_lower_arm":  "lower.arm.R",
	"left_hip":         "hip.L",
	"right_hip":        "hip.R",
	"left_higher_leg":  "higher.leg.L",
	"right_higher_leg": "higher.leg.R",
	"left_lower_leg":   "lower.leg.L",
	"right_lower_leg":  "lower.leg.R",
	"left_foot":        "foot.L",
	"right_foot":       "foot.R",
}

## ── CONVENCIÓN DE FRENTE ──────────────────────────────────────────────────────────────────────────
## DECISIÓN DEL PROYECTO: el frente es **−Z**. Es el estándar de Godot (`Node3D.basis.z` apunta hacia
## ATRÁS, `look_at` mira a −Z) y ya es lo que usa todo este código: la cápsula, la cámara, el pose
## sentado (`-char_rigidbody.global_transform.basis.z`), los interactuables y el tráfico. No se
## discute por personaje ni por modelo: si algo entra mirando para otro lado, se corrige al entrar.
##
## El modelo de Blender está autorado mirando **+Z**, o sea 180° al revés. Medido, no supuesto:
##   · `foot.L` apunta +Z y el CustomBone del pie apunta −Z
##   · `hip.L` / `shoulder.L` apuntan +X y los `left_*` del CustomBone apuntan −X
##   · `higher.leg.L` apunta −Y en los dos
## Un yaw de 180° en Y manda +Z→−Z, +X→−X y deja −Y quieto: explica las tres a la vez. No es un roll
## por hueso (eso ya lo absorbe `_fix`) ni un intercambio de lados — es el modelo entero.
##
## Se corrige UNA sola vez, acá, plegado dentro de `_fix`. Ojo con la tentación de arreglarlo rotando
## el nodo del modelo o el Skeleton3D: `_fix` se calcula a partir de los dos rest, así que cualquier
## rotación puesta en el medio se recalcula adentro y hay que razonarla dos veces. Un solo lugar.
##
## Si algún día el modelo se re-exporta ya mirando −Z (rotarlo 180° en el eje Z de Blender y aplicar
## la rotación), esto pasa a 0.0 y no hay que tocar nada más.
const MODEL_FORWARD_YAW := PI

## Primera persona: la lista es de lo que SE VE, no de lo que se esconde. Todo lo demás desaparece.
##
## Está invertida a propósito. El modelo pasó de 5 mallas a 13 (pelo, ojos, boca, cigarrillo, uñas,
## bolsillo, cierre, tarjeta…), y con una lista de "esconder" cada pieza nueva aparecía flotando en
## primera persona hasta que alguien se acordara de agregarla. Con una lista de "mostrar", lo que se
## agregue queda oculto por defecto — que es lo seguro.
##
## Solo manos y uñas. `arms_mesh` existe como malla propia y podría mostrarse, pero va oculta por
## decisión: en primera persona no se ven los brazos.
const FIRST_PERSON_VISIBLE: Array[String] = ["hand", "nail"]

var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []

## Los huesos que manejamos, ordenados por índice de Skeleton3D — o sea PADRES ANTES QUE HIJOS
## (Godot garantiza parent_idx < child_idx). Ese orden es lo que permite cachear el global del padre
## en vez de recorrer la cadena hacia arriba por cada hueso: sin eso el sync es O(n²) por frame y por
## personaje.
var _driven_idx: PackedInt32Array = PackedInt32Array()
var _driven_bone: Array[CustomBone] = []
## Corrección de ejes por hueso: rest_custom⁻¹ · rest_skel. Se calcula UNA vez en el build, con los
## dos rigs en reposo. No intentes reconciliar las convenciones a mano — CustomBone usa
## createFromToDown/Left/etc. y Blender le asigna su propio roll a cada hueso; la corrección los
## concilia sea cual sea.
var _fix: Array[Basis] = []
## Global de CADA hueso del esqueleto en el frame actual, para resolver el padre. Se siembra con los
## rest globals: si algún hueso manejado colgara de uno NO manejado, ese padre aporta su rest en vez
## de basura. (Hoy no pasa: todos los padres de la tabla están en la tabla.)
var _global: Array[Transform3D] = []


## Construye el espejo y se cuelga de `parent` (la cápsula). `bones` tiene que estar en la POSE DE
## REPOSO REAL — o sea después del primer solve de brazos, no en el rest de construcción. De ahí sale
## la corrección de ejes, y calibrarla en una pose que el personaje no mantiene deja las manos
## rotadas. Ver el comentario en BoneInstantiator.initialize_skeleton.
##
## El add_child va ADENTRO a propósito: _bind compara global_transform del esqueleto contra los de
## los CustomBone, que ya están en el árbol. Bindear antes de entrar al árbol mezcla un global de
## adentro con uno de afuera y la corrección sale mal.
##
## Devuelve null si todavía no existe el modelo, y el personaje sigue andando como siempre.
static func create(bones: CustomBonesUtil, parent: Node3D) -> SkinnedBodyUtil:
	if not ResourceLoader.exists(MODEL_PATH):
		return null
	var scene: PackedScene = load(MODEL_PATH)
	if scene == null:
		push_error("SkinnedBodyUtil: no se pudo cargar %s" % MODEL_PATH)
		return null

	var util := SkinnedBodyUtil.new()
	util.name = "SkinnedBody"
	var model: Node = scene.instantiate()
	util.add_child(model)

	util.skeleton = util._find_skeleton(model)
	if util.skeleton == null:
		push_error("SkinnedBodyUtil: %s no tiene ningún Skeleton3D" % MODEL_PATH)
		util.free()
		return null
	util._collect_meshes(model)
	parent.add_child(util)
	util._bind(bones)
	return util


## Copia el pose del árbol de CustomBone al Skeleton3D. Se llama una vez por frame al final del
## solve, junto a _sync_ragdoll_bodies().
func sync_from_bones() -> void:
	_sync({})


## Igual, pero leyendo los CUERPOS del ragdoll en vez de los huesos. Mientras se ragdollea (y durante
## la recuperación) los huesos quedan congelados y lo que se mueve son los RigidBody3D — así que la
## malla skinneada tiene que seguirlos a ellos. Funciona con la MISMA corrección de ejes porque la
## convención del ragdoll es cuerpo≡hueso: el transform global del cuerpo es el del hueso.
##
## Un hueso sin cuerpo cae de vuelta al CustomBone (queda estático, pero no rompe).
func sync_from_ragdoll(bodies: Dictionary) -> void:
	_sync(bodies)


func _sync(bodies: Dictionary) -> void:
	if skeleton == null:
		return
	var root_inv := skeleton.global_transform.affine_inverse()
	for k in _driven_idx.size():
		var idx := _driven_idx[k]
		var cb := _driven_bone[k]
		if not is_instance_valid(cb):
			continue
		var src: Node3D = cb
		if not bodies.is_empty():
			var rb: Node3D = bodies.get(cb)
			if is_instance_valid(rb):
				src = rb
		# La fuente en el espacio del Skeleton3D. El origin va DIRECTO: de ahí sale el largo de
		# hueso, y por eso las proporciones del arquetipo estiran la malla sin que haya que pedirlo.
		# La base va por delta desde el reposo (·_fix), que es lo que concilia las convenciones.
		var g := root_inv * src.global_transform
		var desired := Transform3D(g.basis * _fix[k], g.origin)
		_global[idx] = desired
		var p := skeleton.get_bone_parent(idx)
		var parent_g: Transform3D = _global[p] if p >= 0 else Transform3D.IDENTITY
		skeleton.set_bone_pose(idx, parent_g.affine_inverse() * desired)


## Aplica FIRST_PERSON_VISIBLE. Perdemos la granularidad por hueso que daba
## BoneInstantiator.set_first_person_visibility (esconder solo antebrazos y pies) — recuperarla
## necesitaría máscara por índice de hueso en el shader. Ver "What breaks" en el doc.
func set_first_person(first_person: bool) -> void:
	for m in meshes:
		if not is_instance_valid(m):
			continue
		if not first_person:
			m.visible = true
			continue
		var lower_name := m.name.to_lower()
		var keep := false
		for hint in FIRST_PERSON_VISIBLE:
			if lower_name.contains(hint):
				keep = true
				break
		m.visible = keep


func set_meshes_visible(value: bool) -> void:
	for m in meshes:
		if is_instance_valid(m):
			m.visible = value


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
		# FASE 4: los blend shapes se escriben acá. En fase 1 tienen que quedar TODOS en 0 — si el
		# mesh se deforma en fase 1, es un bug del espejo y no una proporción.
	for child in node.get_children():
		_collect_meshes(child)


## Busca un hueso tolerando el sufijo `_2` que agrega el importador de Godot.
##
## Godot exige nombres únicos entre TODOS los nodos que salen del .glb, y los huesos compiten con las
## mallas: como hay una malla llamada `head`, el hueso `head` entró como `head_2`. No es un bug del
## importador ni algo que se pueda desactivar — se arregla del lado de Blender renombrando la malla
## (p.ej. `head` → `head_mesh`) y re-exportando. Hasta entonces, esto lo absorbe.
func _find_bone(blender_name: String, field: String) -> int:
	var idx := skeleton.find_bone(blender_name)
	if idx >= 0:
		return idx
	idx = skeleton.find_bone(blender_name + "_2")
	if idx >= 0:
		push_warning("SkinnedBodyUtil: el hueso '%s' entró como '%s_2' (choque de nombre con una malla del .glb). Renombrá la malla en Blender." % [blender_name, blender_name])
		return idx
	push_warning("SkinnedBodyUtil: el rig no tiene el hueso '%s' (para %s)" % [blender_name, field])
	return -1


## Resuelve el mapa de nombres contra el rig real y calcula la corrección de ejes. Un hueso del mapa
## que no exista en el .glb se avisa y se saltea: el personaje se ve mal en esa parte pero no crashea,
## que es lo que querés mientras el rig todavía se está moviendo en Blender.
func _bind(bones: CustomBonesUtil) -> void:
	_global.resize(skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		_global[i] = skeleton.get_bone_global_rest(i)

	# Ordenado por índice de esqueleto = padres antes que hijos.
	var pairs: Array = []
	for field in BONE_MAP:
		var cb := bones.get(field) as CustomBone
		if not is_instance_valid(cb):
			continue  # p.ej. `neck` cuando has_neck es false
		var idx := _find_bone(BONE_MAP[field], field)
		if idx < 0:
			continue
		pairs.append([idx, cb])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var skel_inv := skeleton.global_transform.affine_inverse()
	var forward_fix := Basis(Vector3.UP, MODEL_FORWARD_YAW)
	_driven_idx.resize(pairs.size())
	_driven_bone.resize(pairs.size())
	_fix.resize(pairs.size())
	for k in pairs.size():
		var idx: int = pairs[k][0]
		var cb: CustomBone = pairs[k][1]
		_driven_idx[k] = idx
		_driven_bone[k] = cb
		var custom_rest := (skel_inv * cb.global_transform).basis
		var skel_rest := forward_fix * skeleton.get_bone_global_rest(idx).basis
		# ALINEAR LA DIRECCIÓN, no copiar el rest. Los dos rigs están en POSES distintas: el modelo de
		# Blender tiene los brazos casi horizontales (T-pose) y el rest del CustomBone los tiene
		# colgando. Sin este término, _fix se come esa diferencia de pose además de la de ejes: el
		# hueso del brazo queda orientado horizontal mientras la cadena de posiciones baja, y el mesh
		# sale cruzado/roto.
		#
		# Con el alineado, `_fix` codifica SOLO la convención de ejes (el roll), y se cumple que
		# desired.basis.y == cb.global_basis.y SIEMPRE: el hueso del modelo apunta exactamente a donde
		# apunta el CustomBone, sea cual sea el rest con el que se modeló. Ver el doc.
		var align := _align_axis(skel_rest.y.normalized(), custom_rest.y.normalized())
		_fix[k] = custom_rest.inverse() * (align * skel_rest)


## Rotación mínima que lleva `from` a `to`. Misma construcción que CustomBone.pose_from_rest_to usa
## para su parte de alineado.
static func _align_axis(from: Vector3, to: Vector3) -> Basis:
	var d := clampf(from.dot(to), -1.0, 1.0)
	if d > 0.999999:
		return Basis()
	if d < -0.999999:
		var flip := from.cross(Vector3.RIGHT)
		if flip.length_squared() < 1e-6:
			flip = from.cross(Vector3.UP)
		return Basis(flip.normalized(), PI)
	return Basis(from.cross(to).normalized(), acos(d))
