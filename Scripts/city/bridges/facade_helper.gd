class_name FacadeHelper
extends RefCounted

# Edge indices: 0=north, 1=east, 2=south, 3=west
# Edges 2 and 3 have their cells iterated in reverse order by _get_facade_cells.
# The "reversed" flag (from face node order vs graph node order) may flip the
# cell array again. The combination determines whether building cell indices
# within a module run in the same or opposite direction as the facade order.


static func get_building_dim(edge_idx: int, block: BlockGenerator) -> int:
	if edge_idx == 0 or edge_idx == 2:
		return block.get_building_columns()
	return block.get_building_rows()


# Whether facade-order cell indices need reversal to match building grid coords.
# Edges 2/3 naturally iterate backwards; the reversed flag un-reverses them.
# XOR: reversal needed when exactly one of these is true.
static func needs_cell_reversal(edge_idx: int, is_reversed: bool) -> bool:
	return (edge_idx >= 2) != is_reversed


# Convert facade-local cell range to building grid rectangle for a given edge.
# local_start/local_end: cell indices in facade order within one distorted grid cell.
# Returns {"bx_min", "bx_max", "bz_min", "bz_max"} or empty dict if invalid.
static func facade_to_grid_rect(edge_idx: int, is_reversed: bool,
		local_start: int, local_end: int, core: Dictionary,
		module: BuildingModule, building_dim: int) -> Dictionary:
	var along_min: int; var along_max: int
	if needs_cell_reversal(edge_idx, is_reversed):
		along_min = building_dim - 1 - local_end
		along_max = building_dim - 1 - local_start
	else:
		along_min = local_start
		along_max = local_end

	var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
	match edge_idx:
		0:
			bx_min = along_min; bx_max = along_max
			bz_min = 0; bz_max = core["min_z"] - 1
		1:
			bz_min = along_min; bz_max = along_max
			bx_min = core["max_x"] + 1; bx_max = module.columns - 1
		2:
			bx_min = along_min; bx_max = along_max
			bz_min = core["max_z"] + 1; bz_max = module.rows - 1
		3:
			bz_min = along_min; bz_max = along_max
			bx_min = 0; bx_max = core["min_x"] - 1

	if bx_min > bx_max or bz_min > bz_max:
		return {}
	return {"bx_min": bx_min, "bx_max": bx_max, "bz_min": bz_min, "bz_max": bz_max}

## ── LA REGLA DE ORO DE LAS FACHADAS ─────────────────────────────────────────────────────────────
##
## Todo lo que se apoya en una fachada tiene que salir de la MISMA definición de "piso N" que la malla que
## se ve: el quad del piso 0, inclinado con el terreno, trasladado en Y. Es lo que hacen `point_at_f` y
## todo lo construido sobre él (`get_region_vertices`, `get_facade_quad`, `facade_span_quad`, y
## `ModulePlacer`, por donde van los extremos de puente).
##
## Los pisos son paralelos, así que extruir en vertical entre dos alturas también aterriza exacto. Lo que
## NO se puede es sacar la posición de otra fuente —las esquinas de la manzana, una altura escalar, un
## plano inventado—, porque esa fuente no está obligada a coincidir con la cara del edificio.
##
## Los CONECTORES entre edificios (el tramo del medio de un puente) no viven en ninguna grilla: unen dos
## caras que sí salen de una. Para eso está `facade_span_quad`, que les da las dos caras reales. Un
## conector nunca inventa un plano propio.

## Las dos esquinas del quad que dan A LA CALLE, en orden de recorrido de la fachada.
##
## `get_region_vertices` devuelve [BL, BR, TR, TL] = (u0,v0), (u1,v0), (u1,v1), (u0,v1). Qué lado mira a
## la calle lo fija el borde, comparando con los rectángulos de `facade_to_grid_rect`: el 0 se apoya en
## v0, el 1 en u1, el 2 en v1 y el 3 en u0.
static func street_corner_indices(edge_idx: int, is_reversed: bool) -> Array[int]:
	var pair: Array[int]
	match edge_idx:
		0: pair = [0, 1]
		1: pair = [1, 2]
		2: pair = [3, 2]
		_: pair = [0, 3]
	if needs_cell_reversal(edge_idx, is_reversed):
		return [pair[1], pair[0]]
	return pair


## LA CARA DONDE SE ENGANCHA UN CONECTOR: el quad vertical al borde de la calle, de punta a punta del
## tramo, con su borde de abajo en `index_bottom` y el de arriba en `index_top`, los dos sampleados de la
## grilla.
##
## Sale torcido, y tiene que salir torcido: así es la fachada. Un conector que se enganche acá hereda esa
## torsión y queda al ras. Devuelve [inicio_abajo, fin_abajo, fin_arriba, inicio_arriba], que es el orden
## que `DebugUtil.get_skewed_cube_from_planes_geometry` empareja vértice a vértice.
##
## El tramo puede cruzar varias celdas de la distorted grid; acá se toman SOLO las dos puntas, así que el
## quiebre intermedio queda dentro del conector y no en la cara.
static func facade_span_quad(block: BlockGenerator, edge_idx: int, is_reversed: bool,
		facade_cells: Array, cell_start: int, cell_end: int,
		index_bottom: int, index_top: int) -> Array[Vector3]:
	var start_pair := _facade_edge_point(block, edge_idx, is_reversed, facade_cells,
			cell_start, true, index_bottom, index_top)
	var end_pair := _facade_edge_point(block, edge_idx, is_reversed, facade_cells,
			cell_end, false, index_bottom, index_top)
	if start_pair.is_empty() or end_pair.is_empty():
		return []
	return [start_pair[0], end_pair[0], end_pair[1], start_pair[1]]


## Un punto del borde de la calle, a las dos alturas. `at_span_start` elige cuál de las dos esquinas de la
## celda se usa: la del arranque del tramo o la del final.
static func _facade_edge_point(block: BlockGenerator, edge_idx: int, is_reversed: bool,
		facade_cells: Array, cell_index: int, at_span_start: bool,
		index_bottom: int, index_top: int) -> Array[Vector3]:
	var building_dim := get_building_dim(edge_idx, block)
	if building_dim <= 0:
		return []
	var ci: int = cell_index / building_dim
	if ci < 0 or ci >= facade_cells.size():
		return []
	var coord: Vector2i = facade_cells[ci]
	var module: BuildingModule = block.get_building_module(coord.x, coord.y, 0)
	if module == null:
		return []
	var local: int = clampi(cell_index - ci * building_dim, 0, building_dim - 1)
	var rect := facade_to_grid_rect(edge_idx, is_reversed, local, local,
			module.get_core_info(), module, building_dim)
	if rect.is_empty():
		return []

	var bottom := module.get_region_vertices(rect["bx_min"], rect["bx_max"],
			rect["bz_min"], rect["bz_max"], index_bottom)
	var top := module.get_region_vertices(rect["bx_min"], rect["bx_max"],
			rect["bz_min"], rect["bz_max"], index_top)
	if bottom.size() != 4 or top.size() != 4:
		return []
	var corners := street_corner_indices(edge_idx, is_reversed)
	var which: int = corners[0] if at_span_start else corners[1]
	return [bottom[which], top[which]]


# Convert a building cell along-index to a global mask index.
# Edges 2/3 reverse the mapping within each distorted grid cell.
static func along_to_mask_index(edge_idx: int, ci: int, along: int, building_dim: int) -> int:
	if edge_idx <= 1:
		return ci * building_dim + along
	return ci * building_dim + (building_dim - 1 - along)
