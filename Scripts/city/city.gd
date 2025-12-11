extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(70/10, 70/10)
@export var min_distance: float = 15.5/10
@export var rejection_samples: int = 90
@export var generation_seed: int = 123456

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
@export var large_street_color: Color = Color.PURPLE
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

@export_group("Grillas de Manzanas")
@export var block_grid_rows: int = 100
@export var block_grid_columns: int = 100
@export var block_grid_floors: int = 2
@export var block_cells_per_floor: int = 30

@export_subgroup("Offsets de Calles (en celdas)")
@export var boundary_offset: int = 0
@export var small_street_offset: int = 7
@export var medium_street_offset: int = 12
@export var large_street_offset: int = 17
@export var small_tunnel_offset: int = 12
@export var large_tunnel_offset: int = 17

@export_group("Grilla Distorsionada")
@export var distorted_grid_rows: int = 6
@export var distorted_grid_columns: int = 6
@export_range(0.0, 1.0) var wave_amplitude_x: float = 0.07
@export_range(0.0, 1.0) var wave_amplitude_z: float = 0.07
@export var wave_frequency_x: float = 1.0
@export var wave_frequency_z: float = 1.0
@export var wave_phase_x: float = 0.0
@export var wave_phase_z: float = 0.0
@export_range(0.1, 5.0) var edge_falloff_sharpness: float = 1.0

@export_subgroup("Generación de Alleyways")
@export var small_alleyways_count: int = 3
@export var big_alleyways_count: int = 3
@export var min_steps_before_turn: int = 2
@export var grid_seed: int = -1  # -1 = aleatorio

@export_group("Grilla de Buildings")
@export var building_grid_rows: int = 20
@export var building_grid_columns: int = 20
@export var building_cell_height: float = 3.0

@export_subgroup("Visualización de Grilla Distorsionada")
@export var show_distorted_grid: bool = true
@export var distorted_grid_vertex_radius: float = 0.04
@export var distorted_grid_normal_vertex_color: Color = Color.CYAN
@export var distorted_grid_small_vertex_color: Color = Color.YELLOW
@export var distorted_grid_big_vertex_color: Color = Color.ORANGE
@export var distorted_grid_small_origin_vertex_color: Color = Color.GREEN
@export var distorted_grid_big_origin_vertex_color: Color = Color.MAGENTA
@export var distorted_grid_boundary_vertex_color: Color = Color.RED
@export var distorted_grid_normal_edge_color: Color = Color.WHITE
@export var distorted_grid_small_edge_color: Color = Color.YELLOW
@export var distorted_grid_big_edge_color: Color = Color.ORANGE
@export var distorted_grid_small_origin_edge_color: Color = Color.GREEN
@export var distorted_grid_big_origin_edge_color: Color = Color.MAGENTA
@export var distorted_grid_boundary_edge_color: Color = Color.ORANGE_RED
@export var distorted_grid_edge_width: float = 0.015
@export var distorted_grid_height_offset: float = 0.1

@export_group("Buildings")
@export var show_buildings: bool = true
@export var building_color: Color = Color(0.6, 0.6, 0.6, 0.8)

@export_group("Carriles")
@export var show_lanes: bool = true
@export var lane_color: Color = Color.YELLOW
@export var lane_width: float = 0.02

@export_group("Planos Peatonales")
@export var show_pedestrian_planes: bool = false
@export var pedestrian_plane_color: Color = Color(1.0, 0.5, 0.0, 0.6)
@export_range(0.0, 1.0) var pedestrian_plane_transparency: float = 0.5

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
		boundary_offset,
		small_street_offset,
		medium_street_offset,
		large_street_offset,
		small_tunnel_offset,
		large_tunnel_offset,
		distorted_grid_rows,
		distorted_grid_columns,
		wave_amplitude_x,
		wave_amplitude_z,
		wave_frequency_x,
		wave_frequency_z,
		wave_phase_x,
		wave_phase_z,
		edge_falloff_sharpness,
		small_alleyways_count,
		big_alleyways_count,
		min_steps_before_turn,
		grid_seed,
		building_grid_rows,
		building_grid_columns,
		building_cell_height
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
	
	if show_inscribed_squares:
		_visualize_inscribed_squares()
	
	_visualize_streets()
	
	if show_buildings:
		_visualize_buildings()
	
	if show_distorted_grid:
		_visualize_distorted_grids()
	
	if show_lanes:
		_visualize_lanes()
	
	if show_pedestrian_planes:
		_visualize_pedestrian_planes()
	
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
# VISUALIZACIÓN DE BUILDINGS
# ============================================
func _visualize_buildings() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_buildings = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var distorted = block.get_distorted_grid()
		if distorted == null:
			continue
		
		var building_height = block.get_floors() * block.get_cells_per_floor() * block.get_cell_height()
		var is_clockwise = block.is_clockwise
		
		for z in range(distorted.rows):
			for x in range(distorted.columns):
				var building: Building = block.get_building(x, z)
				
				if building == null:
					continue
				
				var core_vertices = building.get_core_vertices(0)
				
				if core_vertices.size() != 4:
					continue
				
				if is_clockwise:
					var temp = core_vertices[1]
					core_vertices[1] = core_vertices[3]
					core_vertices[3] = temp
				
				# Usar la nueva función con edge_types
				var cube = DebugUtil.create_building_cube(
					core_vertices, 
					building_height, 
					building_color,
					building.edge_types,
					is_clockwise
				)
				add_child(cube)
				total_buildings += 1
	
	print("[Visualizer] Buildings individuales: %d en %d bloques" % [total_buildings, all_block_faces.size()])
# ============================================
# VISUALIZACIÓN DE GRILLAS DISTORSIONADAS
# ============================================
func _visualize_distorted_grids() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_vertices = 0
	var total_edges = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var distorted = block.get_distorted_grid()
		var path_gen = block.get_path_generator()
		
		if distorted == null or path_gen == null:
			continue
		
		# Cache de vértices calculados
		var vertex_cache: Dictionary = {}
		
		# Función helper para calcular vértices
		var get_vertex = func(grid_x: int, grid_z: int) -> Vector2:
			var key = "%d_%d" % [grid_x, grid_z]
			if key in vertex_cache:
				return vertex_cache[key]
			
			var u = float(grid_x) / max(1, distorted.columns)
			var v = float(grid_z) / max(1, distorted.rows)
			var base_pos = GridHelper.bilinear_interpolation(distorted.vertices, u, v)
			
			var bottom_u_dir = (distorted.vertices[1] - distorted.vertices[0]).normalized()
			var top_u_dir = (distorted.vertices[2] - distorted.vertices[3]).normalized()
			var local_u_dir = bottom_u_dir.lerp(top_u_dir, v)
			
			var left_v_dir = (distorted.vertices[3] - distorted.vertices[0]).normalized()
			var right_v_dir = (distorted.vertices[2] - distorted.vertices[1]).normalized()
			var local_v_dir = left_v_dir.lerp(right_v_dir, u)
			
			var u_falloff = pow(min(u, 1.0 - u) * 2.0, distorted.edge_falloff_sharpness)
			var v_falloff = pow(min(v, 1.0 - v) * 2.0, distorted.edge_falloff_sharpness)
			
			var wave_offset_u = sin(v * distorted.wave_frequency_z * TAU + distorted.wave_phase_z) * distorted.wave_amplitude_x * u_falloff
			var wave_offset_v = sin(u * distorted.wave_frequency_x * TAU + distorted.wave_phase_x) * distorted.wave_amplitude_z * v_falloff
			
			var result = base_pos + local_u_dir * wave_offset_u + local_v_dir * wave_offset_v
			vertex_cache[key] = result
			return result
		
		# Visualizar vértices de la grilla
		for grid_z in range(distorted.rows + 1):
			for grid_x in range(distorted.columns + 1):
				var pos_2d = get_vertex.call(grid_x, grid_z)
				var pos_3d = Vector3(pos_2d.x, distorted_grid_height_offset, pos_2d.y)
				
				# Determinar si es vértice de borde
				var is_boundary = (grid_x == 0 or grid_x == distorted.columns or 
								   grid_z == 0 or grid_z == distorted.rows)
				
				var vertex_color: Color
				if is_boundary:
					vertex_color = distorted_grid_boundary_vertex_color
				else:
					vertex_color = distorted_grid_normal_vertex_color
				
				var sphere = DebugUtil.create_debug_sphere(vertex_color, distorted_grid_vertex_radius)
				sphere.position = pos_3d
				add_child(sphere)
				total_vertices += 1
		
		# Visualizar edges horizontales
		for grid_z in range(distorted.rows + 1):
			for grid_x in range(distorted.columns):
				var pos1_2d = get_vertex.call(grid_x, grid_z)
				var pos2_2d = get_vertex.call(grid_x + 1, grid_z)
				
				var pos1_3d = Vector3(pos1_2d.x, distorted_grid_height_offset, pos1_2d.y)
				var pos2_3d = Vector3(pos2_2d.x, distorted_grid_height_offset, pos2_2d.y)
				
				var edge_color: Color
				
				var is_boundary_edge = (grid_z == 0 or grid_z == distorted.rows)
				
				if is_boundary_edge:
					edge_color = distorted_grid_boundary_edge_color
				else:
					# Usar PathGenerator para obtener tipo de edge
					var path_type = path_gen.get_path_edge_type_vertices(grid_x, grid_z, grid_x + 1, grid_z)
					
					match path_type:
						DistortedGrid.CellType.BIG:
							edge_color = distorted_grid_big_edge_color
						DistortedGrid.CellType.SMALL:
							edge_color = distorted_grid_small_edge_color
						DistortedGrid.CellType.SMALL_ORIGIN:
							edge_color = distorted_grid_small_origin_edge_color
						DistortedGrid.CellType.BIG_ORIGIN:
							edge_color = distorted_grid_big_origin_edge_color
						_:
							edge_color = distorted_grid_normal_edge_color
				
				var line = DebugUtil.create_debug_line_to_from(
					pos1_3d,
					pos2_3d,
					edge_color,
					distorted_grid_edge_width
				)
				add_child(line)
				total_edges += 1
		
		# Visualizar edges verticales
		for grid_z in range(distorted.rows):
			for grid_x in range(distorted.columns + 1):
				var pos1_2d = get_vertex.call(grid_x, grid_z)
				var pos2_2d = get_vertex.call(grid_x, grid_z + 1)
				
				var pos1_3d = Vector3(pos1_2d.x, distorted_grid_height_offset, pos1_2d.y)
				var pos2_3d = Vector3(pos2_2d.x, distorted_grid_height_offset, pos2_2d.y)
				
				var edge_color: Color
				
				var is_boundary_edge = (grid_x == 0 or grid_x == distorted.columns)
				
				if is_boundary_edge:
					edge_color = distorted_grid_boundary_edge_color
				else:
					# Usar PathGenerator para obtener tipo de edge
					var path_type = path_gen.get_path_edge_type_vertices(grid_x, grid_z, grid_x, grid_z + 1)
					
					match path_type:
						DistortedGrid.CellType.BIG:
							edge_color = distorted_grid_big_edge_color
						DistortedGrid.CellType.SMALL:
							edge_color = distorted_grid_small_edge_color
						DistortedGrid.CellType.SMALL_ORIGIN:
							edge_color = distorted_grid_small_origin_edge_color
						DistortedGrid.CellType.BIG_ORIGIN:
							edge_color = distorted_grid_big_origin_edge_color
						_:
							edge_color = distorted_grid_normal_edge_color
				
				var line = DebugUtil.create_debug_line_to_from(
					pos1_3d,
					pos2_3d,
					edge_color,
					distorted_grid_edge_width
				)
				add_child(line)
				total_edges += 1
	
	print("[Visualizer] Grillas distorsionadas: %d vértices, %d edges en %d bloques" % [total_vertices, total_edges, all_block_faces.size()])

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
			var line = DebugUtil.create_debug_arrow_to_from(
				lane_data["from"],
				lane_data["to"],
				Color.GREEN,
				lane_width
			)
			add_child(line)
	
	print("[Visualizer] Carriles direccionales generados para %d bloques" % all_block_faces.size())

# ============================================
# VISUALIZACIÓN DE PLANOS PEATONALES
# ============================================
func _visualize_pedestrian_planes() -> void:
	var all_pedestrian_planes = generator.get_all_pedestrian_planes()
	var total_planes = 0
	
	var max_building_height = _calculate_max_building_height()
	
	for edge_key in all_pedestrian_planes:
		var planes = all_pedestrian_planes[edge_key]
		
		for plane_data in planes:
			if plane_data.size() != 2:
				continue
			
			var point1_2d: Vector2 = plane_data[0]
			var point2_2d: Vector2 = plane_data[1]
			
			var v1 = Vector3(point1_2d.x, 0.0, point1_2d.y)
			var v2 = Vector3(point2_2d.x, 0.0, point2_2d.y)
			var v3 = Vector3(point2_2d.x, max_building_height, point2_2d.y)
			var v4 = Vector3(point1_2d.x, max_building_height, point1_2d.y)
			
			var plane = DebugUtil.create_debug_plane(v1, v2, v3, v4, pedestrian_plane_color, pedestrian_plane_transparency)
			add_child(plane)
			total_planes += 1
	
	print("[Visualizer] Planos peatonales generados: %d" % total_planes)

func _calculate_max_building_height() -> float:
	var max_height = 0.0
	var all_block_faces = generator.get_all_block_faces()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var block_height = block.get_floors() * block.get_cells_per_floor() * block.get_cell_height()
		
		if block_height > max_height:
			max_height = block_height
	
	return max_height
