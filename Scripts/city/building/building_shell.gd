class_name BuildingShell
extends RefCounted

## LA CÁSCARA DE UN EDIFICIO — sus módulos piso por piso, en la forma básica sin huecos, de donde salen
## las dos mallas del edificio:
##
##   · La DEBUG, que se arma acá: color del barrio con el sombreado por piso y por módulo (ver
##     NeighborhoodTypes.debug_color), y en cada vértice SUS COORDENADAS EN LAS DOS GRILLAS —la deformable
##     del módulo y la rígida de su superficie—, que es lo que Shaders/building_debug.gdshader dibuja como
##     grilla. ES LA MALLA SEMÁNTICA: sus triángulos van módulo por módulo y piso por piso, así que el
##     índice de piezas (CityIndex) anota rangos sobre ella y el collider del edificio se toma de ella tal
##     cual (`Mesh.get_faces`). Quien apunta a un edificio sigue sabiendo en qué celda y en qué piso, se vea
##     la malla que se vea.
##   · La FINAL, la del juego, que arma la piel (BuildingSkin) con las mismas caras: color del arquetipo,
##     sin caras interiores y con las coplanares unidas. Es solo lo que se ve.
##
## Las dos se construyen en la misma pasada y cuál se ve lo decide la vista (City._apply_view): nada se
## regenera para cambiar de una a otra.
##
## LAS CARAS SON LAS PAREDES DEL MÓDULO (`BuildingModule.get_walls`) más las dos tapas que cierran su
## contorno. La pared que se ve es literalmente el quad sobre el que se arma la matriz rígida
## (`RigidMatrix.of_wall`), y la azotea es el quad de `RigidMatrix.of_roof`: la grilla dibujada no puede
## correrse de la grilla donde se coloca porque son el mismo objeto.
##
## Las tapas solo se emiten contra el aire: la de abajo en el piso 0 y la de arriba en el último —o donde el
## módulo del piso vecino es otro objeto, que hoy no pasa (ver BuildingCluster.building_modules)—. Es un
## ahorro, no la garantía: la piel descuenta por posición cualquier tapa que quede contra otra.
##
## LAS COORDENADAS DE GRILLA VAN POR VÉRTICE Y SE INTERPOLAN. En las paredes eso es exacto: son
## paralelogramos, y sobre un paralelogramo la bilineal de la grilla es afín. En las tapas no: el núcleo es
## un cuadrilátero general con silla, y la interpolación lineal se desvía de la bilineal en el interior. Por
## eso la malla debug tiene DOS SUPERFICIES: las paredes, con lo justo, y las tapas, que llevan además la
## bilineal del núcleo en XZ y la derivada de sus coordenadas, para que el shader invierta por Newton la
## misma cuenta que `PlacementGrid.world_to_cell`. Las paredes son la mayoría de los vértices y no pagan
## nada de eso. Los rangos del índice se anotan en el espacio de `Mesh.get_faces` —primero todas las
## paredes, después todas las tapas—, que es el orden en que el collider ve los triángulos.
##
## Superficie 0, paredes (por vértice):  UV = (x, z) en celdas del módulo · UV2 = (x, z) en celdas de la
##   matriz rígida de la pared · CUSTOM0 = altura en celdas del módulo.
## Superficie 1, tapas:  UV y UV2 igual, interpolados (el punto de partida del Newton) · CUSTOM0 = (altura,
##   1, p, q) con (p, q) los parámetros del quad del núcleo · CUSTOM1 = (c0.xz, e1.xz) y CUSTOM2 = (e3.xz,
##   e13.xz), la bilineal del núcleo en XZ · CUSTOM3 = (ancho, fondo, n_x, n_z), cuánto cambian UV y UV2 por
##   unidad de (p, q).

## Cuánto se oscurecen los pisos impares y los módulos impares (en damero) de la malla debug, para leer la
## altura y dónde termina cada módulo. 1 sería nada.
const SHADE := 0.85

## La malla final, alimentada con las mismas caras que se emiten acá.
var skin: BuildingSkin

# Superficie 0: paredes.
var _w_vertices := PackedVector3Array()
var _w_normals := PackedVector3Array()
var _w_colors := PackedColorArray()
var _w_uv := PackedVector2Array()
var _w_uv2 := PackedVector2Array()
var _w_height := PackedFloat32Array()
var _w_indices := PackedInt32Array()

# Superficie 1: tapas.
var _c_vertices := PackedVector3Array()
var _c_normals := PackedVector3Array()
var _c_colors := PackedColorArray()
var _c_uv := PackedVector2Array()
var _c_uv2 := PackedVector2Array()
var _c_custom0 := PackedFloat32Array()
var _c_custom1 := PackedFloat32Array()
var _c_custom2 := PackedFloat32Array()
var _c_custom3 := PackedFloat32Array()
var _c_indices := PackedInt32Array()

## Cuántas celdas tiene la matriz rígida de cada superficie, por módulo y pared (`Wall.slot`, o -1 para la
## azotea). No depende del piso —la de un piso es la del piso 0 trasladada—, así que se calcula una vez.
var _rigid_counts := {}


func _init(final_color: Color) -> void:
	skin = BuildingSkin.new(final_color)


func is_empty() -> bool:
	return _w_vertices.is_empty()


## Dónde terminan las paredes en el espacio de `Mesh.get_faces`: el offset de los rangos de las tapas.
func wall_index_count() -> int:
	return _w_indices.size()


## Agrega un piso de un módulo. Devuelve `{walls, caps, vertices}` —el rango [from, to) en el array de
## índices de cada superficie y los vértices del piso, para anotarlo en CityIndex— o vacío si el módulo no
## tiene paredes.
func add_floor(module: BuildingModule, cells_per_floor: int, floor_idx: int, cell: Vector2i,
		bottom_cap: bool, top_cap: bool, debug_base: Color) -> Dictionary:
	var walls := module.get_walls()
	if walls.size() < 3:
		return {}
	var index_bottom := floor_idx * cells_per_floor
	var index_top := index_bottom + cells_per_floor
	var debug_color := _debug_shade(debug_base, floor_idx, cell)
	var walls_from := _w_indices.size()
	var caps_from := _c_indices.size()
	var w_vertex_from := _w_vertices.size()
	var c_vertex_from := _c_vertices.size()
	for wall in walls:
		_add_wall(module, wall, cells_per_floor, index_bottom, index_top, debug_color)
	if bottom_cap:
		_add_cap(module, walls, index_bottom, false, debug_color)
	if top_cap:
		_add_cap(module, walls, index_top, true, debug_color)
	var vertices := _w_vertices.slice(w_vertex_from)
	vertices.append_array(_c_vertices.slice(c_vertex_from))
	return {
		"walls": Vector2i(walls_from, _w_indices.size()),
		"caps": Vector2i(caps_from, _c_indices.size()),
		"vertices": vertices,
	}


func debug_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not _w_vertices.is_empty():
		var walls := []
		walls.resize(Mesh.ARRAY_MAX)
		walls[Mesh.ARRAY_VERTEX] = _w_vertices
		walls[Mesh.ARRAY_NORMAL] = _w_normals
		walls[Mesh.ARRAY_COLOR] = _w_colors
		walls[Mesh.ARRAY_TEX_UV] = _w_uv
		walls[Mesh.ARRAY_TEX_UV2] = _w_uv2
		walls[Mesh.ARRAY_CUSTOM0] = _w_height
		walls[Mesh.ARRAY_INDEX] = _w_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, walls, [], {},
			Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	if not _c_vertices.is_empty():
		var caps := []
		caps.resize(Mesh.ARRAY_MAX)
		caps[Mesh.ARRAY_VERTEX] = _c_vertices
		caps[Mesh.ARRAY_NORMAL] = _c_normals
		caps[Mesh.ARRAY_COLOR] = _c_colors
		caps[Mesh.ARRAY_TEX_UV] = _c_uv
		caps[Mesh.ARRAY_TEX_UV2] = _c_uv2
		caps[Mesh.ARRAY_CUSTOM0] = _c_custom0
		caps[Mesh.ARRAY_CUSTOM1] = _c_custom1
		caps[Mesh.ARRAY_CUSTOM2] = _c_custom2
		caps[Mesh.ARRAY_CUSTOM3] = _c_custom3
		caps[Mesh.ARRAY_INDEX] = _c_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, caps, [], {},
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT))
	return mesh


# ── Caras ────────────────────────────────────────────────────────────────────────────────────────

## Un piso sí y uno no más oscuro, y un módulo sí y uno no en damero: los dos sombreados que hacen legible
## la altura y el tamaño de los módulos en la vista debug.
static func _debug_shade(base: Color, floor_idx: int, cell: Vector2i) -> Color:
	var color := base
	if floor_idx % 2 == 1:
		color = color.darkened(1.0 - SHADE)
	if (cell.x + cell.y) % 2 == 1:
		color = color.darkened(1.0 - SHADE)
	return color


## Una pared: su quad, con las coordenadas de grilla de sus cuatro esquinas, y la misma cara a la piel.
func _add_wall(module: BuildingModule, wall: BuildingModule.Wall, cells_per_floor: int, index_bottom: int,
		index_top: int, debug_color: Color) -> void:
	var quad := module.get_wall_quad(wall, index_bottom, index_top)
	if quad.size() != 4:
		return
	# ⚠ CONVENCIÓN DEL PROYECTO: para el orden (a, b, c) la cara visible tiene normal (c - a) x (b - a). El
	# quad es [b0, b1, t1, t0]; con el orden (b0, t0, b1) la normal es (b1 - b0) x (t0 - b0), y si mira
	# hacia adentro se invierte el orden de los dos triángulos.
	var normal := (quad[1] - quad[0]).cross(quad[3] - quad[0])
	if normal.length_squared() <= 0.0:
		return
	normal = normal.normalized()
	var order: Array[int] = [0, 3, 1, 1, 3, 2]
	if normal.dot(module.get_wall_outward(wall)) < 0.0:
		normal = -normal
		order = [0, 1, 3, 1, 2, 3]
	skin.add_wall(quad, normal)

	var base := _w_vertices.size()
	for k in 4:
		_w_vertices.append(quad[k])
		_w_normals.append(normal)
		_w_colors.append(debug_color)
	for k in order:
		_w_indices.append(base + k)

	# Las coordenadas de grilla: el módulo (x, z) de cada extremo y la altura del piso; la matriz rígida
	# tiene la esquina (0, 0) en el inicio de abajo, `x` a lo largo y `z` hacia arriba (ver RigidMatrix).
	var ends := module.get_wall_cells(wall)
	var rigid := _rigid_of_wall(module, wall, cells_per_floor)
	_w_uv.append(ends[0])
	_w_uv.append(ends[1])
	_w_uv.append(ends[1])
	_w_uv.append(ends[0])
	_w_uv2.append(Vector2(0.0, 0.0))
	_w_uv2.append(Vector2(float(rigid.x), 0.0))
	_w_uv2.append(Vector2(float(rigid.x), float(rigid.y)))
	_w_uv2.append(Vector2(0.0, float(rigid.y)))
	_w_height.append(float(index_bottom))
	_w_height.append(float(index_bottom))
	_w_height.append(float(index_top))
	_w_height.append(float(index_top))


## Una tapa: el contorno que dejan las paredes a `height_index`, como abanico desde su centro, mirando al
## aire (`up`: arriba, si no abajo). El contorno en celdas va también a la piel.
func _add_cap(module: BuildingModule, walls: Array[BuildingModule.Wall], height_index: int, up: bool,
		debug_color: Color) -> void:
	var count := walls.size()
	var contour_cells := PackedVector2Array()
	var contour := PackedVector3Array()
	var centre_cells := Vector2.ZERO
	var centre := Vector3.ZERO
	for wall in walls:
		# El inicio de cada pared es el fin de la anterior: el contorno cierra solo.
		var c := module.get_wall_cells(wall)[0]
		var p := module.cell_to_world(Vector3(c.x, float(height_index), c.y))
		contour_cells.append(c)
		contour.append(p)
		centre_cells += c
		centre += p
	centre_cells /= float(count)
	centre /= float(count)
	skin.add_cap(module, contour_cells, height_index, up)

	# La normal del polígono (Newell): la tapa tiene silla, y una sola normal plana es lo que corresponde a
	# una cara que se dibuja plana.
	var air := Vector3.UP if up else Vector3.DOWN
	var normal := Vector3.ZERO
	for i in count:
		var a := contour[i]
		var b := contour[(i + 1) % count]
		normal += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	normal = normal.normalized()
	if normal.dot(air) < 0.0:
		normal = -normal

	var base := _c_vertices.size()
	_c_vertices.append(centre)
	_c_vertices.append_array(contour)
	for k in count + 1:
		_c_normals.append(normal)
		_c_colors.append(debug_color)
	for i in count:
		var b := 1 + i
		var c := 1 + (i + 1) % count
		# Misma convención que las paredes, triángulo por triángulo: (centro, P_i, P_i+1) mira al aire o se
		# da vuelta.
		if (contour[(i + 1) % count] - centre).cross(contour[i] - centre).dot(air) < 0.0:
			var swap := b
			b = c
			c = swap
		_c_indices.append(base)
		_c_indices.append(base + b)
		_c_indices.append(base + c)

	# Las coordenadas de grilla y lo que el shader necesita para corregirlas: la bilineal del núcleo en XZ a
	# esta altura, y cuánto valen (x, z) del módulo y de la azotea por unidad de sus parámetros (p, q).
	var core := module.get_core_info()
	var width := float(core["width"])
	var depth := float(core["depth"])
	var min_x := float(core["min_x"])
	var min_z := float(core["min_z"])
	var rigid := _rigid_of_roof(module, height_index)
	var quad := module.get_core_vertices(height_index)
	var c0 := quad[0]
	var e1 := quad[1] - c0
	var e3 := quad[3] - c0
	var e13 := c0 - quad[1] + quad[2] - quad[3]
	var points_cells := PackedVector2Array([centre_cells])
	points_cells.append_array(contour_cells)
	for cc in points_cells:
		var p := (cc.x - min_x) / width
		var q := (cc.y - min_z) / depth
		_c_uv.append(cc)
		_c_uv2.append(Vector2(p * float(rigid.x), q * float(rigid.y)))
		_c_custom0.append_array(PackedFloat32Array([float(height_index), 1.0, p, q]))
		_c_custom1.append_array(PackedFloat32Array([c0.x, c0.z, e1.x, e1.z]))
		_c_custom2.append_array(PackedFloat32Array([e3.x, e3.z, e13.x, e13.z]))
		_c_custom3.append_array(PackedFloat32Array([width, depth, float(rigid.x), float(rigid.y)]))


# ── Matrices rígidas ─────────────────────────────────────────────────────────────────────────────

func _rigid_of_wall(module: BuildingModule, wall: BuildingModule.Wall, cells_per_floor: int) -> Vector2i:
	var per_module: Dictionary = _rigid_counts.get_or_add(module, {})
	var slot := wall.slot()
	if not per_module.has(slot):
		var matrix := RigidMatrix.of_wall(module, wall, cells_per_floor)
		per_module[slot] = Vector2i(matrix.count.x, matrix.count.z)
	return per_module[slot]


func _rigid_of_roof(module: BuildingModule, height_index: int) -> Vector2i:
	var per_module: Dictionary = _rigid_counts.get_or_add(module, {})
	if not per_module.has(-1):
		var matrix := RigidMatrix.of_roof(module, height_index)
		per_module[-1] = Vector2i(matrix.count.x, matrix.count.z)
	return per_module[-1]
