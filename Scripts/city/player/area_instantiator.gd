extends Node3D
class_name AreaInstantiator

# ============================================================================
# AREA INSTANTIATOR - OPTIMIZADO
# ============================================================================

@export var outer_radius: float = 150.0
@export var inner_radius: float = 100.5
@export var height: float = 80.5
@export var segments: int = 32
@export var debug_volume_ring_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug_volume_ring: bool = false

@export var world: Node3D

@export_group("Lane Volume Visualization")
@export var show_lane_volumes: bool = false
@export var lane_volume_color: Color = Color(1.0, 0.5, 0.0)
@export var lane_volume_transparency: float = 0.3
@export var show_continuations: bool = false
@export var continuation_color: Color = Color(0.0, 1.0, 1.0)
@export var continuation_transparency: float = 0.2
@export var show_grid_points: bool = false
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 1

@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 0.05
@export_subgroup("Spawn Weights")
@export_range(0.0, 1.0) var car_weight: float = 0.7
@export_range(0.0, 1.0) var truck_weight: float = 0.1
@export_range(0.0, 1.0) var motorcycle_weight: float = 0.2

@export_group("Performance")
@export var update_interval: float = 0.5
@export var position_threshold: float = 0.5
@export var rotation_threshold: float = 0.5

var city = null
var debug_volume_ring_mesh: Node3D
var lane_volumes_container: Node3D
var destruction_area: Area3D

# MultiMesh para visualización eficiente
var grid_multimesh: MultiMeshInstance3D

# Cache de volúmenes (Dictionary para búsqueda O(1))
var cached_lane_volumes_dict: Dictionary = {} # key: volume_id, value: LaneVolume
var cached_position: Vector3 = Vector3.ZERO
var cached_rotation: Vector3 = Vector3.ZERO
var update_timer: float = 0.0
var spawn_timer: float = 0.0

# Puntos de spawn (solo intersecciones con radio interno)
var spawn_points: Array = []  # Array de {position: Vector3, direction: Vector3, lane_volume: LaneVolume, grid_u: float, grid_v: float}
var spawn_points_dirty: bool = true

# Meshes base para MultiMesh (reutilizables)
var sphere_mesh: SphereMesh

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	_create_destruction_area()
	_setup_visualization_containers()
	
	if show_debug_volume_ring:
		_create_debug_visualization()

func _exit_tree() -> void:
	_cleanup_containers()

func _setup_visualization_containers() -> void:
	if not world:
		return
	
	# Container para meshes de volúmenes
	lane_volumes_container = Node3D.new()
	lane_volumes_container.name = "LaneVolumesDebug_" + str(get_instance_id())
	world.add_child(lane_volumes_container)
	
	# MultiMesh para puntos de grilla
	sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = grid_point_size
	sphere_mesh.height = grid_point_size * 2
	sphere_mesh.radial_segments = 4
	sphere_mesh.rings = 2
	
	grid_multimesh = MultiMeshInstance3D.new()
	grid_multimesh.name = "GridPointsMultiMesh_" + str(get_instance_id())
	grid_multimesh.multimesh = MultiMesh.new()
	grid_multimesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grid_multimesh.multimesh.mesh = sphere_mesh
	world.add_child(grid_multimesh)

func _cleanup_containers() -> void:
	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_multimesh and is_instance_valid(grid_multimesh):
		grid_multimesh.queue_free()
	if destruction_area and is_instance_valid(destruction_area):
		destruction_area.queue_free()

func _create_destruction_area() -> void:
	destruction_area = Area3D.new()
	destruction_area.collision_layer = 0
	destruction_area.collision_mask = 1
	destruction_area.monitoring = true
	destruction_area.monitorable = false
	
	var collision_shape = CollisionShape3D.new()
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = outer_radius
	cylinder_shape.height = height
	collision_shape.shape = cylinder_shape
	
	destruction_area.add_child(collision_shape)
	destruction_area.area_exited.connect(_on_area_exited_area)
	add_child(destruction_area)

func _on_area_exited_area(area: Area3D) -> void:
	var parent = area.get_parent()
	if parent is FlyingCar:
		parent.queue_free()

func _process(delta: float) -> void:
	if city == null:
		return
	
	update_timer += delta
	
	if update_timer >= update_interval:
		update_timer = 0.0
		
		var position_changed = global_position.distance_to(cached_position) > position_threshold
		var rotation_changed = _rotation_changed()
		
		if position_changed or rotation_changed:
			cached_position = global_position
			cached_rotation = global_rotation
			
			if show_debug_volume_ring:
				_refresh_debug_visualization()
			
			# Obtener lane volumes
			var lane_volumes = city.get_lane_volumes_in_cylindrical_area(
				global_position,
				outer_radius,
				height
			)
			
			# Actualizar si cambiaron los volúmenes
			if _volumes_changed(lane_volumes):
				_update_cached_volumes(lane_volumes)
				spawn_points_dirty = true
				
				# Actualizar visualización incremental
				if show_lane_volumes:
					_update_lane_volumes_incremental()
	
	# Actualizar visualización de grilla (solo si es necesario)
	if show_grid_points and grid_multimesh.visible != show_grid_points:
		grid_multimesh.visible = show_grid_points
		if show_grid_points:
			_rebuild_grid_points()
	
	# Calcular puntos de spawn (independiente de visualización)
	if spawn_points_dirty:
		_calculate_spawn_points()
		spawn_points_dirty = false
		
		# Aprovechar para actualizar visualizaciones si están activas
		if show_grid_points:
			_rebuild_grid_points()
	
	# Sistema de spawn
	if enable_car_spawning:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_try_spawn_car()

func _rotation_changed() -> bool:
	var current_rotation = global_rotation
	var delta_x = abs(current_rotation.x - cached_rotation.x)
	var delta_y = abs(current_rotation.y - cached_rotation.y)
	var delta_z = abs(current_rotation.z - cached_rotation.z)
	
	return delta_x > rotation_threshold or delta_y > rotation_threshold or delta_z > rotation_threshold

func _volumes_changed(new_volumes: Array[LaneVolume]) -> bool:
	# Comparación rápida usando Dictionary
	if new_volumes.size() != cached_lane_volumes_dict.size():
		return true
	
	for vol in new_volumes:
		if not cached_lane_volumes_dict.has(vol.get_id()):
			return true
	
	return false

func _update_cached_volumes(new_volumes: Array[LaneVolume]) -> void:
	# Construir nuevo diccionario
	var new_dict = {}
	for vol in new_volumes:
		new_dict[vol.get_id()] = vol
	
	# Agregar continuaciones si está habilitado
	if show_continuations and city:
		for vol in new_volumes:
			var continuations = city.get_lane_volume_continuations(vol.face_idx, vol.edge_idx)
			for cont in continuations:
				var cont_id = cont.get_id()
				if not new_dict.has(cont_id):
					new_dict[cont_id] = cont
	
	cached_lane_volumes_dict = new_dict

# ============================================================================
# CÁLCULO DE PUNTOS DE SPAWN (OPTIMIZADO)
# ============================================================================

func _calculate_spawn_points() -> void:
	spawn_points.clear()
	
	var effective_width = granularity
	var effective_height = granularity
	
	for vol in cached_lane_volumes_dict.values():
		var width_steps = vol.width_cells * effective_width
		var height_steps = vol.height_cells * effective_height
		
		for i in range(width_steps + 1):
			for j in range(height_steps + 1):
				var u = float(i) / float(width_steps) if width_steps > 0 else 0.0
				var v = float(j) / float(height_steps) if height_steps > 0 else 0.0
				
				var path_segment = vol.get_path_segment_at_grid(u, v)
				
				# Encontrar intersección con cilindro interno
				var intersection = _find_inner_cylinder_intersection(
					path_segment["start"],
					path_segment["end"]
				)
				
				if intersection:
					spawn_points.append({
						"position": intersection["position"],
						"direction": intersection["direction"],
						"lane_volume": vol,
						"grid_u": u,
						"grid_v": v,
						"width_cells": width_steps,
						"height_cells": height_steps
					})

func _find_inner_cylinder_intersection(start: Vector3, end: Vector3) -> Dictionary:
	# Convertir a espacio local del cilindro
	var local_start = to_local(start)
	var local_end = to_local(end)
	
	# Verificar altura
	var half_height = height * 0.5
	if (local_start.y < -half_height and local_end.y < -half_height) or \
	   (local_start.y > half_height and local_end.y > half_height):
		return {}
	
	# Proyectar a plano XZ
	var start_2d = Vector2(local_start.x, local_start.z)
	var end_2d = Vector2(local_end.x, local_end.z)
	
	var dist_start = start_2d.length()
	var dist_end = end_2d.length()
	
	# Verificar si cruza el radio interno desde afuera
	if dist_start <= inner_radius and dist_end <= inner_radius:
		return {}  # Ambos dentro, no cruza desde afuera
	
	if dist_start >= inner_radius and dist_end >= inner_radius:
		# Verificar si pasa por el círculo
		var closest = _closest_point_on_segment_2d(Vector2.ZERO, start_2d, end_2d)
		if closest.length() > inner_radius:
			return {}  # No intersecta
	
	# Calcular punto de intersección con círculo
	var dir_2d = (end_2d - start_2d).normalized()
	var to_start = start_2d
	
	# Resolver ecuación cuadrática: |start + t*dir|² = radius²
	var a = dir_2d.dot(dir_2d)
	var b = 2.0 * to_start.dot(dir_2d)
	var c = to_start.dot(to_start) - inner_radius * inner_radius
	
	var discriminant = b * b - 4 * a * c
	if discriminant < 0:
		return {}
	
	var t1 = (-b - sqrt(discriminant)) / (2 * a)
	var t2 = (-b + sqrt(discriminant)) / (2 * a)
	
	# Queremos el primer punto de entrada (desde afuera hacia adentro)
	var t = t1 if dist_start > inner_radius else t2
	
	if t < 0 or t > start_2d.distance_to(end_2d):
		return {}
	
	# Interpolar en 3D
	var segment_length = start.distance_to(end)
	var t_3d = t / start_2d.distance_to(end_2d) if start_2d.distance_to(end_2d) > 0 else 0
	var intersection_pos = start.lerp(end, t_3d)
	
	# Calcular dirección
	var direction = (end - start).normalized()
	
	return {
		"position": intersection_pos,
		"direction": direction
	}

func _closest_point_on_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var ap = point - a
	var t = ap.dot(ab) / ab.dot(ab)
	t = clamp(t, 0.0, 1.0)
	return a + ab * t

# ============================================================================
# VISUALIZACIÓN DEBUG - OPTIMIZADA
# ============================================================================

func _create_debug_visualization() -> void:
	_refresh_debug_visualization()

func _refresh_debug_visualization() -> void:
	if debug_volume_ring_mesh:
		debug_volume_ring_mesh.queue_free()
	
	debug_volume_ring_mesh = DebugUtil.create_debug_ring_volume_wireframe(
		debug_volume_ring_color, outer_radius, inner_radius, height, segments
	)
	add_child(debug_volume_ring_mesh)

func _update_lane_volumes_incremental() -> void:
	if not lane_volumes_container:
		return
	
	# Marcar meshes existentes
	var existing_meshes = {}
	for child in lane_volumes_container.get_children():
		var vol_id = child.get_meta("volume_id", "")
		if vol_id:
			existing_meshes[vol_id] = child
	
	# Eliminar volúmenes que ya no existen
	for vol_id in existing_meshes.keys():
		if not cached_lane_volumes_dict.has(vol_id):
			existing_meshes[vol_id].queue_free()
			existing_meshes.erase(vol_id)
	
	# Agregar volúmenes nuevos
	for vol_id in cached_lane_volumes_dict.keys():
		if not existing_meshes.has(vol_id):
			var vol = cached_lane_volumes_dict[vol_id]
			
			# Determinar color según si es continuación o no
			var is_continuation = vol_id.begins_with(str(vol.face_idx) + "_") and \
								  not _is_primary_volume(vol)
			var color = continuation_color if is_continuation else lane_volume_color
			var transparency = continuation_transparency if is_continuation else lane_volume_transparency
			
			var mesh = _create_volume_mesh(vol, color, transparency)
			if mesh:
				mesh.set_meta("volume_id", vol_id)
				lane_volumes_container.add_child(mesh)

func _is_primary_volume(vol: LaneVolume) -> bool:
	# Verificar si este volumen está en la lista primaria (no es continuación)
	if city:
		var primary_vols = city.get_lane_volumes_in_cylindrical_area(
			global_position,
			outer_radius,
			height
		)
		for primary in primary_vols:
			if primary.get_id() == vol.get_id():
				return true
	return false

func _create_volume_mesh(vol: LaneVolume, color: Color, transparency: float) -> Node3D:
	return DebugUtil.create_skewed_cube_from_planes(
		vol.start_plane_vertices,
		vol.end_plane_vertices,
		color,
		transparency
	)

func _rebuild_grid_points() -> void:
	if not grid_multimesh or not grid_multimesh.multimesh:
		return
	
	var transforms: Array[Transform3D] = []
	
	var effective_width = granularity
	var effective_height = granularity
	
	for vol in cached_lane_volumes_dict.values():
		var width_steps = vol.width_cells * effective_width
		var height_steps = vol.height_cells * effective_height
		
		for i in range(width_steps + 1):
			for j in range(height_steps + 1):
				var u = float(i) / float(width_steps) if width_steps > 0 else 0.0
				var v = float(j) / float(height_steps) if height_steps > 0 else 0.0
				
				# Punto en plano de inicio
				var point_start = vol.get_point_at_grid(u, v, true)
				var transform_start = Transform3D()
				transform_start.origin = point_start
				transforms.append(transform_start)
				
				# Punto en plano final
				var point_end = vol.get_point_at_grid(u, v, false)
				var transform_end = Transform3D()
				transform_end.origin = point_end
				transforms.append(transform_end)
	
	# Actualizar MultiMesh
	grid_multimesh.multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		grid_multimesh.multimesh.set_instance_transform(i, transforms[i])
	
	# Aplicar material con color
	var material = StandardMaterial3D.new()
	material.albedo_color = grid_point_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_multimesh.material_override = material

# ============================================================================
# SISTEMA DE SPAWN DE AUTOS (OPTIMIZADO)
# ============================================================================

func _try_spawn_car() -> void:
	if spawn_points.is_empty() or not world:
		return
	
	var car_seed = randi()
	
	# Crear auto temporal para obtener dimensiones
	var temp_car = FlyingCar.new()
	var custom_weights = {
		CarArchetypes.Type.CAR: car_weight,
		CarArchetypes.Type.TRUCK: truck_weight,
		CarArchetypes.Type.MOTORCYCLE: motorcycle_weight
	}
	temp_car.initialize_from_seed(car_seed, custom_weights)
	
	var car_width = temp_car.width
	var car_height = temp_car.height
	var car_depth = temp_car.depth
	var car_speed = temp_car.speed
	var car_color = temp_car.car_color
	var car_archetype = temp_car.car_archetype
	
	# Intentar spawn (máximo 5 intentos)
	var max_tries = 5
	var remaining_points = spawn_points.duplicate()
	
	for try_count in range(max_tries):
		if remaining_points.is_empty():
			temp_car.free()
			return
		
		# Seleccionar punto aleatorio
		var random_idx = randi() % remaining_points.size()
		var spawn_data = remaining_points[random_idx]
		var lane_vol: LaneVolume = spawn_data["lane_volume"]
		
		# Construir segmento temporal para la cara frontal
		var spawn_pos = spawn_data["position"]
		var end_pos = spawn_pos + spawn_data["direction"] * car_depth
		
		var front_face = temp_car.get_front_face_at_segment(spawn_pos, end_pos)
		
		# Validar proyección
		var validation = lane_vol.validate_face_projection(
			front_face,
			spawn_data["grid_u"],
			spawn_data["grid_v"]
		)
		
		if validation["valid"]:
			temp_car.free()
			_spawn_car_at_point(spawn_data, lane_vol, car_seed, car_width, car_height,
							   car_depth, car_speed, car_color, car_archetype, custom_weights)
			return
		else:
			# Remover este punto y continuar
			remaining_points.remove_at(random_idx)
	
	temp_car.free()

func _spawn_car_at_point(spawn_data: Dictionary, lane_vol: LaneVolume, car_seed: int,
						car_width: float, car_height: float, car_depth: float,
						car_speed: float, car_color: Color, car_archetype: FlyingCar.Type,
						custom_weights: Dictionary) -> void:
	
	# Construir segmento completo del path
	var full_path_segment = lane_vol.get_path_segment_at_grid(
		spawn_data["grid_u"],
		spawn_data["grid_v"]
	)
	
	# Crear auto
	var car = FlyingCar.new()
	car.world_node = world
	car.city = city
	car.spawn_time = Time.get_ticks_msec() / 1000.0
	
	car.initialize_from_seed(car_seed, custom_weights)
	
	world.add_child(car)
	car.set_path(
		full_path_segment["start"],
		full_path_segment["end"],
		0.0,  # Siempre empieza desde el inicio del segmento
		spawn_data["grid_u"],
		spawn_data["grid_v"],
		lane_vol.get_raw_data(),
		spawn_data["width_cells"],
		spawn_data["height_cells"]
	)
