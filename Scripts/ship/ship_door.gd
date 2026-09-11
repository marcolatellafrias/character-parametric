class_name ShipDoor
extends Node

## LA COMPUERTA — abre y cierra desde sus botones. CÓMO se mueve lo pone el casco, que sabe de qué está
## hecha: la del domo se desliza hacia arriba siguiendo el domo, la de la caja se achica hacia arriba (ver
## DomeHull y BoxHull). Acá queda lo que es igual en las dos: el estado, los botones y el tiempo.
##
## Es la versión de esqueleto: la pieza de verdad, con su animación, viene con el modelo. Acá alcanza
## con que abra y cierre, que es lo que hace falta para probar entrar y salir de la nave.

## Segundos de cerrada a abierta.
const DURATION := 0.9

var _motion: Callable
var _openness := 0.0
var _open := false
var _tween: Tween = null


## `motion` recibe cuánto está abierta, de 0 a 1, y mueve las piezas.
func setup(motion: Callable) -> void:
	_motion = motion


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
	_motion.call(value)
