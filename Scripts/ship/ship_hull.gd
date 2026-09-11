class_name ShipHull

## CASCO DE LA NAVE — un domo de vidrio sobre un piso con su misma planta, y un anillo de consolas
## pegado al vidrio.
##
## Es provisorio a propósito: el modelo de verdad viene después, desde Blender. Mientras tanto la nave
## tiene que existir en su tamaño real para probar cómo se vuela y cómo se usa por dentro. Se arma con
## piezas simples —caras planas, placas y un prisma—, cada una malla Y collider de la misma forma, y cada
## una de un color distinto a su vecina —salvo el domo: el vidrio es cristalino y parejo, y el casco
## opaco de un solo color oscuro—: se ve de un vistazo qué pieza es cuál. El día
## que llegue el modelo, esto se reemplaza entero sin que ninguna otra parte de la nave dependa de cómo
## estaba hecho.
##
## ── EL DOMO ─────────────────────────────────────────────────────────────────────────────────────
## Un hemisferio de esfera UV: `SEGMENTS` gajos alrededor —los mismos lados que el piso, así sus bordes
## coinciden— y `RINGS` anillos del piso al polo, cada cara una placa plana. Los anillos de `OPAQUE_RINGS`
## y la compuerta son opacos; el resto, de vidrio.
##
## Las caras opacas son placas de `WALL` de espesor que van de `DOME_RADIUS` hacia afuera, dibujadas
## enteras —sus dos caras y los cantos—; su cara de afuera queda al ras del borde del piso, así el domo
## mide lo mismo que la base. El vidrio es un plano sin espesor justo ahí, en `GLASS_RADIUS` (ver
## `_glass_face`).
##
## Cada cara es su PROPIO objeto, malla y collider: Godot ordena lo transparente por objeto y no por
## cara, así que un domo de una sola malla, visto desde adentro, dibujaría caras de atrás encima de las
## de adelante.
##
## ── SE MIDE EN CELDAS DE DASHBOARD ──────────────────────────────────────────────────────────────
## La unidad de la nave es la celda, no el metro: el radio, y el ancho y el alto de las consolas. Los
## dashboards son grillas de celdas, y cada consola tiene que alojar un número entero de ellas. Las caras
## del domo y la compuerta salen de los segmentos, así que no dan celdas justas.
##
## La celda es `ProceduralDashboard.CELL`: 4 cm, sin separación.
##
## Ejes: X a la derecha, Y arriba, −Z al frente, +Z atrás (la compuerta). El origen es el centro de la
## base del piso, así que la altura de la nave es la de su panza. El centro de la esfera está sobre el
## piso.

const CELL := ProceduralDashboard.CELL

## Radio interior del domo: 115 celdas, 4,60 m, un 10 % menos que el doble del largo del cubo de antes.
## Las placas del domo van de acá `WALL` hacia afuera, y terminan al ras del piso (ver EL DOMO).
const DOME_RADIUS := 115.0 * CELL
## Radio de la cara de afuera del domo: donde terminan las placas opacas, donde está el plano del vidrio y
## hasta donde llega el piso.
const GLASS_RADIUS := DOME_RADIUS + WALL
## Espesor del piso, del vidrio y de la compuerta.
const WALL := 4.0 * CELL
## Gajos alrededor —del domo y del piso— y anillos del piso al polo, como una esfera UV.
const SEGMENTS := 32
const RINGS := 8
## Anillos opacos, contando desde el piso: el del piso y la cúspide. Los del medio son de vidrio.
const OPAQUE_RINGS: Array[int] = [0, 7]
## El vidrio: cristalino, parejo en todo el domo.
const GLASS_COLOR := Color(0.75, 0.88, 1.0, 0.25)
## Color del casco opaco del domo: todo igual, oscuro.
const SHELL_COLOR := Color(0.2, 0.22, 0.26)

## ── LA COMPUERTA ─────────────────────────────────────────────────────────────────────────────────
## Los gajos de atrás, desde el piso: el del medio (SEGMENTS / 2) y `DOOR_HALF_WIDTH` a cada lado —2,67 m
## al nivel del piso, que es también el diámetro del cilindro de carga—, y `DOOR_RINGS` anillos de alto
## (2,56 m). Va por FUERA del vidrio, a `DOOR_GAP`, para que al subir deslizándose por el domo pase sobre
## él sin tocarlo (ver ShipDoor).
const DOOR_SEGMENT := 16
const DOOR_HALF_WIDTH := 1
const DOOR_RINGS := 3
const DOOR_GAP := 0.02

## ── EL ANILLO DE CONSOLAS ────────────────────────────────────────────────────────────────────────
## Consolas de `CONSOLE_COLUMNS`, una al lado de la otra, formando un polígono que mira al centro. No
## sigue los gajos del domo: va lo más afuera que se puede, con el estante casi tocando el vidrio, y
## tiene tantos lados como consolas entran pegadas a esa distancia (ver `console_sides`). Llevan consola
## todos los lados menos los que se meterían en el pasillo de carga, que es el hueco entre la compuerta
## y los tableros (ver `console_indices`).
##
## Columnas por consola. Con 32 (1,28 m) entran los controles de vuelo y los brazos cortos llegan casi a
## todo el tablero.
const CONSOLE_COLUMNS := 32
## Filas del tablero: tan profundo como el volante, el control más grande.
const CONSOLE_ROWS := 12
## Altura de la BISAGRA de cada consola, desde el piso: el borde de abajo del tablero, del lado de quien
## lo usa. Desde ahí el tablero sube hacia afuera y el plano de abajo baja hacia afuera.
const CONSOLE_HEIGHT := 0.75
## Inclinación del tablero desde la vertical: a 45° queda de frente a la mira del que está sentado.
const PANEL_TILT_DEG := 45.0
## Cuánto se mete hacia afuera, en el piso, el borde del plano de abajo. Inclinado así deja lugar para
## las rodillas debajo del tablero, y el asiento puede ir más cerca (ver Ship._add_seats).
const LOWER_SETBACK := 0.5
## Profundidad mínima del estante cosmético. Llega desde el borde de arriba del tablero hasta el vidrio
## (ver `shelf_depth`); esto es lo menos que tiene que medir, y pone hasta dónde puede ir el anillo.
const SHELF_MIN_DEPTH := 0.3
## Aire entre las esquinas de afuera del estante y el vidrio.
const CONSOLE_GLASS_GAP := 0.02
const PLATE_THICKNESS := 0.03
## Cuánto va la placa por detrás del plano de los controles.
const PLATE_BACK := 0.035

## Botones de la compuerta: en la cara vecina a ella, a esta altura del piso y a esta distancia del borde
## del hueco.
const BUTTON_HEIGHT := 1.2
const BUTTON_SIDE_GAP := 0.35
## Placa detrás de cada botón.
const BUTTON_PLATE := 6.0 * CELL
## El botón, en celdas: más grande que el estándar (`ProceduralDashboard.BUTTON`), para encontrarlo
## sin buscarlo.
const DOOR_BUTTON := Vector2i(4, 4)
## Cuánto se separan los botones del vidrio.
const BUTTON_STANDOFF := 0.06


## Lo que la nave necesita tocar después de construido el casco.
class Parts:
	## Las caras de la compuerta y cómo se deslizan para abrir (ver ShipDoor).
	var door_faces: Array[CollisionShape3D] = []
	var door_pivot := Vector3.ZERO
	var door_axis := Vector3.RIGHT
	var door_travel := 0.0
	## Una por lado ocupado del anillo, en el orden de `console_indices`: la primera es la del frente.
	var consoles: Array[ProceduralDashboard] = []
	## El de adentro y el de afuera de la compuerta.
	var door_buttons: Array[ProceduralDashboard] = []


static var _color_index := 0


## El centro de la esfera del domo: sobre el piso, en el medio.
static func dome_center() -> Vector3:
	return Vector3.UP * WALL


## Rumbo de un gajo del domo: 0 es el frente, y crece hacia la derecha.
static func segment_angle(index: float) -> float:
	return index * TAU / SEGMENTS


## Ancho de la compuerta al nivel del piso: el de sus gajos.
static func door_width() -> float:
	return 2.0 * DOME_RADIUS * sin(segment_angle(float(DOOR_HALF_WIDTH) + 0.5))


## Lados del anillo de consolas: los más que entran con consolas pegadas unas a otras sin que su estante
## toque el vidrio. Más lados es un anillo más grande, así que es el primero que ya no entra, menos uno.
static func console_sides() -> int:
	var limit := _max_console_apothem()
	var n := 3
	while _apothem_for(n + 1) <= limit:
		n += 1
	return n


## Distancia del centro a la bisagra de cada consola: cada lado del polígono mide exactamente
## `CONSOLE_COLUMNS` celdas, y lado = 2 · a · tan(180° / lados).
static func console_apothem() -> float:
	return _apothem_for(console_sides())


static func _apothem_for(sides: int) -> float:
	return float(CONSOLE_COLUMNS) * CELL / (2.0 * tan(PI / sides))


## La distancia más grande a la que puede ir la bisagra: la que todavía deja un estante de
## `SHELF_MIN_DEPTH` antes del vidrio.
static func _max_console_apothem() -> float:
	return _to_glass_at_shelf() - _panel_reach() - SHELF_MIN_DEPTH


## Profundidad del estante: desde el borde de arriba del tablero hasta casi tocar el vidrio.
static func shelf_depth() -> float:
	return _to_glass_at_shelf() - console_apothem() - _panel_reach()


## Cuánto sale el tablero hacia afuera, de la bisagra a su borde de arriba.
static func _panel_reach() -> float:
	return float(CONSOLE_ROWS) * CELL * sin(deg_to_rad(PANEL_TILT_DEG))


## Hasta qué distancia del centro, sobre la línea de una consola, puede llegar su estante: lo que deja
## sus esquinas de afuera —lo que queda más cerca del vidrio— a `CONSOLE_GLASS_GAP` de él.
static func _to_glass_at_shelf() -> float:
	var half_width := float(CONSOLE_COLUMNS) * CELL * 0.5
	var glass := _glass_distance(panel_top_height()) - CONSOLE_GLASS_GAP
	return sqrt(glass * glass - half_width * half_width)


## Distancia horizontal del centro al plano del vidrio, a `height` sobre el piso —donde se choca en los
## anillos de vidrio—, contada por lo bajo: las caras son planas y quedan más adentro que la esfera, lo más
## en el medio de cada una.
static func _glass_distance(height: float) -> float:
	var sphere := sqrt(maxf(GLASS_RADIUS * GLASS_RADIUS - height * height, 0.0))
	return sphere * cos(PI / SEGMENTS) * cos(_ring_step() * 0.5)


## Los lados del anillo que llevan consola, con signo —negativos a la izquierda—: el del frente primero, y
## después alternando izquierda y derecha hacia atrás. Quedan afuera los que se meterían en el pasillo de
## carga, del ancho de la compuerta, que va de ella al centro.
static func console_indices() -> Array[int]:
	var sides := console_sides()
	var apothem := console_apothem()
	var half_width := float(CONSOLE_COLUMNS) * CELL * 0.5
	var corridor := door_width() * 0.5
	var result: Array[int] = [0]
	var k := 1
	while 2 * k <= sides:
		# Qué tan lejos del eje del pasillo queda la esquina de la consola más cercana a él.
		var from_back := PI - float(k) * TAU / sides
		var clearance := apothem * sin(from_back) - half_width * cos(from_back)
		if from_back >= PI * 0.5 or clearance >= corridor:
			result.append(-k)
			result.append(k)
		k += 1
	return result


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
	_build_floor(ship)

	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = SHELL_COLOR
	var glass_material := _glass_material()
	for i in SEGMENTS:
		for j in RINGS:
			if _is_door(i, j):
				continue  # el hueco de la compuerta
			if _is_glass(j):
				var face := _glass_face(ship, "glass_%d_%d" % [i, j], i, j, glass_material)
				(face.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				_face(ship, "shell_%d_%d" % [i, j], i, j, DOME_RADIUS, shell_material)

	var door_material := _opaque_material()
	for i in range(DOOR_SEGMENT - DOOR_HALF_WIDTH, DOOR_SEGMENT + DOOR_HALF_WIDTH + 1):
		for j in DOOR_RINGS:
			parts.door_faces.append(_face(ship, "door_%d_%d" % [i, j], i, j, GLASS_RADIUS + DOOR_GAP, door_material))
	var door_out := _outward(segment_angle(float(DOOR_SEGMENT)))
	parts.door_pivot = dome_center()
	# Girar sobre `hacia afuera × arriba` lleva lo que mira hacia afuera hacia arriba: la compuerta sube.
	parts.door_axis = door_out.cross(Vector3.UP).normalized()
	parts.door_travel = float(DOOR_RINGS) * _ring_step()

	var sides := console_sides()
	for side_index in console_indices():
		var preset := console_presets.get(side_index) as DashboardPreset
		parts.consoles.append(_build_console(ship, side_index, sides, preset))

	_build_door_buttons(ship, parts)
	return parts


static func _is_door(segment: int, ring: int) -> bool:
	return absi(segment - DOOR_SEGMENT) <= DOOR_HALF_WIDTH and ring < DOOR_RINGS


static func _is_glass(ring: int) -> bool:
	return ring not in OPAQUE_RINGS


## Cuánto sube cada anillo, en ángulo.
static func _ring_step() -> float:
	return PI * 0.5 / RINGS


static func _outward(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, -cos(angle))


## Un punto del domo: `lon` es el rumbo (0 al frente) y `lat` la altura en ángulo (0 en el piso).
static func _dome_point(radius: float, lon: float, lat: float) -> Vector3:
	return dome_center() + (_outward(lon) * cos(lat) + Vector3.UP * sin(lat)) * radius


## Las cuatro esquinas de una cara: abajo del lado de rumbo menor, abajo del mayor, arriba del mayor y
## arriba del menor. En el anillo del polo las dos de arriba coinciden.
static func _face_corners(radius: float, segment: int, ring: int) -> PackedVector3Array:
	var lon := segment_angle(float(segment))
	var half := PI / SEGMENTS
	var lat0 := float(ring) * _ring_step()
	var lat1 := float(ring + 1) * _ring_step()
	return PackedVector3Array([
		_dome_point(radius, lon - half, lat0), _dome_point(radius, lon + half, lat0),
		_dome_point(radius, lon + half, lat1), _dome_point(radius, lon - half, lat1)])


## El piso: un prisma de `SEGMENTS` lados con los vértices justo debajo de los del domo, hasta el borde
## de afuera del vidrio, así los dos bordes coinciden.
static func _build_floor(ship: RigidBody3D) -> void:
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	for k in SEGMENTS:
		var corner := _outward(segment_angle(float(k) + 0.5)) * (DOME_RADIUS + WALL)
		bottom.append(corner)
		top.append(corner + Vector3.UP * WALL)
	var points := bottom.duplicate()
	points.append_array(top)
	var hull := ConvexPolygonShape3D.new()
	hull.points = points

	# Normales explícitas: arriba, abajo y el canto hacia afuera.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in SEGMENTS:
		var n := (k + 1) % SEGMENTS
		_triangle(st, Vector3.UP, dome_center(), top[k], top[n])
		_triangle(st, Vector3.DOWN, Vector3.ZERO, bottom[n], bottom[k])
		var side := ((bottom[k] + bottom[n]) * 0.5).normalized()
		_triangle(st, side, bottom[k], top[k], top[n])
		_triangle(st, side, bottom[k], top[n], bottom[n])
	_part(ship, "floor", hull, st.commit(), Transform3D.IDENTITY, _opaque_material())


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


## Una cara del domo: una placa de espesor `WALL` hacia afuera desde `radius`, dibujada entera.
static func _face(ship: RigidBody3D, part_name: String, segment: int, ring: int, radius: float,
		material: Material) -> CollisionShape3D:
	var inner := _face_corners(radius, segment, ring)
	var outer := _face_corners(radius + WALL, segment, ring)
	var points := inner.duplicate()
	points.append_array(outer)
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return _part(ship, part_name, hull, _slab_mesh(inner, outer), Transform3D.IDENTITY, material)


## Una cara de vidrio: un plano sin espesor en `GLASS_RADIUS`, al ras de la cara de afuera de las opacas,
## que se ve de los dos lados. Su collider sí tiene espesor —con una placa muy fina, lo que va rápido la
## atravesaría—: `WALL`, arrancando en el plano y hacia afuera. Así por dentro se choca justo donde se ve
## el vidrio, y el espesor queda del lado de afuera, donde casi no se nota.
static func _glass_face(ship: RigidBody3D, part_name: String, segment: int, ring: int,
		material: Material) -> CollisionShape3D:
	var pane := _face_corners(GLASS_RADIUS, segment, ring)
	var points := pane.duplicate()
	points.append_array(_face_corners(GLASS_RADIUS + WALL, segment, ring))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, dome_center(), pane[0], pane[1], pane[2], pane[3])
	return _part(ship, part_name, hull, st.commit(), Transform3D.IDENTITY, material)


## La malla de una placa: sus dos caras y los cuatro cantos, así se ve su espesor.
static func _slab_mesh(inner: PackedVector3Array, outer: PackedVector3Array) -> ArrayMesh:
	var center := Vector3.ZERO
	for k in 4:
		center += inner[k] + outer[k]
	center /= 8.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, center, inner[0], inner[1], inner[2], inner[3])
	_quad(st, center, outer[0], outer[1], outer[2], outer[3])
	for k in 4:
		var n := (k + 1) % 4
		_quad(st, center, inner[k], inner[n], outer[n], outer[k])
	return st.commit()


## Un cuadrilátero en dos triángulos, mirando hacia el lado contrario a `center`: las esquinas no vienen
## en el mismo orden en todas las caras, así que hacia dónde mira sale de ahí, y `_triangle` las ordena.
## Los triángulos sin área —en el polo, donde dos esquinas coinciden— se saltean.
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


## Un lado del anillo, hecho de placas: el tablero inclinado con el dashboard encima, el plano de abajo
## —de la bisagra al piso, inclinado hacia afuera para dejar lugar a las rodillas— y un estante plano
## sobre el borde de arriba del tablero, hacia el vidrio, para cosas cosméticas.
##
## El dashboard de `ProceduralDashboard` es una grilla en su plano XY con la cara hacia +Z local, que
## arranca en su esquina superior izquierda y crece hacia −Y. Inclinado como atril, la fila de arriba
## queda del lado de afuera y la de abajo del lado de quien lo usa, que es lo natural.
static func _build_console(ship: RigidBody3D, side_index: int, sides: int, preset: DashboardPreset) -> ProceduralDashboard:
	var theta := float(side_index) * TAU / sides
	# Origen en la bisagra; −Z local apunta hacia afuera y +Z hacia el centro, para donde mira el tablero.
	var hinge := Transform3D(Basis(Vector3.UP, -theta),
		_outward(theta) * console_apothem() + Vector3.UP * (WALL + CONSOLE_HEIGHT))
	var tag := _side_tag(side_index)
	var width := float(CONSOLE_COLUMNS) * CELL
	var depth := float(CONSOLE_ROWS) * CELL
	var tilt := deg_to_rad(PANEL_TILT_DEG)

	# Tablero: sube desde la bisagra hacia afuera. En su marco, +Y sube por la pendiente y +Z es la cara.
	var panel := hinge * Transform3D(Basis(Vector3.RIGHT, -tilt), Vector3.ZERO)
	_box_xf(ship, "panel_%s" % tag, Vector3(width, depth, PLATE_THICKNESS),
		panel * Transform3D(Basis(), Vector3(0.0, depth * 0.5, -PLATE_BACK)))

	# Plano de abajo: de la bisagra al piso, con el borde del piso metido `LOWER_SETBACK` hacia afuera.
	var lean := atan2(LOWER_SETBACK, CONSOLE_HEIGHT)
	var lower_length := Vector2(LOWER_SETBACK, CONSOLE_HEIGHT).length()
	_box_xf(ship, "lower_%s" % tag, Vector3(width, lower_length, PLATE_THICKNESS),
		hinge * Transform3D(Basis(Vector3.RIGHT, lean), Vector3(0.0, -CONSOLE_HEIGHT * 0.5, -LOWER_SETBACK * 0.5)))

	# Estante cosmético: plano, del borde de arriba del tablero hasta casi tocar el vidrio.
	var top := Vector3(0.0, depth * cos(tilt), -depth * sin(tilt))
	var shelf := shelf_depth()
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


## Los botones de la compuerta, en la cara vecina a ella —adentro y afuera, inclinados como la cara—, a
## `BUTTON_HEIGHT` del piso y a `BUTTON_SIDE_GAP` del borde del hueco.
static func _build_door_buttons(ship: RigidBody3D, parts: Parts) -> void:
	var ring := int(asin(BUTTON_HEIGHT / DOME_RADIUS) / _ring_step())
	var face := _face_corners(GLASS_RADIUS, DOOR_SEGMENT + DOOR_HALF_WIDTH + 1, ring)
	# La esquina 0 y la 3 son el borde que comparte con la compuerta.
	var toward_door := (face[0] - face[1]).normalized()
	var up := ((face[2] + face[3]) - (face[0] + face[1])).normalized()
	var normal := toward_door.cross(up).normalized()
	if normal.dot(face[0] - dome_center()) < 0.0:
		normal = -normal
	# Subiendo por el borde del hueco hasta la altura de los botones, y de ahí alejándose de él.
	var edge := (face[3] - face[0]).normalized()
	var on_edge := face[0] + edge * ((WALL + BUTTON_HEIGHT - face[0].y) / edge.y)
	var spot := on_edge - toward_door * BUTTON_SIDE_GAP

	# El de adentro va contra el vidrio. El de afuera, pasando el collider del vidrio —si no, el rayo de
	# interacción pegaría primero en él—, con la placa cubriendo ese espesor hasta el vidrio.
	var inside := Basis(up.cross(-normal), up, -normal)
	parts.door_buttons.append(_build_button(ship, "door_button_inside",
		Transform3D(inside, spot - normal * BUTTON_STANDOFF), BUTTON_STANDOFF))
	var outside := Basis(up.cross(normal), up, normal)
	parts.door_buttons.append(_build_button(ship, "door_button_outside",
		Transform3D(outside, spot + normal * (WALL + BUTTON_STANDOFF)), WALL + BUTTON_STANDOFF))


## Un botón de la compuerta: una placa y un dashboard del tamaño justo del botón. `at` es el centro del
## botón, con su +Z hacia donde mira; `backing`, cuánto va la placa hacia atrás, hasta el vidrio.
static func _build_button(ship: RigidBody3D, part_name: String, at: Transform3D, backing: float) -> ProceduralDashboard:
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


## Cristalino y de las dos caras: el vidrio es un plano solo, que se ve de adentro y de afuera. Con las
## esquinas bien ordenadas (ver `_triangle`), Godot ilumina bien cada lado.
static func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GLASS_COLOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## Opaco, en el próximo color de la secuencia: cada pieza sale de un color distinto a su vecina.
static func _opaque_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = debug_color(_color_index)
	_color_index += 1
	return mat


static func _box_xf(ship: RigidBody3D, part_name: String, size: Vector3, xform: Transform3D) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(ship, part_name, box, mesh, xform, _opaque_material())


## Una pieza: collider y malla de la misma forma.
##
## ⚠ EL COLLIDER VA DIRECTO BAJO LA NAVE, nunca anidado en un nodo intermedio: un `CollisionShape3D`
## solo le da forma al cuerpo del que es hijo DIRECTO. Por eso cada pieza trae su transform ya
## calculado en el espacio de la nave, en vez de colgar de un nodo "consola" o "domo".
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
