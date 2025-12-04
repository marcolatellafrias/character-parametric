class_name RectangleSubdivider extends RefCounted

# Lados de un rectángulo
enum RectSide {
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3
}

# Estructura para representar un rectángulo en la grilla
class GridRectangle:
	var x: int
	var z: int
	var width: int
	var height: int
	var id: int
	
	func _init(p_x: int, p_z: int, p_width: int, p_height: int, p_id: int) -> void:
		x = p_x
		z = p_z
		width = p_width
		height = p_height
		id = p_id
	
	func get_aspect_ratio() -> float:
		var max_side = max(width, height)
		var min_side = min(width, height)
		if min_side == 0:
			return INF
		return float(max_side) / float(min_side)
	
	func get_max_dimension() -> int:
		return max(width, height)
	
	func can_split(min_size: int) -> bool:
		return width >= min_size * 2 or height >= min_size * 2

# Estructura para almacenar los offsets de un rectángulo
class RectangleOffsets:
	var north: int = 0
	var east: int = 0
	var south: int = 0
	var west: int = 0
	
	func _init(p_north: int = 0, p_east: int = 0, p_south: int = 0, p_west: int = 0) -> void:
		north = p_north
		east = p_east
		south = p_south
		west = p_west

# Parámetros de generación
var min_rectangle_size: int = 6
var max_aspect_ratio: float = 1.5
var max_rectangle_dimension: int = 12
var min_alley_offset: int = 1
var max_alley_offset: int = 2

# Estado
var rectangles: Array[GridRectangle] = []
var next_rectangle_id: int = 1
var random: RandomNumberGenerator = RandomNumberGenerator.new()

# Información del callejón
var first_split_position: int = -1
var first_split_is_horizontal: bool = false
var merged_rectangles: Dictionary = {}
var rectangle_offsets: Dictionary = {}

# Límites del área disponible
var available_min_x: int
var available_max_x: int
var available_min_z: int
var available_max_z: int


func _init() -> void:
	random.randomize()


# Configura el área disponible
func setup_area(min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	available_min_x = min_x
	available_max_x = max_x
	available_min_z = min_z
	available_max_z = max_z


# Genera rectángulos dividiendo iterativamente
func generate_rectangles(
	p_max_divisions: int = 4,
	p_min_size: int = 2,
	p_max_aspect_ratio: float = 1.5,
	p_max_dimension: int = 8,
	seed_value: int = -1
) -> Array[GridRectangle]:
	min_rectangle_size = p_min_size
	max_aspect_ratio = p_max_aspect_ratio
	max_rectangle_dimension = p_max_dimension
	
	rectangles.clear()
	merged_rectangles.clear()
	rectangle_offsets.clear()
	next_rectangle_id = 1
	first_split_position = -1
	
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	
	var start_x = available_min_x
	var start_z = available_min_z
	var width = available_max_x - available_min_x + 1
	var height = available_max_z - available_min_z + 1
	
	var initial_rect = GridRectangle.new(start_x, start_z, width, height, next_rectangle_id)
	next_rectangle_id += 1
	
	var pending_rects: Array[GridRectangle] = [initial_rect]
	var iterations = 0
	var max_iterations = p_max_divisions * 100
	var is_first_split = true
	
	while not pending_rects.is_empty() and iterations < max_iterations:
		iterations += 1
		
		var worst_rect_idx = _find_rectangle_to_split(pending_rects)
		var rect_to_split = pending_rects[worst_rect_idx]
		pending_rects.remove_at(worst_rect_idx)
		
		if not _should_split_rectangle(rect_to_split):
			rectangles.append(rect_to_split)
			continue
		
		var split_result = _split_rectangle(rect_to_split)
		
		if split_result.is_empty():
			rectangles.append(rect_to_split)
		else:
			if is_first_split:
				_record_first_split(rect_to_split, split_result)
				is_first_split = false
			
			pending_rects.append(split_result[0])
			pending_rects.append(split_result[1])
	
	for rect in pending_rects:
		rectangles.append(rect)
	
	_create_alley_connection()
	_generate_rectangle_offsets()
	
	return rectangles


func _find_rectangle_to_split(rects: Array[GridRectangle]) -> int:
	var worst_idx = 0
	var worst_score = _get_split_priority_score(rects[0])
	
	for i in range(1, rects.size()):
		var score = _get_split_priority_score(rects[i])
		if score > worst_score:
			worst_score = score
			worst_idx = i
	
	return worst_idx


func _get_split_priority_score(rect: GridRectangle) -> float:
	var score = 0.0
	
	var max_side = max(rect.width, rect.height)
	if max_side > max_rectangle_dimension:
		score += (max_side - max_rectangle_dimension) * 100.0
	
	var aspect_ratio = rect.get_aspect_ratio()
	if aspect_ratio > max_aspect_ratio:
		score += (aspect_ratio - max_aspect_ratio) * 10.0
	
	var area = rect.width * rect.height
	score += area * 0.1
	
	return score


func _should_split_rectangle(rect: GridRectangle) -> bool:
	if not rect.can_split(min_rectangle_size):
		return false
	
	if rect.width > max_rectangle_dimension or rect.height > max_rectangle_dimension:
		return true
	
	if rect.get_aspect_ratio() > max_aspect_ratio:
		return true
	
	var area = rect.width * rect.height
	var max_area = max_rectangle_dimension * max_rectangle_dimension
	if area > max_area:
		return true
	
	return false


func _split_rectangle(rect: GridRectangle) -> Array[GridRectangle]:
	var result: Array[GridRectangle] = []
	
	var divide_horizontally = rect.height > rect.width
	
	if divide_horizontally:
		if rect.height < min_rectangle_size * 2:
			return []
		
		var split_z = _find_valid_split(rect.z, rect.height, true)
		if split_z == -1:
			return []
		
		var height1 = split_z - rect.z
		var height2 = rect.height - height1
		
		var rect1 = GridRectangle.new(rect.x, rect.z, rect.width, height1, next_rectangle_id)
		next_rectangle_id += 1
		
		var rect2 = GridRectangle.new(rect.x, split_z, rect.width, height2, next_rectangle_id)
		next_rectangle_id += 1
		
		result.append(rect1)
		result.append(rect2)
	else:
		if rect.width < min_rectangle_size * 2:
			return []
		
		var split_x = _find_valid_split(rect.x, rect.width, false)
		if split_x == -1:
			return []
		
		var width1 = split_x - rect.x
		var width2 = rect.width - width1
		
		var rect1 = GridRectangle.new(rect.x, rect.z, width1, rect.height, next_rectangle_id)
		next_rectangle_id += 1
		
		var rect2 = GridRectangle.new(split_x, rect.z, width2, rect.height, next_rectangle_id)
		next_rectangle_id += 1
		
		result.append(rect1)
		result.append(rect2)
	
	return result


func _find_valid_split(start: int, size: int, is_horizontal: bool) -> int:
	const MAX_ATTEMPTS = 50
	
	for attempt in range(MAX_ATTEMPTS):
		var min_pos = start + min_rectangle_size
		var max_pos = start + size - min_rectangle_size
		
		if min_pos >= max_pos:
			return -1
		
		var split_pos = random.randi_range(min_pos, max_pos)
		
		var size1 = split_pos - start
		var size2 = size - size1
		
		if size1 >= min_rectangle_size and size2 >= min_rectangle_size:
			return split_pos
	
	return -1


func _record_first_split(original_rect: GridRectangle, split_rects: Array[GridRectangle]) -> void:
	first_split_is_horizontal = original_rect.height > original_rect.width
	
	if first_split_is_horizontal:
		first_split_position = split_rects[0].z + split_rects[0].height
	else:
		first_split_position = split_rects[0].x + split_rects[0].width


func _create_alley_connection() -> void:
	if first_split_position == -1:
		return
	
	var side1_rects = _find_rectangles_adjacent_to_alley(true)
	var side2_rects = _find_rectangles_adjacent_to_alley(false)
	
	if side1_rects.is_empty() or side2_rects.is_empty():
		return
	
	var valid_pairs = _find_valid_containment_pairs(side1_rects, side2_rects)
	
	if valid_pairs.is_empty():
		var rect1 = side1_rects[random.randi() % side1_rects.size()]
		var rect2 = _find_best_merge_candidate_by_overlap(rect1, side2_rects)
		
		if rect2 != null:
			merged_rectangles[rect1.id] = rect2.id
			merged_rectangles[rect2.id] = rect1.id
		return
	
	var chosen_pair = valid_pairs[random.randi() % valid_pairs.size()]
	var rect1 = chosen_pair[0]
	var rect2 = chosen_pair[1]
	
	merged_rectangles[rect1.id] = rect2.id
	merged_rectangles[rect2.id] = rect1.id


func _find_valid_containment_pairs(side1_rects: Array[GridRectangle], side2_rects: Array[GridRectangle]) -> Array:
	var valid_pairs = []
	
	for rect1 in side1_rects:
		for rect2 in side2_rects:
			if _does_edge_contain(rect1, rect2) or _does_edge_contain(rect2, rect1):
				valid_pairs.append([rect1, rect2])
	
	return valid_pairs


func _does_edge_contain(rect1: GridRectangle, rect2: GridRectangle) -> bool:
	if first_split_is_horizontal:
		var rect1_start = rect1.x
		var rect1_end = rect1.x + rect1.width
		var rect2_start = rect2.x
		var rect2_end = rect2.x + rect2.width
		
		return rect1_start <= rect2_start and rect1_end >= rect2_end
	else:
		var rect1_start = rect1.z
		var rect1_end = rect1.z + rect1.height
		var rect2_start = rect2.z
		var rect2_end = rect2.z + rect2.height
		
		return rect1_start <= rect2_start and rect1_end >= rect2_end


func _find_rectangles_adjacent_to_alley(first_side: bool) -> Array[GridRectangle]:
	var adjacent_rects: Array[GridRectangle] = []
	
	for rect in rectangles:
		var is_adjacent = false
		
		if first_split_is_horizontal:
			if first_side:
				is_adjacent = (rect.z + rect.height == first_split_position)
			else:
				is_adjacent = (rect.z == first_split_position)
		else:
			if first_side:
				is_adjacent = (rect.x + rect.width == first_split_position)
			else:
				is_adjacent = (rect.x == first_split_position)
		
		if is_adjacent:
			adjacent_rects.append(rect)
	
	return adjacent_rects


func _find_best_merge_candidate_by_overlap(rect1: GridRectangle, candidates: Array[GridRectangle]) -> GridRectangle:
	var best_candidate: GridRectangle = null
	var best_overlap = 0
	
	for rect2 in candidates:
		var overlap = _calculate_shared_edge_length(rect1, rect2)
		
		if overlap > best_overlap:
			best_overlap = overlap
			best_candidate = rect2
	
	return best_candidate


func _calculate_shared_edge_length(rect1: GridRectangle, rect2: GridRectangle) -> int:
	if first_split_is_horizontal:
		var x1_start = rect1.x
		var x1_end = rect1.x + rect1.width
		var x2_start = rect2.x
		var x2_end = rect2.x + rect2.width
		
		var overlap_start = max(x1_start, x2_start)
		var overlap_end = min(x1_end, x2_end)
		
		return max(0, overlap_end - overlap_start)
	else:
		var z1_start = rect1.z
		var z1_end = rect1.z + rect1.height
		var z2_start = rect2.z
		var z2_end = rect2.z + rect2.height
		
		var overlap_start = max(z1_start, z2_start)
		var overlap_end = min(z1_end, z2_end)
		
		return max(0, overlap_end - overlap_start)


func _generate_rectangle_offsets() -> void:
	rectangle_offsets.clear()
	
	for rect in rectangles:
		var offsets = RectangleOffsets.new()
		
		var blocked_side = _get_merged_side(rect)
		
		var is_north_boundary = (rect.z == available_min_z)
		var is_south_boundary = (rect.z + rect.height - 1 == available_max_z)
		var is_west_boundary = (rect.x == available_min_x)
		var is_east_boundary = (rect.x + rect.width - 1 == available_max_x)
		
		if blocked_side != RectSide.NORTH and not is_north_boundary:
			offsets.north = random.randi_range(min_alley_offset, max_alley_offset)
		
		if blocked_side != RectSide.EAST and not is_east_boundary:
			offsets.east = random.randi_range(min_alley_offset, max_alley_offset)
		
		if blocked_side != RectSide.SOUTH and not is_south_boundary:
			offsets.south = random.randi_range(min_alley_offset, max_alley_offset)
		
		if blocked_side != RectSide.WEST and not is_west_boundary:
			offsets.west = random.randi_range(min_alley_offset, max_alley_offset)
		
		rectangle_offsets[rect.id] = offsets


func _get_merged_side(rect: GridRectangle) -> int:
	if not is_rectangle_merged(rect.id):
		return -1
	
	if first_split_is_horizontal:
		if rect.z + rect.height == first_split_position:
			return RectSide.SOUTH
		elif rect.z == first_split_position:
			return RectSide.NORTH
	else:
		if rect.x + rect.width == first_split_position:
			return RectSide.EAST
		elif rect.x == first_split_position:
			return RectSide.WEST
	
	return -1


# Métodos públicos de consulta
func get_rectangle_offsets(rect_id: int) -> RectangleOffsets:
	return rectangle_offsets.get(rect_id, RectangleOffsets.new())


func get_rectangle_bounds_with_offset(rect: GridRectangle) -> Dictionary:
	var offsets = get_rectangle_offsets(rect.id)
	
	return {
		"x_min": rect.x + offsets.west,
		"x_max": rect.x + rect.width - offsets.east,
		"z_min": rect.z + offsets.north,
		"z_max": rect.z + rect.height - offsets.south
	}


func is_rectangle_merged(rect_id: int) -> bool:
	return rect_id in merged_rectangles


func get_merged_with(rect_id: int) -> int:
	return merged_rectangles.get(rect_id, -1)
