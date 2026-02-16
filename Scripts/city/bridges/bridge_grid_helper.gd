class_name BridgeGridHelper extends RefCounted

var block: BlockGenerator
var distorted_rows: int
var distorted_columns: int
var building_rows: int
var building_columns: int

func _init(p_block: BlockGenerator) -> void:
    block = p_block
    var distorted_grid = block.get_distorted_grid()
    if distorted_grid:
        distorted_rows    = distorted_grid.rows
        distorted_columns = distorted_grid.columns
    building_rows    = block.get_building_rows()
    building_columns = block.get_building_columns()

func _get_chamfered_cells(building_module: BuildingModule, core_info: Dictionary) -> Dictionary:
    var chamfered: Dictionary = {}
    var chamfers = building_module.get_chamfers()
    var cols = building_columns
    var rows_ = building_rows

    var west_offset  = core_info.get("min_x", 0)
    var east_offset  = (cols - 1) - core_info.get("max_x", cols - 1)
    var north_offset = core_info.get("min_z", 0)
    var south_offset = (rows_ - 1) - core_info.get("max_z", rows_ - 1)

    for vertex_index in chamfers:
        var cv = chamfers[vertex_index]
        var c1: int = cv[0]
        var c2: int = cv[1]
        var x_range: Array
        var z_range: Array
        match vertex_index:
            0:
                x_range = range(0, west_offset  + c1)
                z_range = range(0, north_offset + c2)
            1:
                x_range = range(cols  - east_offset  - c1, cols)
                z_range = range(0,     north_offset + c2)
            2:
                x_range = range(cols  - east_offset  - c1, cols)
                z_range = range(rows_ - south_offset - c2, rows_)
            3:
                x_range = range(0, west_offset  + c1)
                z_range = range(rows_ - south_offset - c2, rows_)
        for x in x_range:
            for z in z_range:
                chamfered["%d_%d" % [x, z]] = true
    return chamfered

func _get_edge_endpoints(facade_edge_info: Dictionary, is_core: bool) -> Array[Vector3]:
    var edge_index: int = facade_edge_info["edge_index"]

    if not is_core:
        return [facade_edge_info["vertices"][0], facade_edge_info["vertices"][1]]

    var building_module = block.get_building_module(facade_edge_info["cell_x"], facade_edge_info["cell_z"])
    if building_module == null:
        return [facade_edge_info["vertices"][0], facade_edge_info["vertices"][1]]

    var core_info: Dictionary = building_module.get_core_info()
    var start_col: int = core_info.get("min_x", 0)
    var end_col:   int = core_info.get("max_x", building_columns - 1)
    var start_row: int = core_info.get("min_z", 0)
    var end_row:   int = core_info.get("max_z", building_rows - 1)

    var vL: PackedVector3Array
    var vR: PackedVector3Array
    match edge_index:
        0:
            vL = building_module.get_cell_vertices(0,                    start_row)
            vR = building_module.get_cell_vertices(building_columns - 1, start_row)
            return [vL[0], vR[1]]
        1:
            vL = building_module.get_cell_vertices(end_col, 0)
            vR = building_module.get_cell_vertices(end_col, building_rows - 1)
            return [vL[1], vR[2]]
        2:
            vL = building_module.get_cell_vertices(building_columns - 1, end_row)
            vR = building_module.get_cell_vertices(0,                    end_row)
            return [vL[2], vR[3]]
        3:
            vL = building_module.get_cell_vertices(start_col, building_rows - 1)
            vR = building_module.get_cell_vertices(start_col, 0)
            return [vL[3], vR[0]]

    return [facade_edge_info["vertices"][0], facade_edge_info["vertices"][1]]

func _get_col_row(local_x: int, fixed_val: int, edge_index: int, iterate_cols: bool) -> Array[int]:
    var col: int
    var row: int
    if iterate_cols:
        col = (building_columns - 1 - local_x) if edge_index == 2 else local_x
        row = fixed_val
    else:
        col = fixed_val
        row = (building_rows - 1 - local_x) if edge_index == 3 else local_x
    return [col, row]

func _is_cell_available(col: int, row: int, is_core: bool,
        start_col: int, end_col: int, start_row: int, end_row: int,
        chamfered_cells: Dictionary) -> bool:
    if "%d_%d" % [col, row] in chamfered_cells:
        return false
    if is_core:
        return col >= start_col and col <= end_col and row >= start_row and row <= end_row
    return true

func _is_edge_available(local_x0: int, local_x1: int, local_y0: int, local_y1: int,
        grid_width: int, grid_height: int,
        is_core: bool, start_col: int, end_col: int, start_row: int, end_row: int,
        chamfered_cells: Dictionary, fixed_val: int, edge_index: int, iterate_cols: bool) -> bool:
    var cells: Array[Array] = []
    if local_x0 == local_x1:
        if local_x0 > 0:
            cells.append([local_x0 - 1, local_y0])
        if local_x0 < grid_width:
            cells.append([local_x0, local_y0])
    else:
        if local_y0 > 0:
            cells.append([local_x0, local_y0 - 1])
        if local_y0 < grid_height:
            cells.append([local_x0, local_y0])

    for cell in cells:
        var cr = _get_col_row(cell[0], fixed_val, edge_index, iterate_cols)
        if _is_cell_available(cr[0], cr[1], is_core, start_col, end_col, start_row, end_row, chamfered_cells):
            return true
    return false

func _build_unavailable_edges_and_points(
        grid_width: int, grid_height: int,
        is_core: bool, start_col: int, end_col: int, start_row: int, end_row: int,
        chamfered_cells: Dictionary, fixed_val: int, edge_index: int, iterate_cols: bool
) -> Dictionary:
    var unavailable_edges: Dictionary = {}
    var unavailable_points: Dictionary = {}

    for x in range(grid_width):
        for y in range(grid_height + 1):
            if not _is_edge_available(x, x + 1, y, y, grid_width, grid_height,
                    is_core, start_col, end_col, start_row, end_row,
                    chamfered_cells, fixed_val, edge_index, iterate_cols):
                unavailable_edges["h_%d_%d" % [x, y]] = true

    for x in range(grid_width + 1):
        for y in range(grid_height):
            if not _is_edge_available(x, x, y, y + 1, grid_width, grid_height,
                    is_core, start_col, end_col, start_row, end_row,
                    chamfered_cells, fixed_val, edge_index, iterate_cols):
                unavailable_edges["v_%d_%d" % [x, y]] = true

    for px in range(grid_width + 1):
        for py in range(grid_height + 1):
            var all_unavailable = true
            if px > 0:
                if not ("h_%d_%d" % [px - 1, py] in unavailable_edges):
                    all_unavailable = false
            if px < grid_width:
                if not ("h_%d_%d" % [px, py] in unavailable_edges):
                    all_unavailable = false
            if py > 0:
                if not ("v_%d_%d" % [px, py - 1] in unavailable_edges):
                    all_unavailable = false
            if py < grid_height:
                if not ("v_%d_%d" % [px, py] in unavailable_edges):
                    all_unavailable = false
            if all_unavailable:
                unavailable_points["%d_%d" % [px, py]] = true

    return {"unavailable_edges": unavailable_edges, "unavailable_points": unavailable_points}

func _get_core_and_chamfer_info(cell_x: int, cell_z: int, is_core: bool) -> Dictionary:
    var building_module = block.get_building_module(cell_x, cell_z)
    var core_info: Dictionary = building_module.get_core_info() if building_module else {}
    var chamfered_cells: Dictionary = _get_chamfered_cells(building_module, core_info) if building_module else {}
    var start_col = core_info.get("min_x", 0)
    var end_col   = core_info.get("max_x", building_columns - 1)
    var start_row = core_info.get("min_z", 0)
    var end_row   = core_info.get("max_z", building_rows - 1)
    return {
        "chamfered_cells": chamfered_cells,
        "start_col": start_col,
        "end_col":   end_col,
        "start_row": start_row,
        "end_row":   end_row,
    }

func get_facade_grid_all_floors(facade_edge_info: Dictionary, is_core: bool = false) -> Dictionary:
    if facade_edge_info.is_empty():
        return {"quads": [], "width": 0, "height": 0, "unavailable_edges": {}, "unavailable_points": {}}

    var cell_x: int     = facade_edge_info["cell_x"]
    var cell_z: int     = facade_edge_info["cell_z"]
    var edge_index: int = facade_edge_info["edge_index"]

    var cluster = block.get_cluster_for_cell(cell_x, cell_z)
    if cluster == null:
        return {"quads": [], "width": 0, "height": 0, "unavailable_edges": {}, "unavailable_points": {}}

    var endpoints        := _get_edge_endpoints(facade_edge_info, is_core)
    var vA: Vector3       = endpoints[0]
    var vB: Vector3       = endpoints[1]
    var floor_count: int  = cluster.get_floor_count()
    var cells_per_floor   = block.get_cells_per_floor()
    var cell_height       = block.get_building_cell_height()
    var total_cells_v     = floor_count * cells_per_floor
    var iterate_cols      = (edge_index == 0 or edge_index == 2)
    var grid_width: int   = building_columns if iterate_cols else building_rows

    var ci = _get_core_and_chamfer_info(cell_x, cell_z, is_core)

    var fixed_val: int
    match edge_index:
        0: fixed_val = ci["start_row"] if is_core else 0
        1: fixed_val = ci["end_col"]   if is_core else building_columns - 1
        2: fixed_val = ci["end_row"]   if is_core else building_rows - 1
        3: fixed_val = ci["start_col"] if is_core else 0

    var availability = _build_unavailable_edges_and_points(
        grid_width, total_cells_v,
        is_core, ci["start_col"], ci["end_col"], ci["start_row"], ci["end_row"],
        ci["chamfered_cells"], fixed_val, edge_index, iterate_cols
    )

    var quads: Array = []
    for local_x in range(grid_width):
        var t0      = float(local_x)     / grid_width
        var t1      = float(local_x + 1) / grid_width
        var p_left  := Vector2(lerpf(vA.x, vB.x, t0), lerpf(vA.z, vB.z, t0))
        var p_right := Vector2(lerpf(vA.x, vB.x, t1), lerpf(vA.z, vB.z, t1))
        var cr      = _get_col_row(local_x, fixed_val, edge_index, iterate_cols)

        for cell_y in range(total_cells_v):
            var y_bot = cell_y       * cell_height
            var y_top = (cell_y + 1) * cell_height
            quads.append({
                "local_x": local_x,  "local_y": cell_y,
                "grid_x":  cr[0],    "grid_z":  cr[1],
                "v1": Vector3(p_left.x,  y_bot, p_left.y),
                "v2": Vector3(p_right.x, y_bot, p_right.y),
                "v3": Vector3(p_right.x, y_top, p_right.y),
                "v4": Vector3(p_left.x,  y_top, p_left.y),
            })

    return {
        "quads": quads,
        "width": grid_width,
        "height": total_cells_v,
        "unavailable_edges":  availability["unavailable_edges"],
        "unavailable_points": availability["unavailable_points"]
    }

func get_facade_grid_for_floor(facade_edge_info: Dictionary, floor: int, is_core: bool = false) -> Dictionary:
    if facade_edge_info.is_empty():
        return {"quads": [], "width": 0, "height": 0, "unavailable_edges": {}, "unavailable_points": {}}

    var cell_x: int     = facade_edge_info["cell_x"]
    var cell_z: int     = facade_edge_info["cell_z"]
    var edge_index: int = facade_edge_info["edge_index"]

    var cluster = block.get_cluster_for_cell(cell_x, cell_z)
    if cluster == null:
        return {"quads": [], "width": 0, "height": 0, "unavailable_edges": {}, "unavailable_points": {}}

    if floor < 0 or floor >= cluster.get_floor_count():
        return {"quads": [], "width": 0, "height": 0, "unavailable_edges": {}, "unavailable_points": {}}

    var endpoints        := _get_edge_endpoints(facade_edge_info, is_core)
    var vA: Vector3       = endpoints[0]
    var vB: Vector3       = endpoints[1]
    var cells_per_floor   = block.get_cells_per_floor()
    var cell_height       = block.get_building_cell_height()
    var floor_y_bot       = floor * cells_per_floor * cell_height
    var iterate_cols      = (edge_index == 0 or edge_index == 2)
    var grid_width: int   = building_columns if iterate_cols else building_rows

    var ci = _get_core_and_chamfer_info(cell_x, cell_z, is_core)

    var fixed_val: int
    match edge_index:
        0: fixed_val = ci["start_row"] if is_core else 0
        1: fixed_val = ci["end_col"]   if is_core else building_columns - 1
        2: fixed_val = ci["end_row"]   if is_core else building_rows - 1
        3: fixed_val = ci["start_col"] if is_core else 0

    var availability = _build_unavailable_edges_and_points(
        grid_width, cells_per_floor,
        is_core, ci["start_col"], ci["end_col"], ci["start_row"], ci["end_row"],
        ci["chamfered_cells"], fixed_val, edge_index, iterate_cols
    )

    var quads: Array = []
    for local_x in range(grid_width):
        var t0      = float(local_x)     / grid_width
        var t1      = float(local_x + 1) / grid_width
        var p_left  := Vector2(lerpf(vA.x, vB.x, t0), lerpf(vA.z, vB.z, t0))
        var p_right := Vector2(lerpf(vA.x, vB.x, t1), lerpf(vA.z, vB.z, t1))
        var cr      = _get_col_row(local_x, fixed_val, edge_index, iterate_cols)

        for local_y in range(cells_per_floor):
            var y_bot = floor_y_bot + local_y       * cell_height
            var y_top = floor_y_bot + (local_y + 1) * cell_height
            quads.append({
                "local_x": local_x,  "local_y": local_y,
                "grid_x":  cr[0],    "grid_z":  cr[1],
                "floor":   floor,
                "v1": Vector3(p_left.x,  y_bot, p_left.y),
                "v2": Vector3(p_right.x, y_bot, p_right.y),
                "v3": Vector3(p_right.x, y_top, p_right.y),
                "v4": Vector3(p_left.x,  y_top, p_left.y),
            })

    return {
        "quads": quads,
        "width": grid_width,
        "height": cells_per_floor,
        "unavailable_edges":  availability["unavailable_edges"],
        "unavailable_points": availability["unavailable_points"]
    }

func get_random_facade_grid(edge_index: int, rng: RandomNumberGenerator, is_core: bool = false) -> Dictionary:
    var distorted_grid = block.get_distorted_grid()
    if distorted_grid == null:
        return {}

    var max_index = distorted_grid.columns if (edge_index == 0 or edge_index == 2) else distorted_grid.rows
    var cell_index = rng.randi_range(0, max_index - 1)

    var configs = {
        0: [cell_index, 0],
        1: [distorted_columns - 1, cell_index],
        2: [cell_index, distorted_rows - 1],
        3: [0, cell_index]
    }
    var c = configs[edge_index]
    var cluster = block.get_cluster_for_cell(c[0], c[1])
    if cluster == null:
        return {}

    var facade_info = get_facade_edge_info(edge_index, cell_index)
    if facade_info.is_empty():
        return {}

    var floor = rng.randi_range(0, cluster.get_floor_count() - 1)
    return get_facade_grid_for_floor(facade_info, floor, is_core)

func get_all_edges_random_facade_grids(rng: RandomNumberGenerator, is_core: bool = false) -> Array:
    var result: Array = []
    for edge_index in range(4):
        result.append(get_random_facade_grid(edge_index, rng, is_core))
    return result

func get_facade_edge_info(edge_index: int, cell_index: int) -> Dictionary:
    var distorted_grid = block.get_distorted_grid()
    if distorted_grid == null:
        return {}

    var configs = {
        0: [cell_index, 0,                    distorted_columns, 0, 1],
        1: [distorted_columns - 1, cell_index, distorted_rows,   1, 2],
        2: [cell_index, distorted_rows - 1,   distorted_columns, 2, 3],
        3: [0, cell_index,                    distorted_rows,    3, 0]
    }

    var config = configs[edge_index]
    if cell_index < 0 or cell_index >= config[2]:
        return {}

    var cell_vertices = distorted_grid.get_cell_vertices(config[0], config[1])
    if cell_vertices.size() != 4:
        return {}

    return {
        "edge_index": edge_index,
        "cell_index": cell_index,
        "cell_x":     config[0],
        "cell_z":     config[1],
        "vertices":   [cell_vertices[config[3]], cell_vertices[config[4]]]
    }
