class_name SidewalkMatrix
extends RefCounted

enum CellState {
	AVAILABLE = 0,
	UNAVAILABLE = 1,
	ROOF_ONLY = 2
}

var matrices: Dictionary = {}


func _init(block_generator: BlockGenerator) -> void:
	var grid = block_generator.get_distorted_grid()
	for z in range(grid.rows):
		for x in range(grid.columns):
			var matrix = SidewalkMatrix.get_3d_matrix(block_generator, Vector2i(x, z))
			if not matrix.is_empty():
				matrices["%d_%d" % [x, z]] = matrix


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
		var is_rooftop = by >= floor_count * cells_per_floor

		if floor_idx not in floor_modules:
			floor_modules[floor_idx] = block_generator.get_building_module(x, z, floor_idx)
		var floor_module: BuildingModule = floor_modules[floor_idx]

		for bz in range(building_rows):
			for bx in range(building_columns):
				var in_core = floor_module != null and floor_module.is_cell_in_core(bx, bz)
				var in_chamfer = _is_cell_in_chamfer_static(bx, bz, chamfer_rects)

				var state: int
				if in_core and not in_chamfer:
					state = CellState.UNAVAILABLE
				elif is_rooftop:
					state = CellState.ROOF_ONLY
				else:
					state = CellState.AVAILABLE

				var key = "%d_%d_%d" % [bx, bz, by]
				cells[key] = {
					"position": base_module.get_cell_position(bx, bz, by),
					"bx": bx,
					"bz": bz,
					"height_index": by,
					"floor": floor_idx,
					"floor_cell": by % cells_per_floor,
					"type": "rooftop" if is_rooftop else "body",
					"state": state
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
			0:
				min_x = core["min_x"]
				max_x = core["min_x"] + c2 - 1
				min_z = core["min_z"]
				max_z = core["min_z"] + c1 - 1
			1:
				min_x = core["max_x"] - c1 + 1
				max_x = core["max_x"]
				min_z = core["min_z"]
				max_z = core["min_z"] + c2 - 1
			2:
				min_x = core["max_x"] - c2 + 1
				max_x = core["max_x"]
				min_z = core["max_z"] - c1 + 1
				max_z = core["max_z"]
			3:
				min_x = core["min_x"]
				max_x = core["min_x"] + c1 - 1
				min_z = core["max_z"] - c2 + 1
				max_z = core["max_z"]

		rects.append({"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z})

	return rects


static func _is_cell_in_chamfer_static(bx: int, bz: int, chamfer_rects: Array) -> bool:
	for rect in chamfer_rects:
		if bx >= rect["min_x"] and bx <= rect["max_x"] and bz >= rect["min_z"] and bz <= rect["max_z"]:
			return true
	return false


static func get_matrix(matrices: Dictionary, coord: Vector2i) -> Dictionary:
	return matrices.get("%d_%d" % [coord.x, coord.y], {})


static func get_cell(matrix: Dictionary, bx: int, bz: int, by: int) -> Dictionary:
	if matrix.is_empty():
		return {}
	return matrix["cells"].get("%d_%d_%d" % [bx, bz, by], {})


static func get_cell_state(matrix: Dictionary, bx: int, bz: int, by: int) -> int:
	var cell = get_cell(matrix, bx, bz, by)
	if cell.is_empty():
		return CellState.AVAILABLE
	return cell["state"]


static func is_cell_available(matrix: Dictionary, bx: int, bz: int, by: int) -> bool:
	return get_cell_state(matrix, bx, bz, by) == CellState.AVAILABLE


static func set_cell_unavailable(matrix: Dictionary, bx: int, bz: int, by: int) -> void:
	var key = "%d_%d_%d" % [bx, bz, by]
	if matrix.is_empty() or not matrix["cells"].has(key):
		return
	matrix["cells"][key]["state"] = CellState.UNAVAILABLE


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
					if is_cell_available(matrix, cx, cz, cy):
						return true
	return false


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
					cx = vx;  cz = vz + da;  cy = vy + db
				"z":
					cx = vx + da;  cz = vz;  cy = vy + db
				"y":
					cx = vx + da;  cz = vz + db;  cy = vy
				_:
					continue
			if cx >= 0 and cx < cols and cz >= 0 and cz < rows and cy >= 0 and cy < height:
				if is_cell_available(matrix, cx, cz, cy):
					return true
	return false


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
			"y":   cx = a;      cy = b + d;  cz = c
			"x":   cx = a + d;  cy = b;      cz = c
			"z":   cx = a;      cy = b;      cz = c + d
			_:     continue
		if cx >= 0 and cx < cols and cz >= 0 and cz < rows and cy >= 0 and cy < height:
			if is_cell_available(matrix, cx, cz, cy):
				return true
	return false


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
			normal = "z";  fixed_index = depth;          along_count = cols
		"south":
			normal = "z";  fixed_index = rows - depth;   along_count = cols
		"west":
			normal = "x";  fixed_index = depth;          along_count = rows
		"east":
			normal = "x";  fixed_index = cols - depth;   along_count = rows
		_:
			return {}

	var faces = {}
	for by in range(height):
		for along in range(along_count):
			var avail: bool
			match normal:
				"z":  avail = get_face_availability(matrix, "z", along, by, fixed_index)
				"x":  avail = get_face_availability(matrix, "x", fixed_index, by, along)
				_:    avail = false

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
