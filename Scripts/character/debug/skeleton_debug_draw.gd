class_name SkeletonDebugDraw
extends Node3D

## Visualizadores de debug del esqueleto, independientes entre sí:
##   · HUESOS         — una línea por hueso + una esfera en cada articulación.
##   · COLISIONADORES — las cápsulas de colisión que usa el ragdoll, con su forma real.
##
## Los gizmos NO cuelgan de los CustomBone: son hijos de este nodo y cada frame se les copia el
## transform del hueso. Colgarlos del esqueleto era más corto, pero los hacía rehenes de la
## visibilidad ajena — el ragdoll apaga `lower_spine.visible`, que se lleva puesto todo el subárbol, y
## los gizmos desaparecían al ragdollear. Siendo hijos propios, nada de afuera los puede apagar.
##
## Y la fuente del transform es la misma que usa la malla skinneada: los huesos parado, los cuerpos
## del ragdoll mientras ragdollea o se levanta (ahí los huesos quedan congelados y lo que se mueve son
## los cuerpos). Así el gizmo muestra siempre dónde está el personaje de verdad.

const BONE_COLOR  := Color(0.25, 1.0, 0.45)
const JOINT_COLOR := Color(1.0, 0.8, 0.15)
const LINE_WIDTH  := 0.012
const JOINT_SIZE  := 0.02

var bi: BoneInstantiator

var _bones_on: bool = false
var _colliders_on: bool = false

## Gizmo ↔ hueso al que sigue. Dos grupos separados para que apagar uno no toque al otro.
var _bone_nodes: Array[Node3D] = []
var _bone_refs:  Array[CustomBone] = []
var _col_nodes:  Array[Node3D] = []
var _col_refs:   Array[CustomBone] = []

func is_bones_on() -> bool:     return _bones_on
func is_colliders_on() -> bool: return _colliders_on

func set_bones(value: bool) -> void:
	_bones_on = value
	_free_group(_bone_nodes, _bone_refs)
	if _bones_on:
		_build_bones()

func set_colliders(value: bool) -> void:
	_colliders_on = value
	_free_group(_col_nodes, _col_refs)
	if _colliders_on:
		_build_colliders()

## En _physics_process, no en _process: los huesos se resuelven en el frame de física, y leerlos desde
## el frame de render los mostraría un tick atrás.
func _physics_process(_delta: float) -> void:
	_follow(_bone_nodes, _bone_refs)
	_follow(_col_nodes, _col_refs)
	_update_line_lengths()

## Mientras ragdollea, el hueso está congelado y quien se mueve es su RigidBody3D. Misma regla que
## BoneInstantiator._sync_skinned_body.
func _source_transform(bone: CustomBone) -> Transform3D:
	if is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) \
			and (bi.ragdoll_util.is_active or bi.ragdoll_util.is_recovering):
		var rb: Node3D = bi.ragdoll_util.get_bodies().get(bone)
		if is_instance_valid(rb):
			return rb.global_transform
	return bone.global_transform

func _follow(nodes: Array[Node3D], refs: Array[CustomBone]) -> void:
	for i in nodes.size():
		if is_instance_valid(nodes[i]) and is_instance_valid(refs[i]):
			nodes[i].global_transform = _source_transform(refs[i])

## El brazo cambia de largo en runtime al agarrar algo, así que la línea se re-mide sola.
func _update_line_lengths() -> void:
	for i in _bone_nodes.size():
		if not (is_instance_valid(_bone_nodes[i]) and is_instance_valid(_bone_refs[i])):
			continue
		var line := _bone_nodes[i].get_node_or_null("Line") as MeshInstance3D
		var box := line.mesh as BoxMesh if line != null else null
		if box == null:
			continue
		var l: float = maxf(_bone_refs[i].capsule_dimensions.y, 0.0001)
		if absf(box.size.y - l) > 0.0001:
			box.size.y = l
			line.position.y = l * 0.5

func _build_bones() -> void:
	if not is_instance_valid(bi) or bi.custom_bones_util == null:
		return
	for bone in bi.custom_bones_util.get_all_bones():
		if not is_instance_valid(bone):
			continue
		var holder := Node3D.new()
		add_child(holder)

		# El eje +Y local del hueso ES su dirección, así que la línea va de (0,0,0) a (0,largo,0) sin
		# ninguna cuenta de orientación. La caja se arma a mano en vez de con
		# DebugUtil.create_debug_line_to_from porque esa calcula una base propia y acá hace falta poder
		# reescribirle el largo cada frame.
		var line := MeshInstance3D.new()
		line.name = "Line"
		var box := BoxMesh.new()
		box.size = Vector3(LINE_WIDTH, maxf(bone.capsule_dimensions.y, 0.0001), LINE_WIDTH)
		line.mesh = box
		line.position.y = box.size.y * 0.5
		line.material_override = _flat_material(BONE_COLOR)
		holder.add_child(line)

		holder.add_child(DebugUtil.create_debug_sphere(JOINT_COLOR, JOINT_SIZE, true, 6, 4))

		_bone_nodes.append(holder)
		_bone_refs.append(bone)

func _build_colliders() -> void:
	if not is_instance_valid(bi) or not is_instance_valid(bi.ragdoll_util):
		return
	var bodies := bi.ragdoll_util.get_bodies()
	for bone: CustomBone in bodies:
		var rb: Node = bodies[bone]
		if not (is_instance_valid(bone) and is_instance_valid(rb)):
			continue
		# La forma se LEE del collider real del ragdoll en vez de recalcularse: así el gizmo no puede
		# mentir si mañana cambia la fórmula de RagdollUtil.
		for child in rb.get_children():
			var cs := child as CollisionShape3D
			if cs == null:
				continue
			var caps := cs.shape as CapsuleShape3D
			if caps == null:
				continue
			var holder := Node3D.new()
			add_child(holder)
			holder.add_child(DebugUtil.create_debug_capsule(caps.radius, caps.height, cs.position.y))
			_col_nodes.append(holder)
			_col_refs.append(bone)
			break

func _free_group(nodes: Array[Node3D], refs: Array[CustomBone]) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	refs.clear()

static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = color
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat
