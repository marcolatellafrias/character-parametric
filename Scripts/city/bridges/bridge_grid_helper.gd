class_name BuildingGridHelper extends RefCounted

var matrices: Dictionary = {}


func _init(block_generator: BlockGenerator) -> void:
	var grid = block_generator.get_distorted_grid()
	for z in range(grid.rows):
		for x in range(grid.columns):
			var matrix = BuildingGridHelper.get_3d_matrix(block_generator, Vector2i(x, z))
			if not matrix.is_empty():
				matrices["%d_%d" % [x, z]] = matrix


func get_matrix(coord: Vector2i) -> Dictionary:
	return matrices.get("%d_%d" % [coord.x, coord.y], {})


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
	var total_height_cells = floor_count * cells_per_floor

	var base_module = block_generator.get_building_module(x, z, 0)
	if base_module == null:
		return {}

	var chamfer_rects = _get_chamfer_rects_static(base_module)

	var floor_modules: Dictionary = {}
	var cells = {}

	for by in range(total_height_cells):
		var floor_idx = by / cells_per_floor

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
			0:  # BL
				min_x = core["min_x"]
				max_x = core["min_x"] + c2 - 1
				min_z = core["min_z"]
				max_z = core["min_z"] + c1 - 1
			1:  # BR
				min_x = core["max_x"] - c1 + 1
				max_x = core["max_x"]
				min_z = core["min_z"]
				max_z = core["min_z"] + c2 - 1
			2:  # TR
				min_x = core["max_x"] - c2 + 1
				max_x = core["max_x"]
				min_z = core["max_z"] - c1 + 1
				max_z = core["max_z"]
			3:  # TL
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


func get_cell(coord: Vector2i, bx: int, bz: int, by: int) -> Dictionary:
	var matrix = get_matrix(coord)
	if matrix.is_empty():
		return {}
	return matrix["cells"].get("%d_%d_%d" % [bx, bz, by], {})


func get_cell_availability(coord: Vector2i, bx: int, bz: int, by: int) -> bool:
	var cell = get_cell(coord, bx, bz, by)
	if cell.is_empty():
		return false
	return cell["availability"]


func get_vertex_availability(coord: Vector2i, vx: int, vy: int, vz: int) -> bool:
	var matrix = get_matrix(coord)
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
					if get_cell_availability(coord, cx, cz, cy):
						return true
	return false


func get_edge_availability(coord: Vector2i, axis: String, vx: int, vy: int, vz: int) -> bool:
	var matrix = get_matrix(coord)
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
				if get_cell_availability(coord, cx, cz, cy):
					return true
	return false


func get_face_availability(coord: Vector2i, normal: String, a: int, b: int, c: int) -> bool:
	var matrix = get_matrix(coord)
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
			if get_cell_availability(coord, cx, cz, cy):
				return true
	return false
