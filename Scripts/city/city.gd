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
@export var smoothing_steps: int = 50  # Número de pasos de suavizado

@export_group("Visualización")
@export var show_nodes: bool = true
@export var node_radius: float = 0.08
@export var normal_node_color: Color = Color.CHARTREUSE
@export var boundary_node_color: Color = Color.ORANGE_RED
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
@export var num_small_tunnels: int = 16
@export var num_large_tunnels: int = 6
@export var tunnel_min_length: int = 1
@export var tunnel_max_length: int = 3
@export var tunnel_max_angle_degrees: float = 30.0
@export var tunnel_min_gap: int = 3

@export_subgroup("Túneles Pequeños (Tipo 3)")
@export var small_tunnel_color: Color = Color.CYAN
@export var small_tunnel_width: float = 0.015

@export_subgroup("Túneles Grandes (Tipo 4)")
@export var large_tunnel_color: Color = Color.BLUE
@export var large_tunnel_width: float = 0.045

@export_group("Grillas de Manzanas")
@export var show_block_grids: bool = true
@export var block_grid_size: int = 10
@export var block_grid_floors: int = 3
@export var block_floor_height: float = 3.0

@export_subgroup("Puntos de Interés")
@export var num_delivery_facilities: int = 5
@export var delivery_points_per_block: int = 2
@export var num_gas_stations: int = 10
@export var num_stores: int = 15

@export_subgroup("Colores de Celdas")
@export var delivery_facility_color: Color = Color.ORANGE
@export var delivery_point_color: Color = Color.YELLOW
@export var gas_station_color: Color = Color.RED
@export var store_color: Color = Color.PURPLE

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphCityGenerator = null
var neighborhood_colors: Dictionary = {}  # {neighborhood_id: Color}

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
		block_grid_size,
		block_grid_floors,
		block_floor_height
	)
	
	# Generar colores para cada barrio
	_generate_neighborhood_colors()

func _generate_neighborhood_colors() -> void:
	neighborhood_colors.clear()
	seed(generation_seed)
	
	var neighborhood_saturation: float = 0.3
	var neighborhood_brightness: float = 0.3
	var neighborhood_alpha: float = 0.7
	
	for i in range(num_neighborhoods):
		# Generar colores vibrantes y variados con saturación y brillo controlados
		var hue = randf()
		neighborhood_colors[i] = Color.from_hsv(hue, neighborhood_saturation, neighborhood_brightness, neighborhood_alpha)

func clear_visualization() -> void:
	# Eliminar todos los hijos para limpiar la visualización anterior
	for child in get_children():
		child.queue_free()

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return
	
	# 1. Visualizar barrios (primero, para que estén debajo)
	if show_neighborhoods:
		_visualize_neighborhoods()
	
	# 2. Visualizar grillas de manzanas
	if show_block_grids:
		_visualize_block_grids()
	
	# 3. Visualizar calles (según su tipo)
	_visualize_streets()
	
	# 4. Visualizar nodos (último, para que estén arriba)
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
			continue  # Sin barrio asignado
		
		var color = neighborhood_colors.get(neighborhood_id, Color.GRAY)
		
		# Obtener los vértices de la cara
		var vertices: Array[Vector3] = []
		for idx in face:
			vertices.append(generator.plain_graph.points[idx])
		
		# Crear un plano para cada cara
		if vertices.size() >= 3:
			_visualize_face_as_planes(vertices, color)

func _visualize_face_as_planes(vertices: Array[Vector3], color: Color) -> void:
	# Si es un quad (4 vértices), crear un plano
	if vertices.size() == 4:
		var plane = DebugUtil.create_debug_plane(
			vertices[0],
			vertices[1],
			vertices[2],
			vertices[3],
			color
		)
		add_child(plane)
	
	# Si es un triángulo (3 vértices), crear un plano triangular
	# (usando el primer vértice dos veces para simular un triángulo)
	elif vertices.size() == 3:
		var plane = DebugUtil.create_debug_plane(
			vertices[0],
			vertices[1],
			vertices[2],
			vertices[2],  # Repetir el último vértice
			color
		)
		add_child(plane)
	
	# Si tiene más de 4 vértices, triangular desde el centro
	elif vertices.size() > 4:
		# Calcular centro
		var center = Vector3.ZERO
		for v in vertices:
			center += v
		center /= vertices.size()
		
		# Crear triángulos en abanico desde el centro
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
# VISUALIZACIÓN DE GRILLAS DE MANZANAS
# ============================================
func _visualize_block_grids() -> void:
	# Calcular la altura de cada celda basada en min_distance y tamaño de grilla
	var cell_height = min_distance / float(block_grid_size)
	
	# Obtener todas las manzanas que tienen grillas
	var block_faces = generator.get_all_block_faces()
	
	for face_idx in block_faces:
		var block_gen = generator.get_block_grid(face_idx)
		if block_gen == null:
			continue
		
		# Visualizar todas las celdas de todos los pisos
		for floor in range(block_gen.grid_floors):
			for row in range(block_gen.grid_rows):
				for col in range(block_gen.grid_columns):
					var cell_coord = Vector3i(col, row, floor)
					var cell_type = block_gen.get_cell(cell_coord)
					
					# Solo visualizar celdas no vacías
					if cell_type == BlockGenerator.CellType.EMPTY:
						continue
					
					# Obtener color según el tipo de celda
					var color = _get_color_for_cell_type(cell_type)
					
					# Obtener las esquinas de la base de la celda
					var base_vertices = block_gen.get_cell_bottom_corners(col, row, floor)
					
					if base_vertices.size() != 4:
						push_warning("Celda en face %d (%d,%d,%d) no tiene 4 vértices de base" % [face_idx, col, row, floor])
						continue
					
					# Crear el cubo skewed usando DebugUtil
					var cube = DebugUtil.create_skewed_cube(base_vertices, cell_height, color)
					add_child(cube)

func _get_color_for_cell_type(cell_type: int) -> Color:
	"""Retorna el color apropiado según el tipo de celda"""
	match cell_type:
		BlockGenerator.CellType.DELIVERY_FACILITY:
			return delivery_facility_color
		BlockGenerator.CellType.DELIVERY_POINT:
			return delivery_point_color
		BlockGenerator.CellType.GAS_STATION:
			return gas_station_color
		BlockGenerator.CellType.STORE:
			return store_color
		_:
			return Color.WHITE

# ============================================
# VISUALIZACIÓN DE CALLES
# ============================================
func _visualize_streets() -> void:
	for edge in generator.plain_graph.edges:
		var p1 = generator.plain_graph.points[edge[0]]
		var p2 = generator.plain_graph.points[edge[1]]
		
		# Obtener el tipo de calle
		var street_type = generator.get_street_type(edge[0], edge[1])
		
		# Seleccionar color y ancho según el tipo
		var color: Color
		var width: float
		
		match street_type:
			-1:  # Límite
				color = boundary_street_color
				width = boundary_street_width
			0:  # Pequeña
				color = small_street_color
				width = small_street_width
			1:  # Mediana
				color = medium_street_color
				width = medium_street_width
			2:  # Grande
				color = large_street_color
				width = large_street_width
			3:  # Túnel pequeño
				color = small_tunnel_color
				width = small_tunnel_width
			4:  # Túnel grande
				color = large_tunnel_color
				width = large_tunnel_width
			_:  # Por defecto (no debería pasar)
				color = medium_street_color
				width = medium_street_width
		
		# Crear la línea
		var line = DebugUtil.create_debug_line_to_from(p1, p2, color, width)
		add_child(line)

# ============================================
# VISUALIZACIÓN DE NODOS
# ============================================
func _visualize_nodes() -> void:
	for node_idx in range(generator.plain_graph.points.size()):
		var point = generator.plain_graph.points[node_idx]
		
		# Obtener el tipo de nodo (0 = normal, 1 = límite)
		var node_type = generator.plain_graph.node_types.get(node_idx, 0)
		
		# Seleccionar color según el tipo
		var color: Color
		if node_type == 1:
			color = boundary_node_color  # Nodo límite
		else:
			color = normal_node_color    # Nodo normal
		
		# Crear la esfera con el color apropiado
		var sphere = DebugUtil.create_debug_sphere(color, node_radius)
		sphere.position = point
		add_child(sphere)
