class_name FacadeProps
extends RefCounted

## LAS PIEZAS DE FACHADA, diseñadas en el cubo unitario (ver UnitMesh) y colocadas en la grilla rígida de
## una pared (ver RigidMatrix y FacadePlanner).
##
## ⚠ EL MARCO DE UNA FACHADA NO ES EL DE UN TECHO: `x` va a lo largo de la pared, `y` SALE HACIA LA CALLE y
## `z` SUBE. La cara `y = 0` es la que apoya contra la pared, y por eso no se dibuja: nunca se ve, y en una
## ciudad con cientos de miles de ventanas son dos triángulos por pieza.


## Una puerta: un panel sobre la pared.
static func door_unit(color: Color) -> UnitMesh:
	return _panel(color)


## Una ventana: por ahora un panel, para tantear el estilo. Es acá donde gana marco, vidrio o alféizar.
static func window_unit(color: Color) -> UnitMesh:
	return _panel(color)


## Una caja sin la cara que toca la pared: cinco caras, diez triángulos.
static func _panel(color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	var inside := Vector3(0.5, 0.5, 0.5)
	m.add_quad(Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1), inside, color)  # frente
	m.add_quad(Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), inside, color)  # -x
	m.add_quad(Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1), inside, color)  # +x
	m.add_quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), inside, color)  # abajo
	m.add_quad(Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), inside, color)  # arriba
	return m
