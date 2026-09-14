# CityVisualizer.gd
extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
## Lado de la región donde se siembran los nodos. El doble de área es el doble de manzanas.
@export var region_size: Vector2 = Vector2(1425.6, 1425.6)
@export var min_distance: float = 180.5*1.3*1.4
@export var rejection_samples: int = 90
@export var generation_seed: int = 123456
## When true, the city derives its seeds from the weekly world seed (WorldSeeds). Untick to force the inspector values (debug).
@export var use_world_seed: bool = true

@export_group("Barrios")
@export var num_neighborhoods: int = 6
@export var neighborhood_seed: int = -1
## En cuántos parches se reparten las ALTURAS, aparte de los distritos (ver NeighborhoodTypes): más
## parches, zonas más chicas y cambios de pace más seguidos. Conviene que crezca con la ciudad.
@export var num_height_patches: int = 18

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

@export_group("Muralla")
## El límite del mundo: un muro que no se puede pasar ni con el propulsor vertical. Su base sigue el
## terreno y su CIMA queda a altura constante, en tantos pisos de edificio (ver `_visualize_walls`).
@export var show_wall: bool = true
## Si se DIBUJA la muralla. Esta aparte de `show_wall` a proposito: aquel apaga la muralla entera,
## COLISION INCLUIDA, y entonces la nave se escapa del mapa. Este la deja donde esta y solo la esconde.
@export var show_wall_mesh: bool = false
## 13 pisos (~85 m): la nave llega a 10 con el propulsor, así que queda fuera de alcance por 3 pisos
## sin encerrar como una caja — y los edificios altos (15 a 22) la superan siempre.
@export var wall_floors: float = 13.0
@export var wall_thickness: float = 3.0
@export var enable_wall_collider: bool = true
@export var wall_color: Color = Color(0.55, 0.55, 0.58)

@export_group("Terreno")
## Alto de la loma más alta, en PISOS de edificio: es lo que se lee en el juego —cuántos pisos se come el
## relieve—. En 0 la ciudad queda plana, como antes.
@export var terrain_floors: float = 2.0
## Cada cuántos metros cambia el relieve. Más chico, lomas más apretadas.
@export var terrain_feature_size: float = 300.0
## Pendiente máxima de una calle. Si el ruido se pasa, se baja la amplitud de todo el campo (ver
## CityTerrain): 12% es una calle empinada pero caminable.
@export_range(0.01, 0.5) var terrain_max_slope: float = 0.12
@export var show_ground: bool = true
@export var enable_ground_collider: bool = true
@export var ground_color: Color = Color(0.33, 0.31, 0.27)

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
@export var traffic_plane_yellow_color: Color = Color.YELLOW
@export var traffic_plane_red_color: Color = Color.RED

@export_group("Traffic Lights")
@export var enable_traffic_lights: bool = true
@export var traffic_light_cycle_duration: float = 5.0
@export var traffic_light_yellow_duration: float = 2.0

@export var show_sidewalk_matrices: bool = false

@export_group("Delivery Doors")
@export var show_delivery_doors: bool = false
@export var delivery_door_color: Color = Color(0.9, 0.9, 0.85)

@export_group("Objetos de techo")
@export var show_roof_props: bool = true
## Cada cuánto un CLUSTER de techo plano se lleva un tanque de agua. Bajo a propósito: repetido
## demasiado, el tanque deja de leerse como detalle y se vuelve textura.
@export_range(0.0, 1.0) var water_tank_chance: float = 0.12
## Hasta qué altura sobre la azotea llega su matriz rígida (ver RigidMatrix): lo que se apoye ahí no puede
## ser más alto que esto.
const ROOF_SURFACE_DEPTH_M := 10.0

@export_group("Traversal Zones")
@export var show_stair_zones: bool = false
@export var stair_zone_color: Color = Color(1.0, 0.6, 0.1)
@export var sidewalk_color: Color = Color(0.5, 0.48, 0.46)

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
var yellow_phase_active: bool = false
var _building_material: StandardMaterial3D = null
## Semilla del relieve; sale de la del mundo salvo que se fuerce a mano (ver use_world_seed).
var terrain_seed: int = 0

## QUIÉN ES CADA TRIÁNGULO (ver CityIndex). Se llena mientras se hornea la geometría, que es el único
## momento en que la identidad de una pieza existe; después, fusionada en la malla, ya no se puede deducir
## sin reimplementar un resolvedor por cada sistema.
var city_index := CityIndex.new()
## El scope y la malla de cada cluster, para que el collider —que se construye en OTRA pasada— pueda
## estamparse con los mismos. `_visualize_buildings` los llena y `_visualize_building_colliders` los lee;
## el orden entre las dos está fijado en `generate_and_visualize`.
var _scope_by_cluster: Dictionary = {}
## El id de OBJETO de cada cluster. Las paredes y el techo de un edificio lo comparten, y por eso se puede
## resaltar el edificio entero aunque sus dos mitades vivan en mallas distintas.
##
## ⚠ NO sirve `cluster.id` para esto: se numera por manzana y arranca de cero en cada una, así que el
## cluster 5 existe en las 191 manzanas. Hace falta un id global, y es este.
var _object_by_cluster: Dictionary = {}
var _next_object: int = 0


func get_city_index() -> CityIndex:
	return city_index


func _object_for_cluster(cluster: BuildingCluster) -> int:
	if not _object_by_cluster.has(cluster):
		_next_object += 1
		_object_by_cluster[cluster] = _next_object
	return _object_by_cluster[cluster]


func _new_object() -> int:
	_next_object += 1
	return _next_object

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

	# The whole phase is a PURE FUNCTION of accumulated time — never a mutation
	# that can wedge. (The previous flip-on-threshold version froze one index
	# deterministically ~t60 every run and no static inspection revealed why;
	# deriving from the clock removes the entire failure mode. Combined with the
	# computed is_blocking property, a stuck light is now impossible short of
	# _process itself not running.) Each direction holds the road for
	# `cycle_duration`, the last `yellow_duration` of it being yellow (both
	# directions block), so the full period is 2 × cycle_duration.
	traffic_light_timer += delta
	var phase := int(traffic_light_timer / traffic_light_cycle_duration)
	active_traffic_index = phase % 2
	var into_phase := traffic_light_timer - phase * traffic_light_cycle_duration
	yellow_phase_active = into_phase >= (traffic_light_cycle_duration - traffic_light_yellow_duration)

	# Every plane DERIVES is_blocking from these two globals on read — no per-plane
	# push loop, no per-plane state to go stale.
	TrafficPlane.global_active_index = active_traffic_index
	TrafficPlane.global_yellow_phase = yellow_phase_active

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

		var color: Color
		if traffic_index != active_traffic_index:
			color = traffic_plane_red_color
		elif yellow_phase_active:
			color = traffic_plane_yellow_color
		else:
			color = traffic_plane_green_color
		color.a = traffic_plane_transparency
		material.albedo_color = color

# ============================================
# GENERACIÓN Y VISUALIZACIÓN
# ============================================
func generate_and_visualize() -> void:
	clear_visualization()
	generate_graph()
	visualize_graph()

	# Estado inicial de los semáforos (index 0 activo, sin amarillo); _process lo
	# recalcula desde el reloj cada frame.
	traffic_light_timer = 0.0
	active_traffic_index = 0
	yellow_phase_active = false
	TrafficPlane.global_active_index = 0
	TrafficPlane.global_yellow_phase = false

func generate_graph() -> void:
	if use_world_seed:
		generation_seed   = WorldSeeds.weekly_seed()
		neighborhood_seed = WorldSeeds.derive(generation_seed, 1)
		grid_seed         = WorldSeeds.derive(generation_seed, 2)
		terrain_seed      = WorldSeeds.derive(generation_seed, 3)

	generator = GraphCityGenerator.new()
	generator.enable_traffic_lights = enable_traffic_lights

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
		num_height_patches,
		num_neighborhoods,
		neighborhood_seed,
		terrain_floors,
		terrain_feature_size,
		terrain_max_slope,
		terrain_seed
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

	if show_ground:
		_visualize_ground()

	if show_wall:
		_visualize_walls()

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

	if show_bridges:
		_visualize_bridges()

	if show_delivery_doors:
		_visualize_delivery_doors()

	if show_roof_props:
		_visualize_roof_props()

	if show_stair_zones:
		_visualize_stair_zones()

	_visualize_floating_sidewalk_zones()

	print("[Visualizer] Índice de piezas: %d identificables" % city_index.size())

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
func _get_building_material() -> StandardMaterial3D:
	if _building_material == null:
		_building_material = StandardMaterial3D.new()
		_building_material.vertex_color_use_as_albedo = true
		_building_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_building_material.cull_mode = BaseMaterial3D.CULL_BACK
		_building_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return _building_material

# Deja de dibujarse EXACTAMENTE donde la niebla ya es total (`render_distance`), y SIN fundido propio.
#
# ⚠ NO agregar aquí el fundido de Godot (`VISIBILITY_RANGE_FADE_SELF`). Se probó y pelea con la niebla de
# dos maneras, las dos visibles en juego:
#   · La niebla es un shader de PANTALLA COMPLETA que lee el buffer de profundidad. Una pieza a medio
#     desvanecer se dibuja con transparencia/dithering y no queda bien escrita ahí, así que la niebla no
#     la pinta: aparece nítida a lo lejos y, al terminar de aparecer, la niebla le cae de golpe.
#   · El fundido es POR MALLA y con dithering: se ve a través del objeto. Con balcones, puertas y demás
#     como mallas propias, se verían los interiores.
#
# Cortando donde la niebla ya tapa todo, la pieza desaparece cuando ya era 100% color niebla: el corte es
# invisible y no hace falta ningún fundido. LA NIEBLA ES EL FUNDIDO. Si alguna vez hace falta LOD real,
# la herramienta es `visibility_parent` (jerárquico), que agrupa: el fundido de acá es de entrada, no LOD.
# LA PIEZA ENTRA FUNDIÉNDOSE, no apareciendo. Durante mucho tiempo esto fue al revés —corte seco, sin
# fundido— porque la niebla era un shader de PANTALLA COMPLETA que leía el depth buffer: una malla a medio
# fundir se dibuja con dithering, no queda bien escrita en ese buffer, y la niebla se la salteaba; se veía
# nítida y sin niebla a lo lejos y recién al opacarse le caía la niebla encima de golpe. Con la niebla
# NATIVA de Godot eso desapareció: se aplica por fragmento dentro del shader del material, así que una
# malla fundiéndose viene enneblada durante todo el fundido. El fundido volvió a ser posible el día que
# cambiamos de sistema de niebla, no antes.
#
# Y volvió a ser NECESARIO el día que la niebla dejó de ser del color del cielo. Mientras lo era, una pieza
# saturada era indistinguible del fondo y el corte no se veía; ahora la niebla es cálida contra un cielo
# azul, o sea que una pieza lejana ES una silueta naranja. Sin fundido, esa silueta se materializa de una.
#
# El umbral incluye EL RADIO DE LA PIEZA: Godot compara la distancia al ORIGEN del nodo —su centro—,
# mientras que la niebla se calcula por píxel. Sin sumar el radio, un edificio cuyo centro está en el
# umbral tiene su cara cercana decenas de metros más acá, con bastante menos niebla encima.
func _fade_into_fog(piece: GeometryInstance3D) -> void:
	var mesh_piece := piece as MeshInstance3D
	_center_on_own_geometry(mesh_piece)
	var radius := 0.0
	if mesh_piece != null and mesh_piece.mesh != null:
		radius = mesh_piece.mesh.get_aabb().size.length() * 0.5
	var end_distance := WorldSettings.render_distance + radius
	piece.visibility_range_end = end_distance
	piece.visibility_range_end_margin = WorldSettings.fade_ring_for(end_distance)
	piece.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

# ⚠ LA DISTANCIA DE VISIBILIDAD SE MIDE DESDE EL ORIGEN DEL NODO, no desde su geometría.
#
# Casi todas las mallas de la ciudad se arman con vértices en COORDENADAS DE MUNDO y se cuelgan sin
# transform, así que su origen queda en (0,0,0) —la esquina de la ciudad— con la geometría a cientos de
# metros. Con eso, Godot evalúa siempre la distancia `cámara → esquina de la ciudad`, IGUAL PARA TODAS:
# alejándose de esa esquina se desvanecen todos los edificios a la vez, incluso los que se tienen
# enfrente. El síntoma engaña, porque parece un problema de la niebla y no del culling.
#
# Por eso, antes de darle rango de visibilidad a una malla, se la CENTRA en su propia caja: los vértices
# pasan a ser relativos a su centro y el nodo se mueve ahí. La geometría queda en el mismo lugar del
# mundo, pero ahora la distancia que Godot mide es la que uno espera. (Los occluders ya hacían esto: ver
# `_add_box_occluder`.)
func _center_on_own_geometry(piece: MeshInstance3D) -> void:
	if piece == null:
		return
	var mesh := piece.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() != 1:
		return
	var center := mesh.get_aabb().get_center()
	if center.is_zero_approx():
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for i in verts.size():
		verts[i] -= center
	arrays[Mesh.ARRAY_VERTEX] = verts
	var centered := ArrayMesh.new()
	centered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	piece.mesh = centered
	piece.position += center

# ============================================
# MURALLA
# ============================================
# El límite del mundo. Se levanta sobre las aristas de BORDE del grafo —las que tienen una sola manzana de
# un lado, que ya son tipo de calle -1 y no llevan vereda ni calzada—, así que no hace falta inventarle un
# recorrido: el borde de la ciudad ya estaba ahí.
#
# Su base sigue el terreno y su CIMA queda a ALTURA CONSTANTE. Es a propósito: si la cima acompañara las
# lomas, en los valles bajaría y dejaría de ser infranqueable justo donde el relieve ya hunde al jugador.
#
# En cada nodo del borde va además una columna que tapa la junta entre dos tramos: sin ella, las esquinas
# abiertas dejarían una cuña de aire.
func _visualize_walls() -> void:
	var graph := generator.plain_graph
	var top := wall_floors * _floor_height()
	var container := Node3D.new()
	container.name = "Wall"
	container.add_to_group("city_wall")
	add_child(container)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var corners := {}
	var segments := 0
	for edge: Array in graph.edges:
		var node1: int = edge[0]
		var node2: int = edge[1]
		var key := GraphGenerator._get_edge_key(node1, node2)
		if generator.street_types.get(key, 1) != BlockGenerator.StreetType.BOUNDARY:
			continue
		var sides: Array = graph.edge_to_faces.get(key, [])
		if sides.is_empty():
			continue
		var a: Vector3 = _wall_base(node1)
		var b: Vector3 = _wall_base(node2)
		var outward := _wall_outward(a, b, sides[0])
		var shift := outward * wall_thickness
		# Las dos caras y la tapa. La de adentro mira a la ciudad; la de afuera, al vacío.
		_wall_quad(st, faces, a, b, Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), -outward)
		_wall_quad(st, faces, a + shift, b + shift, Vector3(b.x, top, b.z) + shift, Vector3(a.x, top, a.z) + shift, outward)
		_wall_quad(st, faces, Vector3(a.x, top, a.z), Vector3(b.x, top, b.z),
			Vector3(b.x, top, b.z) + shift, Vector3(a.x, top, a.z) + shift, Vector3.UP)
		corners[node1] = a
		corners[node2] = b
		segments += 1

	for node_idx: int in corners:
		_wall_post(st, faces, corners[node_idx], top)
	st.generate_normals()

	var material := StandardMaterial3D.new()
	material.albedo_color = wall_color
	material.roughness = 1.0
	var view := MeshInstance3D.new()
	view.name = "mesh"
	view.mesh = st.commit()
	view.material_override = material
	# SIN límite por distancia, a diferencia de los edificios: la muralla es UNA SOLA malla que abarca la
	# ciudad entera, así que su origen cae en el centro y "distancia a la muralla" no significa nada —
	# con un corte a 294 m solo se dibujaba estando cerca del centro, o sea casi nunca. Lo que evita que su
	# silueta achique la ciudad es la niebla, que la desdibuja a la distancia (ver CityFog).
	view.visible = show_wall_mesh
	container.add_child(view)

	if enable_wall_collider:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		var body := StaticBody3D.new()
		body.name = "collider"
		body.add_child(collider)
		container.add_child(body)
	print("[Visualizer] Muralla: %d tramos · cima a %.0f m (%.0f pisos)" % [segments, top, wall_floors])

# El pie de la muralla en un nodo del borde: sobre el terreno.
func _wall_base(node_idx: int) -> Vector3:
	var point: Vector3 = generator.plain_graph.points[node_idx]
	var height := generator.terrain.height_of(node_idx) if generator.terrain != null else 0.0
	return Vector3(point.x, height, point.z)

# Hacia dónde da la cara de afuera: perpendicular al tramo, del lado contrario a su manzana.
func _wall_outward(a: Vector3, b: Vector3, face_idx: int) -> Vector3:
	var along := (b - a)
	var side := Vector3(-along.z, 0.0, along.x).normalized()
	var face: Array = generator.plain_graph.faces[face_idx]
	var middle := Vector3.ZERO
	for node_idx: int in face:
		middle += generator.plain_graph.points[node_idx]
	middle /= float(face.size())
	if side.dot(middle - a) > 0.0:
		side = -side
	return side

# La columna que tapa la junta entre dos tramos, cuadrada y centrada en el nodo.
func _wall_post(st: SurfaceTool, faces: PackedVector3Array, at: Vector3, top: float) -> void:
	var half := wall_thickness
	var square := [
		Vector3(at.x - half, at.y, at.z - half), Vector3(at.x + half, at.y, at.z - half),
		Vector3(at.x + half, at.y, at.z + half), Vector3(at.x - half, at.y, at.z + half)]
	for k in 4:
		var low_a: Vector3 = square[k]
		var low_b: Vector3 = square[(k + 1) % 4]
		var outward := (((low_a + low_b) * 0.5) - at)
		outward.y = 0.0
		_wall_quad(st, faces, low_a, low_b, Vector3(low_b.x, top, low_b.z), Vector3(low_a.x, top, low_a.z),
			outward.normalized())
	_wall_quad(st, faces, Vector3(square[0].x, top, square[0].z), Vector3(square[1].x, top, square[1].z),
		Vector3(square[2].x, top, square[2].z), Vector3(square[3].x, top, square[3].z), Vector3.UP)

# Un cuadrilátero de muro mirando hacia `outward`. Godot toma como frente el giro horario, cuya normal es
# (c − a) × (b − a): si el orden viene al revés, se lo da vuelta.
func _wall_quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		outward: Vector3) -> void:
	for tri: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		var ordered := [p0, p1, p2] if (p2 - p0).cross(p1 - p0).dot(outward) >= 0.0 else [p0, p2, p1]
		for corner: Vector3 in ordered:
			st.add_vertex(corner)
		faces.append_array(ordered)

# Cuánto mide un piso de edificio: lo mismo que usa el generador para apilarlos.
func _floor_height() -> float:
	for face_idx: int in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block != null:
			return block.get_building_cell_height() * float(block.get_cells_per_floor())
	return 1.0

# ============================================
# SUELO
# ============================================
# El suelo se arma con LOS MISMOS QUADS que usa la ciudad, no con una malla aparte: las celdas de la
# DistortedGrid adentro de cada manzana, y el corredor entre dos manzanas para cada calle. Por eso el suelo
# y lo que se apoya en él —veredas, edificios— son la misma superficie y nada puede clipear (ver
# CityTerrain).
#
# El corredor de calle toma sus cuatro esquinas de `temporal_lane_points` —las esquinas enfrentadas de las
# dos manzanas— y la altura de cada una es la de SU nodo del grafo: las dos de un extremo valen lo mismo,
# así que la calle queda nivelada a lo ancho e inclinada a lo largo.
#
# Lo between-grids —los puentes en el aire y los volúmenes de carril— sigue sobre el cero
# (ver city-generation.md).
func _visualize_ground() -> void:
	var terrain := generator.terrain
	if terrain == null or terrain.amplitude <= 0.0:
		return
	var container := Node3D.new()
	container.name = "Ground"
	container.add_to_group("city_ground")
	add_child(container)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var blocks := 0
	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		var grid := block.get_distorted_grid() if block != null else null
		if grid == null:
			continue
		blocks += 1
		for x in grid.columns:
			for z in grid.rows:
				var cell := grid.get_cell_vertices(x, z)
				if cell.size() == 4:
					_ground_quad(st, faces, cell[0], cell[1], cell[2], cell[3])
	var streets := _ground_streets(st, faces)
	st.generate_normals()

	var material := StandardMaterial3D.new()
	material.albedo_color = ground_color
	material.roughness = 1.0
	var view := MeshInstance3D.new()
	view.name = "mesh"
	view.mesh = st.commit()
	view.material_override = material
	container.add_child(view)

	if enable_ground_collider:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		var body := StaticBody3D.new()
		body.name = "collider"
		body.add_child(collider)
		container.add_child(body)
	print("[Visualizer] Suelo: %d triángulos · %d manzanas · %d calles" % [faces.size() / 3, blocks, streets])

# El corredor de cada calle, una vez por arista. Devuelve cuántas se dibujaron.
func _ground_streets(st: SurfaceTool, faces: PackedVector3Array) -> int:
	var graph := generator.plain_graph
	var terrain := generator.terrain
	var drawn := 0
	for edge: Array in graph.edges:
		var node1: int = edge[0]
		var node2: int = edge[1]
		var sides: Array = graph.edge_to_faces.get(GraphGenerator._get_edge_key(node1, node2), [])
		if sides.size() != 2:
			continue  # el borde de la ciudad no tiene calle de este lado
		var block: BlockGenerator = generator.get_block_grid(sides[0])
		if block == null:
			continue
		var edge_idx := _edge_index_in_face(graph.faces[sides[0]], node1, node2)
		if edge_idx < 0:
			continue
		var first: Dictionary = block.temporal_lane_points.get("%d_%d" % [edge_idx, 0], {})
		var second: Dictionary = block.temporal_lane_points.get("%d_%d" % [edge_idx, 1], {})
		if first.is_empty() or second.is_empty():
			continue
		# Las dos esquinas de un extremo llevan la altura de su nodo: a lo ancho, nivelado.
		var at_first := terrain.height_of(graph.faces[sides[0]][edge_idx])
		var at_second := terrain.height_of(graph.faces[sides[0]][(edge_idx + 1) % graph.faces[sides[0]].size()])
		_ground_quad(st, faces,
			_flat_to_3d(first["point_a"], at_first), _flat_to_3d(first["point_b"], at_first),
			_flat_to_3d(second["point_b"], at_second), _flat_to_3d(second["point_a"], at_second))
		drawn += 1
	return drawn

# En qué lado de la cara está esa arista, o -1 si no está.
func _edge_index_in_face(face: Array, node1: int, node2: int) -> int:
	for i in face.size():
		var a: int = face[i]
		var b: int = face[(i + 1) % face.size()]
		if (a == node1 and b == node2) or (a == node2 and b == node1):
			return i
	return -1

func _flat_to_3d(flat: Vector2, height: float) -> Vector3:
	return Vector3(flat.x, height, flat.y)

# Un quad del suelo, en dos triángulos que miran para arriba. Godot toma como FRENTE el lado desde el que
# las esquinas giran en sentido horario, y la normal de ese lado es (c − a) × (b − a): con el orden al
# revés el suelo se culea desde arriba y desde abajo se ve negro.
func _ground_quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_ground_triangle(st, faces, a, b, c)
	_ground_triangle(st, faces, a, c, d)

func _ground_triangle(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var ordered := [a, b, c] if (c - a).cross(b - a).y >= 0.0 else [a, c, b]
	for corner: Vector3 in ordered:
		st.add_vertex(corner)
	faces.append_array(ordered)

# Los edificios —los meshes con sus occluders, y aparte los colliders— cuelgan de un nodo propio anotado
# en "city_buildings", así se prenden y apagan todos juntos (lo usa el panel de performance del F1).
func _buildings_container(node_name: String) -> Node3D:
	var container := Node3D.new()
	container.name = node_name
	container.add_to_group("city_buildings")
	add_child(container)
	return container

func _visualize_buildings() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_clusters = 0
	var total_cells = 0
	var mat := _get_building_material()
	var buildings := _buildings_container("Buildings")

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or block.get_distorted_grid() == null:
			continue

		var cells_per_floor := block.get_cells_per_floor()
		var clusters := block.get_all_clusters()
		total_clusters += clusters.size()

		for cluster in clusters:
			var cluster_floors := cluster.get_floor_count()
			var base_color: Color = cluster.color

			# Un scope por edificio: el rayo que pegue en su collider solo va a buscar entre SUS piezas.
			var scope := city_index.new_scope()
			_scope_by_cluster[cluster] = scope
			var object_id := _object_for_cluster(cluster)

			var merged_verts  := PackedVector3Array()
			var merged_norms  := PackedVector3Array()
			var merged_colors := PackedColorArray()
			var merged_idxs   := PackedInt32Array()

			for floor_idx in range(cluster_floors):
				var floor_base_index := floor_idx * cells_per_floor
				var floor_color: Color
				if alternate_floor_shading:
					floor_color = base_color if floor_idx % 2 == 0 else base_color.darkened(1.0 - floor_shade_factor)
				else:
					floor_color = base_color

				for cell in cluster.cells:
					var building_module: BuildingModule = block.get_building_module(cell.x, cell.y, floor_idx)
					if building_module == null:
						continue

					# LAS DOS CARAS DEL PISO SE PIDEN A LA GRILLA, ninguna se deduce sumando metros. Así
					# la malla no puede quedar desfasada de lo que se apoya sobre ella: si la altura vuelve
					# a depender del índice, el piso se deforma solo y las dos cosas siguen coincidiendo.
					var floor_bottom := building_module.get_core_vertices(floor_base_index)
					var floor_top := building_module.get_core_vertices(floor_base_index + cells_per_floor)
					if floor_bottom.size() != 4 or floor_top.size() != 4:
						continue

					var core_info := building_module.get_core_info()
					if core_info["width"] <= 0 or core_info["depth"] <= 0:
						continue

					var module_color := floor_color
					if alternate_module_shading and (cell.x + cell.y) % 2 == 1:
						module_color = floor_color.darkened(1.0 - floor_shade_factor)

					var geo := DebugUtil.get_skewed_cube_advanced_grid_geometry_from_planes(
						floor_bottom,
						floor_top,
						module_color,
						building_module.get_chamfers(),
						core_info["depth"],
						core_info["width"]
					)
					if geo.is_empty():
						continue

					var offset := merged_verts.size()
					var idx_from := merged_idxs.size()
					merged_verts.append_array(geo.vertices)
					merged_norms.append_array(geo.normals)
					merged_colors.append_array(geo.colors)
					for idx in geo.indices:
						merged_idxs.append(idx + offset)
					# LA IDENTIDAD SE ANOTA ACÁ, al lado de la línea que ya calcula el offset del merge: es
					# el último momento en que se sabe de quién son estos triángulos.
					city_index.add(scope, object_id, CityIndex.Kind.BUILDING, cluster.id, cell.x, cell.y,
						floor_idx, idx_from, merged_idxs.size(), geo.vertices)
					total_cells += 1

			if merged_verts.is_empty():
				continue

			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = merged_verts
			arrays[Mesh.ARRAY_NORMAL] = merged_norms
			arrays[Mesh.ARRAY_COLOR]  = merged_colors
			arrays[Mesh.ARRAY_INDEX]  = merged_idxs

			var array_mesh := ArrayMesh.new()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = array_mesh
			mesh_instance.material_override = mat
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			city_index.set_scope_mesh(scope, mesh_instance)
			# El occluder va PRIMERO: lee el AABB de la malla, y `_fade_into_fog` la recentra en su propio
			# centro. Al reves, todos los occluders terminaban apilados en el origen de la ciudad.
			_add_box_occluder(array_mesh, buildings)
			_fade_into_fog(mesh_instance)
			buildings.add_child(mesh_instance)

	print("[Visualizer] Buildings: %d clusters (%d cells total) en %d bloques" % [total_clusters, total_cells, all_block_faces.size()])

# ============================================
# VISUALIZACIÓN DE COLLIDERS DE BUILDINGS
# ============================================
# UN SOLO COLLIDER POR EDIFICIO. Antes iba una forma por celda Y por piso —145.000 formas en la ciudad,
# que Jolt carga en su broadphase estés donde estés—, y encima cada una nacía instanciando un cuerpo
# entero para robarle sus hijos y tirarlo.
#
# La MODULARIDAD NO SE PIERDE: vive en los datos (`BuildingModule` por celda y piso, la matriz 3D de
# veredas), que es donde la van a consultar los objetos colocables del futuro. Esto es solo el paso final
# de salida, y se puede volver a partir en piezas cambiando únicamente esta función.
func _visualize_building_colliders() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total_colliders = 0
	var total_blocks = 0
	var colliders := _buildings_container("BuildingColliders")

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or block.get_distorted_grid() == null:
			continue

		var cells_per_floor = block.get_cells_per_floor()
		var clusters = block.get_all_clusters()

		for cluster in clusters:
			var faces := PackedVector3Array()

			for floor_idx in range(cluster.get_floor_count()):
				var floor_base_index = floor_idx * cells_per_floor

				for cell in cluster.cells:
					var building_module: BuildingModule = block.get_building_module(cell.x, cell.y, floor_idx)
					if building_module == null:
						continue

					var floor_bottom = building_module.get_core_vertices(floor_base_index)
					var floor_top = building_module.get_core_vertices(floor_base_index + cells_per_floor)
					if floor_bottom.size() != 4 or floor_top.size() != 4:
						continue

					var core_info = building_module.get_core_info()
					if core_info["width"] <= 0 or core_info["depth"] <= 0:
						continue

					# La MISMA geometría que dibuja el edificio, así no se recalcula nada.
					var geo := DebugUtil.get_skewed_cube_advanced_grid_geometry_from_planes(
						floor_bottom,
						floor_top,
						Color.WHITE,
						building_module.get_chamfers(),
						core_info["depth"],
						core_info["width"]
					)
					if geo.is_empty():
						continue
					var verts: PackedVector3Array = geo.vertices
					for idx: int in geo.indices:
						faces.append(verts[idx])

			if faces.is_empty():
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var collision_shape := CollisionShape3D.new()
			collision_shape.shape = shape
			var static_body := StaticBody3D.new()
			static_body.add_child(collision_shape)
			# EL CUERPO QUE FRENA EL RAYO ES EL QUE DICE QUIÉN ES: lleva el scope de su edificio, y con eso
			# el índice resuelve tanto la pieza como la malla de la que copiarla (ver CityInspector).
			if _scope_by_cluster.has(cluster):
				static_body.set_meta(CityIndex.SCOPE_META, _scope_by_cluster[cluster])
			colliders.add_child(static_body)
			total_colliders += 1

		if clusters.size() > 0:
			total_blocks += 1

	print("[Visualizer] Colliders: %d edificios en %d manzanas (uno por edificio)" % [total_colliders, total_blocks])

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
# OBJETOS DE TECHO
# ============================================

## Tanques de agua y techos inclinados sobre los edificios (ver RoofProps).
##
## El quad del techo se le PIDE a la grilla en la altura del último piso, igual que hace la malla en
## `_visualize_buildings`. Nadie suma alturas a mano: si el relieve vuelve a depender del índice, el techo
## se acomoda solo (ver EL RELIEVE en BuildingModule).
##
## Todo el bloque se fusiona en UNA malla: son miles de objetos chicos y una malla por objeto sería
## desastroso para las draw calls.
func _visualize_roof_props() -> void:
	var container := _buildings_container("RoofProps")
	var mat := _get_building_material()
	var tanks := 0
	var roofs := 0
	var roof_bodies := 0
	## Edificios cuyo estilo sorteado no cerró como mosaico y quedaron planos, contados por motivo (ver
	## RoofPlanner.layout). Cualquier número acá es un caso a mirar.
	var roof_fallbacks := {}
	## Piezas que el placer rechazó aunque el planner las validó: si no es 0, hay un bug entre los dos.
	var roof_rejected := 0

	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or block.get_distorted_grid() == null:
			continue
		var cells_per_floor := block.get_cells_per_floor()
		var cell_height := block.get_building_cell_height()
		var buffer := PropGeometry.new_buffer()
		# Un scope por MANZANA, porque los techos se fusionan en una malla por manzana (los edificios, en
		# cambio, tienen una malla cada uno). La granularidad del scope sigue a la de la malla.
		var scope := city_index.new_scope()

		for cluster in block.get_all_clusters():
			if cluster.get_floor_count() <= 0 or cluster.cells.is_empty():
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = block.cluster_seed + cluster.id * 6151
			var roof_index := cluster.get_floor_count() * cells_per_floor
			# El MISMO id de objeto que las paredes de este edificio, aunque la malla sea otra: es lo que
			# hace que resaltar "el edificio" incluya su techo.
			var object_id := _object_for_cluster(cluster)
			var flat_cells: Array = []

			# ACÁ NO SE DECIDE NADA: el plan dice qué pieza va en cada celda y hacia dónde escurre, y esto
			# solo lo ejecuta (ver RoofPlanner).
			#
			# El ESTILO sale del arquetipo del cluster y de ningún otro lado. City tenía además su propia
			# `roof_shape_chance`, y dos perillas para lo mismo hacen impredecible el resultado; además esa
			# decidía por celda, cuando la forma de un techo es del edificio entero.
			var pitch := 2.2
			var flat_chance := 0.35
			var skirt := 8.0
			if cluster.archetype != null:
				pitch = cluster.archetype.roof_pitch_height
				flat_chance = cluster.archetype.flat_roof_chance
				skirt = cluster.archetype.roof_skirt_building_cells
			var pitch_cells := maxi(1, roundi(pitch / cell_height))
			var plan: Dictionary = RoofPlanner.layout(block, cluster, flat_chance, pitch_cells,
				roundi(skirt), roof_index)
			var pieces: Array = plan["pieces"]
			var reason: String = plan["fallback"]
			if not reason.is_empty():
				roof_fallbacks[reason] = int(roof_fallbacks.get(reason, 0)) + 1

			var modules := {}
			for cell in cluster.cells:
				var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
				if module != null:
					modules[cell] = module

			# TODO SE COLOCA POR LA MISMA INTERFAZ que cualquier otro objeto deformable (ver ModulePlacer): el
			# planner solo dice qué pieza va en qué región, y el placer deforma, anota en el índice y ocupa.
			var placer := ModulePlacer.new(city_index, scope, object_id, buffer)

			if pieces.is_empty():
				# Azotea plana, la única que acepta tanque.
				for cell in cluster.cells:
					if modules.has(cell):
						flat_cells.append(cell)
			else:
				roofs += 1
				var style: int = plan["style"]
				for p: Dictionary in pieces:
					# Tipos a mano: lo que sale de un Dictionary sin tipar es Variant, y no se puede pasar a
					# un parámetro tipado sin que sea una llamada insegura.
					var piece_cell: Vector2i = p["cell"]
					if not modules.has(piece_cell):
						continue
					var piece_module: BuildingModule = modules[piece_cell]
					var lo: Vector3i = p["lo"]
					var size: Vector3i = p["size"]
					var mesh: UnitMesh = p["mesh"]
					if not placer.place(piece_module, lo, size, mesh, CityIndex.Kind.ROOF, cluster.id,
							int(p["piece"]), int(p["side"]), style):
						# El planner valida el mosaico antes; si igual algo no entra, es un bug del planner.
						roof_rejected += 1

			# El tanque va sobre una celda que haya quedado PLANA: sobre un techo a dos aguas no se apoya.
			if not flat_cells.is_empty() and rng.randf() < water_tank_chance:
				# COLOCADO POR LA INTERFAZ: una región de celdas y una mesh unitaria. La deformación, el
				# índice y la ocupación los resuelve el placer; acá solo se decide dónde y qué.
				var tank_cell: Vector2i = flat_cells[rng.randi_range(0, flat_cells.size() - 1)]
				var tank_module: BuildingModule = modules[tank_cell]
				# EL TANQUE ES RÍGIDO: va en la matriz rígida de la azotea, sin deformarse (ver RigidMatrix).
				# La azotea es el quad del núcleo a la altura del último piso; lo que ya haya colocado en el
				# módulo se proyecta sobre esa matriz como ocupado. Si el tanque no entra en las celdas que
				# quedan —azotea angosta, torcida, o tapada— no se pone, y ese es todo el filtro.
				var roof := RigidMatrix.from_quad(tank_module.get_core_vertices(roof_index),
					ROOF_SURFACE_DEPTH_M, Vector3.UP)
				for box: Array in tank_module.occupied_world_boxes():
					roof.mark_world_box(box[0], box[1])
				var size := roof.cells_for(RoofProps.TANK_DIAMETER_M, RoofProps.tank_height_m(),
					RoofProps.TANK_DIAMETER_M)
				if placer.place_rigid(roof, roof.centered(size), size, RoofProps.water_tank_unit(),
						CityIndex.Kind.ROOF, cluster.id, RoofPlanner.Piece.TANK, -1, -1):
					tanks += 1

		if buffer["vertices"].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buffer["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = buffer["normals"]
		arrays[Mesh.ARRAY_COLOR]  = buffer["colors"]
		arrays[Mesh.ARRAY_INDEX]  = buffer["indices"]
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = array_mesh
		mesh_instance.material_override = mat
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_fade_into_fog(mesh_instance)
		container.add_child(mesh_instance)
		city_index.set_scope_mesh(scope, mesh_instance)

		# COLLIDER DEL TECHO, con los MISMOS triángulos y en el MISMO orden que la malla. Ese orden es el
		# contrato del que depende traducir el `face_index` del rayo a una pieza (ver CityIndex).
		var faces := PackedVector3Array()
		var roof_verts: PackedVector3Array = buffer["vertices"]
		for idx: int in buffer["indices"]:
			faces.append(roof_verts[idx])
		if not faces.is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var collision_shape := CollisionShape3D.new()
			collision_shape.shape = shape
			var body := StaticBody3D.new()
			body.add_child(collision_shape)
			body.set_meta(CityIndex.SCOPE_META, scope)
			container.add_child(body)
			roof_bodies += 1

	print("[Visualizer] Objetos de techo: %d edificios con techo inclinado · %d tanques · %d colliders · piezas rechazadas: %d · planos por no cerrar: %s"
		% [roofs, tanks, roof_bodies, roof_rejected, str(roof_fallbacks)])

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

		for door in block.traversal.delivery_doors:
			var cell: Vector2i = door["cell"]
			var edge_idx: int = door["edge"]
			var floor_idx: int = door["floor"]

			var module = block.get_building_module(cell.x, cell.y, 0)
			if module == null:
				continue

			var core = module.get_core_info()
			var height_index = floor_idx * cells_per_floor

			# La puerta ocupa un tramo ACOTADO de la cara, no toda: `along_min/along_max` vienen del
			# generador ya medidos en celdas (ver TraversalGenerator._door_span). Antes esto dibujaba el
			# ancho entero del núcleo por un piso de alto, que es un paredón y no una puerta.
			var along_min: int = door.get("along_min", core["min_x"])
			var along_max: int = door.get("along_max", core["max_x"])
			var door_height: float = float(door.get("height_cells", cells_per_floor)) * building_cell_height

			var bx_min: int; var bx_max: int; var bz_min: int; var bz_max: int
			match edge_idx:
				0:
					bx_min = along_min; bx_max = along_max
					bz_min = core["min_z"] - 1; bz_max = core["min_z"] - 1
				1:
					bx_min = core["max_x"] + 1; bx_max = core["max_x"] + 1
					bz_min = along_min; bz_max = along_max
				2:
					bx_min = along_min; bx_max = along_max
					bz_min = core["max_z"] + 1; bz_max = core["max_z"] + 1
				3:
					bx_min = core["min_x"] - 1; bx_max = core["min_x"] - 1
					bz_min = along_min; bz_max = along_max

			var verts = module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, height_index)
			if verts.size() == 4:
				add_child(DebugUtil.create_skewed_cube(verts, door_height, delivery_door_color))
			total += 1

	print("[Visualizer] Delivery doors: %d" % total)


# ============================================
# VISUALIZACIÓN DE STAIR ZONES
# ============================================

func _visualize_stair_zones() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total = 0

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue

		var cells_per_floor = block.get_cells_per_floor()
		var cell_h = block.get_building_cell_height()
		var block_static_body = StaticBody3D.new()
		var has_colliders = false

		for stair in block.traversal.stair_zones:
			var cell: Vector2i = stair["cell"]
			var edge_idx: int = stair["edge"]
			var floor_idx: int = stair["floor"]

			var module = block.get_building_module(cell.x, cell.y, 0)
			if module == null:
				continue

			var pieces = _build_stair_pieces(module, edge_idx, floor_idx, cells_per_floor, cell_h)
			for piece in pieces:
				if piece is StaticBody3D:
					for child in piece.get_children():
						if child is CollisionShape3D:
							piece.remove_child(child)
							block_static_body.add_child(child)
							has_colliders = true
					piece.queue_free()
				else:
					add_child(piece)
					total += 1

		if has_colliders:
			add_child(block_static_body)

	print("[Visualizer] Stair zones: %d pieces" % total)


func _build_stair_pieces(module: BuildingModule, edge_idx: int, floor_idx: int, cells_per_floor: int, cell_h: float) -> Array:
	var pieces: Array = []
	var core = module.get_core_info()

	var depth: int
	var along_length: int
	match edge_idx:
		0:
			depth = core["min_z"]
			along_length = module.columns
		1:
			depth = module.columns - core["max_x"] - 1
			along_length = module.rows
		2:
			depth = module.rows - core["max_z"] - 1
			along_length = module.columns
		3:
			depth = core["min_x"]
			along_length = module.rows

	if depth <= 1:
		return pieces

	var half_d = depth / 2
	if 2 * depth > along_length:
		return pieces

	var floor_base = floor_idx * cells_per_floor
	var half_floor = cells_per_floor / 2

	var to_bb = func(a_min: int, a_max: int, d_min: int, d_max: int) -> Array:
		match edge_idx:
			0: return [a_min, a_max, d_min, d_max]
			1: return [core["max_x"] + 1 + d_min, core["max_x"] + 1 + d_max, a_min, a_max]
			2: return [a_min, a_max, core["max_z"] + 1 + d_min, core["max_z"] + 1 + d_max]
			3: return [d_min, d_max, a_min, a_max]
		return []

	var li: Array
	var ri: Array
	if edge_idx == 0 or edge_idx == 2:
		li = [0, 3]
		ri = [1, 2]
	else:
		li = [0, 1]
		ri = [3, 2]

	var vface = func(bb: Array, h_idx: int, idx: Array) -> Array:
		var lo = module.get_region_vertices(bb[0], bb[1], bb[2], bb[3], h_idx)
		var hi = module.get_region_vertices(bb[0], bb[1], bb[2], bb[3], h_idx + 1)
		if lo.size() != 4 or hi.size() != 4:
			return []
		return [lo[idx[0]], lo[idx[1]], hi[idx[1]], hi[idx[0]]]

	# === 3 REST PLATFORMS ===
	# Bottom/top at far left (along=0), middle at far right (along=max)

	var bot_bb = to_bb.call(0, depth - 1, 0, depth - 1)
	var bot_v = module.get_region_vertices(bot_bb[0], bot_bb[1], bot_bb[2], bot_bb[3], floor_base)
	if bot_v.size() == 4:
		pieces.append(DebugUtil.create_skewed_cube(bot_v, cell_h, stair_zone_color))
		var c = DebugUtil.create_skewed_cube_collider(bot_v, cell_h)
		if c: pieces.append(c)

	var mid_bb = to_bb.call(along_length - depth, along_length - 1, 0, depth - 1)
	var mid_v = module.get_region_vertices(mid_bb[0], mid_bb[1], mid_bb[2], mid_bb[3], floor_base + half_floor)
	if mid_v.size() == 4:
		pieces.append(DebugUtil.create_skewed_cube(mid_v, cell_h, stair_zone_color))
		var c = DebugUtil.create_skewed_cube_collider(mid_v, cell_h)
		if c: pieces.append(c)

	var top_v = module.get_region_vertices(bot_bb[0], bot_bb[1], bot_bb[2], bot_bb[3], floor_base + cells_per_floor)
	if top_v.size() == 4:
		pieces.append(DebugUtil.create_skewed_cube(top_v, cell_h, stair_zone_color))
		var c = DebugUtil.create_skewed_cube_collider(top_v, cell_h)
		if c: pieces.append(c)

	var r1_bb_bot = to_bb.call(0, depth - 1, 0, half_d - 1)
	var r1_bb_mid = to_bb.call(along_length - depth, along_length - 1, 0, half_d - 1)
	var r1_f1 = vface.call(r1_bb_bot, floor_base, ri)
	var r1_f2 = vface.call(r1_bb_mid, floor_base + half_floor, li)
	if r1_f1.size() == 4 and r1_f2.size() == 4:
		pieces.append(DebugUtil.create_skewed_cube_from_planes(r1_f1, r1_f2, stair_zone_color, 1.0))
		var c = DebugUtil.create_from_planes_collider(r1_f1, r1_f2)
		if c: pieces.append(c)

	var r2_bb_mid = to_bb.call(along_length - depth, along_length - 1, half_d, depth - 1)
	var r2_bb_top = to_bb.call(0, depth - 1, half_d, depth - 1)
	var r2_f1 = vface.call(r2_bb_mid, floor_base + half_floor, li)
	var r2_f2 = vface.call(r2_bb_top, floor_base + cells_per_floor, ri)
	if r2_f1.size() == 4 and r2_f2.size() == 4:
		pieces.append(DebugUtil.create_skewed_cube_from_planes(r2_f1, r2_f2, stair_zone_color, 1.0))
		var c = DebugUtil.create_from_planes_collider(r2_f1, r2_f2)
		if c: pieces.append(c)

	return pieces


# ============================================
# VISUALIZACIÓN DE FLOATING SIDEWALK ZONES
# ============================================

var _sidewalk_material: StandardMaterial3D = null
var _bridge_material: StandardMaterial3D = null

func _get_bridge_material() -> StandardMaterial3D:
	if _bridge_material == null:
		_bridge_material = StandardMaterial3D.new()
		_bridge_material.vertex_color_use_as_albedo = true
		_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_bridge_material.cull_mode = BaseMaterial3D.CULL_BACK
		_bridge_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return _bridge_material

## OJO: hay que llamarla ANTES de `_fade_into_fog`, porque usa el AABB de la malla en coordenadas de
## mundo y aquella lo recentra en el origen. (Hoy es inerte de todos modos: occlusion culling esta
## apagado en project.godot, `rendering/occlusion_culling/use_occlusion_culling`.)
func _add_box_occluder(mesh: ArrayMesh, parent: Node3D) -> void:
	var aabb := mesh.get_aabb()
	var occ_inst := OccluderInstance3D.new()
	var box_occ := BoxOccluder3D.new()
	box_occ.size = aabb.size
	occ_inst.occluder = box_occ
	occ_inst.position = aabb.get_center()
	parent.add_child(occ_inst)

func _bridge_geo_append(buf: Dictionary, geo: Dictionary, color: Color) -> void:
	if geo.is_empty():
		return
	var offset: int = buf.verts.size()
	buf.verts.append_array(geo.vertices)
	buf.norms.append_array(geo.normals)
	for _i in geo.vertices.size():
		buf.colors.append(color)
	for idx: int in geo.indices:
		buf.idxs.append(idx + offset)

func _get_sidewalk_material() -> StandardMaterial3D:
	if _sidewalk_material == null:
		_sidewalk_material = StandardMaterial3D.new()
		_sidewalk_material.albedo_color = sidewalk_color
		_sidewalk_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_sidewalk_material.cull_mode = BaseMaterial3D.CULL_BACK
	return _sidewalk_material

func _visualize_floating_sidewalk_zones() -> void:
	var all_block_faces = generator.get_all_block_faces()
	var total = 0
	var mat := _get_sidewalk_material()

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue

		var cells_per_floor := block.get_cells_per_floor()
		var building_cell_height := block.get_building_cell_height()
		var sidewalk_h := building_cell_height
		var block_static_body := StaticBody3D.new()
		var has_colliders := false

		var merged_verts  := PackedVector3Array()
		var merged_norms  := PackedVector3Array()
		var merged_idxs   := PackedInt32Array()

		for sw in block.traversal.floating_sidewalk_zones:
			var cell: Vector2i = sw["cell"]
			var floor_idx: int = sw["floor"]

			var module = block.get_building_module(cell.x, cell.y, 0)
			if module == null:
				continue

			var height_index := floor_idx * cells_per_floor
			var bx_min: int = sw["bx_min"]
			var bx_max: int = sw["bx_max"]
			var bz_min: int = sw["bz_min"]
			var bz_max: int = sw["bz_max"]

			if bx_min > bx_max or bz_min > bz_max:
				continue

			var verts := module.get_region_vertices(bx_min, bx_max, bz_min, bz_max, height_index)
			if verts.size() != 4:
				continue

			var geo := DebugUtil.get_skewed_cube_geometry(verts, sidewalk_h)
			if not geo.is_empty():
				var offset := merged_verts.size()
				merged_verts.append_array(geo.vertices)
				merged_norms.append_array(geo.normals)
				for idx in geo.indices:
					merged_idxs.append(idx + offset)

			var collider_body := DebugUtil.create_skewed_cube_collider(verts, sidewalk_h)
			if collider_body:
				for child in collider_body.get_children():
					if child is CollisionShape3D:
						collider_body.remove_child(child)
						block_static_body.add_child(child)
						has_colliders = true
				collider_body.queue_free()
			total += 1

		if not merged_verts.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = merged_verts
			arrays[Mesh.ARRAY_NORMAL] = merged_norms
			arrays[Mesh.ARRAY_INDEX]  = merged_idxs
			var array_mesh := ArrayMesh.new()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = array_mesh
			mesh_instance.material_override = mat
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Antes de recentrar: ver el comentario en _visualize_buildings.
			_add_box_occluder(array_mesh, self)
			_fade_into_fog(mesh_instance)
			add_child(mesh_instance)

		if has_colliders:
			add_child(block_static_body)

	print("[Visualizer] Floating sidewalk zones: %d" % total)


# ============================================
# VISUALIZACIÓN DE PUENTES
# ============================================

func _visualize_bridges() -> void:
	var total := 0
	for edge_key in generator.bridges:
		for placed in generator.bridges[edge_key]:
			var buf := {
				verts  = PackedVector3Array(),
				norms  = PackedVector3Array(),
				colors = PackedColorArray(),
				idxs   = PackedInt32Array(),
			}
			var scope := city_index.new_scope()
			_draw_bridge(placed, buf)
			total += 1
			if buf.verts.is_empty():
				continue
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = buf.verts
			arrays[Mesh.ARRAY_NORMAL] = buf.norms
			arrays[Mesh.ARRAY_COLOR]  = buf.colors
			arrays[Mesh.ARRAY_INDEX]  = buf.idxs
			var array_mesh := ArrayMesh.new()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = array_mesh
			mi.material_override = _get_bridge_material()
			_fade_into_fog(mi)
			add_child(mi)

			# Un puente entero es UNA pieza por ahora: alcanza para decir cuál es. Partirlo en base,
			# pasarela, baranda y arcos es anotar un registro por tramo dentro de `_draw_bridge`.
			var bridge_idxs: PackedInt32Array = buf.idxs
			var bridge_verts: PackedVector3Array = buf.verts
			city_index.set_scope_mesh(scope, mi)
			city_index.add(scope, _new_object(), CityIndex.Kind.BRIDGE, total, int(placed["face_a"]),
				int(placed["face_b"]), int(placed["floor_idx"]), 0, bridge_idxs.size(), bridge_verts)
			var bridge_body: Object = buf.get("body")
			if bridge_body is StaticBody3D:
				(bridge_body as StaticBody3D).set_meta(CityIndex.SCOPE_META, scope)
	print("[Visualizer] Puentes: %d" % total)


func _draw_bridge(placed: Dictionary, buf: Dictionary) -> void:
	var bridge: Bridge     = placed["bridge"]
	var cell_start: int    = placed["cell_start"]
	var cell_end: int      = placed["cell_end"]
	var floor_idx: int     = placed["floor_idx"]
	var cell_height: float = placed["cell_height"]
	var cells_per_floor: int = placed["cells_per_floor"]
	var by_base: int = floor_idx * cells_per_floor - bridge.base_height
	var by_base_top: int = floor_idx * cells_per_floor
	var by_arc_bot: int = by_base - bridge.arc_height

	var side_a = {
		"face": placed["face_a"], "edge_idx": placed["edge_idx_a"],
		"cells": placed["cells_a"], "reversed": placed["reversed_a"],
	}
	var side_b = {
		"face": placed["face_b"], "edge_idx": placed["edge_idx_b"],
		"cells": placed["cells_b"], "reversed": placed["reversed_b"],
	}

	# LOS EXTREMOS DECIDEN, EL MEDIO LOS UNE — y ahora literalmente.
	#
	# El medio ya no inventa ningún plano: toma la CARA REAL de cada fachada
	# (`FacadeHelper.facade_span_quad`, sampleada de la grilla arriba y abajo) y se estira entre las dos.
	# Antes se armaba con las esquinas de manzana y una altura escalar por lado, así que su borde salía
	# HORIZONTAL mientras la cara de la fachada está TORCIDA —medido, hasta 0,205 m de torsión a lo largo
	# del tramo—. Un borde recto contra uno torcido no coincide salvo en un punto: de ahí los centímetros.
	#
	# Importa para algo concreto: la pasarela del puente y la pasarela flotante del edificio tienen que
	# ser UNA superficie caminable continua, y eso solo pasa si el puente hereda la torsión del piso.
	var block_a: BlockGenerator = generator.get_block_grid(side_a["face"])
	var block_b: BlockGenerator = generator.get_block_grid(side_b["face"])
	if block_a == null or block_b == null:
		return

	var by_path_top := by_base_top + bridge.pathway_height
	var by_rail_top := by_path_top + bridge.railing_height

	var static_body: StaticBody3D = null
	if enable_bridge_colliders:
		static_body = StaticBody3D.new()

	_add_bridge_span(block_a, block_b, side_a, side_b, cell_start, cell_end,
			by_base, by_base_top, bridge_base_color, static_body, buf)
	_add_bridge_span(block_a, block_b, side_a, side_b, cell_start, cell_end,
			by_base_top, by_path_top, bridge_pathway_color, static_body, buf)

	if bridge.railing_height > 0:
		_add_bridge_span(block_a, block_b, side_a, side_b, cell_start, cell_start,
				by_path_top, by_rail_top, bridge_railing_color, static_body, buf)
		_add_bridge_span(block_a, block_b, side_a, side_b, cell_end, cell_end,
				by_path_top, by_rail_top, bridge_railing_color, static_body, buf)

	if bridge.arc_height > 0 and bridge.arc_length > 0:
		_add_bridge_arc_spans(block_a, block_b, side_a, side_b, cell_start, cell_end,
				by_arc_bot, by_base, bridge.arc_length * cell_height, static_body, buf)

	for side in [side_a, side_b]:
		_draw_bridge_extremes(bridge, side, cell_start, cell_end,
				by_base, by_base_top, by_arc_bot, static_body, buf)

	if static_body:
		# Se devuelve por el buffer para que quien lo llamó pueda estamparlo con su scope (ver CityIndex).
		buf["body"] = static_body
		add_child(static_body)


## UN TRAMO DEL CONECTOR: une la cara real de una fachada con la de la otra.
##
## Las dos caras salen de `FacadeHelper.facade_span_quad`, o sea de la grilla, con su torsión. El tramo
## no aporta forma propia: solo estira una hacia la otra.
func _add_bridge_span(block_a: BlockGenerator, block_b: BlockGenerator,
		side_a: Dictionary, side_b: Dictionary, cell_start: int, cell_end: int,
		index_bottom: int, index_top: int,
		color: Color, static_body: StaticBody3D, buf: Dictionary) -> void:
	var plane_a := FacadeHelper.facade_span_quad(block_a, side_a["edge_idx"], side_a["reversed"],
			side_a["cells"], cell_start, cell_end, index_bottom, index_top)
	var plane_b := FacadeHelper.facade_span_quad(block_b, side_b["edge_idx"], side_b["reversed"],
			side_b["cells"], cell_start, cell_end, index_bottom, index_top)
	if plane_a.size() != 4 or plane_b.size() != 4:
		return
	_bridge_geo_append(buf, DebugUtil.get_skewed_cube_from_planes_geometry(plane_a, plane_b), color)
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(plane_a, plane_b))


## Los arcos: dos trozos cortos pegados a cada punta, entre las mismas dos caras reales.
func _add_bridge_arc_spans(block_a: BlockGenerator, block_b: BlockGenerator,
		side_a: Dictionary, side_b: Dictionary, cell_start: int, cell_end: int,
		index_bottom: int, index_top: int,
		arc_world_depth: float, static_body: StaticBody3D, buf: Dictionary) -> void:
	var plane_a := FacadeHelper.facade_span_quad(block_a, side_a["edge_idx"], side_a["reversed"],
			side_a["cells"], cell_start, cell_end, index_bottom, index_top)
	var plane_b := FacadeHelper.facade_span_quad(block_b, side_b["edge_idx"], side_b["reversed"],
			side_b["cells"], cell_start, cell_end, index_bottom, index_top)
	if plane_a.size() != 4 or plane_b.size() != 4:
		return

	var bridge_depth = plane_a[0].distance_to(plane_b[0])
	var arc_frac = clampf(arc_world_depth / bridge_depth, 0.0, 0.45) if bridge_depth > 0.0 else 0.0

	var near_plane: Array[Vector3] = []
	for i in range(4):
		near_plane.append(plane_a[i].lerp(plane_b[i], arc_frac))
	_bridge_geo_append(buf, DebugUtil.get_skewed_cube_from_planes_geometry(plane_a, near_plane), bridge_arc_color)
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(plane_a, near_plane))

	var far_plane: Array[Vector3] = []
	for i in range(4):
		far_plane.append(plane_a[i].lerp(plane_b[i], 1.0 - arc_frac))
	_bridge_geo_append(buf, DebugUtil.get_skewed_cube_from_planes_geometry(far_plane, plane_b), bridge_arc_color)
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(far_plane, plane_b))


## EL EXTREMO SIGUE LA GRILLA, en las dos alturas.
##
## Se arma como un prisma entre el índice de abajo y el de arriba (ver `BuildingModule.get_region_prism`).
## Los pisos son paralelos, así que extruir en vertical daría lo mismo; se samplean igual las dos alturas
## para que la pieza no dependa de eso y su borde superior caiga siempre en el fin del piso.
func _draw_bridge_extremes(bridge: Bridge, side: Dictionary, cell_start: int, cell_end: int,
		by_base: int, by_base_top: int, by_arc_bot: int,
		static_body: StaticBody3D, buf: Dictionary) -> void:
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

		var base_prism := module.get_region_prism(bx_min, bx_max, bz_min, bz_max, by_base, by_base_top)
		if base_prism.size() == 2:
			var base_bottom: Array[Vector3] = base_prism[0]
			var base_top: Array[Vector3] = base_prism[1]
			_bridge_geo_append(buf,
					DebugUtil.get_skewed_cube_from_planes_geometry(base_bottom, base_top), bridge_base_color)
			if static_body:
				static_body.add_child(DebugUtil.create_collision_shape_from_planes(base_bottom, base_top))

		if bridge.arc_height > 0:
			var arc_prism := module.get_region_prism(bx_min, bx_max, bz_min, bz_max, by_arc_bot, by_base)
			if arc_prism.size() == 2:
				var arc_bottom: Array[Vector3] = arc_prism[0]
				var arc_top: Array[Vector3] = arc_prism[1]
				_bridge_geo_append(buf,
						DebugUtil.get_skewed_cube_from_planes_geometry(arc_bottom, arc_top), bridge_arc_color)
				if static_body:
					static_body.add_child(DebugUtil.create_collision_shape_from_planes(arc_bottom, arc_top))
