extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(10, 10)
@export var min_distance: float = 1.3
@export var rejection_samples: int = 30
@export var use_seed: bool = true
@export var generation_seed: int = 12345

@export_group("Filtros de Ángulos")
@export var max_angle_threshold: float = 0.825 * PI
@export var min_quad_angle: float = 0.2 * PI
@export var max_quad_angle: float = 0.9 * PI

@export_group("Suavizado")
@export var smoothing_steps: int = 30  # Número de pasos de suavizado
@export var auto_smooth: bool = true  # Aplicar suavizado automáticamente
@export var animate_smoothing: bool = true  # Animar el proceso de suavizado
@export var animation_speed: float = 0.15  # Tiempo entre pasos (segundos)

@export_group("Visualización")
@export var node_color: Color = Color.AQUA
@export var node_radius: float = 0.1
@export var edge_color: Color = Color.WHITE
@export var edge_width: float = 0.02
@export var inscribed_square_color: Color = Color.RED
@export var inscribed_square_width: float = 0.03
@export var show_inscribed_squares: bool = true
@export var auto_generate: bool = true

# ============================================
# DATOS DEL GRAFO
# ============================================
var graph: Dictionary = {}
var original_graph: Dictionary = {}  # Guardar el grafo original
var current_smoothing_step: int = 0
var is_animating: bool = false

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
	
	# Guardar el grafo original
	original_graph = graph.duplicate(true)
	
	# Aplicar suavizado si está habilitado
	if auto_smooth:
		if animate_smoothing:
			start_animated_smoothing()
		else:
			apply_smoothing_steps(smoothing_steps)
	
	# Visualizar
	visualize_graph()
	
	# Imprimir estadísticas
	print_graph_stats()

# ============================================
# FUNCIONES DE SUAVIZADO
# ============================================

## Aplica múltiples pasos de suavizado al grafo
func apply_smoothing_steps(steps: int) -> void:
	if graph.is_empty():
		push_warning("No hay grafo para suavizar")
		return
	
	print("Aplicando ", steps, " pasos de suavizado...")
	
	for i in range(steps):
		graph = GraphGenerator.smooth_graph(graph)
	
	print("Suavizado completado")

## Aplica un solo paso de suavizado
func apply_single_smoothing_step() -> void:
	if graph.is_empty():
		push_warning("No hay grafo para suavizar")
		return
	
	graph = GraphGenerator.smooth_graph(graph)
	current_smoothing_step += 1
	
	print("Paso de suavizado ", current_smoothing_step, " aplicado")

## Inicia la animación del suavizado
func start_animated_smoothing() -> void:
	if is_animating:
		push_warning("Ya hay una animación en progreso")
		return
	
	if graph.is_empty():
		push_warning("No hay grafo para suavizar")
		return
	
	is_animating = true
	current_smoothing_step = 0
	_animate_smoothing_step()

## Anima un paso de suavizado
func _animate_smoothing_step() -> void:
	if current_smoothing_step >= smoothing_steps:
		is_animating = false
		print("Animación de suavizado completada")
		return
	
	# Aplicar un paso de suavizado
	apply_single_smoothing_step()
	
	# Actualizar visualización
	clear_visualization()
	visualize_graph()
	
	# Programar el siguiente paso
	await get_tree().create_timer(animation_speed).timeout
	
	if is_animating:  # Verificar que no se haya cancelado
		_animate_smoothing_step()

## Detiene la animación del suavizado
func stop_animated_smoothing() -> void:
	is_animating = false
	print("Animación de suavizado detenida")

## Resetea el grafo al estado original
func reset_to_original() -> void:
	if original_graph.is_empty():
		push_warning("No hay grafo original guardado")
		return
	
	graph = original_graph.duplicate(true)
	current_smoothing_step = 0
	clear_visualization()
	visualize_graph()
	print("Grafo reseteado al estado original")

# ============================================
# VISUALIZACIÓN
# ============================================

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
	print("Pasos de suavizado aplicados: ", current_smoothing_step)
	print("================================\n")

func regenerate() -> void:
	stop_animated_smoothing()  # Detener animación si hay una en progreso
	generate_and_visualize()

# ============================================
# FUNCIONES PÚBLICAS PARA CONTROL MANUAL
# ============================================

## Aplica un número específico de pasos de suavizado y actualiza la visualización
func smooth(steps: int = 1) -> void:
	apply_smoothing_steps(steps)
	clear_visualization()
	visualize_graph()
	print_graph_stats()

## Aplica un paso adicional de suavizado
func smooth_one_step() -> void:
	smooth(1)

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

func get_original_graph() -> Dictionary:
	return original_graph
