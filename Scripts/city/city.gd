extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(40, 40)
@export var min_distance: float = 5.5
@export var rejection_samples: int = 40
@export var generation_seed: int = 12345

@export_group("Barrios")
@export var num_neighborhoods: int = 6
@export var show_neighborhoods: bool = true

@export_group("Suavizado")
@export var smoothing_steps: int = 50

@export_group("Visualización General")
@export var show_nodes: bool = true
@export var node_radius: float = 0.08
@export var normal_node_color: Color = Color.CHARTREUSE
@export var boundary_node_color: Color = Color.ORANGE_RED
@export var show_inscribed_squares: bool = false
@export var inscribed_square_color: Color = Color.RED
@export var inscribed_square_width: float = 0.03
@export var auto_generate: bool = true

@export_group("Tipos de Calles")
@export var num_large_streets: int = 3
@export var num_small_streets: int = 10

@export_subgroup("Calles Pequeñas (Tipo 0)")
@export var small_street_color: Color = Color.DEEP_PINK
@export var small_street_width: float = 0.01

@export_subgroup("Calles Medianas (Tipo 1)")
@export var medium_street_color: Color = Color.WHITE
@export var medium_street_width: float = 0.02

@export_subgroup("Calles Grandes (Tipo 2)")
@export var large_street_color: Color = Color.GREEN
@export var large_street_width: float = 0.04

@export_subgroup("Calles Límite (Tipo -1)")
@export var boundary_street_color: Color = Color.ORANGE_RED
@export var boundary_street_width: float = 0.05

@export_group("Túneles")
@export var num_small_tunnels: int = 2
@export var num_large_tunnels: int = 1
@export var tunnel_min_length: int = 2
@export var tunnel_max_length: int = 6
@export var tunnel_max_angle_degrees: float = 30.0
@export var tunnel_min_gap: int = 3

@export_subgroup("Túneles Pequeños (Tipo 3)")
@export var small_tunnel_color: Color = Color.CYAN
@export var small_tunnel_width: float = 0.015

@export_subgroup("Túneles Grandes (Tipo 4)")
@export var large_tunnel_color: Color = Color.BLUE
@export var large_tunnel_width: float = 0.045

@export_group("Puntos de Interés")
@export var num_delivery_facilities: int = 5
@export var delivery_points_per_block: int = 3
@export var num_gas_stations: int = 10
@export var num_stores: int = 15

@export_group("Grillas de Manzanas")
@export var block_grid_rows: int = 100
@export var block_grid_columns: int = 100
@export var block_grid_floors: int = 1
@export var block_cells_per_floor: int = 30
@export var show_floor_planes: bool = true
@export var floor_plane_color: Color = Color(0.0, 0.5, 1.0, 0.3)

@export_group("Rectángulos")
@export var show_rectangles: bool = true
@export var rect_saturation: float = 0.8
@export var rect_brightness: float = 0.9
@export var rect_alpha: float = 0.8
@export var rect_max_divisions: int = 3
@export var rect_min_size: int = 14
@export var rect_max_aspect_ratio: float = 1.8
@export var rect_max_dimension: int = 18

@export_group("Carriles")
@export var show_lanes: bool = true
@export var lane_color: Color = Color.YELLOW
@export var lane_width: float = 0.02

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphCityGenerator = null
var neighborhood_colors: Dictionary = {}
var rectangle_colors: Dictionary = {}

# ============================================
# INICIALIZACIÓN
# ============================================
func _ready() -> void:
	if auto_generate:
		generate_and_visualize()

# ============================================
# GENERACIÓN Y VISUALIZACIÓN
# ============================================
func generate_and_visualize() -> void:
	clear_visualization()
	generate_graph()
	visualize_graph()

func generate_graph() -> void:
	generator = GraphCityGenerator.new()
	generator.generate_city_graph(
		smoothing_steps,
		region_size,
		min_distance,
		rejection_samples,
		generation_seed,
		num_neighborhoods,
		num_large_streets,
		num_small_streets,
		num_small_tunnels,
		num_large_tunnels,
		tunnel_min_length,
		tunnel_max_length,
		tunnel_max_angle_degrees,
		tunnel_min_gap,
		block_grid_rows,
		block_grid_columns,
		block_grid_floors,
		block_cells_per_floor,
		rect_max_divisions,
		rect_min_size,
		rect_max_aspect_ratio,
		rect_max_dimension,
	)
	
	_generate_neighborhood_colors()
	_generate_rectangle_colors()

func _generate_neighborhood_colors() -> void:
	neighborhood_colors.clear()
	seed(generation_seed)
	
	var neighborhood_saturation: float = 0.3
	var neighborhood_brightness: float = 0.3
	var neighborhood_alpha: float = 0.7
	
	for i in range(num_neighborhoods):
		var hue = randf()
		neighborhood_colors[i] = Color.from_hsv(hue, neighborhood_saturation, neighborhood_brightness, neighborhood_alpha)

func _generate_rectangle_colors() -> void:
	rectangle_colors.clear()
	
	var golden_ratio_conjugate = 0.618033988749895
	var hue = randf()
	
	var all_block_faces = generator.get_all_block_faces()
	var total_rectangles = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block != null:
			var rectangles = block.get_rectangles()
			total_rectangles += rectangles.size()
	
	var use_uniform_distribution = total_rectangles < 20
	var hue_step = 1.0 / total_rectangles if use_uniform_distribution else golden_ratio_conjugate
	
	var rect_index = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue
		
		var rectangles = block.get_rectangles()
		for rect in rectangles:
			if use_uniform_distribution:
				hue = fmod(rect_index * hue_step, 1.0)
			else:
				hue = fmod(hue + golden_ratio_conjugate, 1.0)
			
			var saturation = rect_saturation + randf_range(-0.1, 0.1)
			saturation = clamp(saturation, 0.3, 0.5)
			
			var brightness = rect_brightness + randf_range(-0.1, 0.1)
			brightness = clamp(brightness, 0.3, 0.6)
			
			rectangle_colors[rect.id] = Color.from_hsv(hue, saturation, brightness, rect_alpha)
			rect_index += 1
	
	print("[Visualizer] Generados %d colores distintos para rectángulos" % total_rectangles)

func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return
	
	if show_inscribed_squares:
		_visualize_inscribed_squares()
	
	_visualize_streets()
	
	if show_rectangles:
		_visualize_rectangles()
	
	if show_lanes:
		_visualize_lanes()
	
	if show_nodes:
		_visualize_nodes()

# ============================================
# VISUALIZACIÓN DE BARRIOS
# ============================================
func _visualize_neighborhoods() -> void:
	for face_idx in range(generator.plain_graph.faces.size()):
		var face = generator.plain_graph.faces[face_idx]
		var neighborhood_id = generator.get_neighborhood_for_face(face_idx)
		
		if neighborhood_id == -1:
			continue
		
		var color = neighborhood_colors.get(neighborhood_id, Color.GRAY)
		
		var vertices: Array[Vector3] = []
		for idx in face:
			vertices.append(generator.plain_graph.points[idx])
		
		if vertices.size() >= 3:
			_visualize_face_as_planes(vertices, color)

func _visualize_face_as_planes(vertices: Array[Vector3], color: Color) -> void:
	if vertices.size() == 4:
		var plane = DebugUtil.create_debug_plane(
			vertices[0],
			vertices[1],
			vertices[2],
			vertices[3],
			color
		)
		add_child(plane)
	
	elif vertices.size() == 3:
		var plane = DebugUtil.create_debug_plane(
			vertices[0],
			vertices[1],
			vertices[2],
			vertices[2],
			color
		)
		add_child(plane)
	
	elif vertices.size() > 4:
		var center = Vector3.ZERO
		for v in vertices:
			center += v
		center /= vertices.size()
		
		for i in range(vertices.size()):
			var next_i = (i + 1) % vertices.size()
			var plane = DebugUtil.create_debug_plane(
				center,
				vertices[i],
				vertices[next_i],
				vertices[next_i],
				color
			)
			add_child(plane)

# ============================================
# VISUALIZACIÓN DE CALLES
# ============================================
func _visualize_streets() -> void:
	for edge in generator.plain_graph.edges:
		var p1 = generator.plain_graph.points[edge[0]]
		var p2 = generator.plain_graph.points[edge[1]]
		
		var street_type = generator.get_street_type(edge[0], edge[1])
		
		var color: Color
		var width: float
		
		match street_type:
			-1:
				color = boundary_street_color
				width = boundary_street_width
			0:
				color = small_street_color
				width = small_street_width
			1:
				color = medium_street_color
				width = medium_street_width
			2:
				color = large_street_color
				width = large_street_width
			3:
				color = small_tunnel_color
				width = small_tunnel_width
			4:
				color = large_tunnel_color
				width = large_tunnel_width
			_:
				color = medium_street_color
				width = medium_street_width
		
		var line = DebugUtil.create_debug_line_to_from(p1, p2, color, width)
		add_child(line)

# ============================================
# VISUALIZACIÓN DE NODOS
# ============================================
func _visualize_nodes() -> void:
	for node_idx in range(generator.plain_graph.points.size()):
		var point = generator.plain_graph.points[node_idx]
		var node_type = generator.plain_graph.node_types.get(node_idx, 0)
		
		var color: Color
		if node_type == 1:
			color = boundary_node_color
		else:
			color = normal_node_color
		
		var sphere = DebugUtil.create_debug_sphere(color, node_radius)
		sphere.position = point
		add_child(sphere)

# ============================================
# VISUALIZACIÓN DE CUADRADOS INSCRITOS
# ============================================
func _visualize_inscribed_squares() -> void:
	for face_idx in range(generator.plain_graph.faces.size()):
		var inscribed = generator.plain_graph.get_inscribed_square_for_face(face_idx, true)
		
		if inscribed.is_empty():
			continue
		
		for i in range(inscribed.size()):
			var next_i = (i + 1) % inscribed.size()
			var line = DebugUtil.create_debug_line_to_from(
				inscribed[i],
				inscribed[next_i],
				inscribed_square_color,
				inscribed_square_width
			)
			add_child(line)

# ============================================
# VISUALIZACIÓN DE RECTÁNGULOS
# ============================================
func _visualize_rectangles() -> void:
	var all_block_faces = generator.get_all_block_faces()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var rectangles = block.get_rectangles()
		for rect in rectangles:
			var color: Color
			
			if block.is_rectangle_merged(rect.id):
				var merged_with_id = block.get_merged_with(rect.id)
				if rect.id < merged_with_id:
					color = Color(0.8, 0.8, 0.8, rect_alpha)
				else:
					color = Color(1.0, 1.0, 1.0, rect_alpha)
			else:
				color = rectangle_colors.get(rect.id, Color.WHITE)
			
			var base_corners = _get_rectangle_corners(block, rect, 0)
			
			if base_corners.size() == 4:
				var total_height = block.get_floors() * block.get_cells_per_floor() * block.get_cell_height()
				var cube = DebugUtil.create_skewed_cube(base_corners, total_height, color)
				add_child(cube)
	
	print("[Visualizer] Rectángulos extruidos generados para %d bloques" % all_block_faces.size())

func _get_rectangle_corners(block: BlockGenerator, rect: RectangleSubdivider.GridRectangle, y: int) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	
	var bounds = block.get_rectangle_bounds_with_offset(rect)
	
	var columns = block.get_columns()
	var rows = block.get_rows()
	var cell_height = block.get_cell_height()
	
	var vertices = block.grid_geometry.vertices
	
	var u_min = float(bounds.x_min) / max(1, columns)
	var u_max = float(bounds.x_max) / max(1, columns)
	var v_min = float(bounds.z_min) / max(1, rows)
	var v_max = float(bounds.z_max) / max(1, rows)
	
	var height = y * cell_height
	
	var corner_bl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_min) +
		vertices[1] * u_min * (1 - v_min) +
		vertices[2] * u_min * v_min +
		vertices[3] * (1 - u_min) * v_min
	)
	corners.append(Vector3(corner_bl_2d.x, height, corner_bl_2d.y))
	
	var corner_br_2d = (
		vertices[0] * (1 - u_max) * (1 - v_min) +
		vertices[1] * u_max * (1 - v_min) +
		vertices[2] * u_max * v_min +
		vertices[3] * (1 - u_max) * v_min
	)
	corners.append(Vector3(corner_br_2d.x, height, corner_br_2d.y))
	
	var corner_tr_2d = (
		vertices[0] * (1 - u_max) * (1 - v_max) +
		vertices[1] * u_max * (1 - v_max) +
		vertices[2] * u_max * v_max +
		vertices[3] * (1 - u_max) * v_max
	)
	corners.append(Vector3(corner_tr_2d.x, height, corner_tr_2d.y))
	
	var corner_tl_2d = (
		vertices[0] * (1 - u_min) * (1 - v_max) +
		vertices[1] * u_min * (1 - v_max) +
		vertices[2] * u_min * v_max +
		vertices[3] * (1 - u_min) * v_max
	)
	corners.append(Vector3(corner_tl_2d.x, height, corner_tl_2d.y))
	
	return corners

# ============================================
# VISUALIZACIÓN DE PLANOS DE PISO
# ============================================
func _visualize_floor_planes() -> void:
	var all_block_faces = generator.get_all_block_faces()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var floors = block.get_floors()
		var cells_per_floor = block.get_cells_per_floor()
		
		for floor in range(floors):
			var corner_bl = block.get_cell_position(
				block.available_min_x, 
				block.available_min_z, 
				floor * cells_per_floor
			)
			
			var corner_br = block.get_cell_position(
				block.available_max_x, 
				block.available_min_z, 
				floor * cells_per_floor
			)
			
			var corner_tr = block.get_cell_position(
				block.available_max_x, 
				block.available_max_z, 
				floor * cells_per_floor
			)
			
			var corner_tl = block.get_cell_position(
				block.available_min_x, 
				block.available_max_z, 
				floor * cells_per_floor
			)
			
			var plane = DebugUtil.create_debug_plane(
				corner_bl, 
				corner_br, 
				corner_tr, 
				corner_tl, 
				floor_plane_color
			)
			add_child(plane)
	
	print("[Visualizer] Planos de piso generados para %d bloques" % all_block_faces.size())

# ============================================
# VISUALIZACIÓN DE CARRILES
# ============================================
func _visualize_lanes() -> void:
	var all_block_faces = generator.get_all_block_faces()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var all_lanes = block.get_all_lanes()
		
		for lane_data in all_lanes:
			var line = DebugUtil.create_debug_line_to_from(
				lane_data["start"],
				lane_data["end"],
				lane_color,
				lane_width
			)
			add_child(line)
	
	print("[Visualizer] Carriles generados para %d bloques" % all_block_faces.size())
