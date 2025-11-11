extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(10, 10)
@export var min_distance: float = 4.3
@export var rejection_samples: int = 30
@export var use_seed: bool = true
@export var generation_seed: int = 12345

@export_group("Filtros de Ángulos")
@export var max_angle_threshold: float = 0.825 * PI
@export var min_quad_angle: float = 0.2 * PI
@export var max_quad_angle: float = 0.9 * PI

@export_group("Visualización")
@export var node_color: Color = Color.AQUA
@export var node_radius: float = 0.1
@export var edge_color: Color = Color.WHITE
@export var edge_width: float = 0.02
@export var inscribed_square_color: Color = Color.RED  # Nuevo: color para cuadrados inscritos
@export var inscribed_square_width: float = 0.03  # Nuevo: grosor de líneas de cuadrados inscritos
@export var show_inscribed_squares: bool = true  # Nuevo: opción para mostrar/ocultar
@export var auto_generate: bool = true

# ============================================
# DATOS DEL GRAFO
# ============================================
var graph: Dictionary = {}

func _ready() -> void:
	if auto_generate:
		generate_and_visualize()

# ============================================
# GENERACIÓN Y VISUALIZACIÓN
# ============================================
func generate_and_visualize() -> void:
	# Limpiar visualización anterior
	clear_visualization()
	
	# Generar el grafo
	graph = GraphGenerator.generate_graph(
		region_size,
		min_distance,
		rejection_samples,
		max_angle_threshold,
		min_quad_angle,
		max_quad_angle,
		use_seed,
		generation_seed
	)
	
	# Visualizar
	visualize_graph()
	
	# Imprimir estadísticas
	print_graph_stats()

func visualize_graph() -> void:
	if graph.is_empty():
		push_warning("No hay grafo para visualizar")
		return
	
	# Visualizar nodos
	visualize_nodes()
	
	# Visualizar aristas
	visualize_edges()
	
	# Visualizar cuadrados inscritos
	if show_inscribed_squares:
		visualize_inscribed_squares()

func visualize_nodes() -> void:
	var points: Array = graph.get("points", [])
	
	for point in points:
		var sphere = DebugUtil.create_debug_sphere(node_color, node_radius)
		add_child(sphere)
		sphere.global_position = point

func visualize_edges() -> void:
	var points: Array = graph.get("points", [])
	var edges: Array = graph.get("edges", [])
	
	for edge in edges:
		if edge.size() != 2:
			continue
		
		var idx1 = edge[0]
		var idx2 = edge[1]
		
		# Validar índices
		if idx1 >= points.size() or idx2 >= points.size():
			push_warning("Índice de arista fuera de rango: ", edge)
			continue
		
		var p1 = points[idx1]
		var p2 = points[idx2]
		
		var line = DebugUtil.create_debug_line_to_from(p1, p2, edge_color, edge_width)
		add_child(line)

# ============================================
# NUEVA FUNCIÓN: VISUALIZACIÓN DE CUADRADOS INSCRITOS
# ============================================
func visualize_inscribed_squares() -> void:
	var points: Array = graph.get("points", [])
	var faces: Array = graph.get("faces", [])
	
	# Iterar por cada cara del grafo
	for face_idx in range(faces.size()):
		# Obtener el cuadrado inscrito para esta cara
		var square_vertices: Array[Vector3] = GraphGenerator.get_inscribed_square_for_face(
			face_idx, 
			points, 
			faces
		)
		
		# Validar que se obtuvo un cuadrado válido
		if square_vertices.is_empty():
			continue
		
		if square_vertices.size() != 4:
			push_warning("Cuadrado inscrito inválido para cara ", face_idx, " - tiene ", square_vertices.size(), " vértices")
			continue
		
		# Visualizar el cuadrado como 4 líneas conectadas
		for i in range(4):
			var p1 = square_vertices[i]
			var p2 = square_vertices[(i + 1) % 4]  # Conectar con el siguiente vértice (ciclando al primero)
			
			var line = DebugUtil.create_debug_line_to_from(
				p1, 
				p2, 
				inscribed_square_color, 
				inscribed_square_width
			)
			add_child(line)

# ============================================
# UTILIDADES
# ============================================
func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func print_graph_stats() -> void:
	if graph.is_empty():
		print("No hay grafo generado")
		return
	
	print("\n=== ESTADÍSTICAS DEL GRAFO ===")
	print("Points (puntos): ", graph.get("points", []).size())
	print("Edges: ", graph.get("edges", []).size())
	print("Faces: ", graph.get("faces", []).size())
	print("================================\n")

func regenerate() -> void:
	generate_and_visualize()

# ============================================
# ACCESO A DATOS DEL GRAFO
# ============================================
func get_points() -> Array:
	return graph.get("points", [])

func get_edges() -> Array:
	return graph.get("edges", [])

func get_faces() -> Array:
	return graph.get("faces", [])

func get_graph() -> Dictionary:
	return graph
