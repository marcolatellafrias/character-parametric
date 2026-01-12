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
@export var num_neighborhoods: int = 5
@export var neighborhood_seed: int = -1  # -1 usa generation_seed
@export_range(0.1, 5.0) var neighborhood_height_falloff: float = 1.0

@export_group("Suavizado")
@export var smoothing_steps: int = 50

@export_group("Visualización General")
@export var show_streets: bool = true
@export var show_nodes: bool = false
@export var node_radius: float = 0.08
@export var normal_node_color: Color = Color.CHARTREUSE
@export var boundary_node_color: Color = Color.ORANGE_RED
@export var auto_generate: bool = true

@export_group("Tipos de Calles")
@export var num_large_streets: int = 6
@export var num_small_streets: int = 12

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
@export var show_building_colliders: bool = true

@export_group("Planos Peatonales")
@export var show_pedestrian_planes: bool = false
@export var pedestrian_plane_color: Color = Color(1.0, 0.5, 0.0, 0.6)
@export_range(0.0, 1.0) var pedestrian_plane_transparency: float = 0.5

@export_group("Planos de Pisos")
@export var show_floor_planes: bool = false
@export var floor_plane_color: Color = Color(0.0, 0.5, 1.0, 0.3)
@export_range(0.0, 1.0) var floor_plane_transparency: float = 0.3

@export_group("Lane Planes - Planos Finales")
@export var show_lane_planes: bool = false
@export_range(0.0, 1.0) var lane_plane_transparency: float = 0.5

@export_group("Lane Volumes - Volúmenes de Edges")
@export var show_lane_volumes: bool = false
@export_range(0.0, 1.0) var lane_volume_transparency: float = 0.3
@export var lane_volume_color: Color = Color(0.5, 0.5, 1.0, 0.5)

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphCityGenerator = null
var lane_volume_areas: Dictionary = {}  # Key: "face_idx_edge_idx", Value: LaneVolumeArea3D

# ============================================
# INICIALIZACIÓN
# ============================================
func _ready() -> void:
	add_to_group("city_generator")
	
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
		neighborhood_height_falloff,
		num_neighborhoods,
		neighborhood_seed
	)

func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return
	
	_generate_lane_volume_areas()
	
	if show_streets:
		_visualize_streets()
	
	if show_floor_planes:
		_visualize_floor_planes()
	
	if show_buildings:
		_visualize_buildings()
	
	if show_building_colliders:
		_visualize_building_colliders()
	
	if show_distorted_grid:
		_visualize_distorted_grids()
	
	if show_pedestrian_planes:
		_visualize_pedestrian_planes()
	
	if show_lane_planes:
		_visualize_lane_planes()
	
	if show_lane_volumes:
		_visualize_lane_volumes()
	
	if show_nodes:
		_visualize_nodes()

# ============================================
# GENERACIÓN DE LANE VOLUME AREAS
# ============================================
func _generate_lane_volume_areas() -> void:
	lane_volume_areas.clear()
	var all_block_faces = generator.get_all_block_faces()
	var total_areas = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var face = generator.plain_graph.faces[face_idx]
		
		for edge_idx in range(4):
			var volume_data = block.get_edge_lane_volume(edge_idx)
			
			if volume_data.is_empty():
				continue
			
			var street_type = volume_data.get("street_type", 0)
			var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(street_type, 3)
			
			var height_cells = 0
			if generator.block_cell_height > 0 and generator.cells_per_floor > 0:
				var floor_height = generator.cells_per_floor * generator.block_cell_height
				var num_floors = ceil(volume_data["height"] / floor_height)
				height_cells = int(num_floors * generator.cells_per_floor)
			
			# Obtener los nodos del edge
			var node1 = face[edge_idx]
			var node2 = face[(edge_idx + 1) % face.size()]
			
			# Determinar barrio del edge (mayor jerarquía)
			var edge_neighborhood = generator.get_neighborhood_for_edge(node1, node2)
			
			var enriched_data = volume_data.duplicate()
			enriched_data["face_idx"] = face_idx
			enriched_data["edge_idx"] = edge_idx
			enriched_data["width_cells"] = width_cells
			enriched_data["height_cells"] = height_cells
			enriched_data["neighborhood"] = edge_neighborhood
			enriched_data["cells_per_floor"] = generator.cells_per_floor
			
			var lane_volume = LaneVolume.new(enriched_data)
			add_child(lane_volume)
			
			var key = "%d_%d" % [face_idx, edge_idx]
			lane_volume_areas[key] = lane_volume
			
			total_areas += 1
	
	print("[CityVisualizer] Lane Volume Areas generados: %d" % total_areas)

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
		
		var color = boundary_node_color if node_type == 1 else normal_node_color
		
		var sphere = DebugUtil.create_debug_sphere(color, node_radius)
		sphere.position = point
		add_child(sphere)

# ============================================
# VISUALIZACIÓN DE PLANOS DE PISOS
# ============================================
func _visualize_floor_planes() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_planes = 0
	
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
			
			var v1 = Vector3(face_vertices_3d[0].x, y, face_vertices_3d[0].z)
			var v2 = Vector3(face_vertices_3d[1].x, y, face_vertices_3d[1].z)
			var v3 = Vector3(face_vertices_3d[2].x, y, face_vertices_3d[2].z)
			var v4 = Vector3(face_vertices_3d[3].x, y, face_vertices_3d[3].z)
			
			var plane = DebugUtil.create_debug_plane(v1, v2, v3, v4, floor_plane_color, floor_plane_transparency)
			add_child(plane)
			total_planes += 1
	
	print("[Visualizer] Planos de pisos: %d en %d bloques" % [total_planes, all_block_faces.size()])

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
				
				var vertex_color = distorted_grid_boundary_vertex_color if is_boundary else distorted_grid_normal_vertex_color
				
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

# ============================================
# VISUALIZACIÓN DE LANE PLANES FINALES
# ============================================
func _visualize_lane_planes() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_planes = 0
	var start_planes = 0
	var end_planes = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		var lane_planes_dict = block.get_lane_planes()
		
		for key in lane_planes_dict:
			var plane_data = lane_planes_dict[key]
			var start: Vector2 = plane_data["start"]
			var end: Vector2 = plane_data["end"]
			var is_start_lane: bool = plane_data["is_start_lane"]
			var height: float = plane_data["height"]
			
			var base_color: Color
			if is_start_lane:
				base_color = Color.RED
				start_planes += 1
			else:
				base_color = Color.GREEN
				end_planes += 1
			
			var v1 = Vector3(start.x, 0.0, start.y)
			var v2 = Vector3(end.x, 0.0, end.y)
			var v3 = Vector3(end.x, height, end.y)
			var v4 = Vector3(start.x, height, start.y)
			
			var plane = DebugUtil.create_debug_plane(v1, v2, v3, v4, base_color, lane_plane_transparency)
			add_child(plane)
			total_planes += 1
	
	print("[Visualizer] Lane planes finales: %d planos (%d rojos/start, %d verdes/end) en %d bloques" % [total_planes, start_planes, end_planes, all_block_faces.size()])

# ============================================
# VISUALIZACIÓN DE LANE VOLUMES (VOLÚMENES DE EDGES)
# ============================================
func _visualize_lane_volumes() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_volumes = 0
	
	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		
		if block == null:
			continue
		
		for edge_idx in range(4):
			var volume_data = block.get_edge_lane_volume(edge_idx)
			
			if volume_data.is_empty():
				continue
			
			var start_plane_verts = volume_data["start_plane_vertices"]
			var end_plane_verts = volume_data["end_plane_vertices"]
			
			if start_plane_verts.size() != 4 or end_plane_verts.size() != 4:
				push_warning("Volume de edge %d del bloque %d no tiene vértices correctos" % [edge_idx, face_idx])
				continue
			
			var skewed_cube = DebugUtil.create_skewed_cube_from_planes(
				start_plane_verts,
				end_plane_verts,
				lane_volume_color,
				lane_volume_transparency
			)
			
			if skewed_cube != null:
				add_child(skewed_cube)
				total_volumes += 1
	
	print("[Visualizer] Lane volumes: %d volúmenes visualizados en %d bloques" % [total_volumes, all_block_faces.size()])

# ============================================
# HELPERS PÚBLICOS PARA OTRAS ENTIDADES
# ============================================

func get_generator() -> GraphCityGenerator:
	return generator

func get_block_grid(face_idx: int) -> BlockGenerator:
	if generator == null:
		push_error("CityVisualizer: generator no inicializado")
		return null
	
	return generator.get_block_grid(face_idx)

func get_lane_volume_continuations(face_idx: int, edge_idx: int) -> Array[LaneVolume]:
	if generator == null:
		push_error("CityVisualizer: generator no inicializado")
		return []
	
	return generator.get_lane_volume_continuations(face_idx, edge_idx)

func get_lane_volume_area(face_idx: int, edge_idx: int) -> LaneVolume:
	var key = "%d_%d" % [face_idx, edge_idx]
	return lane_volume_areas.get(key, null)

func get_lane_volume_area_continuations(face_idx: int, edge_idx: int) -> Array[LaneVolume]:
	if generator == null:
		push_error("CityVisualizer: generator no inicializado")
		return []
	
	var continuations = generator.get_lane_volume_continuations(face_idx, edge_idx)
	
	var areas: Array[LaneVolume] = []
	for lane_vol in continuations:
		var area = get_lane_volume_area(lane_vol.face_idx, lane_vol.edge_idx)
		if area:
			areas.append(area)
	
	return areas
