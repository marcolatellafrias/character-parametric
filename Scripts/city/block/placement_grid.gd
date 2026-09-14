class_name PlacementGrid
extends RefCounted

## LA GRILLA DONDE SE COLOCAN LAS COSAS — UNA SOLA CLASE para lo deformable y lo rígido.
##
## Una grilla es un CUADRILÁTERO de cuatro esquinas en el mundo, una dirección `axis_n` que sale de él y una
## cantidad de celdas por eje. Un punto en celdas `(x, y, z)` va al mundo por LA BILINEAL de las esquinas en
## (x, z), más `y` celdas a lo largo de `axis_n` (`cell_to_world`). Ese es todo el mecanismo, y por él pasa
## cada vértice de cada cosa que se coloca en la ciudad (ver GridPlacer). Por eso una pieza NO PUEDE quedar
## torcida respecto de su grilla, ni aunque se quiera: su geometría sale de las celdas mismas, como un
## conector que solo entra de una manera.
##
## Las dos grillas del juego son esta misma clase con celdas distintas:
##   · BuildingModule, la DEFORMABLE: el cuadrilátero es la celda de la grilla distorsionada con su relieve,
##     `axis_n` es arriba, 80 × 80 celdas de ~0,14 m y sin techo de altura. Sus celdas se doblan con la
##     ciudad, y lo que va en ellas se dobla igual: techos, veredas, extremos de puente.
##   · RigidMatrix, la RÍGIDA: el cuadrilátero es una SUPERFICIE (una fachada, una azotea), `axis_n` su
##     normal, y las celdas se RECALCULAN para que salgan lo más cúbicas posible, de ~0,25 m. Como la
##     superficie es casi plana y casi un paralelogramo, la bilineal es casi afín y lo que va en ella casi no
##     se deforma: una ventana sigue el cizallamiento de su pared —el mismo que tiene el edificio—, la base
##     de un tanque se apoya exacta sobre la silla de la azotea, y nada más.
##
## La OCUPACIÓN también vive acá: una lista de cajas en celdas, con `is_free` y `occupy`. Lista y no matriz
## porque un módulo tiene 80 × 80 × 32 celdas por piso —una matriz por módulo serían decenas de millones de
## entradas por ciudad— y los objetos son pocos. La PROYECCIÓN de una grilla sobre otra —lo que una vereda
## del módulo ocupa en la fachada que tiene detrás— es `occupied_world_corners` de una y
## `mark_world_hexahedron` de la otra, pasando por el mundo, la única coordenada que las dos comparten.

## Altura sin techo, para una grilla que no acota `y` (el módulo: los pisos que hagan falta).
const UNBOUNDED := 1 << 30

## Las doce aristas de un sólido de ocho esquinas en orden de bits (1 → x, 2 → y, 4 → z).
const HEXAHEDRON_EDGES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
	Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]

## Las cuatro esquinas, recorridas: (0,0), (x,0), (x,z), (0,z) en celdas.
var corners: Array[Vector3] = []
var axis_n := Vector3.UP
var count := Vector3i.ZERO
## Cuánto mide una celda en metros, por eje: (a lo largo de x, a lo largo de n, a lo largo de z). En x y z
## es el promedio de los dos lados: en un cuadrilátero no todas las celdas miden igual.
var cell := Vector3.ZERO

var _occupied: Array[Array] = []
## Dos ejes del plano de la grilla, perpendiculares a `axis_n`, para invertir la bilineal (`world_to_cell`).
var _e1 := Vector3.RIGHT
var _e2 := Vector3.BACK


func _setup(p_corners: Array[Vector3], p_axis_n: Vector3, cell_n: float, p_count: Vector3i) -> void:
	corners = p_corners
	axis_n = p_axis_n.normalized()
	count = p_count
	var along_x := (corners[0].distance_to(corners[1]) + corners[3].distance_to(corners[2])) * 0.5
	var along_z := (corners[0].distance_to(corners[3]) + corners[1].distance_to(corners[2])) * 0.5
	cell = Vector3(along_x / float(maxi(count.x, 1)), cell_n, along_z / float(maxi(count.z, 1)))
	var e1 := corners[1] - corners[0]
	e1 -= axis_n * e1.dot(axis_n)
	_e1 = e1.normalized() if e1.length_squared() > 0.0 else Vector3.RIGHT
	_e2 = axis_n.cross(_e1)


func is_valid() -> bool:
	return corners.size() == 4 and count.x > 0 and count.y > 0 and count.z > 0


# ── CELDAS ↔ MUNDO ──────────────────────────────────────────────────────────────────────────────

## UN PUNTO EN CELDAS (continuo) AL MUNDO: la bilineal de las esquinas en (x, z) más `y` celdas por la normal.
## Se escribe a mano y sin reservar nada: por acá pasa cada vértice de todo lo colocado en la ciudad.
func cell_to_world(p: Vector3) -> Vector3:
	var s := p.x / float(count.x)
	var t := p.z / float(count.z)
	return corners[0] * ((1.0 - s) * (1.0 - t)) + corners[1] * (s * (1.0 - t)) \
			+ corners[2] * (s * t) + corners[3] * ((1.0 - s) * t) + axis_n * (p.y * cell.y)


## LA MISMA BILINEAL, RESTRINGIDA A UNA REGIÓN y precalculada: cinco vectores `[o, dx, dz, dxz, dy]` tales
## que un punto `u` del cubo unitario de la región `[lo, lo + size)` cae en
##     o + dx·u.x + dz·u.z + dxz·(u.x·u.z) + dy·u.y
## y su derivada es `(dx + dxz·u.z, dy, dz + dxz·u.x)`. Es exactamente `cell_to_world(lo + u * size)`,
## escrito así para que el placer no llame a nada por vértice: pasan millones.
func region_frame(lo: Vector3, size: Vector3) -> PackedVector3Array:
	var s0 := lo.x / float(count.x)
	var t0 := lo.z / float(count.z)
	var ds := size.x / float(count.x)
	var dt := size.z / float(count.z)
	var c0 := corners[0]
	var e1 := corners[1] - c0
	var e3 := corners[3] - c0
	var e13 := c0 - corners[1] + corners[2] - corners[3]
	# bilinear(s, t) = c0 + e1·s + e3·t + e13·s·t, con s = s0 + ds·u.x y t = t0 + dt·u.z.
	var o := c0 + e1 * s0 + e3 * t0 + e13 * (s0 * t0) + axis_n * (lo.y * cell.y)
	var dx := (e1 + e13 * t0) * ds
	var dz := (e3 + e13 * s0) * dt
	var dxz := e13 * (ds * dt)
	var dy := axis_n * (size.y * cell.y)
	return PackedVector3Array([o, dx, dz, dxz, dy])


## UN PUNTO DEL MUNDO EN CELDAS (continuo, sin acotar): la inversa. En el plano se invierte la bilineal por
## Newton desde el centro —en un paralelogramo converge en un paso, en una azotea con silla en pocos—, y la
## altura es lo que sobra a lo largo de la normal.
func world_to_cell(p: Vector3) -> Vector3:
	var c0 := corners[0]
	var c1 := corners[1]
	var c2 := corners[2]
	var c3 := corners[3]
	var target := Vector2(p.dot(_e1), p.dot(_e2))
	var s := 0.5
	var t := 0.5
	for _i in 8:
		var b := _bilinear(s, t)
		var f := Vector2(b.dot(_e1), b.dot(_e2)) - target
		if f.length_squared() < 0.0000000001:
			break
		var ds := (c1 - c0).lerp(c2 - c3, t)
		var dt := (c3 - c0).lerp(c2 - c1, s)
		var j11 := ds.dot(_e1)
		var j12 := dt.dot(_e1)
		var j21 := ds.dot(_e2)
		var j22 := dt.dot(_e2)
		var det := j11 * j22 - j12 * j21
		if absf(det) < 0.000000000001:
			break
		s -= (j22 * f.x - j12 * f.y) / det
		t -= (-j21 * f.x + j11 * f.y) / det
	var on := _bilinear(s, t)
	return Vector3(s * float(count.x), (p - on).dot(axis_n) / cell.y, t * float(count.z))


func _bilinear(s: float, t: float) -> Vector3:
	return corners[0] * ((1.0 - s) * (1.0 - t)) + corners[1] * (s * (1.0 - t)) \
			+ corners[2] * (s * t) + corners[3] * ((1.0 - s) * t)


## Cuántas celdas ocupa una medida en metros, por eje: a lo largo de `x`, hacia afuera por `n`, a lo largo
## de `z`. Qué es "alto" depende de la grilla: en una azotea es `n`, en una fachada es `z`. Redondea hacia
## arriba: un objeto nunca se achica para entrar.
func cells_for(x_m: float, n_m: float, z_m: float) -> Vector3i:
	if not is_valid():
		return Vector3i.ZERO
	return Vector3i(ceili(x_m / cell.x), ceili(n_m / cell.y), ceili(z_m / cell.z))


## La esquina de una región de `size` celdas centrada en la grilla y apoyada en ella.
func centered(size: Vector3i) -> Vector3i:
	return Vector3i((count.x - size.x) / 2, 0, (count.z - size.z) / 2)


# ── OCUPACIÓN ───────────────────────────────────────────────────────────────────────────────────

## Si la región `[lo, lo + size)` entra en la grilla.
func contains(lo: Vector3i, size: Vector3i) -> bool:
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return false
	if lo.x < 0 or lo.y < 0 or lo.z < 0:
		return false
	var hi := lo + size
	return hi.x <= count.x and hi.y <= count.y and hi.z <= count.z


## Si la región `[lo, lo + size)` entra en la grilla y no toca nada ya colocado.
func is_free(lo: Vector3i, size: Vector3i) -> bool:
	if not contains(lo, size):
		return false
	var hi := lo + size
	for box: Array in _occupied:
		var o_lo: Vector3i = box[0]
		var o_hi: Vector3i = box[1]
		if lo.x < o_hi.x and hi.x > o_lo.x and lo.y < o_hi.y and hi.y > o_lo.y and lo.z < o_hi.z and hi.z > o_lo.z:
			return false
	return true


func occupy(lo: Vector3i, size: Vector3i) -> void:
	_occupied.append([lo, lo + size])


## LA PRIMERA FILA LIBRE A LO LARGO DE `z` desde `lo.z`, hasta `lo.z + max_rise` inclusive: la región
## `[lo, lo + size)` corrida lo justo para no tocar nada. Es como un objeto de pared SE APOYA sobre lo que hay
## delante de la fachada —una puerta sobre la vereda— en vez de atravesarlo. Devuelve -1 si no hay lugar
## dentro de ese margen: lo que estorba es demasiado alto para pisarlo.
func first_free_along_z(lo: Vector3i, size: Vector3i, max_rise: int) -> int:
	for rise in range(0, max_rise + 1):
		if is_free(Vector3i(lo.x, lo.y, lo.z + rise), size):
			return lo.z + rise
	return -1


## Las regiones ocupadas como sólidos del MUNDO: las ocho esquinas de cada región, ya llevadas al mundo, en el
## orden de bits (1 → x, 2 → y, 4 → z) que espera `mark_world_hexahedron`. `index_from`/`index_to` filtran por
## altura: solo las regiones que se cruzan con `[index_from, index_to)`, así una fachada pregunta por su piso
## y no paga proyectar lo que está en otro.
##
## Se dan las esquinas y NO la caja envolvente: una vereda de 3 m que baja con el terreno tiene una envolvente
## de decenas de centímetros de alto, y proyectada así marcaba esa altura entera sobre la fachada.
func occupied_world_corners(index_from: int = -UNBOUNDED, index_to: int = UNBOUNDED) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for box: Array in _occupied:
		var lo: Vector3i = box[0]
		var hi: Vector3i = box[1]
		if lo.y >= index_to or hi.y <= index_from:
			continue
		var pts := PackedVector3Array()
		for corner in 8:
			pts.append(cell_to_world(Vector3(
				hi.x if corner & 1 else lo.x,
				hi.y if corner & 2 else lo.y,
				hi.z if corner & 4 else lo.z)))
		out.append(pts)
	return out


## MARCA COMO OCUPADO lo que cubre un sólido de otra grilla, dado por sus ocho esquinas en el mundo (el orden de
## `occupied_world_corners`): la proyección de una grilla sobre esta.
##
## Se hace COLUMNA POR COLUMNA A LO LARGO DE LA NORMAL, y no con la envolvente del sólido entero: para cada
## rebanada de profundidad se recortan las doce aristas contra ella y se marca solo la extensión de lo que
## queda. La diferencia importa: una vereda de 3 m que baja un 12 % con el terreno tiene una envolvente de
## casi 40 cm de alto, y proyectada de una vez marcaba 40 cm de fachada; rebanada, junto a la pared marca su
## espesor real, que es lo que una puerta tiene que pisar. Sigue siendo conservador dentro de cada rebanada
## —la extensión de las aristas recortadas—, nunca de menos.
func mark_world_hexahedron(pts: PackedVector3Array) -> void:
	if pts.size() != 8 or not is_valid():
		return
	var c: Array[Vector3] = []
	var n_lo := INF
	var n_hi := -INF
	for p: Vector3 in pts:
		var q := world_to_cell(p)
		c.append(q)
		n_lo = minf(n_lo, q.y)
		n_hi = maxf(n_hi, q.y)
	var k_from := maxi(floori(n_lo), 0)
	var k_to := mini(ceili(n_hi), count.y)
	for k in range(k_from, k_to):
		var s0 := float(k)
		var s1 := float(k + 1)
		var x_min := INF
		var x_max := -INF
		var z_min := INF
		var z_max := -INF
		var any := false
		for e: Vector2i in HEXAHEDRON_EDGES:
			var a := c[e.x]
			var b := c[e.y]
			var ta := 0.0
			var tb := 1.0
			if is_equal_approx(a.y, b.y):
				if a.y < s0 or a.y > s1:
					continue
			else:
				var t0 := (s0 - a.y) / (b.y - a.y)
				var t1 := (s1 - a.y) / (b.y - a.y)
				ta = clampf(minf(t0, t1), 0.0, 1.0)
				tb = clampf(maxf(t0, t1), 0.0, 1.0)
				if tb <= ta:
					continue
			var pa := a.lerp(b, ta)
			var pb := a.lerp(b, tb)
			x_min = minf(x_min, minf(pa.x, pb.x))
			x_max = maxf(x_max, maxf(pa.x, pb.x))
			z_min = minf(z_min, minf(pa.z, pb.z))
			z_max = maxf(z_max, maxf(pa.z, pb.z))
			any = true
		if not any:
			continue
		var lo_i := Vector3i(maxi(floori(x_min), 0), k, maxi(floori(z_min), 0))
		var hi_i := Vector3i(mini(ceili(x_max), count.x), k + 1, mini(ceili(z_max), count.z))
		if hi_i.x <= lo_i.x or hi_i.z <= lo_i.z:
			continue
		_occupied.append([lo_i, hi_i])
