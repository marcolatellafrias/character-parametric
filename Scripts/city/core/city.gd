# CityVisualizer.gd
extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
@export var region_size: Vector2 = Vector2(800, 800)
@export var min_distance: float = 180.5
@export var rejection_samples: int = 90
@export var generation_seed: int = 123456

@export_group("Barrios")
@export var num_neighborhoods: int = 10
@export var neighborhood_seed: int = -1
@export_range(0.1, 5.0) var neighborhood_height_falloff: float = 0.3

@export_group("Suavizado")
@export var smoothing_steps: int = 50

@export_group("Visualización General")
@export var show_streets: bool = false
@export var show_nodes: bool = false
@export var node_radius: float = 0.08
@export var normal_node_color: Color = Color.CHARTREUSE
@export var boundary_node_color: Color = Color.ORANGE_RED
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
@export var block_cells_per_floor: int = 4

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
@export var show_buildings: bool = true
@export var show_building_colliders: bool = true
@export var alternate_floor_shading: bool = true 
@export var alternate_module_shading: bool = true
@export_range(0.1, 0.9) var floor_shade_factor: float = 0.85

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

@export_group("Facade Grid Debug")
@export var show_facade_rects: bool = true
@export var facade_rect_seed: int = 42
@export var facade_grid_is_core: bool = true

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
        _update_all_traffic_planes()
    
    if show_traffic_planes:
        _update_traffic_planes_visualization()

func _update_all_traffic_planes() -> void:
    for key in generator.lane_volume_areas:
        var vol = generator.lane_volume_areas[key]
        var traffic_plane = vol.get_traffic_plane()
        
        if traffic_plane:
            traffic_plane.update_layer_for_active_index(active_traffic_index)

func _update_traffic_planes_visualization() -> void:
    for child in get_children():
        if child.has_meta("traffic_plane_visual"):
            var traffic_index = child.get_meta("traffic_index", -1)
            
            if traffic_index == -1:
                continue
            
            var mesh_instance = child as MeshInstance3D
            if mesh_instance and mesh_instance.material_override:
                var material = mesh_instance.material_override as StandardMaterial3D
                
                if material:
                    var color: Color
                    if traffic_index == active_traffic_index:
                        color = traffic_plane_green_color
                    else:
                        color = traffic_plane_red_color
                    
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

func clear_visualization() -> void:
    for child in get_children():
        child.queue_free()
    
    if generator:
        generator.lane_volume_areas.clear()

func visualize_graph() -> void:
    if generator == null or generator.plain_graph == null:
        push_error("No hay grafo generado para visualizar")
        return
    
    _add_lane_volume_areas_to_scene()
    
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
    
    if show_traffic_planes:
        _visualize_traffic_planes()
    
    if show_nodes:
        _visualize_nodes()
    
    if show_facade_rects:
        _visualize_facade_rects()

func _add_lane_volume_areas_to_scene() -> void:
    if generator == null:
        return
    
    var total_added = 0
    
    for key in generator.lane_volume_areas:
        var lane_volume = generator.lane_volume_areas[key]
        add_child(lane_volume)
        total_added += 1
    
    print("[Visualizer] Lane Volume Areas agregados a la escena: %d" % total_added)

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
        
        var max_floors = 0
        var clusters = block.get_all_clusters()
        for cluster in clusters:
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
        var building_cell_height = block.get_building_cell_height()
        var building_height = cells_per_floor * building_cell_height
        
        var clusters = block.get_all_clusters()
        total_clusters += clusters.size()
        
        for cluster in clusters:
            var cluster_floors = cluster.get_floor_count()
            var base_color = cluster.color
            
            if cluster_floors == 1 and cluster.get_cell_count() == 1:
                print("=== DEBUG EDIFICIO 1x1x1 ===")
                print("cells_per_floor: %d" % cells_per_floor)
                print("building_cell_height: %.3f" % building_cell_height)
                print("building_height (1 piso): %.3f" % building_height)
                
                var first_cell = cluster.cells[0]
                var x = first_cell.x
                var z = first_cell.y
                var building_module: BuildingModule = block.get_building_module(x, z, 0)
                if building_module:
                    var core_vertices = building_module.get_core_vertices(0)
                    if core_vertices.size() == 4:
                        var width = core_vertices[0].distance_to(core_vertices[1])
                        var depth = core_vertices[1].distance_to(core_vertices[2])
                        print("base_width: %.3f" % width)
                        print("base_depth: %.3f" % depth)
                        print("ratio height/width: %.3f" % (building_height / width))
                        print("ratio height/depth: %.3f" % (building_height / depth))
                    
                    var chamfers = building_module.get_chamfers()
                    if not chamfers.is_empty():
                        print("CHAMFERS detectados:")
                        for vertex_idx in chamfers:
                            print("  Vértice %d: %s" % [vertex_idx, chamfers[vertex_idx]])
                    
                    var core_info = building_module.get_core_info()
                    print("core_width: %d" % core_info["width"])
                    print("core_depth: %d" % core_info["depth"])
                print("========================")
            
            for floor in range(cluster_floors):
                var floor_base_y = floor * cells_per_floor * building_cell_height
                
                var floor_color: Color
                if alternate_floor_shading:
                    if floor % 2 == 0:
                        floor_color = base_color
                    else:
                        floor_color = base_color.darkened(1.0 - floor_shade_factor)
                else:
                    floor_color = base_color
                
                for cell in cluster.cells:
                    var x = cell.x
                    var z = cell.y
                    
                    var building_module: BuildingModule = block.get_building_module(x, z, floor)
                    
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
                    
                    var core_rows = core_info["depth"]
                    var core_columns = core_info["width"]
                    var chamfers = building_module.get_chamfers()
                    
                    var module_color = floor_color
                    if alternate_module_shading and (x + z) % 2 == 1:
                        module_color = floor_color.darkened(1.0 - floor_shade_factor)
                    
                    var cube = DebugUtil.create_skewed_cube_advanced_grid(
                        core_vertices,
                        building_height,
                        module_color,
                        chamfers,
                        core_rows,
                        core_columns,
                        false
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
        var building_cell_height = block.get_building_cell_height()
        var building_height = cells_per_floor * building_cell_height
        
        var clusters = block.get_all_clusters()
        
        for cluster in clusters:
            var static_body = StaticBody3D.new()
            var has_colliders = false
            
            var cluster_floors = cluster.get_floor_count()
            
            for floor in range(cluster_floors):
                var floor_base_y = floor * cells_per_floor * building_cell_height
                
                for cell in cluster.cells:
                    var x = cell.x
                    var z = cell.y
                    
                    var building_module: BuildingModule = block.get_building_module(x, z, floor)
                    
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
                    
                    var core_rows = core_info["depth"]
                    var core_columns = core_info["width"]
                    
                    var chamfers = building_module.get_chamfers()
                    
                    var collision_body = DebugUtil.create_skewed_cube_advanced_grid_collider(
                        core_vertices,
                        building_height,
                        chamfers,
                        core_rows,
                        core_columns
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
                
                var is_facade = (grid_x == 0 or grid_x == distorted.columns or 
                                   grid_z == 0 or grid_z == distorted.rows)
                
                var sphere: Node3D
                if is_facade:
                    sphere = DebugUtil.create_debug_sphere_print(
                        Vector2i(grid_x, grid_z),
                        distorted_grid_facade_vertex_color,
                        distorted_grid_vertex_radius
                    )
                else:
                    sphere = DebugUtil.create_debug_sphere(distorted_grid_normal_vertex_color, distorted_grid_vertex_radius)
                
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
                
                var is_facade_edge = (grid_z == 0 or grid_z == distorted.rows)
                
                if is_facade_edge:
                    edge_color = distorted_grid_facade_edge_color
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
                
                var is_facade_edge = (grid_x == 0 or grid_x == distorted.columns)
                
                if is_facade_edge:
                    edge_color = distorted_grid_facade_edge_color
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
    return generator.get_max_building_height_global()

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
# VISUALIZACIÓN DE TRAFFIC PLANES
# ============================================
func _visualize_traffic_planes() -> void:
    var total_planes = 0
    var index_0_count = 0
    var index_1_count = 0
    var unassigned_count = 0
    
    for key in generator.lane_volume_areas:
        var vol = generator.lane_volume_areas[key]
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
        
        var mesh_instance: MeshInstance3D = MeshInstance3D.new()
        
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        
        var vertices: PackedVector3Array = PackedVector3Array([
            end_verts[0], end_verts[1], end_verts[2], end_verts[3]
        ])
        
        var indices: PackedInt32Array = PackedInt32Array([
            0, 1, 2,
            0, 2, 3
        ])
        
        var edge1: Vector3 = end_verts[1] - end_verts[0]
        var edge2: Vector3 = end_verts[2] - end_verts[0]
        var normal: Vector3 = edge1.cross(edge2).normalized()
        
        var normals: PackedVector3Array = PackedVector3Array([
            normal, normal, normal, normal
        ])
        
        arrays[Mesh.ARRAY_VERTEX] = vertices
        arrays[Mesh.ARRAY_NORMAL] = normals
        arrays[Mesh.ARRAY_INDEX] = indices
        
        var array_mesh: ArrayMesh = ArrayMesh.new()
        array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        
        mesh_instance.mesh = array_mesh
        
        var material: StandardMaterial3D = StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        
        var color: Color
        if traffic_index == active_traffic_index:
            color = traffic_plane_green_color
        else:
            color = traffic_plane_red_color
        
        color.a = traffic_plane_transparency
        material.albedo_color = color
        
        mesh_instance.material_override = material
        
        mesh_instance.set_meta("traffic_plane_visual", true)
        mesh_instance.set_meta("traffic_index", traffic_index)
        
        add_child(mesh_instance)
        total_planes += 1
    
    print("[Visualizer] Traffic planes: %d planos (índice 0: %d, índice 1: %d, sin asignar: %d)" % [total_planes, index_0_count, index_1_count, unassigned_count])

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
    if generator == null:
        push_error("CityVisualizer: generator no inicializado")
        return null
    
    return generator.get_lane_volume_area(face_idx, edge_idx)

func get_lane_volume_area_continuations(face_idx: int, edge_idx: int) -> Array[LaneVolume]:
    if generator == null:
        push_error("CityVisualizer: generator no inicializado")
        return []
    
    return generator.get_lane_volume_continuations(face_idx, edge_idx)

# ============================================
# VISUALIZACIÓN DE FACADE RECTS
# ============================================
func _visualize_facade_rects() -> void:
    if not show_facade_rects:
        return
    var all_block_faces = generator.get_all_block_faces()
    var rng = RandomNumberGenerator.new()
    rng.seed = facade_rect_seed
    var total_grids = 0
    for face_idx in all_block_faces:
        var block: BlockGenerator = generator.get_block_grid(face_idx)
        if block == null:
            continue
        var helper = BridgeGridHelper.new(block)
        var grids = helper.get_all_edges_random_facade_grids(rng, facade_grid_is_core)
        for vgrid in grids:
            if vgrid.is_empty():
                continue
            _debug_visualize_facade_grid(vgrid)
            total_grids += 1
    print("[Visualizer] Facade grids visualizados: %d" % total_grids)

func _debug_visualize_facade_grid(vgrid: Dictionary) -> void:
    var unavailable_points: Dictionary = vgrid.get("unavailable_points", {})
    var nodes: Dictionary = {}
    for quad in vgrid["quads"]:
        var nx = quad["local_x"]
        var ny = quad["local_y"]
        for corner in [
            [nx,   ny,   quad["v1"]],
            [nx+1, ny,   quad["v2"]],
            [nx+1, ny+1, quad["v3"]],
            [nx,   ny+1, quad["v4"]]
        ]:
            var nkey = "%d_%d" % [corner[0], corner[1]]
            if nkey not in nodes:
                nodes[nkey] = {
                    "pos":   corner[2],
                    "coord": Vector2i(corner[0], corner[1])
                }
    for nkey in nodes:
        var nd = nodes[nkey]
        var available = not (nkey in unavailable_points)
        var color = Color.YELLOW if available else Color.RED
        var sphere = DebugUtil.create_debug_sphere_print(nd["coord"], color, distorted_grid_vertex_radius, true)
        sphere.position = nd["pos"]
        add_child(sphere)

func _debug_visualize_bridge_core_grid(helper: BridgeGridHelper, facade_edge_info: Dictionary, floor: int) -> void:
    var vgrid = helper.get_facade_grid_for_floor(facade_edge_info, floor, true)
    _debug_visualize_facade_grid(vgrid)
