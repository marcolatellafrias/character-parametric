class_name BridgeGridHelper extends RefCounted

# ============================================================
# BridgeGridHelper — Documentación de sistemas de coordenadas
# ============================================================
#
# DISTORTED GRID — Edges y celdas de fachada
# ------------------------------------------------------------
# La distorted grid es una grilla de (columns x rows) celdas
# que cubre la manzana. Los 4 edges de fachada son:
#
#   Edge 0 (BOTTOM): celdas [0..columns-1] en z=0
#   Edge 1 (RIGHT):  celdas [0..rows-1]    en x=columns-1
#   Edge 2 (TOP):    celdas [0..columns-1] en z=rows-1
#   Edge 3 (LEFT):   celdas [0..rows-1]    en x=0
#
# Los edges coinciden con los edges del face del grafo:
#   face[0]→face[1] = edge 0, face[1]→face[2] = edge 1, etc.
#
# WINDING ORDER DE CELDAS DE LA DISTORTED GRID:
# Cada celda tiene 4 vértices numerados así (vista desde arriba):
#
#   3 ── 2
#   │    │
#   0 ── 1
#
#   v0 = bottom-left, v1 = bottom-right
#   v2 = top-right,   v3 = top-left
#
# get_facade_edge_info devuelve "vertices": [vA, vB] donde
# vA y vB son los dos vértices del lado exterior de la celda:
#   Edge 0: v0, v1  (lado bottom de la celda)
#   Edge 1: v1, v2  (lado right  de la celda)
#   Edge 2: v2, v3  (lado top    de la celda)
#   Edge 3: v3, v0  (lado left   de la celda)
#
# ============================================================
# BUILDING GRID — Módulos dentro de cada celda distorsionada
# ------------------------------------------------------------
# Cada celda de la distorted grid contiene un BuildingModule
# con su propia subgrilla de (building_columns x building_rows).
# Los ejes son: x = columnas (horizontal), z = filas (profundidad).
#
# get_building_edges_from_facade recorre SIEMPRE la subgrilla
# completa (0..building_columns-1 o 0..building_rows-1).
# Cuando is_core=true, la fila/columna fija usa el offset del
# core (start_row para edge 0, end_col para edge 1, etc.) y
# las celdas fuera de [start_col..end_col] / [start_row..end_row]
# se marcan como available=false.
#
# ============================================================
# VERTICAL GRID — Grilla 2D de quads de fachada
# ============================================================
# Ambas grillas (sidewalk e is_core) tienen IGUAL tamaño en
# width y height. La diferencia es la posición 3D de los quads
# (offset) y la presencia de "unavailable_cells".
#
# "unavailable_cells" es un Dictionary con claves "local_x_local_y"
# cuyo valor es true. Un rect que incluye alguna de estas celdas
# no es válido.
#
# Cada quad tiene 4 vértices con este winding order
# (vista desde el exterior del edificio):
#
#   v4 ── v3
#   │      │
#   v1 ── v2
#
#   v1 = bottom-left,  v2 = bottom-right
#   v3 = top-right,    v4 = top-left
#
# ============================================================
# FACADE RECT — Rectángulo sobre la fachada
# ============================================================
# get_random_facade_rect y get_opposite_facade_rect devuelven
# un Array[Vector3] de 4 vértices con este orden:
#
#   3 ── 2
#   │    │
#   0 ── 1
#
#   [0] = bottom-left  (quad_bl["v1"])
#   [1] = bottom-right (quad_br["v2"])
#   [2] = top-right    (quad_tr["v3"])
#   [3] = top-left     (quad_tl["v4"])
#
# "bottom" = y más bajo, "left/right" = desde exterior mirando
# hacia el edificio, "top" = y más alto.
#
# ============================================================
# CORRESPONDENCIA ENTRE RECT FUENTE Y RECT OPUESTO
# ============================================================
# El rect opuesto puede estar invertido horizontalmente.
# needs_flip = true → se intercambian v1↔v2 y v4↔v3.
#
# ============================================================

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

func _get_chamfered_cells(building_module: BuildingModule) -> Dictionary:
    var chamfered: Dictionary = {}
    var chamfers = building_module.get_chamfers()
    var cols = building_columns
    var rows_ = building_rows

    for vertex_index in chamfers:
        var cv = chamfers[vertex_index]
        var c1: int = cv[0]
        var c2: int = cv[1]

        var x_range: Array
        var z_range: Array

        match vertex_index:
            0:  # BL
                x_range = range(0, c1)
                z_range = range(0, c2)
            1:  # BR
                x_range = range(cols - c1, cols)
                z_range = range(0, c2)
            2:  # TR
                x_range = range(cols - c1, cols)
                z_range = range(rows_ - c2, rows_)
            3:  # TL
                x_range = range(0, c1)
                z_range = range(rows_ - c2, rows_)

        for x in x_range:
            for z in z_range:
                chamfered["%d_%d" % [x, z]] = true

    return chamfered

func get_building_edges_from_facade(facade_edge_info: Dictionary, is_core: bool = false) -> Array:
    var edges: Array = []
    
    if facade_edge_info.is_empty():
        return edges
    
    var building_module = block.get_building_module(facade_edge_info["cell_x"], facade_edge_info["cell_z"])
    if building_module == null:
        return edges
    
    var chamfered_cells = _get_chamfered_cells(building_module)
    
    var core_info = building_module.get_core_info() if is_core else {}
    var start_col: int = core_info.get("min_x", 0)
    var end_col: int   = core_info.get("max_x", building_columns - 1)
    var start_row: int = core_info.get("min_z", 0)
    var end_row: int   = core_info.get("max_z", building_rows - 1)
    
    var fixed_bottom = start_row if is_core else 0
    var fixed_top    = end_row   if is_core else building_rows - 1
    var fixed_right  = end_col   if is_core else building_columns - 1
    var fixed_left   = start_col if is_core else 0
    
    var configs = {
        0: [0, 1, true,  fixed_bottom],
        1: [1, 2, false, fixed_right],
        2: [2, 3, true,  fixed_top],
        3: [3, 0, false, fixed_left]
    }
    
    var config = configs[facade_edge_info["edge_index"]]
    var iterate_cols: bool = config[2]
    var fixed_val: int = config[3]
    var range_vals = range(0, building_columns) if iterate_cols else range(0, building_rows)
    
    for i in range_vals:
        var col: int = i         if iterate_cols else fixed_val
        var row: int = fixed_val if iterate_cols else i
        var verts = building_module.get_cell_vertices(col, row)
        
        var available: bool = true
        if is_core:
            available = col >= start_col and col <= end_col and row >= start_row and row <= end_row
        
        if "%d_%d" % [col, row] in chamfered_cells:
            available = false
        
        if verts.size() == 4:
            edges.append({
                "v1": verts[config[0]],
                "v2": verts[config[1]],
                "grid_x": col,
                "grid_z": row,
                "available": available
            })
    
    return edges

func get_vertical_grid_from_facade(facade_edge_info: Dictionary, is_core: bool = false) -> Dictionary:
    if facade_edge_info.is_empty():
        return {"quads": [], "width": 0, "height": 0, "unavailable_cells": {}}
    
    var cell_x = facade_edge_info["cell_x"]
    var cell_z = facade_edge_info["cell_z"]
    
    var cluster = block.get_cluster_for_cell(cell_x, cell_z)
    if cluster == null:
        return {"quads": [], "width": 0, "height": 0, "unavailable_cells": {}}
    
    var floor_count = cluster.get_floor_count()
    var cells_per_floor = block.get_cells_per_floor()
    var cell_height = block.get_building_cell_height()
    var total_cells_vertical = floor_count * cells_per_floor
    var base_edges = get_building_edges_from_facade(facade_edge_info, is_core)
    
    var quads: Array = []
    var unavailable_cells: Dictionary = {}
    var edge_index = 0
    
    for edge in base_edges:
        var edge_available: bool = edge.get("available", true)
        
        for cell_y in range(total_cells_vertical):
            var y_bottom = cell_y * cell_height
            var y_top = (cell_y + 1) * cell_height
            
            var v1 = Vector3(edge["v1"].x, y_bottom, edge["v1"].z)
            var v2 = Vector3(edge["v2"].x, y_bottom, edge["v2"].z)
            var v3 = Vector3(edge["v2"].x, y_top,    edge["v2"].z)
            var v4 = Vector3(edge["v1"].x, y_top,    edge["v1"].z)
            
            quads.append({
                "local_x":   edge_index,
                "local_y":   cell_y,
                "grid_x":    edge["grid_x"],
                "grid_z":    edge["grid_z"],
                "available": edge_available,
                "v1": v1, "v2": v2, "v3": v3, "v4": v4
            })
            
            if not edge_available:
                unavailable_cells["%d_%d" % [edge_index, cell_y]] = true
        
        edge_index += 1
    
    var grid_width = base_edges.size()
    print("[BridgeGridHelper] mode=%s edge=%d cell=(%d,%d) columns=%d" % [
        "core" if is_core else "sidewalk",
        facade_edge_info["edge_index"],
        cell_x, cell_z,
        grid_width
    ])

    return {
        "quads":             quads,
        "width":             grid_width,
        "height":            total_cells_vertical,
        "unavailable_cells": unavailable_cells
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

func _rect_has_unavailable_cells(vgrid: Dictionary, local_x: int, local_y: int, size: Vector2i) -> bool:
    var unavailable: Dictionary = vgrid.get("unavailable_cells", {})
    if unavailable.is_empty():
        return false
    for dx in range(size.x):
        for dy in range(size.y):
            if "%d_%d" % [local_x + dx, local_y + dy] in unavailable:
                return true
    return false

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
    
    if _rect_has_unavailable_cells(vgrid, local_x, local_y, size):
        return {}
    
    var quad_bl = get_quad_at(vgrid, local_x, local_y)
    var quad_br = get_quad_at(vgrid, local_x + size.x - 1, local_y)
    var quad_tr = get_quad_at(vgrid, local_x + size.x - 1, local_y + size.y - 1)
    var quad_tl = get_quad_at(vgrid, local_x, local_y + size.y - 1)
    
    if quad_bl.is_empty() or quad_br.is_empty() or quad_tr.is_empty() or quad_tl.is_empty():
        return {}
    
    return {
        "verts":      [quad_bl["v1"], quad_br["v2"], quad_tr["v3"], quad_tl["v4"]],
        "edge_index": edge_index,
        "cell_index": cell_index,
        "pos_x":      local_x,
        "pos_y":      local_y,
        "size":       size,
        "is_core":    is_core
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
    
    var current_cell_0  = get_facade_edge_info(edge_index, 0)
    var neighbor_cell_0 = neighbor_helper.get_facade_edge_info(mirrored_edge_index, 0)
    var neighbor_cell_last = neighbor_helper.get_facade_edge_info(mirrored_edge_index, max_index - 1)
    
    if current_cell_0.is_empty() or neighbor_cell_0.is_empty() or neighbor_cell_last.is_empty():
        return {}
    
    var current_origin: Vector3  = current_cell_0["vertices"][0]
    var neighbor_origin: Vector3 = neighbor_cell_0["vertices"][0]
    var neighbor_end: Vector3    = neighbor_cell_last["vertices"][0]
    
    var needs_flip: bool = current_origin.distance_to(neighbor_origin) > current_origin.distance_to(neighbor_end)
    var mirrored_cell_index = (max_index - 1 - cell_index) if needs_flip else cell_index
    mirrored_cell_index = clamp(mirrored_cell_index, 0, max_index - 1)
    
    var facade_info = neighbor_helper.get_facade_edge_info(mirrored_edge_index, mirrored_cell_index)
    if facade_info.is_empty():
        return {}
    
    return {
        "facade_info":          facade_info,
        "neighbor_helper":      neighbor_helper,
        "neighbor_face_idx":    neighbor_face_idx,
        "mirrored_edge_index":  mirrored_edge_index,
        "mirrored_cell_index":  mirrored_cell_index,
        "needs_flip":           needs_flip
    }

func get_opposite_facade_rect(edge_index: int, cell_index: int, size: Vector2i, pos_x: int, pos_y: int, is_core: bool = false) -> Array[Vector3]:
    var mirrored = get_mirrored_facade_info(edge_index, cell_index, is_core)
    if mirrored.is_empty():
        return []
    
    var neighbor_helper: BridgeGridHelper = mirrored["neighbor_helper"]
    var facade_info: Dictionary           = mirrored["facade_info"]
    var needs_flip: bool                  = mirrored["needs_flip"]
    
    var vgrid = neighbor_helper.get_vertical_grid_from_facade(facade_info, is_core)
    
    if vgrid["width"] < size.x or vgrid["height"] < size.y:
        return []
    
    var mirrored_x = (vgrid["width"] - pos_x - size.x) if needs_flip else pos_x
    var mirrored_y = pos_y
    
    if mirrored_x < 0 or mirrored_x + size.x > vgrid["width"]:
        return []
    if mirrored_y < 0 or mirrored_y + size.y > vgrid["height"]:
        return []
    
    if neighbor_helper._rect_has_unavailable_cells(vgrid, mirrored_x, mirrored_y, size):
        return []
    
    var quad_bl = neighbor_helper.get_quad_at(vgrid, mirrored_x, mirrored_y)
    var quad_br = neighbor_helper.get_quad_at(vgrid, mirrored_x + size.x - 1, mirrored_y)
    var quad_tr = neighbor_helper.get_quad_at(vgrid, mirrored_x + size.x - 1, mirrored_y + size.y - 1)
    var quad_tl = neighbor_helper.get_quad_at(vgrid, mirrored_x, mirrored_y + size.y - 1)
    
    if quad_bl.is_empty() or quad_br.is_empty() or quad_tr.is_empty() or quad_tl.is_empty():
        return []
    
    if needs_flip:
        return [quad_br["v2"], quad_bl["v1"], quad_tl["v4"], quad_tr["v3"]]
    else:
        return [quad_bl["v1"], quad_br["v2"], quad_tr["v3"], quad_tl["v4"]]

static func is_facade_edge_inverted(edge_index: int) -> bool:
    return edge_index == 2 or edge_index == 3
