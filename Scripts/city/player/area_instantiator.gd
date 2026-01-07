extends Node3D
class_name AreaInstantiator

@export var outer_radius: float = 40.0
@export var inner_radius: float = 20.5
@export var height: float = 5.5
@export var segments: int = 32
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

@export_group("Car Spawning")
@export var enable_car_spawning: bool = true
@export var spawn_interval: float = 0.1
@export_subgroup("Spawn Weights")
@export_range(0.0, 1.0) var car_weight: float = 0.7
@export_range(0.0, 1.0) var truck_weight: float = 0.1
@export_range(0.0, 1.0) var motorcycle_weight: float = 0.2

@export_group("Performance")
@export var update_interval: float = 0.5
@export var position_threshold: float = 0.5
@export var rotation_threshold: float = 0.5

var debug_mesh: Node3D
var city = null
var lane_volumes_container: Node3D
var grid_points_container: Node3D
var flow_arrows_container: Node3D
var destruction_area: Area3D

var cached_volumes: Array = []
var cached_position: Vector3 = Vector3.ZERO
var cached_rotation: Vector3 = Vector3.ZERO
var update_timer: float = 0.0
var spawn_timer: float = 0.0

var valid_spawn_segments: Array = []

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	_create_destruction_area()
	
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
			
			if show_debug:
				_refresh_debug_visualization()
			
			var volumes = city.get_lane_volumes_in_cylindrical_area(
				global_position,
				outer_radius,
				height
			)
			
			if show_flow_arrows and flow_arrows_container:
				_update_flow_arrows(volumes)
			
			if _volumes_changed(volumes):
				cached_volumes = volumes
				
				if show_lane_volumes and lane_volumes_container:
					_update_lane_volumes(volumes)
				
				if show_grid_points and grid_points_container:
					_update_grid_points(volumes)
	
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
	
	var visualized_volumes: Dictionary = {}
	
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
	
	if show_continuations:
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				if cont_key in visualized_volumes:
					continue
				
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
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
	
	var visualized_volumes: Dictionary = {}
	
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		visualized_volumes[key] = true
		
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_grid_for_plane(vol["start_plane_vertices"], effective_width, effective_height)
		_create_grid_for_plane(vol["end_plane_vertices"], effective_width, effective_height)
	
	if show_continuations and city:
		var gen = city.get_generator()
		if gen == null:
			return
		
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				if cont_key in visualized_volumes:
					continue
				
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
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
	
	valid_spawn_segments.clear()
	
	var visualized_volumes: Dictionary = {}
	
	for vol in volumes:
		var key = "%d_%d" % [vol["face_idx"], vol["edge_idx"]]
		visualized_volumes[key] = true
		
		var width_cells = vol.get("width_cells", 3)
		var height_cells = vol.get("height_cells", 10)
		
		var effective_width = width_cells * granularity
		var effective_height = height_cells * granularity
		
		_create_flow_arrows_for_volume(vol["start_plane_vertices"], vol["end_plane_vertices"], effective_width, effective_height, vol)
	
	if show_continuations and city:
		var gen = city.get_generator()
		if gen == null:
			return
		
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		for vol in volumes:
			var continuations = city.get_lane_volume_continuations(vol["face_idx"], vol["edge_idx"])
			
			for cont in continuations:
				var cont_key = "%d_%d" % [cont["face_idx"], cont["edge_idx"]]
				
				if cont_key in visualized_volumes:
					continue
				
				var cont_block = city.get_block_grid(cont["face_idx"])
				if cont_block == null:
					continue
				
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
			
			var bottom_start = start_plane[0].lerp(start_plane[1], u)
			var top_start = start_plane[3].lerp(start_plane[2], u)
			var point_start = bottom_start.lerp(top_start, v)
			
			var bottom_end = end_plane[0].lerp(end_plane[1], u)
			var top_end = end_plane[3].lerp(end_plane[2], u)
			var point_end = bottom_end.lerp(top_end, v)
			
			var segments_array = GeometryUtils.clip_line_to_ring_volume(
				point_start, 
				point_end, 
				global_transform, 
				inner_radius, 
				outer_radius, 
				height
			)
			
			for segment in segments_array:
				var arrow = DebugUtil.create_debug_arrow_to_from(segment[0], segment[1], flow_arrow_color, flow_arrow_width)
				flow_arrows_container.add_child(arrow)
				
				# Guardar información de celda (coordenadas u, v en la grilla)
				valid_spawn_segments.append({
					"start": segment[0],
					"end": segment[1],
					"original_start": point_start,
					"original_end": point_end,
					"volume": volume,
					"grid_u": u,  # Coordenada horizontal en la grilla
					"grid_v": v,  # Coordenada vertical en la grilla
					"width_cells": width_cells,
					"height_cells": height_cells
				})

# ============================================================================
# NUEVO SISTEMA DE VALIDACIÓN POR PROYECCIÓN DE EDGES FRONTALES
# ============================================================================

func _try_spawn_car() -> void:
	if valid_spawn_segments.is_empty() or not world:
		return
	
	var max_attempts = 10
	for attempt in range(max_attempts):
		print("\n=== INTENTO DE SPAWN %d/%d ===" % [attempt + 1, max_attempts])
		
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
		
		print("Arquetipo: %s | Dims: w=%.2f h=%.2f d=%.2f" % [archetype.name, car_width, car_height, car_depth])
		
		# Filtrar segmentos adecuados
		var suitable_segments = []
		for seg_data in valid_spawn_segments:
			var seg_length = seg_data["start"].distance_to(seg_data["end"])
			if seg_length >= car_depth:
				suitable_segments.append(seg_data)
		
		print("Segmentos disponibles: %d" % suitable_segments.size())
		
		if suitable_segments.is_empty():
			print("  ✗ No hay segmentos adecuados")
			continue
		
		var base_spawn_data = suitable_segments[randi() % suitable_segments.size()]
		print("Segmento elegido: u=%.3f v=%.3f" % [base_spawn_data["grid_u"], base_spawn_data["grid_v"]])
		
		# Intentar validación con hasta 5 carriles alternativos
		var validation_result = _validate_and_find_alternative(
			base_spawn_data, 
			car_width, 
			car_height, 
			car_depth
		)
		
		if validation_result != null:
			var full_path_length = validation_result["original_start"].distance_to(validation_result["original_end"])
			var distance_to_spawn = validation_result["original_start"].distance_to(validation_result["spawn_pos"])
			var initial_progress = distance_to_spawn / full_path_length if full_path_length > 0 else 0.0
			
			print("  ✓ SPAWN EXITOSO en progreso %.1f%%" % (initial_progress * 100.0))
			
			var car = FlyingCar.new()
			car.width = car_width
			car.height = car_height
			car.depth = car_depth
			car.speed = car_speed
			car.car_color = archetype.get_random_color()
			car.world_node = world
			
			world.add_child(car)
			car.set_path(validation_result["original_start"], validation_result["original_end"], initial_progress)
			return
		else:
			print("  ✗ Validación falló después de 5 reintentos")

# Valida un spawn y busca alternativas si falla
func _validate_and_find_alternative(spawn_data: Dictionary, car_width: float, car_height: float, car_depth: float) -> Variant:
	var current_u = spawn_data["grid_u"]
	var current_v = spawn_data["grid_v"]
	
	print("  >> Iniciando validación en u=%.3f v=%.3f" % [current_u, current_v])
	
	for retry in range(5):
		print("    [Reintento %d/5] Testing u=%.3f v=%.3f" % [retry + 1, current_u, current_v])
		
		var test_spawn = _find_spawn_at_grid_coords(
			spawn_data["volume"],
			current_u,
			current_v,
			spawn_data["width_cells"],
			spawn_data["height_cells"]
		)
		
		if test_spawn == null:
			print("      ✗ No se pudo encontrar spawn en estas coordenadas")
			return null
		
		var validation = _validate_car_front_projection(
			test_spawn["original_start"],
			test_spawn["original_end"],
			test_spawn["start"],
			car_width,
			car_height,
			car_depth,
			spawn_data["volume"]
		)
		
		if validation["valid"]:
			print("      ✓ Validación EXITOSA")
			return {
				"spawn_pos": test_spawn["start"],
				"original_start": test_spawn["original_start"],
				"original_end": test_spawn["original_end"]
			}
		
		print("      ✗ Colisión detectada con plano: %s" % validation["collision_plane"])
		
		# Si falló, moverse una celda lejos del plano que chocó
		var collision_plane = validation["collision_plane"]
		if collision_plane == "left":
			current_u = min(current_u + (1.0 / spawn_data["width_cells"]), 1.0)
			print("        → Moviendo a la DERECHA: u=%.3f" % current_u)
		elif collision_plane == "right":
			current_u = max(current_u - (1.0 / spawn_data["width_cells"]), 0.0)
			print("        → Moviendo a la IZQUIERDA: u=%.3f" % current_u)
		elif collision_plane == "bottom":
			current_v = min(current_v + (1.0 / spawn_data["height_cells"]), 1.0)
			print("        → Moviendo ARRIBA: v=%.3f" % current_v)
		elif collision_plane == "top":
			current_v = max(current_v - (1.0 / spawn_data["height_cells"]), 0.0)
			print("        → Moviendo ABAJO: v=%.3f" % current_v)
		else:
			# Si no se identificó el plano, intentar dirección aleatoria
			if randf() > 0.5:
				current_u += (randf() - 0.5) * (2.0 / spawn_data["width_cells"])
			else:
				current_v += (randf() - 0.5) * (2.0 / spawn_data["height_cells"])
			current_u = clamp(current_u, 0.0, 1.0)
			current_v = clamp(current_v, 0.0, 1.0)
			print("        → Movimiento ALEATORIO: u=%.3f v=%.3f" % [current_u, current_v])
	
	print("      ✗ Agotados los 5 reintentos")
	return null

# Encuentra un punto de spawn en coordenadas de grilla específicas
func _find_spawn_at_grid_coords(volume: Dictionary, u: float, v: float, width_cells: int, height_cells: int) -> Variant:
	var start_plane = volume["start_plane_vertices"]
	var end_plane = volume["end_plane_vertices"]
	
	var bottom_start = start_plane[0].lerp(start_plane[1], u)
	var top_start = start_plane[3].lerp(start_plane[2], u)
	var point_start = bottom_start.lerp(top_start, v)
	
	var bottom_end = end_plane[0].lerp(end_plane[1], u)
	var top_end = end_plane[3].lerp(end_plane[2], u)
	var point_end = bottom_end.lerp(top_end, v)
	
	var segments_array = GeometryUtils.clip_line_to_ring_volume(
		point_start, 
		point_end, 
		global_transform, 
		inner_radius, 
		outer_radius, 
		height
	)
	
	if segments_array.is_empty():
		return null
	
	return {
		"start": segments_array[0][0],
		"end": segments_array[0][1],
		"original_start": point_start,
		"original_end": point_end
	}

# Valida proyectando los 4 edges de la cara frontal a lo largo del path
func _validate_car_front_projection(original_start: Vector3, original_end: Vector3, spawn_pos: Vector3, 
									car_width: float, car_height: float, car_depth: float, 
									volume: Dictionary) -> Dictionary:
	
	print("        >> Validando proyección frontal")
	print("           Spawn: %s" % spawn_pos)
	print("           Path: %s -> %s" % [original_start, original_end])
	print("           Dimensiones auto: w=%.2f h=%.2f d=%.2f" % [car_width, car_height, car_depth])
	
	# Calcular orientación del auto
	var direction = (original_end - original_start).normalized()
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	print("           Orientación: forward=%s right=%s up=%s" % [forward, right, up])
	
	# Los 4 vértices de la cara frontal del auto (centrados en spawn_pos)
	var front_corners = [
		spawn_pos + right * (-car_width/2) + up * (-car_height/2),  # bottom-left
		spawn_pos + right * (car_width/2) + up * (-car_height/2),   # bottom-right
		spawn_pos + right * (car_width/2) + up * (car_height/2),    # top-right
		spawn_pos + right * (-car_width/2) + up * (car_height/2)    # top-left
	]
	
	print("           Vértices cara frontal:")
	for i in range(front_corners.size()):
		print("             [%d] %s" % [i, front_corners[i]])
	
	# NUEVA VALIDACIÓN: Verificar que todos los vértices iniciales estén dentro del lane volume
	print("           >> Verificando vértices iniciales dentro del volumen...")
	var start_plane = volume["start_plane_vertices"]
	var end_plane = volume["end_plane_vertices"]
	
	for i in range(front_corners.size()):
		var corner = front_corners[i]
		if not GeometryUtils.is_point_inside_lane_volume(corner, start_plane, end_plane):
			print("             ✗✗✗ VÉRTICE [%d] FUERA DEL VOLUMEN ✗✗✗" % i)
			print("             Posición: %s" % corner)
			
			# Determinar qué plano lateral está más cerca para reportar la colisión
			var lateral_planes = _get_lane_volume_lateral_planes(volume)
			var closest_plane_name = ""
			var min_distance = INF
			
			for plane_name in lateral_planes.keys():
				var plane = lateral_planes[plane_name]
				var distance = abs(plane[0].dot(corner - plane[1]))
				if distance < min_distance:
					min_distance = distance
					closest_plane_name = plane_name
			
			print("             Plano más cercano: %s (distancia: %.3f)" % [closest_plane_name, min_distance])
			
			return {
				"valid": false,
				"collision_plane": closest_plane_name,
				"collision_point": corner,
				"collision_t": 0.0  # Colisión en posición inicial
			}
	
	print("           ✓ Todos los vértices iniciales dentro del volumen")
	
	# Los 4 edges de la cara frontal
	var front_edges = [
		[front_corners[0], front_corners[1]],  # bottom edge
		[front_corners[1], front_corners[2]],  # right edge
		[front_corners[2], front_corners[3]],  # top edge
		[front_corners[3], front_corners[0]]   # left edge
	]
	
	var edge_names = ["bottom", "right", "top", "left"]
	
	# Calcular los 4 planos laterales del lane volume
	var lateral_planes = _get_lane_volume_lateral_planes(volume)
	
	print("           Planos laterales del lane volume:")
	for plane_name in lateral_planes.keys():
		var plane = lateral_planes[plane_name]
		print("             %s: normal=%s point=%s" % [plane_name, plane[0], plane[1]])
	
	# Proyectar cada edge a lo largo del path completo
	for edge_idx in range(front_edges.size()):
		var edge = front_edges[edge_idx]
		print("           Testeando edge %s..." % edge_names[edge_idx])
		
		# Proyectar ambos vértices del edge desde spawn_pos hasta original_end
		for vert_idx in range(2):
			var vertex_start = edge[vert_idx]
			var offset_from_spawn = vertex_start - spawn_pos
			var vertex_end = original_end + offset_from_spawn
			
			print("             Vértice %d: %s -> %s" % [vert_idx, vertex_start, vertex_end])
			
			# Probar intersección con cada plano lateral
			for plane_name in lateral_planes.keys():
				var plane = lateral_planes[plane_name]
				var intersection = _ray_plane_intersection(vertex_start, vertex_end - vertex_start, plane)
				
				if intersection != null:
					# Verificar que la intersección esté dentro del segmento
					var segment_length = vertex_start.distance_to(vertex_end)
					var t = vertex_start.distance_to(intersection) / segment_length if segment_length > 0 else 0.0
					
					print("               Intersección con plano %s en t=%.3f pos=%s" % [plane_name, t, intersection])
					
					if t >= 0.0 and t <= 1.0:
						print("               ✗✗✗ COLISIÓN DETECTADA ✗✗✗")
						return {
							"valid": false,
							"collision_plane": plane_name,
							"collision_point": intersection,
							"collision_t": t
						}
	
	print("           ✓ Sin colisiones detectadas")
	return {"valid": true, "collision_plane": ""}

# Calcula los 4 planos laterales que conectan start_plane con end_plane
func _get_lane_volume_lateral_planes(volume: Dictionary) -> Dictionary:
	var start = volume["start_plane_vertices"]
	var end = volume["end_plane_vertices"]
	
	# Cada plano se define por 3 puntos (o normal + punto)
	# Plano inferior: start[0]-start[1]-end[1]-end[0]
	# Plano derecho: start[1]-start[2]-end[2]-end[1]
	# Plano superior: start[2]-start[3]-end[3]-end[2]
	# Plano izquierdo: start[3]-start[0]-end[0]-end[3]
	
	return {
		"bottom": _plane_from_points(start[0], start[1], end[1]),
		"right": _plane_from_points(start[1], start[2], end[2]),
		"top": _plane_from_points(start[2], start[3], end[3]),
		"left": _plane_from_points(start[3], start[0], end[0])
	}

# Crea un plano a partir de 3 puntos (devuelve [normal, point])
func _plane_from_points(p1: Vector3, p2: Vector3, p3: Vector3) -> Array:
	var v1 = p2 - p1
	var v2 = p3 - p1
	var normal = v1.cross(v2).normalized()
	return [normal, p1]

# Calcula intersección ray-plano, retorna punto o null
func _ray_plane_intersection(ray_origin: Vector3, ray_direction: Vector3, plane: Array) -> Variant:
	var plane_normal = plane[0]
	var plane_point = plane[1]
	
	var denom = plane_normal.dot(ray_direction)
	if abs(denom) < 0.0001:  # Ray paralelo al plano
		return null
	
	var t = plane_normal.dot(plane_point - ray_origin) / denom
	if t < 0:  # Intersección detrás del origen del ray
		return null
	
	return ray_origin + ray_direction * t

# ============================================================================
# FUNCIONES OBSOLETAS (mantenidas por compatibilidad temporal)
# ============================================================================

func _can_car_fit_in_path(start: Vector3, end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary) -> bool:
	# Esta función ya no se usa pero se mantiene temporalmente
	return false

func _calculate_travel_path(original_start: Vector3, original_end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary) -> Variant:
	# Esta función ya no se usa pero se mantiene temporalmente
	return null

func _calculate_valid_subpath(start: Vector3, end: Vector3, car_width: float, car_height: float, car_depth: float, volume: Dictionary) -> Variant:
	# Esta función ya no se usa pero se mantiene temporalmente
	return null

# ============================================================================
# FUNCIONES DE VISUALIZACIÓN (sin cambios)
# ============================================================================

func _create_grid_for_plane(plane_verts: Array, width_cells: int, height_cells: int) -> void:
	for i in range(width_cells + 1):
		for j in range(height_cells + 1):
			var u = float(i) / float(width_cells)
			var v = float(j) / float(height_cells)
			
			var bottom = plane_verts[0].lerp(plane_verts[1], u)
			var top = plane_verts[3].lerp(plane_verts[2], u)
			var point = bottom.lerp(top, v)
			
			var grid_coords = Vector2i(i, j)
			var sphere = DebugUtil.create_debug_sphere_print(grid_coords, grid_point_color, grid_point_size)
			sphere.set_meta("grid_coords", grid_coords)
			sphere.set_meta("world_position", point)
			grid_points_container.add_child(sphere)
			sphere.global_position = point

func _refresh_debug_visualization() -> void:
	if debug_mesh:
		debug_mesh.queue_free()
	
	debug_mesh = DebugUtil.create_debug_ring_volume_wireframe(debug_color, outer_radius, inner_radius, height, segments)
	add_child(debug_mesh)
