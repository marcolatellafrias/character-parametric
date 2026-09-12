class_name PropGeometry
extends RefCounted

## PRIMITIVAS PARA OBJETOS DE LA CIUDAD — cilindros, conos, quads y triángulos, todos construidos DENTRO DE
## UN CUADRILÁTERO base en vez de alineados a los ejes.
##
## Esa es la idea central y es la que hace que el skew desaparezca como problema. Un techo de edificio no es
## un rectángulo: la grilla distorsionada lo deforma y el terreno lo inclina. Si un objeto se construyera
## como una caja recta y después se torciera, habría que arrastrar ángulos por todos lados. Acá al revés:
## cada punto se da en coordenadas normalizadas `(u, v)` del quad y se interpola —bilineal en XZ, bilineal
## en Y—, así que el objeto nace ya deformado igual que la superficie donde se apoya.
##
## Está aparte de DebugUtil a propósito: esto es CONTENIDO del mundo, no ayuda de depuración. DebugUtil ya
## es un cajón grande de helpers de debug y mezclarlos haría que ninguno de los dos se entienda. Lo único
## que sí se le pide prestado son las CAJAS: `get_skewed_cube_advanced_geometry` ya produce una caja
## skeweada con el winding correcto a partir de 4 vértices base, así que no tiene sentido reescribirla.
##
## El formato de salida es el mismo diccionario que mergea `City._visualize_buildings`:
## `{vertices, normals, colors, indices}`, triángulos planos sin compartir vértices.
##
## ⚠ WINDING: el material de los edificios usa `CULL_BACK`, así que el ORDEN de los vértices decide si una
## cara se ve o no. Nada acá lo deja librado a una convención: `add_tri` recibe un punto interior del sólido
## y ORIENTA cada triángulo hacia afuera, corrigiendo orden y normal a la vez.

const DEFAULT_SEGMENTS := 12


## Un buffer vacío listo para acumular.
static func new_buffer() -> Dictionary:
	return {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
	}


## Mete un diccionario de geometría (el que devuelve DebugUtil) dentro del buffer, corriendo los índices.
static func append_geometry(buffer: Dictionary, geo: Dictionary) -> void:
	if geo.is_empty():
		return
	var offset: int = buffer["vertices"].size()
	buffer["vertices"].append_array(geo["vertices"])
	buffer["normals"].append_array(geo["normals"])
	buffer["colors"].append_array(geo["colors"])
	for idx: int in geo["indices"]:
		buffer["indices"].append(idx + offset)


## Un triángulo orientado HACIA AFUERA respecto de `inside`: si la normal apunta hacia adentro, se da vuelta
## el orden de los vértices. Así ninguna cara queda invisible por culpa del culling.
static func add_tri(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3, inside: Vector3,
		color: Color) -> void:
	# ⚠ CONVENCION DEL PROYECTO: para el orden (a, b, c) la cara que se ve tiene normal (c-a)x(b-a), no
	# al reves. Ver `City._ground_triangle`, que decide el orden con ese mismo producto. Escribirlo dado
	# vuelta compila, no rompe nada, y deja TODAS las caras invertidas: con CULL_BACK se ve el interior.
	var normal := (c - a).cross(b - a)
	if normal.length_squared() <= 0.0:
		return
	normal = normal.normalized()
	var v2 := b
	var v3 := c
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
		v2 = c
		v3 = b
		normal = -normal
	var base: int = buffer["vertices"].size()
	buffer["vertices"].append(a); buffer["vertices"].append(v2); buffer["vertices"].append(v3)
	for i in 3:
		buffer["normals"].append(normal)
		buffer["colors"].append(color)
		buffer["indices"].append(base + i)


## Un triángulo orientado hacia una DIRECCIÓN dada, no hacia afuera de un sólido.
##
## Hace falta para las caras planas donde el truco del punto interior se degenera: el plano de un techo
## de una agua tiene su centroide exactamente en el centro del quad a media altura, que es justo donde
## caería el punto interior, y ahí el producto escalar da ~0 y la orientación queda librada al azar.
## Una cara que mira para abajo es invisible desde arriba, que es de donde se mira un techo.
static func add_tri_facing(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3,
		facing: Vector3, color: Color) -> void:
	# Misma convencion que `add_tri`: la cara visible de (a, b, c) tiene normal (c-a)x(b-a).
	var normal := (c - a).cross(b - a)
	if normal.length_squared() <= 0.0:
		return
	normal = normal.normalized()
	var v2 := b
	var v3 := c
	if normal.dot(facing) < 0.0:
		v2 = c
		v3 = b
		normal = -normal
	var base: int = buffer["vertices"].size()
	buffer["vertices"].append(a); buffer["vertices"].append(v2); buffer["vertices"].append(v3)
	for i in 3:
		buffer["normals"].append(normal)
		buffer["colors"].append(color)
		buffer["indices"].append(base + i)


## Un quad orientado hacia una dirección dada.
static func add_quad_facing(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		facing: Vector3, color: Color) -> void:
	add_tri_facing(buffer, a, b, c, facing, color)
	add_tri_facing(buffer, a, c, d, facing, color)


## Un quad orientado hacia afuera, como dos triángulos.
static func add_quad(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		inside: Vector3, color: Color) -> void:
	add_tri(buffer, a, b, c, inside, color)
	add_tri(buffer, a, c, d, inside, color)


## Un punto dentro del quad, en coordenadas normalizadas, elevado `y` metros sobre él. `quad` va en el orden
## [BL, BR, TR, TL], que es el que devuelven `get_region_vertices` y `get_core_vertices`.
static func point(quad: Array, u: float, v: float, y: float) -> Vector3:
	# Tipados a mano: lo que sale de un Array sin tipar es Variant, y pasarlo a un parametro tipado o
	# inferirlo con `:=` es error de compilacion.
	var q0: Vector3 = quad[0]
	var q1: Vector3 = quad[1]
	var q2: Vector3 = quad[2]
	var q3: Vector3 = quad[3]
	var flat: Array[Vector2] = [
		Vector2(q0.x, q0.z), Vector2(q1.x, q1.z), Vector2(q2.x, q2.z), Vector2(q3.x, q3.z),
	]
	var xz := GridHelper.bilinear_interpolation(flat, u, v)
	var base_y := GridHelper.bilinear_height([q0.y, q1.y, q2.y, q3.y], u, v)
	return Vector3(xz.x, base_y + y, xz.y)


## Un sub-cuadrilátero del quad, en el mismo orden [BL, BR, TR, TL].
static func sub_quad(quad: Array, u0: float, v0: float, u1: float, v1: float, y: float) -> Array:
	return [
		point(quad, u0, v0, y), point(quad, u1, v0, y),
		point(quad, u1, v1, y), point(quad, u0, v1, y),
	]


## El centro del quad a una altura dada. Sirve como punto interior para orientar caras.
static func center(quad: Array, y: float) -> Vector3:
	return point(quad, 0.5, 0.5, y)


## Una caja: se delega en DebugUtil, que ya la resuelve skeweada y bien orientada.
static func add_box(buffer: Dictionary, quad: Array, u0: float, v0: float, u1: float, v1: float,
		y: float, height: float, color: Color) -> void:
	append_geometry(buffer, DebugUtil.get_skewed_cube_advanced_geometry(
		sub_quad(quad, u0, v0, u1, v1, y), height, color, {}))


## Un cilindro cuya base es el círculo INSCRITO en el sub-cuadrilátero dado. Si el sub-quad es cuadrado sale
## redondo; si está deformado sale elíptico, que es exactamente lo que se quiere cuando el techo lo está.
static func add_cylinder(buffer: Dictionary, quad: Array, u0: float, v0: float, u1: float, v1: float,
		y: float, height: float, color: Color, segments: int = DEFAULT_SEGMENTS) -> void:
	var uc := (u0 + u1) * 0.5
	var vc := (v0 + v1) * 0.5
	var ru := (u1 - u0) * 0.5
	var rv := (v1 - v0) * 0.5
	var inside := point(quad, uc, vc, y + height * 0.5)
	var bottom_center := point(quad, uc, vc, y)
	var top_center := point(quad, uc, vc, y + height)

	for i in segments:
		var a1 := TAU * float(i) / float(segments)
		var a2 := TAU * float(i + 1) / float(segments)
		var b1 := point(quad, uc + cos(a1) * ru, vc + sin(a1) * rv, y)
		var b2 := point(quad, uc + cos(a2) * ru, vc + sin(a2) * rv, y)
		var t1 := point(quad, uc + cos(a1) * ru, vc + sin(a1) * rv, y + height)
		var t2 := point(quad, uc + cos(a2) * ru, vc + sin(a2) * rv, y + height)
		add_quad(buffer, b1, b2, t2, t1, inside, color)
		add_tri(buffer, bottom_center, b1, b2, inside, color)
		add_tri(buffer, top_center, t1, t2, inside, color)


## Un cono apoyado en el mismo círculo inscrito. Con `height` chico queda la tapa achatada de un tanque.
static func add_cone(buffer: Dictionary, quad: Array, u0: float, v0: float, u1: float, v1: float,
		y: float, height: float, color: Color, segments: int = DEFAULT_SEGMENTS) -> void:
	var uc := (u0 + u1) * 0.5
	var vc := (v0 + v1) * 0.5
	var ru := (u1 - u0) * 0.5
	var rv := (v1 - v0) * 0.5
	var inside := point(quad, uc, vc, y + height * 0.25)
	var apex := point(quad, uc, vc, y + height)
	var base_center := point(quad, uc, vc, y)

	for i in segments:
		var a1 := TAU * float(i) / float(segments)
		var a2 := TAU * float(i + 1) / float(segments)
		var b1 := point(quad, uc + cos(a1) * ru, vc + sin(a1) * rv, y)
		var b2 := point(quad, uc + cos(a2) * ru, vc + sin(a2) * rv, y)
		add_tri(buffer, b1, b2, apex, inside, color)
		add_tri(buffer, base_center, b1, b2, inside, color)
