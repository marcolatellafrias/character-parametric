class_name GridPlacer
extends RefCounted

## LA INTERFAZ DE COLOCACIÓN. Una sola llamada, para cualquier grilla:
##
##     placer.place(grid, lo, size, mesh, kind, id_a, id_b, id_c, id_d)
##
## Quien coloca piensa en dos cosas: qué REGIÓN de celdas ocupa (`lo` y `size`, en celdas de la grilla) y qué
## MESH va, diseñada en el cubo unitario (ver UnitMesh). Nada más. Lo demás pasa solo, y es la parte que no se
## puede olvidar:
##
##   · LA FORMA: cada vértice del cubo se lleva al mundo por `PlacementGrid.cell_to_world`, o sea con las
##     celdas de esa grilla. En un módulo eso es la grilla distorsionada y el relieve; en una superficie
##     rígida, celdas casi cúbicas que siguen la pared. La pieza no puede quedar torcida respecto de su grilla
##     porque no hay otra fuente de posición. Dos piezas de módulos vecinos que comparten arista coinciden
##     exactas, porque en la arista las dos bilineales se reducen a la misma recta.
##   · EL ÍNDICE: la pieza queda anotada en `CityIndex` con su scope y su objeto, así el inspector la nombra;
##     y con ella su región, que es lo que la vista debug dibuja como caja (`CityIndex.add_region`).
##   · LA OCUPACIÓN: la región queda marcada en la grilla. Si ya estaba ocupada o se salía, `place` devuelve
##     false y no pone nada: dos objetos no se pueden superponer por descuido.
##
## Un placer vive lo que vive una malla fusionada: se crea con el scope y el objeto que le tocan, y escribe
## en el buffer de esa malla.

var _index: CityIndex
var _scope: int
var _object: int
var _buffer: Dictionary


## Un buffer de malla vacío: `{vertices, normals, colors, indices}`, triángulos planos sin compartir vértices.
## Es el formato que `City._bake_placed` convierte en `ArrayMesh`.
static func new_buffer() -> Dictionary:
	return {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
	}


## Un buffer como `MeshInstance3D`. Lo usan la ciudad (`City._bake_placed`, que además le pone el collider)
## y quien coloca fuera de ella (el design sandbox, ver SampleWall). Sin `material`, uno de colores por
## vértice propio.
static func bake_mesh(buffer: Dictionary, material: Material = null, shadows := true) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = buffer["normals"]
	arrays[Mesh.ARRAY_COLOR] = buffer["colors"]
	arrays[Mesh.ARRAY_INDEX] = buffer["indices"]
	var mesh := ArrayMesh.new()
	if not buffer["vertices"].is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	if material == null:
		material = StandardMaterial3D.new()
		(material as StandardMaterial3D).vertex_color_use_as_albedo = true
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows 			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _init(index: CityIndex, scope: int, object: int, buffer: Dictionary) -> void:
	_index = index
	_scope = scope
	_object = object
	_buffer = buffer


## Coloca `mesh` en la región `[lo, lo + size)` de `grid`. Devuelve false, sin colocar nada, si la región no
## está libre o se sale de la grilla.
## `sink_cells` hunde la pieza esa cantidad de celdas hacia adentro de la superficie (una ventana metida
## en el espesor de la pared, ver BuildingSkin.add_opening): la ocupación sigue siendo la región declarada,
## delante de la pared, que es lo que las piezas se disputan entre sí.
func place(grid: PlacementGrid, lo: Vector3i, size: Vector3i, mesh: UnitMesh,
		kind: int, id_a: int, id_b: int, id_c: int, id_d: int, sink_cells := 0, over_occupied := false,
		max_skew_deg := 0.0) -> bool:
	# Lo que ATRAVIESA lo ya colocado (una cúpula sobre el techo que sea) no pide lugar libre, solo entrar
	# en la grilla; ocupa igual, así lo que venga después lo ve. Y un deformable CON LÍMITE no entra si su
	# región está torcida más de `max_skew_deg` (ver PlacementGrid.LIMITED_SKEW_DEG).
	if not (grid.contains(lo, size) if over_occupied else grid.is_free(lo, size)):
		return false
	if max_skew_deg > 0.0 and grid.region_skew_deg(lo, size) > max_skew_deg:
		return false

	# La bilineal de la grilla restringida a la región, precalculada (ver PlacementGrid.region_frame), y la
	# pieza escrita en arrays propios que se vuelcan de una vez al buffer: por acá pasan cientos de miles de
	# ventanas, y en GDScript cada llamada por vértice cuesta.
	var frame := grid.region_frame(Vector3(lo.x, lo.y - sink_cells, lo.z), Vector3(size))
	var o := frame[0]
	var dx := frame[1]
	var dz := frame[2]
	var dxz := frame[3]
	var dy := frame[4]
	var tris := mesh.triangle_count()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(tris * 3)
	normals.resize(tris * 3)
	colors.resize(tris * 3)
	var written := 0
	for t in tris:
		var pa := mesh.vertices[mesh.indices[t * 3]]
		var pb := mesh.vertices[mesh.indices[t * 3 + 1]]
		var pc := mesh.vertices[mesh.indices[t * 3 + 2]]
		var a := o + dx * pa.x + dz * pa.z + dxz * (pa.x * pa.z) + dy * pa.y
		var b := o + dx * pb.x + dz * pb.z + dxz * (pb.x * pb.z) + dy * pb.y
		var c := o + dx * pc.x + dz * pc.z + dxz * (pc.x * pc.z) + dy * pc.y
		# ⚠ CONVENCIÓN DEL PROYECTO: para el orden (a, b, c) la cara visible tiene normal (c-a)x(b-a). Hacia
		# dónde mira se mide EN EL MUNDO, porque la grilla puede espejar los ejes del cubo: la dirección de
		# diseño de la mesh se lleva al mundo con la derivada en el centro del triángulo, y se da vuelta el
		# orden si no coincide.
		var normal := (c - a).cross(b - a)
		if normal.length_squared() <= 0.0:
			continue
		normal = normal.normalized()
		var m := (pa + pb + pc) / 3.0
		var f := mesh.facings[t]
		var facing := (dx + dxz * m.z) * f.x + dy * f.y + (dz + dxz * m.x) * f.z
		if normal.dot(facing) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		verts[written] = a
		verts[written + 1] = b
		verts[written + 2] = c
		var color := mesh.colors[t]
		for k in 3:
			normals[written + k] = normal
			colors[written + k] = color
		written += 3
	# Una pieza sin triángulos ocupa igual: es una abertura cuya hoja es un nodo aparte (ver Gate).
	if written == 0 and tris > 0:
		return false
	verts.resize(written)
	normals.resize(written)
	colors.resize(written)

	var v_from: int = _buffer["vertices"].size()
	var idx_from: int = _buffer["indices"].size()
	var indices := PackedInt32Array()
	indices.resize(written)
	for i in written:
		indices[i] = v_from + i
	_buffer["vertices"].append_array(verts)
	_buffer["normals"].append_array(normals)
	_buffer["colors"].append_array(colors)
	_buffer["indices"].append_array(indices)
	_index.add(_scope, _object, kind, id_a, id_b, id_c, id_d, idx_from, idx_from + written, verts)
	grid.occupy(lo, size)
	_index.add_region(CityIndex.Grid.RIGID if grid is RigidMatrix else CityIndex.Grid.DEFORMABLE, frame)
	return true
