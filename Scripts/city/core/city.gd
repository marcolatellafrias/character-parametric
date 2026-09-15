# CityVisualizer.gd
extends Node3D

# ============================================
# PARÁMETROS DE GENERACIÓN
# ============================================
@export_group("Generación del Grafo")
## Lado de la región donde se siembran los nodos. El doble de área es el doble de manzanas.
@export var region_size: Vector2 = Vector2(2138.4, 2138.4)
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
## LA CELDA DE EDIFICIO, en metros: la unidad en la que se cuentan pisos (32 celdas), callejones (18 por
## lado) y veredas (24). Es fija a propósito: cuántas celdas tiene un módulo sale de dividir su ancho por
## esta —no al revés—, así que agrandar las manzanas (`min_distance`) ensancha edificios y nada más.
## 0,213 es lo que daban 80 celdas en la ciudad de 164 m de `min_distance`.
@export_range(0.05, 1.0, 0.001) var building_cell_m: float = 0.213

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

@export_group("Afueras")
## LA ALTURA INFRANQUEABLE, en pisos de edificio. Es el único número del límite del mundo: lo usa la
## cima de las montañas y de él sale el techo de la nave (`Ship.max_altitude`, vía
## `WorldSettings.impassable_height`). Cambiarlo acá lo cambia en todos lados.
##
## 13 pisos (~87 m): la nave llega a 10 con el propulsor, así que queda fuera de alcance por 3 sin
## encerrar como una caja, y los edificios altos (15 a 22) la superan siempre.
@export_range(0.0, 40.0, 0.5) var impassable_floors: float = 16.0
## DÓNDE NIVELAN LAS AFUERAS, en pisos, y con signo. Positivo son montañas; NEGATIVO hunde la falda y la
## ciudad queda arriba de una meseta, con la tierra cayendo hacia afuera. Va aparte de la altura
## infranqueable justo porque la barrera es la que contiene: la forma quedó libre de ir para donde quiera.
@export_range(-20.0, 40.0, 0.5) var outskirts_crest_floors: float = 40.0
@export var show_outskirts: bool = true
## Cuántos metros hay del borde de la ciudad a la cima, ANTES de la variación por dirección.
@export_range(100.0, 4000.0, 10.0) var outskirts_depth: float = 2440.0
## Cuánto se estira o se acorta esa distancia según la dirección, de 0 (anillo parejo, se lee artificial)
## a 1 (la mitad o el doble). Es lo que evita que el límite se sienta un círculo.
@export_range(0.0, 1.0) var outskirts_depth_variation: float = 1.0
## En cuántas tiras se parte la subida. Más tiras, silueta más fina y más triángulos.
@export_range(2, 40) var outskirts_rings: int = 17
## Cuánto puede QUEDARSE CORTA una cima respecto de la altura infranqueable, según la dirección. En 0
## todas las cimas miden lo mismo y el límite se lee como un anillo parejo; en 1 van de un cordón entero
## a casi nada. Que un paso quede bajo no abre el mundo: de contener se ocupa la barrera invisible.
@export_range(0.0, 1.0) var outskirts_crest_variation: float = 0.504
## Cuánto relieve propio llevan las afueras, como fracción de la cima. Es lo que las saca de ser una
## rampa lisa: cava valles y levanta lomos por encima del perfil.
@export_range(0.0, 1.0) var outskirts_relief: float = 1.0
## Tamaño de esas formas, en metros. Grande da cordones largos; chico, cerros sueltos.
@export_range(100.0, 10000.0) var outskirts_feature_size: float = 1599.6
## Corrimiento de la semilla de las afueras: cambiarlo vuelve a sortear las montañas SIN tocar la ciudad.
@export_range(0, 999, 1) var outskirts_seed_offset: int = 87
## Cómo sube el perfil hacia la cima. 1 es una rampa recta; arriba de 1 arranca plano y se empina al
## final, que es como se lee una montaña; abajo de 1 sube de golpe y se aplana, como una meseta.
@export_range(0.3, 4.0, 0.05) var outskirts_rise_power: float = 2.0
## En qué punto del recorrido está la cima. Más chico la trae cerca de la ciudad y deja una bajada larga
## por detrás; en 1.0 la cima es la última tira y no hay contrapendiente.
@export_range(0.2, 1.0, 0.01) var outskirts_crest_at: float = 0.79
## Cuánto baja pasada la cima, como fracción de ella. Le da espesor a la silueta en vez de un filo.
@export_range(0.0, 1.0, 0.01) var outskirts_back_drop: float = 0.17
## LA BARRERA INVISIBLE, en la última tira: sube hasta la altura infranqueable y es lo único que contiene
## de verdad. Existe para que la silueta pueda hacer lo que quiera —valles, pasos bajos, cimas
## desparejas— sin que la nave se escape por el punto más bajo.
@export var enable_outskirts_barrier: bool = true
@export var enable_outskirts_collider: bool = true
@export var outskirts_color: Color = Color(0.17016602, 0.17165756, 0.265625)

@export_group("Terreno")
## Alto de la loma más alta, en PISOS de edificio: es lo que se lee en el juego —cuántos pisos se come el
## relieve—. En 0 la ciudad queda plana, como antes.
@export_range(0.0, 20.0, 0.1) var terrain_floors: float = 7.8
## Cada cuántos metros cambia el relieve. Más chico, lomas más apretadas.
@export_range(50.0, 3000.0, 5.0) var terrain_feature_size: float = 300.0
## Pendiente máxima de una calle. Si el ruido se pasa, se baja la amplitud de todo el campo (ver
## CityTerrain): 12% es una calle empinada pero caminable.
@export_range(0.01, 0.5) var terrain_max_slope: float = 0.12
@export var show_ground: bool = true
@export var enable_ground_collider: bool = true
@export var ground_color: Color = Color(0.33, 0.31, 0.27)
## Las calles van en su propia malla, para el shader de asfalto que viene (ver `_visualize_ground`).
@export var street_color: Color = Color(0.16, 0.16, 0.17)

@export_group("Buildings")
@export var show_buildings: bool = false
@export var enable_building_colliders: bool = true
@export var show_parked_cars: bool = true

@export_group("Vista")
## LA VISTA DEBUG DE EDIFICIOS: en lugar de la malla final (color del arquetipo, sin caras interiores; la
## que va a llevar los huecos) se muestra la debug (color del barrio, un piso sí y uno no más oscuro, módulos
## en damero, la forma básica sin huecos). Las dos se construyen al generar (ver BuildingShell); esto solo
## prende una y apaga la otra, al instante. Arranca apagada.
@export var building_debug_view: bool = false:
	set(value):
		building_debug_view = value
		_apply_view()
enum BuildingGrid { NONE, DEFORMABLE, RIGID }
## Con la vista debug, una grilla translúcida sobre cada cara de cada módulo: la DEFORMABLE del módulo
## (celdas de 0,213 m; donde van techos, veredas y extremos de puente) o la RÍGIDA de cada superficie
## (~0,25 m; donde van puertas, ventanas y tanques). Es la misma grilla donde el placer coloca, vértice por
## vértice (ver BuildingShell y Shaders/building_debug.gdshader).
@export var building_grid: BuildingGrid = BuildingGrid.NONE:
	set(value):
		building_grid = value
		_apply_view()
## Con la vista debug, la región exacta que cada objeto colocado ocupa en su grilla, como caja translúcida:
## roja para lo deformable, verde para lo rígido (ver `_visualize_placement_boxes`).
@export var show_deformable_boxes: bool = false:
	set(value):
		show_deformable_boxes = value
		_apply_view()
@export var show_rigid_boxes: bool = false:
	set(value):
		show_rigid_boxes = value
		_apply_view()

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

@export_group("Delivery Doors")
@export var show_delivery_doors: bool = false

@export_group("Ventanas")
@export var show_windows: bool = true
## Si las ventanas se HUNDEN en la pared con su abertura cortada y sus derrames (ver
## BuildingSkin.add_opening), como las puertas siempre. Con cientos de miles de ventanas dibujadas vértice
## a vértice en GDScript cuesta decenas de segundos y cientos de MB, así que la escena del juego lo apaga
## —ventanas al ras, sin hueco— hasta que las ventanas sean instancias (MultiMesh, ver
## technical/city-generation.md). La muestra del sandbox lo deja prendido: ahí se mira de cerca.
@export var window_openings: bool = true

@export_group("Objetos de techo")
@export var show_roof_props: bool = true
## Cada cuánto un CLUSTER de techo plano se lleva un tanque de agua. Bajo a propósito: repetido
## demasiado, el tanque deja de leerse como detalle y se vuelve textura.
@export_range(0.0, 1.0) var water_tank_chance: float = 0.12

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
var _debug_material: ShaderMaterial = null
const BUILDING_DEBUG_SHADER := preload("res://Shaders/building_debug.gdshader")
const PLACEMENT_BOX_SHADER := preload("res://Shaders/placement_box.gdshader")
const DEFORMABLE_BOX_TINT := Color(1.0, 0.15, 0.1, 0.12)
const RIGID_BOX_TINT := Color(0.15, 1.0, 0.2, 0.12)
## Los nodos que la vista prende y apaga (ver `_apply_view`): las dos mallas de los edificios y las cajas.
var _final_buildings: Node3D = null
var _debug_buildings: Node3D = null
var _deformable_boxes: MultiMeshInstance3D = null
var _rigid_boxes: MultiMeshInstance3D = null
## La malla debug (semántica) de cada cluster, de donde sale su collider (ver BuildingShell).
var _shell_mesh_by_cluster: Dictionary = {}
## Y la piel de los HUECOS, que se pisan por dentro: ahí el collider es ella, con el hueco del portón.
var _skin_mesh_by_cluster: Dictionary = {}
## El portón de cada edificio que lleva uno (ver Gate): uno solo por edificio.
var _gates: Dictionary = {}
## LAS ABERTURAS de cada cluster —`{quad, outward, arch, segments}` por puerta y ventana colocada—, que la
## piel corta al construirse. Por eso las fachadas se colocan ANTES que las cáscaras (ver `_passes`).
var _openings: Dictionary = {}
## LAS FRANJAS DE ESTACIONAMIENTO, `[a, b]` de cada cordón con calle: el tráfico las reserva como obstáculo
## (ver AreaInstantiator._register_parking_strips).
var parking_strips: Array[PackedVector3Array] = []

## EL EDIFICIO EN FOCO, o null para todos: en la muestra del design sandbox (`generate_block_sample`) solo
## él se dibuja completo —techo, puertas, ventanas— y el resto sale como fantasma gris translúcido, sin
## accesorios, para que se lo vea a él.
var spotlight: BuildingCluster = null
const GHOST_COLOR := Color(0.6, 0.6, 0.6)
var _ghost_material: StandardMaterial3D = null
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
		building_cell_m,
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

## UNA MANZANA DE MUESTRA, para el design sandbox: una sola, cuadrada, sin distorsión ni relieve, del
## distrito del arquetipo (ver GraphCityGenerator.generate_single_block), con TODOS los edificios de ese
## arquetipo —forzado, ver ArchetypeDefinitions— y el más grande en foco; el resto, fantasmas. Todo lo que
## no sea la manzana (calles, afueras, carriles) queda apagado; los colliders también, porque el nodo va
## escalado (ver BuildingArchetype.build).
func generate_block_sample(sample_seed: int, archetype: BuildingArchetype, side_m: float,
		distortion: Vector2 = Vector2.ZERO, colliders := false) -> void:
	show_streets = false
	show_outskirts = false
	show_distorted_grid = false
	show_nodes = false
	show_bridges = false
	show_lane_planes = false
	show_lane_volumes = false
	show_traffic_planes = false
	show_floor_planes = false
	show_stair_zones = false
	enable_traffic_lights = false
	enable_ground_collider = false
	enable_building_colliders = colliders
	show_buildings = true
	show_delivery_doors = true
	show_windows = true
	show_roof_props = true

	clear_visualization()
	generator = GraphCityGenerator.new()
	generator.enable_traffic_lights = false
	ArchetypeDefinitions.forced_archetype = archetype.get_script()
	generator.generate_single_block(side_m, sample_seed, archetype.district, NeighborhoodTypes.Height.MID,
		block_grid_rows, block_grid_columns, block_cells_per_floor, distorted_grid_rows,
		distorted_grid_columns, small_alleyways_count, big_alleyways_count, min_steps_before_turn,
		building_cell_m, distortion)
	ArchetypeDefinitions.forced_archetype = null
	spotlight = _largest_cluster()
	visualize_graph()


## El edificio con más celdas que no sea el corazón de manzana: el que mejor muestra al arquetipo.
func _largest_cluster() -> BuildingCluster:
	var best: BuildingCluster = null
	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null:
			continue
		for cluster in block.get_all_clusters():
			if cluster.is_block_heart or cluster.get_floor_count() <= 0:
				continue
			if best == null or cluster.cells.size() > best.cells.size():
				best = cluster
	return best


## LOS PASES DE LA CIUDAD, EN ORDEN: `[nombre, función, si corre]`. Cada uno lee la ocupación que dejaron
## los anteriores y escribe la suya, y ese orden es lo único que evita la circularidad entre lo que va en
## la grilla del módulo, en las superficies y en free placement (ver technical/city-generation.md,
## "Passes"). Es una tabla y no una cadena de `if` porque el orden va a cambiar seguido:
##   · Lo deformable (puentes, veredas, techos) ocupa el módulo.
##   · Lo rígido (puertas, ventanas) lee esa ocupación en su superficie, y deja anotadas las ABERTURAS.
##   · Free placement (autos estacionados) lee las puertas.
##   · Recién entonces la cáscara y la piel, que necesitan las aberturas para cortar la pared; y el collider,
##     que sale de la cáscara.
func _passes() -> Array[Array]:
	return [
		["carriles", _add_lane_volumes_to_scene, true],
		["suelo", _visualize_ground, show_ground],
		["afueras", _visualize_outskirts, show_outskirts],
		["calles (debug)", _visualize_streets, show_streets],
		["planos de piso (debug)", _visualize_floor_planes, show_floor_planes],
		["grillas (debug)", _visualize_distorted_grids, show_distorted_grid],
		["planos de carril (debug)", _visualize_lane_planes, show_lane_planes],
		["volúmenes de carril (debug)", _visualize_lane_volumes, show_lane_volumes],
		["planos de tráfico (debug)", _visualize_traffic_planes, show_traffic_planes],
		["nodos (debug)", _visualize_nodes, show_nodes],
		["puentes", _visualize_bridges, show_bridges],
		["veredas", _visualize_floating_sidewalk_zones, true],
		["techos", _visualize_roof_props, show_roof_props],
		["fachadas", _visualize_facade_objects, show_delivery_doors or show_windows],
		["autos estacionados", _visualize_parked_cars, show_parked_cars],
		["edificios", _visualize_buildings, show_buildings or enable_building_colliders],
		["colliders", _visualize_building_colliders, enable_building_colliders],
		["escaleras (debug)", _visualize_stair_zones, show_stair_zones],
		["cajas de lo colocado", _visualize_placement_boxes, true],
	]


# Libera solo los hijos visuales; el generator se reemplaza en generate_graph().
func clear_visualization() -> void:
	for child in get_children():
		child.queue_free()
	# Lo que los hijos dejaron anotado se va con ellos: el índice apuntaría a mallas que ya no existen.
	city_index = CityIndex.new()
	_scope_by_cluster.clear()
	_shell_mesh_by_cluster.clear()
	_skin_mesh_by_cluster.clear()
	_gates.clear()
	_openings.clear()
	parking_strips.clear()
	_final_buildings = null
	_debug_buildings = null
	_deformable_boxes = null
	_rigid_boxes = null

func visualize_graph() -> void:
	if generator == null or generator.plain_graph == null:
		push_error("No hay grafo generado para visualizar")
		return

	for pass_entry in _passes():
		if not pass_entry[2]:
			continue
		var started := Time.get_ticks_msec()
		(pass_entry[1] as Callable).call()
		print("[Pase] %s: %d ms" % [pass_entry[0], Time.get_ticks_msec() - started])
	_apply_view()

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
		_building_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_building_material.cull_mode = BaseMaterial3D.CULL_BACK
		_building_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		_building_material.vertex_color_use_as_albedo = true
	return _building_material


func _spotlit(cluster: BuildingCluster) -> bool:
	return spotlight == null or cluster == spotlight


func _get_ghost_material() -> StandardMaterial3D:
	if _ghost_material == null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.albedo_color = Color(0.72, 0.72, 0.72, 0.35)
		_ghost_material.cull_mode = BaseMaterial3D.CULL_BACK
	return _ghost_material


## El material de la malla debug de los edificios, uno para toda la ciudad: la grilla se elige escribiendo
## su uniform (ver `_apply_view`).
func _get_debug_material() -> ShaderMaterial:
	if _debug_material == null:
		_debug_material = ShaderMaterial.new()
		_debug_material.shader = BUILDING_DEBUG_SHADER
		_debug_material.set_shader_parameter("grid_mode", building_grid)
	return _debug_material


## LA VISTA: cuál de las dos mallas de edificio se ve, qué grilla lleva la debug y qué cajas se muestran. Es
## instantáneo porque todo está construido: acá solo se prenden y apagan nodos y se escribe un uniform.
## Antes de generar no hay nada que tocar.
func _apply_view() -> void:
	if is_instance_valid(_final_buildings):
		_final_buildings.visible = not building_debug_view
	if is_instance_valid(_debug_buildings):
		_debug_buildings.visible = building_debug_view
	if is_instance_valid(_deformable_boxes):
		_deformable_boxes.visible = building_debug_view and show_deformable_boxes
	if is_instance_valid(_rigid_boxes):
		_rigid_boxes.visible = building_debug_view and show_rigid_boxes
	if _debug_material != null:
		_debug_material.set_shader_parameter("grid_mode", building_grid)

# ============================================
# AFUERAS
# ============================================
# LO QUE HAY MÁS ALLÁ DE LA CIUDAD: una falda de terreno que sube desde el borde hasta una cima
# infranqueable. Reemplazó a la muralla, que era invisible y dejaba el mundo terminando en el aire — lo
# que encerraba no era el muro, era el vacío detrás.
#
# Se construye EMPUJANDO EL BORDE HACIA AFUERA en línea recta desde el centro de la ciudad. El borde ya
# existe como anillo de nodos del grafo (`GraphGenerator.boundary_ring`), así que no hay que inventarle un
# recorrido, igual que no había que inventárselo a la muralla.
#
# Por qué RADIAL y no perpendicular a cada tramo: empujar cada arista por su propia normal pliega la malla
# en las esquinas cóncavas. Desde el centro no puede pasar mientras el contorno sea estrellado respecto de
# él, y lo es — medido sobre una ciudad: 38 nodos, 0 tramos que retroceden en ángulo, hueco máximo de 17°.
#
# LA COSTURA ES EXACTA y no por acuerdo: la primera tira usa la altura de los nodos del borde, que es la
# misma que la ciudad interpola a lo largo de esa arista. De ahí para afuera la altura la da
# `CityTerrain.height_at`, el MISMO campo de ruido que armó el relieve de adentro.
#
# LA DISTANCIA A LA CIMA VARÍA POR DIRECCIÓN, y de ahí sale que no se lea como un anillo: se sortea con el
# mismo campo de ruido, muestreado lejos en la dirección de salida. En algunas direcciones la montaña
# arranca cerca y en otras lejos, pero en todas termina llegando a `impassable_floors`.
func _visualize_outskirts() -> void:
	var graph := generator.plain_graph
	var terrain := generator.terrain
	var ring := graph.boundary_ring()
	if ring.size() < 3 or terrain == null:
		return
	var loose := graph.boundary_node_count() - ring.size()

	var limit := impassable_floors * _floor_height()
	var target := outskirts_crest_floors * _floor_height()
	var centre := Vector2.ZERO
	for node_idx in ring:
		var p: Vector3 = graph.points[node_idx]
		centre += Vector2(p.x, p.z)
	centre /= float(ring.size())

	# El campo que le da forma a las afueras: OTRO ruido, de formas mucho más grandes que el de la ciudad
	# (300 m ahí, más de un kilómetro acá). Va local, no guardado: es lo único que lo usa, y así no hay
	# que arrastrar un parámetro más por la lista de argumentos del generador.
	var relief := FastNoiseLite.new()
	relief.seed = terrain_seed + outskirts_seed_offset
	relief.frequency = 1.0 / maxf(outskirts_feature_size, 1.0)

	# Por nodo del borde: de dónde sale, hacia dónde, hasta dónde, y a qué altura llega SU cima.
	#
	# El sorteo de las cimas se ESTIRA al rango entero, la misma corrección que `CityTerrain` le hace al
	# relieve y por la misma razón: el ruido crudo no llega a sus extremos —sobre 38 nodos se quedaba
	# entre 0,53 y 0,82—, así que sin esto `outskirts_crest_variation` promete un rango que no entrega y
	# todas las cimas salen parecidas.
	var raw := PackedFloat32Array()
	var raw_low := INF
	var raw_high := -INF
	for node_idx in ring:
		var p: Vector3 = graph.points[node_idx]
		var sample := relief.get_noise_2d(p.x, p.z)
		raw.append(sample)
		raw_low = minf(raw_low, sample)
		raw_high = maxf(raw_high, sample)
	var raw_spread := maxf(raw_high - raw_low, 0.0001)

	var bases := PackedVector3Array()
	var aways := PackedVector3Array()
	var reaches := PackedFloat32Array()
	var crests := PackedFloat32Array()
	var lowest_crest := INF
	var highest_crest := -INF
	for i in ring.size():
		var p: Vector3 = graph.points[ring[i]]
		var away := (Vector3(p.x, 0.0, p.z) - Vector3(centre.x, 0.0, centre.y)).normalized()
		if away.length_squared() < 0.5:
			away = Vector3.RIGHT
		# La cima de esta dirección. Como las formas del ruido son diez veces más largas que un tramo del
		# borde, los nodos vecinos sacan valores parecidos: salen cordones y pasos, no un peine.
		var crest: float = target * lerpf(1.0 - outskirts_crest_variation, 1.0,
			(raw[i] - raw_low) / raw_spread)
		lowest_crest = minf(lowest_crest, crest)
		highest_crest = maxf(highest_crest, crest)
		bases.append(Vector3(p.x, terrain.height_of(ring[i]), p.z))
		aways.append(away)
		reaches.append(outskirts_depth * _outskirts_reach_factor(p, away, terrain))
		crests.append(crest)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var previous := bases
	var steepest := 0.0
	var top := 0.0
	var bottom := INF
	for k in range(1, outskirts_rings + 1):
		var t := float(k) / float(outskirts_rings)
		var current := PackedVector3Array()
		for i in ring.size():
			var out_distance: float = reaches[i] * t
			var at: Vector3 = bases[i] + aways[i] * out_distance
			at.y = _outskirts_height(bases[i].y, crests[i], t, at.x, at.z, terrain, relief)
			current.append(at)
			top = maxf(top, at.y)
			bottom = minf(bottom, at.y)
			var rise := absf(at.y - previous[i].y)
			var run := maxf(reaches[i] / float(outskirts_rings), 0.001)
			steepest = maxf(steepest, rise / run)
		for i in ring.size():
			var j: int = (i + 1) % ring.size()
			# Mirando hacia arriba, como el suelo de la ciudad: es terreno, no una pared.
			_ground_quad(st, faces, previous[i], previous[j], current[j], current[i])
		previous = current
	st.generate_normals()

	var container := Node3D.new()
	container.name = "Outskirts"
	container.add_to_group("city_outskirts")
	add_child(container)

	var material := StandardMaterial3D.new()
	material.albedo_color = outskirts_color
	material.roughness = 1.0
	var view := MeshInstance3D.new()
	view.name = "mesh"
	view.mesh = st.commit()
	view.material_override = material
	# SIN límite por distancia, igual que la muralla antes: es UNA sola malla que rodea la ciudad entera,
	# así que su origen cae en el centro y "distancia a las afueras" no significa nada. Lo que evita que
	# su silueta achique el mundo es la niebla (ver CityFog).
	container.add_child(view)

	if enable_outskirts_collider:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		var body := StaticBody3D.new()
		body.name = "collider"
		body.add_child(collider)
		container.add_child(body)

	if enable_outskirts_barrier:
		container.add_child(_outskirts_barrier(previous, maxf(limit, top), bottom))

	# El techo de la nave sale de acá: se publica en metros para que no haya que repetir la cuenta. Es el
	# LÍMITE, no la cima más alta: las cimas quedan por debajo y de contener se ocupa la barrera.
	WorldSettings.impassable_height = limit
	WorldSettings.floor_height = _floor_height()
	print("[Visualizer] Afueras: %d nodos de borde%s · %d triángulos · cimas de %.0f a %.0f m (límite %.0f m, %.0f pisos) · terreno de %.0f a %.0f m · pendiente máx %.0f%%"
		% [ring.size(), "" if loose == 0 else " (%d sueltos)" % loose, faces.size() / 3,
			lowest_crest, highest_crest, limit, impassable_floors, bottom, top, steepest * 100.0])


## LA BARRERA INVISIBLE, un anillo vertical sobre la última tira. Es lo ÚNICO que contiene: la montaña
## dejó de hacerlo cuando las cimas pasaron a ser desparejas, que es justamente lo que las saca de sosas.
##
## Solo colisión, sin malla: nunca se ve, y por eso puede estar recta y lejos. Se pasa de largo por los
## dos lados —`BARRIER_SKIRT` por debajo del punto más bajo del terreno y por encima del más alto—, así
## no queda ni una hondonada por donde colarse ni un pico por el que treparla. Que sea más alta que el
## límite no le afecta a la nave: su techo sale del límite, no de acá.
const BARRIER_SKIRT := 200.0

func _outskirts_barrier(rim: PackedVector3Array, limit: float, bottom: float) -> StaticBody3D:
	var faces := PackedVector3Array()
	var top_y := limit + BARRIER_SKIRT
	var floor_y := bottom - BARRIER_SKIRT
	for i in rim.size():
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % rim.size()]
		var low_a := Vector3(a.x, floor_y, a.z)
		var low_b := Vector3(b.x, floor_y, b.z)
		var high_a := Vector3(a.x, top_y, a.z)
		var high_b := Vector3(b.x, top_y, b.z)
		# El orden no importa: un ConcavePolygonShape3D colisiona por las dos caras.
		faces.append_array([low_a, low_b, high_b, low_a, high_b, high_a])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	var body := StaticBody3D.new()
	body.name = "barrier"
	body.add_child(collider)
	return body

## REHACE SOLO LAS AFUERAS, sin tocar la ciudad. Lo usa el afinador de terreno (F7): la falda son mil y
## pico de triángulos contra los cientos de miles de la ciudad, así que se puede iterar en vivo sobre su
## forma; el relieve de la ciudad, en cambio, mueve todo lo que se apoya en él y obliga a regenerar.
##
## El nodo viejo se saca del árbol EN EL ACTO y recién después se libera: `queue_free` es diferido, y si
## no, por un cuadro habría dos afueras en el grupo.
func rebuild_outskirts() -> void:
	if generator == null or generator.plain_graph == null:
		return
	var old := get_node_or_null("Outskirts")
	if old != null:
		remove_child(old)
		old.queue_free()
	if show_outskirts:
		_visualize_outskirts()


## DÓNDE EMPIEZA EL JUGADOR: el nodo del grafo más cercano al centro de la ciudad, o sea un cruce de
## calles, elevado para no nacer dentro del suelo.
##
## Hace falta porque el grafo se genera en el PRIMER CUADRANTE, no centrado: la ciudad medida va de
## (6, 46) a (1395, 1422), así que el (0, 0, 3) que el spawner traía escrito cae AFUERA del borde. Con el
## mundo terminando en el aire eso no se notaba —se caía sobre un piso invisible de 3 km—; con afueras de
## verdad, sí.
const START_CLEARANCE := 3.0

func start_point() -> Vector3:
	if generator == null or generator.plain_graph == null:
		return Vector3.ZERO
	var graph := generator.plain_graph
	var ring := graph.boundary_ring()
	if ring.is_empty():
		return Vector3.ZERO
	var centre := Vector2.ZERO
	for node_idx in ring:
		var p: Vector3 = graph.points[node_idx]
		centre += Vector2(p.x, p.z)
	centre /= float(ring.size())

	var best := -1
	var best_distance := INF
	for i in graph.points.size():
		var p: Vector3 = graph.points[i]
		var distance := Vector2(p.x, p.z).distance_squared_to(centre)
		if distance < best_distance:
			best_distance = distance
			best = i
	if best < 0:
		return Vector3.ZERO
	var node: Vector3 = graph.points[best]
	var height := generator.terrain.height_of(best) if generator.terrain != null else 0.0
	return Vector3(node.x, height + START_CLEARANCE, node.z)


## Cuánto se estira la distancia a la cima en una dirección, alrededor de 1. Sale de muestrear el MISMO
## campo de relieve bien lejos hacia afuera: es determinista, no agrega estado, y queda descorrelacionado
## de la altura del borde —que se muestrea acá nomás—, así que la montaña cerca o lejos no acompaña al
## valle o la loma de la ciudad.
func _outskirts_reach_factor(at: Vector3, away: Vector3, terrain: CityTerrain) -> float:
	if terrain.amplitude <= 0.0:
		return 1.0
	var far := at + away * outskirts_depth
	var t := clampf(terrain.height_at(far.x, far.z) / terrain.amplitude, 0.0, 1.0)
	return lerpf(1.0 - outskirts_depth_variation, 1.0 + outskirts_depth_variation, t)

## LA ALTURA EN UN PUNTO DE LA FALDA. Son tres cosas sumadas, y cada una hace un trabajo distinto:
##
##   · EL PERFIL sube como `t²` hasta la cima de ESA dirección: arranca casi plano —lomas a la salida de
##     la ciudad, no una rampa desde la vereda— y se empina hacia arriba, que es como se lee una montaña.
##     Pasada la cima baja un poco, para que la silueta tenga espesor en vez de terminar en un filo.
##   · EL RELIEVE GRANDE, de formas de más de un kilómetro, cava valles y levanta lomos POR ENCIMA del
##     perfil. Va con signo, así que resta tanto como suma: sin él la falda es una rampa lisa y todas las
##     montañas salen iguales, que era lo que se veía soso.
##   · EL RELIEVE DE LA CIUDAD encima, el mismo campo de 300 m, como detalle fino. Dos escalas apiladas.
##
## Las dos últimas entran multiplicadas por `climb`, que vale 0 en el borde: por eso la costura con la
## ciudad sigue siendo exacta por más que las afueras se deformen.
func _outskirts_height(edge_height: float, crest: float, t: float, x: float, z: float,
		terrain: CityTerrain, relief: FastNoiseLite) -> float:
	var climb := minf(t / outskirts_crest_at, 1.0)
	var height := lerpf(edge_height, crest, pow(climb, outskirts_rise_power))
	if t > outskirts_crest_at and outskirts_crest_at < 1.0:
		var over := (t - outskirts_crest_at) / (1.0 - outskirts_crest_at)
		height -= absf(crest) * outskirts_back_drop * over
	# En valor absoluto: con la falda hundida la cima es negativa, y el relieve tiene que seguir midiendo
	# lo mismo en vez de darse vuelta o desaparecer.
	var shape := absf(crest) * outskirts_relief * relief.get_noise_2d(x, z)
	return height + (shape + terrain.height_at(x, z)) * climb


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
	if terrain == null:
		return
	# Antes esto se salteaba con relieve 0 y la ciudad se apoyaba en un piso invisible de 3 km que traía
	# la escena. Ese piso ya no existe, así que el suelo se dibuja siempre: con relieve 0 sale plano.
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
	st.generate_normals()
	container.add_child(_ground_mesh(st, ground_color, "blocks"))

	# LAS CALLES EN SU PROPIA MALLA, una para toda la ciudad, con UV en metros para el shader de asfalto que
	# viene: media calle por manzana, del cordón al eje (ver `_ground_aprons`). Todo entra en el mismo
	# collider que las manzanas.
	var streets_st := SurfaceTool.new()
	streets_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var streets := _ground_aprons(streets_st, faces)
	streets_st.generate_normals()
	container.add_child(_ground_mesh(streets_st, street_color, "streets"))

	if enable_ground_collider:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		var body := StaticBody3D.new()
		body.name = "collider"
		body.add_child(collider)
		container.add_child(body)
	print("[Visualizer] Suelo: %d triángulos · %d manzanas · %d medias calles" % [faces.size() / 3, blocks, streets])


func _ground_mesh(st: SurfaceTool, color: Color, node_name: String) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var view := MeshInstance3D.new()
	view.name = node_name
	view.mesh = st.commit()
	view.material_override = material
	return view

## LA CALLE, MEDIA POR MANZANA: cada manzana pavimenta el anillo entre su CORDÓN —el borde de su grilla, a
## la altura de la grilla, así sigue sin costura al suelo y a la vereda— y el EJE de cada calle —la arista
## del grafo, a la altura de sus nodos—: un trapecio por lado y un parche por esquina, del cordón al nodo.
## Las dos mitades de una calle se encuentran en el eje con la misma altura, así que no hay costura entre
## manzanas; y como no depende de la manzana de enfrente ni de los puntos de carril, la muestra del sandbox
## tiene su media calle sola, una calle de borde (offset 0) no tiene nada, y cambiar el ancho de veredas o
## calles no toca esto. Los huecos de las esquinas —lo que quedaba entre corredores de cordón a cordón—
## no existen: el parche de esquina va del cordón al nodo.
##
## UV en metros: `u` desde el cordón, `v` a lo largo de la arista en su sentido canónico (del nodo menor al
## mayor), igual en las dos mitades, así el asfalto corre continuo. En las esquinas, planas (x, z).
func _ground_aprons(st: SurfaceTool, faces: PackedVector3Array) -> int:
	var graph := generator.plain_graph
	var drawn := 0
	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		var grid := block.get_distorted_grid() if block != null else null
		var face: Array = graph.faces[face_idx]
		if grid == null or face.size() != 4:
			continue
		var kerb := _kerb_corners(block, grid)
		if kerb.size() != 4:
			continue
		var is_street: Array[bool] = []
		for i in 4:
			is_street.append(generator.get_street_type(face[i], face[(i + 1) % 4]) != BlockGenerator.StreetType.BOUNDARY)
		# Un trapecio por lado: del cordón al eje.
		for i in 4:
			if not is_street[i]:
				continue
			var n1: int = face[i]
			var n2: int = face[(i + 1) % 4]
			var k0 := kerb[i]
			var k1 := kerb[(i + 1) % 4]
			var p0 := _on_edge(n1, n2, k0)
			var p1 := _on_edge(n1, n2, k1)
			var uv := PackedVector2Array([Vector2(0.0, _along_edge(n1, n2, k0)),
				Vector2(k0.distance_to(p0), _along_edge(n1, n2, p0)),
				Vector2(k1.distance_to(p1), _along_edge(n1, n2, p1)),
				Vector2(0.0, _along_edge(n1, n2, k1))])
			_ground_quad(st, faces, k0, p0, p1, k1, uv)
			drawn += 1
		# Un parche por esquina: del cordón al nodo, entre las dos calles que lo tocan. Si una de las dos es
		# borde de ciudad, el cordón ya está sobre su eje y el parche es un triángulo.
		for i in 4:
			var prev := (i + 3) % 4
			if not is_street[i] and not is_street[prev]:
				continue
			var node: int = face[i]
			var n := Vector3(graph.points[node].x, generator.terrain.height_of(node), graph.points[node].z)
			var k := kerb[i]
			var pa := _on_edge(face[prev], node, k)
			var pb := _on_edge(node, face[(i + 1) % 4], k)
			_ground_quad(st, faces, k, pa, n, pb, PackedVector2Array([Vector2(k.x, k.z), Vector2(pa.x, pa.z),
				Vector2(n.x, n.z), Vector2(pb.x, pb.z)]))
		# Y lo que la esquina curva de la vereda deja como calle ADENTRO de la manzana: el cuadrado de la
		# esquina menos el cuarto de disco del cordón (ver SidewalkProps.corner_unit), llevado al mundo con la
		# MISMA bilineal con que se colocó la vereda, así los dos coinciden en el arco. Apenas levantado
		# sobre el suelo de la manzana, que sigue debajo.
		for zone: Dictionary in block.traversal.floating_sidewalk_zones:
			if int(zone["piece"]) != SidewalkProps.Piece.CURVED_CORNER or int(zone["floor"]) != 0:
				continue
			var cell: Vector2i = zone["cell"]
			var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
			if module == null:
				continue
			var lo := Vector2(float(zone["bx_min"]), float(zone["bz_min"]))
			var size := Vector2(float(zone["bx_max"]) - lo.x + 1.0, float(zone["bz_max"]) - lo.y + 1.0)
			var world := PackedVector3Array()
			var uv := PackedVector2Array()
			for p in SidewalkProps.curb_outside(int(zone["side"])):
				var w := module.cell_to_world(Vector3(lo.x + p.x * size.x, 0.0, lo.y + p.y * size.y)) \
						+ Vector3.UP * STREET_LIFT
				world.append(w)
				uv.append(Vector2(w.x, w.z))
			# En abanico desde la esquina exterior: la región se ve entera desde ahí.
			for j in range(1, world.size() - 1):
				_ground_triangle(st, faces, world[0], world[j], world[j + 1],
					PackedVector2Array([uv[0], uv[j], uv[j + 1]]))
	return drawn


## Cuánto se levanta la calle donde pisa el suelo de la manzana (la esquina curva), para no pelear con él.
const STREET_LIFT := 0.01

## Las cuatro esquinas del cordón de una manzana, en el orden de sus nodos y a la altura de la grilla: de
## las cuatro esquinas de la grilla, la más cercana a cada vértice del núcleo.
func _kerb_corners(block: BlockGenerator, grid: DistortedGrid) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(grid.columns - 1, 0),
			Vector2i(grid.columns - 1, grid.rows - 1), Vector2i(0, grid.rows - 1)]:
		var vertices: Array = grid.get_cell_vertices(cell.x, cell.y)
		if vertices.size() != 4:
			return []
		for v in vertices:
			candidates.append(v)
	var out: Array[Vector3] = []
	for core: Vector2 in block.get_core_vertices():
		var best := candidates[0]
		var best_distance := INF
		for c in candidates:
			var d := Vector2(c.x, c.z).distance_squared_to(core)
			if d < best_distance:
				best_distance = d
				best = c
		out.append(best)
	return out


## La proyección de un punto sobre el eje de la calle `n1`→`n2`, a la altura interpolada entre sus nodos.
func _on_edge(n1: int, n2: int, p: Vector3) -> Vector3:
	var graph := generator.plain_graph
	var a := graph.points[n1]
	var b := graph.points[n2]
	var d := Vector2(b.x - a.x, b.z - a.z)
	var t := 0.0
	if d.length_squared() > 0.0:
		t = clampf(Vector2(p.x - a.x, p.z - a.z).dot(d) / d.length_squared(), 0.0, 1.0)
	var terrain := generator.terrain
	return Vector3(a.x + d.x * t, lerpf(terrain.height_of(n1), terrain.height_of(n2), t), a.z + d.y * t)


## Metros a lo largo de la arista desde su nodo menor: la misma `v` para las dos mitades de la calle.
func _along_edge(n1: int, n2: int, p: Vector3) -> float:
	var graph := generator.plain_graph
	var lo: int = mini(n1, n2)
	var hi: int = maxi(n1, n2)
	var a := graph.points[lo]
	var d := Vector2(graph.points[hi].x - a.x, graph.points[hi].z - a.z)
	if d.length_squared() <= 0.0:
		return 0.0
	return Vector2(p.x - a.x, p.z - a.z).dot(d.normalized())



# Un quad del suelo, en dos triángulos que miran para arriba. Godot toma como FRENTE el lado desde el que
# las esquinas giran en sentido horario, y la normal de ese lado es (c − a) × (b − a): con el orden al
# revés el suelo se culea desde arriba y desde abajo se ve negro.
func _ground_quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uv := PackedVector2Array()) -> void:
	if uv.size() == 4:
		_ground_triangle(st, faces, a, b, c, PackedVector2Array([uv[0], uv[1], uv[2]]))
		_ground_triangle(st, faces, a, c, d, PackedVector2Array([uv[0], uv[2], uv[3]]))
	else:
		_ground_triangle(st, faces, a, b, c)
		_ground_triangle(st, faces, a, c, d)

func _ground_triangle(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3,
		uv := PackedVector2Array()) -> void:
	var ordered: Array[Vector3] = [a, b, c]
	var uvs: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	if uv.size() == 3:
		uvs = [uv[0], uv[1], uv[2]]
	if (c - a).cross(b - a).y < 0.0:
		ordered = [a, c, b]
		uvs = [uvs[0], uvs[2], uvs[1]]
	for i in 3:
		st.set_uv(uvs[i])
		st.add_vertex(ordered[i])
	faces.append_array(PackedVector3Array(ordered))

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
	var raw_walls := 0
	var lost_openings := 0
	var started := Time.get_ticks_msec()
	var buildings := _buildings_container("Buildings")
	# LAS DOS MALLAS DE CADA EDIFICIO —la final y la debug, ver BuildingShell— cuelgan de dos nodos hermanos,
	# y la vista prende uno y apaga el otro (`_apply_view`): un `visible` por vista, no uno por edificio. Los
	# dos viven bajo el contenedor de edificios, que es lo que apagan los toggles de performance.
	_final_buildings = Node3D.new()
	_final_buildings.name = "Final"
	buildings.add_child(_final_buildings)
	_debug_buildings = Node3D.new()
	_debug_buildings.name = "Debug"
	buildings.add_child(_debug_buildings)

	for face_idx in all_block_faces:
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or block.get_distorted_grid() == null:
			continue

		var cells_per_floor := block.get_cells_per_floor()
		var clusters := block.get_all_clusters()
		total_clusters += clusters.size()

		for cluster in clusters:
			var cluster_floors := cluster.get_floor_count()

			# Un scope por edificio: el rayo que pegue en su collider solo va a buscar entre SUS piezas.
			var scope := city_index.new_scope()
			_scope_by_cluster[cluster] = scope
			var object_id := _object_for_cluster(cluster)
			var shell := BuildingShell.new(cluster.color if _spotlit(cluster) else GHOST_COLOR)
			var pieces: Array[Dictionary] = []

			for floor_idx in range(cluster_floors):
				for cell in cluster.cells:
					var module: BuildingModule = block.get_building_module(cell.x, cell.y, floor_idx)
					if module == null:
						continue
					# Las tapas van solo contra el aire: abajo en el piso 0, arriba en el último. Si algún
					# día un piso tuviera otro módulo que el de al lado (ver
					# BuildingCluster.building_modules), el objeto sería otro y la tapa entre los dos
					# volvería sola.
					var below: BuildingModule = null
					if floor_idx > 0:
						below = block.get_building_module(cell.x, cell.y, floor_idx - 1)
					var above: BuildingModule = null
					if floor_idx + 1 < cluster_floors:
						above = block.get_building_module(cell.x, cell.y, floor_idx + 1)
					var piece := shell.add_floor(module, cells_per_floor, floor_idx, cell,
						below != module, above != module, cluster.debug_color)
					if piece.is_empty():
						continue
					piece["cell"] = cell
					piece["floor"] = floor_idx
					pieces.append(piece)
					total_cells += 1

			if shell.is_empty():
				continue
			# Las aberturas se cortan con la piel ya armada: sus planos existen.
			shell.skin.wall_thickness = cluster.archetype.wall_thickness_m
			var hollow: bool = cluster.archetype.hollow
			shell.skin.hollow = hollow
			if _openings.has(cluster):
				var record: Dictionary = _openings[cluster]
				var quads: PackedVector3Array = record["quads"]
				for k in record["arch"].size():
					var quad: Array[Vector3] = [quads[k * 4], quads[k * 4 + 1], quads[k * 4 + 2], quads[k * 4 + 3]]
					shell.skin.add_opening(quad, record["outward"][k], record["arch"][k], record["segments"][k])
			# LA IDENTIDAD SE ANOTA cuando la cáscara está completa: las tapas van en su segunda superficie,
			# y su rango en el espacio de `Mesh.get_faces` —el del collider— empieza donde terminan las
			# paredes. Una pieza con tapa son dos registros con los mismos ids.
			var caps_offset := shell.wall_index_count()
			var shell_mesh := shell.debug_mesh()
			_shell_mesh_by_cluster[cluster] = shell_mesh
			var final_mesh := shell.skin.build()
			raw_walls += shell.skin.raw_walls
			lost_openings += shell.skin.lost_openings
			if hollow:
				# Un edificio hueco se pisa por dentro: su collider es la piel, y su identidad una sola pieza
				# sobre ella —la piel no sabe de celdas ni de pisos—.
				_skin_mesh_by_cluster[cluster] = final_mesh
				if final_mesh.get_surface_count() > 0:
					city_index.add(scope, object_id, CityIndex.Kind.BUILDING, cluster.id, -1, -1, -1, 0,
						final_mesh.surface_get_array_index_len(0), final_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			else:
				for piece in pieces:
					var cell: Vector2i = piece["cell"]
					var walls: Vector2i = piece["walls"]
					var caps: Vector2i = piece["caps"]
					city_index.add(scope, object_id, CityIndex.Kind.BUILDING, cluster.id, cell.x, cell.y,
						piece["floor"], walls.x, walls.y, piece["vertices"])
					if caps.y > caps.x:
						city_index.add(scope, object_id, CityIndex.Kind.BUILDING, cluster.id, cell.x, cell.y,
							piece["floor"], caps_offset + caps.x, caps_offset + caps.y, piece["vertices"])
			if not show_buildings:
				continue

			var debug_instance := MeshInstance3D.new()
			debug_instance.mesh = shell_mesh
			debug_instance.material_override = _get_debug_material()
			debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_debug_buildings.add_child(debug_instance)

			var final_instance := MeshInstance3D.new()
			final_instance.mesh = final_mesh
			final_instance.material_override = _get_building_material() if _spotlit(cluster) \
					else _get_ghost_material()
			final_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if not hollow:  # un hueco se ve por dentro: nada que tapar con una caja
				_add_box_occluder(final_mesh, buildings)
			_final_buildings.add_child(final_instance)
			# El índice copia los triángulos de la malla que dio el collider, se vea o no: sus rangos son los
			# de ella. La semántica, salvo en los huecos, donde es la piel.
			city_index.set_scope_mesh(scope, final_instance if hollow else debug_instance)

	print("[Visualizer] Buildings: %d clusters (%d cells total) en %d bloques · paredes fuera de marco: %d · aberturas perdidas: %d · en %d ms"
		% [total_clusters, total_cells, all_block_faces.size(), raw_walls, lost_openings, Time.get_ticks_msec() - started])

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

		var clusters = block.get_all_clusters()

		for cluster in clusters:
			# LOS MISMOS TRIÁNGULOS QUE LA MALLA SEMÁNTICA, literalmente: el collider se lee de ella, y por
			# eso el `face_index` del rayo cae en los rangos que el índice anotó (ver BuildingShell). En un
			# edificio hueco, de la piel: es lo que se pisa por dentro, con el hueco del portón.
			var mesh: ArrayMesh = _skin_mesh_by_cluster.get(cluster, _shell_mesh_by_cluster.get(cluster))
			if mesh == null:
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(mesh.get_faces())
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
		var buffer := GridPlacer.new_buffer()
		# Un scope por MANZANA, porque los techos se fusionan en una malla por manzana (los edificios, en
		# cambio, tienen una malla cada uno). La granularidad del scope sigue a la de la malla.
		var scope := city_index.new_scope()

		for cluster in block.get_all_clusters():
			if cluster.get_floor_count() <= 0 or cluster.cells.is_empty() or not _spotlit(cluster):
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

			# TODO SE COLOCA POR LA MISMA INTERFAZ que cualquier otro objeto (ver GridPlacer): el
			# planner solo dice qué pieza va en qué región, y el placer deforma, anota en el índice y ocupa.
			var placer := GridPlacer.new(city_index, scope, object_id, buffer)

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
				# EL TANQUE ES UNA ENTIDAD: free placement sobre el quad de la azotea (ver FreePlacement), sin
				# deformarse —en la matriz rígida se torcía con la silla del techo—. Lo que el módulo ya tiene
				# ocupado a la altura de la azotea se proyecta como huella; si el tanque no entra con su margen
				# —azotea angosta o tapada— no se pone, y ese es todo el filtro.
				var roof := FreePlacement.new(tank_module.get_core_vertices(roof_index), TANK_MARGIN_M)
				for corners: PackedVector3Array in tank_module.occupied_world_corners(roof_index - 1,
						roof_index + cells_per_floor * 4):
					roof.block_points(corners)
				var diameter := RoofProps.TANK_DIAMETER_M
				var footprint := Rect2((roof.size.x - diameter) * 0.5, (roof.size.y - diameter) * 0.5,
					diameter, diameter)
				if roof.place(footprint):
					_place_entity(container, RoofProps.water_tank_unit(),
						Vector3(diameter, RoofProps.tank_height_m(), diameter), roof.frame_at(footprint),
						object_id, CityIndex.Kind.ROOF, cluster.id, RoofPlanner.Piece.TANK, -1, -1)
					tanks += 1

		if _bake_placed(container, buffer, scope, true):
			roof_bodies += 1

	print("[Visualizer] Objetos de techo: %d edificios con techo inclinado · %d tanques · %d colliders · piezas rechazadas: %d · planos por no cerrar: %s"
		% [roofs, tanks, roof_bodies, roof_rejected, str(roof_fallbacks)])


## HORNEA UN BUFFER DE PIEZAS COLOCADAS (techos, veredas, puertas, ventanas): una malla con el material de
## colores por vértice y, si `collider`, un collider de triángulos con LOS MISMOS triángulos en EL MISMO orden
## que la malla —el contrato del que depende traducir el `face_index` del rayo a una pieza (ver CityIndex)—,
## estampado con el scope. Devuelve false si el buffer estaba vacío y no se creó nada.
func _bake_placed(container: Node3D, buffer: Dictionary, scope: int, shadows: bool, collider: bool = true) -> bool:
	if buffer["vertices"].is_empty():
		return false
	var mesh_instance := GridPlacer.bake_mesh(buffer, _get_building_material(), shadows)
	container.add_child(mesh_instance)
	city_index.set_scope_mesh(scope, mesh_instance)
	if not collider:
		return true

	var faces := PackedVector3Array()
	var verts: PackedVector3Array = buffer["vertices"]
	for idx: int in buffer["indices"]:
		faces.append(verts[idx])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	var body := StaticBody3D.new()
	body.add_child(collision_shape)
	body.set_meta(CityIndex.SCOPE_META, scope)
	container.add_child(body)
	return true

# ============================================
# OBJETOS DE FACHADA: PUERTAS Y VENTANAS
# ============================================

## TODO LO RÍGIDO QUE VA EN UNA PARED, en una sola pasada por manzana y con UNA MATRIZ POR FACHADA (módulo,
## lado, piso) compartida por todos: una ventana solo puede esquivar una puerta si lee la misma matriz donde
## la puerta quedó ocupando.
##
## El orden es de prioridad: primero las puertas, que son de gameplay; después las ventanas, que rodean lo que
## ya hay. Las dos leen además lo deformable que el módulo ya tiene delante (veredas, extremos de puente).
func _visualize_facade_objects() -> void:
	var started := Time.get_ticks_msec()
	var doors := {"total": 0, "raised": 0, "slid": 0, "dropped": 0}
	var windows := {"total": 0, "rejected": 0, "faces": 0}
	var door_container := _buildings_container("Doors")
	var window_container := _buildings_container("Windows")
	var window_triangles := 0

	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or block.get_distorted_grid() == null:
			continue
		var surfaces := {}
		if show_delivery_doors:
			var door_buffer := GridPlacer.new_buffer()
			var door_scope := city_index.new_scope()
			_place_delivery_doors(block, surfaces, door_buffer, door_scope, doors)
			_bake_placed(door_container, door_buffer, door_scope, true)
		if show_windows:
			var window_buffer := GridPlacer.new_buffer()
			var window_scope := city_index.new_scope()
			_place_windows(block, surfaces, window_buffer, window_scope, windows)
			window_triangles += window_buffer["indices"].size() / 3
			# Sin collider y sin sombra: son cientos de miles y están a centímetros de la pared.
			_bake_placed(window_container, window_buffer, window_scope, false, false)

	if show_delivery_doors:
		print("[Visualizer] Puertas de entrega: %d · apoyadas sobre la vereda: %d · corridas: %d · sin lugar: %d"
			% [doors["total"], doors["raised"], doors["slid"], doors["dropped"]])
	if show_windows:
		print("[Visualizer] Ventanas: %d en %d fachadas · %d triángulos · candidatas que no entraron: %d"
			% [windows["total"], windows["faces"], window_triangles, windows["rejected"]])
	print("[Visualizer] Objetos de fachada en %d ms" % (Time.get_ticks_msec() - started))


## Lo que una pieza colocada deja en la pared: su cara sobre la superficie, para que la piel la corte (ver
## BuildingSkin.add_opening y `_openings`).
func _record_opening(cluster: BuildingCluster, facade: RigidMatrix, lo: Vector3i, size: Vector3i,
		arch_height_m: float, arch_segments: int) -> void:
	# Arrays empaquetados y no un diccionario por abertura: son cientos de miles.
	if not _openings.has(cluster):
		_openings[cluster] = {"quads": PackedVector3Array(), "outward": PackedVector3Array(),
			"arch": PackedFloat32Array(), "segments": PackedInt32Array()}
	var record: Dictionary = _openings[cluster]
	record["quads"].append_array(SampleWall.opening_quad(facade, lo, size))
	record["outward"].append(facade.axis_n)
	record["arch"].append(arch_height_m)
	record["segments"].append(arch_segments)


## La matriz de una pared —fachada o chaflán, ver BuildingModule.Wall— de un piso, armada la primera vez
## que alguien la pide en esta manzana.
##
## Solo la del PISO 0 se calcula desde el quad (se guarda con la clave de piso -1); la de cualquier otro
## piso es esa misma trasladada en Y (`RigidMatrix.translated`) con la ocupación de SU altura marcada.
func _wall_surface_cached(surfaces: Dictionary, module: BuildingModule, cell: Vector2i,
		wall: BuildingModule.Wall, floor_idx: int, cells_per_floor: int) -> RigidMatrix:
	var key := Vector4i(cell.x, cell.y, wall.slot(), floor_idx)
	if surfaces.has(key):
		return surfaces[key]
	var frame_key := Vector4i(cell.x, cell.y, wall.slot(), -1)
	if not surfaces.has(frame_key):
		surfaces[frame_key] = RigidMatrix.of_wall(module, wall, cells_per_floor)
	var frame: RigidMatrix = surfaces[frame_key]
	var floor_base := floor_idx * cells_per_floor
	var surface := frame.translated(Vector3(0.0, float(floor_base) * module.cell_height, 0.0))
	if surface.is_valid():
		for corners: PackedVector3Array in module.occupied_world_corners(floor_base, floor_base + cells_per_floor):
			surface.mark_world_hexahedron(corners)
	surfaces[key] = surface
	return surface


## LAS PUERTAS SON RÍGIDAS: van en la matriz de su fachada, sin deformarse, y leen lo que la matriz
## deformable ya puso delante de esa pared. Es el caso que motivó el sistema entero: antes la puerta se
## dibujaba desde el piso y la vereda —deformable, y dibujada después— la atravesaba. Ahora la vereda ocupa
## primero, la matriz de la fachada la ve, y la puerta SE APOYA sobre ella (`first_free_along_z`). Si lo
## que estorba es más alto que un escalón, la puerta no va, y se cuenta.
func _place_delivery_doors(block: BlockGenerator, surfaces: Dictionary, buffer: Dictionary, scope: int,
		stats: Dictionary) -> void:
	var cells_per_floor := block.get_cells_per_floor()
	var number := 0
	for door: Dictionary in block.traversal.delivery_doors:
		var cell: Vector2i = door["cell"]
		var edge_idx: int = door["edge"]
		var floor_idx: int = door["floor"]
		var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
		var cluster: BuildingCluster = block.get_cluster_for_cell(cell.x, cell.y)
		if module == null or cluster == null or not _spotlit(cluster):
			continue
		# Un portón no es una pieza en la pared sino un nodo que sube (ver Gate): ocupa su abertura sin
		# hornear nada, y hay uno solo por edificio.
		var moving: bool = cluster.door.moving
		if moving and _gates.has(cluster):
			continue
		number += 1
		var floor_base := floor_idx * cells_per_floor
		var facade := _wall_surface_cached(surfaces, module, cell, BuildingModule.Wall.facade(edge_idx),
			floor_idx, cells_per_floor)
		if not facade.is_valid():
			stats["dropped"] += 1
			continue

		# En el marco de una fachada `y` sale hacia la calle y `z` sube (ver RigidMatrix).
		# La puerta de ESTE edificio (ver DoorArchetype). El tramo se sorteó para la puerta estándar
		# (TraversalGenerator.DOOR_WIDTH_M); si esta es más ancha, abajo se corre hasta entrar.
		var size := facade.cells_for(cluster.door.width_m, cluster.door.depth_m, cluster.door.height_m)
		if size.x > facade.count.x:
			stats["dropped"] += 1
			continue
		# Dónde cae el tramo `along_min..along_max` sobre la matriz: por el mundo, la única coordenada que las
		# dos grillas comparten. Si cae en lo que la matriz no cubre —la esquina ochavada, el sesgo del quad—
		# se corre hasta entrar; nunca se achica.
		var u_a := facade.world_to_cell(module.facade_point(edge_idx, int(door["along_min"]), floor_base)).x
		var u_b := facade.world_to_cell(module.facade_point(edge_idx, int(door["along_max"]) + 1, floor_base)).x
		var u := roundi(minf(u_a, u_b))
		var u_in := clampi(u, 0, facade.count.x - size.x)
		if u_in != u:
			stats["slid"] += 1
		var lo := Vector3i(u_in, 0, 0)
		var max_rise := ceili(TraversalGenerator.DOOR_MAX_STEP_M / facade.cell.z)
		var sink := floori(cluster.archetype.wall_thickness_m / facade.cell.y)
		var row := facade.first_free_along_z(lo, size, max_rise)
		if row < 0:
			stats["dropped"] += 1
			continue
		if row > 0:
			stats["raised"] += 1
		lo.z = row
		var placer := GridPlacer.new(city_index, scope, _object_for_cluster(cluster), buffer)
		if placer.place(facade, lo, size, UnitMesh.new() if moving else cluster.door.unit(), CityIndex.Kind.DOOR,
				cluster.id, floor_idx, edge_idx, number, sink):
			stats["total"] += 1
			_record_opening(cluster, facade, lo, size, cluster.door.arch_height_m, cluster.door.arch_segments)
			if moving:
				_gates[cluster] = Gate.build(_buildings_container("Gates"), "gate_%d" % _object_for_cluster(cluster),
					SampleWall.opening_quad(facade, lo, size), facade.axis_n, cluster.archetype.wall_thickness_m)
		else:
			stats["dropped"] += 1


## LAS VENTANAS: cada fachada con pared a la vista de cada piso de cada edificio pide sus candidatas al
## planner según el criterio de su arquetipo, y se colocan las que entren. Las que chocan con una puerta,
## una vereda, un puente u otra ventana las descarta la matriz, no esta función.
func _place_windows(block: BlockGenerator, surfaces: Dictionary, buffer: Dictionary, scope: int,
		stats: Dictionary) -> void:
	var cells_per_floor := block.get_cells_per_floor()
	for cluster in block.get_all_clusters():
		var archetype: BuildingArchetype = cluster.archetype
		if cluster.floor_count <= 0 or archetype == null or not _spotlit(cluster):
			continue
		var placer := GridPlacer.new(city_index, scope, _object_for_cluster(cluster), buffer)
		for cell: Vector2i in cluster.cells:
			var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
			if module == null:
				continue
			for side in 4:
				for floor_idx in cluster.floor_count:
					if not FacadePlanner.has_wall(block, cluster, cell, module, side, floor_idx):
						continue
					var facade := _wall_surface_cached(surfaces, module, cell, BuildingModule.Wall.facade(side),
						floor_idx, cells_per_floor)
					if not facade.is_valid():
						continue
					stats["faces"] += 1
					# Del seed de la manzana y de la fachada: la misma ciudad en todos los peers.
					var rng := RandomNumberGenerator.new()
					rng.seed = hash([block.cluster_seed, cluster.id, cell, side, floor_idx])
					var size := FacadePlanner.window_size(cluster.window, facade)
					var positions := FacadePlanner.window_positions(archetype, facade, size, rng)
					var sink := floori(archetype.wall_thickness_m / facade.cell.y) if window_openings else 0
					for lo: Vector3i in positions:
						if placer.place(facade, lo, size, cluster.window.unit(), CityIndex.Kind.WINDOW, cluster.id,
								floor_idx, side, archetype.window_layout, sink):
							stats["total"] += 1
							if window_openings:
								_record_opening(cluster, facade, lo, size, cluster.window.arch_height_m,
									cluster.window.arch_segments)
						else:
							stats["rejected"] += 1


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

var _bridge_material: StandardMaterial3D = null

func _get_bridge_material() -> StandardMaterial3D:
	if _bridge_material == null:
		_bridge_material = StandardMaterial3D.new()
		_bridge_material.vertex_color_use_as_albedo = true
		_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_bridge_material.cull_mode = BaseMaterial3D.CULL_BACK
		_bridge_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return _bridge_material

## Hoy es inerte: occlusion culling esta apagado en project.godot
## (`rendering/occlusion_culling/use_occlusion_culling`). Se centra en el AABB de la malla porque la malla
## esta en coordenadas de mundo con el origen en la esquina de la ciudad —ver technical/city-generation.md,
## "Meshes are built in world space"—.
func _add_box_occluder(mesh: ArrayMesh, parent: Node3D) -> void:
	var aabb := mesh.get_aabb()
	var occ_inst := OccluderInstance3D.new()
	var box_occ := BoxOccluder3D.new()
	box_occ.size = aabb.size
	occ_inst.occluder = box_occ
	occ_inst.position = aabb.get_center()
	parent.add_child(occ_inst)

## Margen del tanque al borde de la azotea y a lo que ya haya en ella.
const TANK_MARGIN_M := 0.4

## UNA ENTIDAD COLOCADA: la pieza entera en un transform (ver FreePlacement), con su collider y anotada en el
## índice con scope propio, así el inspector la nombra como a cualquier pieza.
func _place_entity(container: Node3D, unit: UnitMesh, size: Vector3, xf: Transform3D, object_id: int,
		kind: int, id_a: int, id_b: int, id_c: int, id_d: int) -> void:
	var mesh := unit.build_mesh(size)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _get_building_material()
	instance.transform = xf
	container.add_child(instance)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shape)
	instance.add_child(body)
	var scope := city_index.new_scope()
	body.set_meta(CityIndex.SCOPE_META, scope)
	city_index.set_scope_mesh(scope, instance)
	var arrays := mesh.surface_get_arrays(0)
	var world := PackedVector3Array()
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		world.append(xf * v)
	city_index.add(scope, object_id, kind, id_a, id_b, id_c, id_d, 0, arrays[Mesh.ARRAY_INDEX].size(), world)


# ============================================
# AUTOS ESTACIONADOS (free placement)
# ============================================
## LA FRANJA DE CORDÓN de cada lado de manzana que da a una calle es un free placement (ver FreePlacement):
## del cordón hacia la calle, `ParkedCar.STRIP_M` de ancho, a lo largo de la fachada. Se la recorre por
## semilla dejando huecos, con los tipos de auto del distrito (los mismos pesos que el tráfico) y sin
## estacionar delante de una puerta de entrega. Cada auto es un cuerpo pasivo empujable (ver ParkedCar,
## PassiveBodies). Sin colliders de ciudad —la muestra escalada del sandbox— salen como cajas.
const PARKING_FILL := 0.45
const PARKING_GAP_M := Vector2(0.8, 3.0)
const PARKING_MARGIN_M := 0.3
const DOOR_CLEARANCE_M := 1.0
## Cuánto queda libre en cada esquina de la manzana: nadie estaciona sobre la ochava.
const CORNER_CLEARANCE_M := 6.0

func _visualize_parked_cars() -> void:
	var physical := enable_building_colliders
	var container: Node3D = PassiveBodies.new() if physical else Node3D.new()
	container.name = "ParkedCars"
	add_child(container)
	var terrain := generator.terrain
	var total := 0
	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or terrain == null:
			continue
		var face: Array = generator.plain_graph.faces[face_idx]
		var corners := block.get_core_vertices()
		if corners.size() != 4 or face.size() != 4:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = block.cluster_seed + 9311
		var weights := NeighborhoodTypes.get_car_weights(block.neighborhood_type)
		var centre := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
		for edge_idx in 4:
			var node_a: int = face[edge_idx]
			var node_b: int = face[(edge_idx + 1) % 4]
			if generator.get_street_type(node_a, node_b) == BlockGenerator.StreetType.BOUNDARY:
				continue
			var a2 := corners[edge_idx]
			var b2 := corners[(edge_idx + 1) % 4]
			var along := (b2 - a2).normalized()
			var out2 := Vector2(-along.y, along.x)
			if out2.dot(a2 - centre) < 0.0:
				out2 = -out2
			var out3 := Vector3(out2.x, 0.0, out2.y) * ParkedCar.STRIP_M
			var a := Vector3(a2.x, terrain.height_of(node_a), a2.y)
			var b := Vector3(b2.x, terrain.height_of(node_b), b2.y)
			var strip := FreePlacement.new([a, b, b + out3, a + out3], PARKING_MARGIN_M)
			parking_strips.append(PackedVector3Array([a, b]))
			# Delante de una puerta no estaciona nadie.
			for door: Dictionary in block.traversal.delivery_doors:
				if int(door["edge"]) != edge_idx:
					continue
				var cell: Vector2i = door["cell"]
				var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
				if module == null:
					continue
				strip.block_span(module.facade_point(edge_idx, int(door["along_min"]), 0),
					module.facade_point(edge_idx, int(door["along_max"]) + 1, 0), DOOR_CLEARANCE_M)
			var u := CORNER_CLEARANCE_M + rng.randf_range(0.0, PARKING_GAP_M.y)
			while u < strip.size.x - CORNER_CLEARANCE_M:
				var type := CarArchetypes.select_type_seeded(rng, weights)
				var archetype := CarArchetypes.get_archetype(type)
				if u + archetype.depth > strip.size.x - CORNER_CLEARANCE_M:
					break
				if archetype.width <= ParkedCar.STRIP_M - PARKING_MARGIN_M * 2.0 and rng.randf() < PARKING_FILL:
					var footprint := Rect2(u, (ParkedCar.STRIP_M - archetype.width) * 0.5, archetype.depth, archetype.width)
					if strip.place(footprint):
						var car := ParkedCar.create(type, physical)
						car.transform = strip.frame_at(footprint)
						container.add_child(car)
						if physical:
							(container as PassiveBodies).register(car as RigidBody3D)
						total += 1
				u += archetype.depth + rng.randf_range(PARKING_GAP_M.x, PARKING_GAP_M.y)
	print("[Visualizer] Autos estacionados: %d" % total)


# ============================================
# CAJAS DE LO COLOCADO (vista debug)
# ============================================
## LA REGIÓN EXACTA QUE OCUPA CADA OBJETO COLOCADO, como caja translúcida: rojas las de la grilla deformable
## (techos, veredas, extremos de puente), verdes las de las rígidas (puertas, ventanas, tanques). Una
## MultiMesh por clase con un cubo unitario por instancia, llevado al mundo con el MISMO marco bilineal que
## el placer usó para la pieza (ver CityIndex.add_region y Shaders/placement_box.gdshader): no es una caja
## afín parecida, es la región, con la curvatura de su grilla. Las prende la vista (`_apply_view`).
func _visualize_placement_boxes() -> void:
	var parent := _buildings_container("PlacementBoxes")
	var cube := _unit_box_mesh()
	_deformable_boxes = _placement_boxes(parent, "Deformable", cube, city_index.deformable_regions,
		DEFORMABLE_BOX_TINT)
	_rigid_boxes = _placement_boxes(parent, "Rigid", cube, city_index.rigid_regions, RIGID_BOX_TINT)
	print("[Visualizer] Cajas de lo colocado: %d deformables · %d rígidas"
		% [_deformable_boxes.multimesh.instance_count, _rigid_boxes.multimesh.instance_count])


func _placement_boxes(parent: Node3D, node_name: String, cube: Mesh, frames: PackedVector3Array,
		tint: Color) -> MultiMeshInstance3D:
	var count := frames.size() / 5
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = cube
	multimesh.instance_count = count
	for i in count:
		var at := i * 5
		# El marco de la región (ver PlacementGrid.region_frame): origen y derivadas en x, z y y, y el
		# término cruzado, que una transformación no puede llevar y va como dato de la instancia.
		multimesh.set_instance_transform(i,
			Transform3D(Basis(frames[at + 1], frames[at + 4], frames[at + 2]), frames[at]))
		var dxz := frames[at + 3]
		multimesh.set_instance_custom_data(i, Color(dxz.x, dxz.y, dxz.z, 0.0))
	var material := ShaderMaterial.new()
	material.shader = PLACEMENT_BOX_SHADER
	material.set_shader_parameter("tint", tint)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	parent.add_child(instance)
	return instance


## Un cubo unitario [0, 1]³ con las caras hacia afuera según la convención del proyecto (ver
## technical/city-generation.md, "Mesh generation"): la mesh de las instancias de las cajas.
func _unit_box_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	for corner in 8:
		verts.append(Vector3(1.0 if corner & 1 else 0.0, 1.0 if corner & 2 else 0.0, 1.0 if corner & 4 else 0.0))
	var centre := Vector3(0.5, 0.5, 0.5)
	var indices := PackedInt32Array()
	# Cada cara por los bits de sus esquinas (1 → x, 2 → y, 4 → z), en orden cíclico.
	for face: Array in [[0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 3, 2], [4, 5, 7, 6]]:
		var a: Vector3 = verts[face[0]]
		var b: Vector3 = verts[face[1]]
		var c: Vector3 = verts[face[2]]
		var d: Vector3 = verts[face[3]]
		# Para el orden (a, b, c) la cara visible tiene normal (c - a) x (b - a): si mira al centro, se
		# invierte.
		var order: Array[int] = [0, 1, 2, 0, 2, 3]
		if (c - a).cross(b - a).dot((a + b + c + d) * 0.25 - centre) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k in order:
			indices.append(face[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _bridge_geo_append(buf: Dictionary, geo: Dictionary, color: Color) -> void:
	if geo.is_empty():
		return
	var offset: int = buf["vertices"].size()
	buf["vertices"].append_array(geo.vertices)
	buf["normals"].append_array(geo.normals)
	for _i in geo.vertices.size():
		buf["colors"].append(color)
	for idx: int in geo.indices:
		buf["indices"].append(idx + offset)


## LAS VEREDAS SON DEFORMABLES y van por `GridPlacer`: se estiran con la grilla, coinciden exactas con la
## del módulo vecino, quedan en el índice y —lo que importa para todo lo demás— OCUPAN el módulo, así la
## matriz rígida de la fachada las ve y una puerta se apoya en ellas en vez de atravesarlas.
func _visualize_floating_sidewalk_zones() -> void:
	var container := _buildings_container("Sidewalks")
	var total := 0
	## Zonas que no entraron por solaparse con otra: las zonas se generan disjuntas, así que esto es un bug.
	var rejected := 0
	# Una mesh por (pieza, orientación), armada la primera vez que hace falta.
	var meshes := {}

	for face_idx in generator.get_all_block_faces():
		var block: BlockGenerator = generator.get_block_grid(face_idx)
		if block == null or block.get_distorted_grid() == null:
			continue
		var cells_per_floor := block.get_cells_per_floor()
		var buffer := GridPlacer.new_buffer()
		var scope := city_index.new_scope()

		for sw: Dictionary in block.traversal.floating_sidewalk_zones:
			var cell: Vector2i = sw["cell"]
			var floor_idx: int = sw["floor"]
			var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
			var cluster: BuildingCluster = block.get_cluster_for_cell(cell.x, cell.y)
			if module == null or cluster == null:
				continue
			# Una celda de edificio de espesor, apoyada en el arranque del piso.
			var lo := Vector3i(int(sw["bx_min"]), floor_idx * cells_per_floor, int(sw["bz_min"]))
			var size := Vector3i(int(sw["bx_max"]) - lo.x + 1, 1, int(sw["bz_max"]) - lo.z + 1)
			var piece: int = sw["piece"]
			var side: int = sw["side"]
			var key := Vector2i(piece, side)
			if not meshes.has(key):
				meshes[key] = SidewalkProps.unit_for(piece, side, sidewalk_color)
			var mesh: UnitMesh = meshes[key]
			var placer := GridPlacer.new(city_index, scope, _object_for_cluster(cluster), buffer)
			if placer.place(module, lo, size, mesh, CityIndex.Kind.SIDEWALK, cluster.id, floor_idx,
					side, piece):
				total += 1
			else:
				rejected += 1

		_bake_placed(container, buffer, scope, false)

	print("[Visualizer] Veredas: %d · rechazadas por solaparse: %d" % [total, rejected])


# ============================================
# VISUALIZACIÓN DE PUENTES
# ============================================

func _visualize_bridges() -> void:
	var total := 0
	_bridge_extremes_rejected = 0
	for edge_key in generator.bridges:
		for placed in generator.bridges[edge_key]:
			var buf := GridPlacer.new_buffer()
			var scope := city_index.new_scope()
			var object_id := _new_object()
			total += 1
			# Los extremos se colocan por el placer con el scope y el objeto del puente: son parte de él.
			var placer := GridPlacer.new(city_index, scope, object_id, buf)
			_draw_bridge(placed, buf, placer, total)
			if buf["vertices"].is_empty():
				continue
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = buf["vertices"]
			arrays[Mesh.ARRAY_NORMAL] = buf["normals"]
			arrays[Mesh.ARRAY_COLOR]  = buf["colors"]
			arrays[Mesh.ARRAY_INDEX]  = buf["indices"]
			var array_mesh := ArrayMesh.new()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = array_mesh
			mi.material_override = _get_bridge_material()
			add_child(mi)

			# El conector entero es UNA pieza por ahora: alcanza para decir cuál es. Partirlo en base,
			# pasarela, baranda y arcos es anotar un registro por tramo dentro de `_draw_bridge`. Los
			# extremos ya son piezas propias (los anota el placer) y ganan por ser cajas más chicas.
			var bridge_idxs: PackedInt32Array = buf["indices"]
			var bridge_verts: PackedVector3Array = buf["vertices"]
			city_index.set_scope_mesh(scope, mi)
			city_index.add(scope, object_id, CityIndex.Kind.BRIDGE, total, int(placed["face_a"]),
				int(placed["face_b"]), int(placed["floor_idx"]), 0, bridge_idxs.size(), bridge_verts)
			var bridge_body: Object = buf.get("body")
			if bridge_body is StaticBody3D:
				(bridge_body as StaticBody3D).set_meta(CityIndex.SCOPE_META, scope)
	print("[Visualizer] Puentes: %d · extremos sin lugar en la fachada: %d" % [total, _bridge_extremes_rejected])


## Extremos de puente que el placer rechazó por caer sobre algo ya colocado. Cualquier número es un caso a
## mirar: dos puentes en el mismo lugar de una fachada.
var _bridge_extremes_rejected := 0


func _draw_bridge(placed: Dictionary, buf: Dictionary, placer: GridPlacer, number: int) -> void:
	var bridge: Bridge     = placed["bridge"]
	var cell_start: int    = placed["cell_start"]
	var cell_end: int      = placed["cell_end"]
	var floor_idx: int     = placed["floor_idx"]
	var cell_height: float = placed["cell_height"]
	var cells_per_floor: int = placed["cells_per_floor"]
	var by_base: int = floor_idx * cells_per_floor - bridge.base_height
	var by_base_top: int = floor_idx * cells_per_floor
	var by_arc_bot: int = by_base - bridge.arc_height

	var sides := FacadeHelper.bridge_sides(placed)
	var side_a: Dictionary = sides[0]
	var side_b: Dictionary = sides[1]

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
				by_base, by_base_top, by_arc_bot, static_body, buf, placer,
				[number, int(placed["face_a"]), int(placed["face_b"]), floor_idx])

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
	# Las mismas caras que lee el planificador de altura de los autos (ver FacadeHelper.span_faces).
	var faces := FacadeHelper.span_faces(block_a, block_b, side_a, side_b, cell_start, cell_end,
			index_bottom, index_top)
	if faces.is_empty():
		return
	var plane_a: Array[Vector3] = faces[0]
	var plane_b: Array[Vector3] = faces[1]
	_bridge_geo_append(buf, DebugUtil.get_skewed_cube_from_planes_geometry(plane_a, plane_b), color)
	if static_body:
		static_body.add_child(DebugUtil.create_collision_shape_from_planes(plane_a, plane_b))


## Los arcos: dos trozos cortos pegados a cada punta, entre las mismas dos caras reales.
func _add_bridge_arc_spans(block_a: BlockGenerator, block_b: BlockGenerator,
		side_a: Dictionary, side_b: Dictionary, cell_start: int, cell_end: int,
		index_bottom: int, index_top: int,
		arc_world_depth: float, static_body: StaticBody3D, buf: Dictionary) -> void:
	var faces := FacadeHelper.span_faces(block_a, block_b, side_a, side_b, cell_start, cell_end,
			index_bottom, index_top)
	if faces.is_empty():
		return
	var plane_a: Array[Vector3] = faces[0]
	var plane_b: Array[Vector3] = faces[1]

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


## EL EXTREMO ES DEFORMABLE y va por `GridPlacer`: una región de celdas del módulo entre el índice de
## abajo y el de arriba, y una caja unitaria. El placer lo deforma con la grilla —así su borde superior cae
## siempre en el fin del piso, con edificios inclinados o rectos—, lo anota en el índice y OCUPA el módulo:
## la fachada sabe que ahí hay un puente apoyado, y nada rígido se coloca a través de él.
func _draw_bridge_extremes(bridge: Bridge, side: Dictionary, cell_start: int, cell_end: int,
		by_base: int, by_base_top: int, by_arc_bot: int,
		static_body: StaticBody3D, buf: Dictionary, placer: GridPlacer, ids: Array) -> void:
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
		var bz_min: int = grid_rect["bz_min"]
		var footprint := Vector2i(int(grid_rect["bx_max"]) - bx_min + 1, int(grid_rect["bz_max"]) - bz_min + 1)

		_place_bridge_extreme(placer, buf, module, Vector3i(bx_min, by_base, bz_min),
				Vector3i(footprint.x, by_base_top - by_base, footprint.y), bridge_base_color, static_body, ids)
		if bridge.arc_height > 0:
			_place_bridge_extreme(placer, buf, module, Vector3i(bx_min, by_arc_bot, bz_min),
					Vector3i(footprint.x, by_base - by_arc_bot, footprint.y), bridge_arc_color, static_body, ids)


## Una caja de extremo por la interfaz deformable. El collider sale de LOS MISMOS vértices que acaba de
## escribir el placer, así malla y colisión no pueden diferir.
func _place_bridge_extreme(placer: GridPlacer, buf: Dictionary, module: BuildingModule,
		lo: Vector3i, size: Vector3i, color: Color, static_body: StaticBody3D, ids: Array) -> void:
	var box := UnitMesh.new()
	box.add_box(Vector3.ZERO, Vector3.ONE, color)
	var v_from: int = buf["vertices"].size()
	if not placer.place(module, lo, size, box, CityIndex.Kind.BRIDGE, int(ids[0]), int(ids[1]),
			int(ids[2]), int(ids[3])):
		_bridge_extremes_rejected += 1
		return
	if static_body:
		var shape := ConvexPolygonShape3D.new()
		shape.points = buf["vertices"].slice(v_from)
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape
		static_body.add_child(collision_shape)
