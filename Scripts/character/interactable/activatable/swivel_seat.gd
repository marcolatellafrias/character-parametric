@tool
class_name SwivelSeat
extends Node3D

## SILLA GIRATORIA — el asiento del modelo (`Cube`) sobre un pie armado por código: un disco fijo en el
## piso y una columna que se estira hasta la base del asiento. Qué tan alto va lo decide
## SeatInteractable con `set_lift`; acá solo se dibuja.
##
## El pie no está en el modelo porque cambia de largo: estirar una malla deformaría también el disco.
## Disco y columna son redondos, así que girar la silla con el ocupante no les cambia nada.

const DISC_RADIUS := 0.14
const DISC_HEIGHT := 0.03
const COLUMN_RADIUS := 0.03
## Cuánto se mete la columna dentro del asiento: sin esto, al subirlo se vería la junta.
const COLUMN_OVERLAP := 0.03

var _top: MeshInstance3D = null
var _top_rest_y := 0.0
## Altura de la base del asiento, desde el piso, a su altura de modelo. Sale de la malla.
var _top_bottom := 0.0
var _column: MeshInstance3D = null
var _column_mesh: CylinderMesh = null


func _ready() -> void:
	_top = get_node_or_null("Cube") as MeshInstance3D
	if _top == null:
		push_warning("SwivelSeat: no hay un nodo 'Cube' con el asiento")
		return
	_top_rest_y = _top.position.y
	_top_bottom = _top_rest_y + _top.get_aabb().position.y
	var material := _top.get_surface_override_material(0)

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = DISC_RADIUS
	disc_mesh.bottom_radius = DISC_RADIUS
	disc_mesh.height = DISC_HEIGHT
	var disc := MeshInstance3D.new()
	disc.name = "disc"
	disc.mesh = disc_mesh
	disc.material_override = material
	disc.position.y = DISC_HEIGHT * 0.5
	add_child(disc)

	_column_mesh = CylinderMesh.new()
	_column_mesh.top_radius = COLUMN_RADIUS
	_column_mesh.bottom_radius = COLUMN_RADIUS
	_column = MeshInstance3D.new()
	_column.name = "column"
	_column.mesh = _column_mesh
	_column.material_override = material
	add_child(_column)
	set_lift(0.0)


## Cuánto sube el asiento respecto de su altura de modelo, en metros (negativo = baja).
func set_lift(lift: float) -> void:
	if _top == null:
		return
	_top.position.y = _top_rest_y + lift
	var length := maxf(_top_bottom + lift + COLUMN_OVERLAP - DISC_HEIGHT, 0.01)
	_column_mesh.height = length
	_column.position.y = DISC_HEIGHT + length * 0.5
