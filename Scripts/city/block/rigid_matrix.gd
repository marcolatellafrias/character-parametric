class_name RigidMatrix
extends RefCounted

## LA MATRIZ RÍGIDA DE UNA SUPERFICIE — donde viven los objetos que NO se deforman: ventanas, puertas,
## tanques, balcones.
##
## Se construye SOLO a partir de la superficie: un marco de tres ejes perpendiculares apoyado en ella, y una
## cantidad de celdas elegida para que salgan lo más cúbicas posible, de `TARGET_CELL_M` de lado. La
## profundidad se proyecta hacia afuera de la superficie con el mismo tamaño de celda. Nada de esto depende
## de los objetos: la matriz existe desde el inicio, y lo único que los objetos deformables le cambian es
## qué celdas quedan DISPONIBLES (ver `mark_world_box`).
##
## ⚠ NO HAY UMBRAL DE DISTORSIÓN. Un objeto rígido se coloca en este marco sin deformarse nunca; la
## distorsión de la ciudad solo achica la matriz. La superficie es un cuadrilátero sesgado y la matriz es
## el rectángulo ALINEADO más grande que le cabe adentro —los triángulos que sobran por el sesgo son
## espacio residual, aceptado—, así que un quad muy torcido o muy angosto da pocas celdas, o ninguna, y el
## objeto que necesita más de las que hay no entra. Ese es todo el filtro.
##
## El marco es (u, n, v): `u` a lo largo del primer lado del quad, `n` la normal, `v = u × n`. Un cubo
## unitario cae en una celda como (x → u, y → n, z → v), conservando su mano.
##
## ⚠ UNA AZOTEA NO ES PLANA. Sale de una bilineal sobre el relieve con cuatro alturas independientes en las
## esquinas: es una silla de montar, el mismo caso que un quad no plano en Blender, que se parte en
## triángulos con un quiebre. Medido sobre 6.519 azoteas: las esquinas se apartan de un plano 2,2 cm de
## mediana, 6 cm en el percentil 90 y hasta 17 cm. Las FACHADAS no tienen el problema: su borde de arriba es
## el de abajo subido, y eso es siempre un plano (medido: 0,000001 m).
##
## Una cuadrícula rígida es un plano por definición, así que no puede copiar esa forma. Lo que sí hace: el
## plano se centra entre las cuatro esquinas, y CADA OBJETO SE APOYA EN LA ALTURA REAL DE LA SUPERFICIE BAJO
## SU CENTRO (`surface_offset`), corriéndose entero esa diferencia. Así el error no es el de la azotea sino
## el de la silla dentro de la huella del objeto, que crece con el cuadrado de su tamaño. Medido en las
## 20.636 patas de tanque de una ciudad: 1,2 mm de mediana, 4 mm en el percentil 90, 2,2 cm en la peor.
## Para un objeto CENTRADO el centrado del plano ya da eso solo; el `surface_offset` es lo que lo mantiene
## cuando el objeto va en cualquier otro lugar de la superficie. Solo un objeto que ocupe la azotea entera
## vería los centímetros completos, y eso es inherente a ser rígido.

const TARGET_CELL_M := 0.25

var origin := Vector3.ZERO
var axis_u := Vector3.RIGHT
var axis_n := Vector3.UP
var axis_v := Vector3.BACK
## El tamaño de celda en metros, por eje del marco: (u, n, v).
var cell := Vector3.ZERO
## Cuántas celdas, por eje del marco: (u, n, v).
var count := Vector3i.ZERO
## Regiones ocupadas, como cajas `[lo, hi)` en celdas. Lista y no matriz por la misma razón que en
## BuildingModule: los objetos son pocos.
var _occupied: Array[Array] = []
## El quad de la superficie, para preguntarle la altura real en un punto (ver `surface_offset`).
var _corners: Array[Vector3] = []


## La matriz de un quad `[c0, c1, c2, c3]` en el mundo, recorrido en orden. `depth_m` es cuánto se proyecta
## hacia afuera; `outward` dice de qué lado está afuera, para orientar la normal.
static func from_quad(corners: Array[Vector3], depth_m: float, outward: Vector3) -> RigidMatrix:
	var m := RigidMatrix.new()
	if corners.size() != 4:
		return m
	var c0 := corners[0]
	var c1 := corners[1]
	var c2 := corners[2]
	var c3 := corners[3]

	var normal := (c2 - c0).cross(c3 - c1)
	if normal.length_squared() <= 0.0:
		return m
	normal = normal.normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	var along := (c1 - c0) - normal * (c1 - c0).dot(normal)
	if along.length_squared() <= 0.0:
		return m
	m.axis_u = along.normalized()
	m.axis_n = normal
	m.axis_v = m.axis_u.cross(m.axis_n)

	# El rectángulo alineado más grande que cabe: en cada eje, del SEGUNDO valor más chico al SEGUNDO más
	# grande de las cuatro esquinas. Para un quad convexo más o menos alineado eso es exactamente lo que
	# queda entre sus dos lados, y no depende de en qué orden vengan las esquinas.
	var us: Array[float] = []
	var vs: Array[float] = []
	for c: Vector3 in corners:
		var f := m._flat(c, c0)
		us.append(f.x)
		vs.append(f.y)
	us.sort()
	vs.sort()
	var u_min := us[1]
	var u_max := us[2]
	var v_min := vs[1]
	var v_max := vs[2]
	var width := u_max - u_min
	var height := v_max - v_min
	if width <= 0.0 or height <= 0.0:
		return m

	# Cantidad de celdas: las que hagan falta para que midan lo más cerca de `TARGET_CELL_M`. Un lado más
	# corto que media celda da cero, y la matriz queda vacía a propósito.
	var n_u := roundi(width / TARGET_CELL_M)
	var n_v := roundi(height / TARGET_CELL_M)
	if n_u <= 0 or n_v <= 0:
		return m
	var cell_u := width / float(n_u)
	var cell_v := height / float(n_v)
	var cell_n := (cell_u + cell_v) * 0.5
	var n_n := maxi(1, ceili(depth_m / cell_n))

	# El plano se centra entre las cuatro esquinas a lo largo de la normal: por la primera esquina sola,
	# las otras tres quedaban todas del mismo lado del plano.
	var lift := 0.0
	for c: Vector3 in corners:
		lift += (c - c0).dot(normal)
	lift *= 0.25
	m.origin = c0 + m.axis_u * u_min + m.axis_v * v_min + normal * lift
	m.cell = Vector3(cell_u, cell_n, cell_v)
	m.count = Vector3i(n_u, n_n, n_v)
	m._corners = corners.duplicate()
	return m


## CUÁNTO HAY QUE CORRER UN OBJETO para que su base toque la superficie REAL en el punto `p_cell` (celdas,
## se usa su `x` y `z`), como vector a lo largo de la normal. Es la diferencia entre la bilineal del quad y el
## plano de la matriz en ese punto: cero en una fachada, unos milímetros en el medio de una azotea típica.
##
## Para evaluar la bilineal en un punto del mundo hay que invertirla en XZ; son un par de pasos de Newton
## desde el centro, que sobran para un quad apenas torcido.
func surface_offset(p_cell: Vector3) -> Vector3:
	if _corners.size() != 4:
		return Vector3.ZERO
	var on_plane := cell_to_world(Vector3(p_cell.x, 0.0, p_cell.z))
	var target := Vector2(on_plane.x, on_plane.z)
	var c0 := _corners[0]
	var c1 := _corners[1]
	var c2 := _corners[2]
	var c3 := _corners[3]
	var s := 0.5
	var t := 0.5
	for _i in 6:
		var p := _bilinear(s, t)
		var f := Vector2(p.x, p.z) - target
		if f.length_squared() < 0.000001:
			break
		var ds := (c1 - c0).lerp(c2 - c3, t)
		var dt := (c3 - c0).lerp(c2 - c1, s)
		var det := ds.x * dt.z - dt.x * ds.z
		if absf(det) < 0.000000001:
			break
		s -= (dt.z * f.x - dt.x * f.y) / det
		t -= (-ds.z * f.x + ds.x * f.y) / det
	s = clampf(s, 0.0, 1.0)
	t = clampf(t, 0.0, 1.0)
	return axis_n * (_bilinear(s, t) - on_plane).dot(axis_n)


func _bilinear(s: float, t: float) -> Vector3:
	return _corners[0] * ((1.0 - s) * (1.0 - t)) + _corners[1] * (s * (1.0 - t)) \
			+ _corners[2] * (s * t) + _corners[3] * ((1.0 - s) * t)


func is_valid() -> bool:
	return count.x > 0 and count.y > 0 and count.z > 0


## Coordenadas (u, v) de un punto sobre el plano, relativas a `reference`, en metros.
func _flat(p: Vector3, reference: Vector3) -> Vector2:
	var d := p - reference
	return Vector2(d.dot(axis_u), d.dot(axis_v))


## Un punto en celdas (continuo, `x` → u, `y` → n, `z` → v) al mundo. Es afín: nada se deforma.
func cell_to_world(p: Vector3) -> Vector3:
	return origin + axis_u * (p.x * cell.x) + axis_n * (p.y * cell.y) + axis_v * (p.z * cell.z)


## Una dirección del marco al mundo, para orientar caras.
func dir_to_world(d: Vector3) -> Vector3:
	return axis_u * d.x + axis_n * d.y + axis_v * d.z


## Un punto del mundo en celdas (continuo).
func world_to_cell(p: Vector3) -> Vector3:
	var d := p - origin
	return Vector3(d.dot(axis_u) / cell.x, d.dot(axis_n) / cell.y, d.dot(axis_v) / cell.z)


## MARCA COMO OCUPADO todo lo que toque la caja del mundo `[lo, hi]`: la proyección conservadora de una
## región deformable. Marca de más —una caja girada respecto del marco ocupa su envolvente—, nunca de menos.
func mark_world_box(lo: Vector3, hi: Vector3) -> void:
	var cmin := Vector3(INF, INF, INF)
	var cmax := Vector3(-INF, -INF, -INF)
	for corner in 8:
		var p := Vector3(
			hi.x if corner & 1 else lo.x,
			hi.y if corner & 2 else lo.y,
			hi.z if corner & 4 else lo.z)
		var c := world_to_cell(p)
		cmin = Vector3(minf(cmin.x, c.x), minf(cmin.y, c.y), minf(cmin.z, c.z))
		cmax = Vector3(maxf(cmax.x, c.x), maxf(cmax.y, c.y), maxf(cmax.z, c.z))
	var lo_i := Vector3i(maxi(floori(cmin.x), 0), maxi(floori(cmin.y), 0), maxi(floori(cmin.z), 0))
	var hi_i := Vector3i(mini(ceili(cmax.x), count.x), mini(ceili(cmax.y), count.y), mini(ceili(cmax.z), count.z))
	if hi_i.x <= lo_i.x or hi_i.y <= lo_i.y or hi_i.z <= lo_i.z:
		return
	_occupied.append([lo_i, hi_i])


## Si la región `[lo, lo + size)` está dentro de la matriz y libre.
func is_free(lo: Vector3i, size: Vector3i) -> bool:
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return false
	if lo.x < 0 or lo.y < 0 or lo.z < 0:
		return false
	var hi := lo + size
	if hi.x > count.x or hi.y > count.y or hi.z > count.z:
		return false
	for box: Array in _occupied:
		var o_lo: Vector3i = box[0]
		var o_hi: Vector3i = box[1]
		if lo.x < o_hi.x and hi.x > o_lo.x and lo.y < o_hi.y and hi.y > o_lo.y and lo.z < o_hi.z and hi.z > o_lo.z:
			return false
	return true


func occupy(lo: Vector3i, size: Vector3i) -> void:
	_occupied.append([lo, lo + size])


## Cuántas celdas ocupa una medida en metros, por eje del marco (ancho → u, alto → n, fondo → v). Redondea
## hacia arriba: un objeto rígido nunca se achica para entrar.
func cells_for(width_m: float, height_m: float, depth_m: float) -> Vector3i:
	if not is_valid():
		return Vector3i.ZERO
	return Vector3i(ceili(width_m / cell.x), ceili(height_m / cell.y), ceili(depth_m / cell.z))


## La esquina de una región de `size` celdas centrada en la superficie y apoyada en ella.
func centered(size: Vector3i) -> Vector3i:
	return Vector3i((count.x - size.x) / 2, 0, (count.z - size.z) / 2)
