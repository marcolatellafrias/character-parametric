class_name ReferenceRig
extends RefCounted

## EL MODELO DE BLENDER ES LA FUENTE DE VERDAD DEL ESQUELETO.
##
## Lee `character.glb` UNA vez por sesión y cachea, por hueso, su **base de reposo** y su **largo**.
## De acá sale la pose de reposo del rig lógico: antes estaba hardcodeada en cinco helpers
## (`createFromToUp/Down/Left/Right/Forward`) que aproximaban a mano lo que el modelo ya dice exacto.
## Lo que se ve en Blender es lo que se ve en el juego, sin transcripción de por medio.
##
## Consecuencia buena: como los dos rigs quedan en la MISMA pose de reposo, la corrección de ejes de
## SkinnedBodyUtil colapsa a la identidad sola. Se deja igual porque se calcula sola y protege si
## algún día las poses vuelven a divergir.

const MODEL_PATH := "res://Models/character.glb"

## CustomBone (Godot) → hueso del rig de Blender. Los nombres del lado de Godot siguen a Blender
## (`higher_spine`, `higher_leg`, `foot`); lo único que queda por traducir es la convención de lado,
## porque GDScript no acepta puntos en un identificador y Blender usa el sufijo .L/.R (que ahí tiene
## significado funcional: X-mirror, Flip Names).
##
## `wrist.L/R` y los 30 huesos de dedos NO están: van rígidos colgando del antebrazo y no los maneja
## nadie todavía (ver "Deferred — hands and fingers" en technical/skinned-character-migration.md).
const BONE_MAP := {
	"lower_spine":      "lower.spine",
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
## ATRÁS, `look_at` mira a −Z) y ya es lo que usa todo el código: la cápsula, la cámara, el pose
## sentado, los interactuables y el tráfico. Si algo entra mirando para otro lado, se corrige al
## entrar — acá, una sola vez, para todos los consumidores.
##
## El modelo está autorado mirando **+Z**. Medido, no supuesto: `foot.L` apunta +Z contra el −Z del
## rig lógico, y `hip.L`/`shoulder.L` apuntan +X contra −X. Un yaw de 180° explica las dos a la vez.
##
## Si algún día se re-exporta ya mirando −Z (rotarlo 180° en el eje Z de Blender y aplicar), esto
## pasa a 0.0 y no hay que tocar nada más.
const MODEL_FORWARD_YAW := PI

## ── FACTORES DE ESTIRAMIENTO POR CADENA ───────────────────────────────────────────────────────────
## La ESCALA DE POSE que se le aplicó en Blender al PRIMER hueso de la cadena para esculpir su shape
## key, o sea cuánto mide la cadena en el extremo 1.0 respecto del 0.0.
##
## Son los ÚNICOS números de cada cadena que no salen del .glb, y no por descuido: glTF no exporta
## escala de pose, así que el archivo solo puede contar el extremo 0.0 (`arm_chain`, `leg_chain`). Si
## se re-esculpe con otro factor, se cambia acá y nada más.
##
## ⚠ EL MODELO ES EL MÍNIMO DE LA CADENA, no el medio. Vale para las dos: la pierna se acortó al 65%
## en Blender justo para que el 0.0 fuera un extremo real. Un arquetipo que quiera el largo esculpido
## original pide un valor INTERMEDIO, no 0.5 por default — ver `EntityArchetype.generic_arch`.
##
## Ver technical/character-blender-length-variable.md.
const ARM_MODEL_FACTOR := 4.0
const LEGS_MODEL_FACTOR := 2.0
const TORSO_MODEL_FACTOR := 2.0

## ── ANCHO DE FRAME Y DE CADERA ────────────────────────────────────────────────────────────────────
## Cuánto se ensancha el hombro al máximo de músculo, y la cadera al máximo de grasa.
##
## NO tienen shape key propia y no la van a tener: su correctivo es `muscle_max` / `fat_max`, que ya
## se esculpen con el hueso posado en su factor. Por eso el bulto cuadrático que obliga a la curva
## `F·v/s` en las cadenas de largo acá no importa — a factor 1.3 el error a mitad de rango es del
## **1.7%**, contra el 56% que da el ×4 del brazo. Ver technical/character-appearance-system.md.
##
## Van colgados de `muscle` y `fat` a propósito, sin knob propio: hombros anchos y músculo son la
## misma variable en este personaje, igual que caderas anchas y grasa. Se puede desacoplar después
## agregando dos campos al arquetipo, sin tocar nada más.
const FRAME_MODEL_FACTOR := 1.3
const HIPS_MODEL_FACTOR := 1.3

static var _cached: ReferenceRig = null

## Base de reposo GLOBAL por hueso. Del modelo sale la DIRECCIÓN; el ROLL lo pone la convención del
## proyecto (ver _conventional_basis). La consume CustomBone.create, que espera una rotación global y
## la convierte a local contra su padre.
var bases: Dictionary = {}
## Largo de reposo por hueso, en metros. Vacío para los huesos hoja (cabeza, pie), que no tienen hijo
## del cual medir.
var lengths: Dictionary = {}
## Altura de la pelvis en reposo, en metros sobre el piso. En Blender la planta del pie está en 0, así
## que la Y global del hueso raíz ES la altura a la que el personaje se para. Antes esto se estimaba
## como una fracción del largo de pierna; el modelo lo dice exacto.
var pelvis_rest_height: float = 0.0
## Altura del tobillo sobre el piso. La diferencia con la planta es el grosor de pie/zapato, que no se
## puede deducir del esqueleto — pero como el modelo apoya en 0, se mide directo.
var ankle_rest_height: float = 0.0
## Separación lateral del pie en reposo, en metros desde el eje del personaje. Es la ESTANCIA con la
## que fue modelado. Antes se estimaba como el ancho de cadera; el modelo la dice exacta, y si no
## coincide la tibia queda girada respecto del modelo y el pie hereda ese giro.
var foot_rest_x: float = 0.0
## Largos de cadena y de los huesos sueltos, medidos del rig. Antes eran constantes transcritas a mano
## de un volcado, y quedaban viejas en silencio cada vez que se re-exportaba el modelo: el rig lógico
## le pedía a la malla proporciones de una versión anterior y el espejo la estiraba para cumplir.
var arm_chain: float = 0.0
var torso_chain: float = 0.0
var shoulder_len: float = 0.0
var hip_len: float = 0.0
var neck_len: float = 0.0
## La cabeza es hueso HOJA, así que su largo no sale de un hijo: se mide como el tope de head_mesh
## menos la base del hueso. Solo alimenta la altura total (cápsula y altura de cámara).
var head_len: float = 0.0
## Largo de la cadena de pierna del modelo, para escalar lo de arriba cuando un arquetipo tenga otra.
var leg_chain: float = 0.0
var valid: bool = false

static func get_rig() -> ReferenceRig:
	if _cached == null:
		_cached = ReferenceRig.new()
		_cached._load()
	return _cached

func _load() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		push_error("ReferenceRig: falta %s — el esqueleto no se puede construir." % MODEL_PATH)
		return
	var root: Node = (load(MODEL_PATH) as PackedScene).instantiate()
	var skel := _find_skeleton(root)
	if skel == null:
		push_error("ReferenceRig: %s no tiene ningún Skeleton3D." % MODEL_PATH)
		root.free()
		return

	var yaw := Basis(Vector3.UP, MODEL_FORWARD_YAW)
	for field in BONE_MAP:
		var idx := _find_bone(skel, BONE_MAP[field])
		if idx < 0:
			continue
		bases[field] = _conventional_basis(yaw * skel.get_bone_global_rest(idx).basis.y)
		var children := skel.get_bone_children(idx)
		if not children.is_empty():
			var longest := 0.0
			for c in children:
				longest = maxf(longest, skel.get_bone_rest(c).origin.length())
			lengths[field] = longest
	var root_idx := _find_bone(skel, "lower.spine")
	if root_idx >= 0:
		pelvis_rest_height = skel.get_bone_global_rest(root_idx).origin.y
	var ankle_idx := _find_bone(skel, "foot.L")
	if ankle_idx >= 0:
		ankle_rest_height = skel.get_bone_global_rest(ankle_idx).origin.y
		foot_rest_x = absf(skel.get_bone_global_rest(ankle_idx).origin.x)
	leg_chain = float(lengths.get("left_higher_leg", 0.0)) + float(lengths.get("left_lower_leg", 0.0))
	arm_chain    = float(lengths.get("left_upper_arm", 0.0)) + float(lengths.get("left_lower_arm", 0.0))
	torso_chain  = float(lengths.get("lower_spine", 0.0)) + float(lengths.get("higher_spine", 0.0)) + float(lengths.get("chest", 0.0))
	shoulder_len = float(lengths.get("left_shoulder", 0.0))
	hip_len      = float(lengths.get("left_hip", 0.0))
	neck_len     = float(lengths.get("neck", 0.0))
	var head_idx := _find_bone(skel, "head")
	if head_idx >= 0:
		head_len = maxf(0.0, _top_of_head(root) - skel.get_bone_global_rest(head_idx).origin.y)
	valid = not bases.is_empty()
	root.free()

## Godot exige nombres únicos entre TODOS los nodos del .glb, y los huesos compiten con las mallas:
## un hueso llamado igual que una malla entra con sufijo `_2`. Se arregla renombrando la malla en
## Blender; hasta entonces, esto lo absorbe con un aviso.
func _find_bone(skel: Skeleton3D, blender_name: String) -> int:
	var idx := skel.find_bone(blender_name)
	if idx >= 0:
		return idx
	idx = skel.find_bone(blender_name + "_2")
	if idx >= 0:
		push_warning("ReferenceRig: '%s' entró como '%s_2' (choque de nombre con una malla). Renombrá la malla en Blender." % [blender_name, blender_name])
		return idx
	push_warning("ReferenceRig: el rig no tiene el hueso '%s'." % blender_name)
	return -1

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

## Base de reposo de un hueso que apunta hacia `dir`: la rotación MÍNIMA que lleva el marco del
## personaje (X derecha, Y arriba, Z atrás) a tener su +Y sobre esa dirección.
##
## Del modelo se toma la DIRECCIÓN, no el roll. Es deliberado y es la línea que separa las dos
## responsabilidades: **el modelo dice hacia dónde apunta cada hueso, el proyecto dice cómo está
## rolado.** Copiar también el roll del modelo dejaba a los huesos verticales (columna, cuello,
## cabeza) girados 180° sobre su eje respecto de la convención de Godot — su X local apuntaba a la
## izquierda y su Z al frente. Todo lo que lee ejes locales se rompía en silencio: los targets de
## brazo salían del lado contrario (brazos cruzados) y el pitch de cabeza quedaba invertido.
##
## La diferencia de roll no se pierde: SkinnedBodyUtil la recupera sola en su corrección por hueso y
## se la devuelve a la malla, que es exactamente para lo que esa corrección existe.
##
## Dato curioso y buena señal: esta regla REPRODUCE EXACTO las cinco fábricas que había hardcodeadas
## (`createFromToUp/Down/Left/Right/Forward`). Eran una sola regla escrita cinco veces.
static func _conventional_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	# 1. La CONVENCIÓN la elige el eje del mundo al que más se parece la dirección.
	# 2. La dirección exacta del modelo entra como corrección chica encima.
	#
	# Los dos pasos, y no la rotación mínima directa desde +Y, porque esa es INESTABLE cerca de la
	# vertical: para un hueso que apunta casi derecho para abajo, el eje de la rotación mínima lo decide
	# la componente horizontal minúscula de la dirección, y termina metiendo un yaw enorme. Medido en
	# este modelo: 9.5° de inclinación de la pierna producían 48° de yaw espurio, que el pie heredaba —
	# eran los pies abiertos. Snapeando primero al eje más cercano, la corrección que queda es siempre
	# chica y el roll sale de la convención, que es estable por definición.
	var axis := _nearest_axis(y)
	return _minimal_rotation(axis, y) * _canonical_basis(axis)

static func _nearest_axis(v: Vector3) -> Vector3:
	var axes := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var best: Vector3 = Vector3.UP
	var best_dot := -2.0
	for a: Vector3 in axes:
		var d := v.dot(a)
		if d > best_dot:
			best_dot = d
			best = a
	return best

## Las seis convenciones canónicas. Reproducen exacto las cinco fábricas que había hardcodeadas
## (`createFromToUp/Down/Left/Right/Forward`), más la de atrás que no existía.
static func _canonical_basis(axis: Vector3) -> Basis:
	if axis == Vector3.UP:      return Basis()
	if axis == Vector3.DOWN:    return Basis(Vector3.RIGHT, PI)
	if axis == Vector3.LEFT:    return Basis(Vector3.BACK, PI * 0.5)
	if axis == Vector3.RIGHT:   return Basis(Vector3.BACK, -PI * 0.5)
	if axis == Vector3.FORWARD: return Basis(Vector3.RIGHT, -PI * 0.5)
	return Basis(Vector3.RIGHT, PI * 0.5)

static func _minimal_rotation(from: Vector3, to: Vector3) -> Basis:
	var d := clampf(from.dot(to), -1.0, 1.0)
	if d > 0.999999:
		return Basis()
	if d < -0.999999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(from.cross(to).normalized(), acos(d))

## Tope de la malla de la cabeza, para medir el largo del hueso hoja `head`.
## El punto más alto de cualquier malla cuyo nombre contenga "head". Alimenta `head_len`, y de ahí la
## altura total, la cápsula y la altura de cámara.
##
## Toma el MÁXIMO de todas, no la primera que encuentra. Con una sola malla da igual, pero con dos
## —una cabeza duplicada, o la cabeza partida del cuello— devolver la primera dependía del orden en que
## el .glb las lista, y si esa era la de abajo el personaje quedaba medido más bajo de lo que es.
func _top_of_head(node: Node) -> float:
	var best := 0.0
	var mi := node as MeshInstance3D
	if mi != null and mi.name.to_lower().contains("head"):
		var ab: AABB = mi.get_aabb()
		best = ab.position.y + ab.size.y
	for child in node.get_children():
		best = maxf(best, _top_of_head(child))
	return best
