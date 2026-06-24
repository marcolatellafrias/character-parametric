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




# Get the along_min, along_max, and depth_pos for facade mask building.
# Used by _build_facade_mask in grafo_ciudad.gd.
static func get_mask_ranges(edge_idx: int, core: Dictionary) -> Dictionary:
	match edge_idx:
		0: return {"along_min": core["min_x"], "along_max": core["max_x"], "depth": core["min_z"]}
		1: return {"along_min": core["min_z"], "along_max": core["max_z"], "depth": core["max_x"]}
		2: return {"along_min": core["min_x"], "along_max": core["max_x"], "depth": core["max_z"]}
		3: return {"along_min": core["min_z"], "along_max": core["max_z"], "depth": core["min_x"]}
	return {}


# Convert a building cell along-index to bx/bz for mask building.
static func along_to_bx_bz(edge_idx: int, along: int, depth: int) -> Vector2i:
	if edge_idx == 0 or edge_idx == 2:
		return Vector2i(along, depth)
	return Vector2i(depth, along)


# Convert a building cell along-index to a global mask index.
# Edges 2/3 reverse the mapping within each distorted grid cell.
static func along_to_mask_index(edge_idx: int, ci: int, along: int, building_dim: int) -> int:
	if edge_idx <= 1:
		return ci * building_dim + along
	return ci * building_dim + (building_dim - 1 - along)
