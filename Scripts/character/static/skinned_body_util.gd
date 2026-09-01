class_name SkinnedBodyUtil
extends Node3D

## ESPEJO del rig lógico sobre un Skeleton3D skinneado.
##
## El árbol de CustomBone sigue siendo la ÚNICA fuente de verdad del pose: la IK, el animador
## procedural, anim_mod, el solve sentado y el ragdoll lo siguen manejando como Node3Ds igual que
## antes. Esta clase no anima nada — solo copia ese pose a un Skeleton3D real cada frame, para que
## las mallas skinneadas del modelo de Blender lo sigan.
##
## Ver technical/skinned-character-migration.md.

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

## ── HUESOS QUE ESTIRAN LA MALLA ───────────────────────────────────────────────────────────────────
## Un hueso de esta lista se ESCALA a lo largo de sí mismo hasta el largo que pide el rig lógico, en
## vez de solo rotar. Es lo mismo que hace el driver de `arms_length` en Blender, y es lo único que
## deforma la malla de verdad: mover el hueso hijo traslada nada más los vértices que le pesan a ÉL,
## y el tramo del medio del brazo —que pesa 100% al padre— se queda quieto. Se ve como una junta que
## se abre, no como un brazo largo.
##
## Una CADENA por entrada, con los huesos que la componen, el nombre de su shape key correctivo y el
## factor con el que se esculpió en Blender. Es una tabla y no una lista suelta porque cada cadena
## tiene su propio factor: agregar el torso es una entrada más y ni una línea de lógica.
##
## Los huesos van TODOS, no solo el primero. En Blender se escala únicamente el hueso raíz de la
## cadena y el resto hereda; acá no puede ser así, porque `_detach_children_of_stretched` saca a los
## hijos de la jerarquía —no les queda padre del cual heredar— y el espejo le escribe a cada hueso su
## global directo. Cada uno se escala solo, con su propio `cb.length / _rest_len`, y como `_share`
## reparte la cadena en la proporción del modelo el resultado es el mismo estiramiento uniforme.
##
## UNA CADENA PUEDE ESTAR ACÁ SIN QUE SU SHAPE KEY EXISTA TODAVÍA, y hace falta que esté. Los huesos
## se escalan igual —eso sale de `cb.length / _rest_len`, no del blend shape— y sin eso los huesos se
## separan sin estirar la malla, que es la junta abierta que describe el doc. El escritor del shape
## simplemente no encuentra la key y no escribe nada. Así se puede probar un largo en el juego antes de
## tener el correctivo esculpido.
const STRETCH_CHAINS: Array[Dictionary] = [
	{
		"shape": "arms_length_max",
		"factor": ReferenceRig.ARM_MODEL_FACTOR,
		"bones": ["left_upper_arm", "right_upper_arm", "left_lower_arm", "right_lower_arm"],
	},
	{
		"shape": "legs_length_max",
		"factor": ReferenceRig.LEGS_MODEL_FACTOR,
		"bones": ["left_higher_leg", "right_higher_leg", "left_lower_leg", "right_lower_leg"],
	},
	{
		"shape": "torso_length_max",
		"factor": ReferenceRig.TORSO_MODEL_FACTOR,
		"bones": ["lower_spine", "higher_spine", "chest"],
	},
	# ANCHO DE FRAME Y CADERA: escalan el hueso pero NO tienen correctivo propio — su shape key es
	# `muscle_max` / `fat_max`, que se escriben aparte por STATIC_SHAPES. `shape` vacío significa
	# exactamente eso: escalá el hueso y no busques ninguna key.
	{
		"shape": "",
		"factor": ReferenceRig.FRAME_MODEL_FACTOR,
		"bones": ["left_shoulder", "right_shoulder"],
	},
	{
		"shape": "",
		"factor": ReferenceRig.HIPS_MODEL_FACTOR,
		"bones": ["left_hip", "right_hip"],
	},
]

## LOS DOS EJES DE MASA: solo malla, sin hueso detrás. `nombre del key` → `campo del arquetipo`.
##
## No son "grosor de brazo", "panza", "cuello": son **el cuerpo entero al máximo de músculo** y **al
## máximo de grasa**, esculpidos cada uno de una vez sobre todas las mallas que participan. Esa es la
## decisión que evita el problema de acoplamiento — con una key por parte del cuerpo habría que
## mantener el torso en sincronía con el brazo a mano; con una key por ESTADO del cuerpo, encajan por
## construcción porque se esculpieron juntas.
##
## Se suman: `flaco + m·(musculoso − flaco) + f·(gordo − flaco)`. Con `m + f = 1` da un promedio entre
## los dos extremos; por encima de 1 se apilan, que es la zona del gordo fuerte y es a propósito.
##
##
## Se escriben UNA SOLA VEZ al construir el personaje y no se vuelven a tocar. Esa es toda la
## diferencia con STRETCH_CHAINS: el brazo se estira con cada agarre, así que su key se recalcula por
## frame; una panza no cambia mientras el personaje existe.
##
## Se escriben LINEALES, con el valor del arquetipo tal cual. La curva `F·v/s` de `_write_shape` sería
## un error acá: existe para cancelar la escala de un hueso y estas keys no tienen ninguno detrás.
##
## Un key que el modelo todavía no tenga simplemente no se encuentra y no pasa nada — por eso esto
## puede entrar antes de que el arte exista.
const STATIC_SHAPES := {
	"fat_max":    "fat",
	"muscle_max": "muscle",
}

## En qué cadena está un hueso, o −1 si no estira.
static func _chain_of(field: String) -> int:
	for c in STRETCH_CHAINS.size():
		var bones: Array = STRETCH_CHAINS[c]["bones"]
		if bones.has(field):
			return c
	return -1

## Hueso RÍGIDO que cuelga de un hueso estirable y que NO tiene que crecer con él. No está en
## BONE_MAP porque nadie lo anima —la mano y los 30 huesos de dedos van rígidos colgando del
## antebrazo—, así que si no se lo maneja acá hereda la escala del padre y la mano crece con el brazo.
## Es el `Inherit Scale = None` que el doc de Blender pide en `wrist.L/R`, del lado de Godot.
##
## LA PIERNA NO NECESITA UNA: `foot.L/R` sí está en BONE_MAP, o sea que es un hueso MANEJADO y el
## espejo le escribe su propio global (el que sale de la IK). Al estar desprendido de la tibia por
## `_detach_children_of_stretched` y no figurar en ninguna cadena, su `_rest_len` es 0 y nadie lo
## escala. Eso es, del lado de Godot, el `Inherit Scale = None` que el doc de Blender pide en `foot`.
const RIGID_TIP := {
	"left_lower_arm":  "wrist.L",
	"right_lower_arm": "wrist.R",
}

var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []

## Los huesos que manejamos, ordenados por índice de Skeleton3D — o sea PADRES ANTES QUE HIJOS
## (Godot garantiza parent_idx < child_idx). Ese orden es lo que permite cachear el global del padre
## en vez de recorrer la cadena hacia arriba por cada hueso: sin eso el sync es O(n²) por frame y por
## personaje.
var _driven_idx: PackedInt32Array = PackedInt32Array()
var _driven_bone: Array[CustomBone] = []
## Corrección de ejes por hueso. Lleva justo la diferencia de ROLL entre los dos rigs: el rig lógico
## usa la convención de Godot (X derecha, Z atrás) y el modelo tiene el roll con el que fue esculpido.
## ReferenceRig se queda con la dirección del modelo y descarta su roll a propósito; esta corrección
## se lo devuelve a la malla, que sí lo necesita para verse bien. Se calcula sola en el build.
var _fix: Array[Basis] = []
## Global de CADA hueso del esqueleto en el frame actual, para resolver el padre. Se siembra con los
## rest globals: si algún hueso manejado colgara de uno NO manejado, ese padre aporta su rest en vez
## de basura.
var _global: Array[Transform3D] = []
## Largo de reposo del hueso EN EL MODELO, o 0 si el hueso no estira. Con esto el sync deduce solo la
## escala (`cb.length / _rest_len`): nadie tiene que avisarle que el arquetipo cambió de brazo ni que
## el agarre lo está estirando — sale del largo del CustomBone, que ya es la verdad.
var _rest_len: PackedFloat32Array = PackedFloat32Array()
## Punta rígida colgada de este hueso (−1 si no hay), y su pose de reposo relativa al hueso.
var _tip_idx: PackedInt32Array = PackedInt32Array()
var _tip_rest: Array[Transform3D] = []
## Cadena a la que pertenece cada hueso manejado (índice en STRETCH_CHAINS), o −1 si no estira.
var _chain_idx: PackedInt32Array = PackedInt32Array()
## Escala de cada cadena en el frame actual. Miembro y no local para no allocar por frame.
var _chain_scale: PackedFloat32Array = PackedFloat32Array()
## Por cadena: TODAS las mallas que tienen su blend shape, no la primera.
##
## El brazo lo cubren varias mallas (la manga y el puño), y todas necesitan su correctivo con el MISMO
## nombre. Manejar solo la primera dejaba a la otra sin corregir — se veía como una costura que se abre
## al estirar, y no había nada que lo avisara.
var _shape_meshes: Array[Array] = []
var _shape_idxs: Array[PackedInt32Array] = []
## Escala escrita en el frame anterior por cadena, para no reescribir el blend shape si no cambió.
var _shape_written: PackedFloat32Array = PackedFloat32Array()


## Construye el espejo y se cuelga de `parent` (la cápsula).
##
## Se puede llamar en cualquier momento: la calibración sale de dos REPOSOS, no de la pose viva (ver
## `_bind`), así que no importa en qué estado estén los CustomBone ni hacia dónde mire el personaje.
## `bones` solo se recorre para resolver qué CustomBone corresponde a cada hueso.
##
## Devuelve null si todavía no existe el modelo, y el personaje sigue andando como siempre.
static func create(bones: CustomBonesUtil, parent: Node3D) -> SkinnedBodyUtil:
	if not ResourceLoader.exists(ReferenceRig.MODEL_PATH):
		return null
	var scene: PackedScene = load(ReferenceRig.MODEL_PATH)
	if scene == null:
		push_error("SkinnedBodyUtil: no se pudo cargar %s" % ReferenceRig.MODEL_PATH)
		return null

	var util := SkinnedBodyUtil.new()
	util.name = "SkinnedBody"
	var model: Node = scene.instantiate()
	util.add_child(model)

	util.skeleton = util._find_skeleton(model)
	if util.skeleton == null:
		push_error("SkinnedBodyUtil: %s no tiene ningún Skeleton3D" % ReferenceRig.MODEL_PATH)
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
	_chain_scale.fill(1.0)
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
		# La fuente en el espacio del Skeleton3D. El origin va DIRECTO: de ahí sale dónde ARRANCA el
		# hueso. La base va por delta desde el reposo (·_fix), que concilia las convenciones de ejes.
		var g := root_inv * src.global_transform
		var rigid := Transform3D(g.basis * _fix[k], g.origin)
		var stretched := rigid
		if _rest_len[k] > 0.0:
			# `_fix` es un roll puro alrededor de Y, así que `rigid.basis.y` sigue siendo la dirección
			# del hueso: escalar Y en local estira a lo LARGO del hueso, igual que el `S Y Y` de Blender.
			var s: float = cb.length / _rest_len[k]
			stretched.basis = rigid.basis.scaled_local(Vector3(1.0, s, 1.0))
			_chain_scale[_chain_idx[k]] = s
		_global[idx] = stretched
		var p := skeleton.get_bone_parent(idx)
		var parent_g: Transform3D = _global[p] if p >= 0 else Transform3D.IDENTITY
		skeleton.set_bone_pose(idx, parent_g.affine_inverse() * stretched)

		# La punta rígida (la muñeca): va en la punta del antebrazo YA ESTIRADO —por eso la posición
		# sale de `stretched`— pero con la orientación y el tamaño SIN escalar —por eso la base sale de
		# `rigid`. Los dedos cuelgan de ella y heredan lo mismo.
		var ti := _tip_idx[k]
		if ti >= 0:
			var tip := _tip_rest[k]
			skeleton.set_bone_pose(ti, Transform3D((rigid * tip).basis, (stretched * tip).origin))

	for c in STRETCH_CHAINS.size():
		_write_shape(c, _chain_scale[c])


## El blend shape sale de la MISMA escala que fue al hueso, invirtiendo el factor con el que se
## esculpió esa cadena en Blender. No hay un segundo número que mantener en sincronía: si el brazo
## mide 1.54×, el shape va en 0.18 y punto — incluido el estirón del agarre, que sube los dos a la vez.
func _write_shape(chain: int, scale: float) -> void:
	var targets: Array = _shape_meshes[chain]
	if targets.is_empty():
		return
	if is_equal_approx(scale, _shape_written[chain]):
		return
	_shape_written[chain] = scale
	var f: float = STRETCH_CHAINS[chain]["factor"]
	var w := 0.0
	if f > 1.0 and scale > 0.0:
		# w = F·v/s, NO w = v. Y la diferencia no es cosmética.
		#
		# La malla final es (escala del hueso) × (mezcla del shape key). Las dos son lineales, así que
		# el producto es CUADRÁTICO: sale exacto en los dos extremos —que es donde se autoró— y se va
		# en el medio. Concreto con F=4: el codo está esculpido para conservar su tamaño, o sea que en
		# el reposo largo mide 1/4; a mitad de camino el reposo mezclado da 0.625 y el hueso escala
		# 2.5, así que el codo se hincha 1.5625×. La cota es (1+F)²/(4F), y crece con el factor: +56%
		# a ×4, +12.5% a ×2. Además el corrector queda subaplicado (0.18 donde iba 0.47), y por eso el
		# resultado se parecía al hueso escalado a secas.
		#
		# Esta curva lo cancela EXACTO: pedir que `s·(1 − w(1−1/F)) = 1` para todo s despeja en
		# w = (1−1/s)/(1−1/F) = F·v/s. Todo lo que se esculpió para conservar tamaño lo conserva en
		# todos los valores intermedios, no solo en los extremos. Lo que se esculpió para escalar
		# proporcional no lo toca (su reposo no cambia entre los dos extremos, así que w le da igual).
		#
		# La PIERNA lo necesita más que el brazo, aunque su factor sea menor: el personaje genérico vive
		# en 0.5385, o sea casi exactamente en el medio del rango, que es donde el error es máximo.
		#
		# El driver de Blender tiene que usar la MISMA expresión o el preview miente. Ver
		# technical/character-blender-length-variable.md.
		w = clampf((1.0 - 1.0 / scale) / (1.0 - 1.0 / f), 0.0, 1.0)
	var idxs: PackedInt32Array = _shape_idxs[chain]
	for i in targets.size():
		var mi: MeshInstance3D = targets[i]
		if is_instance_valid(mi):
			mi.set_blend_shape_value(idxs[i], w)


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


## Escribe las keys de clase B con los valores del arquetipo. La llama `initialize_skeleton` una vez,
## después de construir el espejo.
func apply_static_shapes(arch: EntityArchetype) -> void:
	if arch == null:
		return
	for shape_name in STATIC_SHAPES:
		var value: float = arch.get(STATIC_SHAPES[shape_name])
		for mi in meshes:
			if not is_instance_valid(mi):
				continue
			var found := mi.find_blend_shape_by_name(shape_name)
			if found >= 0:
				mi.set_blend_shape_value(found, clampf(value, 0.0, 1.0))


## Recolecta las mallas y, de paso, dónde vive el blend shape de cada cadena. Se llama una sola vez,
## desde `create`, así que acá se dimensionan los arrays por cadena.
func _collect_meshes(node: Node) -> void:
	var n := STRETCH_CHAINS.size()
	_shape_meshes.resize(n)
	_shape_idxs.resize(n)
	_shape_written.resize(n)
	_chain_scale.resize(n)
	for c in n:
		_shape_meshes[c] = []
		_shape_idxs[c] = PackedInt32Array()
		_shape_written[c] = -1.0
	_collect_meshes_rec(node)


func _collect_meshes_rec(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		meshes.append(mi)
		for c in STRETCH_CHAINS.size():
			var shape_name: String = STRETCH_CHAINS[c]["shape"]
			var found := mi.find_blend_shape_by_name(shape_name)
			if found >= 0:
				var targets: Array = _shape_meshes[c]
				targets.append(mi)
				var idxs: PackedInt32Array = _shape_idxs[c]
				idxs.append(found)
				_shape_idxs[c] = idxs
	for child in node.get_children():
		_collect_meshes_rec(child)


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
	for field in ReferenceRig.BONE_MAP:
		var cb := bones.get(field) as CustomBone
		if not is_instance_valid(cb):
			continue  # p.ej. `neck` cuando has_neck es false
		var idx := _find_bone(ReferenceRig.BONE_MAP[field], field)
		if idx < 0:
			continue
		pairs.append([idx, cb, field])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var rig := ReferenceRig.get_rig()
	var forward_fix := Basis(Vector3.UP, ReferenceRig.MODEL_FORWARD_YAW)
	_driven_idx.resize(pairs.size())
	_driven_bone.resize(pairs.size())
	_fix.resize(pairs.size())
	_rest_len.resize(pairs.size())
	_chain_idx.resize(pairs.size())
	_tip_idx.resize(pairs.size())
	_tip_rest.resize(pairs.size())
	for k in pairs.size():
		var idx: int = pairs[k][0]
		var cb: CustomBone = pairs[k][1]
		var field: String = pairs[k][2]
		_driven_idx[k] = idx
		_driven_bone[k] = cb
		# LA CALIBRACIÓN NO MIRA LA POSE. `_fix` es una constante de CONVENCIÓN entre los dos rigs —
		# cuánto difiere el roll con el que Blender esculpió el hueso del que usa el rig lógico— así que
		# sale de dos reposos y de nada más: el reposo de construcción del CustomBone (`rig.bases`, que
		# ya viene del modelo) contra el reposo del propio modelo.
		#
		# Definición: con el CustomBone en su reposo de construcción, el hueso del modelo tiene que
		# quedar en SU reposo. De ahí `_fix = bases⁻¹ · (yaw · rest)`, y se cumple exacto porque
		# `bases[field].y == (yaw · rest).y` por construcción (ReferenceRig lo arma justo así).
		#
		# Antes esto se medía contra la pose VIVA, después del primer solve de brazos. El problema no
		# era la idea sino que la pose viva trae la TORSIÓN QUE ELIGIÓ LA IK en ese frame, y esa torsión
		# no es la misma dos veces: cada respawn congelaba un roll distinto (se midieron 8.4° de
		# dispersión, y ~34° de corrimiento sistemático) y las manos salían torcidas, distinto cada vez.
		# Peor: los dos brazos pueden estar en puntos distintos de su transitorio, y entonces cada mano
		# congela una torsión propia — de ahí que salieran asimétricas y no espejadas.
		#
		# Si a partir de acá la mano queda mal pero SIEMPRE IGUAL, el problema es la torsión que elige
		# la IK del brazo (el pole del codo), no esto. Es el lugar honesto para arreglarlo.
		_fix[k] = (rig.bases[field] as Basis).inverse() * (forward_fix * skeleton.get_bone_global_rest(idx).basis)

		_chain_idx[k] = _chain_of(field)
		_rest_len[k] = float(rig.lengths.get(field, 0.0)) if _chain_idx[k] >= 0 else 0.0
		_tip_idx[k] = -1
		_tip_rest[k] = Transform3D.IDENTITY
		if RIGID_TIP.has(field):
			var tip := _find_bone(RIGID_TIP[field], field)
			if tip >= 0:
				_tip_idx[k] = tip
				# Se lee ANTES de reparentar: después, el global rest deja de ser el del modelo.
				_tip_rest[k] = skeleton.get_bone_global_rest(idx).affine_inverse() * skeleton.get_bone_global_rest(tip)

	_detach_children_of_stretched()


## UN HUESO ESCALADO NO PUEDE TENER HIJOS. Godot compone el global de un hueso como
## `global(padre) · local(hijo)` y guarda ese local descompuesto en posición + cuaternión + escala:
## un producto con SHEAR no entra ahí. Y con el padre escalado en Y y el hijo rotado (el codo
## doblado), `local = S⁻¹·R·S` es exactamente eso — a 1.54× y 28° de codo se pierden ~20° de
## ortogonalidad, o sea un antebrazo que se tuerce distinto según cuánto esté doblado el brazo.
##
## La salida es sacarlos de la jerarquía: como el espejo ya calcula el global de CADA hueso manejado,
## un hueso raíz no necesita padre — `_sync` le escribe el global directo (ya contempla `p < 0`) y no
## queda producto que descomponer. Lo único que sigue colgando de un hueso escalado son huesos
## rígidos (los dedos, bajo la muñeca), que sí tienen que heredar.
##
## No toca las poses de bind del Skin, que son absolutas: el skinning sigue leyendo el global que le
## escribimos. Sí invalida `get_bone_global_rest` de los huesos movidos — por eso corre al final de
## `_bind`, cuando ya se leyó todo lo que hacía falta.
func _detach_children_of_stretched() -> void:
	for k in _driven_idx.size():
		if _rest_len[k] <= 0.0:
			continue
		for child in skeleton.get_bone_children(_driven_idx[k]):
			skeleton.set_bone_parent(child, -1)

