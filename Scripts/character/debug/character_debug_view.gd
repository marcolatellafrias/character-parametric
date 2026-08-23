class_name CharacterDebugView

## Estado GLOBAL de los visualizadores de debug de personajes. Los toggles del panel escriben acá y
## esto los aplica a todos los personajes de la escena, no solo al propio.
##
## Es estado estático a propósito. La alternativa —que cada toggle recorra la escena— dejaba afuera a
## los personajes que spawnean DESPUÉS de prender la opción, y a los que se regeneran al respawnear.
## Guardando el estado, `apply_to` se llama también al final de initialize_skeleton y cualquier
## personaje nuevo nace con lo que esté prendido.
##
## Enumerar es gratis: las cápsulas ya están en CharacterRigidBody3D.CHARACTER_GROUP, y el
## BoneInstantiator es su padre.

static var hide_character: bool = false
static var show_capsule:   bool = false
static var show_skeleton:  bool = false
static var show_colliders: bool = false
static var show_grab_cone: bool = false
static var ragdoll_color:  bool = false
## Poles, targets, anillos de alcance/zancada y sondeos del raycast de piernas. Apagado por defecto:
## son ayudas de autoría de la marcha y ensucian la vista el resto del tiempo.
static var show_gait_gizmos: bool = false

static func toggle_hide_character(tree: SceneTree) -> void:
	hide_character = not hide_character
	apply_all(tree)

static func toggle_capsule(tree: SceneTree) -> void:
	show_capsule = not show_capsule
	apply_all(tree)

static func toggle_skeleton(tree: SceneTree) -> void:
	show_skeleton = not show_skeleton
	apply_all(tree)

static func toggle_colliders(tree: SceneTree) -> void:
	show_colliders = not show_colliders
	apply_all(tree)

static func toggle_grab_cone(tree: SceneTree) -> void:
	show_grab_cone = not show_grab_cone
	apply_all(tree)

static func toggle_ragdoll_color(tree: SceneTree) -> void:
	ragdoll_color = not ragdoll_color
	apply_all(tree)

static func toggle_gait_gizmos(tree: SceneTree) -> void:
	show_gait_gizmos = not show_gait_gizmos
	apply_all(tree)

static func apply_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for rb in tree.get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		apply_to((rb as Node).get_parent() as BoneInstantiator)

## Deja UN personaje en el estado global. La llama initialize_skeleton al final, así el spawn y el
## respawn heredan lo que esté prendido.
static func apply_to(bi: BoneInstantiator) -> void:
	if not is_instance_valid(bi):
		return

	bi.set_character_visible(not hide_character)
	bi.show_grab_cone = show_grab_cone

	if is_instance_valid(bi.char_rigidbody) and is_instance_valid(bi.char_rigidbody.mesh_instance):
		bi.char_rigidbody.mesh_instance.visible = show_capsule

	if is_instance_valid(bi.ik_util):
		bi.ik_util.set_gizmos_visible(show_gait_gizmos)

	if is_instance_valid(bi.ragdoll_util):
		bi.ragdoll_util.debug_ragdoll_color = ragdoll_color

	# Los gizmos se crean recién si hace falta: un personaje con todo apagado no paga nada.
	if show_skeleton or show_colliders or is_instance_valid(bi.skeleton_debug):
		var draw := bi.get_skeleton_debug()
		draw.set_bones(show_skeleton)
		draw.set_colliders(show_colliders)
