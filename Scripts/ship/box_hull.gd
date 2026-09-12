class_name BoxHull
extends ShipHull

## LA CAJA — una habitación de cubos opacos, cada uno de un color, con una ventana adelante y la compuerta
## atrás. Lo común (el anillo de módulos, los asientos, los botones) está en ShipHull; acá va lo que es de
## la caja.
##
## Viene en dos tamaños (ver `large` y `small`): la GRANDE tiene la planta y el alto del domo, para
## compararlas de igual a igual; la CHICA, la mitad de lado y el mismo alto, así queda un cubo. La ventana y
## la compuerta son las mismas en las dos, las del diseño cúbico original: son de escala humana —agrandadas
## con la caja, la ventana quedaría por encima de la mira del piloto—.
##
## Las paredes, el techo y la compuerta son la cáscara que el toggle de paredes traslúcidas vuelve medio
## transparente (ver Ship.translucent_walls): desde afuera se ve al personaje con los controles.
##
## ── EL ANILLO DE MÓDULOS ─────────────────────────────────────────────────────────────────────────
## Un octógono: cuatro lados de frente a las paredes y cuatro cortando las esquinas. Sus lados son lo más
## anchos que se puede —y con eso el anillo, lo más grande—: los que dan a una pared quedan con el estante
## mínimo (ver `_ring_fits`), y los de las esquinas tienen siempre más lugar. Cada lado es el módulo
## principal, de `MAIN_COLUMNS`, con uno a cada costado que se lleva el resto: en la caja grande,
## gabinetes; en la chica, más angostos que `CABINET_MIN_COLUMNS`, siguen el atril principal, lisos.

## Compuerta trasera: ancho y alto, en celdas (1,92 × 2,24 m). El ancho es también el diámetro del
## cilindro de carga.
const DOOR := Vector2(48.0, 56.0)
## Ventana delantera: ancho y alto, en celdas (3,20 × 1,92 m), y a qué altura del piso arranca (0,96 m).
const WINDOW := Vector2(80.0, 48.0)
const WINDOW_SILL := 24.0
## Lados del anillo.
const RING_SIDES := 8
## Lo menos que mide un gabinete a los costados del principal: el control de relleno más grande, de 6, con
## una celda de aire a cada lado. Más angostos, los costados van lisos.
const CABINET_MIN_COLUMNS := 8

## Medio lado y alto interiores (ver `large` y `small`).
var half_side: float
var room_height: float
## Columnas de cada módulo de los costados de un lado: las más que entran.
var _flank_columns := 0


## La grande: la planta y el alto del domo, 252 × 126 × 252 celdas (10,08 × 5,04 × 10,08 m).
static func large() -> BoxHull:
	return BoxHull.new(HALF_WIDTH, HALF_WIDTH)


## La chica: la mitad de lado y el mismo alto, un cubo de 126 celdas (5,04 m).
static func small() -> BoxHull:
	return BoxHull.new(HALF_WIDTH * 0.5, HALF_WIDTH)


func _init(box_half_side: float, box_height: float) -> void:
	half_side = box_half_side
	room_height = box_height
	# El lado crece de a dos columnas —una por costado, así el principal queda en el medio— mientras entre.
	while _ring_fits(RING_SIDES, MAIN_COLUMNS + 2 * (_flank_columns + 1)):
		_flank_columns += 1


func console_sides() -> int:
	return RING_SIDES


## Qué va en cada lado: el atril principal en el medio —con tablero volador donde puede haber asiento, ver
## `_seat_layouts`— y a los costados gabinetes, bajos junto a las paredes y altos en las diagonales; o, si
## no entran, la continuación lisa del atril.
func _side_modules(side_index: int) -> Array:
	var k := absi(side_index)
	var main := Module.new(ModuleType.LECTERN, MAIN_COLUMNS, k != 1)
	if _flank_columns == 0:
		return [main]
	if _flank_columns < CABINET_MIN_COLUMNS:
		return [Module.new(ModuleType.LECTERN, _flank_columns, false, true), main,
			Module.new(ModuleType.LECTERN, _flank_columns, false, true)]
	var cabinet := ModuleType.TALL if k % 2 == 1 else ModuleType.SHORT
	return [Module.new(cabinet, _flank_columns), main, Module.new(cabinet, _flank_columns)]


## Hasta la pared en línea recta: las paredes son planos verticales en x = ±`half_side` y z = ±`half_side`.
func _wall_distance(point: Vector3, dir: Vector3, _height: float) -> float:
	var limit := half_side - CONSOLE_WALL_GAP
	var distance := INF
	for axis: int in [0, 2]:
		if absf(dir[axis]) > 1e-6:
			distance = minf(distance, (limit * signf(dir[axis]) - point[axis]) / dir[axis])
	return distance


func door_width() -> float:
	return DOOR.x * CELL


func _seat_layouts() -> Dictionary:
	return {1: [0], 3: [0, -2, 2], 4: [0, -2, 2, 3]}


## A media altura, en el medio.
func center_of_mass() -> Vector3:
	return Vector3.UP * (WALL + room_height * 0.5)


## Hasta la cara de afuera de la pared del fondo.
func half_extent() -> float:
	return half_side + WALL


func _build_shell(ship: RigidBody3D, parts: ShipHull.Parts) -> void:
	assert(_ring_fits(RING_SIDES, side_columns()), "BoxHull: el octógono no entra ni con el módulo principal solo")
	var size := Vector3(2.0 * half_side, room_height, 2.0 * half_side)
	var hw := size.x * 0.5
	var hl := size.z * 0.5

	var slab := Vector3(size.x + 2.0 * WALL, WALL, size.z + 2.0 * WALL)
	_box(ship, "floor", slab, Vector3(0.0, WALL * 0.5, 0.0))
	_shell(parts, _box(ship, "ceiling", slab, Vector3(0.0, WALL + size.y + WALL * 0.5, 0.0)))
	# Las laterales van de punta a punta, esquinas incluidas; frente y fondo quedan entre ellas.
	var side_wall := Vector3(WALL, size.y, size.z + 2.0 * WALL)
	_shell(parts, _box(ship, "wall_left", side_wall, Vector3(-(hw + WALL * 0.5), WALL + size.y * 0.5, 0.0)))
	_shell(parts, _box(ship, "wall_right", side_wall, Vector3(hw + WALL * 0.5, WALL + size.y * 0.5, 0.0)))

	_build_front_wall(ship, parts, size, -(hl + WALL * 0.5))
	var door := _build_back_wall(ship, parts, size, hl + WALL * 0.5)
	var door_mesh := door.get_child(0) as MeshInstance3D
	var full := (door.shape as BoxShape3D).size.y
	var top_y := door.position.y + full * 0.5

	# La compuerta se ACHICA HACIA ARRIBA: el borde de arriba queda fijo y el de abajo sube, como una
	# compuerta elevadiza; nunca le aparece geometría de golpe a alguien parado en el hueco. Abierta, el
	# collider se apaga: una caja de alto cero es una forma degenerada para el motor de física.
	parts.door_motion = func(openness: float) -> void:
		var height := full * (1.0 - openness)
		var solid := height > 0.01
		door.disabled = not solid
		door_mesh.visible = solid
		if solid:
			(door.shape as BoxShape3D).size.y = height
			(door_mesh.mesh as BoxMesh).size.y = height
			door.position.y = top_y - height * 0.5


## Frente: cuatro cubos alrededor del hueco de la ventana — abajo, arriba y los dos costados.
func _build_front_wall(ship: RigidBody3D, parts: ShipHull.Parts, size: Vector3, z: float) -> void:
	var sill := WINDOW_SILL * CELL
	var win := WINDOW * CELL
	var top := size.y - sill - win.y
	var jamb := size.x * 0.5 - win.x * 0.5
	assert(top > 0.0 and jamb > 0.0, "BoxHull: la ventana no entra en la pared del frente")
	var mid_y := WALL + sill + win.y * 0.5
	_shell(parts, _box(ship, "front_below_window", Vector3(size.x, sill, WALL),
		Vector3(0.0, WALL + sill * 0.5, z)))
	_shell(parts, _box(ship, "front_above_window", Vector3(size.x, top, WALL),
		Vector3(0.0, WALL + sill + win.y + top * 0.5, z)))
	_shell(parts, _box(ship, "front_left_of_window", Vector3(jamb, win.y, WALL),
		Vector3(-(win.x * 0.5 + jamb * 0.5), mid_y, z)))
	_shell(parts, _box(ship, "front_right_of_window", Vector3(jamb, win.y, WALL),
		Vector3(win.x * 0.5 + jamb * 0.5, mid_y, z)))


## Fondo: tres cubos alrededor del hueco de la compuerta, y la compuerta misma. Devuelve la compuerta.
func _build_back_wall(ship: RigidBody3D, parts: ShipHull.Parts, size: Vector3, z: float) -> CollisionShape3D:
	var door := DOOR * CELL
	var above := size.y - door.y
	var side_w := size.x * 0.5 - door.x * 0.5
	assert(above > 0.0 and side_w > 0.0, "BoxHull: la compuerta no entra en la pared del fondo")
	_shell(parts, _box(ship, "back_above_door", Vector3(size.x, above, WALL),
		Vector3(0.0, WALL + door.y + above * 0.5, z)))
	_shell(parts, _box(ship, "back_left_of_door", Vector3(side_w, door.y, WALL),
		Vector3(-(door.x * 0.5 + side_w * 0.5), WALL + door.y * 0.5, z)))
	_shell(parts, _box(ship, "back_right_of_door", Vector3(side_w, door.y, WALL),
		Vector3(door.x * 0.5 + side_w * 0.5, WALL + door.y * 0.5, z)))
	return _shell(parts, _box(ship, "door", Vector3(door.x, door.y, WALL),
		Vector3(0.0, WALL + door.y * 0.5, z)))


## Los botones de la compuerta: en la pared del fondo, al costado del hueco, uno mirando adentro y otro
## afuera.
func _build_door_buttons(ship: RigidBody3D, parts: ShipHull.Parts) -> void:
	var x := DOOR.x * CELL * 0.5 + BUTTON_SIDE_GAP
	var y := WALL + BUTTON_HEIGHT
	var wall := half_side  # la cara de adentro de la pared del fondo
	parts.door_buttons.append(_build_button(ship, "door_button_inside",
		Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, wall - BUTTON_STANDOFF)), BUTTON_STANDOFF))
	parts.door_buttons.append(_build_button(ship, "door_button_outside",
		Transform3D(Basis(), Vector3(x, y, wall + WALL + BUTTON_STANDOFF)), BUTTON_STANDOFF))


func _box(ship: RigidBody3D, part_name: String, size: Vector3, center: Vector3) -> CollisionShape3D:
	return _box_xf(ship, part_name, size, Transform3D(Basis(), center))
