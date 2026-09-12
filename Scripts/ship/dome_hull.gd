class_name DomeHull
extends ShipHull

## EL DOMO — un domo de vidrio sobre un piso con su misma planta. Lo común (el anillo de módulos, los
## asientos, los botones) está en ShipHull; acá va lo que es del domo.
##
## Un hemisferio de esfera UV: `SEGMENTS` gajos alrededor —los mismos lados que el piso, así sus bordes
## coinciden— y `RINGS` anillos del piso al polo, cada cara una placa plana. Son opacos los anillos de
## `OPAQUE_RINGS`, la compuerta y lo de arriba de ella hasta el marco del medio (ver `_is_opaque`); el resto,
## de vidrio.
##
## Las caras opacas son placas de `WALL` de espesor que van de `DOME_RADIUS` hacia afuera, dibujadas
## enteras —sus dos caras y los cantos—; su cara de afuera queda al ras del borde del piso, así el domo
## mide lo mismo que la base. El vidrio es un plano sin espesor justo ahí, en `GLASS_RADIUS` (ver
## `_glass_face`).
##
## Cada cara es su PROPIO objeto, malla y collider: Godot ordena lo transparente por objeto y no por
## cara, así que un domo de una sola malla, visto desde adentro, dibujaría caras de atrás encima de las
## de adelante. Aun así se ve SUAVE: cada vértice lleva la normal de la esfera (ver `_smooth_quad`), y como
## las caras vecinas calculan la misma en sus vértices compartidos, la luz empalma sin corte. Solo los
## cantos de las placas, los marcos y el piso quedan planos.
##
## El anillo lleva un módulo de `MAIN_COLUMNS` por lado, tantos lados como entran sin que el estante toque
## el vidrio (ver `console_sides`). La cáscara no se transparenta con el toggle: ya es de vidrio, y sus
## partes opacas lo son a propósito. El centro de la esfera está sobre el piso.

## Radio interior del domo: el medio ancho común, 126 celdas, 5,04 m. Las placas del domo van de acá `WALL`
## hacia afuera, y terminan al ras del piso.
const DOME_RADIUS := HALF_WIDTH
## Radio de la cara de afuera del domo: donde terminan las placas opacas, donde está el plano del vidrio y
## hasta donde llega el piso.
const GLASS_RADIUS := DOME_RADIUS + WALL
## Gajos alrededor —del domo y del piso— y anillos del piso al polo, como una esfera UV. Divisible por
## tres, para los marcos (ver MARCOS).
const SEGMENTS := 42
const RINGS := 8
## Anillos opacos, contando desde el piso: el del piso y la cúspide. Los del medio son de vidrio.
const OPAQUE_RINGS: Array[int] = [0, 7]
## El vidrio: con los brillos del sol encima y un gradiente marcado —abajo cristalino, arriba oscuro y casi
## opaco, `GLASS_TOP_COLOR`— (ver Shaders/ship_glass.gdshader).
const GLASS_COLOR := Color(0.8, 0.9, 1.0, 0.15)
const GLASS_TOP_COLOR := Color(0.14, 0.17, 0.21, 0.75)
const GLASS_SHADER := preload("res://Shaders/ship_glass.gdshader")
## Color de la estructura del domo —la base, la cúspide, la compuerta con lo de arriba de ella, y los
## marcos—: un gris claro apenas rojizo. El piso, otra sombra del mismo gris, más oscura, para que se
## distingan.
const SHELL_COLOR := Color(0.56, 0.51, 0.5)
const FLOOR_COLOR := Color(0.42, 0.37, 0.36)

## ── LA COMPUERTA ─────────────────────────────────────────────────────────────────────────────────
## Los gajos de atrás, desde el piso: el del medio (SEGMENTS / 2) y `DOOR_HALF_WIDTH` a cada lado —2,24 m
## al nivel del piso, que es también el diámetro del cilindro de carga—, y `DOOR_RINGS` anillos de alto
## (2,80 m). Va por FUERA del vidrio, a `DOOR_GAP`, para que al subir deslizándose por el domo pase sobre
## él sin tocarlo.
const DOOR_SEGMENT := 21
const DOOR_HALF_WIDTH := 1
const DOOR_RINGS := 3
const DOOR_GAP := 0.02

## ── MARCOS ───────────────────────────────────────────────────────────────────────────────────────
## Divisiones del vidrio: barras finas del color de la estructura, solo para la vista —el vidrio ya tiene
## su collider—, todas en una malla, y solo sobre el vidrio.
##
## Uno HORIZONTAL que da toda la vuelta en el borde de abajo del anillo `FRAME_MID_RING`, a media altura. Y
## `FRAME_COUNT` VERTICALES, parejos y simétricos respecto del eje de la nave: con tres, uno cae sobre el eje
## atrás, sobre la compuerta, y va del marco del medio a la cúspide —debajo de él, hasta el marco, la
## compuerta y lo de arriba de ella son opacos—; los otros dos, a ±60° del frente, van de la base al marco
## del medio, y el paño de adelante del piloto queda libre. Van por el medio de las caras, no por sus
## bordes: con 42 gajos, uno cada 14.
const FRAME_MID_RING := 4
const FRAME_COUNT := 3
const FRAME_WIDTH := 0.03
## Cuánto entran hacia adentro y salen hacia afuera del plano del vidrio. Afuera, menos que `DOOR_GAP`: la
## compuerta pasa por encima al abrir.
const FRAME_IN := 0.02
const FRAME_OUT := 0.01


func console_sides() -> int:
	# Más lados es un anillo más grande: son los del primero que ya no entra, menos uno.
	var n := 3
	while _ring_fits(n + 1, side_columns()):
		n += 1
	return n


## Qué va en cada lado: un módulo por lado, repartido de a pares desde el frente. Los asientos (ver
## `_seat_layouts`) caen en atriles con tablero volador.
func _side_modules(side_index: int) -> Array:
	var overhead := absi(side_index) in [0, 4, 7]
	var type := ModuleType.LECTERN
	match absi(side_index):
		2, 5:
			type = ModuleType.SHORT
		3, 6:
			type = ModuleType.TALL
	return [Module.new(type, MAIN_COLUMNS, overhead)]


## Hasta la cara de adentro del domo a esa altura: el vidrio o, en los anillos opacos, su placa, que arranca
## `WALL` más adentro. Contado por lo bajo: las caras son planas y quedan más adentro que la esfera, lo más
## en el medio de cada una.
func _wall_distance(point: Vector3, dir: Vector3, height: float) -> float:
	var ring := int(asin(clampf(height / DOME_RADIUS, 0.0, 1.0)) / _ring_step())
	var radius := DOME_RADIUS if ring in OPAQUE_RINGS else GLASS_RADIUS
	var sphere := sqrt(maxf(radius * radius - height * height, 0.0))
	var reach := sphere * cos(PI / SEGMENTS) * cos(_ring_step() * 0.5) - CONSOLE_WALL_GAP
	# El punto sobre la línea `point + dir · t` que queda a `reach` del centro.
	var b := point.dot(dir)
	return -b + sqrt(maxf(b * b - point.length_squared() + reach * reach, 0.0))


## Ancho de la compuerta al nivel del piso: el de sus gajos.
func door_width() -> float:
	return 2.0 * DOME_RADIUS * sin(segment_angle(float(DOOR_HALF_WIDTH) + 0.5))


func _seat_layouts() -> Dictionary:
	return {1: [0], 4: [0, -4, 4, 7]}


## El del volumen de un hemisferio: 3/8 del radio sobre el piso.
func center_of_mass() -> Vector3:
	return Vector3.UP * (WALL + DOME_RADIUS * 0.375)


## Hasta la cara de afuera del domo. Como es redondo, es también el radio del círculo que lo encierra.
func half_extent() -> float:
	return GLASS_RADIUS


func bounding_radius() -> float:
	return GLASS_RADIUS


## El centro de la esfera del domo: sobre el piso, en el medio.
static func dome_center() -> Vector3:
	return Vector3.UP * WALL


## Rumbo de un gajo del domo: 0 es el frente, y crece hacia la derecha.
static func segment_angle(index: float) -> float:
	return index * TAU / SEGMENTS


func _build_shell(ship: RigidBody3D, parts: ShipHull.Parts) -> void:
	_build_floor(ship)

	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = SHELL_COLOR
	var glass_material := _glass_material()
	for i in SEGMENTS:
		for j in RINGS:
			if _is_door(i, j):
				continue  # el hueco de la compuerta
			if _is_opaque(i, j):
				_face(ship, "shell_%d_%d" % [i, j], i, j, DOME_RADIUS, shell_material)
			else:
				var face := _glass_face(ship, "glass_%d_%d" % [i, j], i, j, glass_material)
				(face.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_build_frames(ship)

	var faces: Array[CollisionShape3D] = []
	for i in range(DOOR_SEGMENT - DOOR_HALF_WIDTH, DOOR_SEGMENT + DOOR_HALF_WIDTH + 1):
		for j in DOOR_RINGS:
			faces.append(_face(ship, "door_%d_%d" % [i, j], i, j, GLASS_RADIUS + DOOR_GAP, shell_material))

	# La compuerta se DESLIZA HACIA ARRIBA siguiendo el domo: gira alrededor del centro de la esfera, sobre
	# el eje horizontal que la cruza de lado a lado, hasta quedar justo encima del hueco. Girar alrededor
	# del centro de una esfera deja todo sobre la esfera, así que no se despega del domo en ningún momento.
	# Girar sobre `hacia afuera × arriba` lleva lo que mira hacia afuera hacia arriba. Las caras nacen con
	# transform identidad —sus puntos ya están en el espacio de la nave—, así que el giro es su transform.
	var pivot := dome_center()
	var axis := _outward(segment_angle(float(DOOR_SEGMENT))).cross(Vector3.UP).normalized()
	var travel := float(DOOR_RINGS) * _ring_step()
	parts.door_motion = func(openness: float) -> void:
		var turn := Basis(axis, travel * openness)
		var slide := Transform3D(turn, pivot - turn * pivot)
		for face in faces:
			face.transform = slide


## Los botones de la compuerta, en la cara vecina a ella —adentro y afuera, inclinados como la cara—, a
## `BUTTON_HEIGHT` del piso y a `BUTTON_SIDE_GAP` del borde del hueco.
func _build_door_buttons(ship: RigidBody3D, parts: ShipHull.Parts) -> void:
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


static func _is_door(segment: int, ring: int) -> bool:
	return absi(segment - DOOR_SEGMENT) <= DOOR_HALF_WIDTH and ring < DOOR_RINGS


## Las caras que no son de vidrio: los anillos de `OPAQUE_RINGS` y los gajos de la compuerta hasta el marco
## del medio —ella y lo de arriba de ella—.
static func _is_opaque(segment: int, ring: int) -> bool:
	return ring in OPAQUE_RINGS or (absi(segment - DOOR_SEGMENT) <= DOOR_HALF_WIDTH and ring < FRAME_MID_RING)


## Cuánto sube cada anillo, en ángulo.
static func _ring_step() -> float:
	return PI * 0.5 / RINGS


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
func _build_floor(ship: RigidBody3D) -> void:
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	for k in SEGMENTS:
		var corner := _outward(segment_angle(float(k) + 0.5)) * GLASS_RADIUS
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
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	_part(ship, "floor", hull, st.commit(), Transform3D.IDENTITY, floor_material)


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
	_smooth_quad(st, pane[0], pane[1], pane[2], pane[3], false)
	return _part(ship, part_name, hull, st.commit(), Transform3D.IDENTITY, material)


## La malla de una placa del domo: sus dos caras suaves —la de adentro mirando hacia el centro, la de
## afuera hacia afuera— y los cuatro cantos planos, así se ve su espesor.
static func _slab_mesh(inner: PackedVector3Array, outer: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_smooth_quad(st, inner[0], inner[1], inner[2], inner[3], true)
	_smooth_quad(st, outer[0], outer[1], outer[2], outer[3], false)
	var center := Vector3.ZERO
	for k in 4:
		center += inner[k] + outer[k]
	center /= 8.0
	for k in 4:
		var n := (k + 1) % 4
		_quad(st, center, inner[k], inner[n], outer[n], outer[k])
	return st.commit()


## Un cuadrilátero sobre la esfera del domo, con sombreado SUAVE: cada vértice lleva la normal de la esfera
## en ese punto —del centro hacia él, o al revés con `inward`—. Las caras vecinas calculan la misma normal
## en sus vértices compartidos, así la luz empalma sin corte aunque cada cara sea su propio objeto. Hacia
## qué lado mira el triángulo —y con eso el orden de sus esquinas, ver `_triangle`— sale del mismo lado.
## Los triángulos sin área —en el polo, donde dos esquinas coinciden— se saltean.
static func _smooth_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inward: bool) -> void:
	var side := -1.0 if inward else 1.0
	for tri: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		if (p1 - p0).cross(p2 - p0).length_squared() < 1e-10:
			continue
		var facing := ((p0 + p1 + p2) / 3.0 - dome_center()) * side
		var corners := [p0, p1, p2] if (p2 - p0).cross(p1 - p0).dot(facing) >= 0.0 else [p0, p2, p1]
		for corner: Vector3 in corners:
			st.set_normal((corner - dome_center()).normalized() * side)
			st.add_vertex(corner)


## Una placa entre dos cuadriláteros —sus dos caras y los cuatro cantos— agregada a `st`.
static func _slab_into(st: SurfaceTool, inner: PackedVector3Array, outer: PackedVector3Array) -> void:
	var center := Vector3.ZERO
	for k in 4:
		center += inner[k] + outer[k]
	center /= 8.0
	_quad(st, center, inner[0], inner[1], inner[2], inner[3])
	_quad(st, center, outer[0], outer[1], outer[2], outer[3])
	for k in 4:
		var n := (k + 1) % 4
		_quad(st, center, inner[k], inner[n], outer[n], outer[k])


## Los marcos del vidrio (ver MARCOS): todas las barras en una sola malla, sin collider.
func _build_frames(ship: RigidBody3D) -> void:
	assert(SEGMENTS % FRAME_COUNT == 0, "DomeHull: los marcos no quedan parejos con estos gajos")
	@warning_ignore("integer_division")
	var spacing := SEGMENTS / FRAME_COUNT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in FRAME_COUNT:
		var segment := (DOOR_SEGMENT + k * spacing) % SEGMENTS
		# El de la compuerta sigue su línea del marco del medio para arriba; los otros van de la base al medio.
		var rings := range(FRAME_MID_RING, RINGS) if segment == DOOR_SEGMENT else range(0, FRAME_MID_RING)
		for j: int in rings:
			if _is_opaque(segment, j):
				continue  # solo sobre el vidrio
			# Por el medio de la cara: de la mitad de su borde de abajo a la mitad del de arriba.
			var face := _face_corners(GLASS_RADIUS, segment, j)
			_frame_bar(st, (face[0] + face[1]) * 0.5, (face[2] + face[3]) * 0.5)
	# El horizontal, toda la vuelta por el borde de abajo del anillo del medio: los verticales terminan en él.
	var lat := float(FRAME_MID_RING) * _ring_step()
	for i in SEGMENTS:
		_frame_bar(st, _dome_point(GLASS_RADIUS, segment_angle(float(i) - 0.5), lat),
			_dome_point(GLASS_RADIUS, segment_angle(float(i) + 0.5), lat))
	var frames := MeshInstance3D.new()
	frames.name = "frames"
	frames.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = SHELL_COLOR
	frames.material_override = material
	ship.add_child(frames)


## Una barra de marco de `a` a `b`, sobre el plano del vidrio: `FRAME_WIDTH` de ancho, `FRAME_IN` hacia
## adentro y `FRAME_OUT` hacia afuera. Se estira medio ancho de cada punta, así las juntas no dejan hueco.
static func _frame_bar(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var along := (b - a).normalized()
	var side := along.cross((a + b) * 0.5 - dome_center()).normalized()
	var out := side.cross(along).normalized()  # hacia afuera, perpendicular a la barra
	var start := a - along * FRAME_WIDTH * 0.5
	var end := b + along * FRAME_WIDTH * 0.5
	side *= FRAME_WIDTH * 0.5
	var inner := -out * FRAME_IN
	var outer := out * FRAME_OUT
	_slab_into(st,
		PackedVector3Array([start - side + inner, end - side + inner, end + side + inner, start + side + inner]),
		PackedVector3Array([start - side + outer, end - side + outer, end + side + outer, start + side + outer]))


## El vidrio: el shader de Shaders/ship_glass.gdshader, con el gradiente entre el vidrio de más abajo —el
## borde de arriba del anillo de la base— y el de más arriba —el de abajo de la cúspide—.
static func _glass_material() -> ShaderMaterial:
	var step := _ring_step()
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("bottom_tint", GLASS_COLOR)
	mat.set_shader_parameter("top_tint", GLASS_TOP_COLOR)
	mat.set_shader_parameter("gradient_bottom", WALL + GLASS_RADIUS * sin(float(OPAQUE_RINGS.min() + 1) * step))
	mat.set_shader_parameter("gradient_top", WALL + GLASS_RADIUS * sin(float(OPAQUE_RINGS.max()) * step))
	return mat
