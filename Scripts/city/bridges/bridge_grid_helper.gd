class_name BridgeGridHelper extends RefCounted

## Helper para obtener vértices de volúmenes en el building grid distorsionado
## Útil para colocar objetos procedurales (ventanas, ACs, etc.)

var block: BlockGenerator
var distorted_rows: int
var distorted_columns: int
var building_rows: int
var building_columns: int

func _init(p_block: BlockGenerator) -> void:
	block = p_block
	
	var distorted_grid = block.get_distorted_grid()
	if distorted_grid:
		distorted_rows = distorted_grid.rows
		distorted_columns = distorted_grid.columns
	
	building_rows = block.get_building_rows()
	building_columns = block.get_building_columns()

## Retorna información completa del edge de fachada en un borde del bloque
## edge_index: 0=norte, 1=este, 2=sur, 3=oeste
## cell_index: índice lineal a lo largo de ese borde
func get_facade_edge_info(edge_index: int, cell_index: int) -> Dictionary:
	var distorted_grid = block.get_distorted_grid()
	if distorted_grid == null:
		return {}
	
	# [cell_x, cell_z, max_index, v1_idx, v2_idx]
	var configs = {
		0: [cell_index, 0, distorted_columns, 0, 1],  # Norte: BL→BR
		1: [distorted_columns - 1, cell_index, distorted_rows, 1, 2],  # Este: BR→TR
		2: [cell_index, distorted_rows - 1, distorted_columns, 2, 3],  # Sur: TR→TL
		3: [0, cell_index, distorted_rows, 3, 0]  # Oeste: TL→BL
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


## Retorna los edges del building grid que coinciden con un edge facade
## facade_edge_info: Dictionary retornado por get_facade_edge_info()
## is_core: si true, retorna edges del área core (aplicando offsets de alleyway)
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
	
	# [v1_idx, v2_idx, is_horizontal, fixed_coord]
	var configs = {
		0: [0, 1, true, start_row],   # Norte: BL→BR
		1: [1, 2, false, end_col],    # Este: BR→TR
		2: [2, 3, true, end_row],     # Sur: TR→TL
		3: [3, 0, false, start_col]   # Oeste: TL→BL
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
	
## Retorna una grilla vertical de quads a partir de un facade edge
## Incluye índices relativos (local_x, local_y) para fácil acceso
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
	var base_edges = get_building_edges_from_facade(facade_edge_info, is_core)
	
	var quads: Array = []
	var edge_index = 0
	
	for edge in base_edges:
		for floor in range(floor_count):
			var y_bottom = floor * cells_per_floor * block.get_building_cell_height()
			var y_top = (floor + 1) * cells_per_floor * block.get_building_cell_height()
			
			var v1 = Vector3(edge["v1"].x, y_bottom, edge["v1"].z)
			var v2 = Vector3(edge["v2"].x, y_bottom, edge["v2"].z)
			var v3 = Vector3(edge["v2"].x, y_top, edge["v2"].z)
			var v4 = Vector3(edge["v1"].x, y_top, edge["v1"].z)
			
			quads.append({
				"local_x": edge_index,  # índice horizontal relativo
				"local_y": floor,       # índice vertical relativo
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
		"height": floor_count
	}


## Obtiene un quad específico de una grilla vertical usando coordenadas relativas
func get_quad_at(vertical_grid: Dictionary, local_x: int, local_y: int) -> Dictionary:
	if local_x < 0 or local_x >= vertical_grid["width"]:
		return {}
	if local_y < 0 or local_y >= vertical_grid["height"]:
		return {}
	
	for quad in vertical_grid["quads"]:
		if quad["local_x"] == local_x and quad["local_y"] == local_y:
			return quad
	
	return {}
