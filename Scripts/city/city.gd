extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(10, 10)
@export var min_distance: float = 3.8
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
@export var block_grid_rows: int = 20
@export var block_grid_columns: int = 20
@export var block_grid_floors: int = 5
@export var block_cells_per_floor: int = 4
@export var show_floor_planes: bool = true
@export var floor_plane_color: Color = Color(0.0, 0.5, 1.0, 0.3)

@export_group("Rectángulos")
@export var show_rectangles: bool = true
@export var rect_saturation: float = 0.8
@export var rect_brightness: float = 0.9
@export var rect_alpha: float = 0.8
@export var rect_max_divisions: int = 4
@export var rect_min_size: int = 2



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
	seed(generation_seed + 1000)
	
	# Generar colores para todos los rectángulos de todas las manzanas
	var all_block_faces = generator.get_all_block_faces()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue
		
		for rect in block.rectangles:
			var hue = randf()
			rectangle_colors[rect.id] = Color.from_hsv(hue, rect_saturation, rect_brightness, rect_alpha)

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
		
		# Visualizar cada rectángulo en cada piso
		for rect in block.rectangles:
			var color = rectangle_colors.get(rect.id, Color.WHITE)
			
			for floor in range(block.floors):
				var y = floor * block.cells_per_floor
				
				# Obtener las 4 esquinas del rectángulo
				var corners = _get_rectangle_corners(block, rect, y)
				
				if corners.size() == 4:
					var plane = DebugUtil.create_debug_plane(
						corners[0],
						corners[1],
						corners[2],
						corners[3],
						color
					)
					add_child(plane)
	
	print("[Visualizer] Rectángulos generados para %d bloques" % all_block_faces.size())

# Obtiene las 4 esquinas externas de un rectángulo en un piso específico
func _get_rectangle_corners(block: BlockGenerator, rect: BlockGenerator.GridRectangle, y: int) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	
	# Calcular las posiciones normalizadas (u, v) de las esquinas del rectángulo
	var u_min = float(rect.x) / max(1, block.columns)
	var u_max = float(rect.x + rect.width) / max(1, block.columns)
	var v_min = float(rect.z) / max(1, block.rows)
	var v_max = float(rect.z + rect.height) / max(1, block.rows)
	
	var height = y * block.cell_height
	
	# Esquina inferior-izquierda (u_min, v_min)
	var corner_bl_2d = (
		block.vertices[0] * (1 - u_min) * (1 - v_min) +
		block.vertices[1] * u_min * (1 - v_min) +
		block.vertices[2] * u_min * v_min +
		block.vertices[3] * (1 - u_min) * v_min
	)
	corners.append(Vector3(corner_bl_2d.x, height, corner_bl_2d.y))
	
	# Esquina inferior-derecha (u_max, v_min)
	var corner_br_2d = (
		block.vertices[0] * (1 - u_max) * (1 - v_min) +
		block.vertices[1] * u_max * (1 - v_min) +
		block.vertices[2] * u_max * v_min +
		block.vertices[3] * (1 - u_max) * v_min
	)
	corners.append(Vector3(corner_br_2d.x, height, corner_br_2d.y))
	
	# Esquina superior-derecha (u_max, v_max)
	var corner_tr_2d = (
		block.vertices[0] * (1 - u_max) * (1 - v_max) +
		block.vertices[1] * u_max * (1 - v_max) +
		block.vertices[2] * u_max * v_max +
		block.vertices[3] * (1 - u_max) * v_max
	)
	corners.append(Vector3(corner_tr_2d.x, height, corner_tr_2d.y))
	
	# Esquina superior-izquierda (u_min, v_max)
	var corner_tl_2d = (
		block.vertices[0] * (1 - u_min) * (1 - v_max) +
		block.vertices[1] * u_min * (1 - v_max) +
		block.vertices[2] * u_min * v_max +
		block.vertices[3] * (1 - u_min) * v_max
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
		
		for floor in range(block.floors):
			var corner_bl = block.get_cell_position(
				block.available_min_x, 
				block.available_min_z, 
				floor * block.cells_per_floor
			)
			
			var corner_br = block.get_cell_position(
				block.available_max_x, 
				block.available_min_z, 
				floor * block.cells_per_floor
			)
			
			var corner_tr = block.get_cell_position(
				block.available_max_x, 
				block.available_max_z, 
				floor * block.cells_per_floor
			)
			
			var corner_tl = block.get_cell_position(
				block.available_min_x, 
				block.available_max_z, 
				floor * block.cells_per_floor
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
