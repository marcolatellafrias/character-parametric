class_name FreePlacement
extends RefCounted

## EL TERCER MODO DE COLOCAR — ni la grilla del módulo ni la de superficie: UN QUAD donde se apoyan
## ENTIDADES que no se deforman jamás. Autos estacionados, containers, chimeneas: cada uno es un transform
## (dónde sobre el quad, y cómo gira) y lo único que el sistema sabe de él es su HUELLA, un rectángulo en el
## plano del quad, con margen al borde y a las otras huellas.
##
## Las otras dos grillas deforman lo que ponen —mucho el módulo, apenas la superficie—, porque lo que va en
## ellas se dibuja con sus celdas. Acá no hay celdas: la pieza se instancia entera en un lugar. Por eso un
## tanque de agua o un auto van acá y no en la matriz rígida de la azotea, que sobre una silla los deforma.
##
## Es SECUENCIAL como las grillas (ver technical/city-generation.md, "Passes"): lo que ya está —de este
## sistema o proyectado de las otras dos con `block_points`— limita lo que entra después. No controla la
## altura: es un quad, y por ahora no hace falta más.

## Las esquinas en el mundo, recorridas: `[c0, c1, c2, c3]`, `u` de c0 a c1 y `v` de c0 a c3.
var corners: Array[Vector3] = []
## Cuánto mide, en metros, a lo largo de `u` y de `v`.
var size := Vector2.ZERO
## Margen al borde del quad y entre huellas.
var margin := 0.0

var _taken: Array[Rect2] = []


func _init(quad: Array[Vector3], p_margin: float) -> void:
	corners = quad
	margin = p_margin
	if quad.size() == 4:
		size = Vector2(quad[0].distance_to(quad[1]), quad[0].distance_to(quad[3]))


func is_valid() -> bool:
	return corners.size() == 4 and size.x > 0.0 and size.y > 0.0


## Si una huella entra: dentro del quad menos el margen, y sin tocar ninguna otra ni su margen.
func is_free(footprint: Rect2) -> bool:
	if not is_valid():
		return false
	var inside := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	if not inside.encloses(footprint):
		return false
	var grown := footprint.grow(margin)
	for taken in _taken:
		if grown.intersects(taken):
			return false
	return true


## Coloca la huella si entra. Devuelve false, sin ocupar nada, si no.
func place(footprint: Rect2) -> bool:
	if not is_free(footprint):
		return false
	_taken.append(footprint)
	return true


## Marca como ocupado lo que cubren esos puntos del mundo, proyectados sobre el quad (su envolvente en
## `u`, `v`), más `clearance`. Es la proyección de las otras grillas: la región de una puerta, un extremo
## de puente.
func block_points(points: PackedVector3Array, clearance := 0.0) -> void:
	if points.is_empty() or not is_valid():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var uv := to_local(p)
		lo = Vector2(minf(lo.x, uv.x), minf(lo.y, uv.y))
		hi = Vector2(maxf(hi.x, uv.x), maxf(hi.y, uv.y))
	_taken.append(Rect2(lo - Vector2.ONE * clearance, hi - lo + Vector2.ONE * clearance * 2.0))


## Marca ocupada una franja a lo ancho entero del quad, entre dos puntos del mundo (por su `u`): delante de
## una puerta no estaciona nadie, esté la puerta a la distancia que esté del quad.
func block_span(a: Vector3, b: Vector3, clearance := 0.0) -> void:
	if not is_valid():
		return
	var ua := to_local(a).x
	var ub := to_local(b).x
	var u0 := minf(ua, ub) - clearance
	var u1 := maxf(ua, ub) + clearance
	_taken.append(Rect2(u0, -size.y, u1 - u0, size.y * 3.0))


## Un punto del mundo en el marco del quad (`u`, `v` en metros), proyectado sobre su plano.
func to_local(p: Vector3) -> Vector2:
	var eu := (corners[1] - corners[0]).normalized()
	var ev := (corners[3] - corners[0]).normalized()
	var d := p - corners[0]
	return Vector2(d.dot(eu), d.dot(ev))


## Dónde va lo que ocupa `footprint`: el transform con origen en el centro de la huella sobre el quad, `z`
## a lo largo de `u`, `y` la normal del quad (arriba en una franja de calle o una azotea), `x` lo que cierra
## la terna. Lo que se coloque ahí no se deforma: se instancia con este transform y listo.
func frame_at(footprint: Rect2) -> Transform3D:
	var centre := footprint.get_center()
	var origin := at(centre.x, centre.y)
	var along := (corners[1] - corners[0]).normalized()
	var normal := (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized()
	if normal.y < 0.0:
		normal = -normal
	var across := normal.cross(along).normalized()
	return Transform3D(Basis(across, normal, along), origin)


## Un punto del marco al mundo: la bilineal de las esquinas.
func at(u: float, v: float) -> Vector3:
	var s := u / size.x
	var t := v / size.y
	return corners[0] * ((1.0 - s) * (1.0 - t)) + corners[1] * (s * (1.0 - t)) \
			+ corners[2] * (s * t) + corners[3] * ((1.0 - s) * t)
