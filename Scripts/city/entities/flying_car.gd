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

# Colores para continuaciones
@export var continuation_exact_color: Color = Color(0.0, 1.0, 0.0, 1.0)  # Verde
@export var continuation_approx_color: Color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan

var mesh_instance: MeshInstance3D
var path_debug_mesh: MeshInstance3D
var continuation_debug_meshes: Array[MeshInstance3D] = []
var detection_area: Area3D
var path_3d: Path3D
var path_follow: PathFollow3D
var has_path: bool = false
var world_node: Node3D
var city = null

func _ready() -> void:
	_create_visual()
	_create_detection_area()

func _process(delta: float) -> void:
	if has_path and path_follow:
		path_follow.progress += delta * speed
		global_position = path_follow.global_position
		global_rotation = path_follow.global_rotation

func _exit_tree() -> void:
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
	
	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()
	
	if path_3d and is_instance_valid(path_3d):
		path_3d.queue_free()

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
	
	# Crear Path3D y Curve3D
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	
	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, Vector3.ZERO)
	
	path_3d.curve = curve
	
	if world_node:
		world_node.add_child(path_3d)
	else:
		get_parent().add_child(path_3d)
	
	# Crear PathFollow3D
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	var curve_length = curve.get_baked_length()
	path_follow.progress = initial_progress * curve_length
	
	global_position = path_follow.global_position
	global_rotation = path_follow.global_rotation
	
	has_path = true
	
	# Visualizar path principal
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
		
		# Convertir coordenadas normalizadas a índices de celda discretos
		var cell_x = int(round(grid_u * width_cells))
		var cell_y = int(round(grid_v * height_cells))
		
		# Visualizar continuaciones
		_visualize_continuations(cell_x, cell_y, volume)
	
	# Timer para verificar si llegó al final
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_check_path_complete)
	add_child(timer)
	timer.start()

func _visualize_continuations(cell_x: int, cell_y: int, volume: Dictionary) -> void:
	if not city or not volume.has("face_idx") or not volume.has("edge_idx"):
		return
	
	var face_idx = volume["face_idx"]
	var edge_idx = volume["edge_idx"]
	
	var continuations = city.get_lane_volume_continuations(face_idx, edge_idx)
	
	for cont_vol in continuations:
		var result = _get_validated_continuation_path(cont_vol, cell_x, cell_y)
		
		if result != null and result.has("start") and result.has("end"):
			var color = continuation_exact_color if result["is_exact"] else continuation_approx_color
			
			var points = [
				{"pos": result["start"], "in": Vector3.ZERO, "out": Vector3.ZERO},
				{"pos": result["end"], "in": Vector3.ZERO, "out": Vector3.ZERO}
			]
			
			var debug_mesh = DebugUtil.create_debug_path3d(
				points,
				path_debug_segments,
				color,
				path_debug_width
			)
			world_node.add_child(debug_mesh)
			continuation_debug_meshes.append(debug_mesh)

func _get_validated_continuation_path(lane_vol: LaneVolume, target_cell_x: int, target_cell_y: int) -> Variant:
	var cont_width_cells = lane_vol.width_cells
	var cont_height_cells = lane_vol.height_cells
	
	# Verificar si las celdas están dentro del rango
	var x_in_range = (target_cell_x >= 0 and target_cell_x <= cont_width_cells)
	var y_in_range = (target_cell_y >= 0 and target_cell_y <= cont_height_cells)
	
	var current_cell_x = target_cell_x
	var current_cell_y = target_cell_y
	var is_exact = true
	
	# Si están fuera de rango, clampear
	if not x_in_range or not y_in_range:
		current_cell_x = clampi(target_cell_x, 0, cont_width_cells)
		current_cell_y = clampi(target_cell_y, 0, cont_height_cells)
		is_exact = false
	
	# Intentar validar la posición hasta 5 veces
	var max_tries = 5
	for attempt in range(max_tries):
		# Convertir celdas a coordenadas normalizadas
		var u = float(current_cell_x) / float(cont_width_cells) if cont_width_cells > 0 else 0.0
		var v = float(current_cell_y) / float(cont_height_cells) if cont_height_cells > 0 else 0.0
		
		# Obtener el segmento de path
		var path_segment = lane_vol.get_path_segment_at_grid(u, v)
		
		# Construir cara frontal del auto en este segmento
		var front_face = get_front_face_at_segment(path_segment["start"], path_segment["end"])
		
		# Validar proyección
		var validation = lane_vol.validate_face_projection(front_face, u, v)
		
		if validation["valid"]:
			# Posición válida encontrada
			return {
				"start": path_segment["start"],
				"end": path_segment["end"],
				"is_exact": is_exact and (attempt == 0),
				"used_cell_x": current_cell_x,
				"used_cell_y": current_cell_y,
				"attempts": attempt + 1
			}
		
		# Colisión detectada, alejarse del plano problemático
		var collision_plane = validation["collision_plane"]
		var moved = _move_away_from_plane(
			collision_plane, 
			current_cell_x, 
			current_cell_y, 
			cont_width_cells, 
			cont_height_cells
		)
		
		if moved.has("cell_x") and moved.has("cell_y"):
			current_cell_x = moved["cell_x"]
			current_cell_y = moved["cell_y"]
			is_exact = false  # Ya no es exacta porque nos movimos
		else:
			# No se puede mover más, abandonar
			break
	
	# No se encontró posición válida después de todos los intentos
	return null
	
func _move_away_from_plane(plane_name: String, current_x: int, current_y: int, 
						   max_width: int, max_height: int) -> Dictionary:
	var new_x = current_x
	var new_y = current_y
	
	match plane_name:
		"bottom":
			new_y = current_y + 1  # Subir
		"top":
			new_y = current_y - 1  # Bajar
		"left":
			new_x = current_x + 1  # Ir a la derecha
		"right":
			new_x = current_x - 1  # Ir a la izquierda
	
	# Verificar que la nueva posición esté dentro de los límites
	if new_x < 0 or new_x > max_width or new_y < 0 or new_y > max_height:
		return {}  # No se puede mover, fuera de límites
	
	return {
		"cell_x": new_x,
		"cell_y": new_y
	}

func _get_continuation_path(lane_vol: LaneVolume, target_cell_x: int, target_cell_y: int) -> Dictionary:
	# Obtener dimensiones del volumen de continuación
	var cont_width_cells = lane_vol.width_cells
	var cont_height_cells = lane_vol.height_cells
	
	# Verificar si las celdas están dentro del rango del volumen de continuación
	var x_in_range = (target_cell_x >= 0 and target_cell_x <= cont_width_cells)
	var y_in_range = (target_cell_y >= 0 and target_cell_y <= cont_height_cells)
	
	var final_cell_x = target_cell_x
	var final_cell_y = target_cell_y
	var is_exact = true
	
	# Si están fuera de rango, clampear a la celda más cercana
	if not x_in_range or not y_in_range:
		final_cell_x = clampi(target_cell_x, 0, cont_width_cells)
		final_cell_y = clampi(target_cell_y, 0, cont_height_cells)
		is_exact = false
	
	# Convertir celdas discretas a coordenadas normalizadas u,v
	var final_u = float(final_cell_x) / float(cont_width_cells) if cont_width_cells > 0 else 0.0
	var final_v = float(final_cell_y) / float(cont_height_cells) if cont_height_cells > 0 else 0.0
	
	# Obtener el segmento de path en las coordenadas
	var path_segment = lane_vol.get_path_segment_at_grid(final_u, final_v)
	
	return {
		"start": path_segment["start"],
		"end": path_segment["end"],
		"is_exact": is_exact,
		"used_cell_x": final_cell_x,
		"used_cell_y": final_cell_y
	}

func _check_path_complete() -> void:
	if path_follow and path_3d:
		var curve_length = path_3d.curve.get_baked_length()
		if path_follow.progress >= curve_length:
			queue_free()

func build_front_face() -> Array:
	"""Construye los 4 vértices de la cara frontal del auto como offsets desde el origen."""
	var direction = -global_transform.basis.z.normalized()
	
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	
	var right = direction.cross(up).normalized()
	var true_up = right.cross(direction).normalized()
	
	var half_width = width * 0.5
	var half_height = height * 0.5
	
	# [bottom-left, bottom-right, top-right, top-left]
	return [
		-right * half_width - true_up * half_height,
		right * half_width - true_up * half_height,
		right * half_width + true_up * half_height,
		-right * half_width + true_up * half_height
	]

func get_front_face_at_segment(start: Vector3, end: Vector3) -> Array:
	"""Construye cara frontal en un segmento específico sin depender del transform global."""
	var direction = (end - start).normalized()
	
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	
	var right = direction.cross(up).normalized()
	var true_up = right.cross(direction).normalized()
	
	var half_width = width * 0.5
	var half_height = height * 0.5
	
	return [
		-right * half_width - true_up * half_height,
		right * half_width - true_up * half_height,
		right * half_width + true_up * half_height,
		-right * half_width + true_up * half_height
	]
