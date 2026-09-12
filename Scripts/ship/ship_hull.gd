class_name ShipHull
extends RefCounted

## CASCO DE LA NAVE — lo que comparten todas las formas: el anillo de módulos, los asientos, los botones
## de la compuerta, las piezas y sus colores. Cada forma pone lo suyo —la cáscara, el piso, cómo se mueve
## la compuerta, dónde está la pared y qué módulos lleva cada lado—: `DomeHull`, un domo de vidrio, y
## `BoxHull`, una caja. Las dos se siguen probando, y Ship elige cuál arma.
##
## Es provisorio a propósito: el modelo de verdad viene después, desde Blender. Mientras tanto la nave
## tiene que existir en su tamaño real para probar cómo se vuela y cómo se usa por dentro. Se arma con
## piezas simples, cada una malla Y collider de la misma forma, y cada una de un color distinto a su
## vecina: se ve de un vistazo qué pieza es cuál. El día que llegue el modelo, esto se reemplaza entero
## sin que ninguna otra parte de la nave dependa de cómo estaba hecho.
##
## ── SE MIDE EN CELDAS DE DASHBOARD ──────────────────────────────────────────────────────────────
## La unidad de la nave es la celda, no el metro: el ancho, el alto y los módulos. Los dashboards son
## grillas de celdas, y cada módulo tiene que alojar un número entero de ellas. La celda es
## `ProceduralDashboard.CELL`: 4 cm, sin separación.
##
## ── EL ANILLO DE MÓDULOS ─────────────────────────────────────────────────────────────────────────
## Un polígono regular que mira al centro, lo más afuera que se puede. Cada LADO es una fila recta de
## MÓDULOS pegados (ver `_side_modules`): el domo, redondo, lleva muchos lados de un módulo; la caja,
## cuadrada, un octógono de lados de hasta tres. El módulo del medio de cada lado es el PRINCIPAL: el que mira el
## asiento, y en el frente el que lleva el tablero de vuelo; siempre es un atril de `MAIN_COLUMNS`. Llevan
## módulos todos los lados menos los que se meterían en el pasillo de carga, que es el hueco entre la
## compuerta y los tableros (ver `console_indices`).
##
## Tipos de módulo (ver ModuleType). Todos se arman CONTRA LA PARED: el casco dice hasta dónde se puede
## construir a cada altura (`_wall_distance`) y el módulo llega hasta ahí —recto en la caja, siguiendo la
## curva en el domo—.
##   · ATRIL (el tablero común): tablero inclinado, plano de abajo que deja lugar a las rodillas y un
##     estante cosmético hasta la pared.
##   · GABINETE ALTO: un bloque con el tablero en la cara de adelante, a altura de alguien parado.
##   · GABINETE BAJO: a la altura de la cintura, con el tablero arriba. La cara de adelante queda libre
##     para más adelante.
##   · TABLERO VOLADOR (opcional, sobre un módulo): un bloque colgado de la pared arriba del que está
##     sentado, con la esquina de abajo de adentro cortada a la inclinación del atril, pero para abajo: ahí
##     va el tablero, mirándolo.
## Todo tablero que no tenga un preset lleva controles de relleno, para ver cómo queda (ver `_dummy_preset`).
##
## Ejes: X a la derecha, Y arriba, −Z al frente, +Z atrás (la compuerta). El origen es el centro de la
## base del piso, así que la altura de la nave es la de su panza. Las alturas de los módulos se miden
## desde el piso de adentro.

const CELL := ProceduralDashboard.CELL
## Medio ancho interior de las naves grandes —el radio del domo, la mitad del lado de la caja grande—: 126
## celdas, 5,04 m. Las dos tienen la misma planta, para compararlas de igual a igual; la caja chica, la
## mitad (ver BoxHull.small).
const HALF_WIDTH := 126.0 * CELL
## Espesor del piso, las paredes y la compuerta.
const WALL := 4.0 * CELL
## Opacidad de la cáscara con el toggle de paredes traslúcidas prendido (ver Ship.translucent_walls).
const SHELL_ALPHA := 0.25

enum ModuleType { LECTERN, TALL, SHORT }

## Columnas del módulo principal de cada lado: las del tablero de vuelo. Con 32 (1,28 m) entran los
## controles de vuelo y los brazos cortos llegan casi a todo el tablero.
const MAIN_COLUMNS := 32

## ── ATRIL ────────────────────────────────────────────────────────────────────────────────────────
## Filas del tablero: tan profundo como el volante, el control más grande.
const CONSOLE_ROWS := 12
## Altura de la BISAGRA, desde el piso: el borde de abajo del tablero, del lado de quien lo usa. Desde ahí
## el tablero sube hacia afuera y el plano de abajo baja hacia afuera.
const CONSOLE_HEIGHT := 0.75
## Inclinación del tablero desde la vertical: a 45° queda de frente a la mira del que está sentado.
const PANEL_TILT_DEG := 45.0
## Cuánto se mete hacia afuera, en el piso, el borde del plano de abajo. Inclinado así deja lugar para
## las rodillas debajo del tablero, y el asiento puede ir más cerca (ver Ship._add_seats).
const LOWER_SETBACK := 0.5
## Profundidad mínima del estante cosmético, que llega hasta la pared: lo menos que tiene que medir pone
## hasta dónde puede ir el anillo (ver `_ring_fits`).
const SHELF_MIN_DEPTH := 0.3

## ── GABINETES Y TABLERO VOLADOR ──────────────────────────────────────────────────────────────────
## Gabinete alto: su alto, y su tablero —en la cara de adelante, a altura de alguien parado—.
const TALL_HEIGHT := 2.0
const TALL_PANEL_BOTTOM := 0.9
const TALL_PANEL_ROWS := 24
## Gabinete bajo: alto del borde de adelante, cuánto sube hacia atrás su tapa y las filas del tablero de
## arriba.
const SHORT_HEIGHT := 0.95
const SHORT_TILT_DEG := 15.0
const SHORT_PANEL_ROWS := 14
## Tablero volador: su punto más bajo —lo justo para que el más chico lo alcance sentado, sin rozarle la
## cabeza—, las filas del tablero y cuánto sigue el bloque hacia arriba después del tablero.
const OVERHEAD_BOTTOM := 1.45
const OVERHEAD_PANEL_ROWS := 12
const OVERHEAD_LIP := 0.15

## Aire entre los módulos y la pared.
const CONSOLE_WALL_GAP := 0.02
const PLATE_THICKNESS := 0.03
## Cuánto va la placa del atril por detrás del plano de los controles.
const PLATE_BACK := 0.035

## Controles de relleno: [tipo, lado en celdas, peso]. Botones chicos y grandes, y perillas chicas y
## grandes —nunca tan grandes como el volante, que es de 12—.
const DUMMIES := [
	["button", 2, 4.0],
	["button", 4, 2.0],
	["knob", 3, 2.0],
	["knob", 6, 1.0],
]
## De cada lugar posible —uno cada dos celdas—, la proporción que se intenta llenar.
const DUMMY_DENSITY := 0.45
## Grupo de los tableros de relleno: el panel de performance del F1 los apaga (ver PerformanceToggles).
const DUMMY_GROUP := "ship_dummy_dashboards"

## Botones de la compuerta: a esta altura del piso y a esta distancia del borde del hueco.
const BUTTON_HEIGHT := 1.2
const BUTTON_SIDE_GAP := 0.35
## Placa detrás de cada botón.
const BUTTON_PLATE := 6.0 * CELL
## El botón, en celdas: más grande que el estándar (`ProceduralDashboard.BUTTON`), para encontrarlo
## sin buscarlo.
const DOOR_BUTTON := Vector2i(4, 4)
## Cuánto se separan los botones de la pared.
const BUTTON_STANDOFF := 0.06


## Un módulo de un lado del anillo: qué es, cuántas columnas de ancho, si lleva tablero volador arriba y si
## es LISO —su forma sin tablero, para completar un lado donde no entra otra cosa—.
class Module:
	var type: ShipHull.ModuleType
	var columns: int
	var overhead: bool
	var blank: bool

	func _init(module_type: ShipHull.ModuleType, module_columns: int, with_overhead: bool = false,
			is_blank: bool = false) -> void:
		type = module_type
		columns = module_columns
		overhead = with_overhead
		blank = is_blank


## Lo que la nave necesita tocar después de construido el casco.
class Parts:
	## Cómo se mueve la compuerta: recibe cuánto está abierta, de 0 a 1 (ver ShipDoor).
	var door_motion: Callable
	## El tablero del módulo principal de cada lado, en el orden de `console_indices`: el primero es el del
	## frente.
	var consoles: Array[ProceduralDashboard] = []
	## El de adentro y el de afuera de la compuerta.
	var door_buttons: Array[ProceduralDashboard] = []
	## La cáscara que el toggle de paredes traslúcidas vuelve traslúcida.
	var shell: Array[MeshInstance3D] = []


var _color_index := 0


# ── Lo que pone cada forma ────────────────────────────────────────────────────────────────────────

## Arma el piso, la cáscara y la compuerta —con su `door_motion`—, y anota en `parts.shell` lo que el
## toggle de paredes traslúcidas puede transparentar.
func _build_shell(_ship: RigidBody3D, _parts: Parts) -> void:
	pass


## Los dos botones de la compuerta, el de adentro y el de afuera, con `_build_button`.
func _build_door_buttons(_ship: RigidBody3D, _parts: Parts) -> void:
	pass


## Lados del anillo.
func console_sides() -> int:
	return 8


## Los módulos de un lado, de izquierda a derecha vistos desde adentro. Todos los lados suman lo mismo, y
## el del medio es el principal (ver EL ANILLO DE MÓDULOS).
func _side_modules(_side_index: int) -> Array:
	return [Module.new(ModuleType.LECTERN, MAIN_COLUMNS)]


## Cuánto hay desde `point` hasta la pared yendo en la dirección horizontal `dir`, a `height` sobre el
## piso, dejando `CONSOLE_WALL_GAP` de aire. `point` es horizontal, en el espacio de la nave.
func _wall_distance(_point: Vector3, _dir: Vector3, _height: float) -> float:
	return 0.0


## Ancho de la compuerta, que es el del pasillo de carga que el anillo deja libre.
func door_width() -> float:
	return 0.0


## Frente a qué lados va un asiento, por tamaño de tripulación —mirando al módulo principal—. El 0 es el
## piloto, frente al tablero de vuelo; los demás, repartidos por el anillo sin necesidad de simetría.
func _seat_layouts() -> Dictionary:
	return {1: [0]}


## El centro de masa: el del volumen de la forma.
func center_of_mass() -> Vector3:
	return Vector3.UP * WALL


## Cuánto llega el casco desde el centro sobre los ejes: hasta la cara de afuera de la pared del fondo,
## donde está la compuerta.
func half_extent() -> float:
	return 0.0


## Radio del círculo que encierra el casco, desde el centro: el de la esquina de un cuadrado de medio lado
## `half_extent`, que alcanza para cualquier forma.
func bounding_radius() -> float:
	return half_extent() * sqrt(2.0)


# ── El anillo ─────────────────────────────────────────────────────────────────────────────────────

## Arma el casco completo como hijos de `ship`. `main_presets` es lado → preset del módulo principal; los
## demás tableros llevan controles de relleno.
func build(ship: RigidBody3D, main_presets: Dictionary) -> Parts:
	_color_index = 0
	var parts := Parts.new()
	_build_shell(ship, parts)
	var sides := console_sides()
	var apothem := console_apothem()
	var width := float(side_columns()) * CELL
	for side_index in console_indices():
		var theta := float(side_index) * TAU / sides
		# El marco del lado: en el piso, sobre la línea de las bisagras; −Z hacia afuera, +Z hacia el centro.
		var side := Transform3D(Basis(Vector3.UP, -theta), _outward(theta) * apothem + Vector3.UP * WALL)
		var tag := _side_tag(side_index)
		var modules := _side_modules(side_index)
		var x := -width * 0.5
		for i in modules.size():
			var module: Module = modules[i]
			var w := float(module.columns) * CELL
			var center := x + w * 0.5
			x += w
			var frame := side * Transform3D(Basis(), Vector3(center, 0.0, 0.0))
			var main := absf(center) < 0.001
			var module_name := tag if main else "%s_%d" % [tag, i]
			var preset: DashboardPreset = main_presets.get(side_index) if main else null
			var dash := _build_module(ship, frame, module, module_name, preset, hash([side_index, i]))
			if main:
				parts.consoles.append(dash)
	_build_door_buttons(ship, parts)
	return parts


## Columnas de cada lado: las de sus módulos.
func side_columns() -> int:
	var total := 0
	for module: Module in _side_modules(0):
		total += module.columns
	return total


## Los lados con asiento para una tripulación. Cada uno tiene que llevar módulos.
func seat_sides(crew: int) -> Array[int]:
	var sides: Array[int] = []
	sides.assign(_seat_layouts().get(crew, [0]))
	return sides


## Distancia del centro a la línea de las bisagras: cada lado del polígono mide exactamente sus columnas,
## y lado = 2 · a · tan(180° / lados).
func console_apothem() -> float:
	return _apothem_for(console_sides(), side_columns())


static func _apothem_for(sides: int, columns: int) -> float:
	return float(columns) * CELL / (2.0 * tan(PI / sides))


## ¿Entra un anillo de `sides` lados de `columns` columnas? Sí, si al estante de un atril del ancho del
## lado —en sus esquinas, lo más cerca de la pared— le queda al menos `SHELF_MIN_DEPTH`.
func _ring_fits(sides: int, columns: int) -> bool:
	var frame := Transform3D(Basis(), Vector3(0.0, WALL, -_apothem_for(sides, columns)))
	var half_width := float(columns) * CELL * 0.5
	return _depth_to_wall(frame, half_width, panel_top_height()) - _panel_reach() >= SHELF_MIN_DEPTH


## Los lados del anillo que llevan módulos, con signo —negativos a la izquierda—: el del frente primero, y
## después alternando izquierda y derecha hacia atrás. Quedan afuera los que se meterían en el pasillo de
## carga, del ancho de la compuerta, que va de ella al centro.
func console_indices() -> Array[int]:
	var sides := console_sides()
	var apothem := console_apothem()
	var half_width := float(side_columns()) * CELL * 0.5
	var corridor := door_width() * 0.5
	var result: Array[int] = [0]
	var k := 1
	while 2 * k <= sides:
		# Qué tan lejos del eje del pasillo queda la esquina del lado más cercana a él.
		var from_back := PI - float(k) * TAU / sides
		var clearance := apothem * sin(from_back) - half_width * cos(from_back)
		if from_back >= PI * 0.5 or clearance >= corridor:
			result.append(-k)
			result.append(k)
		k += 1
	return result


## Cuánto se puede construir hacia afuera desde la línea de un módulo, a `height` sobre el piso: lo que
## deja la pared en la peor de sus dos esquinas. `frame` es el marco del módulo en el piso (−Z afuera).
func _depth_to_wall(frame: Transform3D, half_width: float, height: float) -> float:
	var outward := -frame.basis.z
	outward.y = 0.0
	outward = outward.normalized()
	var depth := INF
	for sign_x: float in [-1.0, 1.0]:
		var corner := frame.origin + frame.basis.x * half_width * sign_x
		corner.y = 0.0
		depth = minf(depth, _wall_distance(corner, outward, height))
	return depth


## Altura del borde de arriba del tablero del atril, desde el piso: lo más alto de un atril.
static func panel_top_height() -> float:
	return CONSOLE_HEIGHT + float(CONSOLE_ROWS) * CELL * cos(deg_to_rad(PANEL_TILT_DEG))


## Cuánto se mete el plano de abajo del atril detrás de la bisagra a `height` sobre el piso: el lugar que
## hay para las rodillas a esa altura.
static func knee_room_at(height: float) -> float:
	return LOWER_SETBACK * clampf(1.0 - height / CONSOLE_HEIGHT, 0.0, 1.0)


## Cuánto sale el tablero del atril hacia afuera, de la bisagra a su borde de arriba.
static func _panel_reach() -> float:
	return float(CONSOLE_ROWS) * CELL * sin(deg_to_rad(PANEL_TILT_DEG))


# ── Los módulos ───────────────────────────────────────────────────────────────────────────────────

## Arma un módulo en `frame` —su marco en el piso, sobre la línea de las bisagras— y devuelve su tablero
## de abajo, o null si es liso. Sin `preset`, lleva controles de relleno. Cada tipo arma su forma y dice
## dónde va su tablero; el dashboard se pone acá.
func _build_module(ship: RigidBody3D, frame: Transform3D, module: Module, module_name: String,
		preset: DashboardPreset, seed_value: int) -> ProceduralDashboard:
	var panel := Transform3D()
	var rows := CONSOLE_ROWS
	match module.type:
		ModuleType.TALL:
			panel = _build_tall(ship, frame, module.columns, module_name)
			rows = TALL_PANEL_ROWS
		ModuleType.SHORT:
			panel = _build_short(ship, frame, module.columns, module_name)
			rows = SHORT_PANEL_ROWS
		_:
			panel = _build_lectern(ship, frame, module.columns, module_name)
	if module.overhead:
		_build_overhead(ship, frame, module.columns, module_name, seed_value + 1)
	if module.blank:
		return null
	return _dashboard_on(ship, "dashboard_%s" % module_name, panel, module.columns, rows, preset, seed_value)


## El atril: el tablero inclinado con el dashboard encima, el plano de abajo —de la bisagra al piso,
## inclinado hacia afuera para dejar lugar a las rodillas— y un estante plano sobre el borde de arriba del
## tablero, hasta la pared, para cosas cosméticas.
func _build_lectern(ship: RigidBody3D, frame: Transform3D, columns: int, module_name: String) -> Transform3D:
	var width := float(columns) * CELL
	var depth := float(CONSOLE_ROWS) * CELL
	var tilt := deg_to_rad(PANEL_TILT_DEG)
	var hinge := frame * Transform3D(Basis(), Vector3.UP * CONSOLE_HEIGHT)

	# Tablero: sube desde la bisagra hacia afuera. En su marco, +Y sube por la pendiente y +Z es la cara.
	var panel := hinge * Transform3D(Basis(Vector3.RIGHT, -tilt), Vector3.ZERO)
	_box_xf(ship, "panel_%s" % module_name, Vector3(width, depth, PLATE_THICKNESS),
		panel * Transform3D(Basis(), Vector3(0.0, depth * 0.5, -PLATE_BACK)))

	# Plano de abajo: de la bisagra al piso, con el borde del piso metido `LOWER_SETBACK` hacia afuera.
	var lean := atan2(LOWER_SETBACK, CONSOLE_HEIGHT)
	var lower_length := Vector2(LOWER_SETBACK, CONSOLE_HEIGHT).length()
	_box_xf(ship, "lower_%s" % module_name, Vector3(width, lower_length, PLATE_THICKNESS),
		hinge * Transform3D(Basis(Vector3.RIGHT, lean), Vector3(0.0, -CONSOLE_HEIGHT * 0.5, -LOWER_SETBACK * 0.5)))

	# Estante cosmético: plano, del borde de arriba del tablero hasta casi tocar la pared.
	var top := Vector3(0.0, depth * cos(tilt), -depth * sin(tilt))
	var shelf := _depth_to_wall(frame, width * 0.5, panel_top_height()) - _panel_reach()
	_box_xf(ship, "shelf_%s" % module_name, Vector3(width, PLATE_THICKNESS, shelf),
		hinge * Transform3D(Basis(), top + Vector3(0.0, -PLATE_THICKNESS * 0.5, -shelf * 0.5)))

	return panel


## El gabinete alto: un bloque del piso a `TALL_HEIGHT`, con la cara de adelante sobre la línea del módulo
## y la de atrás contra la pared. El tablero va en la cara de adelante.
func _build_tall(ship: RigidBody3D, frame: Transform3D, columns: int, module_name: String) -> Transform3D:
	var half := float(columns) * CELL * 0.5
	_prism(ship, "tall_%s" % module_name, frame, half, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, TALL_HEIGHT),
		Vector2(_depth_to_wall(frame, half, TALL_HEIGHT), TALL_HEIGHT),
		Vector2(_depth_to_wall(frame, half, 0.0), 0.0)]))
	var panel := frame * Transform3D(Basis(), Vector3.UP * TALL_PANEL_BOTTOM)
	return panel


## El gabinete bajo: un bloque a la altura de la cintura, contra la pared, con la tapa subiendo
## `SHORT_TILT_DEG` hacia atrás. El tablero va en la tapa; la cara de adelante queda libre.
func _build_short(ship: RigidBody3D, frame: Transform3D, columns: int, module_name: String) -> Transform3D:
	var half := float(columns) * CELL * 0.5
	var slope := tan(deg_to_rad(SHORT_TILT_DEG))
	# Hasta dónde llega la tapa: se mide a la altura de su borde de atrás, que depende de cuánto llega.
	var back := _depth_to_wall(frame, half, SHORT_HEIGHT)
	back = minf(back, _depth_to_wall(frame, half, SHORT_HEIGHT + back * slope))
	_prism(ship, "short_%s" % module_name, frame, half, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, SHORT_HEIGHT),
		Vector2(back, SHORT_HEIGHT + back * slope),
		Vector2(_depth_to_wall(frame, half, 0.0), 0.0)]))
	# El tablero sobre la tapa: desde el borde de adelante, subiendo hacia atrás.
	var panel := frame * Transform3D(Basis(Vector3.RIGHT, -(PI * 0.5 - deg_to_rad(SHORT_TILT_DEG))),
		Vector3.UP * SHORT_HEIGHT)
	return panel


## El tablero volador: un bloque colgado de la pared arriba del módulo, con la esquina de abajo de adentro
## cortada a `PANEL_TILT_DEG` —la del atril, pero para abajo—; en ese corte va el tablero, mirando al que
## está sentado. Se sostiene en la pared, así que no llega al techo.
func _build_overhead(ship: RigidBody3D, frame: Transform3D, columns: int, module_name: String, seed_value: int) -> void:
	var half := float(columns) * CELL * 0.5
	var tilt := deg_to_rad(PANEL_TILT_DEG)
	var slant := float(OVERHEAD_PANEL_ROWS) * CELL
	var cut := Vector2(slant * sin(tilt), slant * cos(tilt))  # cuánto se mete hacia afuera y hacia arriba
	var top := OVERHEAD_BOTTOM + cut.y + OVERHEAD_LIP
	_prism(ship, "overhead_%s" % module_name, frame, half, PackedVector2Array([
		Vector2(0.0, top), Vector2(0.0, OVERHEAD_BOTTOM + cut.y), Vector2(cut.x, OVERHEAD_BOTTOM),
		Vector2(_depth_to_wall(frame, half, OVERHEAD_BOTTOM), OVERHEAD_BOTTOM),
		Vector2(_depth_to_wall(frame, half, top), top)]))
	# El tablero sobre el corte: desde su borde de afuera —el más bajo— subiendo hacia adentro, con la cara
	# mirando hacia abajo y hacia adentro.
	var panel := frame * Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0.0, OVERHEAD_BOTTOM, -cut.x))
	_dashboard_on(ship, "overhead_dashboard_%s" % module_name, panel, columns, OVERHEAD_PANEL_ROWS, null, seed_value)


## Un dashboard sobre un tablero. `panel` tiene el origen en el medio del borde de abajo del tablero, +Y
## subiendo por él y +Z hacia donde mira; la grilla arranca en su esquina de arriba a la izquierda y crece
## hacia −Y. Sin `preset`, lleva controles de relleno.
func _dashboard_on(ship: RigidBody3D, dash_name: String, panel: Transform3D, columns: int, rows: int,
		preset: DashboardPreset, seed_value: int) -> ProceduralDashboard:
	var dash := ProceduralDashboard.new()
	dash.name = dash_name
	dash.grid_columns = columns
	dash.grid_rows = rows
	if preset == null:
		preset = _dummy_preset(columns, rows, seed_value)
		dash.add_to_group(DUMMY_GROUP)
	dash.custom_preset = preset
	dash.transform = panel * Transform3D(Basis(), Vector3(-float(columns) * CELL * 0.5, float(rows) * CELL, 0.0))
	ship.add_child(dash)
	return dash


## Controles de relleno, para ver cómo queda cada tablero: se recorre la grilla cada dos celdas y, en cada
## lugar libre, más o menos `DUMMY_DENSITY` de las veces se prueba un control al azar de `DUMMIES`. Si entra,
## se reserva su lugar y una celda de aire alrededor: nunca se pisan y queda salpicado, no lleno. Semilla
## fija, así cada tablero sale siempre igual.
static func _dummy_preset(columns: int, rows: int, seed_value: int) -> DashboardPreset:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total := 0.0
	for kind: Array in DUMMIES:
		total += float(kind[2])
	var taken := {}
	var slots: Array[DashboardSlot] = []
	for y in range(1, rows - 1, 2):
		for x in range(1, columns - 1, 2):
			if taken.has(Vector2i(x, y)) or rng.randf() >= DUMMY_DENSITY:
				continue
			var pick := rng.randf() * total
			var kind: Array = DUMMIES[0]
			for candidate: Array in DUMMIES:
				pick -= float(candidate[2])
				if pick <= 0.0:
					kind = candidate
					break
			var side: int = kind[1]
			if x + side > columns - 1 or y + side > rows - 1 or not _dummy_fits(taken, x, y, side):
				continue
			for dx in range(-1, side + 1):
				for dy in range(-1, side + 1):
					taken[Vector2i(x + dx, y + dy)] = true
			var slot := DashboardSlot.new()
			slot.cell = Vector2i(x, y)
			slot.definition = _dummy_control(kind[0], side, rng)
			slots.append(slot)
	var p := _empty_preset()
	p.fixed_slots = slots
	return p


static func _dummy_fits(taken: Dictionary, x: int, y: int, side: int) -> bool:
	for dx in side:
		for dy in side:
			if taken.has(Vector2i(x + dx, y + dy)):
				return false
	return true


## Un control de relleno. Las perillas giran con la ruedita alrededor de la normal del tablero, como un
## dial, apenas despegadas de él; algunos botones son de los que quedan prendidos.
static func _dummy_control(kind: String, side: int, rng: RandomNumberGenerator) -> ControlDefinition:
	var d := ControlDefinition.new()
	d.grid_size = Vector2i(side, side)
	if kind == "knob":
		d.type = ControlDefinition.ControlType.ROTATING
		d.rotation_axis_local = Vector3.BACK
		d.height_offset = 0.02
	else:
		d.type = ControlDefinition.ControlType.TOUCH
		d.is_toggle = rng.randf() < 0.3
	return d


## Un bloque: un perfil convexo —puntos (hacia afuera, alto) en el plano del costado del módulo— estirado
## de lado a lado del módulo. Collider y malla de la misma forma.
func _prism(ship: RigidBody3D, part_name: String, frame: Transform3D, half_width: float,
		profile: PackedVector2Array) -> CollisionShape3D:
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for p in profile:
		left.append(frame * Vector3(-half_width, p.y, -p.x))
		right.append(frame * Vector3(half_width, p.y, -p.x))
	var points := left.duplicate()
	points.append_array(right)
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var center := Vector3.ZERO
	for p in points:
		center += p
	center /= float(points.size())

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	for k in n:
		var j := (k + 1) % n
		_quad(st, center, left[k], left[j], right[j], right[k])
	# Las dos tapas, en abanico: un cuadrilátero con las dos últimas esquinas iguales es un triángulo.
	for k in range(1, n - 1):
		_quad(st, center, left[0], left[k], left[k + 1], left[k + 1])
		_quad(st, center, right[0], right[k], right[k + 1], right[k + 1])
	return _part(ship, part_name, hull, st.commit(), Transform3D.IDENTITY, _opaque_material())


## Un cuadrilátero en dos triángulos, mirando hacia el lado contrario a `center`: las esquinas no vienen
## en el mismo orden en todas las caras, así que hacia dónde mira sale de ahí, y `_triangle` las ordena.
## Los triángulos sin área —donde dos esquinas coinciden— se saltean.
static func _quad(st: SurfaceTool, center: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		var normal := (p1 - p0).cross(p2 - p0)
		if normal.length_squared() < 1e-10:
			continue
		normal = normal.normalized()
		if normal.dot(p0 - center) < 0.0:
			normal = -normal
		_triangle(st, normal, p0, p1, p2)


## Un triángulo que mira hacia `normal`. Godot toma como frente el lado desde el que las esquinas giran en
## sentido horario —su normal es (c − a) × (b − a)—, así que si vienen al revés se las da vuelta. Importa
## aunque la normal vaya explícita: con un material de dos caras Godot invierte la normal del lado de
## atrás, y un triángulo al revés quedaba iluminado del lado contrario — el techo del domo se veía más
## claro desde adentro que desde afuera.
static func _triangle(st: SurfaceTool, normal: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var corners := [a, b, c] if (c - a).cross(b - a).dot(normal) >= 0.0 else [a, c, b]
	for corner: Vector3 in corners:
		st.set_normal(normal)
		st.add_vertex(corner)


# ── Piezas ────────────────────────────────────────────────────────────────────────────────────────

## Hacia afuera, en el rumbo `angle`: 0 es el frente (−Z), y crece hacia la derecha.
static func _outward(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, -cos(angle))


## Colores bien distintos entre piezas vecinas. El tono avanza por la razón áurea, que es la forma más
## barata de que dos índices seguidos nunca caigan cerca en la rueda de color.
static func debug_color(index: int) -> Color:
	return Color.from_hsv(fposmod(float(index) * 0.618034, 1.0), 0.55, 0.9)


## Pasa una pieza de la cáscara a medio traslúcida o de vuelta a opaca, conservando su color.
static func set_translucent(mesh: MeshInstance3D, on: bool) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = SHELL_ALPHA if on else 1.0


## Un botón de la compuerta: una placa y un dashboard del tamaño justo del botón. `at` es el centro del
## botón, con su +Z hacia donde mira; `backing`, cuánto va la placa hacia atrás, hasta la pared.
func _build_button(ship: RigidBody3D, part_name: String, at: Transform3D, backing: float) -> ProceduralDashboard:
	_box_xf(ship, "%s_plate" % part_name, Vector3(BUTTON_PLATE, BUTTON_PLATE, backing),
		at * Transform3D(Basis(), Vector3(0.0, 0.0, -backing * 0.5)))
	var dash := ProceduralDashboard.new()
	dash.name = part_name
	dash.grid_columns = DOOR_BUTTON.x
	dash.grid_rows = DOOR_BUTTON.y
	dash.custom_preset = _button_preset()
	# La grilla arranca en su esquina superior izquierda: corrida la mitad del botón, queda centrado en `at`.
	var half := Vector2(DOOR_BUTTON) * CELL * 0.5
	dash.transform = at * Transform3D(Basis(), Vector3(-half.x, half.y, 0.0))
	ship.add_child(dash)
	return dash


## "front" para el lado del frente; los demás, "left_N" o "right_N" según hacia dónde y cuántos lados.
static func _side_tag(side_index: int) -> String:
	if side_index == 0:
		return "front"
	return "%s_%d" % ["right" if side_index > 0 else "left", absi(side_index)]


## Un tablero sin controles. Hace falta un preset explícito: sin preset, `ProceduralDashboard` rellena la
## grilla con controles al azar.
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


## Opaco, en el próximo color de la secuencia: cada pieza sale de un color distinto a su vecina.
func _opaque_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = debug_color(_color_index)
	_color_index += 1
	return mat


## Anota una pieza como parte de la cáscara que el toggle transparenta. Devuelve la misma pieza.
static func _shell(parts: Parts, piece: CollisionShape3D) -> CollisionShape3D:
	parts.shell.append(piece.get_child(0) as MeshInstance3D)
	return piece


func _box_xf(ship: RigidBody3D, part_name: String, size: Vector3, xform: Transform3D) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(ship, part_name, box, mesh, xform, _opaque_material())


## Una pieza: collider y malla de la misma forma.
##
## ⚠ EL COLLIDER VA DIRECTO BAJO LA NAVE, nunca anidado en un nodo intermedio: un `CollisionShape3D`
## solo le da forma al cuerpo del que es hijo DIRECTO. Por eso cada pieza trae su transform ya
## calculado en el espacio de la nave, en vez de colgar de un nodo "consola" o "pared".
static func _part(ship: RigidBody3D, part_name: String, shape: Shape3D, mesh: Mesh, xform: Transform3D,
		material: Material) -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	collider.name = part_name
	collider.shape = shape
	collider.transform = xform
	var view := MeshInstance3D.new()
	view.name = "mesh"
	view.mesh = mesh
	view.material_override = material
	collider.add_child(view)
	ship.add_child(collider)
	return collider
