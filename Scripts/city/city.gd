extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(10, 10)
@export var min_distance: float = 0.7
@export var rejection_samples: int = 30
@export var generation_seed: int = 1234

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
@export var num_delivery_facilities: int = 6
@export var delivery_points_per_block: int = 2
@export var num_gas_stations: int = 10
@export var num_stores: int = 15

@export_group("Grillas de Manzanas")
@export var block_grid_rows: int = 10
@export var block_grid_columns: int = 10
@export var block_grid_floors: int = 3
@export var block_cells_per_floor: int = 4
@export var show_block_cells: bool = true

@export_subgroup("Colores de Celdas")
@export var delivery_facility_color: Color = Color.ORANGE
@export var delivery_point_color: Color = Color.YELLOW
@export var gas_station_color: Color = Color.RED
@export var store_color: Color = Color.BLUE

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphCityGenerator = null
var neighborhood_colors: Dictionary = {}

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
		# Parámetros de túneles
		num_small_tunnels,
		num_large_tunnels,
		tunnel_min_length,
		tunnel_max_length,
		tunnel_max_angle_degrees,
		tunnel_min_gap,
		# Parámetros de puntos de interés
		num_delivery_facilities,
		delivery_points_per_block,
		num_gas_stations,
		num_stores,
		# Parámetros de grillas
		block_grid_rows,
		block_grid_columns,
		block_grid_floors,
		block_cells_per_floor,
	)
	
	_generate_neighborhood_colors()

func _generate_neighborhood_colors() -> void:
	neighborhood_colors.clear()
	seed(generation_seed)
	
	var neighborhood_saturation: float = 0.3
	var neighborhood_brightness: float = 0.3
	var neighborhood_alpha: float = 0.7
	
	for i in range(num_neighborhoods):
		var hue = randf()
		neighborhood_colors[i] = Color.from_hsv(hue, neighborhood_saturation, neighborhood_brightness, neighborhood_alpha)

func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return
	
	# 1. Visualizar barrios (primero, para que estén debajo)
	if show_neighborhoods:
		_visualize_neighborhoods()
	
	# 2. Visualizar cuadrados inscritos (opcional)
	if show_inscribed_squares:
		_visualize_inscribed_squares()
	
	# 3. Visualizar calles (según su tipo)
	_visualize_streets()
	
	# 4. Visualizar celdas de las manzanas
	if show_block_cells:
		_visualize_block_cells()
	
	# 5. Visualizar nodos (último, para que estén arriba)
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
# VISUALIZACIÓN DE CELDAS DE MANZANAS
# ============================================
func _visualize_block_cells() -> void:
	var all_block_faces = generator.get_all_block_faces()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		# Obtener todas las celdas no vacías
		var non_empty_cells = block.get_non_empty_cells()
		
		for cell_info in non_empty_cells:
			var cell_type = cell_info["cell_type"]
			var base_vertices = cell_info["base_vertices"]
			var height = cell_info["height"]
			
			# Saltar si no hay vértices válidos
			if base_vertices.size() != 4:
				continue
			
			# Seleccionar color según el tipo de celda
			var color: Color
			match cell_type:
				BlockGenerator.CellType.DELIVERY_FACILITY:
					color = delivery_facility_color
				BlockGenerator.CellType.DELIVERY_POINT:
					color = delivery_point_color
				BlockGenerator.CellType.GAS_STATION:
					color = gas_station_color
				BlockGenerator.CellType.STORE:
					color = store_color
				_:
					color = Color.WHITE  # Por defecto
			
			# Crear el cubo skewed
			var cube = DebugUtil.create_skewed_cube(base_vertices, height, color)
			add_child(cube)
