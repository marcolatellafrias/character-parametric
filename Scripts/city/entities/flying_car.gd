extends Node3D
class_name FlyingCar

@export var width: float = 2.0
@export var height: float = 1.0
@export var depth: float = 4.0
@export var car_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var speed: float = 10.0
@export var show_path_debug: bool = true
@export var path_debug_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var path_debug_width: float = 0.05
@export var path_debug_segments: int = 20
@export var show_continuation_paths: bool = true
@export var continuation_exact_color: Color = Color(0.0, 1.0, 0.0, 1.0)  # Verde para coordenadas exactas
@export var continuation_adjusted_color: Color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan para coordenadas ajustadas
@export var show_continuation_front_planes: bool = true  # Mostrar planos frontales del auto en continuaciones

var mesh_instance: MeshInstance3D
var path_debug_mesh: MeshInstance3D
var continuation_paths_container: Node3D
var main_path_front_planes: Array = []  # Planos frontales del path principal
var detection_area: Area3D
var path_3d: Path3D
var path_follow: PathFollow3D
var has_path: bool = false
var world_node: Node3D
var city = null

# Datos para visualización de continuaciones
var spawn_grid_u: float = 0.0
var spawn_grid_v: float = 0.0
var spawn_volume: Dictionary = {}
var spawn_width_cells: int = 3
var spawn_height_cells: int = 10

func _ready() -> void:
	_create_visual()
	_create_detection_area()

func _process(delta: float) -> void:
	if has_path and path_follow:
		path_follow.progress += delta * speed
		
		# Sincronizar posición global con PathFollow3D
		global_position = path_follow.global_position
		global_rotation = path_follow.global_rotation

func _exit_tree() -> void:
	print("\n=== FLYINGCAR EXIT_TREE (limpiando) ===")
	
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		print("  Limpiando path_debug_mesh...")
		path_debug_mesh.queue_free()
	
	# Limpiar planos frontales principales
	if main_path_front_planes.size() > 0:
		print("  Limpiando %d planos frontales principales..." % main_path_front_planes.size())
		for plane in main_path_front_planes:
			if is_instance_valid(plane):
				plane.queue_free()
		main_path_front_planes.clear()
	
	if continuation_paths_container and is_instance_valid(continuation_paths_container):
		print("  Limpiando continuation_paths_container con %d hijos..." % continuation_paths_container.get_child_count())
		continuation_paths_container.queue_free()
	
	if path_3d and is_instance_valid(path_3d):
		print("  Limpiando path_3d...")
		path_3d.queue_free()
	
	print("  ✓ Limpieza completada")

func _create_visual() -> void:
	mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mesh_instance.mesh = box
	
	var material := StandardMaterial3D.new()
	material.albedo_color = car_color
	mesh_instance.material_override = material
	
	add_child(mesh_instance)

func _create_detection_area() -> void:
	detection_area = Area3D.new()
	detection_area.collision_layer = 1
	detection_area.collision_mask = 0
	detection_area.monitorable = true
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.5
	collision_shape.shape = sphere_shape
	
	detection_area.add_child(collision_shape)
	add_child(detection_area)

func set_path(start: Vector3, end: Vector3, initial_progress: float = 0.0, 
			  grid_u: float = 0.0, grid_v: float = 0.0, 
			  volume: Dictionary = {}, width_cells: int = 3, height_cells: int = 10) -> void:
	
	print("\n=== FLYINGCAR SET_PATH ===")
	print("Start: %s" % start)
	print("End: %s" % end)
	print("Grid coords: u=%.3f v=%.3f" % [grid_u, grid_v])
	print("Volume keys: %s" % str(volume.keys()))
	print("Width/Height cells: %d/%d" % [width_cells, height_cells])
	print("World node: %s" % ("SI" if world_node else "NO"))
	print("City: %s" % ("SI" if city else "NO"))
	print("Show continuation paths: %s" % show_continuation_paths)
	
	# Guardar datos para continuaciones
	spawn_grid_u = grid_u
	spawn_grid_v = grid_v
	spawn_volume = volume
	spawn_width_cells = width_cells
	spawn_height_cells = height_cells
	
	# Crear Path3D y Curve3D
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	
	# Agregar puntos a la curva (línea recta)
	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, Vector3.ZERO)
	
	path_3d.curve = curve
	
	# El Path3D va al world, no como hijo del auto
	if world_node:
		world_node.add_child(path_3d)
	else:
		get_parent().add_child(path_3d)
	
	# Crear PathFollow3D
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	# Establecer progreso inicial
	var curve_length = curve.get_baked_length()
	path_follow.progress = initial_progress * curve_length
	
	# Posicionar el auto en el progreso inicial
	global_position = path_follow.global_position
	global_rotation = path_follow.global_rotation
	
	has_path = true
	
	# Visualizar el path principal
	if show_path_debug and world_node:
		var points = [
			{"pos": start, "in": Vector3.ZERO, "out": Vector3.ZERO},
			{"pos": end, "in": Vector3.ZERO, "out": Vector3.ZERO}
		]
		
		path_debug_mesh = DebugUtil.create_debug_path3d(
			points,
			path_debug_segments,
			path_debug_color,
			path_debug_width
		)
		world_node.add_child(path_debug_mesh)
		
		# Visualizar planos frontales del path principal
		if show_continuation_front_planes:
			print("  Visualizando planos frontales del path PRINCIPAL...")
			_visualize_main_path_front_planes(start, end)
	
	# Visualizar paths de continuación
	if show_continuation_paths and city and not volume.is_empty():
		_create_continuation_visualizations()
	
	# Timer para verificar si llegó al final
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_check_path_complete)
	add_child(timer)
	timer.start()

func _create_continuation_visualizations() -> void:
	print("\n=== _CREATE_CONTINUATION_VISUALIZATIONS ===")
	
	if not world_node:
		print("✗ world_node no disponible")
		return
	
	print("✓ world_node disponible")
	
	# Limpiar contenedor anterior si existe
	if continuation_paths_container and is_instance_valid(continuation_paths_container):
		print("⚠ Limpiando contenedor anterior...")
		continuation_paths_container.queue_free()
	
	# Crear contenedor para paths de continuación
	continuation_paths_container = Node3D.new()
	continuation_paths_container.name = "ContinuationPaths_" + str(get_instance_id())
	world_node.add_child(continuation_paths_container)
	print("✓ Contenedor creado y agregado: %s" % continuation_paths_container.name)
	print("  Parent: %s" % continuation_paths_container.get_parent().name)
	
	# Obtener continuaciones del volumen actual
	var face_idx = spawn_volume.get("face_idx", -1)
	var edge_idx = spawn_volume.get("edge_idx", -1)
	
	print("Face idx: %d" % face_idx)
	print("Edge idx: %d" % edge_idx)
	
	if face_idx == -1 or edge_idx == -1:
		print("✗ Face o edge idx inválidos")
		return
	
	if not city:
		print("✗ City no disponible")
		return
	
	print("✓ City disponible, llamando a get_lane_volume_continuations...")
	
	var continuations = city.get_lane_volume_continuations(face_idx, edge_idx)
	
	print("\n=== VISUALIZANDO CONTINUACIONES ===")
	print("Volumen actual: face=%d edge=%d" % [face_idx, edge_idx])
	print("Coordenadas spawn: u=%.3f v=%.3f" % [spawn_grid_u, spawn_grid_v])
	print("Continuaciones encontradas: %d" % continuations.size())
	
	for cont in continuations:
		var cont_face = cont["face_idx"]
		var cont_edge = cont["edge_idx"]
		
		print("\n  >> Procesando continuación: face=%d edge=%d" % [cont_face, cont_edge])
		
		var cont_block = city.get_block_grid(cont_face)
		if cont_block == null:
			print("    ✗ Block no encontrado")
			continue
		
		print("    ✓ Block encontrado")
		
		var cont_volume_data = cont_block.get_edge_lane_volume(cont_edge)
		if cont_volume_data.is_empty():
			print("    ✗ Volumen vacío")
			continue
		
		print("    ✓ Volumen obtenido, keys: %s" % str(cont_volume_data.keys()))
		
		# Calcular dimensiones del volumen de continuación
		var gen = city.get_generator()
		if gen == null:
			print("    ✗ Generador no disponible")
			continue
		
		print("    ✓ Generador disponible")
		
		var cont_width_cells = BlockGenerator.STREET_HALF_WIDTH_CELLS.get(cont_volume_data.get("street_type", 0), 3)
		var cont_height_cells = 0
		
		var city_block_cell_height = gen.block_cell_height
		var city_cells_per_floor = gen.cells_per_floor
		
		print("    City params: cell_height=%.2f cells_per_floor=%d" % [city_block_cell_height, city_cells_per_floor])
		
		if city_block_cell_height > 0 and city_cells_per_floor > 0:
			var floor_height = city_cells_per_floor * city_block_cell_height
			var num_floors = ceil(cont_volume_data["height"] / floor_height)
			cont_height_cells = int(num_floors * city_cells_per_floor)
		
		print("    Dimensiones continuación: width_cells=%d height_cells=%d" % [cont_width_cells, cont_height_cells])
		
		# Intentar encontrar camino en las mismas coordenadas
		print("    Llamando a _find_continuation_path...")
		var path_result = _find_continuation_path(
			cont_volume_data,
			spawn_grid_u,
			spawn_grid_v,
			cont_width_cells,
			cont_height_cells
		)
		
		if path_result != null:
			var path_color = continuation_exact_color if path_result["exact_coords"] else continuation_adjusted_color
			var coord_type = "EXACTAS" if path_result["exact_coords"] else "AJUSTADAS"
			
			print("    ✓ Path encontrado con coordenadas %s: u=%.3f v=%.3f" % [coord_type, path_result["u"], path_result["v"]])
			print("    Path start: %s" % path_result["start"])
			print("    Path end: %s" % path_result["end"])
			print("    Color: %s" % path_color)
			
			var points = [
				{"pos": path_result["start"], "in": Vector3.ZERO, "out": Vector3.ZERO},
				{"pos": path_result["end"], "in": Vector3.ZERO, "out": Vector3.ZERO}
			]
			
			print("    Creando debug path3d...")
			var path_mesh = DebugUtil.create_debug_path3d(
				points,
				path_debug_segments,
				path_color,
				path_debug_width
			)
			
			if path_mesh:
				print("    ✓ Path mesh creado, agregando a contenedor...")
				continuation_paths_container.add_child(path_mesh)
				print("    ✓ Path mesh agregado exitosamente")
			else:
				print("    ✗ create_debug_path3d retornó null")
			
			# Visualizar planos frontales del auto en start y end
			if show_continuation_front_planes:
				print("    Creando visualización de planos frontales...")
				_visualize_car_front_planes(
					path_result["start"],
					path_result["end"],
					path_color
				)
		else:
			print("    ✗ No se pudo encontrar path válido")
	
	print("\n✓ Procesamiento de continuaciones completado.")
	print("  Total meshes en contenedor: %d" % continuation_paths_container.get_child_count())

func _find_continuation_path(volume: Dictionary, target_u: float, target_v: float, 
							  width_cells: int, height_cells: int) -> Variant:
	
	print("      >> _find_continuation_path: target u=%.3f v=%.3f" % [target_u, target_v])
	print("         Volumen original: spawn_width_cells=%d spawn_height_cells=%d" % [spawn_width_cells, spawn_height_cells])
	print("         Volumen continuación: width_cells=%d height_cells=%d" % [width_cells, height_cells])
	
	# Convertir coordenadas normalizadas a índices de CELDA discretos (no vértices)
	# Las celdas van de 0 a width_cells-1
	var original_cell_x = floor(target_u * spawn_width_cells)
	var original_cell_y = floor(target_v * spawn_height_cells)
	
	print("         Celda original (discreta): x=%d y=%d" % [original_cell_x, original_cell_y])
	
	# Clampear a las celdas válidas del volumen de continuación
	var continuation_cell_x = clamp(original_cell_x, 0, width_cells - 1)
	var continuation_cell_y = clamp(original_cell_y, 0, height_cells - 1)
	
	var exact_coords = (continuation_cell_x == original_cell_x and continuation_cell_y == original_cell_y)
	
	if not exact_coords:
		print("         ⚠ Celdas ajustadas: (%d,%d) -> (%d,%d)" % [original_cell_x, original_cell_y, continuation_cell_x, continuation_cell_y])
	
	# Convertir índice de celda al índice de vértice de la grilla
	# Para usar el centro de la celda, sumamos 0.5
	# Pero para que coincida con los puntos de la grilla, usamos el índice de vértice correspondiente
	# Los vértices van de 0 a width_cells (inclusive)
	# Para una celda X, sus vértices son X y X+1
	# Usamos el vértice inicial de la celda
	var grid_index_u = continuation_cell_x
	var grid_index_v = continuation_cell_y
	
	# Convertir índice de vértice a coordenada normalizada
	var adjusted_u = float(grid_index_u) / float(width_cells)
	var adjusted_v = float(grid_index_v) / float(height_cells)
	
	print("         Índices de grilla continuación: u_idx=%d v_idx=%d" % [grid_index_u, grid_index_v])
	print("         Coordenadas normalizadas continuación: u=%.3f v=%.3f" % [adjusted_u, adjusted_v])
	print("         Coordenadas exactas: %s" % ("SI" if exact_coords else "NO"))
	
	# Intentar con las coordenadas ajustadas
	var path = _try_path_at_coords(volume, adjusted_u, adjusted_v, width_cells, height_cells)
	
	if path != null:
		path["exact_coords"] = exact_coords
		if exact_coords:
			print("      ✓ Path encontrado con coordenadas EXACTAS (verde)")
		else:
			print("      ✓ Path encontrado con coordenadas AJUSTADAS (cyan)")
		return path
	
	print("      ✗ No se pudo encontrar path válido")
	return null

func _try_path_at_coords(volume: Dictionary, u: float, v: float, 
						  width_cells: int, height_cells: int) -> Variant:
	
	var start_plane = volume["start_plane_vertices"]
	var end_plane = volume["end_plane_vertices"]
	
	# Calcular puntos en las coordenadas dadas
	var bottom_start = start_plane[0].lerp(start_plane[1], u)
	var top_start = start_plane[3].lerp(start_plane[2], u)
	var point_start = bottom_start.lerp(top_start, v)
	
	var bottom_end = end_plane[0].lerp(end_plane[1], u)
	var top_end = end_plane[3].lerp(end_plane[2], u)
	var point_end = bottom_end.lerp(top_end, v)
	
	print("        Point start: %s" % point_start)
	print("        Point end: %s" % point_end)
	
	# Validar que el auto cabe en este path
	var validation = _validate_car_in_continuation(
		point_start,
		point_end,
		volume
	)
	
	if not validation["valid"]:
		return null
	
	return {
		"start": point_start,
		"end": point_end,
		"u": u,
		"v": v
	}

func _validate_car_in_continuation(start: Vector3, end: Vector3, volume: Dictionary) -> Dictionary:
	# VALIDACIÓN TEMPORALMENTE DESACTIVADA PARA DEBUG
	print("        >> Validación DESACTIVADA (retorna siempre true)")
	return {"valid": true}
	
	print("        >> Validando continuación: start=%s end=%s" % [start, end])
	print("           Dimensiones auto: w=%.2f h=%.2f d=%.2f" % [width, height, depth])
	
	# Calcular orientación
	var direction = (end - start).normalized()
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# Vértices de la cara frontal
	var front_corners = [
		start + right * (-width/2) + up * (-height/2),
		start + right * (width/2) + up * (-height/2),
		start + right * (width/2) + up * (height/2),
		start + right * (-width/2) + up * (height/2)
	]
	
	print("           Vértices frontales:")
	for i in range(front_corners.size()):
		print("             [%d] %s" % [i, front_corners[i]])
	
	# Verificar que todos los vértices estén dentro del volumen
	var start_plane = volume["start_plane_vertices"]
	var end_plane = volume["end_plane_vertices"]
	
	print("           Start plane: %s" % start_plane)
	print("           End plane: %s" % end_plane)
	
	for i in range(front_corners.size()):
		var corner = front_corners[i]
		var inside = GeometryUtils.is_point_inside_lane_volume(corner, start_plane, end_plane)
		print("           Vértice [%d] inside=%s" % [i, inside])
		if not inside:
			return {"valid": false, "reason": "vertex_%d_outside" % i}
	
	print("           ✓ VALIDACIÓN EXITOSA - Todos los vértices dentro del volumen")
	
	# NOTA: Para visualización, solo verificamos que los vértices iniciales estén dentro
	# No hacemos la validación completa de proyección que se usa en el spawn
	return {"valid": true}

func _visualize_main_path_front_planes(start: Vector3, end: Vector3) -> void:
	if not world_node:
		return
	
	# Calcular orientación del auto
	var direction = (end - start).normalized()
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# Calcular los 4 vértices de la cara frontal en START
	var front_corners_start = [
		start + right * (-width/2) + up * (-height/2),  # bottom-left
		start + right * (width/2) + up * (-height/2),   # bottom-right
		start + right * (width/2) + up * (height/2),    # top-right
		start + right * (-width/2) + up * (height/2)    # top-left
	]
	
	# Crear plano frontal en START (amarillo opaco)
	var start_plane = DebugUtil.create_debug_plane(
		front_corners_start[0],
		front_corners_start[1],
		front_corners_start[2],
		front_corners_start[3],
		Color(1.0, 1.0, 0.0, 0.8),  # Amarillo opaco
		0.2  # Poca transparencia
	)
	
	if start_plane:
		world_node.add_child(start_plane)
		main_path_front_planes.append(start_plane)  # Guardar para limpieza
		print("    ✓ Plano frontal PRINCIPAL START creado (amarillo)")
	
	# Calcular los 4 vértices de la cara frontal en END
	var front_corners_end = [
		end + right * (-width/2) + up * (-height/2),  # bottom-left
		end + right * (width/2) + up * (-height/2),   # bottom-right
		end + right * (width/2) + up * (height/2),    # top-right
		end + right * (-width/2) + up * (height/2)    # top-left
	]
	
	# Crear plano frontal en END (naranja semi-transparente)
	var end_plane = DebugUtil.create_debug_plane(
		front_corners_end[0],
		front_corners_end[1],
		front_corners_end[2],
		front_corners_end[3],
		Color(1.0, 0.5, 0.0, 0.6),  # Naranja
		0.4  # Semi-transparente
	)
	
	if end_plane:
		world_node.add_child(end_plane)
		main_path_front_planes.append(end_plane)  # Guardar para limpieza
		print("    ✓ Plano frontal PRINCIPAL END creado (naranja)")

func _visualize_car_front_planes(start: Vector3, end: Vector3, base_color: Color) -> void:
	# Calcular orientación del auto
	var direction = (end - start).normalized()
	var forward = direction
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	# Calcular los 4 vértices de la cara frontal en START
	var front_corners_start = [
		start + right * (-width/2) + up * (-height/2),  # bottom-left
		start + right * (width/2) + up * (-height/2),   # bottom-right
		start + right * (width/2) + up * (height/2),    # top-right
		start + right * (-width/2) + up * (height/2)    # top-left
	]
	
	# Crear plano frontal en START (semi-transparente)
	var start_plane = DebugUtil.create_debug_plane(
		front_corners_start[0],
		front_corners_start[1],
		front_corners_start[2],
		front_corners_start[3],
		base_color,
		0.3  # Transparencia
	)
	
	if start_plane and continuation_paths_container:
		continuation_paths_container.add_child(start_plane)
		print("      ✓ Plano frontal START creado")
	
	# Calcular los 4 vértices de la cara frontal en END
	var front_corners_end = [
		end + right * (-width/2) + up * (-height/2),  # bottom-left
		end + right * (width/2) + up * (-height/2),   # bottom-right
		end + right * (width/2) + up * (height/2),    # top-right
		end + right * (-width/2) + up * (height/2)    # top-left
	]
	
	# Crear plano frontal en END (más transparente)
	var end_plane = DebugUtil.create_debug_plane(
		front_corners_end[0],
		front_corners_end[1],
		front_corners_end[2],
		front_corners_end[3],
		Color(base_color.r, base_color.g, base_color.b, 0.5),  # Más opaco para distinguirlo
		0.5  # Más transparencia
	)
	
	if end_plane and continuation_paths_container:
		continuation_paths_container.add_child(end_plane)
		print("      ✓ Plano frontal END creado")

func _get_continuation_lateral_planes(volume: Dictionary) -> Dictionary:
	var start = volume["start_plane_vertices"]
	var end = volume["end_plane_vertices"]
	
	return {
		"bottom": _plane_from_points(start[0], start[1], end[1]),
		"right": _plane_from_points(start[1], start[2], end[2]),
		"top": _plane_from_points(start[2], start[3], end[3]),
		"left": _plane_from_points(start[3], start[0], end[0])
	}

func _plane_from_points(p1: Vector3, p2: Vector3, p3: Vector3) -> Array:
	var v1 = p2 - p1
	var v2 = p3 - p1
	var normal = v1.cross(v2).normalized()
	return [normal, p1]

func _ray_plane_intersection(ray_origin: Vector3, ray_direction: Vector3, plane: Array) -> Variant:
	var plane_normal = plane[0]
	var plane_point = plane[1]
	
	var denom = plane_normal.dot(ray_direction)
	if abs(denom) < 0.0001:
		return null
	
	var t = plane_normal.dot(plane_point - ray_origin) / denom
	if t < 0:
		return null
	
	return ray_origin + ray_direction * t

func _check_path_complete() -> void:
	if path_follow and path_3d:
		var curve_length = path_3d.curve.get_baked_length()
		if path_follow.progress >= curve_length:
			queue_free()
