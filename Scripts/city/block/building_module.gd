class_name BuildingModule extends PlacementGrid

## EL MÓDULO ES LA GRILLA DEFORMABLE: una PlacementGrid cuyo cuadrilátero es la celda de la grilla
## distorsionada con su relieve, `axis_n` arriba y 80 × 80 celdas sin techo de altura. Todo lo que se coloca
## en él —techos, veredas, extremos de puente— se dobla con sus celdas (ver PlacementGrid, GridPlacer).

# Vértices del quad completo [BL, BR, TR, TL]. Son las `corners` de la grilla.
var vertices: Array[Vector3]

# Tipos de edges [north, east, south, west]
var edge_types: Array[int]

# Geometría de la grilla del building
var rows: int
var columns: int
var cell_height: float

# Offsets de alleyways (número de celdas por tipo de edge)
var alleyway_offsets: Dictionary

# Área core del building (después de offsets)
var core_min_x: int
var core_max_x: int
var core_min_z: int
var core_max_z: int

# Chamfers de las esquinas: {vertex_index: [c1, c2]}
# donde c1 y c2 son el número de celdas chamfereadas
var chamfers: Dictionary = {}

## DE QUÉ es esquina cada chaflán: {vertex_index: ChamferKind}.
##
## Geométricamente los dos son iguales, pero significan cosas distintas: el de CALLE es la esquina noble de
## la manzana —la que se ochava y lleva el techo francés— y el de CALLEJÓN es una forma rara de fondo. El
## techo decide con esto (ver RoofPlanner), así que el tipo se guarda en vez de perderse.
enum ChamferKind { STREET, ALLEY }
var chamfer_kinds: Dictionary = {}

# ── EL RELIEVE ──────────────────────────────────────────────────────────────────────────────────
# Todas las alturas del módulo salen de acá (ver `point_at_f`), y por acá pasa TODO lo que se sitúa en la
# ciudad: las veredas, las puertas, las escaleras, los extremos de puente y los conectores.
#
# La altura sale de las CUATRO ESQUINAS DEL PROPIO MÓDULO (`vertices`, que ya vienen con su Y de la celda
# de grilla), interpolada con la misma bilineal que da el XZ. No hay consulta a ningún campo global: el
# relieve viaja con la geometría, así que dos piezas vecinas que comparten esquinas coinciden exactas y
# nada puede clipear contra el suelo (ver CityTerrain).
#
# ⚠ EL PISO N ES EL PISO 0 SUBIDO EN Y, y nada más: el mismo quad inclinado del terreno, trasladado. Los
# pisos son PARALELOS entre sí y están TODOS inclinados por igual. No es un detalle interno: es la
# definición que usa la malla que se ve —`City._visualize_buildings` arma cada piso con
# `get_core_vertices(0)` más el desplazamiento del piso, y extruye en vertical—, así que la colocación
# tiene que decir exactamente lo mismo o los objetos quedan flotando sobre una superficie que no existe.
#
# SUPERSEDED — el taper: había un `ground_reference` (la altura promedio del cluster) hacia el cual el
# módulo se enderezaba a lo largo de los primeros 2 pisos, para dejar los techos horizontales. Nunca
# llegó a la geometría, porque la malla no pasa por acá: solo movía la grilla de COLOCACIÓN, que del
# piso 2 para arriba devolvía un plano HORIZONTAL mientras el edificio visible seguía inclinado. Todo lo
# apoyado en una fachada quedaba corrido por `bilinear(u,v) - ground_reference` —hasta ~1,35 m— y con la
# inclinación equivocada. Si algún día se quieren techos horizontales, hay que hacerlo en la MALLA y en
# la colocación a la vez, nunca en una sola.

func _init(
	p_vertices: Array[Vector3],
	p_edge_types: Array[int],
	p_rows: int,
	p_columns: int,
	p_cell_height: float,
	p_alleyway_offsets: Dictionary,
	p_distorted_grid: DistortedGrid = null,
	p_grid_x: int = -1,
	p_grid_z: int = -1,
	p_path_generator: PathGenerator = null,
	p_archetype: BuildingArchetype = null
) -> void:
	vertices = p_vertices
	edge_types = p_edge_types
	rows = p_rows
	columns = p_columns
	cell_height = p_cell_height
	alleyway_offsets = p_alleyway_offsets
	_setup(vertices, Vector3.UP, cell_height, Vector3i(columns, UNBOUNDED, rows))

	_calculate_core_area()
	
	if p_distorted_grid and p_grid_x >= 0 and p_grid_z >= 0 and p_path_generator:
		_calculate_chamfers(p_distorted_grid, p_grid_x, p_grid_z, p_path_generator, p_archetype)


func _calculate_core_area() -> void:
	var north_offset = alleyway_offsets.get(edge_types[0], 0)
	var east_offset = alleyway_offsets.get(edge_types[1], 0)
	var south_offset = alleyway_offsets.get(edge_types[2], 0)
	var west_offset = alleyway_offsets.get(edge_types[3], 0)
	
	core_min_x = west_offset
	core_max_x = columns - east_offset - 1
	core_min_z = north_offset
	core_max_z = rows - south_offset - 1


func _calculate_chamfers(
	distorted_grid: DistortedGrid,
	grid_x: int,
	grid_z: int,
	path_generator: PathGenerator,
	archetype: BuildingArchetype = null
) -> void:
	for vertex_index in range(4):
		var info = distorted_grid.get_vertex_edges_info(grid_x, grid_z, vertex_index)
		var vertex_grid_pos: Vector2i = info["vertex"]
		
		# Verificar si es esquina de calle (street corner)
		if distorted_grid.is_street_corner_vertex(vertex_grid_pos.x, vertex_grid_pos.y):
			if archetype != null:
				# Seed único por vértice basado en posición
				var vertex_seed = hash(Vector2i(grid_x * 1000 + vertex_index, grid_z))
				var chamfer_value = archetype.get_street_corner_chamfer_value(vertex_seed)
				
				if chamfer_value > 0:
					chamfers[vertex_index] = [chamfer_value, chamfer_value]
					chamfer_kinds[vertex_index] = ChamferKind.STREET
					continue  # Ya procesamos este vértice como street corner
		
		# Verificar si es esquina de callejón (alleyway corner)
		if not distorted_grid.is_alleyway_corner_vertex(vertex_grid_pos.x, vertex_grid_pos.y):
			continue
		
		var corner_edges_valid = true
		for corner_edge in info["corner_edges"]:
			var edge_type = _get_edge_type_from_vertices(
				corner_edge["v1"], corner_edge["v2"], path_generator
			)
			if edge_type != DistortedGrid.CellType.NORMAL and edge_type != DistortedGrid.CellType.FACADE and edge_type != DistortedGrid.CellType.BOUNDARY:
				corner_edges_valid = false
				break
		
		if not corner_edges_valid:
			continue
		
		var secondary_edge_data: Array = []
		var all_secondary_valid = true
		
		for secondary_edge in info["secondary_edges"]:
			var edge_type = _get_edge_type_from_vertices(
				secondary_edge["v1"], secondary_edge["v2"], path_generator
			)
			if edge_type == DistortedGrid.CellType.NORMAL or edge_type == DistortedGrid.CellType.FACADE or edge_type == DistortedGrid.CellType.BOUNDARY:
				all_secondary_valid = false
				break
			
			var offset = alleyway_offsets.get(edge_type, 0)
			
			secondary_edge_data.append({
				"edge": secondary_edge,
				"offset": offset
			})
		
		if not all_secondary_valid or secondary_edge_data.size() != 2:
			continue
		
		var chamfer_values = _determine_chamfer_values(
			vertex_index, vertex_grid_pos, secondary_edge_data
		)
		
		if chamfer_values.size() == 2:
			chamfers[vertex_index] = chamfer_values
			chamfer_kinds[vertex_index] = ChamferKind.ALLEY


func _get_edge_type_from_vertices(
	v1: Vector2i,
	v2: Vector2i,
	path_generator: PathGenerator
) -> int:
	return path_generator.get_path_edge_type_vertices(v1.x, v1.y, v2.x, v2.y)


func _determine_chamfer_values(
	vertex_index: int,
	vertex_pos: Vector2i,
	secondary_edge_data: Array
) -> Array:
	# Mapeo de vértice index a las direcciones de c1 y c2
	# c1: hacia el edge que conecta con el vértice anterior (clockwise)
	# c2: hacia el edge que conecta con el vértice siguiente (clockwise)
	
	# Direcciones para cada vértice:
	# V0 (BL): c1 hacia west (-x o +z según la orientación), c2 hacia north (+x)
	# V1 (BR): c1 hacia north (+x o -x), c2 hacia east (+z)
	# V2 (TR): c1 hacia east (+z o -z), c2 hacia south (-x o +x)
	# V3 (TL): c1 hacia south (-x o +x), c2 hacia west (-z o +z)
	
	var c1_offset = 0
	var c2_offset = 0
	
	# Identificar qué edge secundario corresponde a cada dirección
	for edge_data in secondary_edge_data:
		var edge = edge_data["edge"]
		var offset = edge_data["offset"]
		var v1: Vector2i = edge["v1"]
		var v2: Vector2i = edge["v2"]
		var other_v = v2 if v1 == vertex_pos else v1
		var direction = other_v - vertex_pos
		
		# Determinar si este edge corresponde a c1 o c2 según el vértice
		match vertex_index:
			0:  # BL
				if direction.y > 0:  # Hacia +z (west en términos de la celda, hacia TL)
					c1_offset = offset
				elif direction.x > 0:  # Hacia +x (north, hacia BR)
					c2_offset = offset
				elif direction.y < 0:  # Hacia -z (norte absoluto)
					c2_offset = offset
				elif direction.x < 0:  # Hacia -x (oeste absoluto)
					c1_offset = offset
			1:  # BR
				if direction.x < 0:  # Hacia -x (north, hacia BL)
					c1_offset = offset
				elif direction.y > 0:  # Hacia +z (east, hacia TR)
					c2_offset = offset
				elif direction.x > 0:  # Hacia +x (este absoluto)
					c2_offset = offset
				elif direction.y < 0:  # Hacia -z (norte absoluto)
					c1_offset = offset
			2:  # TR
				if direction.y < 0:  # Hacia -z (east, hacia BR)
					c1_offset = offset
				elif direction.x < 0:  # Hacia -x (south, hacia TL)
					c2_offset = offset
				elif direction.y > 0:  # Hacia +z (sur absoluto)
					c2_offset = offset
				elif direction.x > 0:  # Hacia +x (este absoluto)
					c1_offset = offset
			3:  # TL
				if direction.x > 0:  # Hacia +x (south, hacia TR)
					c1_offset = offset
				elif direction.y < 0:  # Hacia -z (west, hacia BL)
					c2_offset = offset
				elif direction.x < 0:  # Hacia -x (oeste absoluto)
					c2_offset = offset
				elif direction.y > 0:  # Hacia +z (sur absoluto)
					c1_offset = offset
	
	if c1_offset > 0 and c2_offset > 0:
		return [c1_offset, c2_offset]
	return []


func get_vertex(index: int) -> Vector3:
	if index < 0 or index >= vertices.size():
		return Vector3.ZERO
	return vertices[index]


func get_edge_type(side: String) -> int:
	match side:
		"north":
			return edge_types[0]
		"east":
			return edge_types[1]
		"south":
			return edge_types[2]
		"west":
			return edge_types[3]
		_:
			return 0


func get_cell_position(grid_x: int, grid_z: int, local_floor: int = 0) -> Vector3:
	var u = (float(grid_x) + 0.5) / max(1, columns)
	var v = (float(grid_z) + 0.5) / max(1, rows)
	
	return _at_height(u, v, local_floor)


func get_cell_vertices(grid_x: int, grid_z: int, local_floor: int = 0) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	var u_min = float(grid_x) / max(1, columns)
	var u_max = float(grid_x + 1) / max(1, columns)
	var v_min = float(grid_z) / max(1, rows)
	var v_max = float(grid_z + 1) / max(1, rows)
	
	# Bottom-Left
	result.append(_at_height(u_min, v_min, local_floor))
	
	# Bottom-Right
	result.append(_at_height(u_max, v_min, local_floor))
	
	# Top-Right
	result.append(_at_height(u_max, v_max, local_floor))
	
	# Top-Left
	result.append(_at_height(u_min, v_max, local_floor))
	
	return result


func get_core_vertices(local_floor: int = 0) -> Array[Vector3]:
	var result: Array[Vector3] = []
	
	var u_min = float(core_min_x) / max(1, columns)
	var u_max = float(core_max_x + 1) / max(1, columns)
	var v_min = float(core_min_z) / max(1, rows)
	var v_max = float(core_max_z + 1) / max(1, rows)
	
	# Bottom-Left
	result.append(_at_height(u_min, v_min, local_floor))
	
	# Bottom-Right
	result.append(_at_height(u_max, v_min, local_floor))
	
	# Top-Right
	result.append(_at_height(u_max, v_max, local_floor))
	
	# Top-Left
	result.append(_at_height(u_min, v_max, local_floor))
	
	return result


func is_cell_in_core(grid_x: int, grid_z: int) -> bool:
	return (grid_x >= core_min_x and grid_x <= core_max_x and
			grid_z >= core_min_z and grid_z <= core_max_z)


func is_cell_alleyway(grid_x: int, grid_z: int) -> bool:
	return not is_cell_in_core(grid_x, grid_z)


func get_region_vertices(bx_min: int, bx_max: int, bz_min: int, bz_max: int, height_index: int = 0) -> Array[Vector3]:
	var result: Array[Vector3] = []

	var u_min = float(bx_min) / max(1, columns)
	var u_max = float(bx_max + 1) / max(1, columns)
	var v_min = float(bz_min) / max(1, rows)
	var v_max = float(bz_max + 1) / max(1, rows)

	result.append(_at_height(u_min, v_min, height_index))
	result.append(_at_height(u_max, v_min, height_index))
	result.append(_at_height(u_max, v_max, height_index))
	result.append(_at_height(u_min, v_max, height_index))

	return result


func get_core_info() -> Dictionary:
	return {
		"min_x": core_min_x,
		"max_x": core_max_x,
		"min_z": core_min_z,
		"max_z": core_max_z,
		"width": core_max_x - core_min_x + 1,
		"depth": core_max_z - core_min_z + 1
	}


func get_chamfers() -> Dictionary:
	return chamfers


## De qué es esquina cada chaflán: {vertex_index: ChamferKind}. Solo trae los vértices que tienen chaflán.
func get_chamfer_kinds() -> Dictionary:
	return chamfer_kinds


## Un punto del módulo en (u, v) y a `height_index` celdas de alto, ya apoyado en el relieve (ver EL
## RELIEVE). El XZ y la altura salen de la MISMA interpolación sobre las mismas cuatro esquinas.
##
## La altura es el relieve MÁS un desplazamiento vertical puro, que es exactamente como la malla arma
## cada piso. Por eso lo que se coloque acá cae sobre la cara que se ve, en cualquier piso.
func _at_height(u: float, v: float, height_index: int) -> Vector3:
	return point_at(u, v, height_index)


## Un punto de la CELDA ENTERA —`u` y `v` de 0 a 1 sobre su cuadrilátero, no sobre el núcleo— a
## `height_index` celdas de alto. Es la vía para colocar geometría libre dentro del módulo: se arma en
## coordenadas normalizadas y sale deformada con la grilla e inclinada con el terreno, igual que los techos.
func point_at(u: float, v: float, height_index: int) -> Vector3:
	return point_at_f(u, v, float(height_index))


## Lo mismo con la altura en celdas FRACCIONARIA: lo que necesita una mesh deformada dentro de una región,
## cuyos vértices caen entre dos índices. Es `cell_to_world` con (u, v) normalizados: la bilineal de las
## cuatro esquinas 3D del módulo —el XZ de la grilla y el Y del relieve salen de la misma cuenta— más el
## desplazamiento vertical del índice.
func point_at_f(u: float, v: float, height_cells: float) -> Vector3:
	return cell_to_world(Vector3(u * float(columns), height_cells, v * float(rows)))


# ── PAREDES ─────────────────────────────────────────────────────────────────────────────────────
# Una PARED es una cara vertical del núcleo en un piso: la superficie donde viven los objetos rígidos de
# pared (puertas, ventanas, balcones; ver RigidMatrix) y lo que la malla del edificio dibuja (ver
# BuildingShell). Hay de dos clases, y LAS DOS PASAN POR LAS MISMAS FUNCIONES: quien las recorre no puede
# tratar distinto a una que a otra sin pedirlo (`Wall.kind`).
#   · FACHADA: la cara del núcleo sobre un lado del módulo. Los lados son 0 norte (z mínima), 1 este, 2 sur,
#     3 oeste, y cada uno se recorre de la esquina `e` a la `e + 1` del núcleo, en el orden [BL, BR, TR, TL]
#     de `get_core_vertices`. Un chaflán la acorta: la esquina ochavada no tiene pared de fachada.
#   · CHAFLÁN: la diagonal de una esquina ochavada, del final de la fachada anterior al principio de la
#     siguiente. NO TIENE GEOMETRÍA PROPIA: sus extremos son los de las dos fachadas (`get_facade_span`),
#     así que entre una y otra no puede quedar ni un hueco ni un solape, y lo que se coloque sobre él está
#     exactamente donde termina la pared de al lado. Existe si sus dos extremos no coinciden, y nada más.
# En orden de recorrido del contorno van chaflán 0, fachada 0, chaflán 1, fachada 1, ... (`get_walls`).

enum WallKind { FACADE, CHAMFER }

## Una pared: de qué clase y cuál. `index` es la arista (FACADE) o el vértice (CHAMFER).
class Wall:
	var kind: int
	var index: int

	func _init(p_kind: int, p_index: int) -> void:
		kind = p_kind
		index = p_index

	static func facade(edge_idx: int) -> Wall:
		return Wall.new(WallKind.FACADE, edge_idx)

	static func chamfer(vertex_idx: int) -> Wall:
		return Wall.new(WallKind.CHAMFER, vertex_idx)

	## Su lugar en el recorrido del contorno, 0..7: chaflán 0, fachada 0, chaflán 1, ... Sirve de clave.
	func slot() -> int:
		return index * 2 + (1 if kind == WallKind.FACADE else 0)


## Punto sobre la arista `edge_idx` del núcleo a `along` celdas de edificio (en x para norte y sur, en z
## para este y oeste), en celdas del módulo (x, z).
func _edge_cells(edge_idx: int, along: float) -> Vector2:
	match edge_idx:
		0: return Vector2(along, float(core_min_z))
		1: return Vector2(float(core_max_x + 1), along)
		2: return Vector2(along, float(core_max_z + 1))
		_: return Vector2(float(core_min_x), along)


## Lo mismo en (u, v) normalizados del módulo.
func _edge_uv(edge_idx: int, along: float) -> Vector2:
	return _edge_cells(edge_idx, along) / Vector2(float(maxi(columns, 1)), float(maxi(rows, 1)))


## De dónde a dónde va la cara `edge_idx`, en celdas de edificio y en el sentido del recorrido (los lados 2
## y 3 van decreciendo). Descuenta los chaflanes de las dos esquinas: `c2` de la esquina de arranque y `c1`
## de la de llegada, que son los tramos de cada una sobre esta arista (ver `chamfers`). Es la ÚNICA
## definición de "dónde hay pared" en ese lado: de acá salen la fachada, el chaflán que la sigue y quien
## sortea posiciones sobre ella (ver TraversalGenerator._door_span), así una puerta no puede caer en la ochava.
func get_facade_span(edge_idx: int) -> Vector2:
	var at_start: Array = chamfers.get(edge_idx, [0, 0])
	var at_end: Array = chamfers.get((edge_idx + 1) % 4, [0, 0])
	var cut_start := float(at_start[1])
	var cut_end := float(at_end[0])
	match edge_idx:
		0: return Vector2(float(core_min_x) + cut_start, float(core_max_x + 1) - cut_end)
		1: return Vector2(float(core_min_z) + cut_start, float(core_max_z + 1) - cut_end)
		2: return Vector2(float(core_max_x + 1) - cut_start, float(core_min_x) + cut_end)
		_: return Vector2(float(core_max_z + 1) - cut_start, float(core_min_z) + cut_end)


## LOS DOS EXTREMOS DE UNA PARED, `[inicio, fin]` en celdas del módulo (x, z), en el sentido del recorrido.
## Una fachada va de punta a punta de su tramo con pared; un chaflán, del fin de la fachada anterior al
## inicio de la siguiente. Es la única fuente de la geometría de las paredes: el quad, la tapa que las
## cierra y las coordenadas de grilla que lleva cada vértice salen todos de acá.
func get_wall_cells(wall: Wall) -> PackedVector2Array:
	if wall.kind == WallKind.FACADE:
		var span := get_facade_span(wall.index)
		return PackedVector2Array([_edge_cells(wall.index, span.x), _edge_cells(wall.index, span.y)])
	var prev := (wall.index + 3) % 4
	return PackedVector2Array([
		_edge_cells(prev, get_facade_span(prev).y),
		_edge_cells(wall.index, get_facade_span(wall.index).x),
	])


## Las paredes que el núcleo tiene, en orden de recorrido. Sin casos especiales: una pared existe si sus
## dos extremos no coinciden, sea el chaflán de una esquina sin ochava (sus extremos son la misma esquina)
## o una fachada que el chaflán se comió entera.
func get_walls() -> Array[Wall]:
	var out: Array[Wall] = []
	for i in 4:
		for wall: Wall in [Wall.chamfer(i), Wall.facade(i)]:
			var ends := get_wall_cells(wall)
			if not ends[0].is_equal_approx(ends[1]):
				out.append(wall)
	return out


## EL QUAD DE UNA PARED entre dos índices de altura: `[inicio_abajo, fin_abajo, fin_arriba, inicio_arriba]`.
## Vacío si la pared no existe.
##
## Va de abajo hacia arriba en su segundo eje: la grilla que se arme sobre él (`RigidMatrix.of_wall`) tiene
## la fila 0 en el piso. En qué sentido se recorre el borde de abajo no importa: la grilla puede espejar `x`
## y las piezas se orientan en el mundo. Es un PARALELOGRAMO exacto —el borde de arriba es el de abajo
## subido—, y de eso depende que las coordenadas de grilla se interpolen exactas sobre él (ver BuildingShell).
func get_wall_quad(wall: Wall, index_bottom: int, index_top: int) -> Array[Vector3]:
	var ends := get_wall_cells(wall)
	if ends[0].is_equal_approx(ends[1]):
		return []
	return [
		cell_to_world(Vector3(ends[0].x, float(index_bottom), ends[0].y)),
		cell_to_world(Vector3(ends[1].x, float(index_bottom), ends[1].y)),
		cell_to_world(Vector3(ends[1].x, float(index_top), ends[1].y)),
		cell_to_world(Vector3(ends[0].x, float(index_top), ends[0].y)),
	]


## Hacia dónde mira una pared: del centro del núcleo al medio de la pared, en el plano horizontal. Vale
## igual para el chaflán de un callejón, que aunque sea el fondo de una muesca en la manzana sigue siendo
## una esquina cortada del rectángulo del núcleo.
func get_wall_outward(wall: Wall) -> Vector3:
	var centre := cell_to_world(Vector3(float(core_min_x + core_max_x + 1) * 0.5, 0.0,
		float(core_min_z + core_max_z + 1) * 0.5))
	var ends := get_wall_cells(wall)
	var mid := (ends[0] + ends[1]) * 0.5
	var out := cell_to_world(Vector3(mid.x, 0.0, mid.y)) - centre
	out.y = 0.0
	return out.normalized()


## Un punto de la arista `edge_idx` del núcleo a `along` celdas de edificio y `height_index` de alto: dónde
## cae, en el mundo, una posición dada sobre la fachada en celdas del módulo.
func facade_point(edge_idx: int, along: int, height_index: int) -> Vector3:
	var uv := _edge_uv(edge_idx, float(along))
	return point_at_f(uv.x, uv.y, float(height_index))




