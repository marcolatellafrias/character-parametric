class_name BoxHull
extends ShipHull

## LA CAJA — una habitación de cubos opacos, cada uno de un color, con una ventana adelante y la compuerta
## atrás. Lo común (el anillo de módulos, los asientos, los botones) está en ShipHull; acá va lo que es de
## la caja.
##
## Tiene la planta del domo —de lado, su diámetro— y su alto, para compararlas de igual a igual. La ventana
## y la compuerta son las del diseño cúbico original: agrandadas en proporción, la ventana quedaría por
## encima de la mira del piloto.
##
## Las paredes, el techo y la compuerta son la cáscara que el toggle de paredes traslúcidas vuelve medio
## transparente (ver Ship.translucent_walls): desde afuera se ve al personaje con los controles.
##
## ── EL ANILLO DE MÓDULOS ─────────────────────────────────────────────────────────────────────────
## Un octógono: cuatro lados de frente a las paredes y cuatro cortando las esquinas, así queda poco hueco
## en ellas. Cada lado son tres módulos, `SIDE_MODULE_COLUMNS` + `MAIN_COLUMNS` + `SIDE_MODULE_COLUMNS`
## (80 columnas): el del medio, el principal, y dos a los costados.

## Alto interior: el del domo, que es su radio.
const HEIGHT := HALF_WIDTH
## Compuerta trasera: ancho y alto, en celdas (1,92 × 2,24 m). El ancho es también el diámetro del
## cilindro de carga.
const DOOR := Vector2(48.0, 56.0)
## Ventana delantera: ancho y alto, en celdas (3,20 × 1,92 m), y a qué altura del piso arranca (0,96 m).
const WINDOW := Vector2(80.0, 48.0)
const WINDOW_SILL := 24.0
## Lados del anillo, y columnas de los módulos de los costados de cada lado.
const RING_SIDES := 8
const SIDE_MODULE_COLUMNS := 24


func console_sides() -> int:
	return RING_SIDES


## Qué va en cada lado: el atril principal en el medio —con tablero volador donde hay asiento, ver
## `_seat_layouts`— y gabinetes a los costados: bajos junto a las paredes, altos en las diagonales.
func _side_modules(side_index: int) -> Array:
	var k := absi(side_index)
	var cabinet := ModuleType.TALL if k % 2 == 1 else ModuleType.SHORT
	return [
		Module.new(cabinet, SIDE_MODULE_COLUMNS),
		Module.new(ModuleType.LECTERN, MAIN_COLUMNS, k != 1),
		Module.new(cabinet, SIDE_MODULE_COLUMNS),
	]


## Hasta la pared en línea recta: las paredes son planos verticales en x = ±`HALF_WIDTH` y z = ±`HALF_WIDTH`.
func _wall_distance(point: Vector3, dir: Vector3, _height: float) -> float:
	var limit := HALF_WIDTH - CONSOLE_WALL_GAP
	var distance := INF
	for axis: int in [0, 2]:
		if absf(dir[axis]) > 1e-6:
			distance = minf(distance, (limit * signf(dir[axis]) - point[axis]) / dir[axis])
	return distance


func door_width() -> float:
	return DOOR.x * CELL


func _seat_layouts() -> Dictionary:
	return {1: [0], 4: [0, -2, 2, 3]}


## A media altura, en el medio.
func center_of_mass() -> Vector3:
	return Vector3.UP * (WALL + HEIGHT * 0.5)


func _build_shell(ship: RigidBody3D, parts: ShipHull.Parts) -> void:
	assert(_ring_fits(RING_SIDES), "BoxHull: los lados del octógono no entran con su estante")
	var size := Vector3(2.0 * HALF_WIDTH, HEIGHT, 2.0 * HALF_WIDTH)
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
	var wall := HALF_WIDTH  # la cara de adentro de la pared del fondo
	parts.door_buttons.append(_build_button(ship, "door_button_inside",
		Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, wall - BUTTON_STANDOFF)), BUTTON_STANDOFF))
	parts.door_buttons.append(_build_button(ship, "door_button_outside",
		Transform3D(Basis(), Vector3(x, y, wall + WALL + BUTTON_STANDOFF)), BUTTON_STANDOFF))


func _box(ship: RigidBody3D, part_name: String, size: Vector3, center: Vector3) -> CollisionShape3D:
	return _box_xf(ship, part_name, size, Transform3D(Basis(), center))
