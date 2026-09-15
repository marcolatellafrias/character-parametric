class_name Gate
extends Node3D

## EL PORTÓN DE UN EDIFICIO: la hoja que sube en la abertura de una puerta `moving` (ver DoorArchetype) y un
## interruptor a cada lado de la pared. Es la compuerta de la nave puesta en un edificio (ver ShipDoor y
## BoxHull): la hoja se achica hacia arriba —el borde de arriba fijo, el de abajo sube—, abierta se le apaga
## el collider, y cada apretada de un botón la cambia de estado, así los dos botones nunca se contradicen.
## Cada botón es un tablero de un control (ProceduralDashboard), como los de la nave.
##
## La abertura ya está cortada en la piel con su espesor (ver BuildingSkin.add_opening); la hoja va en el
## medio de ese espesor. El estado no viaja por la red todavía, como el de la nave.

const LEAF_M := 0.12
const LEAF_COLOR := Color(0.35, 0.33, 0.3)
## Los botones: a esta altura del piso del hueco, a esta distancia de su borde, sobre una placa que los
## separa de la pared.
const BUTTON_HEIGHT := 1.2
const BUTTON_SIDE_GAP := 0.35
const BUTTON_PLATE := 6.0 * ProceduralDashboard.CELL
const BUTTON_STANDOFF := 0.06
const BUTTON := Vector2i(4, 4)

var _door := ShipDoor.new()
var _buttons: Array[ProceduralDashboard] = []


## Un portón en la abertura `quad` —`[b0, b1, t1, t0]` sobre la cara exterior de la pared, ver
## SampleWall.opening_quad— de una pared de espesor `thickness` que mira a `outward`.
static func build(parent: Node3D, gate_name: String, quad: Array[Vector3], outward: Vector3,
		thickness: float) -> Gate:
	var gate := Gate.new()
	gate.name = gate_name
	var along := quad[1] - quad[0]
	var width := along.length()
	var height := (quad[3] - quad[0]).length()
	# El marco del portón: el centro del hueco sobre la cara exterior, `x` a lo largo, `z` hacia afuera.
	var x := along / width
	var z := outward.normalized()
	gate.transform = Transform3D(Basis(x, z.cross(x).normalized(), z), (quad[0] + quad[2]) * 0.5)

	# La hoja, en el medio del espesor.
	var leaf := StaticBody3D.new()
	leaf.name = "Leaf"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, LEAF_M)
	shape.shape = box
	leaf.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = LEAF_COLOR
	mesh.material_override = material
	leaf.add_child(mesh)
	leaf.position = Vector3(0.0, 0.0, -thickness * 0.5)
	gate.add_child(leaf)

	var top_y := height * 0.5
	gate._door.name = "Door"
	gate.add_child(gate._door)
	gate._door.setup(func(openness: float) -> void:
		var open_height := height * (1.0 - openness)
		var solid := open_height > 0.01
		shape.disabled = not solid
		mesh.visible = solid
		if solid:
			box.size.y = open_height
			box_mesh.size.y = open_height
			leaf.position.y = top_y - open_height * 0.5)

	# Un botón afuera y otro adentro, a la derecha del hueco visto de frente a la pared: el de adentro va
	# sobre la cara interior, dado vuelta.
	var plate_material := StandardMaterial3D.new()
	plate_material.albedo_color = LEAF_COLOR.darkened(0.3)
	for side: float in [1.0, -1.0]:
		var outside := side > 0.0
		var at := Transform3D(Basis(Vector3.UP, 0.0 if outside else PI), Vector3(
			side * (width * 0.5 + BUTTON_SIDE_GAP + BUTTON_PLATE * 0.5), BUTTON_HEIGHT - height * 0.5,
			BUTTON_STANDOFF if outside else -thickness - BUTTON_STANDOFF))
		var plate := MeshInstance3D.new()
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(BUTTON_PLATE, BUTTON_PLATE, BUTTON_STANDOFF)
		plate.mesh = plate_mesh
		plate.material_override = plate_material
		plate.transform = at * Transform3D(Basis(), Vector3(0.0, 0.0, -BUTTON_STANDOFF * 0.5))
		gate.add_child(plate)
		var dash := ProceduralDashboard.new()
		dash.name = "button_out" if outside else "button_in"
		dash.grid_columns = BUTTON.x
		dash.grid_rows = BUTTON.y
		var button := ControlArchetype.definition_of("button")
		button.grid_size = BUTTON
		dash.custom_preset = DashboardPreset.single(button)
		# La grilla arranca en su esquina superior izquierda: corrida la mitad del botón, queda centrado.
		var half := Vector2(BUTTON) * ProceduralDashboard.CELL * 0.5
		dash.transform = at * Transform3D(Basis(), Vector3(-half.x, half.y, 0.0))
		gate.add_child(dash)
		gate._buttons.append(dash)
	# Al árbol con todo armado: así `_ready` encuentra los botones ya generados.
	parent.add_child(gate)
	return gate


## Los tableros ya generaron sus controles (los hijos entran al árbol antes que el padre).
func _ready() -> void:
	for dash in _buttons:
		var touch := dash.get_node_or_null("ctrl_0/Control") as TouchComponent
		if touch != null:
			_door.connect_button(touch)
