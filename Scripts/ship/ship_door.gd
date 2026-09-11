class_name ShipDoor
extends Node

## COMPUERTA TRASERA — un cubo que se achica hacia arriba al abrirse.
##
## Es la versión de esqueleto de la compuerta elevadiza: la pieza de verdad, con su animación, viene
## con el modelo. Acá alcanza con que abra y cierre, que es lo que hace falta para probar entrar y
## salir de la nave.
##
## Se achica ANCLADA ARRIBA: el borde de arriba queda fijo y el de abajo sube. Es lo que hace una
## compuerta elevadiza, y además nunca le aparece geometría nueva de golpe a alguien parado en el hueco.
##
## ⚠ ABIERTA, EL COLLIDER SE APAGA en vez de quedar con alto cero. Una caja de tamaño cero es una forma
## degenerada para el motor de física; apagada, el hueco queda limpio.

## Segundos de cerrada a abierta.
const DURATION := 0.9

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _full_height := 0.0
var _top_y := 0.0
var _openness := 0.0
var _open := false
var _tween: Tween = null


func setup(shape: CollisionShape3D, mesh: MeshInstance3D) -> void:
	_shape = shape
	_mesh = mesh
	_full_height = (shape.shape as BoxShape3D).size.y
	_top_y = shape.position.y + _full_height * 0.5


## Cada vez que se APRIETA el botón, la compuerta cambia de estado. Por eso los botones son momentáneos
## y no toggle: con dos toggles (adentro y afuera) cada uno tendría su propio estado y podrían
## contradecirse — uno diciendo "abierta" y el otro "cerrada" con la compuerta en cualquiera de las dos.
func connect_button(button: TouchComponent) -> void:
	button.pressed.connect(toggle)


func toggle() -> void:
	_open = not _open
	if is_instance_valid(_tween):
		_tween.kill()
	var target := 1.0 if _open else 0.0
	_tween = create_tween()
	# La duración es proporcional a lo que falta: si se aprieta a mitad de camino, vuelve en la mitad.
	_tween.tween_method(_set_openness, _openness, target, DURATION * absf(target - _openness))


func _set_openness(value: float) -> void:
	_openness = value
	var height := _full_height * (1.0 - value)
	var solid := height > 0.01
	_shape.disabled = not solid
	_mesh.visible = solid
	if not solid:
		return
	(_shape.shape as BoxShape3D).size.y = height
	(_mesh.mesh as BoxMesh).size.y = height
	_shape.position.y = _top_y - height * 0.5
