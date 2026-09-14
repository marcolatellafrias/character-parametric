class_name ModulePlacer
extends RefCounted

## LA INTERFAZ DE COLOCACIÓN EN LA MATRIZ DEFORMABLE. Una sola llamada:
##
##     placer.place(module, cell, lo, size, mesh, kind, id_b, id_c, id_d)
##
## Quien coloca piensa en dos cosas: qué REGIÓN de celdas de edificio ocupa (`lo` y `size`, en celdas del
## módulo: x y z de 0 a `columns`/`rows`, y = índice de altura) y qué MESH va, diseñada en el cubo unitario
## (ver UnitMesh). Nada más. Lo demás pasa solo, y es la parte que no se puede olvidar:
##
##   · LA DEFORMACIÓN: cada vértice del cubo se lleva al mundo por `BuildingModule.point_at_f`, o sea con
##     la grilla distorsionada y el terreno del módulo. Dos piezas de módulos vecinos que comparten arista
##     coinciden exactas, porque en la arista las dos bilineales se reducen a la misma recta.
##   · EL ÍNDICE: la pieza queda anotada en `CityIndex` con su scope y su objeto, así el inspector la nombra.
##   · LA OCUPACIÓN: la región queda marcada en el módulo. Si ya estaba ocupada, `place` devuelve false y no
##     pone nada: dos objetos no se pueden superponer por descuido.
##
## ⚠ ESTO ES PARA OBJETOS DEFORMABLES: los que se pueden estirar sin quedar mal y necesitan alinearse con
## sus vecinos (techos, columnas, extremos de puente, caños). Los rígidos —ventanas, tanques, balcones—
## van por la matriz rígida de una superficie, que es otro sistema (ver technical/city-generation.md).
##
## Un placer vive lo que vive una malla fusionada: se crea con el scope y el objeto que le tocan, y escribe
## en el buffer de esa malla.

var _index: CityIndex
var _scope: int
var _object: int
var _buffer: Dictionary

## Cuánto se corre un punto del cubo para medir hacia dónde mira una cara en el mundo.
const FACING_STEP := 0.01


func _init(index: CityIndex, scope: int, object: int, buffer: Dictionary) -> void:
	_index = index
	_scope = scope
	_object = object
	_buffer = buffer


## Coloca `mesh` en la región `[lo, lo + size)` del módulo. Devuelve false, sin colocar nada, si la región
## no está libre o se sale del módulo.
func place(module: BuildingModule, lo: Vector3i, size: Vector3i, mesh: UnitMesh,
		kind: int, id_a: int, id_b: int, id_c: int, id_d: int) -> bool:
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return false
	if lo.x < 0 or lo.z < 0 or lo.x + size.x > module.columns or lo.z + size.z > module.rows:
		return false
	if not module.is_free(lo, size):
		return false

	var idx_from: int = _buffer["indices"].size()
	var v_from: int = _buffer["vertices"].size()

	var fx := float(module.columns)
	var fz := float(module.rows)
	for t in mesh.triangle_count():
		var a := _to_world(module, lo, size, mesh.vertices[mesh.indices[t * 3]], fx, fz)
		var b := _to_world(module, lo, size, mesh.vertices[mesh.indices[t * 3 + 1]], fx, fz)
		var c := _to_world(module, lo, size, mesh.vertices[mesh.indices[t * 3 + 2]], fx, fz)
		# Hacia dónde mira, medido EN EL MUNDO: la deformación puede espejar los ejes del cubo, así que la
		# dirección de diseño no se puede usar tal cual.
		var unit_centroid := (mesh.vertices[mesh.indices[t * 3]] + mesh.vertices[mesh.indices[t * 3 + 1]]
				+ mesh.vertices[mesh.indices[t * 3 + 2]]) / 3.0
		var facing := _to_world(module, lo, size, unit_centroid + mesh.facings[t] * FACING_STEP, fx, fz) \
				- _to_world(module, lo, size, unit_centroid, fx, fz)
		PropGeometry.add_tri_facing(_buffer, a, b, c, facing, mesh.colors[t])

	var idx_to: int = _buffer["indices"].size()
	if idx_to == idx_from:
		return false
	var piece_verts: PackedVector3Array = _buffer["vertices"].slice(v_from)
	_index.add(_scope, _object, kind, id_a, id_b, id_c, id_d, idx_from, idx_to, piece_verts)
	module.occupy(lo, size)
	return true


## LA MISMA INTERFAZ PARA UN OBJETO RÍGIDO: una región de celdas de una `RigidMatrix` y una mesh unitaria.
## La diferencia es que acá la mesh va al mundo con una transformación AFÍN —el marco de la matriz—, sin
## deformación alguna: es lo que hace que una ventana o un tanque conserven sus proporciones. Igual que
## `place`, anota en el índice y ocupa; y devuelve false, sin colocar, si la región no entra o no está libre.
func place_rigid(matrix: RigidMatrix, lo: Vector3i, size: Vector3i, mesh: UnitMesh,
		kind: int, id_a: int, id_b: int, id_c: int, id_d: int) -> bool:
	if not matrix.is_free(lo, size):
		return false

	var idx_from: int = _buffer["indices"].size()
	var v_from: int = _buffer["vertices"].size()
	var flo := Vector3(lo)
	var fsize := Vector3(size)
	for t in mesh.triangle_count():
		var a := matrix.cell_to_world(flo + mesh.vertices[mesh.indices[t * 3]] * fsize)
		var b := matrix.cell_to_world(flo + mesh.vertices[mesh.indices[t * 3 + 1]] * fsize)
		var c := matrix.cell_to_world(flo + mesh.vertices[mesh.indices[t * 3 + 2]] * fsize)
		PropGeometry.add_tri_facing(_buffer, a, b, c, matrix.dir_to_world(mesh.facings[t]), mesh.colors[t])

	var idx_to: int = _buffer["indices"].size()
	if idx_to == idx_from:
		return false
	var piece_verts: PackedVector3Array = _buffer["vertices"].slice(v_from)
	_index.add(_scope, _object, kind, id_a, id_b, id_c, id_d, idx_from, idx_to, piece_verts)
	matrix.occupy(lo, size)
	return true


## Un punto del cubo unitario en el mundo. Pasa por `point_at_f` del módulo con las coordenadas del MÓDULO
## (no de la región), así la deformación es exactamente la de la grilla y no una aproximación por región.
static func _to_world(module: BuildingModule, lo: Vector3i, size: Vector3i, p: Vector3,
		fx: float, fz: float) -> Vector3:
	var u := (float(lo.x) + p.x * float(size.x)) / fx
	var v := (float(lo.z) + p.z * float(size.z)) / fz
	var h := float(lo.y) + p.y * float(size.y)
	return module.point_at_f(u, v, h)
