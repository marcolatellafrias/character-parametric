class_name CityIndex
extends RefCounted

## QUIÉN ES CADA TRIÁNGULO DE LA CIUDAD — la tabla que hace posible apuntarle a algo y que te diga qué es.
##
## El problema que resuelve: cada visualizador de `City` recibe datos con nombre y apellido —este cluster,
## esta celda, este piso— y los TIRA al hornear la malla fusionada. La identidad existe en el momento de
## generar y se pierde en el `append_array`. Sin esta tabla, identificar algo obliga a hacer ingeniería
## inversa con rayos y punto-en-polígono, y esa deducción hay que escribirla DE NUEVO para cada sistema
## nuevo (pipes, escaleras, ventanas).
##
## Acá la identidad se ANOTA en el momento en que existe, al lado de la línea que ya calcula el offset del
## merge. Lo que queda específico de cada sistema es solamente QUÉ ids anota —datos, no lógica—, y por eso
## un sistema nuevo no necesita ningún resolvedor propio: anota y ya aparece en el inspector.
##
## ⚠ ARRAYS PARALELOS, no un diccionario por pieza. Los edificios solos hornean decenas de miles de piezas
## y un Dictionary por cada una sería un costo de memoria real. Acá cada pieza son unos pocos enteros y dos
## Vector3 en arrays empaquetados.
##
## El SCOPE es lo que ata un collider a sus piezas: el cuerpo que frena el rayo lleva su scope en un meta,
## y la búsqueda se hace solo dentro de ese scope. Así no hay que recorrer la ciudad entera, y dos piezas
## de edificios distintos no se pueden confundir.

enum Kind { BUILDING, ROOF, BRIDGE, SIDEWALK, DOOR, WINDOW }

const KIND_NAMES: Array[String] = ["edificio", "techo", "puente", "vereda", "puerta", "ventana"]
## El meta que lleva el StaticBody3D para decir a qué scope pertenece lo que frena el rayo.
const SCOPE_META := "city_index_scope"

var _next_scope: int = 0

var _scope: PackedInt32Array = PackedInt32Array()
## A qué OBJETO pertenece la pieza. Es lo que permite resaltar "todo el edificio" y no solo el módulo: las
## paredes y el techo de un mismo edificio comparten este id aunque vivan en mallas y scopes distintos.
var _object: PackedInt32Array = PackedInt32Array()
var _kind: PackedInt32Array = PackedInt32Array()
## Los cuatro ids de una pieza. Qué significan depende del `kind`, y lo traduce `describe`.
var _id_a: PackedInt32Array = PackedInt32Array()
var _id_b: PackedInt32Array = PackedInt32Array()
var _id_c: PackedInt32Array = PackedInt32Array()
var _id_d: PackedInt32Array = PackedInt32Array()
## El rango [from, to) de la pieza dentro del array de ÍNDICES de su malla. Es lo que permite copiar sus
## triángulos para el resaltado, y lo que permite resolver un `face_index` exacto si el rayo lo da.
var _from: PackedInt32Array = PackedInt32Array()
var _to: PackedInt32Array = PackedInt32Array()
var _aabb_min: PackedVector3Array = PackedVector3Array()
var _aabb_max: PackedVector3Array = PackedVector3Array()

## Qué piezas tiene cada scope: `{scope: PackedInt32Array de posiciones}`.
##
## Sin esto, buscar una pieza recorría las DECENAS DE MILES de la ciudad entera filtrando por scope, una vez
## por frame. Con esto toca solo las de ese cuerpo, que son unas veinte.
var _by_scope: Dictionary = {}
## Qué piezas tiene cada objeto: `{objeto: PackedInt32Array de posiciones}`. Cruza scopes a propósito.
var _by_object: Dictionary = {}
## La malla de cada scope. Vive acá y no en un meta del collider para que una pieza se pueda dibujar sin
## depender de cuál fue el cuerpo que frenó el rayo — que es justo lo que hace falta para resaltar un
## edificio entero, cuyas paredes y techo están en mallas distintas.
var _mesh_by_scope: Dictionary = {}

## LAS TRES MANERAS DE COLOCAR (ver technical/city-generation.md, "Placing objects"), que son las tres
## listas de regiones de abajo y los tres colores de la vista debug.
enum Grid { DEFORMABLE, RIGID, FREE }

## LAS REGIONES COLOCADAS, para dibujar sus cajas en la vista debug (ver City._visualize_placement_boxes):
## una lista por manera de colocar, y en cada una, por pieza, el marco de su región —los cinco vectores de
## `PlacementGrid.region_frame`—. Es la región exacta que la pieza ocupó, no la envolvente de sus
## triángulos: una vereda que no llena su región muestra la región. En free placement, donde no hay
## celdas, es la caja de la entidad instanciada (ver City._place_entity).
var regions: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]


## Un scope nuevo, para estampar en el collider que va a frenar el rayo.
func new_scope() -> int:
	_next_scope += 1
	return _next_scope


## Anota la región de una pieza colocada (ver `regions`).
func add_region(grid: Grid, frame: PackedVector3Array) -> void:
	regions[grid].append_array(frame)


## LA REGIÓN DE UNA ENTIDAD de free placement: ahí no hay celdas, así que la región es su propia caja —el
## mismo transform y el mismo tamaño con que se dibuja, centrada en `x` y `z` y apoyada en `y = 0`, la
## convención de `UnitMesh.build_mesh`—, escrita en el formato de `PlacementGrid.region_frame`.
func add_entity_region(xf: Transform3D, size: Vector3) -> void:
	add_region(Grid.FREE, PackedVector3Array([
		xf * Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), xf.basis.x * size.x, xf.basis.z * size.z,
		Vector3.ZERO, xf.basis.y * size.y]))


## Anota una pieza. `from_index`/`to_index` son posiciones en el array de índices de la malla fusionada.
func add(scope: int, object: int, kind: int, id_a: int, id_b: int, id_c: int, id_d: int,
		from_index: int, to_index: int, verts: PackedVector3Array) -> void:
	if verts.is_empty():
		return
	var lo := verts[0]
	var hi := verts[0]
	for v: Vector3 in verts:
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))

	_scope.append(scope)
	_object.append(object)
	_kind.append(kind)
	_id_a.append(id_a)
	_id_b.append(id_b)
	_id_c.append(id_c)
	_id_d.append(id_d)
	_from.append(from_index)
	_to.append(to_index)
	_aabb_min.append(lo)
	_aabb_max.append(hi)

	# ⚠ SE AGREGA EN EL LUGAR, sin sacar el array a una variable. Un PackedInt32Array es copy-on-write: sacarlo a
	# una local, agregarle y volver a guardarlo COPIA EL ARRAY ENTERO en cada alta, y con miles de ventanas por
	# scope eso era cuadrático.
	var position := _scope.size() - 1
	if not _by_scope.has(scope):
		_by_scope[scope] = PackedInt32Array()
	_by_scope[scope].append(position)

	if not _by_object.has(object):
		_by_object[object] = PackedInt32Array()
	_by_object[object].append(position)


func size() -> int:
	return _scope.size()


## LA PIEZA QUE SE APUNTÓ. Primero por índice de cara, que es exacto; si el rayo no lo da (o no cae en
## ningún rango), por la caja más CHICA que contenga el punto, que es lo más específico que se puede decir.
##
## Las dos rutas son genéricas: no saben si están mirando un techo, un edificio o un caño.
func find(scope: int, point: Vector3, face_index: int = -1) -> int:
	if face_index >= 0:
		var by_face := _find_by_face(scope, face_index)
		if by_face >= 0:
			return by_face

	if not _by_scope.has(scope):
		return -1
	var members: PackedInt32Array = _by_scope[scope]

	var best := -1
	var best_volume := INF
	for i: int in members:
		var lo := _aabb_min[i]
		var hi := _aabb_max[i]
		if point.x < lo.x or point.x > hi.x: continue
		if point.y < lo.y or point.y > hi.y: continue
		if point.z < lo.z or point.z > hi.z: continue
		var size_v := hi - lo
		var volume := maxf(size_v.x, 0.01) * maxf(size_v.y, 0.01) * maxf(size_v.z, 0.01)
		if volume < best_volume:
			best_volume = volume
			best = i
	return best


## El triángulo `face_index` ocupa las posiciones [face_index*3, face_index*3+3) del array de índices. Vale
## solo si el collider se armó con los MISMOS triángulos y en el MISMO orden que la malla, que es el
## contrato que cumplen los constructores de City.
func _find_by_face(scope: int, face_index: int) -> int:
	if not _by_scope.has(scope):
		return -1
	var members: PackedInt32Array = _by_scope[scope]
	var pos := face_index * 3
	for i: int in members:
		if pos >= _from[i] and pos < _to[i]:
			return i
	return -1


## La malla de un scope, de donde se copian los triángulos de sus piezas.
func set_scope_mesh(scope: int, mesh: MeshInstance3D) -> void:
	_mesh_by_scope[scope] = mesh


func mesh_for_scope(scope: int) -> MeshInstance3D:
	return _mesh_by_scope.get(scope, null)


func scope_of(i: int) -> int:
	if i < 0 or i >= _scope.size():
		return -1
	return _scope[i]


## TODAS las piezas del objeto al que pertenece esta: el edificio entero, con sus paredes y su techo.
func members_of_object(i: int) -> PackedInt32Array:
	if i < 0 or i >= _object.size():
		return PackedInt32Array()
	var obj := _object[i]
	if not _by_object.has(obj):
		return PackedInt32Array()
	return _by_object[obj]


## El rango de índices de la pieza, para copiar sus triángulos al resaltado.
func range_of(i: int) -> Vector2i:
	if i < 0 or i >= _from.size():
		return Vector2i.ZERO
	return Vector2i(_from[i], _to[i])


## El centro de la pieza: donde van el punto y el cartel.
func centre_of(i: int) -> Vector3:
	if i < 0 or i >= _aabb_min.size():
		return Vector3.ZERO
	return (_aabb_min[i] + _aabb_max[i]) * 0.5


## La pieza en texto. Es el único lugar donde los cuatro ids vuelven a tener significado, y se traduce según
## el tipo: un sistema nuevo agrega su caso acá y no toca nada más.
func describe(i: int) -> Dictionary:
	if i < 0 or i >= _kind.size():
		return {}
	var kind := _kind[i]
	var lines: Array[String] = []
	match kind:
		Kind.BUILDING:
			lines.append("edificio %d · celda (%d, %d) · piso %d" % [_id_a[i], _id_b[i], _id_c[i], _id_d[i]])
		Kind.ROOF:
			# a = edificio, b = pieza, c = lado del contorno (o -1), d = estilo (o -1 en un tanque).
			var style := "" if _id_d[i] < 0 else " de techo %s" % RoofPlanner.style_name(_id_d[i])
			var side := "" if _id_c[i] < 0 else " · lado %d" % _id_c[i]
			lines.append("%s%s · edificio %d%s" % [RoofPlanner.piece_name(_id_b[i]), style, _id_a[i], side])
		Kind.BRIDGE:
			# Un extremo apoyado en una fachada lleva los mismos ids que su puente: es parte de él.
			lines.append("puente %d · manzanas %d y %d · piso %d" % [_id_a[i], _id_b[i], _id_c[i], _id_d[i]])
		Kind.SIDEWALK:
			# a = edificio, b = piso, c = lado (0 norte, 1 este, 2 sur, 3 oeste) o esquina (0 NO, 1 NE,
			# 2 SE, 3 SO) según la pieza, o -1; d = pieza (SidewalkProps.Piece).
			var where := "" if _id_c[i] < 0 else " %d" % _id_c[i]
			lines.append("%s%s · edificio %d · piso %d" % [SidewalkProps.piece_name(_id_d[i]), where,
				_id_a[i], _id_b[i]])
		Kind.DOOR:
			# a = edificio, b = piso, c = lado, d = número de puerta en la manzana.
			lines.append("puerta de entrega %d · edificio %d · piso %d · lado %d" % [_id_d[i], _id_a[i], _id_b[i], _id_c[i]])
		Kind.WINDOW:
			# a = edificio, b = piso, c = lado, d = criterio (FacadePlanner.Layout). Las ventanas no tienen
			# collider: no se apuntan sueltas, pero aparecen al resaltar su edificio.
			lines.append("ventana %s · edificio %d · piso %d · lado %d" % [FacadePlanner.layout_name(_id_d[i]),
				_id_a[i], _id_b[i], _id_c[i]])
		_:
			lines.append("pieza desconocida")
	return {
		"kind": kind,
		"kind_name": KIND_NAMES[kind] if kind < KIND_NAMES.size() else "?",
		"id_a": _id_a[i], "id_b": _id_b[i], "id_c": _id_c[i], "id_d": _id_d[i],
		"lines": lines,
		"centre": centre_of(i),
	}
