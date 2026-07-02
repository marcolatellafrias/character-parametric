class_name TraversalGenerator extends RefCounted

var block: BlockGenerator

var delivery_doors: Array[Dictionary] = []
var stair_zones: Array[Dictionary] = []
var floating_sidewalk_zones: Array[Dictionary] = []


func _init(p_block: BlockGenerator) -> void:
	block = p_block


func generate(_doors_per_block: int = 4) -> void:
	delivery_doors.clear()
	stair_zones.clear()
	floating_sidewalk_zones.clear()
	_generate_floor_sidewalks()


func _generate_floor_sidewalks() -> void:
	var grid = block.get_distorted_grid()
	if grid == null:
		return

	var cols = grid.columns
	var rows = grid.rows

	# Corners: facade_offset × facade_offset at each block corner
	var corner_cells = {
		"nw": {"cell": Vector2i(0, 0), "edges": [3, 0]},
		"ne": {"cell": Vector2i(cols - 1, 0), "edges": [0, 1]},
		"se": {"cell": Vector2i(cols - 1, rows - 1), "edges": [1, 2]},
		"sw": {"cell": Vector2i(0, rows - 1), "edges": [2, 3]},
	}

	for key in corner_cells:
		var info = corner_cells[key]
		var cell: Vector2i = info["cell"]
		var module = block.get_building_module(cell.x, cell.y, 0)
		if module == null:
			continue

		var core = module.get_core_info()
		var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
		match key:
			"nw":
				bx_min = 0; bx_max = core["min_x"] - 1
				bz_min = 0; bz_max = core["min_z"] - 1
			"ne":
				bx_min = core["max_x"] + 1; bx_max = module.columns - 1
				bz_min = 0; bz_max = core["min_z"] - 1
			"se":
				bx_min = core["max_x"] + 1; bx_max = module.columns - 1
				bz_min = core["max_z"] + 1; bz_max = module.rows - 1
			"sw":
				bx_min = 0; bx_max = core["min_x"] - 1
				bz_min = core["max_z"] + 1; bz_max = module.rows - 1

		if bx_min > bx_max or bz_min > bz_max:
			continue

		var cluster = block.get_cluster_for_cell(cell.x, cell.y)
		if cluster == null:
			continue

		floating_sidewalk_zones.append({
			"cell": cell, "edge": info["edges"][0], "floor": 0,
			"cluster_id": cluster.id,
			"bx_min": bx_min, "bx_max": bx_max, "bz_min": bz_min, "bz_max": bz_max
		})

	# Sides: one strip per DG cell along each perimeter edge
	var side_edges = [
		[0, 0,       0, cols - 1],
		[1, cols - 1, 0, rows - 1],
		[2, rows - 1, 0, cols - 1],
		[3, 0,       0, rows - 1],
	]
	for side_info in side_edges:
		var edge_idx: int = side_info[0]
		var fixed: int = side_info[1]
		var range_start: int = side_info[2]
		var range_end: int = side_info[3]
		for i in range(range_start, range_end + 1):
			var coord: Vector2i
			if edge_idx == 0 or edge_idx == 2:
				coord = Vector2i(i, fixed)
			else:
				coord = Vector2i(fixed, i)
			var module = block.get_building_module(coord.x, coord.y, 0)
			if module == null:
				continue
			var core = module.get_core_info()
			var is_first = (i == range_start)
			var is_last = (i == range_end)
			var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
			match edge_idx:
				0:
					bx_min = core["min_x"] if is_first else 0
					bx_max = core["max_x"] if is_last else module.columns - 1
					bz_min = 0; bz_max = core["min_z"] - 1
				1:
					bx_min = core["max_x"] + 1; bx_max = module.columns - 1
					bz_min = core["min_z"] if is_first else 0
					bz_max = core["max_z"] if is_last else module.rows - 1
				2:
					bx_min = core["min_x"] if is_first else 0
					bx_max = core["max_x"] if is_last else module.columns - 1
					bz_min = core["max_z"] + 1; bz_max = module.rows - 1
				3:
					bx_min = 0; bx_max = core["min_x"] - 1
					bz_min = core["min_z"] if is_first else 0
					bz_max = core["max_z"] if is_last else module.rows - 1
			if bx_min > bx_max or bz_min > bz_max:
				continue

			var cluster = block.get_cluster_for_cell(coord.x, coord.y)
			if cluster == null:
				continue

			floating_sidewalk_zones.append({
				"cell": coord, "edge": edge_idx, "floor": 0,
				"cluster_id": cluster.id,
				"bx_min": bx_min, "bx_max": bx_max, "bz_min": bz_min, "bz_max": bz_max
			})
