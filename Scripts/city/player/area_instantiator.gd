extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 8.0
@export var inner_radius: float = 4.5
@export var height: float = 4.5
@export var segments: int = 32  # Solo para fidelidad visual
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var show_debug: bool = true

@export var world: Node3D

@export_group("Lane Volume Visualization")
@export var show_lane_volumes: bool = true
@export var lane_volume_color: Color = Color(1.0, 0.5, 0.0)
@export var lane_volume_transparency: float = 0.3
@export var show_continuations: bool = true
@export var continuation_color: Color = Color(0.0, 1.0, 1.0)
@export var continuation_transparency: float = 0.2
@export var show_grid_points: bool = true
@export var grid_point_color: Color = Color(1.0, 1.0, 0.0)
@export var grid_point_size: float = 0.05
@export_range(1, 10) var granularity: int = 1
@export var show_flow_arrows: bool = true
@export var flow_arrow_color: Color = Color(0.0, 0.5, 1.0)
@export var flow_arrow_width: float = 0.02

# Reemplazar el grupo "Car Spawning" con esto:
@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 0.05
@export_subgroup("Spawn Weights")
@export_range(0.0, 1.0) var car_weight: float = 0.7
@export_range(0.0, 1.0) var truck_weight: float = 0.1
@export_range(0.0, 1.0) var motorcycle_weight: float = 0.2

@export_group("Performance")
@export var update_interval: float = 0.01
@export var position_threshold: float = 0.01
@export var rotation_threshold: float = 0.01

var debug_mesh: Node3D
var city = null
var lane_volumes_container: Node3D
var grid_points_container: Node3D
var flow_arrows_container: Node3D

var cached_volumes: Array = []
var cached_position: Vector3 = Vector3.ZERO
var cached_rotation: Vector3 = Vector3.ZERO
var update_timer: float = 0.0
var spawn_timer: float = 0.0

# Almacenar segmentos válidos para spawning
var valid_spawn_segments: Array = []  # Array de {start: Vector3, end: Vector3, volume: Dictionary}

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	if world:
		lane_volumes_container = Node3D.new()
		lane_volumes_container.name = "LaneVolumesDebug_" + str(get_instance_id())
		world.add_child(lane_volumes_container)
		
		grid_points_container = Node3D.new()
		grid_points_container.name = "GridPointsDebug_" + str(get_instance_id())
		world.add_child(grid_points_container)
		
		flow_arrows_container = Node3D.new()
		flow_arrows_container.name = "FlowArrowsDebug_" + str(get_instance_id())
		world.add_child(flow_arrows_container)
	
	if show_debug:
		_create_debug_visualization()

func _exit_tree() -> void:
	if lane_volumes_container and is_instance_valid(lane_volumes_container):
		lane_volumes_container.queue_free()
	if grid_points_container and is_instance_valid(grid_points_container):
		grid_points_container.queue_free()
	if flow_arrows_container and is_instance_valid(flow_arrows_container):
		flow_arrows_container.queue_free()

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
			
			if show_debug:
				_refresh_debug_visualization()
			
			var volumes = city.get_lane_volumes_in_cylindrical_area(
				global_position,
				outer_radius,
				height
			)
			
			# Actualizar flechas siempre que haya movimiento/rotación
			if show_flow_arrows and flow_arrows_container:
				_update_flow_arrows(volumes)
			
			if _volumes_changed(volumes):
				cached_volumes = volumes
				
				if show_lane_volumes and lane_volumes_container:
					_update_lane_volumes(volumes)
				
				if show_grid_points and grid_points_container:
					_update_grid_points(volumes)
	
	# Sistema de spawn de autos basado en delta
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

func _volumes_changed(new_volumes: Array) -> bool:
	if new_volumes.size() != cached_volumes.size():
		return true
	
	for i in range(new_volumes.size()):
		if i >= cached_volumes.size():
			return true
		
		var new_vol = new_volumes[i]
		var old_vol = cached_volumes[i]
		
		if new_vol.get("face_idx") != old_vol.get("face_idx"):
			return true
		if new_vol.get("edge_idx") != old_vol.get("edge_idx"):
			return true
	
	return false

func _create_debug_visualization() -> void:
	_refresh_debug_visualization()

func _update_lane_volumes(volumes: Array) -> void:
	for child in lane_volumes_container.get_children():
		child.queue_free()
	
	# Set para rastrear volumes ya visualizados (evitar duplicados)
	var visualized_volumes: Dictionary = {}
	
	# Visualizar volumes primarios (intersectados)
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		
		var volume_mesh = DebugUtil.create_skewed_cube_from_planes(
			vol["start_plane_vertices"],
			vol["end_plane_vertices"],
			lane_volume_color,
			lane_volume_transparency
		)
		
		if volume_mesh:
			lane_volumes_container.add_child(volume_mesh)
			visualized_volumes[key] = true
	
	# Visualizar continuaciones si está habilitado
	if show_continuations:
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				# Evitar visualizar volumes ya mostrados
				if cont_key in visualized_volumes:
					continue
				
				# Obtener el BlockGenerator del face continuación
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
				# Obtener el volume data completo
				var cont_volume_data = cont_block.get_edge_lane_volume(cont["edge_idx"])
				
				if cont_volume_data.is_empty():
					continue
				
				var cont_mesh = DebugUtil.create_skewed_cube_from_planes(
					cont_volume_data["start_plane_vertices"],
					cont_volume_data["end_plane_vertices"],
					continuation_color,
					continuation_transparency
				)
				
				if cont_mesh:
					lane_volumes_container.add_child(cont_mesh)
					visualized_volumes[cont_key] = true

func _update_grid_points(volumes: Array) -> void:
	for child in grid_points_container.get_children():
		child.queue_free()
	
	# Set para rastrear volumes ya visualizados (evitar duplicados)
	var visualized_volumes: Dictionary = {}
	
	# Visualizar grid points de volumes primarios (intersectados)
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		visualized_volumes[key] = true
		
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_grid_for_plane(vol["start_plane_vertices"], effective_width, effective_height)
		_create_grid_for_plane(vol["end_plane_vertices"], effective_width, effective_height)
	
	# Visualizar grid points de continuaciones si está habilitado
	if show_continuations and city:
		# Obtener el generator del city visualizer
		var gen = city.get_generator()
		if gen == null:
			return
		
		# Obtener parámetros del city generator para calcular cells
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				# Evitar visualizar volumes ya mostrados
				if cont_key in visualized_volumes:
					continue
				
				# Obtener el BlockGenerator del face continuación
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
				# Obtener el volume data completo
				var cont_volume_data = cont_block.get_edge_lane_volume(cont["edge_idx"])
				
				if cont_volume_data.is_empty():
					continue
				
				var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(cont_volume_data.get("street_type", 0), 3)
				var height_cells = 0
				if city_block_cell_height > 0 and city_cells_per_floor > 0:
					var floor_height = city_cells_per_floor * city_block_cell_height
					var num_floors = ceil(cont_volume_data["height"] / floor_height)
					height_cells = int(num_floors * city_cells_per_floor)
				
				var effective_width = width_cells * granularity
				var effective_height = height_cells * granularity
				
				_create_grid_for_plane(cont_volume_data["start_plane_vertices"], effective_width, effective_height)
				_create_grid_for_plane(cont_volume_data["end_plane_vertices"], effective_width, effective_height)
				
				visualized_volumes[cont_key] = true

func _update_flow_arrows(volumes: Array) -> void:
	for child in flow_arrows_container.get_children():
		child.queue_free()
	
	# Limpiar segmentos válidos previos
	valid_spawn_segments.clear()
	
	# Set para rastrear volumes ya visualizados (evitar duplicados)
	var visualized_volumes: Dictionary = {}
	
	# Visualizar flow arrows de volumes primarios (intersectados)
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		visualized_volumes[key] = true
		
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_flow_arrows_for_volume(vol["start_plane_vertices"], vol["end_plane_vertices"], effective_width, effective_height, vol)
	
	# Visualizar flow arrows de continuaciones si está habilitado
	if show_continuations and city:
		# Obtener el generator del city visualizer
		var gen = city.get_generator()
		if gen == null:
			return
		
		# Obtener parámetros del city generator para calcular cells
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				# Evitar visualizar volumes ya mostrados
				if cont_key in visualized_volumes:
					continue
				
				# Obtener el BlockGenerator del face continuación
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
				# Obtener el volume data completo
				var cont_volume_data = cont_block.get_edge_lane_volume(cont["edge_idx"])
				
				if cont_volume_data.is_empty():
					continue
				
				var width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(cont_volume_data.get("street_type", 0), 3)
				var height_cells = 0
				if city_block_cell_height > 0 and city_cells_per_floor > 0:
					var floor_height = city_cells_per_floor * city_block_cell_height
					var num_floors = ceil(cont_volume_data["height"] / floor_height)
					height_cells = int(num_floors * city_cells_per_floor)
				
				var effective_width = width_cells * granularity
				var effective_height = height_cells * granularity
				
				_create_flow_arrows_for_volume(cont_volume_data["start_plane_vertices"], cont_volume_data["end_plane_vertices"], effective_width, effective_height, cont_volume_data)
				
				visualized_volumes[cont_key] = true

func _create_flow_arrows_for_volume(start_plane: Array, end_plane: Array, width_cells: int, height_cells: int, volume: Dictionary) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			# Obtener puntos correspondientes en ambos planos
			var bottom_start = start_plane[0].lerp(start_plane[1], u)
			var top_start = start_plane[3].lerp(start_plane[2], u)
			var point_start = bottom_start.lerp(top_start, v)
			
			var bottom_end = end_plane[0].lerp(end_plane[1], u)
			var top_end = end_plane[3].lerp(end_plane[2], u)
			var point_end = bottom_end.lerp(top_end, v)
			
			# Obtener segmentos de la línea que están dentro del anillo
			var segments_array = _get_line_segments_in_ring(point_start, point_end)
			
			# Crear flechas para cada segmento y almacenarlos para spawning
			for segment in segments_array:
				var arrow = DebugUtil.create_debug_arrow_to_from(segment[0], segment[1], flow_arrow_color, flow_arrow_width)
				flow_arrows_container.add_child(arrow)
				
				# Almacenar segmento válido para spawning con el path original completo
				valid_spawn_segments.append({
					"start": segment[0],
					"end": segment[1],
					"original_start": point_start,  # Path completo original
					"original_end": point_end,
					"volume": volume
				})

func _try_spawn_car() -> void:
	print("=== Intentando spawnear auto ===")
	print("Valid spawn segments: ", valid_spawn_segments.size())
	print("World exists: ", world != null)
	
	if valid_spawn_segments.is_empty() or not world:
		print("ABORTADO: No hay segmentos válidos o no hay world")
		return
	
	# Intentar varias veces encontrar un spawn válido
	var max_attempts = 10
	for attempt in range(max_attempts):
		print("  Intento ", attempt + 1, "/", max_attempts)
		var custom_weights = {
		CarArchetypes.Type.CAR: car_weight,
		CarArchetypes.Type.TRUCK: truck_weight,
		CarArchetypes.Type.MOTORCYCLE: motorcycle_weight
		}
		var archetype = CarArchetypes.get_weighted_random_archetype(custom_weights)

		var dims = archetype.get_random_dimensions()
		
		var car_width = dims["width"]
		var car_height = dims["height"]
		var car_depth = dims["depth"]
		var car_speed = dims["speed"]
		
		print("    Arquetipo: ", archetype.name)
		print("    Dimensiones: w=%.2f h=%.2f d=%.2f speed=%.2f" % [car_width, car_height, car_depth, car_speed])
		
		# Filtrar segmentos que sean lo suficientemente largos
		var suitable_segments = []
		for seg_data in valid_spawn_segments:
			var seg_length = seg_data["start"].distance_to(seg_data["end"])
			if seg_length >= car_depth:
				suitable_segments.append(seg_data)
		
		print("    Segmentos adecuados (>= %.2f): %d" % [car_depth, suitable_segments.size()])
		
		if suitable_segments.is_empty():
			print("    ✗ No hay segmentos lo suficientemente largos")
			continue
		
		# Elegir un segmento adecuado aleatorio
		var spawn_data = suitable_segments[randi() % suitable_segments.size()]
		
		print("    Spawn path original: ", spawn_data["start"], " -> ", spawn_data["end"])
		
		# Calcular el subtramo válido del spawn path donde el auto cabe en el anillo
		var valid_spawn_path = _calculate_valid_subpath(spawn_data["start"], spawn_data["end"], car_width, car_height, car_depth, spawn_data["volume"])
		
		if valid_spawn_path != null:
			# Calcular el travel path completo (a través de todo el cilindro)
			var travel_path = _calculate_travel_path(spawn_data["original_start"], spawn_data["original_end"], car_width, car_height, car_depth, spawn_data["volume"])
			
			if travel_path != null:
				print("    ✓ AUTO SPAWNEADO EXITOSAMENTE")
				print("    Spawn path: ", valid_spawn_path["start"], " -> ", valid_spawn_path["end"])
				print("    Travel path: ", travel_path["start"], " -> ", travel_path["end"])
				
				# Crear y spawnear el auto
				var car = FlyingCar.new()
				car.width = car_width
				car.height = car_height
				car.depth = car_depth
				car.speed = car_speed
				car.car_color = archetype.get_random_color()
				
				world.add_child(car)
				# Posicionar el auto en el inicio del spawn path, pero darle el travel path completo
				car.global_position = valid_spawn_path["start"]
				car.set_path(travel_path["start"], travel_path["end"])
				
				return  # Spawn exitoso
			else:
				print("    ✗ No se pudo calcular travel path")
		else:
			print("    ✗ No se pudo encontrar un subtramo válido para spawn")
	
	print("FALLO: No se pudo spawnear después de ", max_attempts, " intentos")

func _can_car_fit_in_path(start: Vector3, end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary) -> bool:
	# Dirección del path
	var direction = (end - start).normalized()
	
	# Crear un basis orientado al path
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# 8 esquinas del auto en espacio local
	var half_extents = [
		Vector3(-car_width/2, -car_height/2, -car_depth/2),
		Vector3(car_width/2, -car_height/2, -car_depth/2),
		Vector3(-car_width/2, car_height/2, -car_depth/2),
		Vector3(car_width/2, car_height/2, -car_depth/2),
		Vector3(-car_width/2, -car_height/2, car_depth/2),
		Vector3(car_width/2, -car_height/2, car_depth/2),
		Vector3(-car_width/2, car_height/2, car_depth/2),
		Vector3(car_width/2, car_height/2, car_depth/2)
	]
	
	# Verificar múltiples puntos a lo largo del path
	var num_samples = 10
	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var pos = start.lerp(end, t)
		
		# Verificar las 8 esquinas del auto en esta posición
		for corner_idx in range(half_extents.size()):
			var corner_local = half_extents[corner_idx]
			# Transformar esquina a coordenadas globales
			var corner_global = pos + right * corner_local.x + up * corner_local.y + forward * corner_local.z
			
			# Verificar que está dentro del anillo
			var local_corner = global_transform.affine_inverse() * corner_global
			if not _is_point_in_ring(local_corner):
				print("      Fallo en anillo: sample=%d corner=%d" % [i, corner_idx])
				return false
			
			# Verificar que está dentro del lane volume
			if not _is_point_inside_lane_volume(corner_global, volume["start_plane_vertices"], volume["end_plane_vertices"]):
				print("      Fallo en lane volume: sample=%d corner=%d" % [i, corner_idx])
				return false
	
	return true

func _calculate_travel_path(original_start: Vector3, original_end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary):
	# El travel path es el segmento completo que cruza el cilindro exterior
	# (ignorando el cilindro interior, solo considerando outer_radius)
	
	var direction = (original_end - original_start).normalized()
	var path_length = original_start.distance_to(original_end)
	
	# Crear un basis orientado al path
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# 8 esquinas del auto en espacio local
	var half_extents = [
		Vector3(-car_width/2, -car_height/2, -car_depth/2),
		Vector3(car_width/2, -car_height/2, -car_depth/2),
		Vector3(-car_width/2, car_height/2, -car_depth/2),
		Vector3(car_width/2, car_height/2, -car_depth/2),
		Vector3(-car_width/2, -car_height/2, car_depth/2),
		Vector3(car_width/2, -car_height/2, car_depth/2),
		Vector3(-car_width/2, car_height/2, car_depth/2),
		Vector3(car_width/2, car_height/2, car_depth/2)
	]
	
	var valid_t_min = 0.0
	var valid_t_max = 1.0
	
	# Para cada esquina, calcular dónde está dentro del cilindro exterior
	for corner_local in half_extents:
		var corner_at_start = original_start + right * corner_local.x + up * corner_local.y + forward * corner_local.z
		var corner_direction = direction
		
		var local_corner_start = global_transform.affine_inverse() * corner_at_start
		var local_corner_direction = global_transform.affine_inverse().basis * corner_direction
		
		# Solo intersecciones con cilindro exterior
		var t_outer = _intersect_cylinder_parametric(local_corner_start, local_corner_direction, outer_radius, path_length)
		
		var corner_t_min = 0.0
		var corner_t_max = 1.0
		
		if t_outer.size() >= 2:
			corner_t_min = max(corner_t_min, t_outer[0])
			corner_t_max = min(corner_t_max, t_outer[1])
		elif t_outer.size() == 1:
			var test_t = clamp(0.5, corner_t_min, corner_t_max)
			var test_pos = local_corner_start + local_corner_direction * test_t * path_length
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null
		else:
			var test_pos = local_corner_start
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null
		
		# Verificar restricciones de altura
		var half_height = height / 2.0
		if abs(local_corner_direction.y) > 0.001:
			var t_bottom = (-half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			var t_top = (half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			
			var t_y_min = min(t_bottom, t_top)
			var t_y_max = max(t_bottom, t_top)
			
			corner_t_min = max(corner_t_min, t_y_min)
			corner_t_max = min(corner_t_max, t_y_max)
		else:
			if local_corner_start.y < -half_height or local_corner_start.y > half_height:
				return null
		
		valid_t_min = max(valid_t_min, corner_t_min)
		valid_t_max = min(valid_t_max, corner_t_max)
		
		if valid_t_min >= valid_t_max:
			return null
	
	var valid_start = original_start.lerp(original_end, valid_t_min)
	var valid_end = original_start.lerp(original_end, valid_t_max)
	
	# Verificar que esté dentro del lane volume
	for i in range(5):
		var t = float(i) / 4.0
		var sample_t = valid_t_min + (valid_t_max - valid_t_min) * t
		var sample_pos = original_start.lerp(original_end, sample_t)
		
		if not _is_point_inside_lane_volume(sample_pos, volume["start_plane_vertices"], volume["end_plane_vertices"]):
			return null
	
	return {
		"start": valid_start,
		"end": valid_end
	}

func _calculate_valid_subpath(start: Vector3, end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary):
	# Dirección del path
	var direction = (end - start).normalized()
	var path_length = start.distance_to(end)
	
	# Crear un basis orientado al path
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# 8 esquinas del auto en espacio local (relativo al centro del auto)
	var half_extents = [
		Vector3(-car_width/2, -car_height/2, -car_depth/2),
		Vector3(car_width/2, -car_height/2, -car_depth/2),
		Vector3(-car_width/2, car_height/2, -car_depth/2),
		Vector3(car_width/2, car_height/2, -car_depth/2),
		Vector3(-car_width/2, -car_height/2, car_depth/2),
		Vector3(car_width/2, -car_height/2, car_depth/2),
		Vector3(-car_width/2, car_height/2, car_depth/2),
		Vector3(car_width/2, car_height/2, car_depth/2)
	]
	
	# Para cada esquina, calcular el rango válido t donde está dentro del anillo
	var valid_t_min = 0.0
	var valid_t_max = 1.0
	
	for corner_local in half_extents:
		# Posición de la esquina cuando el auto está en t=0
		var corner_at_start = start + right * corner_local.x + up * corner_local.y + forward * corner_local.z
		
		# Dirección de la línea de esta esquina (paralela al path)
		var corner_direction = direction
		
		# Calcular intersecciones de esta línea con los cilindros
		var local_corner_start = global_transform.affine_inverse() * corner_at_start
		var local_corner_direction = global_transform.affine_inverse().basis * corner_direction
		
		# Intersecciones con cilindro exterior
		var t_outer = _intersect_cylinder_parametric(local_corner_start, local_corner_direction, outer_radius, path_length)
		
		# Intersecciones con cilindro interior
		var t_inner = _intersect_cylinder_parametric(local_corner_start, local_corner_direction, inner_radius, path_length)
		
		# Calcular rango válido para esta esquina (dentro del anillo)
		var corner_t_min = 0.0
		var corner_t_max = 1.0
		
		# Si intersecta con el cilindro exterior
		if t_outer.size() >= 2:
			# La esquina debe estar entre las dos intersecciones del outer cylinder
			corner_t_min = max(corner_t_min, t_outer[0])
			corner_t_max = min(corner_t_max, t_outer[1])
		elif t_outer.size() == 1:
			# Tangente - verificar si está dentro o fuera
			var test_t = clamp(0.5, corner_t_min, corner_t_max)
			var test_pos = local_corner_start + local_corner_direction * test_t * path_length
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null  # Completamente fuera
		else:
			# No intersecta - verificar si está completamente dentro o fuera
			var test_pos = local_corner_start
			var test_r = sqrt(test_pos.x * test_pos.x + test_pos.z * test_pos.z)
			if test_r > outer_radius:
				return null  # Completamente fuera del outer cylinder
		
		# Si intersecta con el cilindro interior
		if t_inner.size() >= 2:
			# La esquina NO debe estar entre las dos intersecciones del inner cylinder
			# Esto significa que el rango válido se divide en dos partes
			# Por simplicidad, tomamos solo el rango antes de entrar al cilindro interior
			# o después de salir
			if t_inner[1] < corner_t_max:
				# Hay espacio después de salir del inner cylinder
				corner_t_min = max(corner_t_min, t_inner[1])
			elif t_inner[0] > corner_t_min:
				# Hay espacio antes de entrar al inner cylinder
				corner_t_max = min(corner_t_max, t_inner[0])
			else:
				return null  # El inner cylinder bloquea todo el path
		
		# Verificar restricciones de altura
		var half_height = height / 2.0
		# Calcular t donde la esquina entra y sale del rango de altura
		if abs(local_corner_direction.y) > 0.001:
			var t_bottom = (-half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			var t_top = (half_height - local_corner_start.y) / (local_corner_direction.y * path_length)
			
			var t_y_min = min(t_bottom, t_top)
			var t_y_max = max(t_bottom, t_top)
			
			corner_t_min = max(corner_t_min, t_y_min)
			corner_t_max = min(corner_t_max, t_y_max)
		else:
			# Línea horizontal - verificar si está en rango
			if local_corner_start.y < -half_height or local_corner_start.y > half_height:
				return null
		
		# Actualizar el rango global válido (intersección de todos los rangos)
		valid_t_min = max(valid_t_min, corner_t_min)
		valid_t_max = min(valid_t_max, corner_t_max)
		
		# Si no hay rango válido, retornar null
		if valid_t_min >= valid_t_max:
			return null
	
	# Verificar que el subpath válido sea lo suficientemente largo para el auto
	var valid_length = (valid_t_max - valid_t_min) * path_length
	if valid_length < car_depth:
		print("      Subpath válido muy corto: %.2f < %.2f" % [valid_length, car_depth])
		return null
	
	# Calcular las posiciones start y end del subpath válido
	var valid_start = start.lerp(end, valid_t_min)
	var valid_end = start.lerp(end, valid_t_max)
	
	# Verificar que el subpath esté dentro del lane volume
	# Muestrear algunos puntos
	for i in range(5):
		var t = float(i) / 4.0
		var sample_t = valid_t_min + (valid_t_max - valid_t_min) * t
		var sample_pos = start.lerp(end, sample_t)
		
		if not _is_point_inside_lane_volume(sample_pos, volume["start_plane_vertices"], volume["end_plane_vertices"]):
			print("      Subpath sale del lane volume")
			return null
	
	return {
		"start": valid_start,
		"end": valid_end
	}

func _intersect_cylinder_parametric(origin: Vector3, direction: Vector3, radius: float, total_length: float) -> Array:
	# Similar a _intersect_cylinder pero retorna t en términos del path completo [0,1]
	var a = direction.x * direction.x + direction.z * direction.z
	var b = 2.0 * (origin.x * direction.x + origin.z * direction.z)
	var c = origin.x * origin.x + origin.z * origin.z - radius * radius
	
	# Línea vertical
	if abs(a) < 0.0001:
		return []
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return []
	
	if abs(discriminant) < 0.0001:
		# Una intersección (tangente)
		var t = (-b) / (2.0 * a)
		return [t / total_length]
	
	# Dos intersecciones
	var sqrt_disc = sqrt(discriminant)
	var t1 = (-b - sqrt_disc) / (2.0 * a)
	var t2 = (-b + sqrt_disc) / (2.0 * a)
	
	return [
		t1 / total_length,
		t2 / total_length
	]

func _is_point_inside_lane_volume(point: Vector3, plane1_verts: Array, plane2_verts: Array) -> bool:
	if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[1], plane1_verts[2], true):
		return false
	
	if not _is_point_on_correct_side(point, plane2_verts[3], plane2_verts[2], plane2_verts[1], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[0], plane2_verts[0], plane2_verts[1], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[3], plane1_verts[2], plane2_verts[2], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[3], plane2_verts[3], true):
		return false
	
	if not _is_point_on_correct_side(point, plane1_verts[1], plane2_verts[1], plane2_verts[2], true):
		return false
	
	return true

func _is_point_on_correct_side(point: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, inside: bool) -> bool:
	var normal = (v2 - v1).cross(v3 - v1).normalized()
	var to_point = point - v1
	var dot = normal.dot(to_point)
	
	return dot >= 0 if inside else dot <= 0

func _get_line_segments_in_ring(line_start: Vector3, line_end: Vector3) -> Array:
	# Convertir a coordenadas locales
	var local_start = global_transform.affine_inverse() * line_start
	var local_end = global_transform.affine_inverse() * line_end
	
	var half_height = height / 2.0
	var direction = local_end - local_start
	
	# Calcular intersecciones con cilindro exterior
	var t_outer = _intersect_cylinder(local_start, direction, outer_radius)
	
	# Calcular intersecciones con cilindro interior
	var t_inner = _intersect_cylinder(local_start, direction, inner_radius)
	
	# Recopilar todos los puntos de intersección relevantes
	var intersections = []
	
	# Añadir intersecciones con cilindro exterior
	for t in t_outer:
		if t >= 0.0 and t <= 1.0:
			var point = local_start + t * direction
			if point.y >= -half_height and point.y <= half_height:
				intersections.append({"t": t, "type": "outer"})
	
	# Añadir intersecciones con cilindro interior
	for t in t_inner:
		if t >= 0.0 and t <= 1.0:
			var point = local_start + t * direction
			if point.y >= -half_height and point.y <= half_height:
				intersections.append({"t": t, "type": "inner"})
	
	# Añadir extremos de la línea si están dentro del anillo
	if _is_point_in_ring(local_start):
		intersections.append({"t": 0.0, "type": "start"})
	if _is_point_in_ring(local_end):
		intersections.append({"t": 1.0, "type": "end"})
	
	# Ordenar por t
	intersections.sort_custom(func(a, b): return a["t"] < b["t"])
	
	# Construir segmentos que están dentro del anillo
	var segments_result = []
	var i = 0
	while i < intersections.size():
		var t1 = intersections[i]["t"]
		
		# Buscar el siguiente punto de intersección
		if i + 1 < intersections.size():
			var t2 = intersections[i + 1]["t"]
			var mid_t = (t1 + t2) / 2.0
			var mid_point = local_start + mid_t * direction
			
			# Verificar si el punto medio está en el anillo
			if _is_point_in_ring(mid_point):
				var global_p1 = global_transform * (local_start + t1 * direction)
				var global_p2 = global_transform * (local_start + t2 * direction)
				segments_result.append([global_p1, global_p2])
		
		i += 1
	
	return segments_result

func _intersect_cylinder(origin: Vector3, direction: Vector3, radius: float) -> Array:
	var a = direction.x * direction.x + direction.z * direction.z
	var b = 2.0 * (origin.x * direction.x + origin.z * direction.z)
	var c = origin.x * origin.x + origin.z * origin.z - radius * radius
	
	# Línea vertical
	if abs(a) < 0.0001:
		return []
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return []
	
	if abs(discriminant) < 0.0001:
		# Una intersección (tangente)
		return [(-b) / (2.0 * a)]
	
	# Dos intersecciones
	var sqrt_disc = sqrt(discriminant)
	return [
		(-b - sqrt_disc) / (2.0 * a),
		(-b + sqrt_disc) / (2.0 * a)
	]

func _is_point_in_ring(local_point: Vector3) -> bool:
	var half_height = height / 2.0
	var r = sqrt(local_point.x * local_point.x + local_point.z * local_point.z)
	return r >= inner_radius and r <= outer_radius and local_point.y >= -half_height and local_point.y <= half_height

func _create_grid_for_plane(plane_verts: Array, width_cells: int, height_cells: int) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			var bottom = plane_verts[0].lerp(plane_verts[1], u)
			var top = plane_verts[3].lerp(plane_verts[2], u)
			var point = bottom.lerp(top, v)
			
			var sphere = DebugUtil.create_debug_sphere(grid_point_color, grid_point_size)
			grid_points_container.add_child(sphere)
			sphere.global_position = point

func _refresh_debug_visualization() -> void:
	if debug_mesh:
		debug_mesh.queue_free()
	
	debug_mesh = DebugUtil.create_debug_ring_volume_wireframe(debug_color, outer_radius, inner_radius, height, segments)
	add_child(debug_mesh)
