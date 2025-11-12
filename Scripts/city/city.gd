extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(10, 10)
@export var min_distance: float = 1.3
@export var rejection_samples: int = 100
@export var use_seed: bool = true
@export var generation_seed: int = 1234

@export_group("Filtros de Ángulos")
@export var max_angle_threshold: float = 0.825 * PI
@export var min_quad_angle: float = 0.2 * PI
@export var max_quad_angle: float = 0.9 * PI

@export_group("Barrios")
@export var num_neighborhoods: int = 6
@export var show_neighborhoods: bool = true

@export_group("Suavizado")
@export var smoothing_steps: int = 40  # Número de pasos de suavizado
@export var auto_smooth: bool = true  # Aplicar suavizado automáticamente
@export var animate_smoothing: bool = true  # Animar el proceso de suavizado
@export var animation_speed: float = 0.05  # Tiempo entre pasos (segundos)

@export_group("Visualización")
@export var node_color: Color = Color.CHARTREUSE
@export var node_radius: float = 0.08
@export var edge_color: Color = Color.WHITE
@export var edge_width: float = 0.02
@export var inscribed_square_color: Color = Color.RED
@export var inscribed_square_width: float = 0.03
@export var show_inscribed_squares: bool = false
@export var auto_generate: bool = true

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphGenerator = null
var original_generator: GraphGenerator = null  # Guardar el grafo original
var current_smoothing_step: int = 0
var is_animating: bool = false
var neighborhood_colors: Dictionary = {}  # {neighborhood_id: Color}

func _ready() -> void:
	if auto_generate:
		generate_and_visualize()

# ============================================
# GENERACIÓN Y VISUALIZACIÓN
# ============================================
func generate_and_visualize() -> void:
	# Limpiar visualización anterior
	clear_visualization()
	
	# Crear nueva instancia del generador
	generator = GraphGenerator.new()
	
	# Generar el grafo
	generator.generate_graph(
		region_size,
		min_distance,
		rejection_samples,
		max_angle_threshold,
		min_quad_angle,
		max_quad_angle,
		use_seed,
		generation_seed,
		num_neighborhoods
	)
	
	# Generar colores para los barrios
	_generate_neighborhood_colors()
	
	# Guardar el grafo original (copia profunda)
	original_generator = GraphGenerator.new()
	original_generator.points = generator.points.duplicate()
	original_generator.edges = []
	for edge in generator.edges:
		original_generator.edges.append(edge.duplicate())
	original_generator.faces = []
	for face in generator.faces:
		original_generator.faces.append(face.duplicate())
	original_generator.neighborhoods = generator.neighborhoods.duplicate()
	
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
	if generator == null:
		push_warning("No hay grafo para suavizar")
		return
	
	print("Aplicando ", steps, " pasos de suavizado...")
	
	for i in range(steps):
		generator.smooth_graph()
	
	print("Suavizado completado")

## Aplica un solo paso de suavizado
func apply_single_smoothing_step() -> void:
	if generator == null:
		push_warning("No hay grafo para suavizar")
		return
	
	generator.smooth_graph()
	current_smoothing_step += 1
	
	print("Paso de suavizado ", current_smoothing_step, " aplicado")

## Inicia la animación del suavizado
func start_animated_smoothing() -> void:
	if is_animating:
		push_warning("Ya hay una animación en progreso")
		return
	
	if generator == null:
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
	if original_generator == null:
		push_warning("No hay grafo original guardado")
		return
	
	# Restaurar el grafo desde el original (copia profunda)
	generator = GraphGenerator.new()
	generator.points = original_generator.points.duplicate()
	generator.edges = []
	for edge in original_generator.edges:
		generator.edges.append(edge.duplicate())
	generator.faces = []
	for face in original_generator.faces:
		generator.faces.append(face.duplicate())
	generator.neighborhoods = original_generator.neighborhoods.duplicate()
	
	current_smoothing_step = 0
	clear_visualization()
	visualize_graph()
	print("Grafo reseteado al estado original")

# ============================================
# VISUALIZACIÓN
# ============================================

func visualize_graph() -> void:
	if generator == null:
		push_warning("No hay grafo para visualizar")
		return
	
	# Visualizar caras (barrios) primero para que queden debajo
	if show_neighborhoods:
		visualize_faces()
	
	# Visualizar nodos
	visualize_nodes()
	
	# Visualizar aristas
	visualize_edges()
	
	# Visualizar cuadrados inscritos
	if show_inscribed_squares:
		visualize_inscribed_squares()

func visualize_nodes() -> void:
	for point in generator.points:
		var sphere = DebugUtil.create_debug_sphere(node_color, node_radius)
		add_child(sphere)
		sphere.global_position = point

func visualize_edges() -> void:
	for edge in generator.edges:
		if edge.size() != 2:
			continue
		
		var idx1 = edge[0]
		var idx2 = edge[1]
		
		# Validar índices
		if idx1 >= generator.points.size() or idx2 >= generator.points.size():
			push_warning("Índice de arista fuera de rango: ", edge)
			continue
		
		var p1 = generator.points[idx1]
		var p2 = generator.points[idx2]
		
		var line = DebugUtil.create_debug_line_to_from(p1, p2, edge_color, edge_width)
		add_child(line)

func visualize_faces() -> void:
	for face_idx in range(generator.faces.size()):
		var face = generator.faces[face_idx]
		
		# Obtener el color del barrio de esta cara
		var neighborhood_id = generator.get_neighborhood_for_face(face_idx)
		var face_color = _get_neighborhood_color(neighborhood_id)
		
		# Solo visualizamos quads (4 vértices)
		if face.size() == 4:
			# Obtener las posiciones de los vértices
			var p1 = generator.points[face[0]]
			var p2 = generator.points[face[1]]
			var p3 = generator.points[face[2]]
			var p4 = generator.points[face[3]]
			
			# Crear el plano con el color del barrio
			var plane = DebugUtil.create_debug_plane(p1, p2, p3, p4, face_color)
			add_child(plane)
		elif face.size() == 3:
			# Para triángulos, crear dos triángulos pequeños para formar un quad
			# O simplemente omitir (ya que después de la subdivisión todo debería ser quads)
			push_warning("Cara con 3 vértices encontrada en face_idx: ", face_idx)

func visualize_inscribed_squares() -> void:
	# Iterar por cada cara del grafo
	for face_idx in range(generator.faces.size()):
		# Obtener el cuadrado inscrito para esta cara
		var square_vertices: Array[Vector3] = generator.get_inscribed_square_for_face(face_idx)
		
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
# GESTIÓN DE COLORES DE BARRIOS
# ============================================

## Genera colores distintivos para cada barrio usando HSV
func _generate_neighborhood_colors() -> void:
	neighborhood_colors.clear()
	
	# Color para caras sin barrio asignado
	neighborhood_colors[-1] = Color.DARK_GRAY
	
	# Generar colores para cada barrio usando el espacio HSV
	# Distribuyendo uniformemente el matiz (hue) alrededor del círculo cromático
	for i in range(num_neighborhoods):
		var hue = float(i) / float(num_neighborhoods)
		var saturation = 0.7  # Saturación moderada
		var value = 0.9  # Brillo alto
		
		var color = Color.from_hsv(hue, saturation, value)
		neighborhood_colors[i] = color

## Obtiene el color de un barrio específico
func _get_neighborhood_color(neighborhood_id: int) -> Color:
	if neighborhood_id in neighborhood_colors:
		return neighborhood_colors[neighborhood_id]
	
	# Color por defecto si no se encuentra el barrio
	return Color.MAGENTA

# ============================================
# UTILIDADES
# ============================================

func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func print_graph_stats() -> void:
	if generator == null:
		print("No hay grafo generado")
		return
	
	print("\n=== ESTADÍSTICAS DEL GRAFO ===")
	print("Points (puntos): ", generator.points.size())
	print("Edges: ", generator.edges.size())
	print("Faces: ", generator.faces.size())
	print("Barrios: ", num_neighborhoods)
	print("Pasos de suavizado aplicados: ", current_smoothing_step)
	
	# Estadísticas de barrios
	var neighborhood_counts = {}
	for face_idx in generator.neighborhoods:
		var neighborhood_id = generator.neighborhoods[face_idx]
		if neighborhood_id not in neighborhood_counts:
			neighborhood_counts[neighborhood_id] = 0
		neighborhood_counts[neighborhood_id] += 1
	
	print("\n--- Distribución de Barrios ---")
	for neighborhood_id in neighborhood_counts:
		print("  Barrio ", neighborhood_id, ": ", neighborhood_counts[neighborhood_id], " caras")
	
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

func get_points() -> Array[Vector3]:
	if generator == null:
		return []
	return generator.points

func get_edges() -> Array[Array]:
	if generator == null:
		return []
	return generator.edges

func get_faces() -> Array:
	if generator == null:
		return []
	return generator.faces

func get_generator() -> GraphGenerator:
	return generator

func get_original_generator() -> GraphGenerator:
	return original_generator
