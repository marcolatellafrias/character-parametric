# BuildingGridHelper.gd
# ============================================================
# Genera y almacena matrices 3D volumétricas para cada celda
# de la DistortedGrid de un BlockGenerator.
#
# CONTEXTO DEL SISTEMA:
# - BlockGenerator: representa una manzana urbana. Contiene una
#   DistortedGrid (grilla irregular 2D) subdividida en clusters.
# - BuildingCluster: grupo de celdas de la DistortedGrid que
#   comparten un edificio. Tiene floor_count (pisos).
# - BuildingModule: representa una celda de la DistortedGrid en
#   un piso concreto. Expone la building grid interna (bx, bz)
#   y los offsets de alleyways y chamfers.
#
# ESTRUCTURA DE LA MATRIZ 3D:
# Cada celda de la DistortedGrid genera una matriz de celdas
# volumétricas de dimensiones:
#   columns x rows x (floor_count * cells_per_floor)
# donde columns/rows son la building grid interna del módulo.
#
# Las celdas se indexan como (bx, bz, by):
#   bx: columna de la building grid  [0, columns)
#   bz: fila de la building grid     [0, rows)
#   by: índice de altura global      [0, floor_count * cells_per_floor)
#
# AVAILABILITY:
# Cada celda tiene una bool `availability` que indica si está
# disponible para colocar contenido (ventanas, props, etc.).
# Se marca como unavailable si:
#   1. Está fuera del core del BuildingModule (zona de alleyway)
#   2. Está dentro de un rectángulo de chamfer de esquina
# Vértices, edges y faces NO almacenan availability; se computan
# lazy a partir de las celdas vecinas mediante métodos auxiliares.
#
# COORDENADAS DE VÉRTICES/EDGES/FACES:
# Los vértices van de (0,0,0) a (columns, height_cells, rows).
# Edges tienen un eje ("x"|"y"|"z") y el vértice origen.
# Faces tienen una normal ("x"|"y"|"z") y tres coordenadas
# donde una es de vértice (frontera) y dos son de celda.
# ============================================================
class_name BuildingGridHelper extends RefCounted

# Diccionario de matrices 3D indexado por coord de DistortedGrid.
# Key: "x_z" (coord de celda en la DistortedGrid)
# Value: Dictionary con estructura descrita en get_3d_matrix()
var matrices: Dictionary = {}


# Construye las matrices de todas las celdas de la DistortedGrid.
func _init(block_generator: BlockGenerator) -> void:
	var grid = block_generator.get_distorted_grid()
	for z in range(grid.rows):
		for x in range(grid.columns):
			var matrix = BuildingGridHelper.get_3d_matrix(block_generator, Vector2i(x, z))
			if not matrix.is_empty():
				matrices["%d_%d" % [x, z]] = matrix


# ============================================================
# GENERACIÓN ESTÁTICA DE MATRIZ 3D
# ============================================================

# Genera la matriz 3D volumétrica para una celda (coord) de la DistortedGrid.
# Devuelve {} si la celda no pertenece a ningún cluster.
#
# Estructura del diccionario devuelto:
# {
#   "columns": int,          # building grid columns (eje X)
#   "rows": int,             # building grid rows (eje Z)
#   "height_cells": int,     # total celdas en altura ((floor_count + 1) * cells_per_floor)
#   "floor_count": int,      # número de pisos del cluster (sin contar rooftop)
#   "cells_per_floor": int,  # celdas de building grid por piso
#   "cell_height": float,    # altura en unidades de mundo de cada celda
#   "cells": {
#     "bx_bz_by": {
#       "position": Vector3,   # centro de la celda en world space
#       "bx": int,
#       "bz": int,
#       "height_index": int,   # índice global de altura (by)
#       "floor": int,          # piso al que pertenece (by / cells_per_floor), clampeado al último piso válido para rooftop
#       "floor_cell": int,     # celda dentro del piso (by % cells_per_floor)
#       "type": String,        # "body" para pisos normales, "rooftop" para el piso extra superior
#       "availability": bool   # false si es alleyway o está en chamfer
#     }
#   }
# }
static func get_3d_matrix(block_generator: BlockGenerator, coord: Vector2i) -> Dictionary:
	var x = coord.x
	var z = coord.y

	var cluster = block_generator.get_cluster_for_cell(x, z)
	if cluster == null:
		return {}

	var floor_count = cluster.floor_count
	var cells_per_floor = block_generator.get_cells_per_floor()
	var building_rows = block_generator.get_building_rows()
	var building_columns = block_generator.get_building_columns()
	var building_cell_height = block_generator.get_building_cell_height()
	var total_height_cells = (floor_count + 1) * cells_per_floor

	var base_module = block_generator.get_building_module(x, z, 0)
	if base_module == null:
		return {}

	var chamfer_rects = _get_chamfer_rects_static(base_module)

	var floor_modules: Dictionary = {}
	var cells = {}

	for by in range(total_height_cells):
		var floor_idx = min(by / cells_per_floor, floor_count - 1)
		var cell_type = "rooftop" if by >= floor_count * cells_per_floor else "body"

		if floor_idx not in floor_modules:
			floor_modules[floor_idx] = block_generator.get_building_module(x, z, floor_idx)
		var floor_module: BuildingModule = floor_modules[floor_idx]

		for bz in range(building_rows):
			for bx in range(building_columns):
				var available = true

				if floor_module != null and floor_module.is_cell_alleyway(bx, bz):
					available = false

				if available and _is_cell_in_chamfer_static(bx, bz, chamfer_rects):
					available = false

				var key = "%d_%d_%d" % [bx, bz, by]
				cells[key] = {
					"position": base_module.get_cell_position(bx, bz, by),
					"bx": bx,
					"bz": bz,
					"height_index": by,
					"floor": floor_idx,
					"floor_cell": by % cells_per_floor,
					"type": cell_type,
					"availability": available
				}

	return {
		"columns": building_columns,
		"rows": building_rows,
		"height_cells": total_height_cells,
		"floor_count": floor_count,
		"cells_per_floor": cells_per_floor,
		"cell_height": building_cell_height,
		"cells": cells
	}


# Genera los rectángulos de chamfer en coordenadas de building grid.
# Un chamfer es una esquina cortada del edificio. Cada vértice del quad
# puede tener [c1, c2] celdas chamfereadas en dos direcciones ortogonales.
#
# Los vértices del quad del BuildingModule son:
#   0: BL (Bottom-Left,  core_min_x, core_min_z)
#   1: BR (Bottom-Right, core_max_x, core_min_z)
#   2: TR (Top-Right,    core_max_x, core_max_z)
#   3: TL (Top-Left,     core_min_x, core_max_z)
#
# c1 y c2 representan la extensión del chamfer desde la esquina del core
# en cada una de las dos direcciones que convergen en ese vértice.
static func _get_chamfer_rects_static(module: BuildingModule) -> Array:
	var rects = []
	var chamfers = module.get_chamfers()
	var core = module.get_core_info()

	for vertex_index in chamfers.keys():
		var values = chamfers[vertex_index]
		var c1: int = values[0]
		var c2: int = values[1]

		var min_x: int
		var max_x: int
		var min_z: int
		var max_z: int

		match vertex_index:
			0:  # BL: c2 hacia +x, c1 hacia +z
				min_x = core["min_x"]
				max_x = core["min_x"] + c2 - 1
				min_z = core["min_z"]
				max_z = core["min_z"] + c1 - 1
			1:  # BR: c1 hacia -x, c2 hacia +z
				min_x = core["max_x"] - c1 + 1
				max_x = core["max_x"]
				min_z = core["min_z"]
				max_z = core["min_z"] + c2 - 1
			2:  # TR: c2 hacia -x, c1 hacia -z
				min_x = core["max_x"] - c2 + 1
				max_x = core["max_x"]
				min_z = core["max_z"] - c1 + 1
				max_z = core["max_z"]
			3:  # TL: c1 hacia +x, c2 hacia -z
				min_x = core["min_x"]
				max_x = core["min_x"] + c1 - 1
				min_z = core["max_z"] - c2 + 1
				max_z = core["max_z"]

		rects.append({"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z})

	return rects


# Devuelve true si (bx, bz) cae dentro de algún rectángulo de chamfer.
static func _is_cell_in_chamfer_static(bx: int, bz: int, chamfer_rects: Array) -> bool:
	for rect in chamfer_rects:
		if bx >= rect["min_x"] and bx <= rect["max_x"] and bz >= rect["min_z"] and bz <= rect["max_z"]:
			return true
	return false


# ============================================================
# LOOKUP EN MATRICES (acceso por coord desde el dict almacenado)
# ============================================================

# Devuelve la matriz 3D de una celda de la DistortedGrid, o {} si no existe.
static func get_matrix(matrices: Dictionary, coord: Vector2i) -> Dictionary:
	return matrices.get("%d_%d" % [coord.x, coord.y], {})


# ============================================================
# ACCESO A CELDAS
# ============================================================

# Devuelve el diccionario de una celda, o {} si no existe.
static func get_cell(matrix: Dictionary, bx: int, bz: int, by: int) -> Dictionary:
	if matrix.is_empty():
		return {}
	return matrix["cells"].get("%d_%d_%d" % [bx, bz, by], {})


# Devuelve la availability de una celda.
# false si la celda no existe.
static func get_cell_availability(matrix: Dictionary, bx: int, bz: int, by: int) -> bool:
	var cell = get_cell(matrix, bx, bz, by)
	if cell.is_empty():
		return false
	return cell["availability"]


# ============================================================
# AVAILABILITY LAZY DE VÉRTICES, EDGES Y FACES
# No se almacenan; se computan a partir de las celdas vecinas.
# ============================================================

# Un vértice (vx, vy, vz) es available si al menos una de las
# hasta 8 celdas que comparten ese vértice es available.
# Rango de vértices: [0, columns] x [0, height_cells] x [0, rows]
static func get_vertex_availability(matrix: Dictionary, vx: int, vy: int, vz: int) -> bool:
	if matrix.is_empty():
		return false

	var cols = matrix["columns"]
	var rows = matrix["rows"]
	var height = matrix["height_cells"]

	for dy in range(-1, 1):
		for dz in range(-1, 1):
			for dx in range(-1, 1):
				var cx = vx + dx
				var cz = vz + dz
				var cy = vy + dy
				if cx >= 0 and cx < cols and cz >= 0 and cz < rows and cy >= 0 and cy < height:
					if get_cell_availability(matrix, cx, cz, cy):
						return true
	return false


# Un edge es available si al menos una de sus hasta 4 celdas vecinas es available.
# El eje indica la dirección del edge:
#   "x": corre en X, las 4 celdas vecinas varían en Z e Y
#   "z": corre en Z, las 4 celdas vecinas varían en X e Y
#   "y": corre en Y, las 4 celdas vecinas varían en X y Z
# (vx, vy, vz) es el vértice origen del edge.
static func get_edge_availability(matrix: Dictionary, axis: String, vx: int, vy: int, vz: int) -> bool:
	if matrix.is_empty():
		return false

	var cols = matrix["columns"]
	var rows = matrix["rows"]
	var height = matrix["height_cells"]

	for da in range(-1, 1):
		for db in range(-1, 1):
			var cx: int
			var cz: int
			var cy: int
			match axis:
				"x":
					cx = vx
					cz = vz + da
					cy = vy + db
				"z":
					cx = vx + da
					cz = vz
					cy = vy + db
				"y":
					cx = vx + da
					cz = vz + db
					cy = vy
				_:
					continue
			if cx >= 0 and cx < cols and cz >= 0 and cz < rows and cy >= 0 and cy < height:
				if get_cell_availability(matrix, cx, cz, cy):
					return true
	return false


# Una face es available si al menos una de sus 2 celdas vecinas es available.
# La normal indica el eje perpendicular a la cara:
#   "y": cara horizontal. a=bx, b=vy (frontera vertical), c=bz
#   "x": cara vertical normal X. a=vx (frontera en X), b=by, c=bz
#   "z": cara vertical normal Z. a=bx, b=by, c=vz (frontera en Z)
# El parámetro que actúa como frontera es siempre el del eje de la normal.
static func get_face_availability(matrix: Dictionary, normal: String, a: int, b: int, c: int) -> bool:
	if matrix.is_empty():
		return false

	var cols = matrix["columns"]
	var rows = matrix["rows"]
	var height = matrix["height_cells"]

	for d in range(-1, 1):
		var cx: int
		var cz: int
		var cy: int
		match normal:
			"y":  # a=bx, b=vy, c=bz
				cx = a
				cy = b + d
				cz = c
			"x":  # a=vx, b=by, c=bz
				cx = a + d
				cy = b
				cz = c
			"z":  # a=bx, b=by, c=vz
				cx = a
				cy = b
				cz = c + d
			_:
				continue
		if cx >= 0 and cx < cols and cz >= 0 and cz < rows and cy >= 0 and cy < height:
			if get_cell_availability(matrix, cx, cz, cy):
				return true
	return false


# Devuelve una grilla 2D vertical de faces a una profundidad `depth` desde un edge
# de la building grid de una celda de la DistortedGrid.
#
# edge: "north" | "south" | "east" | "west"
# depth: offset desde el edge (0 = el plano más exterior)
#
# "north"/"south" generan faces con normal "z", along varía en bx (0..columns-1)
# "east"/"west"   generan faces con normal "x", along varía en bz (0..rows-1)
#
# Resultado:
# {
#   "along_count": int,
#   "height_count": int,
#   "faces": {
#     "along_height": {
#       "along": int,
#       "height": int,
#       "availability": bool
#     }
#   }
# }
static func get_2d_grid_from_edge(matrix: Dictionary, edge: String, depth: int) -> Dictionary:
	if matrix.is_empty():
		return {}

	var cols = matrix["columns"]
	var rows = matrix["rows"]
	var height = matrix["height_cells"]

	var normal: String
	var fixed_index: int
	var along_count: int

	match edge:
		"north":
			normal = "z"
			fixed_index = depth
			along_count = cols
		"south":
			normal = "z"
			fixed_index = rows - depth
			along_count = cols
		"west":
			normal = "x"
			fixed_index = depth
			along_count = rows
		"east":
			normal = "x"
			fixed_index = cols - depth
			along_count = rows
		_:
			return {}

	var faces = {}
	for by in range(height):
		for along in range(along_count):
			var avail: bool
			match normal:
				"z":  # a=bx, b=by, c=vz
					avail = get_face_availability(matrix, "z", along, by, fixed_index)
				"x":  # a=vx, b=by, c=bz
					avail = get_face_availability(matrix, "x", fixed_index, by, along)
				_:
					avail = false

			faces["%d_%d" % [along, by]] = {
				"along": along,
				"height": by,
				"availability": avail
			}

	return {
		"along_count": along_count,
		"height_count": height,
		"faces": faces
	}
