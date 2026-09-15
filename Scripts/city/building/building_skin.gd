class_name BuildingSkin
extends RefCounted

## LA PIEL DE UN EDIFICIO — la malla final, reconstruida a partir de las caras de sus módulos POR POSICIÓN,
## sin saber de módulos ni de pisos:
##   · Lo que no se ve, se va: dos caras coplanares enfrentadas —la pared entre dos módulos pegados, el techo
##     de un piso contra el suelo del siguiente— son interior de sólido donde se superponen, y se descuentan
##     una de la otra. Lo que no se superpone queda: la parte de una fachada que asoma sobre el vecino más bajo.
##   · Lo coplanar se une: las doce paredes de una fachada de doce pisos salen como UNA, con los vértices
##     compartidos. Es lo que necesita un shader de texturizado, y lo que menos triángulos cuesta.
## Como no depende de qué módulo es vecino de cuál, sirve igual para un edificio escalonado por pisos: si el
## piso de arriba es más chico, el suelo que le sobra al de abajo queda como cornisa sin cambiar nada acá.
##
## Es SOLO lo que se ve. La identidad de las piezas (CityIndex) y el collider salen de la malla debug, que
## conserva la forma básica módulo por módulo (ver BuildingShell): fundir doce pisos en un quad no puede
## costarle al inspector saber en qué piso hiciste clic.
##
## LAS PAREDES SON RECTÁNGULOS EN EL MARCO DE SU PLANO. Cada pared es un paralelogramo vertical (ver
## BuildingModule.get_wall_quad) cuyas líneas de piso son paralelas a la línea de la que el plano salió; en
## el marco (u a lo largo de esa línea, v la altura menos la pendiente por u) es un rectángulo con los lados
## en los ejes, y todo lo que hay en ese plano también. Entonces "unión de las de un lado menos unión de las
## del otro" es aritmética de rectángulos: exacta, sin Clipper, sin agujeros —un rectángulo menos otro son a
## lo sumo cuatro— y se une sola al fusionar los que comparten ancho. Si una cara no cumpliera lo del marco
## (la línea de piso torcida respecto del plano) se emite tal cual, ni oculta ni unida, y se cuenta en
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

## Un plano por entrada: `{n, d, o, e, slope, front, back}` — normal canónica y distancia, el marco (origen,
## dirección horizontal de la línea, pendiente de la línea) y los rectángulos de cada lado.
var _planes: Array[Dictionary] = []
## Los planos por normal redondeada, para encontrar el de una cara sin recorrerlos todos.
var _planes_by_normal: Dictionary = {}
## Las tapas por `[módulo, altura]`: `{module, height, front, back}` con polígonos en celdas.
var _caps: Dictionary = {}
## Caras que no entraron en el marco de su plano: `[quad, normal]`, se emiten tal cual.
var _raw: Array = []
var raw_walls := 0

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
	var u0 := _u(plane, quad[0])
	var u1 := _u(plane, quad[1])
	var v0 := _v(plane, quad[0])
	var v1 := _v(plane, quad[3])
	# El marco vale si la línea de piso es paralela a la del plano y los lados son verticales.
	if absf(_v(plane, quad[1]) - v0) > EPS or absf(_u(plane, quad[3]) - u0) > EPS:
		_raw.append([quad, normal])
		raw_walls += 1
		return
	var rect := Rect2(minf(u0, u1), minf(v0, v1), absf(u1 - u0), absf(v1 - v0))
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


# ── Salida ───────────────────────────────────────────────────────────────────────────────────────

func build() -> ArrayMesh:
	for plane in _planes:
		var front := _merge(plane["front"])
		var back := _merge(plane["back"])
		var n: Vector3 = plane["n"]
		_emit_rects(plane, _merge(_subtract_all(front, back)), n)
		_emit_rects(plane, _merge(_subtract_all(back, front)), -n)
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
	var plane := {"n": canon, "d": d, "o": on, "e": e, "slope": slope, "front": [], "back": []}
	_planes.append(plane)
	if not _planes_by_normal.has(key):
		_planes_by_normal[key] = PackedInt32Array()
	_planes_by_normal[key].append(_planes.size() - 1)
	return plane


func _u(plane: Dictionary, p: Vector3) -> float:
	return (p - plane["o"]).dot(plane["e"])


func _v(plane: Dictionary, p: Vector3) -> float:
	return p.y - plane["o"].y - plane["slope"] * _u(plane, p)


func _point(plane: Dictionary, u: float, v: float) -> Vector3:
	var o: Vector3 = plane["o"]
	var e: Vector3 = plane["e"]
	return o + e * u + Vector3.UP * (v + plane["slope"] * u)


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


static func _subtract_all(rects: Array[Rect2], cutters: Array[Rect2]) -> Array[Rect2]:
	var out := rects
	for c in cutters:
		var next: Array[Rect2] = []
		for r in out:
			next.append_array(_subtract(r, c))
		out = next
	return out


## Un rectángulo menos otro: lo que queda a la izquierda y a la derecha del corte a toda altura, y lo que
## queda abajo y arriba entre medio. A lo sumo cuatro, y ninguno de menos de un milímetro.
static func _subtract(r: Rect2, c: Rect2) -> Array[Rect2]:
	var cut := r.intersection(c)
	if cut.size.x <= EPS or cut.size.y <= EPS:
		return [r]
	var out: Array[Rect2] = []
	for piece: Rect2 in [
		Rect2(r.position.x, r.position.y, cut.position.x - r.position.x, r.size.y),
		Rect2(cut.end.x, r.position.y, r.end.x - cut.end.x, r.size.y),
		Rect2(cut.position.x, r.position.y, cut.size.x, cut.position.y - r.position.y),
		Rect2(cut.position.x, cut.end.y, cut.size.x, r.end.y - cut.end.y),
	]:
		if piece.size.x > EPS and piece.size.y > EPS:
			out.append(piece)
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
