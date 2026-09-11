class_name ShipHull

## CASCO DE LA NAVE — hecho de cubos, cada uno de un color distinto.
##
## Es provisorio a propósito: el modelo de verdad viene después, desde Blender. Mientras tanto la nave
## tiene que existir en su tamaño real para probar cómo se vuela y cómo se usa por dentro, y cubos de
## colores distintos dejan ver de un vistazo qué pieza es cuál y dónde se pisa una con otra.
##
## Cada cubo es malla Y collider, con la misma medida. No hay formas raras: el día que llegue el modelo,
## esto se reemplaza entero sin que ninguna otra parte de la nave dependa de cómo estaba hecho.
##
## ── TODO SE MIDE EN CELDAS DE DASHBOARD ─────────────────────────────────────────────────────────
## La unidad de la nave es la celda, no el metro. Los dashboards son grillas de celdas, y el anillo de
## consolas tiene que alojar un número entero de ellas: midiendo el casco en la misma unidad, cambiar
## una medida nunca deja una consola con media celda colgando.
##
## La celda es `ProceduralDashboard.CELL`: 4 cm, sin separación. Los números de acá son grandes porque
## la celda es chica, y es chica para poder ubicar las cosas con precisión.
##
## Ejes: X a la derecha, Y arriba, −Z al frente (la ventana), +Z atrás (la compuerta). El origen es el
## centro de la base del piso, así que la altura de la nave es la de su panza.

const CELL := ProceduralDashboard.CELL

## Interior: ancho (X), alto (Y) y largo (Z), en celdas.
const INTERIOR := Vector3(128.0, 88.0, 128.0)
## Espesor de piso, techo y paredes.
const WALL := 4.0 * CELL
## Compuerta trasera: ancho y alto, en celdas. El ancho es también el diámetro del cilindro de carga.
const DOOR := Vector2(48.0, 56.0)
## Ventana delantera: ancho y alto, en celdas, y a qué altura del piso arranca.
const WINDOW := Vector2(80.0, 48.0)
const WINDOW_SILL := 24.0

## ── EL ANILLO DE CONSOLAS ────────────────────────────────────────────────────────────────────────
## Octágono parcial, metido hacia adentro de las paredes y mirando al centro. De sus ocho lados se
## ocupan cinco: el frente, los dos diagonales delanteros y los dos laterales, en octavos de vuelta
## desde el frente. El lado de la compuerta queda libre, y también los dos diagonales traseros: a esta
## distancia del centro invadirían el pasillo de carga justo al lado de la compuerta — es el hueco
## entre la puerta y los dashboards que pide la doc.
##
## El orden importa: la primera es la del frente, que es la de vuelo.
const CONSOLE_SIDES: Array[int] = [0, -1, 1, -2, 2]
const CONSOLE_COLUMNS := 40
## Filas del tablero: tan profundo como el volante, el control más grande. Lo que queda hasta la pared
## es un estante plano, cosmético.
const CONSOLE_ROWS := 12
## Altura de la BISAGRA de cada consola, desde el piso: el borde de abajo del tablero, del lado de quien
## lo usa. Desde ahí el tablero sube hacia la pared y el plano de abajo baja hacia ella.
const CONSOLE_HEIGHT := 0.75
## Inclinación del tablero desde la vertical: a 45° queda de frente a la mira del que está sentado.
const PANEL_TILT_DEG := 45.0
## Cuánto se mete hacia la pared, en el piso, el borde del plano de abajo. Inclinado así deja lugar para
## las rodillas debajo del tablero, y el asiento puede ir más cerca (ver Ship._add_pilot_seat).
const LOWER_SETBACK := 0.5
const PLATE_THICKNESS := 0.03
## Cuánto va la placa por detrás del plano de los controles.
const PLATE_BACK := 0.035

## Botones de la compuerta: altura desde el piso y separación del borde del hueco.
const BUTTON_HEIGHT := 1.2
const BUTTON_SIDE_GAP := 0.35
## Placa de la pared detrás de cada botón.
const BUTTON_PLATE := 6.0 * CELL
## El botón, en celdas: más grande que el estándar (`ProceduralDashboard.BUTTON`), para encontrarlo
## en la pared sin buscarlo.
const DOOR_BUTTON := Vector2i(4, 4)
## Cuánto sobresalen los botones de la cara de la pared.
const BUTTON_STANDOFF := 0.06

## Opacidad del casco exterior en modo traslúcido. Ver `Ship.translucent_walls`.
const SHELL_ALPHA := 0.25


## Lo que la nave necesita tocar después de construido el casco.
class Parts:
	var door_shape: CollisionShape3D
	var door_mesh: MeshInstance3D
	## Una por lado del anillo, en el orden de `CONSOLE_SIDES`: la primera es la del frente.
	var consoles: Array[ProceduralDashboard] = []
	## El de adentro y el de afuera de la compuerta.
	var door_buttons: Array[ProceduralDashboard] = []
	## El casco exterior —paredes, compuerta y techo—, que `Ship.translucent_walls` vuelve traslúcido.
	var shell: Array[MeshInstance3D] = []


static var _color_index := 0


static func interior_size() -> Vector3:
	return INTERIOR * CELL


## Distancia del centro a la cara interior de cada consola. Sale de que cada lado del octágono mida
## exactamente `CONSOLE_COLUMNS` celdas: lado = 2 · a · tan(22.5°).
static func console_apothem() -> float:
	return float(CONSOLE_COLUMNS) * CELL / (2.0 * tan(deg_to_rad(22.5)))


## Altura del borde de arriba del panel de una consola, desde el piso: lo más alto de un tablero.
static func panel_top_height() -> float:
	return CONSOLE_HEIGHT + float(CONSOLE_ROWS) * CELL * cos(deg_to_rad(PANEL_TILT_DEG))


## Cuánto se mete el plano de abajo detrás de la bisagra a `height` sobre el piso: el lugar que hay para
## las rodillas a esa altura.
static func knee_room_at(height: float) -> float:
	return LOWER_SETBACK * clampf(1.0 - height / CONSOLE_HEIGHT, 0.0, 1.0)


## Colores bien distintos entre piezas vecinas. El tono avanza por la razón áurea, que es la forma más
## barata de que dos índices seguidos nunca caigan cerca en la rueda de color.
static func debug_color(index: int) -> Color:
	return Color.from_hsv(fposmod(float(index) * 0.618034, 1.0), 0.55, 0.9)


## Arma el casco completo como hijos de `ship`. `console_presets` es lado → preset; los lados que no
## estén ahí quedan como slots vacíos.
static func build(ship: RigidBody3D, console_presets: Dictionary) -> Parts:
	_color_index = 0
	var parts := Parts.new()
	var size := interior_size()
	var hw := size.x * 0.5
	var hl := size.z * 0.5

	var slab := Vector3(size.x + 2.0 * WALL, WALL, size.z + 2.0 * WALL)
	_box(ship, "floor", slab, Vector3(0.0, WALL * 0.5, 0.0))
	_add_shell(parts, _box(ship, "ceiling", slab, Vector3(0.0, WALL + size.y + WALL * 0.5, 0.0)))
	# Las laterales van de punta a punta, esquinas incluidas; frente y fondo quedan entre ellas.
	var side_wall := Vector3(WALL, size.y, size.z + 2.0 * WALL)
	_add_shell(parts, _box(ship, "wall_left", side_wall, Vector3(-(hw + WALL * 0.5), WALL + size.y * 0.5, 0.0)))
	_add_shell(parts, _box(ship, "wall_right", side_wall, Vector3(hw + WALL * 0.5, WALL + size.y * 0.5, 0.0)))

	_build_front_wall(ship, parts, size, -(hl + WALL * 0.5))
	parts.door_shape = _build_back_wall(ship, parts, size, hl + WALL * 0.5)
	parts.door_mesh = parts.door_shape.get_child(0) as MeshInstance3D

	for side_index in CONSOLE_SIDES:
		var preset := console_presets.get(side_index) as DashboardPreset
		parts.consoles.append(_build_console(ship, side_index, preset))

	var button_x := DOOR.x * CELL * 0.5 + BUTTON_SIDE_GAP
	var button_y := WALL + BUTTON_HEIGHT
	parts.door_buttons.append(_build_button(ship, "door_button_inside",
		Vector3(button_x, button_y, hl - BUTTON_STANDOFF), true))
	parts.door_buttons.append(_build_button(ship, "door_button_outside",
		Vector3(button_x, button_y, hl + WALL + BUTTON_STANDOFF), false))
	return parts


## Frente: cuatro cubos alrededor del hueco de la ventana — abajo, arriba y los dos costados.
static func _build_front_wall(ship: RigidBody3D, parts: Parts, size: Vector3, z: float) -> void:
	var sill := WINDOW_SILL * CELL
	var win := WINDOW * CELL
	var top := size.y - sill - win.y
	var jamb := size.x * 0.5 - win.x * 0.5
	assert(top > 0.0 and jamb > 0.0, "ShipHull: la ventana no entra en la pared del frente")
	var mid_y := WALL + sill + win.y * 0.5
	_add_shell(parts, _box(ship, "front_below_window", Vector3(size.x, sill, WALL),
		Vector3(0.0, WALL + sill * 0.5, z)))
	_add_shell(parts, _box(ship, "front_above_window", Vector3(size.x, top, WALL),
		Vector3(0.0, WALL + sill + win.y + top * 0.5, z)))
	_add_shell(parts, _box(ship, "front_left_of_window", Vector3(jamb, win.y, WALL),
		Vector3(-(win.x * 0.5 + jamb * 0.5), mid_y, z)))
	_add_shell(parts, _box(ship, "front_right_of_window", Vector3(jamb, win.y, WALL),
		Vector3(win.x * 0.5 + jamb * 0.5, mid_y, z)))


## Fondo: tres cubos alrededor del hueco de la compuerta, y la compuerta misma. Devuelve la compuerta.
static func _build_back_wall(ship: RigidBody3D, parts: Parts, size: Vector3, z: float) -> CollisionShape3D:
	var door := DOOR * CELL
	var above := size.y - door.y
	var side_w := size.x * 0.5 - door.x * 0.5
	assert(above > 0.0 and side_w > 0.0, "ShipHull: la compuerta no entra en la pared del fondo")
	_add_shell(parts, _box(ship, "back_above_door", Vector3(size.x, above, WALL),
		Vector3(0.0, WALL + door.y + above * 0.5, z)))
	_add_shell(parts, _box(ship, "back_left_of_door", Vector3(side_w, door.y, WALL),
		Vector3(-(door.x * 0.5 + side_w * 0.5), WALL + door.y * 0.5, z)))
	_add_shell(parts, _box(ship, "back_right_of_door", Vector3(side_w, door.y, WALL),
		Vector3(door.x * 0.5 + side_w * 0.5, WALL + door.y * 0.5, z)))
	return _add_shell(parts, _box(ship, "door", Vector3(door.x, door.y, WALL),
		Vector3(0.0, WALL + door.y * 0.5, z)))


## Un lado del anillo, hecho de placas: el tablero inclinado con el dashboard encima, el plano de abajo
## —de la bisagra al piso, inclinado hacia la pared para dejar lugar a las rodillas— y un estante plano
## del borde de arriba del tablero hasta la pared, para cosas cosméticas.
##
## El dashboard de `ProceduralDashboard` es una grilla en su plano XY con la cara hacia +Z local, que
## arranca en su esquina superior izquierda y crece hacia −Y. Inclinado como atril, la fila de arriba
## queda del lado de la pared y la de abajo del lado de quien lo usa, que es lo natural.
static func _build_console(ship: RigidBody3D, side_index: int, preset: DashboardPreset) -> ProceduralDashboard:
	var theta := float(side_index) * PI * 0.25
	var outward := Vector3(sin(theta), 0.0, -cos(theta))
	# Origen en la bisagra; −Z local apunta hacia la pared y +Z hacia el centro, para donde mira el tablero.
	var hinge := Transform3D(Basis(Vector3.UP, -theta),
		outward * console_apothem() + Vector3.UP * (WALL + CONSOLE_HEIGHT))
	var tag := _side_tag(side_index)
	var width := float(CONSOLE_COLUMNS) * CELL
	var depth := float(CONSOLE_ROWS) * CELL
	var tilt := deg_to_rad(PANEL_TILT_DEG)

	# Tablero: sube desde la bisagra hacia la pared. En su marco, +Y sube por la pendiente y +Z es la cara.
	var panel := hinge * Transform3D(Basis(Vector3.RIGHT, -tilt), Vector3.ZERO)
	_box_xf(ship, "panel_%s" % tag, Vector3(width, depth, PLATE_THICKNESS),
		panel * Transform3D(Basis(), Vector3(0.0, depth * 0.5, -PLATE_BACK)))

	# Plano de abajo: de la bisagra al piso, con el borde del piso metido `LOWER_SETBACK` hacia la pared.
	var lean := atan2(LOWER_SETBACK, CONSOLE_HEIGHT)
	var lower_length := Vector2(LOWER_SETBACK, CONSOLE_HEIGHT).length()
	_box_xf(ship, "lower_%s" % tag, Vector3(width, lower_length, PLATE_THICKNESS),
		hinge * Transform3D(Basis(Vector3.RIGHT, lean), Vector3(0.0, -CONSOLE_HEIGHT * 0.5, -LOWER_SETBACK * 0.5)))

	# Estante cosmético: plano, del borde de arriba del tablero hasta la pared.
	var top := Vector3(0.0, depth * cos(tilt), -depth * sin(tilt))
	var shelf := interior_size().z * 0.5 - console_apothem() + top.z
	if shelf > 0.0:
		_box_xf(ship, "shelf_%s" % tag, Vector3(width, PLATE_THICKNESS, shelf),
			hinge * Transform3D(Basis(), top + Vector3(0.0, -PLATE_THICKNESS * 0.5, -shelf * 0.5)))

	var dash := ProceduralDashboard.new()
	dash.name = "dashboard_%s" % tag
	dash.grid_columns = CONSOLE_COLUMNS
	dash.grid_rows = CONSOLE_ROWS
	dash.custom_preset = preset if preset != null else _empty_preset()
	# La grilla arranca en su esquina superior izquierda: el borde de arriba del tablero, a la izquierda.
	dash.transform = panel * Transform3D(Basis(), Vector3(-width * 0.5, depth, 0.0))
	ship.add_child(dash)
	return dash


## Un botón de la compuerta: una placa en la pared y un dashboard del tamaño justo del botón.
static func _build_button(ship: RigidBody3D, part_name: String, target: Vector3,
		faces_inward: bool) -> ProceduralDashboard:
	# El dashboard mira a +Z local: el de adentro se da vuelta para mirar al interior.
	var at := Transform3D(Basis(Vector3.UP, PI) if faces_inward else Basis(), target)
	_box_xf(ship, "%s_plate" % part_name, Vector3(BUTTON_PLATE, BUTTON_PLATE, PLATE_THICKNESS),
		at * Transform3D(Basis(), Vector3(0.0, 0.0, -PLATE_BACK)))
	var dash := ProceduralDashboard.new()
	dash.name = part_name
	dash.grid_columns = DOOR_BUTTON.x
	dash.grid_rows = DOOR_BUTTON.y
	dash.custom_preset = _button_preset()
	# La grilla arranca en su esquina superior izquierda: corrida la mitad del botón, queda centrado en
	# `target`.
	var half := Vector2(DOOR_BUTTON) * CELL * 0.5
	dash.transform = at * Transform3D(Basis(), Vector3(-half.x, half.y, 0.0))
	ship.add_child(dash)
	return dash


static func _side_tag(side_index: int) -> String:
	match side_index:
		0:
			return "front"
		1:
			return "front_right"
		-1:
			return "front_left"
		2:
			return "right"
		-2:
			return "left"
	return "side_%d" % side_index


## Un slot vacío. Hace falta un preset explícito: sin preset, `ProceduralDashboard` rellena la grilla
## con controles al azar.
static func _empty_preset() -> DashboardPreset:
	var p := DashboardPreset.new()
	p.fill_remaining_random = false
	return p


static func _button_preset() -> DashboardPreset:
	var d := ControlDefinition.new()
	d.type = ControlDefinition.ControlType.TOUCH
	d.grid_size = DOOR_BUTTON
	# Momentáneo y no toggle: con dos botones de toggle (adentro y afuera) cada uno tendría su propio
	# estado y podrían contradecirse. Ver ShipDoor.connect_button.
	d.is_toggle = false
	var slot := DashboardSlot.new()
	slot.cell = Vector2i(0, 0)
	slot.definition = d
	var p := _empty_preset()
	var slots: Array[DashboardSlot] = [slot]
	p.fixed_slots = slots
	return p


## Anota una pieza como parte del casco exterior. Devuelve la misma forma, para poder encadenarlo.
static func _add_shell(parts: Parts, shape: CollisionShape3D) -> CollisionShape3D:
	parts.shell.append(shape.get_child(0) as MeshInstance3D)
	return shape


## Pasa una pieza a medio traslúcida o de vuelta a opaca, conservando su color.
static func set_translucent(mesh: MeshInstance3D, on: bool) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = SHELL_ALPHA if on else 1.0


static func _box(ship: RigidBody3D, part_name: String, size: Vector3, center: Vector3) -> CollisionShape3D:
	return _box_xf(ship, part_name, size, Transform3D(Basis(), center))


## Un cubo: collider y malla de la misma medida, en su color.
##
## ⚠ EL COLLIDER VA DIRECTO BAJO LA NAVE, nunca anidado en un nodo intermedio: un `CollisionShape3D`
## solo le da forma al cuerpo del que es hijo DIRECTO. Por eso cada pieza trae su transform ya
## calculado en el espacio de la nave, en vez de colgar de un nodo "consola" o "pared".
static func _box_xf(ship: RigidBody3D, part_name: String, size: Vector3, xform: Transform3D) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.name = part_name
	shape.shape = box
	shape.transform = xform

	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = debug_color(_color_index)
	_color_index += 1
	var view := MeshInstance3D.new()
	view.name = "mesh"
	view.mesh = mesh
	view.material_override = mat
	shape.add_child(view)

	ship.add_child(shape)
	return shape
