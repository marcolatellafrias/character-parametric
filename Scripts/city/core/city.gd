# CityVisualizer.gd
extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(800/2, 800/2)
@export var min_distance: float = 180.5*1.3
@export var rejection_samples: int = 90
@export var generation_seed: int = 123456

@export_group("Barrios")
@export var num_neighborhoods: int = 10
@export var neighborhood_seed: int = -1
@export_range(0.1, 5.0) var neighborhood_height_falloff: float = 0.3

@export_group("Suavizado")
@export var smoothing_steps: int = 40

@export_group("Visualización General")
@export var show_streets: bool = true
@export var show_nodes: bool = false
@export var node_radius: float = 0.08
@export var normal_node_color: Color = Color.CHARTREUSE
@export var boundary_node_color: Color = Color.ORANGE_RED
@export var auto_generate: bool = true

@export_group("Tipos de Calles")
@export var num_large_streets: int = 6
@export var num_small_streets: int = 10

@export_subgroup("Calles Pequeñas (Tipo 0)")
@export var small_street_color: Color = Color.WHITE
@export var small_street_width: float = 0.01

@export_subgroup("Calles Medianas (Tipo 1)")
@export var medium_street_color: Color = Color.CYAN
@export var medium_street_width: float = 0.02

@export_subgroup("Calles Grandes (Tipo 2)")
@export var large_street_color: Color = Color.MAGENTA
@export var large_street_width: float = 0.04

@export_subgroup("Calles Límite (Tipo -1)")
@export var boundary_street_color: Color = Color.ORANGE_RED
@export var boundary_street_width: float = 0.05

@export_group("Grillas de Manzanas")
@export var block_grid_rows: int = 100
@export var block_grid_columns: int = 100
@export var block_cells_per_floor: int = 32

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
@export var building_grid_rows: int = 80
@export var building_grid_columns: int = 80

@export_subgroup("Visualización de Grilla Distorsionada")
@export var show_distorted_grid: bool = true
@export var distorted_grid_floor_to_show: int = 0
@export var distorted_grid_vertex_radius: float = 0.04
@export var distorted_grid_normal_vertex_color: Color = Color.CYAN
@export var distorted_grid_facade_vertex_color: Color = Color.RED
@export var distorted_grid_normal_edge_color: Color = Color.WHITE
@export var distorted_grid_small_edge_color: Color = Color.YELLOW
@export var distorted_grid_big_edge_color: Color = Color.ORANGE
@export var distorted_grid_small_origin_edge_color: Color = Color.GREEN
@export var distorted_grid_big_origin_edge_color: Color = Color.MAGENTA
@export var distorted_grid_facade_edge_color: Color = Color.ORANGE_RED
@export var distorted_grid_edge_width: float = 0.015
@export var distorted_grid_height_offset: float = 0.1

@export_group("Buildings")
@export var show_buildings: bool = false
@export var enable_building_colliders: bool = true
@export var alternate_floor_shading: bool = true
@export var alternate_module_shading: bool = true
@export_range(0.1, 0.9) var floor_shade_factor: float = 0.85

@export_group("Planos de Pisos")
@export var show_floor_planes: bool = false
@export var floor_plane_color: Color = Color(0.0, 0.5, 1.0, 0.3)
@export_range(0.0, 1.0) var floor_plane_transparency: float = 0.3

@export_group("Lane Planes - Planos Finales")
@export var show_lane_planes: bool = false
@export_range(0.0, 1.0) var lane_plane_transparency: float = 0.85

@export_group("Lane Volumes - Volúmenes de Edges")
@export var show_lane_volumes: bool = false
@export_range(0.0, 1.0) var lane_volume_transparency: float = 1.0
@export var lane_volume_color: Color = Color(0.5, 0.5, 1.0, 0.5)

@export_group("Traffic Planes")
@export var show_traffic_planes: bool = false
@export_range(0.0, 1.0) var traffic_plane_transparency: float = 0.1
@export var traffic_plane_green_color: Color = Color.GREEN
@export var traffic_plane_red_color: Color = Color.RED

@export_group("Traffic Lights")
@export var enable_traffic_lights: bool = true
@export var traffic_light_cycle_duration: float = 5.0

@export var show_sidewalk_matrices: bool = false

@export_group("Delivery Doors")
@export var show_delivery_doors: bool = false
@export var delivery_door_color: Color = Color(0.9, 0.9, 0.85)

@export_group("Puentes")
@export var show_bridges: bool = true
@export var enable_bridge_colliders: bool = true
@export var bridge_arc_color: Color = Color(0.8, 0.2, 0.2)
@export var bridge_base_color: Color = Color(0.55, 0.55, 0.55)
@export var bridge_pathway_color: Color = Color(0.9, 0.8, 0.2)
@export var bridge_railing_color: Color = Color(0.2, 0.75, 0.9)

# ============================================
# DATOS DEL GRAFO
# ============================================
var generator: GraphCityGenerator = null
var traffic_light_timer: float = 0.0
var active_traffic_index: int = 0

# ============================================
# INICIALIZACIÓN
# ============================================
func _ready() -> void:
	add_to_group("city_generator")

	if auto_generate:
		generate_and_visualize()

func _process(delta: float) -> void:
	if not enable_traffic_lights or generator == null:
		return

	traffic_light_timer += delta

	if traffic_light_timer >= traffic_light_cycle_duration:
		traffic_light_timer = 0.0
		active_traffic_index = 1 - active_traffic_index
		_on_traffic_cycle_changed()

# Consolida la actualización de LaneVolumes y de los meshes de debug en un solo lugar.
func _on_traffic_cycle_changed() -> void:
	for key in generator.lane_volume_areas:
		var vol: LaneVolume = generator.lane_volume_areas[key]
		var traffic_plane = vol.get_traffic_plane()
		if traffic_plane:
			traffic_plane.update_layer_for_active_index(active_traffic_index)

	if show_traffic_planes:
		_refresh_traffic_plane_colors()

func _refresh_traffic_plane_colors() -> void:
	for child in get_children():
		if not child.has_meta("traffic_plane_visual"):
			continue

		var traffic_index = child.get_meta("traffic_index", -1)
		if traffic_index == -1:
			continue

		var mesh_instance = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.material_override == null:
			continue

		var material = mesh_instance.material_override as StandardMaterial3D
		if material == null:
			continue

		var color: Color = traffic_plane_green_color if traffic_index == active_traffic_index else traffic_plane_red_color
		color.a = traffic_plane_transparency
		material.albedo_color = color

# ============================================
# GENERACIÓN Y VISUALIZACIÓN
# ============================================
func generate_and_visualize() -> void:
	clear_visualization()
	generate_graph()
	visualize_graph()

func generate_graph() -> void:
	generator = GraphCityGenerator.new()

	var legacy_block_cell_height = min_distance / block_grid_rows

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
		legacy_block_cell_height,
		0.0,
		neighborhood_height_falloff,
		num_neighborhoods,
		neighborhood_seed
	)

# Libera solo los hijos visuales; el generator se reemplaza en generate_graph().
func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return

	_add_lane_volumes_to_scene()

	if show_streets:
		_visualize_streets()

	if show_floor_planes:
		_visualize_floor_planes()

	if show_buildings:
		_visualize_buildings()

	if enable_building_colliders:
		_visualize_building_colliders()

	if show_distorted_grid:
		_visualize_distorted_grids()

	if show_lane_planes:
		_visualize_lane_planes()

	if show_lane_volumes:
		_visualize_lane_volumes()

	if show_traffic_planes:
		_visualize_traffic_planes()

	if show_nodes:
		_visualize_nodes()
		
	if show_sidewalk_matrices:
		_visualize_sidewalk_matrices()

	_visualize_sidewalks()

	if show_bridges:
		_visualize_bridges()

	if show_delivery_doors:
		_visualize_delivery_doors()

# LaneVolume es Node3D y necesita estar en el árbol para funcionar.
# Si en el futuro se convierte a RefCounted, este método desaparece.
func _add_lane_volumes_to_scene() -> void:
	var total = 0
	for key in generator.lane_volume_areas:
		add_child(generator.lane_volume_areas[key])
		total += 1
	print("[Visualizer] Lane Volume Areas agregados a la escena: %d" % total)

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

		add_child(DebugUtil.create_debug_line_to_from(p1, p2, color, width))

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

		var max_floors = 0
		for cluster in block.get_all_clusters():
			max_floors = max(max_floors, cluster.get_floor_count())

		var cells_per_floor = block.get_cells_per_floor()
		var building_cell_height = block.get_building_cell_height()

		var face_nodes = generator.plain_graph.faces[face_idx]
		var face_vertices_3d: Array[Vector3] = []
		for node_idx in face_nodes:
			face_vertices_3d.append(generator.plain_graph.points[node_idx])

		if face_vertices_3d.size() != 4:
			continue

		for floor in range(max_floors):
			var y = floor * cells_per_floor * building_cell_height
			var v1 = Vector3(face_vertices_3d[0].x, y, face_vertices_3d[0].z)
			var v2 = Vector3(face_vertices_3d[1].x, y, face_vertices_3d[1].z)
			var v3 = Vector3(face_vertices_3d[2].x, y, face_vertices_3d[2].z)
			var v4 = Vector3(face_vertices_3d[3].x, y, face_vertices_3d[3].z)

			add_child(DebugUtil.create_debug_plane(v1, v2, v3, v4, floor_plane_color, floor_plane_transparency))
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
		if block == null or block.get_distorted_grid() == null:
			continue

		var cells_per_floor = block.get_cells_per_floor()
		var building_cell_height = block.get_building_cell_height()
		var building_height = cells_per_floor * building_cell_height

		var clusters = block.get_all_clusters()
		total_clusters += clusters.size()

		for cluster in clusters:
			var cluster_floors = cluster.get_floor_count()
			var base_color = cluster.color

			for floor in range(cluster_floors):
				var floor_base_y = floor * cells_per_floor * building_cell_height

				var floor_color: Color
				if alternate_floor_shading:
					floor_color = base_color if floor % 2 == 0 else base_color.darkened(1.0 - floor_shade_factor)
				else:
					floor_color = base_color

				for cell in cluster.cells:
					var building_module: BuildingModule = block.get_building_module(cell.x, cell.y, floor)
					if building_module == null:
						continue

					var core_vertices = building_module.get_core_vertices(0)
					if core_vertices.size() != 4:
						continue

					var core_info = building_module.get_core_info()
					if core_info["width"] <= 0 or core_info["depth"] <= 0:
						continue

					for i in range(core_vertices.size()):
						core_vertices[i].y += floor_base_y

					var module_color = floor_color
					if alternate_module_shading and (cell.x + cell.y) % 2 == 1:
						module_color = floor_color.darkened(1.0 - floor_shade_factor)

					add_child(DebugUtil.create_skewed_cube_advanced_grid(
						core_vertices,
						building_height,
						module_color,
						building_module.get_chamfers(),
						core_info["depth"],
						core_info["width"],
						false
					))
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
		if block == null or block.get_distorted_grid() == null:
			continue

		var cells_per_floor = block.get_cells_per_floor()
		var building_cell_height = block.get_building_cell_height()
		var building_height = cells_per_floor * building_cell_height
		var clusters = block.get_all_clusters()

		for cluster in clusters:
			var static_body = StaticBody3D.new()
			var has_colliders = false

			for floor in range(cluster.get_floor_count()):
				var floor_base_y = floor * cells_per_floor * building_cell_height

				for cell in cluster.cells:
					var building_module: BuildingModule = block.get_building_module(cell.x, cell.y, floor)
					if building_module == null:
						continue

					var core_vertices = building_module.get_core_vertices(0)
					if core_vertices.size() != 4:
						continue

					var core_info = building_module.get_core_info()
					if core_info["width"] <= 0 or core_info["depth"] <= 0:
						continue

					for i in range(core_vertices.size()):
						core_vertices[i].y += floor_base_y

					var collision_body = DebugUtil.create_skewed_cube_advanced_grid_collider(
						core_vertices,
						building_height,
						building_module.get_chamfers(),
						core_info["depth"],
						core_info["width"]
					)

					if collision_body != null:
						for child in collision_body.get_children():
							if child is CollisionShape3D:
								collision_body.remove_child(child)
								static_body.add_child(child)
								has_colliders = true
						collision_body.queue_free()

			if has_colliders:
				add_child(static_body)
				total_colliders += 1

		if clusters.size() > 0:
			total_blocks += 1

	print("[Visualizer] Colliders: %d clusters en %d manzanas" % [total_colliders, total_blocks])

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
				var is_facade = (grid_x == 0 or grid_x == distorted.columns or
								grid_z == 0 or grid_z == distorted.rows)

				var sphere: Node3D
				if is_facade:
					sphere = DebugUtil.create_debug_sphere_2dprint(Vector2i(grid_x, grid_z), distorted_grid_facade_vertex_color, distorted_grid_vertex_radius)
				else:
					sphere = DebugUtil.create_debug_sphere(distorted_grid_normal_vertex_color, distorted_grid_vertex_radius)

				sphere.position = pos_3d
				add_child(sphere)
				total_vertices += 1

		for grid_z in range(distorted.rows + 1):
			for grid_x in range(distorted.columns):
				var pos1_3d = Vector3(get_vertex.call(grid_x, grid_z).x, distorted_grid_height_offset, get_vertex.call(grid_x, grid_z).y)
				var pos2_3d = Vector3(get_vertex.call(grid_x + 1, grid_z).x, distorted_grid_height_offset, get_vertex.call(grid_x + 1, grid_z).y)

				var edge_color: Color
				if grid_z == 0 or grid_z == distorted.rows:
					edge_color = distorted_grid_facade_edge_color
				else:
					var path_type = path_gen.get_path_edge_type_vertices(grid_x, grid_z, grid_x + 1, grid_z, distorted_grid_floor_to_show)
					edge_color = _path_type_to_color(path_type)

				add_child(DebugUtil.create_debug_line_to_from(pos1_3d, pos2_3d, edge_color, distorted_grid_edge_width))
				total_edges += 1

		for grid_z in range(distorted.rows):
			for grid_x in range(distorted.columns + 1):
				var pos1_3d = Vector3(get_vertex.call(grid_x, grid_z).x, distorted_grid_height_offset, get_vertex.call(grid_x, grid_z).y)
				var pos2_3d = Vector3(get_vertex.call(grid_x, grid_z + 1).x, distorted_grid_height_offset, get_vertex.call(grid_x, grid_z + 1).y)

				var edge_color: Color
				if grid_x == 0 or grid_x == distorted.columns:
					edge_color = distorted_grid_facade_edge_color
				else:
					var path_type = path_gen.get_path_edge_type_vertices(grid_x, grid_z, grid_x, grid_z + 1, distorted_grid_floor_to_show)
					edge_color = _path_type_to_color(path_type)

				add_child(DebugUtil.create_debug_line_to_from(pos1_3d, pos2_3d, edge_color, distorted_grid_edge_width))
				total_edges += 1

	print("[Visualizer] Grillas distorsionadas: %d vértices, %d edges en %d bloques" % [total_vertices, total_edges, all_block_faces.size()])

func _path_type_to_color(path_type: DistortedGrid.CellType) -> Color:
	match path_type:
		DistortedGrid.CellType.BIG:          return distorted_grid_big_edge_color
		DistortedGrid.CellType.SMALL:        return distorted_grid_small_edge_color
		DistortedGrid.CellType.SMALL_ORIGIN: return distorted_grid_small_origin_edge_color
		DistortedGrid.CellType.BIG_ORIGIN:   return distorted_grid_big_origin_edge_color
		_:                                    return distorted_grid_normal_edge_color

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

		for key in block.get_lane_planes():
			var plane_data = block.get_lane_planes()[key]
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

			add_child(DebugUtil.create_debug_plane(v1, v2, v3, v4, base_color, lane_plane_transparency))
			total_planes += 1

	print("[Visualizer] Lane planes: %d (%d rojos, %d verdes) en %d bloques" % [total_planes, start_planes, end_planes, all_block_faces.size()])

# ============================================
# VISUALIZACIÓN DE LANE VOLUMES
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

			var skewed_cube = DebugUtil.create_skewed_cube_from_planes(start_plane_verts, end_plane_verts, lane_volume_color, lane_volume_transparency)
			if skewed_cube != null:
				add_child(skewed_cube)
				total_volumes += 1

	print("[Visualizer] Lane volumes: %d en %d bloques" % [total_volumes, all_block_faces.size()])

# ============================================
# VISUALIZACIÓN DE TRAFFIC PLANES
# ============================================
func _visualize_traffic_planes() -> void:
	var total_planes = 0
	var index_0_count = 0
	var index_1_count = 0
	var unassigned_count = 0

	for key in generator.lane_volume_areas:
		var vol: LaneVolume = generator.lane_volume_areas[key]
		var traffic_plane = vol.get_traffic_plane()
		if not traffic_plane:
			continue

		var traffic_index = vol.get_traffic_index()
		if traffic_index == -1:
			unassigned_count += 1
			continue

		var end_verts = traffic_plane.get_end_vertices()
		if end_verts.size() != 4:
			continue

		if traffic_index == 0:
			index_0_count += 1
		else:
			index_1_count += 1

		var mesh_instance = MeshInstance3D.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)

		var vertices = PackedVector3Array([end_verts[0], end_verts[1], end_verts[2], end_verts[3]])
		var indices = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var normal = (end_verts[1] - end_verts[0]).cross(end_verts[2] - end_verts[0]).normalized()
		var normals = PackedVector3Array([normal, normal, normal, normal])

		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices

		var array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh_instance.mesh = array_mesh

		var material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		material.cull_mode = BaseMaterial3D.CULL_DISABLED

		var color: Color = traffic_plane_green_color if traffic_index == active_traffic_index else traffic_plane_red_color
		color.a = traffic_plane_transparency
		material.albedo_color = color

		mesh_instance.material_override = material
		mesh_instance.set_meta("traffic_plane_visual", true)
		mesh_instance.set_meta("traffic_index", traffic_index)

		add_child(mesh_instance)
		total_planes += 1

	print("[Visualizer] Traffic planes: %d (índice 0: %d, índice 1: %d, sin asignar: %d)" % [total_planes, index_0_count, index_1_count, unassigned_count])

# ============================================
# HELPERS PÚBLICOS
# ============================================
func get_generator() -> GraphCityGenerator:
	return generator

func get_block_grid(face_idx: int) -> BlockGenerator:
	if generator == null:
		push_error("CityVisualizer: generator no inicializado")
		return null
	return generator.get_block_grid(face_idx)

func _visualize_sidewalk_matrices() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_cells = 0
	var available_cells = 0

	for face_idx in all_block_faces:
		var helper: SidewalkMatrix = generator.get_sidewalk_matrix(face_idx)
		if helper == null:
			continue

		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue

		for coord_key in helper.matrices:
			var parts = coord_key.split("_")
			var coord = Vector2i(int(parts[0]), int(parts[1]))

			var base_module: BuildingModule = block.get_building_module(coord.x, coord.y, 0)
			if base_module == null:
				continue

			var cell_matrix = helper.matrices[coord_key]
			var building_cell_height = cell_matrix["cell_height"]

			for cell_key in cell_matrix["cells"]:
				var cell = cell_matrix["cells"][cell_key]
				var cell_state: int = cell["state"]
				var color: Color
				match cell_state:
					SidewalkMatrix.CellState.AVAILABLE:   color = Color(0.0, 1.0, 0.0, 0.5)
					SidewalkMatrix.CellState.ROOF_ONLY:   color = Color(0.0, 0.5, 1.0, 0.5)
					_:                                        color = Color(1.0, 0.0, 0.0, 0.5)

				var bottom_vertices = base_module.get_cell_vertices(cell["bx"], cell["bz"], cell["height_index"])
				if bottom_vertices.size() != 4:
					continue

				add_child(DebugUtil.create_skewed_cube(bottom_vertices, building_cell_height, color, true))

				total_cells += 1
				if cell_state == SidewalkMatrix.CellState.AVAILABLE:
					available_cells += 1

	print("[Visualizer] Building grid cells: %d total (%d available, %d unavailable)" % [
		total_cells, available_cells, total_cells - available_cells
	])


# ============================================
# VISUALIZACIÓN DE SIDEWALKS
# ============================================

func _visualize_sidewalks() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_pieces = 0

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue

		var grid = block.get_distorted_grid()
		if grid == null:
			continue

		var cell_height = block.get_building_cell_height()
		var sidewalk_h = cell_height

		var corner_verts = _get_sidewalk_corner_verts(block, grid)
		if corner_verts.is_empty():
			continue

		# 4 corners
		for key in corner_verts:
			var verts = corner_verts[key]
			if verts.size() == 4:
				add_child(DebugUtil.create_skewed_cube(verts, sidewalk_h, Color(0.45, 0.43, 0.41)))
				total_pieces += 1

		# 4 sides — one piece per DG cell between the two corners
		# [edge_idx, fixed_coord, range_start, range_end]
		var cols = grid.columns
		var rows = grid.rows
		var side_edges = [
			[0, 0,       0, cols - 1],  # North: z=0, all x
			[1, cols - 1, 0, rows - 1], # East: x=cols-1, all z
			[2, rows - 1, 0, cols - 1], # South: z=rows-1, all x
			[3, 0,       0, rows - 1],  # West: x=0, all z
		]
		for side_info in side_edges:
			var edge_idx: int = side_info[0]
			var fixed: int = side_info[1]
			var range_start: int = side_info[2]
			var range_end: int = side_info[3]
			for i in range(range_start, range_end + 1):
				var coord: Vector2i
				if edge_idx == 0 or edge_idx == 2:
					coord = Vector2i(i, fixed)
				else:
					coord = Vector2i(fixed, i)
				var module = block.get_building_module(coord.x, coord.y, 0)
				if module == null:
					continue
				var core = module.get_core_info()
				var is_first = (i == range_start)
				var is_last = (i == range_end)
				var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
				match edge_idx:
					0:
						bx_min = core["min_x"] if is_first else 0
						bx_max = core["max_x"] if is_last else module.columns - 1
						bz_min = 0; bz_max = core["min_z"] - 1
					1:
						bx_min = core["max_x"] + 1; bx_max = module.columns - 1
						bz_min = core["min_z"] if is_first else 0
						bz_max = core["max_z"] if is_last else module.rows - 1
					2:
						bx_min = core["min_x"] if is_first else 0
						bx_max = core["max_x"] if is_last else module.columns - 1
						bz_min = core["max_z"] + 1; bz_max = module.rows - 1
					3:
						bx_min = 0; bx_max = core["min_x"] - 1
						bz_min = core["min_z"] if is_first else 0
						bz_max = core["max_z"] if is_last else module.rows - 1
				if bx_min > bx_max or bz_min > bz_max:
					continue
				var verts = module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, 0)
				if verts.size() == 4:
					add_child(DebugUtil.create_skewed_cube(verts, sidewalk_h, Color(0.5, 0.48, 0.46)))
					total_pieces += 1

	print("[Visualizer] Sidewalks: %d pieces" % total_pieces)


func _get_sidewalk_corner_verts(block: BlockGenerator, grid: DistortedGrid) -> Dictionary:
	var cols = grid.columns
	var rows = grid.rows
	var result = {}

	# Corner DG cells: NW=(0,0), NE=(cols-1,0), SE=(cols-1,rows-1), SW=(0,rows-1)
	var corner_cells = {
		"nw": Vector2i(0, 0),
		"ne": Vector2i(cols - 1, 0),
		"se": Vector2i(cols - 1, rows - 1),
		"sw": Vector2i(0, rows - 1),
	}

	for key in corner_cells:
		var coord = corner_cells[key]
		var module = block.get_building_module(coord.x, coord.y, 0)
		if module == null:
			continue

		var core = module.get_core_info()
		var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int

		match key:
			"nw":
				bx_min = 0; bx_max = core["min_x"] - 1
				bz_min = 0; bz_max = core["min_z"] - 1
			"ne":
				bx_min = core["max_x"] + 1; bx_max = module.columns - 1
				bz_min = 0; bz_max = core["min_z"] - 1
			"se":
				bx_min = core["max_x"] + 1; bx_max = module.columns - 1
				bz_min = core["max_z"] + 1; bz_max = module.rows - 1
			"sw":
				bx_min = 0; bx_max = core["min_x"] - 1
				bz_min = core["max_z"] + 1; bz_max = module.rows - 1

		if bx_min > bx_max or bz_min > bz_max:
			continue

		result[key] = module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, 0)

	return result




# ============================================
# VISUALIZACIÓN DE DELIVERY DOORS
# ============================================

func _visualize_delivery_doors() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total = 0

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue

		var cells_per_floor = block.get_cells_per_floor()
		var building_cell_height = block.get_building_cell_height()

		for door in block.delivery_doors:
			var cell: Vector2i = door["cell"]
			var edge_idx: int = door["edge"]
			var floor_idx: int = door["floor"]

			var module = block.get_building_module(cell.x, cell.y, 0)
			if module == null:
				continue

			var core = module.get_core_info()
			var height_index = floor_idx * cells_per_floor
			var floor_height = cells_per_floor * building_cell_height

			var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
			match edge_idx:
				0:
					bx_min = core["min_x"]; bx_max = core["max_x"]
					bz_min = core["min_z"] - 1; bz_max = core["min_z"] - 1
				1:
					bx_min = core["max_x"] + 1; bx_max = core["max_x"] + 1
					bz_min = core["min_z"]; bz_max = core["max_z"]
				2:
					bx_min = core["min_x"]; bx_max = core["max_x"]
					bz_min = core["max_z"] + 1; bz_max = core["max_z"] + 1
				3:
					bx_min = core["min_x"] - 1; bx_max = core["min_x"] - 1
					bz_min = core["min_z"]; bz_max = core["max_z"]

			var verts = module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, height_index)
			if verts.size() == 4:
				add_child(DebugUtil.create_skewed_cube(verts, floor_height, delivery_door_color))
			total += 1

	print("[Visualizer] Delivery doors: %d" % total)


# ============================================
# VISUALIZACIÓN DE PUENTES
# ============================================

func _visualize_bridges() -> void:
	var total = 0
	for edge_key in generator.bridges:
		for placed in generator.bridges[edge_key]:
			_draw_bridge(placed)
			total += 1
	print("[Visualizer] Puentes: %d" % total)


func _draw_bridge(placed: Dictionary) -> void:
	var bridge: Bridge     = placed["bridge"]
	var cell_start: int    = placed["cell_start"]
	var cell_end: int      = placed["cell_end"]
	var floor_idx: int     = placed["floor_idx"]
	var cell_height: float = placed["cell_height"]
	var cells_per_floor: int = placed["cells_per_floor"]
	var facade_building_cells: int = placed["facade_building_cells"]
	var c_a1: Vector2      = placed["c_a1"]
	var c_a2: Vector2      = placed["c_a2"]
	var c_b1: Vector2      = placed["c_b1"]
	var c_b2: Vector2      = placed["c_b2"]

	var t_start = float(cell_start) / facade_building_cells
	var t_end = float(cell_end + 1) / facade_building_cells
	var t_one_cell = 1.0 / facade_building_cells

	var by_base = floor_idx * cells_per_floor - bridge.base_height
	var h_base_bot = by_base * cell_height
	var h_base_top = h_base_bot + bridge.base_height * cell_height
	var h_path_top = h_base_top + bridge.pathway_height * cell_height
	var h_rail_top = h_path_top + bridge.railing_height * cell_height

	var static_body: StaticBody3D = null
	if enable_bridge_colliders:
		static_body = StaticBody3D.new()

	# Middle parts (between-grids: two facade planes connected across the street)
	_add_bridge_section(c_a1, c_a2, c_b1, c_b2, t_start, t_end, h_base_bot, h_base_top,
			bridge_base_color, static_body)
	_add_bridge_section(c_a1, c_a2, c_b1, c_b2, t_start, t_end, h_base_top, h_path_top,
			bridge_pathway_color, static_body)

	if bridge.railing_height > 0:
		_add_bridge_section(c_a1, c_a2, c_b1, c_b2, t_start, t_start + t_one_cell,
				h_path_top, h_rail_top, bridge_railing_color, static_body)
		_add_bridge_section(c_a1, c_a2, c_b1, c_b2, t_end - t_one_cell, t_end,
				h_path_top, h_rail_top, bridge_railing_color, static_body)

	if bridge.arc_height > 0 and bridge.arc_length > 0:
		var h_arc_bot = h_base_bot - bridge.arc_height * cell_height
		_add_bridge_arcs(c_a1, c_a2, c_b1, c_b2, t_start, t_end,
				h_arc_bot, h_base_bot, bridge.arc_length * cell_height, static_body)

	# Extremes (in-grid: skewed cubes within the sidewalk 3D matrix)
	var by_base_top = floor_idx * cells_per_floor
	var by_arc_bot = by_base - bridge.arc_height
	var side_a = {
		"face": placed["face_a"], "edge_idx": placed["edge_idx_a"],
		"cells": placed["cells_a"], "reversed": placed["reversed_a"],
	}
	var side_b = {
		"face": placed["face_b"], "edge_idx": placed["edge_idx_b"],
		"cells": placed["cells_b"], "reversed": placed["reversed_b"],
	}
	for side in [side_a, side_b]:
		_draw_bridge_extremes(bridge, side, cell_start, cell_end,
				by_base, by_base_top, by_arc_bot, cell_height, static_body)

	if static_body:
		add_child(static_body)


func _add_bridge_section(c_a1: Vector2, c_a2: Vector2, c_b1: Vector2, c_b2: Vector2,
		t_start: float, t_end: float, h_bottom: float, h_top: float,
		color: Color, static_body: StaticBody3D) -> void:
	var plane_a = _bridge_plane(c_a1, c_a2, t_start, t_end, h_bottom, h_top)
	var plane_b = _bridge_plane(c_b1, c_b2, t_start, t_end, h_bottom, h_top)
	add_child(DebugUtil.create_skewed_cube_from_planes(plane_a, plane_b, color, 1.0))
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(plane_a, plane_b))


func _add_bridge_arcs(c_a1: Vector2, c_a2: Vector2, c_b1: Vector2, c_b2: Vector2,
		t_start: float, t_end: float, h_bottom: float, h_top: float,
		arc_world_depth: float, static_body: StaticBody3D) -> void:
	var plane_a = _bridge_plane(c_a1, c_a2, t_start, t_end, h_bottom, h_top)
	var plane_b = _bridge_plane(c_b1, c_b2, t_start, t_end, h_bottom, h_top)

	var bridge_depth = plane_a[0].distance_to(plane_b[0])
	var arc_frac = clampf(arc_world_depth / bridge_depth, 0.0, 0.45) if bridge_depth > 0.0 else 0.0

	var near_plane: Array[Vector3] = []
	for i in range(4):
		near_plane.append(plane_a[i].lerp(plane_b[i], arc_frac))
	add_child(DebugUtil.create_skewed_cube_from_planes(plane_a, near_plane, bridge_arc_color, 1.0))
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(plane_a, near_plane))

	var far_plane: Array[Vector3] = []
	for i in range(4):
		far_plane.append(plane_a[i].lerp(plane_b[i], 1.0 - arc_frac))
	add_child(DebugUtil.create_skewed_cube_from_planes(far_plane, plane_b, bridge_arc_color, 1.0))
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(far_plane, plane_b))


func _draw_bridge_extremes(bridge: Bridge, side: Dictionary, cell_start: int, cell_end: int,
		by_base: int, by_base_top: int, by_arc_bot: int,
		cell_height: float, static_body: StaticBody3D) -> void:
	var face_idx: int = side["face"]
	var edge_idx: int = side["edge_idx"]
	var facade_cells: Array = side["cells"]
	var is_reversed: bool = side["reversed"]

	var block: BlockGenerator = generator.get_block_grid(face_idx)
	if block == null:
		return

	var building_dim = FacadeHelper.get_building_dim(edge_idx, block)
	var dg_idx_start = cell_start / building_dim
	var dg_idx_end = cell_end / building_dim

	for ci in range(dg_idx_start, dg_idx_end + 1):
		if ci < 0 or ci >= facade_cells.size():
			continue
		var coord: Vector2i = facade_cells[ci]
		var module: BuildingModule = block.get_building_module(coord.x, coord.y, 0)
		if module == null:
			continue

		var core = module.get_core_info()

		var local_start = cell_start - ci * building_dim if ci == dg_idx_start else 0
		var local_end = cell_end - ci * building_dim if ci == dg_idx_end else building_dim - 1
		local_start = clampi(local_start, 0, building_dim - 1)
		local_end = clampi(local_end, 0, building_dim - 1)

		var grid_rect = FacadeHelper.facade_to_grid_rect(
				edge_idx, is_reversed, local_start, local_end, core, module, building_dim)
		if grid_rect.is_empty():
			continue

		var bx_min: int = grid_rect["bx_min"]
		var bx_max: int = grid_rect["bx_max"]
		var bz_min: int = grid_rect["bz_min"]
		var bz_max: int = grid_rect["bz_max"]

		# Base extreme
		var base_verts = module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, by_base)
		if base_verts.size() == 4:
			var base_h = (by_base_top - by_base) * cell_height
			add_child(DebugUtil.create_skewed_cube(base_verts, base_h, bridge_base_color))
			if static_body:
				var top_verts: Array = []
				for v in base_verts:
					top_verts.append(v + Vector3(0, base_h, 0))
				static_body.add_child(DebugUtil.create_collision_shape_from_planes(base_verts, top_verts))

		# Arc extreme
		if bridge.arc_height > 0:
			var arc_verts = module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, by_arc_bot)
			if arc_verts.size() == 4:
				var arc_h = (by_base - by_arc_bot) * cell_height
				add_child(DebugUtil.create_skewed_cube(arc_verts, arc_h, bridge_arc_color))
				if static_body:
					var top_verts: Array = []
					for v in arc_verts:
						top_verts.append(v + Vector3(0, arc_h, 0))
					static_body.add_child(DebugUtil.create_collision_shape_from_planes(arc_verts, top_verts))


static func _bridge_plane(c1: Vector2, c2: Vector2, t_start: float, t_end: float,
		h_bottom: float, h_top: float) -> Array[Vector3]:
	var p_s = c1.lerp(c2, t_start)
	var p_e = c1.lerp(c2, t_end)
	return [
		Vector3(p_s.x, h_bottom, p_s.y),
		Vector3(p_e.x, h_bottom, p_e.y),
		Vector3(p_e.x, h_top,    p_e.y),
		Vector3(p_s.x, h_top,    p_s.y),
	]
