class_name SidewalkProps
extends RefCounted

## LAS PIEZAS DE VEREDA, diseñadas en el cubo unitario (ver UnitMesh) y colocadas por GridPlacer, como
## las de techo: acá no hay metros ni celdas, solo proporciones. El tamaño real lo pone la región donde se
## coloca, así que la misma pieza sirve para cualquier ancho de vereda y de calle.

## Qué pieza va en una zona de vereda (ver TraversalGenerator._generate_floor_sidewalks).
enum Piece { STRIP, CORNER, CURVED_CORNER, CHAMFER, PLAZA }

const PIECE_NAMES: Array[String] = ["tira", "esquina", "esquina curva", "relleno de ochava", "plaza"]

const CORNER_SEGMENTS := 8


static func piece_name(piece: int) -> String:
	return PIECE_NAMES[piece] if piece >= 0 and piece < PIECE_NAMES.size() else "?"


## La mesh de una pieza, girada `k` cuartos de vuelta para la esquina que le toca (0 NO, 1 NE, 2 SE, 3 SO;
## las piezas sin orientación lo ignoran).
static func unit_for(piece: int, k: int, color: Color) -> UnitMesh:
	match piece:
		Piece.CURVED_CORNER:
			return corner_unit(k, color)
		Piece.CHAMFER:
			return chamfer_fill_unit(k, color)
		_:
			return slab_unit(color)


## La losa: una tira recta, una esquina cuadrada o una plaza.
static func slab_unit(color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	m.add_box(Vector3.ZERO, Vector3.ONE, color)
	return m


## LA ESQUINA CURVA, la de manzana: donde dos calles se cruzan y el cordón dobla. Canónica para la esquina
## NOROESTE del módulo: la esquina interior —la del núcleo del edificio— en (1, 1) y la exterior, la que da
## a las dos calles, en (0, 0). El cordón es un cuarto de círculo centrado en la interior, de radio `radius`
## (1 = la esquina entera); lo que queda del cuadrado hacia (0, 0) es calle. Deformada a una región de
## a × b celdas sale un cuarto de elipse, así que sirve para cualquier ancho de vereda. Los dos lados rectos,
## en x = 1 y z = 1, son los que tocan las tiras vecinas. `k` cuartos de vuelta la llevan a las otras
## esquinas: 1 noreste, 2 sureste, 3 suroeste.
static func corner_unit(k: int, color: Color, radius: float = 1.0) -> UnitMesh:
	var m := UnitMesh.new()
	var centre := Vector2(1.0, 1.0)
	# Un punto adentro del cuarto de disco, para orientar las caras.
	var inside := Vector3(1.0 - radius * 0.3, 0.5, 1.0 - radius * 0.3)
	var arc: Array[Vector2] = []
	for i in CORNER_SEGMENTS + 1:
		var a := PI * 0.5 * float(i) / float(CORNER_SEGMENTS)
		arc.append(centre + Vector2(-sin(a), -cos(a)) * radius)

	for i in CORNER_SEGMENTS:
		var p := arc[i]
		var q := arc[i + 1]
		m.add_tri(_top(centre), _top(p), _top(q), inside, color)
		m.add_tri(_bottom(centre), _bottom(p), _bottom(q), inside, color)
		# El cordón.
		m.add_quad(_bottom(p), _bottom(q), _top(q), _top(p), inside, color)
	var first := arc[0]
	var last := arc[CORNER_SEGMENTS]
	m.add_quad(_bottom(first), _bottom(centre), _top(centre), _top(first), inside, color)
	m.add_quad(_bottom(centre), _bottom(last), _top(last), _top(centre), inside, color)
	return m.rotated(k)


## LO QUE LA ESQUINA CURVA DEJA COMO CALLE, como polígono en el cuadrado unitario de su región: la esquina
## exterior y el arco del cordón de `corner_unit`, con los mismos puntos —es su complemento exacto—, girado
## `k` como ella. La malla de calles lo rellena (ver City._ground_aprons).
static func curb_outside(k: int, radius: float = 1.0) -> PackedVector2Array:
	var centre := Vector2(1.0, 1.0)
	var out := PackedVector2Array([Vector2(0.0, 0.0)])
	for i in CORNER_SEGMENTS + 1:
		var a := PI * 0.5 * float(i) / float(CORNER_SEGMENTS)
		out.append(centre + Vector2(-sin(a), -cos(a)) * radius)
	for i in out.size():
		var p := UnitMesh._rot_point(Vector3(out[i].x, 0.0, out[i].y), k)
		out[i] = Vector2(p.x, p.z)
	return out


## EL RELLENO DE OCHAVA: el triángulo del núcleo que el chaflán le quitó al edificio, para que la vereda
## llegue hasta la pared diagonal. Canónico para la esquina NOROESTE: la región es el cuadrado del chaflán
## en la esquina del núcleo, el ángulo recto en (0, 0) —la esquina que el edificio ya no ocupa— y la
## hipotenusa de (1, 0) a (0, 1), que es exactamente la base de la pared ochavada (ver
## BuildingModule.get_wall_cells, el chaflán). Sirve igual para el chaflán cóncavo de un
## callejón: también es un triángulo de núcleo sin edificio.
static func chamfer_fill_unit(k: int, color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	var a := Vector2(0.0, 0.0)
	var b := Vector2(1.0, 0.0)
	var c := Vector2(0.0, 1.0)
	var inside := Vector3(1.0 / 3.0, 0.5, 1.0 / 3.0)
	m.add_tri(_top(a), _top(b), _top(c), inside, color)
	m.add_tri(_bottom(a), _bottom(b), _bottom(c), inside, color)
	m.add_quad(_bottom(a), _bottom(b), _top(b), _top(a), inside, color)
	m.add_quad(_bottom(b), _bottom(c), _top(c), _top(b), inside, color)
	m.add_quad(_bottom(c), _bottom(a), _top(a), _top(c), inside, color)
	return m.rotated(k)


static func _bottom(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


static func _top(p: Vector2) -> Vector3:
	return Vector3(p.x, 1.0, p.y)
