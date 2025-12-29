extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(700, 700)
@export var min_distance: float = 150.5
@export var rejection_samples: int = 90
@export var generation_seed: int = 123456

@export_group("Barrios")
@export var show_neighborhoods: bool = false

@export_subgroup("Transición de Alturas")
@export_range(0.1, 5.0) var neighborhood_height_falloff: float = 1.0

@export_subgroup("Industrial")
@export var industrial_min_floors: int = 8
@export var industrial_max_floors: int = 14
@export_range(0.0, 1.0) var industrial_block_heart_probability: float = 0.2

@export_subgroup("Residential") 
@export var residential_min_floors: int = 1
@export var residential_max_floors: int = 3
@export_range(0.0, 1.0) var residential_block_heart_probability: float = 0.4

@export_subgroup("Financial")
@export var financial_min_floors: int = 7
@export var financial_max_floors: int = 9
@export_range(0.0, 1.0) var financial_block_heart_probability: float = 0.1

@export_group("Suavizado")
@export var smoothing_steps: int = 50

@export_group("Visualización General")
@export var show_nodes: bool = false
@export var node_radius: float = 0.08
@export var normal_node_color: Color = Color.CHARTREUSE
@export var boundary_node_color: Color = Color.ORANGE_RED
@export var inscribed_square_color: Color = Color.RED
@export var inscribed_square_width: float = 0.03
@export var auto_generate: bool = true

@export_group("Tipos de Calles")
@export var num_large_streets: int = 6
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

@export_group("Grillas de Manzanas")
@export var block_grid_rows: int = 100
@export var block_grid_columns: int = 100
@export var block_grid_floors: int = 8
@export var block_cells_per_floor: int = 5

@export_subgroup("Root Floors")
@export var min_root_floor_height: int = 2
@export var max_root_floor_height: int = 3
@export var use_generation_seed_for_roots: bool = true

@export_subgroup("Offsets de Calles (en celdas)")
@export var boundary_offset: int = 0
@export var small_street_offset: int = 7
@export var medium_street_offset: int = 12
@export var large_street_offset: int = 17

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
@export var grid_seed: int = -1

@export_group("Grilla de Buildings")
@export var building_grid_rows: int = 20
@export var building_grid_columns: int = 20

@export_subgroup("Visualización de Grilla Distorsionada")
@export var show_distorted_grid: bool = true
@export var distorted_grid_floor_to_show: int = 0
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
@export var show_building_colliders: bool = true

@export_group("Carriles")
@export var show_lanes: bool = true
@export var lane_color: Color = Color.YELLOW
@export var lane_width: float = 0.02

@export_group("Planos Peatonales")
@export var show_pedestrian_planes: bool = false
@export var pedestrian_plane_color: Color = Color(1.0, 0.5, 0.0, 0.6)
@export_range(0.0, 1.0) var pedestrian_plane_transparency: float = 0.5

@export_group("Planos de Pisos")
@export var show_floor_planes: bool = false
@export var root_floor_plane_color: Color = Color(1.0, 0.0, 0.5, 0.4)
@export_range(0.0, 1.0) var root_floor_plane_transparency: float = 0.4
@export var normal_floor_plane_color: Color = Color(0.0, 0.5, 1.0, 0.3)
@export_range(0.0, 1.0) var normal_floor_plane_transparency: float = 0.3

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphCityGenerator = null
var neighborhood_colors: Dictionary = {}
var root_floors: Array[int] = []

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
	
	var block_cell_height = min_distance / block_grid_rows
	var building_cell_height = min_distance / building_grid_rows
	
	_generate_root_floors()
	
	generator.generate_city_graph(
		smoothing_steps,
		region_size,
		min_distance,
		rejection_samples,
		generation_seed,
		num_large_streets,
		num_small_streets,
		block_grid_rows,
		block_grid_columns,
		block_grid_floors,
		block_cells_per_floor,
		boundary_offset,
		small_street_offset,
		medium_street_offset,
		large_street_offset,
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
		block_cell_height,
		building_cell_height,
		root_floors,
		industrial_min_floors,
		industrial_max_floors,
		residential_min_floors,
		residential_max_floors,
		financial_min_floors,
		financial_max_floors,
		neighborhood_height_falloff,
		industrial_block_heart_probability,
		residential_block_heart_probability,
		financial_block_heart_probability
	)
	
	_generate_neighborhood_colors()

func _generate_root_floors() -> void:
	root_floors.clear()
	root_floors.append(0)
	
	if use_generation_seed_for_roots:
		seed(generation_seed)
	
	var current_floor = 0
	
	while current_floor < block_grid_floors:
		var root_height = randi_range(min_root_floor_height, max_root_floor_height)
		current_floor += root_height
		
		if current_floor < block_grid_floors:
			root_floors.append(current_floor)
	
	print("[Visualizer] Root floors generados: %s" % str(root_floors))

func _generate_neighborhood_colors() -> void:
	neighborhood_colors.clear()
	neighborhood_colors[0] = Color(0.3, 0.35, 0.4, 0.7)
	neighborhood_colors[1] = Color(0.3, 0.5, 0.3, 0.7)
	neighborhood_colors[2] = Color(0.6, 0.5, 0.2, 0.7)

func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return
	
	_visualize_streets()
	
	if show_floor_planes:
		_visualize_floor_planes()
	
	if show_buildings:
		_visualize_buildings()
	
	if show_building_colliders:
		_visualize_building_colliders()
	
	if show_distorted_grid:
		_visualize_distorted_grids()
	
	if show_lanes:
		_visualize_lanes()
	
	if show_pedestrian_planes:
		_visualize_pedestrian_planes()
	
	if show_nodes:
		_visualize_nodes()

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
# VISUALIZACIÓN DE PLANOS DE PISOS
# ============================================
func _visualize_floor_planes() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_planes = 0
	var total_root_planes = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var floors = block.get_floors()
		var cells_per_floor = block.get_cells_per_floor()
		var cell_height = block.get_cell_height()
		
		var face_nodes = generator.plain_graph.faces[face_idx]
		var face_vertices_3d: Array[Vector3] = []
		
		for node_idx in face_nodes:
			face_vertices_3d.append(generator.plain_graph.points[node_idx])
		
		if face_vertices_3d.size() != 4:
			continue
		
		for floor in range(floors):
			var y = floor * cells_per_floor * cell_height
			
			var is_root_floor = floor in root_floors
			
			var color: Color
			var transparency: float
			
			if is_root_floor:
				color = root_floor_plane_color
				transparency = root_floor_plane_transparency
				total_root_planes += 1
			else:
				color = normal_floor_plane_color
				transparency = normal_floor_plane_transparency
			
			var v1 = Vector3(face_vertices_3d[0].x, y, face_vertices_3d[0].z)
			var v2 = Vector3(face_vertices_3d[1].x, y, face_vertices_3d[1].z)
			var v3 = Vector3(face_vertices_3d[2].x, y, face_vertices_3d[2].z)
			var v4 = Vector3(face_vertices_3d[3].x, y, face_vertices_3d[3].z)
			
			var plane = DebugUtil.create_debug_plane(v1, v2, v3, v4, color, transparency)
			add_child(plane)
			total_planes += 1
	
	print("[Visualizer] Planos de pisos: %d (%d root, %d normal) en %d bloques" % [total_planes, total_root_planes, total_planes - total_root_planes, all_block_faces.size()])

# ============================================
# VISUALIZACIÓN DE BUILDINGS (CON CLUSTERS)
# ============================================
func _visualize_buildings() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_clusters = 0
	var total_cells = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var distorted = block.get_distorted_grid()
		if distorted == null:
			continue
		
		var cells_per_floor = block.get_cells_per_floor()
		var cell_height = block.get_cell_height()
		var building_height = cells_per_floor * cell_height
		var is_clockwise = block.is_clockwise
		
		var clusters = block.get_all_clusters()
		total_clusters += clusters.size()
		
		for cluster in clusters:
			var cluster_floors = cluster.get_floor_count()
			
			for floor in range(cluster_floors):
				var floor_base_y = floor * cells_per_floor * cell_height
				
				for cell in cluster.cells:
					var x = cell.x
					var z = cell.y
					
					var building: Building = block.get_building(x, z, floor)
					
					if building == null:
						continue
					
					var core_vertices = building.get_core_vertices(0)
					
					if core_vertices.size() != 4:
						continue
					
					var core_info = building.get_core_info()
					if core_info["width"] <= 0 or core_info["depth"] <= 0:
						continue
					
					for i in range(core_vertices.size()):
						core_vertices[i].y += floor_base_y
					
					if is_clockwise:
						var temp = core_vertices[1]
						core_vertices[1] = core_vertices[3]
						core_vertices[3] = temp
					
					var cube = DebugUtil.create_skewed_cube(
						core_vertices,
						building_height,
						cluster.color																		
					)
					add_child(cube)
					total_cells += 1
	
	print("[Visualizer] Buildings: %d clusters (%d cells total) en %d bloques" % [total_clusters, total_cells, all_block_faces.size()])

# ============================================
# VISUALIZACIÓN DE COLLIDERS DE BUILDINGS
# ============================================
func _visualize_building_colliders() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_colliders = 0
	var total_blocks = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var distorted = block.get_distorted_grid()
		if distorted == null:
			continue
		
		var cells_per_floor = block.get_cells_per_floor()
		var cell_height = block.get_cell_height()
		var building_height = cells_per_floor * cell_height
		var is_clockwise = block.is_clockwise
		
		var clusters = block.get_all_clusters()
		
		for cluster in clusters:
			var static_body = StaticBody3D.new()
			var has_colliders = false
			
			var cluster_floors = cluster.get_floor_count()
			
			for floor in range(cluster_floors):
				var floor_base_y = floor * cells_per_floor * cell_height
				
				for cell in cluster.cells:
					var x = cell.x
					var z = cell.y
					
					var building: Building = block.get_building(x, z, floor)
					
					if building == null:
						continue
					
					var core_vertices = building.get_core_vertices(0)
					
					if core_vertices.size() != 4:
						continue
					
					var core_info = building.get_core_info()
					if core_info["width"] <= 0 or core_info["depth"] <= 0:
						continue
					
					for i in range(core_vertices.size()):
						core_vertices[i].y += floor_base_y
					
					if is_clockwise:
						var temp = core_vertices[1]
						core_vertices[1] = core_vertices[3]
						core_vertices[3] = temp
					
					var collision_shape = _create_collision_shape_from_vertices(
						core_vertices,
						building_height
					)
					
					if collision_shape != null:
						static_body.add_child(collision_shape)
						has_colliders = true
			
			if has_colliders:
				add_child(static_body)
				total_colliders += 1
		
		if clusters.size() > 0:
			total_blocks += 1
	
	print("[Visualizer] Colliders: %d clusters en %d manzanas" % [total_colliders, total_blocks])

func _create_collision_shape_from_vertices(base_vertices: Array, height: float) -> CollisionShape3D:
	if base_vertices.size() != 4:
		return null
	
	var bottom_verts = base_vertices
	var top_verts = []
	
	for i in range(4):
		top_verts.append(bottom_verts[i] + Vector3(0, height, 0))
	
	var points = PackedVector3Array()
	
	for v in bottom_verts:
		points.append(v)
	
	for v in top_verts:
		points.append(v)
	
	var convex_shape = ConvexPolygonShape3D.new()
	convex_shape.points = points
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = convex_shape
	
	return collision_shape

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
		
		var vertex_cache: Dictionary = {}
		
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
		
		for grid_z in range(distorted.rows + 1):
			for grid_x in range(distorted.columns + 1):
				var pos_2d = get_vertex.call(grid_x, grid_z)
				var pos_3d = Vector3(pos_2d.x, distorted_grid_height_offset, pos_2d.y)
				
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
					var path_type = path_gen.get_path_edge_type_vertices(grid_x, grid_z, grid_x + 1, grid_z, distorted_grid_floor_to_show)
					
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
					var path_type = path_gen.get_path_edge_type_vertices(grid_x, grid_z, grid_x, grid_z + 1, distorted_grid_floor_to_show)
					
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
	
	var red_even = Color(1.0, 0.0, 0.0, 0.5)
	var green_even = Color(0.0, 1.0, 0.0, 0.5)
	var red_odd = Color(0.6, 0.0, 0.0, 0.5)
	var green_odd = Color(0.0, 0.6, 0.0, 0.5)
	
	var max_building_height_global = generator.get_max_building_height_global()
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var lane_height = block.get_lane_height()
		
		var num_lane_floors = 0
		if lane_height > 0:
			num_lane_floors = int(ceil(max_building_height_global / lane_height))
		
		var all_lanes = block.get_all_lanes()
		
		for lane_data in all_lanes:
			var cell1: Vector2i = lane_data["cell1"]
			var cell2: Vector2i = lane_data["cell2"]
			var additional_width: int = lane_data["additional_width"]
			var side: String = lane_data["side"]
			
			var lane_edges = block.get_lane_edges(cell1, cell2, additional_width, side)
			
			if lane_edges["start_edge"].size() != 2 or lane_edges["end_edge"].size() != 2:
				continue
			
			var start_v1_base = lane_edges["start_edge"][0]
			var start_v2_base = lane_edges["start_edge"][1]
			var end_v1_base = lane_edges["end_edge"][0]
			var end_v2_base = lane_edges["end_edge"][1]
			
			for floor_idx in range(num_lane_floors):
				var floor_y = floor_idx * lane_height
				
				var red_color = red_even if floor_idx % 2 == 0 else red_odd
				var green_color = green_even if floor_idx % 2 == 0 else green_odd
				
				var start_plane = DebugUtil.create_debug_plane(
					start_v1_base + Vector3(0, floor_y, 0),
					start_v2_base + Vector3(0, floor_y, 0),
					start_v2_base + Vector3(0, floor_y + lane_height, 0),
					start_v1_base + Vector3(0, floor_y + lane_height, 0),
					red_color,
					0.5
				)
				add_child(start_plane)
				
				var end_plane = DebugUtil.create_debug_plane(
					end_v1_base + Vector3(0, floor_y, 0),
					end_v2_base + Vector3(0, floor_y, 0),
					end_v2_base + Vector3(0, floor_y + lane_height, 0),
					end_v1_base + Vector3(0, floor_y + lane_height, 0),
					green_color,
					0.5
				)
				add_child(end_plane)
	
	print("[Visualizer] Planos de lanes verticales (altura global): ROJO=inicio, VERDE=fin")

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
