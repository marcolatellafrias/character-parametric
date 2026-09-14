class_name TraversalGenerator extends RefCounted

var block: BlockGenerator

var delivery_doors: Array[Dictionary] = []
var stair_zones: Array[Dictionary] = []
var floating_sidewalk_zones: Array[Dictionary] = []


func _init(p_block: BlockGenerator) -> void:
	block = p_block


## Las medidas de una puerta, en metros. La puerta es RÍGIDA: estas medidas son la verdad, y en la matriz de
## la fachada ocupa las celdas que hagan falta para cubrirlas (ver City._visualize_delivery_doors). El ancho
## se convierte además a celdas de edificio, solo para decidir DÓNDE cae a lo largo de la cara.
const DOOR_WIDTH_M := 1.4
const DOOR_HEIGHT_M := 2.2
const DOOR_DEPTH_M := 0.15
## Cuánto puede subir una puerta para apoyarse sobre lo que haya delante de la fachada (la vereda). Más que
## eso no es un escalón sino un obstáculo, y la puerta no va.
const DOOR_MAX_STEP_M := 0.5


func generate(doors_per_block: int = 4) -> void:
	delivery_doors.clear()
	stair_zones.clear()
	floating_sidewalk_zones.clear()
	_generate_floor_sidewalks()
	_generate_ground_doors(doors_per_block)


## LAS PUERTAS DE PLANTA BAJA. Por ahora solo el piso 0, y acá solo el DATO —qué celda, qué lado, qué tramo
## de la cara—; la geometría la coloca City en la matriz rígida de esa fachada, encima de la pared, sin
## agujerear la malla del módulo (eso viene después, cuando los edificios tengan geometría real).
##
## Un borde sirve si da a la calle (FACADE) o a un callejón. NORMAL es interior —no da a ningún lado— y
## BOUNDARY es el límite de la ciudad.
func _generate_ground_doors(doors_per_block: int) -> void:
	if doors_per_block <= 0:
		return
	var grid = block.get_distorted_grid()
	if grid == null:
		return

	var candidates: Array[Dictionary] = []
	for z in range(grid.rows):
		for x in range(grid.columns):
			var cluster = block.get_cluster_for_cell(x, z)
			if cluster == null or cluster.floor_count <= 0:
				continue
			var module = block.get_building_module(x, z, 0)
			if module == null:
				continue
			for edge_idx in range(4):
				if not _edge_faces_outside(module, edge_idx):
					continue
				candidates.append({
					"cell": Vector2i(x, z), "edge": edge_idx, "cluster_id": cluster.id, "module": module
				})

	if candidates.is_empty():
		return

	# Del seed de la manzana, no de `randi()`: la ciudad tiene que salir idéntica en todos los peers.
	var rng := RandomNumberGenerator.new()
	rng.seed = block.cluster_seed + 4801
	var picked: Array[int] = []
	for i in candidates.size():
		picked.append(i)
	for i in range(picked.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := picked[i]
		picked[i] = picked[j]
		picked[j] = tmp

	var wanted: int = mini(doors_per_block, picked.size())
	for k in range(wanted):
		var candidate: Dictionary = candidates[picked[k]]
		var module: BuildingModule = candidate["module"]
		var span := _door_span(module, candidate["edge"], rng)
		if span.is_empty():
			continue
		delivery_doors.append({
			"cell": candidate["cell"],
			"edge": candidate["edge"],
			"floor": 0,
			"cluster_id": candidate["cluster_id"],
			"along_min": span["along_min"],
			"along_max": span["along_max"],
		})


## Si ese borde del módulo mira a la calle o a un callejón. NORMAL queda adentro de la manzana y
## BOUNDARY es el borde del mundo: en ninguno de los dos tiene sentido una puerta.
func _edge_faces_outside(module: BuildingModule, edge_idx: int) -> bool:
	var sides := ["north", "east", "south", "west"]
	var edge_type: int = module.get_edge_type(sides[edge_idx])
	if edge_type == DistortedGrid.CellType.NORMAL or edge_type == DistortedGrid.CellType.BOUNDARY:
		return false
	return true


## Dónde cae la puerta a lo largo de esa cara, en celdas de edificio. Se sortea sobre la CARA REAL —el
## tramo con pared, sin las esquinas ochavadas (`BuildingModule.get_facade_span`)— y no sobre el núcleo
## entero. El tamaño de celda se mide del módulo mismo —dos posiciones vecinas— en vez de darlo por fijo.
func _door_span(module: BuildingModule, edge_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var core = module.get_core_info()
	var span := module.get_facade_span(edge_idx)
	# `span` va en el sentido del recorrido y cubre celdas [from, to); acá se quieren índices inclusivos.
	var along_from: int = ceili(minf(span.x, span.y))
	var along_to: int = floori(maxf(span.x, span.y)) - 1
	if along_to < along_from:
		return {}

	var origin := module.get_cell_position(core["min_x"], core["min_z"], 0)
	var next_along: Vector3
	if edge_idx == 0 or edge_idx == 2:
		next_along = module.get_cell_position(core["min_x"] + 1, core["min_z"], 0)
	else:
		next_along = module.get_cell_position(core["min_x"], core["min_z"] + 1, 0)
	var cell_size: float = origin.distance_to(next_along)
	if cell_size <= 0.0:
		return {}

	var width_cells: int = maxi(1, int(round(DOOR_WIDTH_M / cell_size)))
	var available: int = along_to - along_from + 1
	if width_cells > available:
		width_cells = available
	var start: int = along_from + rng.randi_range(0, available - width_cells)
	return {
		"along_min": start,
		"along_max": start + width_cells - 1,
	}


## Si ese lado del módulo da a la calle. Solo ahí hay cordón: un callejón es vereda de lado a lado.
static func _is_street(module: BuildingModule, edge_idx: int) -> bool:
	var sides := ["north", "east", "south", "west"]
	return module.get_edge_type(sides[edge_idx]) == DistortedGrid.CellType.FACADE


## LAS VEREDAS DEL PISO 0, MÓDULO POR MÓDULO. Todo lo que no es edificio a nivel de suelo es vereda: cada
## módulo pavimenta SU RETIRO ENTERO —hacia la calle hasta el cordón, hacia un callejón hasta el medio, así
## los dos módulos que lo flanquean lo cubren completo: los callejones son vereda pura—. Se parte en una
## TIRA por lado con retiro y una ESQUINA en cada vértice cuyos dos lados tienen retiro; la tira se acorta
## donde hay esquina y llega hasta el borde del módulo donde no la hay, así contra un vecino adosado las
## tiras de los dos módulos se continúan. No hay piezas "de manzana".
##
## La esquina es CURVA solo donde los dos lados son calle —ahí hay cordón que dobla—. En la boca de un
## callejón sobre la calle el cordón sigue recto y el pavimento del callejón llega a ras, y en un cruce de
## callejones todo es losa: esas esquinas son cuadradas.
##
## Dos casos más completan el suelo: el CORAZÓN DE MANZANA, sin edificio, es una plaza —la celda entera—, y
## el chaflán le quita al edificio un triángulo de núcleo que se rellena para que la vereda llegue a la pared
## ochavada (ver SidewalkProps).
func _generate_floor_sidewalks() -> void:
	var grid = block.get_distorted_grid()
	if grid == null:
		return
	for z in range(grid.rows):
		for x in range(grid.columns):
			var cell := Vector2i(x, z)
			var cluster = block.get_cluster_for_cell(x, z)
			var module: BuildingModule = block.get_building_module(x, z, 0)
			if cluster == null or module == null:
				continue
			var cols: int = module.columns
			var rows: int = module.rows
			if cluster.floor_count <= 0:
				_add_sidewalk_zone(cell, cluster.id, SidewalkProps.Piece.PLAZA, -1,
						Vector4i(0, cols - 1, 0, rows - 1))
				continue

			var core := module.get_core_info()
			# El retiro de cada lado (norte, este, sur, oeste), en celdas: cero contra un vecino adosado o
			# contra el límite del mundo.
			var w: Array[int] = [int(core["min_z"]), cols - 1 - int(core["max_x"]),
					rows - 1 - int(core["max_z"]), int(core["min_x"])]
			# Hasta dónde llega una tira a lo largo de su lado: al núcleo si el lado vecino tiene retiro (ahí
			# va la esquina), al borde del módulo si no.
			var x_from: int = core["min_x"] if w[3] > 0 else 0
			var x_to: int = core["max_x"] if w[1] > 0 else cols - 1
			var z_from: int = core["min_z"] if w[0] > 0 else 0
			var z_to: int = core["max_z"] if w[2] > 0 else rows - 1
			# El espesor de cada tira, del borde del módulo al núcleo: [min, max] en profundidad, por lado.
			var depth := [
				Vector2i(0, core["min_z"] - 1),
				Vector2i(core["max_x"] + 1, cols - 1),
				Vector2i(core["max_z"] + 1, rows - 1),
				Vector2i(0, core["min_x"] - 1),
			]
			var strips := [
				Vector4i(x_from, x_to, depth[0].x, depth[0].y),
				Vector4i(depth[1].x, depth[1].y, z_from, z_to),
				Vector4i(x_from, x_to, depth[2].x, depth[2].y),
				Vector4i(depth[3].x, depth[3].y, z_from, z_to),
			]
			for edge_idx in 4:
				if w[edge_idx] > 0:
					_add_sidewalk_zone(cell, cluster.id, SidewalkProps.Piece.STRIP, edge_idx, strips[edge_idx])

			# Esquinas, numeradas como los cuartos de vuelta de UnitMesh.rotated: 0 NO, 1 NE, 2 SE, 3 SO.
			# Cada una es el retiro de su lado en x por el retiro de su lado en z.
			var corner_sides := [Vector2i(3, 0), Vector2i(1, 0), Vector2i(1, 2), Vector2i(3, 2)]
			for k in 4:
				var sides: Vector2i = corner_sides[k]
				if w[sides.x] <= 0 or w[sides.y] <= 0:
					continue
				var curved := _is_street(module, sides.x) and _is_street(module, sides.y)
				var piece: int = SidewalkProps.Piece.CURVED_CORNER if curved else SidewalkProps.Piece.CORNER
				var along_x: Vector2i = depth[sides.x]
				var along_z: Vector2i = depth[sides.y]
				_add_sidewalk_zone(cell, cluster.id, piece, k,
						Vector4i(along_x.x, along_x.y, along_z.x, along_z.y))

			# Rellenos de ochava: el cuadrado del chaflán en cada esquina del núcleo, mismo índice de vértice
			# que `chamfers` (0 NO, 1 NE, 2 SE, 3 SO). `c1` va sobre la arista anterior y `c2` sobre la
			# siguiente, como en el constructor de la pared (DebugUtil._grid_chamfers_to_metres).
			var chamfers: Dictionary = module.get_chamfers()
			for k in 4:
				if not chamfers.has(k):
					continue
				var cut: Array = chamfers[k]
				var c1 := int(cut[0])
				var c2 := int(cut[1])
				if c1 <= 0 or c2 <= 0:
					continue
				var rect: Vector4i
				match k:
					0: rect = Vector4i(core["min_x"], core["min_x"] + c2 - 1, core["min_z"], core["min_z"] + c1 - 1)
					1: rect = Vector4i(core["max_x"] - c1 + 1, core["max_x"], core["min_z"], core["min_z"] + c2 - 1)
					2: rect = Vector4i(core["max_x"] - c2 + 1, core["max_x"], core["max_z"] - c1 + 1, core["max_z"])
					_: rect = Vector4i(core["min_x"], core["min_x"] + c1 - 1, core["max_z"] - c2 + 1, core["max_z"])
				_add_sidewalk_zone(cell, cluster.id, SidewalkProps.Piece.CHAMFER, k, rect)


## Una zona de vereda: qué `piece` va (SidewalkProps.Piece) y su `side` —el lado de una tira, la esquina de
## una esquina o de un relleno, -1 en una plaza—. `rect` es (bx_min, bx_max, bz_min, bz_max), inclusivo.
func _add_sidewalk_zone(cell: Vector2i, cluster_id: int, piece: int, side: int, rect: Vector4i) -> void:
	if rect.x > rect.y or rect.z > rect.w:
		return
	floating_sidewalk_zones.append({
		"cell": cell, "piece": piece, "side": side, "floor": 0, "cluster_id": cluster_id,
		"bx_min": rect.x, "bx_max": rect.y, "bz_min": rect.z, "bz_max": rect.w,
	})
