class_name ShipDoor
extends Node

## LA COMPUERTA — las caras del gajo de atrás que tapan el hueco de la puerta (ver ShipHull).
##
## Para abrir se DESLIZAN HACIA ARRIBA siguiendo el domo: giran alrededor del centro de la esfera, sobre
## el eje horizontal que cruza la puerta de lado a lado, hasta quedar justo encima del hueco. Girar
## alrededor del centro de una esfera deja todo sobre la esfera, así que las caras no se despegan del
## domo en ningún momento. Van por fuera del vidrio y pasan sobre él sin tocarlo.
##
## Es la versión de esqueleto: la pieza de verdad, con su animación, viene con el modelo. Acá alcanza
## con que abra y cierre, que es lo que hace falta para probar entrar y salir de la nave.

## Segundos de cerrada a abierta.
const DURATION := 0.9

var _faces: Array[CollisionShape3D] = []
var _rest: Array[Transform3D] = []
var _pivot := Vector3.ZERO
var _axis := Vector3.RIGHT
var _travel := 0.0
var _openness := 0.0
var _open := false
var _tween: Tween = null


## `faces` son las caras en su lugar de cerrada; `pivot` y `axis`, el centro y el eje del giro; `travel`,
## cuánto giran para abrir del todo, en radianes.
func setup(faces: Array[CollisionShape3D], pivot: Vector3, axis: Vector3, travel: float) -> void:
	_faces = faces
	_rest.clear()
	for face in faces:
		_rest.append(face.transform)
	_pivot = pivot
	_axis = axis
	_travel = travel


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
	var turn := Basis(_axis, _travel * value)
	# Girar alrededor de `_pivot`: x' = turn·(x − pivot) + pivot.
	var slide := Transform3D(turn, _pivot - turn * _pivot)
	for i in _faces.size():
		_faces[i].transform = slide * _rest[i]
