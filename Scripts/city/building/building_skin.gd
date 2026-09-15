class_name BuildingSkin
extends RefCounted

## LA PIEL DE UN EDIFICIO — la malla final, reconstruida a partir de las caras de sus módulos POR POSICIÓN,
## sin saber de módulos ni de pisos:
##   · Lo que no se ve, se va: dos caras coplanares enfrentadas —la pared entre dos módulos pegados, el techo
##     de un piso contra el suelo del siguiente— son interior de sólido donde se superponen, y se descuentan
##     una de la otra. Lo que no se superpone queda: la parte de una fachada que asoma sobre el vecino más bajo.
##   · Lo coplanar se une: las doce paredes de una fachada de doce pisos salen como UNA, con los vértices
##     compartidos. Es lo que necesita un shader de texturizado, y lo que menos triángulos cuesta.
##   · LAS ABERTURAS se cortan de la pared (`add_opening`): el hueco de cada puerta y ventana, con el ESPESOR
##     de la pared a la vista alrededor —los derrames: jambas, dintel y alféizar, `wall_thickness` hacia
##     adentro— y, si la abertura lleva ARCO, las dos esquinas superiores redondeadas con los segmentos que
##     pida. Sin derrame en el borde donde la pared termina: ahí no hay espesor que mostrar.
## Como no depende de qué módulo es vecino de cuál, sirve igual para un edificio escalonado por pisos: si el
## piso de arriba es más chico, el suelo que le sobra al de abajo queda como cornisa sin cambiar nada acá.
##
## Es SOLO lo que se ve. La identidad de las piezas (CityIndex) y el collider salen de la malla debug, que
## conserva la forma básica módulo por módulo y sin huecos (ver BuildingShell).
##
## LAS PAREDES SON RECTÁNGULOS EN EL MARCO DE SU PLANO. Cada pared es un paralelogramo vertical (ver
## BuildingModule.get_wall_quad) cuyas líneas de piso son paralelas a la línea de la que el plano salió; en
## el marco (u a lo largo de esa línea, v la altura menos la pendiente por u) es un rectángulo con los lados
## en los ejes, y todo lo que hay en ese plano también —las aberturas incluidas: la región de una ventana en
## la matriz rígida es un trozo del mismo paralelogramo—. Entonces "unión de un lado, menos unión del otro,
## menos aberturas" es aritmética de rectángulos: exacta, sin Clipper, sin agujeros —un rectángulo menos otro
## son a lo sumo cuatro— y se une sola al fusionar los que comparten ancho. El arco es un rectángulo más
## (la sección superior de la abertura, inscripta en ella): se resta entero y se devuelven las dos esquinas
## como abanicos. Si una cara no cumpliera lo del marco se emite tal cual, ni oculta ni unida, y se cuenta en
## `raw_walls`: hoy no pasa, y cualquier número ahí es un caso a mirar.
##
## LAS TAPAS VIVEN EN EL ESPACIO DE CELDAS DE SU MÓDULO, no en un plano: tienen silla, y dos tapas a la misma
## altura de la misma celda están sobre la misma superficie bilineal. Ahí la resta es de polígonos
## (Geometry2D), con el caso de siempre —las dos tapas iguales— resuelto por comparación directa y sin
## Clipper. Un agujero (una cornisa cerrada alrededor de un piso más chico) se parte por una línea que lo
## cruce hasta que no quede ninguno, porque el triangulador no los admite.

## Un milímetro: la tolerancia con que dos caras están en el mismo plano, dos bordes coinciden y dos vértices
## son el mismo. En celdas (las tapas) es 0,2 mm.
const EPS := 0.001
## Más allá de esto no hay ciudad: los semiplanos con que se parte un polígono con agujero.
const FAR := 1.0e6

var _color: Color
## Cuánto entra el derrame de una abertura: el espesor de la pared, del arquetipo del edificio.
var wall_thickness := 0.3

## Un plano por entrada: `{n, d, o, e, slope, front, back, openings}` — normal canónica y distancia, el
## marco (origen, dirección horizontal de la línea, pendiente de la línea), los rectángulos de cada lado y
## las aberturas `{rect, front, arch, segments, reveals}`.
var _planes: Array[Dictionary] = []
## Los planos por normal redondeada, para encontrar el de una cara sin recorrerlos todos.
var _planes_by_normal: Dictionary = {}
## Las tapas por `[módulo, altura]`: `{module, height, front, back}` con polígonos en celdas.
var _caps: Dictionary = {}
## Caras que no entraron en el marco de su plano: `[quad, normal]`, se emiten tal cual.
var _raw: Array = []
var raw_walls := 0
## Aberturas que no cayeron en ningún plano de pared: un caso a mirar.
var lost_openings := 0

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _init(color: Color) -> void:
	_color = color


# ── Entrada ──────────────────────────────────────────────────────────────────────────────────────

## Una pared: su quad `[b0, b1, t1, t0]` y la normal hacia afuera.
func add_wall(quad: Array[Vector3], normal: Vector3) -> void:
	var canon := normal if _is_canonical(normal) else -normal
	var plane := _plane_for(canon, quad)
	if plane.is_empty():
		_raw.append([quad, normal])
		raw_walls += 1
		return
	var rect := _rect_in(plane, quad)
	if rect == Rect2():
		_raw.append([quad, normal])
		raw_walls += 1
		return
	if normal.dot(canon) > 0.0:
		plane["front"].append(rect)
	else:
		plane["back"].append(rect)


## Una tapa: el contorno en celdas del módulo a `height_index`, mirando arriba (`up`) o abajo.
func add_cap(module: BuildingModule, contour: PackedVector2Array, height_index: int, up: bool) -> void:
	var key := [module, height_index]
	if not _caps.has(key):
		_caps[key] = {"module": module, "height": height_index, "front": [], "back": []}
	_caps[key]["front" if up else "back"].append(contour)


## UNA ABERTURA en una pared ya agregada: su quad sobre el plano de la pared `[b0, b1, t1, t0]` (la cara
## `y = 0` de la región de la matriz rígida, ver RigidMatrix) y hacia dónde mira esa pared. `arch_height`
## es cuánto de arriba de la abertura es la sección de arco (0 = sin arco) y `arch_segments` con cuántos
## segmentos se redondea cada esquina. Con `reveals` se dibujan los derrames: sin ellos es solo el hueco (la
## cara de atrás de un tabique atravesado, que ya tiene los derrames del frente).
func add_opening(quad: Array[Vector3], outward: Vector3, arch_height: float, arch_segments: int,
		reveals := true) -> void:
	var normal := (quad[1] - quad[0]).cross(quad[3] - quad[0])
	if normal.length_squared() <= 0.0:
		lost_openings += 1
		return
	normal = normal.normalized()
	var canon := normal if _is_canonical(normal) else -normal
	var plane := _plane_for(canon, quad)
	if plane.is_empty():
		lost_openings += 1
		return
	var rect := _rect_in(plane, quad)
	if rect == Rect2():
		lost_openings += 1
		return
	plane["openings"].append({"rect": rect, "front": outward.dot(canon) > 0.0,
		"arch": clampf(arch_height, 0.0, rect.size.y), "segments": maxi(arch_segments, 1), "reveals": reveals})


# ── Salida ───────────────────────────────────────────────────────────────────────────────────────

func build() -> ArrayMesh:
	for plane in _planes:
		var front := _merge(plane["front"])
		var back := _merge(plane["back"])
		var holes_front: Array[Rect2] = []
		var holes_back: Array[Rect2] = []
		for opening: Dictionary in plane["openings"]:
			if opening["front"]:
				holes_front.append(opening["rect"])
			else:
				holes_back.append(opening["rect"])
		var n: Vector3 = plane["n"]
		_emit_rects(plane, _carve(front, back + holes_front), n)
		_emit_rects(plane, _carve(back, front + holes_back), -n)
		for opening: Dictionary in plane["openings"]:
			_emit_opening(plane, opening, front if opening["front"] else back)
	for raw: Array in _raw:
		_emit_polygon(raw[0], raw[1])
	for group: Dictionary in _caps.values():
		_emit_caps(group)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ── Planos ───────────────────────────────────────────────────────────────────────────────────────

## De las dos normales de un plano, la canónica es la que tiene positiva su primera componente no nula:
## así las caras de los dos lados caen en la misma entrada.
static func _is_canonical(n: Vector3) -> bool:
	for c in [n.x, n.y, n.z]:
		if absf(c) > 0.000001:
			return c > 0.0
	return true


## El plano de una cara, creado con su marco si es la primera. Vacío si la cara es horizontal (no es una
## pared) o su línea de piso no avanza en el plano: no hay con qué armar el marco.
##
## La PENDIENTE de la línea de piso es parte de la identidad: dos paredes coplanares con líneas de piso
## distintas —dos celdas vecinas de una zona donde la grilla se vuelve regular, cada una con su relieve—
## van a marcos distintos. No se descuentan entre sí, pero no tienen por qué: no se tocan.
func _plane_for(canon: Vector3, quad: Array[Vector3]) -> Dictionary:
	var key := Vector3i((canon * 100.0).round())
	var on := quad[0]
	var d := canon.dot(on)
	# El eje `u` es la horizontal del plano: perpendicular a la normal y al eje Y. La pendiente es cuánto
	# sube la línea de piso por metro a lo largo de `u`; es lo que hace rectángulos a las paredes.
	var e := Vector3.UP.cross(canon)
	if e.length_squared() < 0.000001:
		return {}
	e = e.normalized()
	var along := quad[1] - on
	var run := along.dot(e)
	if absf(run) < EPS:
		return {}
	var slope := along.y / run
	if _planes_by_normal.has(key):
		for i: int in _planes_by_normal[key]:
			var plane: Dictionary = _planes[i]
			if plane["n"].dot(canon) > 0.99999 and absf(plane["d"] - d) < EPS \
					and absf(plane["slope"] - slope) < 0.0001:
				return plane
	var plane := {"n": canon, "d": d, "o": on, "e": e, "slope": slope, "front": [], "back": [],
		"openings": []}
	_planes.append(plane)
	if not _planes_by_normal.has(key):
		_planes_by_normal[key] = PackedInt32Array()
	_planes_by_normal[key].append(_planes.size() - 1)
	return plane


## El rectángulo de un quad `[b0, b1, t1, t0]` en el marco del plano, o `Rect2()` si no es un rectángulo
## ahí (la línea de piso no es paralela a la del plano, o los lados no son verticales).
func _rect_in(plane: Dictionary, quad: Array[Vector3]) -> Rect2:
	var u0 := _u(plane, quad[0])
	var u1 := _u(plane, quad[1])
	var v0 := _v(plane, quad[0])
	var v1 := _v(plane, quad[3])
	if absf(_v(plane, quad[1]) - v0) > EPS or absf(_u(plane, quad[3]) - u0) > EPS:
		return Rect2()
	return Rect2(minf(u0, u1), minf(v0, v1), absf(u1 - u0), absf(v1 - v0))


func _u(plane: Dictionary, p: Vector3) -> float:
	return (p - plane["o"]).dot(plane["e"])


func _v(plane: Dictionary, p: Vector3) -> float:
	return p.y - plane["o"].y - plane["slope"] * _u(plane, p)


## Un punto del marco al mundo, `depth` metros hacia adentro de la cara de normal `n_side`.
func _point(plane: Dictionary, u: float, v: float, n_side := Vector3.ZERO, depth := 0.0) -> Vector3:
	var o: Vector3 = plane["o"]
	var e: Vector3 = plane["e"]
	return o + e * u + Vector3.UP * (v + plane["slope"] * u) - n_side * depth


# ── Rectángulos ──────────────────────────────────────────────────────────────────────────────────

## Une los rectángulos del mismo ancho que se tocan o se solapan en vertical: las paredes de los pisos de
## una misma fachada, y los pedazos que deja una resta.
static func _merge(rects: Array) -> Array[Rect2]:
	var columns := {}
	for r: Rect2 in rects:
		var key := Vector2i(roundi(r.position.x / EPS), roundi(r.end.x / EPS))
		if not columns.has(key):
			columns[key] = []
		columns[key].append(r)
	var out: Array[Rect2] = []
	for column: Array in columns.values():
		column.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y)
		var current: Rect2 = column[0]
		for i in range(1, column.size()):
			var r: Rect2 = column[i]
			if r.position.y <= current.end.y + EPS:
				current.size.y = maxf(current.end.y, r.end.y) - current.position.y
			else:
				out.append(current)
				current = r
		out.append(current)
	return out


## LO SÓLIDO MENOS LOS CORTES, como rectángulos: la pared menos la de enfrente y menos sus aberturas.
##
## Por una GRILLA y no restando rectángulo a rectángulo: todos los bordes en u y en v de todo lo que entra
## parten el plano en celdas; cada celda es sólida si la cubre algo sólido y nada la corta (los bordes
## están exactamente sobre las líneas, así que marcar rangos de celdas es exacto); y las celdas sólidas se
## juntan en columnas, corridas verticales de una columna de celdas —la franja de pared entre dos columnas
## de ventanas sale como UN rectángulo de toda la altura—. Es lineal en las aberturas; restar una por una
## era cuadrático, y con cientos de miles de ventanas no terminaba.
static func _carve(solid: Array[Rect2], cuts: Array[Rect2]) -> Array[Rect2]:
	if solid.is_empty():
		return []
	if cuts.is_empty():
		return solid
	var us := _edges(solid, cuts, true)
	var vs := _edges(solid, cuts, false)
	var columns := us.size() - 1
	var rows := vs.size() - 1
	var cell := PackedByteArray()
	cell.resize(columns * rows)
	for r in solid:
		_paint(cell, us, vs, r, 1)
	for c in cuts:
		_paint(cell, us, vs, c, 0)
	var out: Array[Rect2] = []
	for i in columns:
		var j := 0
		while j < rows:
			if cell[i * rows + j] == 0:
				j += 1
				continue
			var j0 := j
			while j < rows and cell[i * rows + j] == 1:
				j += 1
			out.append(Rect2(us[i], vs[j0], us[i + 1] - us[i], vs[j] - vs[j0]))
	return out


## Los bordes de todos los rectángulos en un eje, ordenados y sin repetidos (a un milímetro).
static func _edges(solid: Array[Rect2], cuts: Array[Rect2], horizontal: bool) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for r in solid:
		values.append(r.position.x if horizontal else r.position.y)
		values.append(r.end.x if horizontal else r.end.y)
	for c in cuts:
		values.append(c.position.x if horizontal else c.position.y)
		values.append(c.end.x if horizontal else c.end.y)
	values.sort()
	var out := PackedFloat32Array()
	for v in values:
		if out.is_empty() or v - out[out.size() - 1] > EPS:
			out.append(v)
	return out


## Marca las celdas que cubre un rectángulo. Sus bordes están en las líneas, así que el rango de celdas
## es el que va del índice de su inicio al de su fin.
static func _paint(cell: PackedByteArray, us: PackedFloat32Array, vs: PackedFloat32Array, r: Rect2,
		value: int) -> void:
	var i0 := _index_of(us, r.position.x)
	var i1 := _index_of(us, r.end.x)
	var j0 := _index_of(vs, r.position.y)
	var j1 := _index_of(vs, r.end.y)
	var rows := vs.size() - 1
	for i in range(i0, i1):
		for j in range(j0, j1):
			cell[i * rows + j] = value


static func _index_of(edges: PackedFloat32Array, value: float) -> int:
	var i := edges.bsearch(value - EPS)
	return clampi(i, 0, edges.size() - 1)


## La envolvente de una lista de rectángulos: hasta dónde llega la pared de ese lado.
static func _bounds(rects: Array[Rect2]) -> Rect2:
	var out := Rect2()
	for i in rects.size():
		out = rects[i] if i == 0 else out.merge(rects[i])
	return out


func _emit_rects(plane: Dictionary, rects: Array[Rect2], normal: Vector3) -> void:
	# Los vértices se comparten dentro del plano y del lado: dos rectángulos que se tocan usan los mismos.
	var shared := {}
	for r in rects:
		var corners: Array[Vector3] = [
			_point(plane, r.position.x, r.position.y),
			_point(plane, r.end.x, r.position.y),
			_point(plane, r.end.x, r.end.y),
			_point(plane, r.position.x, r.end.y),
		]
		var keys: Array[Vector2i] = [
			Vector2i(roundi(r.position.x / EPS), roundi(r.position.y / EPS)),
			Vector2i(roundi(r.end.x / EPS), roundi(r.position.y / EPS)),
			Vector2i(roundi(r.end.x / EPS), roundi(r.end.y / EPS)),
			Vector2i(roundi(r.position.x / EPS), roundi(r.end.y / EPS)),
		]
		var ids := PackedInt32Array()
		for k in 4:
			if not shared.has(keys[k]):
				shared[keys[k]] = _vertices.size()
				_vertices.append(corners[k])
				_normals.append(normal)
				_colors.append(_color)
			ids.append(shared[keys[k]])
		_emit_quad(ids, corners, normal)


## Dos triángulos de un quad `[p0, p1, p2, p3]` ya en la malla, orientados según la convención del proyecto
## (para el orden (a, b, c) la cara visible tiene normal (c - a) x (b - a)).
func _emit_quad(ids: PackedInt32Array, corners: Array[Vector3], normal: Vector3) -> void:
	var order: Array[int] = [0, 3, 1, 1, 3, 2]
	if (corners[1] - corners[0]).cross(corners[3] - corners[0]).dot(normal) < 0.0:
		order = [0, 1, 3, 1, 2, 3]
	for k in order:
		_indices.append(ids[k])


## Una cara cualquiera tal cual, con vértices propios.
func _emit_polygon(quad: Array[Vector3], normal: Vector3) -> void:
	var ids := PackedInt32Array()
	for p in quad:
		ids.append(_vertices.size())
		_vertices.append(p)
		_normals.append(normal)
		_colors.append(_color)
	_emit_quad(ids, quad, normal)


## Un triángulo con vértices propios, orientado hacia `normal`.
func _emit_triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var base := _vertices.size()
	for p: Vector3 in [a, b, c]:
		_vertices.append(p)
		_normals.append(normal)
		_colors.append(_color)
	if (c - a).cross(b - a).dot(normal) < 0.0:
		_indices.append_array(PackedInt32Array([base, base + 2, base + 1]))
	else:
		_indices.append_array(PackedInt32Array([base, base + 1, base + 2]))


# ── Aberturas ────────────────────────────────────────────────────────────────────────────────────

## EL CONTORNO DE UNA ABERTURA en el marco del plano, antihorario (u a la derecha, v arriba): abajo de
## izquierda a derecha, el lado derecho subiendo, el arco o dintel de derecha a izquierda, el lado
## izquierdo bajando. Con arco, las dos esquinas de arriba son cuartos de círculo de radio `arch` (o medio
## ancho si la abertura es más angosta que dos radios), con `segments` tramos cada uno. Cada tramo lleva
## qué es (`side`: 0 abajo, 1 derecha, 2 arriba, 3 izquierda), para saber cuál cae en el borde de la pared.
static func _outline(rect: Rect2, arch: float, segments: int) -> Array:
	var u0 := rect.position.x
	var u1 := rect.end.x
	var v0 := rect.position.y
	var v1 := rect.end.y
	var r := minf(arch, rect.size.x * 0.5)
	var points: Array = [[Vector2(u0, v0), 0], [Vector2(u1, v0), 1]]
	if r <= EPS:
		points.append([Vector2(u1, v1), 2])
		points.append([Vector2(u0, v1), 3])
	else:
		# Esquina derecha: centro (u1 - r, v1 - r), del ángulo 0 al 90.
		for k in range(0, segments + 1):
			var t := PI * 0.5 * float(k) / float(segments)
			points.append([Vector2(u1 - r + r * cos(t), v1 - r + r * sin(t)), 2 if k < segments else 2])
		# Esquina izquierda: centro (u0 + r, v1 - r), del 90 al 180.
		for k in range(0, segments + 1):
			var t := PI * 0.5 + PI * 0.5 * float(k) / float(segments)
			points.append([Vector2(u0 + r + r * cos(t), v1 - r + r * sin(t)), 3 if k == segments else 2])
	return points


## Los derrames y las esquinas de arco de una abertura. `side_rects` son las paredes de su lado, para saber
## dónde termina la pared: un tramo del contorno que cae en ese borde no lleva derrame.
func _emit_opening(plane: Dictionary, opening: Dictionary, side_rects: Array[Rect2]) -> void:
	var rect: Rect2 = opening["rect"]
	var arch: float = opening["arch"]
	var n_side: Vector3 = plane["n"] if opening["front"] else -plane["n"]
	var e: Vector3 = plane["e"]
	var slope: float = plane["slope"]
	var du := e + Vector3.UP * slope  # el mundo por unidad de u
	var dv := Vector3.UP               # y por unidad de v

	# Las esquinas del arco, como abanicos de pared desde la esquina del rectángulo hasta el arco.
	var r := minf(arch, rect.size.x * 0.5)
	if r > EPS:
		var segments: int = opening["segments"]
		for corner in 2:
			var cu := rect.end.x - r if corner == 0 else rect.position.x + r
			var tip := Vector2(rect.end.x, rect.end.y) if corner == 0 else Vector2(rect.position.x, rect.end.y)
			var from_angle := 0.0 if corner == 0 else PI * 0.5
			for k in segments:
				var t0 := from_angle + PI * 0.5 * float(k) / float(segments)
				var t1 := from_angle + PI * 0.5 * float(k + 1) / float(segments)
				var a := Vector2(cu + r * cos(t0), rect.end.y - r + r * sin(t0))
				var b := Vector2(cu + r * cos(t1), rect.end.y - r + r * sin(t1))
				_emit_triangle(_point(plane, tip.x, tip.y), _point(plane, a.x, a.y), _point(plane, b.x, b.y), n_side)

	if not opening["reveals"]:
		return
	var bounds := _bounds(side_rects)
	var outline := _outline(rect, arch, opening["segments"])
	for i in outline.size():
		var a: Vector2 = outline[i][0]
		var b: Vector2 = outline[(i + 1) % outline.size()][0]
		var side: int = outline[i][1]
		if a.distance_to(b) <= EPS:
			continue
		# En el borde de la pared no hay espesor que mostrar.
		if side == 0 and absf(a.y - bounds.position.y) < EPS:
			continue
		if side == 2 and absf(a.y - bounds.end.y) < EPS and absf(b.y - bounds.end.y) < EPS:
			continue
		if side == 1 and absf(a.x - bounds.end.x) < EPS:
			continue
		if side == 3 and absf(a.x - bounds.position.x) < EPS:
			continue
		# La normal del derrame apunta hacia adentro de la abertura: la izquierda del tramo, en el plano.
		var d := b - a
		var normal := (du * -d.y + dv * d.x).normalized()
		var corners: Array[Vector3] = [
			_point(plane, a.x, a.y), _point(plane, b.x, b.y),
			_point(plane, b.x, b.y, n_side, wall_thickness), _point(plane, a.x, a.y, n_side, wall_thickness),
		]
		var ids := PackedInt32Array()
		for p in corners:
			ids.append(_vertices.size())
			_vertices.append(p)
			_normals.append(normal)
			_colors.append(_color)
		_emit_quad(ids, corners, normal)


# ── Tapas ────────────────────────────────────────────────────────────────────────────────────────

func _emit_caps(group: Dictionary) -> void:
	var module: BuildingModule = group["module"]
	var height: int = group["height"]
	var front: Array = group["front"]
	var back: Array = group["back"]
	_cancel_equal(front, back)
	_emit_cap_side(module, height, _clip_all(front, back), true)
	_emit_cap_side(module, height, _clip_all(back, front), false)


## Saca de las dos listas cada par de tapas iguales: es el caso de todos los pisos intermedios, y no
## necesita ni Clipper ni triangular nada.
static func _cancel_equal(front: Array, back: Array) -> void:
	var i := 0
	while i < front.size():
		var found := -1
		for j in back.size():
			if _same_polygon(front[i], back[j]):
				found = j
				break
		if found >= 0:
			front.remove_at(i)
			back.remove_at(found)
		else:
			i += 1


static func _same_polygon(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for offset in a.size():
		var equal := true
		for k in a.size():
			if a[k].distance_to(b[(k + offset) % a.size()]) > EPS:
				equal = false
				break
		if equal:
			return true
	return false


## Cada polígono menos todos los del otro lado, ya sin agujeros.
static func _clip_all(polygons: Array, cutters: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p: PackedVector2Array in polygons:
		out.append(p)
	for c: PackedVector2Array in cutters:
		var next: Array[PackedVector2Array] = []
		for p in out:
			next.append_array(_simple(Geometry2D.clip_polygons(p, c)))
		out = next
	return out


## Polígonos sin agujeros a partir de lo que devuelve Geometry2D, donde un agujero es un polígono horario.
## Con agujero, el contorno se parte por la vertical que pasa por el centro del agujero, y a cada mitad se
## le restan todos los agujeros: el que se cortó ya no queda encerrado en ninguna, y los demás se resuelven
## igual, una cortada por vez.
static func _simple(results: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for p in results:
		if p.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(p):
			holes.append(p)
		else:
			outers.append(p)
	if holes.is_empty():
		return outers
	var cx := 0.0
	for p in holes[0]:
		cx += p.x
	cx /= float(holes[0].size())
	var halves: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-FAR, -FAR), Vector2(cx, -FAR), Vector2(cx, FAR), Vector2(-FAR, FAR)]),
		PackedVector2Array([Vector2(cx, -FAR), Vector2(FAR, -FAR), Vector2(FAR, FAR), Vector2(cx, FAR)]),
	]
	var out: Array[PackedVector2Array] = []
	for outer in outers:
		for half in halves:
			var parts := Geometry2D.intersect_polygons(outer, half)
			for hole in holes:
				var next: Array[PackedVector2Array] = []
				for part in parts:
					next.append_array(Geometry2D.clip_polygons(part, hole))
				parts = next
			out.append_array(_simple(parts))
	return out


func _emit_cap_side(module: BuildingModule, height: int, polygons: Array[PackedVector2Array], up: bool) -> void:
	var air := Vector3.UP if up else Vector3.DOWN
	var shared := {}
	for polygon in polygons:
		var triangles := Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			continue
		var world := PackedVector3Array()
		for c in polygon:
			world.append(module.cell_to_world(Vector3(c.x, float(height), c.y)))
		# Una normal plana por polígono (Newell), hacia el aire: la tapa se dibuja plana aunque tenga silla.
		var normal := Vector3.ZERO
		for i in world.size():
			var a := world[i]
			var b := world[(i + 1) % world.size()]
			normal += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		normal = normal.normalized()
		if normal.dot(air) < 0.0:
			normal = -normal
		var ids := PackedInt32Array()
		for i in polygon.size():
			var key := Vector2i(roundi(polygon[i].x / EPS), roundi(polygon[i].y / EPS))
			if not shared.has(key):
				shared[key] = _vertices.size()
				_vertices.append(world[i])
				_normals.append(normal)
				_colors.append(_color)
			ids.append(shared[key])
		var t := 0
		while t + 2 < triangles.size():
			var a := triangles[t]
			var b := triangles[t + 1]
			var c := triangles[t + 2]
			# Triángulo por triángulo hacia el aire, con la convención del proyecto.
			if (world[c] - world[a]).cross(world[b] - world[a]).dot(air) < 0.0:
				var swap := b
				b = c
				c = swap
			_indices.append(ids[a])
			_indices.append(ids[b])
			_indices.append(ids[c])
			t += 3
