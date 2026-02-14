class_name BridgeGridHelper extends RefCounted

var block: BlockGenerator
var city: GraphCityGenerator
var face_idx: int
var distorted_rows: int
var distorted_columns: int
var building_rows: int
var building_columns: int

func _init(p_block: BlockGenerator, p_city: GraphCityGenerator = null, p_face_idx: int = -1) -> void:
	block = p_block
	city = p_city
	face_idx = p_face_idx
	
	var distorted_grid = block.get_distorted_grid()
	if distorted_grid:
		distorted_rows = distorted_grid.rows
		distorted_columns = distorted_grid.columns
	
	building_rows = block.get_building_rows()
	building_columns = block.get_building_columns()

func get_facade_edge_info(edge_index: int, cell_index: int) -> Dictionary:
	var distorted_grid = block.get_distorted_grid()
	if distorted_grid == null:
		return {}
	
	var configs = {
		0: [cell_index, 0, distorted_columns, 0, 1],
		1: [distorted_columns - 1, cell_index, distorted_rows, 1, 2],
		2: [cell_index, distorted_rows - 1, distorted_columns, 2, 3],
		3: [0, cell_index, distorted_rows, 3, 0]
	}
	
	if edge_index not in configs:
		return {}
	
	var config = configs[edge_index]
	
	if cell_index < 0 or cell_index >= config[2]:
		return {}
	
	var cell_vertices = distorted_grid.get_cell_vertices(config[0], config[1])
	if cell_vertices.size() != 4:
		return {}
	
	return {
		"edge_index": edge_index,
		"cell_index": cell_index,
		"cell_x": config[0],
		"cell_z": config[1],
		"vertices": [cell_vertices[config[3]], cell_vertices[config[4]]]
	}

func get_building_edges_from_facade(facade_edge_info: Dictionary, is_core: bool = false) -> Array:
	var edges: Array = []
	
	if facade_edge_info.is_empty():
		return edges
	
	var building_module = block.get_building_module(facade_edge_info["cell_x"], facade_edge_info["cell_z"])
	if building_module == null:
		return edges
	
	var core_info = building_module.get_core_info() if is_core else {}
	var start_col = core_info.get("min_x", 0)
	var end_col = core_info.get("max_x", building_columns - 1)
	var start_row = core_info.get("min_z", 0)
	var end_row = core_info.get("max_z", building_rows - 1)
	
	var configs = {
		0: [0, 1, true, start_row],
		1: [1, 2, false, end_col],
		2: [2, 3, true, end_row],
		3: [3, 0, false, start_col]
	}
	
	var config = configs[facade_edge_info["edge_index"]]
	var range_vals = range(start_col, end_col + 1) if config[2] else range(start_row, end_row + 1)
	
	for i in range_vals:
		var col = i if config[2] else config[3]
		var row = config[3] if config[2] else i
		var verts = building_module.get_cell_vertices(col, row)
		
		if verts.size() == 4:
			edges.append({
				"v1": verts[config[0]],
				"v2": verts[config[1]],
				"grid_x": col,
				"grid_z": row
			})
	
	return edges

func get_vertical_grid_from_facade(facade_edge_info: Dictionary, is_core: bool = false) -> Dictionary:
	if facade_edge_info.is_empty():
		return {"quads": [], "width": 0, "height": 0}
	
	var cell_x = facade_edge_info["cell_x"]
	var cell_z = facade_edge_info["cell_z"]
	
	var cluster = block.get_cluster_for_cell(cell_x, cell_z)
	if cluster == null:
		return {"quads": [], "width": 0, "height": 0}
	
	var floor_count = cluster.get_floor_count()
	var cells_per_floor = block.get_cells_per_floor()
	var cell_height = block.get_building_cell_height()
	var total_cells_vertical = floor_count * cells_per_floor
	var base_edges = get_building_edges_from_facade(facade_edge_info, is_core)
	
	var quads: Array = []
	var edge_index = 0
	
	for edge in base_edges:
		for cell_y in range(total_cells_vertical):
			var y_bottom = cell_y * cell_height
			var y_top = (cell_y + 1) * cell_height
			
			var v1 = Vector3(edge["v1"].x, y_bottom, edge["v1"].z)
			var v2 = Vector3(edge["v2"].x, y_bottom, edge["v2"].z)
			var v3 = Vector3(edge["v2"].x, y_top, edge["v2"].z)
			var v4 = Vector3(edge["v1"].x, y_top, edge["v1"].z)
			
			quads.append({
				"local_x": edge_index,
				"local_y": cell_y,
				"grid_x": edge["grid_x"],
				"grid_z": edge["grid_z"],
				"v1": v1,
				"v2": v2,
				"v3": v3,
				"v4": v4
			})
		
		edge_index += 1
	
	return {
		"quads": quads,
		"width": base_edges.size(),
		"height": total_cells_vertical
	}

func get_quad_at(vertical_grid: Dictionary, local_x: int, local_y: int) -> Dictionary:
	if local_x < 0 or local_x >= vertical_grid["width"]:
		return {}
	if local_y < 0 or local_y >= vertical_grid["height"]:
		return {}
	
	for quad in vertical_grid["quads"]:
		if quad["local_x"] == local_x and quad["local_y"] == local_y:
			return quad
	
	return {}

func get_random_facade_rect(edge_index: int, size: Vector2i, rng: RandomNumberGenerator, is_core: bool = false) -> Dictionary:
	var distorted_grid = block.get_distorted_grid()
	if distorted_grid == null:
		return {}
	
	var max_index = distorted_grid.columns if (edge_index == 0 or edge_index == 2) else distorted_grid.rows
	var cell_index = rng.randi_range(0, max_index - 1)
	
	var facade_info = get_facade_edge_info(edge_index, cell_index)
	if facade_info.is_empty():
		return {}
	
	var vgrid = get_vertical_grid_from_facade(facade_info, is_core)
	if vgrid["width"] < size.x or vgrid["height"] < size.y:
		return {}
	
	var local_x = rng.randi_range(0, vgrid["width"] - size.x)
	var local_y = rng.randi_range(0, vgrid["height"] - size.y)
	
	var quad_bl = get_quad_at(vgrid, local_x, local_y)
	var quad_br = get_quad_at(vgrid, local_x + size.x - 1, local_y)
	var quad_tr = get_quad_at(vgrid, local_x + size.x - 1, local_y + size.y - 1)
	var quad_tl = get_quad_at(vgrid, local_x, local_y + size.y - 1)
	
	if quad_bl.is_empty() or quad_br.is_empty() or quad_tr.is_empty() or quad_tl.is_empty():
		return {}
	
	return {
		"verts": [quad_bl["v1"], quad_br["v2"], quad_tr["v3"], quad_tl["v4"]],
		"edge_index": edge_index,
		"cell_index": cell_index,
		"pos_x": local_x,
		"pos_y": local_y,
		"size": size,
		"is_core": is_core
	}

func get_mirrored_facade_info(edge_index: int, cell_index: int, is_core: bool = false) -> Dictionary:
	if city == null or face_idx == -1:
		return {}
	
	var face = city.plain_graph.faces[face_idx]
	var node1 = face[edge_index]
	var node2 = face[(edge_index + 1) % face.size()]
	
	var sharing_faces = city._find_faces_sharing_edge(node1, node2)
	var neighbor_face_idx = -1
	for f in sharing_faces:
		if f != face_idx:
			neighbor_face_idx = f
			break
	
	if neighbor_face_idx == -1:
		return {}
	
	var neighbor_block = city.get_block_grid(neighbor_face_idx)
	if neighbor_block == null:
		return {}
	
	var neighbor_face = city.plain_graph.faces[neighbor_face_idx]
	var mirrored_edge_index = -1
	for i in range(neighbor_face.size()):
		var n1 = neighbor_face[i]
		var n2 = neighbor_face[(i + 1) % neighbor_face.size()]
		if n1 == node2 and n2 == node1:
			mirrored_edge_index = i
			break
	
	if mirrored_edge_index == -1:
		return {}
	
	var neighbor_distorted = neighbor_block.get_distorted_grid()
	var max_index = neighbor_distorted.columns if (mirrored_edge_index == 0 or mirrored_edge_index == 2) else neighbor_distorted.rows
	
	var neighbor_helper = BridgeGridHelper.new(neighbor_block, city, neighbor_face_idx)
	
	var current_cell_0 = get_facade_edge_info(edge_index, 0)
	var neighbor_cell_0 = neighbor_helper.get_facade_edge_info(mirrored_edge_index, 0)
	var neighbor_cell_last = neighbor_helper.get_facade_edge_info(mirrored_edge_index, max_index - 1)
	
	if current_cell_0.is_empty() or neighbor_cell_0.is_empty() or neighbor_cell_last.is_empty():
		return {}
	
	var current_origin: Vector3 = current_cell_0["vertices"][0]
	var neighbor_origin: Vector3 = neighbor_cell_0["vertices"][0]
	var neighbor_end: Vector3 = neighbor_cell_last["vertices"][0]
	
	var needs_flip: bool = current_origin.distance_to(neighbor_origin) > current_origin.distance_to(neighbor_end)
	var mirrored_cell_index = (max_index - 1 - cell_index) if needs_flip else cell_index
	mirrored_cell_index = clamp(mirrored_cell_index, 0, max_index - 1)
	
	var facade_info = neighbor_helper.get_facade_edge_info(mirrored_edge_index, mirrored_cell_index)
	
	if facade_info.is_empty():
		return {}
	
	return {
		"facade_info": facade_info,
		"neighbor_helper": neighbor_helper,
		"neighbor_face_idx": neighbor_face_idx,
		"mirrored_edge_index": mirrored_edge_index,
		"mirrored_cell_index": mirrored_cell_index,
		"needs_flip": needs_flip
	}

func get_opposite_facade_rect(edge_index: int, cell_index: int, size: Vector2i, pos_x: int, pos_y: int, is_core: bool = false) -> Array[Vector3]:
	var mirrored = get_mirrored_facade_info(edge_index, cell_index, is_core)
	if mirrored.is_empty():
		return []
	
	var neighbor_helper: BridgeGridHelper = mirrored["neighbor_helper"]
	var facade_info: Dictionary = mirrored["facade_info"]
	var needs_flip: bool = mirrored["needs_flip"]
	
	var vgrid = neighbor_helper.get_vertical_grid_from_facade(facade_info, is_core)
	
	if vgrid["width"] < size.x or vgrid["height"] < size.y:
		return []
	
	var mirrored_x = (vgrid["width"] - pos_x - size.x) if needs_flip else pos_x
	var mirrored_y = pos_y
	
	if mirrored_x < 0 or mirrored_x + size.x > vgrid["width"]:
		return []
	if mirrored_y < 0 or mirrored_y + size.y > vgrid["height"]:
		return []
	
	var quad_bl = neighbor_helper.get_quad_at(vgrid, mirrored_x, mirrored_y)
	var quad_br = neighbor_helper.get_quad_at(vgrid, mirrored_x + size.x - 1, mirrored_y)
	var quad_tr = neighbor_helper.get_quad_at(vgrid, mirrored_x + size.x - 1, mirrored_y + size.y - 1)
	var quad_tl = neighbor_helper.get_quad_at(vgrid, mirrored_x, mirrored_y + size.y - 1)
	
	if quad_bl.is_empty() or quad_br.is_empty() or quad_tr.is_empty() or quad_tl.is_empty():
		return []
	
	return [
		quad_bl["v1"],
		quad_br["v2"],
		quad_tr["v3"],
		quad_tl["v4"]
	]
