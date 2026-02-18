extends StaticBody3D
class_name Interactable

# 1. Aceptamos Node3D (para que puedas arrastrar el Pivote/Marker3D)
@export var meshes_visuales: Array[Node3D]

# 2. Devolvemos la variable para que ASIGNES TU MATERIAL BONITO
@export var highlight_material: Material

func interact(_player: Node3D):
	pass

func on_mouse_drag(_relative: Vector2):
	pass

func set_highlight(enabled: bool):
	var material_to_use = highlight_material if enabled else null
	
	# Recorremos la lista (que puede tener Pivotes o Meshes)
	for node in meshes_visuales:
		if node:
			_apply_recursive(node, material_to_use)

# Función espía: Busca meshes dentro de grupos/pivotes
func _apply_recursive(node: Node, mat: Material):
	# Si encontramos un Mesh, le ponemos el overlay
	if node is MeshInstance3D:
		node.material_overlay = mat
	
	# Seguimos buscando en los hijos (para encontrar el volante dentro del pivote)
	for child in node.get_children():
		_apply_recursive(child, mat)
