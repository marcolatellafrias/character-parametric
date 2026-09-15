class_name UnitMesh
extends RefCounted

## UNA MESH DISEÑADA EN EL CUBO UNITARIO — `x`, `y`, `z` de 0 a 1 — sin saber dónde va a ir.
##
## Es la mitad "qué" de la interfaz de colocación: el diseñador arma el objeto acá, en un cubo abstracto, y
## `GridPlacer` lo lleva a una región de celdas de una grilla (un módulo, o la superficie de una pared). Quien diseña la mesh nunca
## piensa en metros, ni en grillas, ni en terreno: solo en proporciones dentro del cubo.
##
## Cada triángulo lleva su color y hacia dónde MIRA (en el espacio del cubo). Se guarda la dirección y no
## el orden de los vértices porque la grilla puede espejar ejes, y el orden solo se puede decidir después,
## en el mundo (lo hace `GridPlacer.place`). Los constructores de acá calculan esa dirección con un punto
## interior del sólido.

const DEFAULT_SEGMENTS := 12

var vertices := PackedVector3Array()
## Tres índices por triángulo.
var indices := PackedInt32Array()
## Un color por triángulo.
var colors := PackedColorArray()
## Hacia dónde mira cada triángulo, en el espacio del cubo.
var facings := PackedVector3Array()


func triangle_count() -> int:
	return indices.size() / 3


## Un triángulo mirando hacia afuera de `inside`.
func add_tri(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var centroid := (a + b + c) / 3.0
	var facing := centroid - inside
	if facing.length_squared() <= 0.0:
		facing = (b - a).cross(c - a)
	add_tri_facing(a, b, c, facing, color)


## Un triángulo mirando hacia `facing`.
func add_tri_facing(a: Vector3, b: Vector3, c: Vector3, facing: Vector3, color: Color) -> void:
	var base := vertices.size()
	vertices.append(a); vertices.append(b); vertices.append(c)
	indices.append(base); indices.append(base + 1); indices.append(base + 2)
	colors.append(color)
	facings.append(facing.normalized())


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, color: Color) -> void:
	add_tri(a, b, c, inside, color)
	add_tri(a, c, d, inside, color)


func add_quad_facing(a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, color: Color) -> void:
	add_tri_facing(a, b, c, facing, color)
	add_tri_facing(a, c, d, facing, color)


# ── ROTACIÓN ────────────────────────────────────────────────────────────────────────────────────

## La mesh girada `k` cuartos de vuelta alrededor de Y, dentro del cubo. Un cuarto de vuelta lleva el lado
## -z al lado +x, así que una pieza canónica con el exterior en -z (dirección 0) queda con el exterior en
## la dirección `k`. Con `k = 0` devuelve la misma mesh, no una copia.
func rotated(k: int) -> UnitMesh:
	k = posmod(k, 4)
	if k == 0:
		return self
	var out := UnitMesh.new()
	for v: Vector3 in vertices:
		out.vertices.append(_rot_point(v, k))
	out.indices = indices.duplicate()
	out.colors = colors.duplicate()
	for f: Vector3 in facings:
		out.facings.append(_rot_dir(f, k))
	return out


static func _rot_point(p: Vector3, k: int) -> Vector3:
	var x := p.x
	var z := p.z
	for _i in k:
		var nx := 1.0 - z
		var nz := x
		x = nx
		z = nz
	return Vector3(x, p.y, z)


static func _rot_dir(d: Vector3, k: int) -> Vector3:
	var x := d.x
	var z := d.z
	for _i in k:
		var nx := -z
		var nz := x
		x = nx
		z = nz
	return Vector3(x, d.y, z)


# ── PRIMITIVAS ──────────────────────────────────────────────────────────────────────────────────
# Todas reciben su caja dentro del cubo unitario: `lo` y `hi` de 0 a 1 en los tres ejes.

## Una caja alineada a los ejes del cubo.
func add_box(lo: Vector3, hi: Vector3, color: Color) -> void:
	var inside := (lo + hi) * 0.5
	var p000 := Vector3(lo.x, lo.y, lo.z); var p100 := Vector3(hi.x, lo.y, lo.z)
	var p110 := Vector3(hi.x, lo.y, hi.z); var p010 := Vector3(lo.x, lo.y, hi.z)
	var p001 := Vector3(lo.x, hi.y, lo.z); var p101 := Vector3(hi.x, hi.y, lo.z)
	var p111 := Vector3(hi.x, hi.y, hi.z); var p011 := Vector3(lo.x, hi.y, hi.z)
	add_quad(p000, p100, p110, p010, inside, color)  # abajo
	add_quad(p001, p101, p111, p011, inside, color)  # arriba
	add_quad(p000, p100, p101, p001, inside, color)  # -z
	add_quad(p010, p110, p111, p011, inside, color)  # +z
	add_quad(p000, p010, p011, p001, inside, color)  # -x
	add_quad(p100, p110, p111, p101, inside, color)  # +x


## Un cilindro con el eje en Y, con la elipse inscrita en la caja.
func add_cylinder(lo: Vector3, hi: Vector3, color: Color, segments: int = DEFAULT_SEGMENTS) -> void:
	_add_cylinder(lo, hi, color, segments, Vector3.AXIS_Y)


## Un cilindro con el eje en Z: lo que sale de un tablero (ver ControlArchetype), donde +z es hacia quien
## lo mira.
func add_cylinder_z(lo: Vector3, hi: Vector3, color: Color, segments: int = DEFAULT_SEGMENTS) -> void:
	_add_cylinder(lo, hi, color, segments, Vector3.AXIS_Z)


func _add_cylinder(lo: Vector3, hi: Vector3, color: Color, segments: int, axis: int) -> void:
	var centre := (lo + hi) * 0.5
	var radius := (hi - lo) * 0.5
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var bottom := centre
	bottom[axis] = lo[axis]
	var top := centre
	top[axis] = hi[axis]
	for i in segments:
		var a1 := TAU * float(i) / float(segments)
		var a2 := TAU * float(i + 1) / float(segments)
		var b1 := bottom
		b1[u] += cos(a1) * radius[u]
		b1[v] += sin(a1) * radius[v]
		var b2 := bottom
		b2[u] += cos(a2) * radius[u]
		b2[v] += sin(a2) * radius[v]
		var t1 := b1
		t1[axis] = hi[axis]
		var t2 := b2
		t2[axis] = hi[axis]
		add_quad(b1, b2, t2, t1, centre, color)
		add_tri(bottom, b1, b2, centre, color)
		add_tri(top, t1, t2, centre, color)


## Un anillo con el eje en Z: la elipse inscrita en la caja, hueca hasta `thickness` de su radio.
func add_ring_z(lo: Vector3, hi: Vector3, thickness: float, color: Color, segments: int = DEFAULT_SEGMENTS) -> void:
	var centre := (lo + hi) * 0.5
	var outer := Vector2(hi.x - lo.x, hi.y - lo.y) * 0.5
	var inner := outer * (1.0 - thickness)
	var depth := Vector3(0.0, 0.0, hi.z - lo.z)
	for i in segments:
		var d1 := Vector2.from_angle(TAU * float(i) / float(segments))
		var d2 := Vector2.from_angle(TAU * float(i + 1) / float(segments))
		var o1 := Vector3(centre.x + d1.x * outer.x, centre.y + d1.y * outer.y, lo.z)
		var o2 := Vector3(centre.x + d2.x * outer.x, centre.y + d2.y * outer.y, lo.z)
		var i1 := Vector3(centre.x + d1.x * inner.x, centre.y + d1.y * inner.y, lo.z)
		var i2 := Vector3(centre.x + d2.x * inner.x, centre.y + d2.y * inner.y, lo.z)
		# Cada cara mira desde el centro de su tramo del anillo.
		var mid := (o1 + o2 + i1 + i2) * 0.25 + depth * 0.5
		add_quad(o1, o2, o2 + depth, o1 + depth, mid, color)
		add_quad(i1, i2, i2 + depth, i1 + depth, mid, color)
		add_quad(o1, o2, i2, i1, mid, color)
		add_quad(o1 + depth, o2 + depth, i2 + depth, i1 + depth, mid, color)


## Un cono con el eje en Y, apoyado en la elipse inscrita en la base de la caja y con la punta arriba.
func add_cone(lo: Vector3, hi: Vector3, color: Color, segments: int = DEFAULT_SEGMENTS) -> void:
	var cx := (lo.x + hi.x) * 0.5
	var cz := (lo.z + hi.z) * 0.5
	var rx := (hi.x - lo.x) * 0.5
	var rz := (hi.z - lo.z) * 0.5
	var inside := Vector3(cx, lo.y + (hi.y - lo.y) * 0.25, cz)
	var apex := Vector3(cx, hi.y, cz)
	var base_centre := Vector3(cx, lo.y, cz)
	for i in segments:
		var a1 := TAU * float(i) / float(segments)
		var a2 := TAU * float(i + 1) / float(segments)
		var b1 := Vector3(cx + cos(a1) * rx, lo.y, cz + sin(a1) * rz)
		var b2 := Vector3(cx + cos(a2) * rx, lo.y, cz + sin(a2) * rz)
		add_tri(b1, b2, apex, inside, color)
		add_tri(base_centre, b1, b2, inside, color)


# ── ENTIDAD ─────────────────────────────────────────────────────────────────────────────────────

## LA MESH COMO ENTIDAD: el cubo escalado a `size` metros con `pivot` en el origen —por defecto centrado
## en `x` y `z` y apoyado en `y = 0`—, con normales planas y el color de cada triángulo. Es lo que se
## instancia en un free placement (ver FreePlacement): la pieza entera, sin deformar, en un transform.
## Indexada, así el índice de piezas la copia como a cualquier otra.
func build_mesh(size: Vector3, pivot := Vector3(0.5, 0.0, 0.5)) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for t in triangle_count():
		var a := (vertices[indices[t * 3]] - pivot) * size
		var b := (vertices[indices[t * 3 + 1]] - pivot) * size
		var c := (vertices[indices[t * 3 + 2]] - pivot) * size
		# ⚠ CONVENCIÓN DEL PROYECTO: para el orden (a, b, c) la cara visible tiene normal (c - a) x (b - a).
		# La dirección diseñada en el cubo se lleva al escalado con la inversa de la escala.
		var facing := Vector3(facings[t].x / size.x, facings[t].y / size.y, facings[t].z / size.z)
		var normal := (c - a).cross(b - a)
		if normal.dot(facing) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		normal = normal.normalized()
		var base := verts.size()
		for p: Vector3 in [a, b, c]:
			verts.append(p)
			normals.append(normal)
			cols.append(colors[t])
			idx.append(base)
			base += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
