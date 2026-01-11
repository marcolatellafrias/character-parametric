extends Node3D
class_name AreaInstantiator

# ============================================================================
# AREA INSTANTIATOR - VERSIÓN CON DETECCIÓN POR CONTACTO
# ============================================================================

@export var outer_radius: float = 200.0
@export var ring_thickness: float = 10.0
@export var height: float = 6.5
@export var segments: int = 16
@export var debug_cylinder_color: Color = Color(0.0, 1.0, 0.0, 0.15)
@export var debug_ring_color: Color = Color(1.0, 0.5, 0.0, 0.15)
@export var show_debug_cylinder: bool = false
@export var show_debug_ring: bool = false

@export var world: Node3D

@export_group("Lane Volume Visualization")
@export var show_ring_volumes: bool = false
@export var ring_volume_color: Color = Color(1.0, 0.5, 0.0) 
@export var ring_volume_transparency: float = 0.2
@export var show_continuations: bool = false
@export var continuation_color: Color = Color(0.0, 1.0, 1.0)
@export var continuation_transparency: float = 0.3
@export var show_grid_points: bool = false
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 1

@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 0.1
@export_subgroup("Spawn Weights")
@export_range(0.0, 1.0) var car_weight: float = 0.7
@export_range(0.0, 1.0) var truck_weight: float = 0.02
@export_range(0.0, 1.0) var motorcycle_weight: float = 0.28

var city = null
var debug_cylinder_mesh: MeshInstance3D
var debug_ring_mesh: Node3D  
var lane_volumes_container: Node3D
var grid_points_container: Node3D

var cylinder_area: Area3D
var ring_area: Area3D

# Lane volumes detectados por contacto
var cylinder_lane_volumes: Array[LaneVolume] = []
var ring_lane_volumes: Array[LaneVolume] = []

var spawn_timer: float = 0.0

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	_create_cylinder_area()
	_create_ring_area()
	_setup_visualization_containers()
	
	if show_debug_cylinder:
		_create_debug_cylinder()
	
	if show_debug_ring:
		_create_debug_ring()

func _exit_tree() -> void:
	_cleanup_containers()

func _setup_visualization_containers() -> void:
	if not world:
		return
	
	lane_volumes_container = Node3D.new()
	lane_volumes_container.name = "LaneVolumesDebug_" + str(get_instance_id())
	world.add_child(lane_volumes_container)
	
	grid_points_container = Node3D.new()
	grid_points_container.name = "GridPointsDebug_" + str(get_instance_id())
	world.add_child(grid_points_container)

func _cleanup_containers() -> void:
	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_points_container and is_instance_valid(grid_points_container):
		grid_points_container.queue_free()
	if cylinder_area and is_instance_valid(cylinder_area):
		cylinder_area.queue_free()
	if ring_area and is_instance_valid(ring_area):
		ring_area.queue_free()
	if debug_cylinder_mesh and is_instance_valid(debug_cylinder_mesh):
		debug_cylinder_mesh.queue_free()
	if debug_ring_mesh and is_instance_valid(debug_ring_mesh):
		debug_ring_mesh.queue_free()

# ============================================================================
# CREACIÓN DE ÁREAS
# ============================================================================

func _create_cylinder_area() -> void:
	cylinder_area = Area3D.new()
	cylinder_area.name = "CylinderArea"
	cylinder_area.collision_layer = 0
	cylinder_area.collision_mask = 2
	cylinder_area.monitoring = true
	cylinder_area.monitorable = false
	
	var colliders = DebugUtil.create_cylinder_colliders(outer_radius, height, segments)
	for collider in colliders:
		cylinder_area.add_child(collider)
	
	cylinder_area.area_entered.connect(_on_cylinder_area_entered)
	cylinder_area.area_exited.connect(_on_cylinder_area_exited)
	add_child(cylinder_area)

func _create_ring_area() -> void:
	ring_area = Area3D.new()
	ring_area.name = "RingVolumeArea"
	ring_area.collision_layer = 0
	ring_area.collision_mask = 2
	ring_area.monitoring = true
	ring_area.monitorable = false
	
	var inner_radius = outer_radius - ring_thickness
	var colliders = DebugUtil.create_ring_volume_colliders(outer_radius, inner_radius, height, segments)
	for collider in colliders:
		ring_area.add_child(collider)
	
	ring_area.area_entered.connect(_on_ring_area_entered)
	ring_area.area_exited.connect(_on_ring_area_exited)
	add_child(ring_area)

# ============================================================================
# SEÑALES DE DETECCIÓN DE CONTACTO
# ============================================================================

func _on_cylinder_area_entered(area: Area3D) -> void:
	if area is LaneVolume:
		if not cylinder_lane_volumes.has(area):
			cylinder_lane_volumes.append(area)

func _on_cylinder_area_exited(area: Area3D) -> void:
	if area is LaneVolume:
		var idx = cylinder_lane_volumes.find(area)
		if idx != -1:
			cylinder_lane_volumes.remove_at(idx)

func _on_ring_area_entered(area: Area3D) -> void:
	if area is LaneVolume:
		if not ring_lane_volumes.has(area):
			ring_lane_volumes.append(area)
			print("Lane volume entró al anillo: ", area.get_id())
			_update_visualization()

func _on_ring_area_exited(area: Area3D) -> void:
	if area is LaneVolume:
		var idx = ring_lane_volumes.find(area)
		if idx != -1:
			ring_lane_volumes.remove_at(idx)
			print("Lane volume salió del anillo: ", area.get_id())
			_update_visualization()

# ============================================================================
# VISUALIZACIÓN DEBUG
# ============================================================================

func _create_debug_cylinder() -> void:
	if debug_cylinder_mesh and is_instance_valid(debug_cylinder_mesh):
		debug_cylinder_mesh.queue_free()
	
	debug_cylinder_mesh = DebugUtil.create_debug_cylinder(
		debug_cylinder_color, 
		outer_radius, 
		height, 
		segments
	)
	add_child(debug_cylinder_mesh)

func _create_debug_ring() -> void:
	if debug_ring_mesh and is_instance_valid(debug_ring_mesh):
		debug_ring_mesh.queue_free()
	
	var inner_radius = outer_radius - ring_thickness
	
	# Crear contenedor para los dos círculos
	debug_ring_mesh = Node3D.new()
	debug_ring_mesh.name = "DebugRingBase"
	
	# Círculo exterior
	var outer_circle = MeshInstance3D.new()
	outer_circle.mesh = DebugUtil.create_debug_ring_mesh(outer_radius, segments)
	var outer_material = StandardMaterial3D.new()
	outer_material.albedo_color = debug_ring_color
	outer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_circle.material_override = outer_material
	debug_ring_mesh.add_child(outer_circle)
	
	# Círculo interior
	var inner_circle = MeshInstance3D.new()
	inner_circle.mesh = DebugUtil.create_debug_ring_mesh(inner_radius, segments)
	var inner_material = StandardMaterial3D.new()
	inner_material.albedo_color = debug_ring_color
	inner_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_circle.material_override = inner_material
	debug_ring_mesh.add_child(inner_circle)
	
	# Posicionar a la altura del player (mitad de la altura hacia abajo)
	debug_ring_mesh.position.y = -height * 0.5
	
	add_child(debug_ring_mesh)

func _update_visualization() -> void:
	if not lane_volumes_container or not grid_points_container:
		return
	
	# Limpiar visualización anterior
	for child in lane_volumes_container.get_children():
		child.queue_free()
	for child in grid_points_container.get_children():
		child.queue_free()
	
	# Obtener todas las continuaciones si está habilitado
	var volumes_to_visualize: Array[LaneVolume] = []
	volumes_to_visualize.append_array(ring_lane_volumes)
	
	var continuation_volumes: Array[LaneVolume] = []
	if show_continuations and city:
		for vol in ring_lane_volumes:
			var continuations = city.get_lane_volume_continuations(vol.face_idx, vol.edge_idx)
			for cont in continuations:
				if not _volume_exists_in_array(cont, volumes_to_visualize):
					continuation_volumes.append(cont)
	
	# Visualizar lane volumes del anillo
	if show_ring_volumes:
		for vol in ring_lane_volumes:
			var mesh = _create_volume_mesh(vol, ring_volume_color, ring_volume_transparency)
			if mesh:
				lane_volumes_container.add_child(mesh)
	
	# Visualizar continuaciones
	if show_continuations:
		for cont_vol in continuation_volumes:
			var mesh = _create_volume_mesh(cont_vol, continuation_color, continuation_transparency)
			if mesh:
				lane_volumes_container.add_child(mesh)
	
	# Visualizar grid points
	if show_grid_points:
		# Grid points de ring volumes
		for vol in ring_lane_volumes:
			_create_grid_points_for_volume(vol, grid_point_color)
		
		# Grid points de continuaciones
		if show_continuations:
			for cont_vol in continuation_volumes:
				_create_grid_points_for_volume(cont_vol, continuation_color)

func _volume_exists_in_array(vol: LaneVolume, array: Array[LaneVolume]) -> bool:
	var vol_id = vol.get_id()
	for existing in array:
		if existing.get_id() == vol_id:
			return true
	return false

func _create_volume_mesh(vol: LaneVolume, color: Color, transparency: float) -> Node3D:
	return DebugUtil.create_skewed_cube_from_planes(
		vol.start_plane_vertices,
		vol.end_plane_vertices,
		color,
		transparency
	)

func _create_grid_points_for_volume(vol: LaneVolume, color: Color) -> void:
	var effective_width = granularity
	var effective_height = granularity
	
	var width_steps = vol.width_cells * effective_width
	var height_steps = vol.height_cells * effective_height
	
	for i in range(width_steps + 1):
		for j in range(height_steps + 1):
			var u = float(i) / float(width_steps) if width_steps > 0 else 0.0
			var v = float(j) / float(height_steps) if height_steps > 0 else 0.0
			
			# Punto en start plane
			var point_start = vol.get_point_at_grid(u, v, true)
			var sphere_start = DebugUtil.create_debug_sphere_print(
				Vector2i(i, j), 
				color, 
				grid_point_size
			)
			grid_points_container.add_child(sphere_start)
			sphere_start.global_position = point_start
			
			# Punto en end plane
			var point_end = vol.get_point_at_grid(u, v, false)
			var sphere_end = DebugUtil.create_debug_sphere_print(
				Vector2i(i, j), 
				color, 
				grid_point_size
			)
			grid_points_container.add_child(sphere_end)
			sphere_end.global_position = point_end

# ============================================================================
# PROCESO PRINCIPAL
# ============================================================================

func _process(delta: float) -> void:
	if not enable_car_spawning:
		return
	
	if not world:
		print("ERROR: No hay world node")
		return
	
	if not city:
		print("ERROR: No hay city")
		return
	
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		print("\n--- Timer de spawn alcanzado (", spawn_interval, "s) ---")
		print("Ring volumes: ", ring_lane_volumes.size())
		print("Cylinder volumes: ", cylinder_lane_volumes.size())
		_try_spawn_car()

# ============================================================================
# SISTEMA DE SPAWN DE AUTOS
# ============================================================================

func _try_spawn_car() -> void:
	print("=== Intentando spawnear auto ===")
	print("Ring volumes detectados: ", ring_lane_volumes.size())
	print("Cylinder volumes detectados: ", cylinder_lane_volumes.size())
	
	var spawn_candidates: Array[LaneVolume] = []
	
	for ring_vol in ring_lane_volumes:
		if _has_continuation_in_cylinder(ring_vol):
			spawn_candidates.append(ring_vol)
			print("Volume candidato encontrado: ", ring_vol.get_id())
	
	print("Total candidatos: ", spawn_candidates.size())
	
	if spawn_candidates.is_empty():
		print("No hay candidatos para spawn")
		return
	
	var selected_vol = spawn_candidates[randi() % spawn_candidates.size()]
	print("Volume seleccionado: ", selected_vol.get_id())
	
	var car_seed = randi()
	var temp_car = FlyingCar.new()
	var custom_weights = {
		CarArchetypes.Type.CAR: car_weight,
		CarArchetypes.Type.TRUCK: truck_weight,
		CarArchetypes.Type.MOTORCYCLE: motorcycle_weight
	}
	temp_car.initialize_from_seed(car_seed, custom_weights)
	
	var max_attempts = 10
	for attempt in range(max_attempts):
		var random_u = randf()
		var random_v = randf()
		
		print("Intento ", attempt + 1, " en u=", random_u, " v=", random_v)
		
		var spawn_pos = selected_vol.get_point_at_grid(random_u, random_v, true)
		var end_pos = selected_vol.get_point_at_grid(random_u, random_v, false)
		
		var front_face = temp_car.get_front_face_at_segment(spawn_pos, end_pos)
		
		var validation = selected_vol.validate_face_projection(
			front_face,
			random_u,
			random_v
		)
		
		print("Validación: ", validation)
		
		if validation["valid"]:
			print("¡Spawn exitoso!")
			temp_car.free()
			_spawn_car_at_volume(selected_vol, random_u, random_v, car_seed, custom_weights)
			return
	
	print("Falló después de ", max_attempts, " intentos")
	temp_car.free()

func _has_continuation_in_cylinder(ring_vol: LaneVolume) -> bool:
	if not city:
		print("No hay city para ", ring_vol.get_id())
		return false
	
	var continuations = city.get_lane_volume_continuations(ring_vol.face_idx, ring_vol.edge_idx)
	print("Volume ", ring_vol.get_id(), " tiene ", continuations.size(), " continuaciones")
	
	for cont in continuations:
		for cyl_vol in cylinder_lane_volumes:
			if cont.get_id() == cyl_vol.get_id():
				print("  Continuación ", cont.get_id(), " está en cilindro!")
				return true
	
	return false

func _spawn_car_at_volume(vol: LaneVolume, grid_u: float, grid_v: float, 
						  car_seed: int, custom_weights: Dictionary) -> void:
	
	print("Spawneando auto en volume ", vol.get_id(), " en u=", grid_u, " v=", grid_v)
	
	var path_segment = vol.get_path_segment_at_grid(grid_u, grid_v)
	
	print("Path start: ", path_segment["start"])
	print("Path end: ", path_segment["end"])
	
	var car = FlyingCar.new()
	car.world_node = world
	car.city = city
	car.spawn_time = Time.get_ticks_msec() / 1000.0
	
	car.initialize_from_seed(car_seed, custom_weights)
	
	world.add_child(car)
	
	print("Auto agregado al world, llamando set_path...")
	
	car.set_path(
		path_segment["start"],
		path_segment["end"],
		0.0,
		grid_u,
		grid_v,
		vol.get_raw_data(),
		vol.width_cells,
		vol.height_cells
	)
	
	print("set_path completado, auto debería estar visible")
