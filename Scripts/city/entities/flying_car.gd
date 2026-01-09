extends Node3D
class_name FlyingCar

enum Type {
	CAR,
	TRUCK,
	MOTORCYCLE
}

@export var width: float = 2.0
@export var height: float = 1.0
@export var depth: float = 4.0
@export var car_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var speed: float = 10.0
@export var spawn_time: float = 0.0
@export var seed: int = 0
@export var car_archetype: Type = Type.CAR

@export var show_path_debug: bool = false
@export var path_debug_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var path_debug_width: float = 0.05
@export var path_debug_segments: int = 20

# Colores para continuaciones
@export var continuation_exact_color: Color = Color(0.0, 1.0, 0.0, 1.0)  # Verde
@export var continuation_approx_color: Color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan

# Parámetro para transición
@export var transition_distance: float = 2.0  # Distancia antes del final para buscar siguiente path

var mesh_instance: MeshInstance3D
var path_debug_mesh: MeshInstance3D
var continuation_debug_meshes: Array[MeshInstance3D] = []
var detection_area: Area3D
var path_3d: Path3D
var path_follow: PathFollow3D
var has_path: bool = false
var world_node: Node3D
var city = null

# Estado actual del volumen
var current_volume: Dictionary = {}
var current_cell_x: int = 0
var current_cell_y: int = 0
var current_width_cells: int = 3
var current_height_cells: int = 10

# RNG para decisiones deterministas
var rng: RandomNumberGenerator

# Control de transición
var is_transitioning: bool = false
var next_path_info: Dictionary = {}

func _ready() -> void:
	_create_visual()
	_create_detection_area()
	
	# Inicializar RNG con la seed del auto
	rng = RandomNumberGenerator.new()
	rng.seed = seed

func _process(delta: float) -> void:
	if has_path and path_follow:
		path_follow.progress += delta * speed
		global_position = path_follow.global_position
		global_rotation = path_follow.global_rotation
		
		# Verificar si está cerca del final para preparar transición
		if not is_transitioning and path_3d and path_3d.curve:
			var curve_length = path_3d.curve.get_baked_length()
			var distance_to_end = curve_length - path_follow.progress
			
			if distance_to_end <= transition_distance:
				_prepare_next_path()

func _exit_tree() -> void:
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
	
	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()
	
	if path_3d and is_instance_valid(path_3d):
		path_3d.queue_free()

func initialize_from_seed(p_seed: int, archetype_weights: Dictionary = {}) -> void:
	seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	
	car_archetype = _select_archetype_from_seed(rng, archetype_weights)
	
	var archetype_type = _convert_to_car_archetype_type(car_archetype)
	var archetype = CarArchetypes.get_archetype(archetype_type)
	
	width = rng.randf_range(archetype.min_width, archetype.max_width)
	height = rng.randf_range(archetype.min_height, archetype.max_height)
	depth = rng.randf_range(archetype.min_depth, archetype.max_depth)
	speed = rng.randf_range(archetype.min_speed, archetype.max_speed)
	
	if archetype.color_palette.is_empty():
		car_color = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
	else:
		var color_idx = rng.randi() % archetype.color_palette.size()
		car_color = archetype.color_palette[color_idx]

func _select_archetype_from_seed(rng: RandomNumberGenerator, custom_weights: Dictionary) -> Type:
	var total_weight = 0.0
	var weighted_types = []
	
	var type_mapping = {
		Type.CAR: CarArchetypes.Type.CAR,
		Type.TRUCK: CarArchetypes.Type.TRUCK,
		Type.MOTORCYCLE: CarArchetypes.Type.MOTORCYCLE
	}
	
	for type in Type.values():
		var car_archetype_type = type_mapping[type]
		var archetype = CarArchetypes.get_archetype(car_archetype_type)
		var weight = custom_weights.get(car_archetype_type, archetype.weight)
		total_weight += weight
		weighted_types.append({"type": type, "weight": weight})
	
	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0
	
	for item in weighted_types:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return item["type"]
	
	return Type.CAR

func _convert_to_car_archetype_type(type: Type) -> CarArchetypes.Type:
	match type:
		Type.CAR:
			return CarArchetypes.Type.CAR
		Type.TRUCK:
			return CarArchetypes.Type.TRUCK
		Type.MOTORCYCLE:
			return CarArchetypes.Type.MOTORCYCLE
	return CarArchetypes.Type.CAR

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
	
	# Guardar info del volumen actual
	current_volume = volume
	current_cell_x = int(round(grid_u * width_cells))
	current_cell_y = int(round(grid_v * height_cells))
	current_width_cells = width_cells
	current_height_cells = height_cells
	
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
	is_transitioning = false
	
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
	
	# Timer para verificar si llegó al final
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_check_path_complete)
	add_child(timer)
	timer.start()

func _prepare_next_path() -> void:
	is_transitioning = true
	
	if not city or not current_volume.has("face_idx") or not current_volume.has("edge_idx"):
		return
	
	var face_idx = current_volume["face_idx"]
	var edge_idx = current_volume["edge_idx"]
	
	var continuations = city.get_lane_volume_continuations(face_idx, edge_idx)
	
	if continuations.is_empty():
		# Callejón sin salida, el auto se destruirá
		return
	
	# Obtener dirección actual del path
	var current_direction = _get_current_path_direction()
	
	# Validar continuaciones y calcular ángulos
	var valid_continuations = []
	
	for cont_vol in continuations:
		var result = _get_validated_continuation_path(cont_vol, current_cell_x, current_cell_y)
		
		if result != null and result.has("start") and result.has("end"):
			var cont_direction = (result["end"] - result["start"]).normalized()
			var angle_diff = abs(current_direction.angle_to(cont_direction))
			
			valid_continuations.append({
				"volume": cont_vol,
				"path": result,
				"angle_diff": angle_diff
			})
	
	if valid_continuations.is_empty():
		# No hay continuaciones válidas
		return
	
	# Seleccionar una basándose en ángulos de forma determinista
	var selected = _select_continuation_by_angle(valid_continuations)
	
	if selected:
		next_path_info = selected

func _get_current_path_direction() -> Vector3:
	if path_3d and path_3d.curve and path_3d.curve.point_count >= 2:
		var start = path_3d.curve.get_point_position(0)
		var end = path_3d.curve.get_point_position(path_3d.curve.point_count - 1)
		return (end - start).normalized()
	return Vector3.FORWARD

func _select_continuation_by_angle(continuations: Array) -> Dictionary:
	# Calcular pesos basados en el ángulo (menor ángulo = mayor peso)
	var total_weight = 0.0
	var weighted_continuations = []
	
	for cont in continuations:
		# Peso inversamente proporcional al ángulo
		# Usamos (PI - angle) para que ángulos pequeños tengan mayor peso
		var weight = PI - cont["angle_diff"]
		total_weight += weight
		weighted_continuations.append({
			"continuation": cont,
			"weight": weight
		})
	
	# Seleccionar basado en seed
	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0
	
	for item in weighted_continuations:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return item["continuation"]
	
	# Fallback al primero
	return continuations[0] if not continuations.is_empty() else {}

func _check_path_complete() -> void:
	if path_follow and path_3d:
		var curve_length = path_3d.curve.get_baked_length()
		if path_follow.progress >= curve_length:
			if next_path_info.is_empty():
				# Callejón sin salida, destruir auto
				queue_free()
			else:
				# Transicionar al siguiente path
				_transition_to_next_path()

func _transition_to_next_path() -> void:
	if next_path_info.is_empty():
		return
	
	# Limpiar path anterior
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
	
	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()
	
	var old_path = path_3d
	
	# Obtener info del path siguiente
	var path_data = next_path_info["path"]
	var new_volume = next_path_info["volume"]
	
	var current_end = old_path.curve.get_point_position(old_path.curve.point_count - 1)
	var next_start = path_data["start"]
	var next_end = path_data["end"]
	
	# Calcular direcciones tangentes
	var current_direction = _get_current_path_direction()
	var next_direction = (next_end - next_start).normalized()
	
	# Crear nuevo path con bezier
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	
	# Calcular handles basados en las direcciones de movimiento
	var connection_distance = (next_start - current_end).length()
	var handle_length = connection_distance * 0.4
	
	# Handle de salida: continúa en la dirección actual
	var out_handle = current_direction * handle_length
	
	# Handle de entrada: se opone a la dirección del siguiente path
	var in_handle = -next_direction * handle_length
	
	# Agregar puntos con handles para curva suave
	curve.add_point(current_end, Vector3.ZERO, out_handle)
	curve.add_point(next_start, in_handle, Vector3.ZERO)
	curve.add_point(next_end, Vector3.ZERO, Vector3.ZERO)
	
	path_3d.curve = curve
	
	if world_node:
		world_node.add_child(path_3d)
	else:
		get_parent().add_child(path_3d)
	
	# Limpiar path anterior
	if old_path and is_instance_valid(old_path):
		old_path.queue_free()
	
	# Crear nuevo PathFollow3D
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	path_follow.progress = 0.0
	
	# Actualizar volumen actual
	current_volume = {
		"face_idx": new_volume.face_idx,
		"edge_idx": new_volume.edge_idx
	}
	current_cell_x = path_data["used_cell_x"]
	current_cell_y = path_data["used_cell_y"]
	current_width_cells = new_volume.width_cells
	current_height_cells = new_volume.height_cells
	
	# Visualizar nuevo path
	if show_path_debug and world_node:
		var points = [
			{"pos": current_end, "in": Vector3.ZERO, "out": out_handle},
			{"pos": next_start, "in": in_handle, "out": Vector3.ZERO},
			{"pos": next_end, "in": Vector3.ZERO, "out": Vector3.ZERO}
		]
		
		path_debug_mesh = DebugUtil.create_debug_path3d(
			points,
			path_debug_segments,
			path_debug_color,
			path_debug_width
		)
		world_node.add_child(path_debug_mesh)
	
	# Limpiar info de siguiente path
	next_path_info = {}
	is_transitioning = false

func _get_validated_continuation_path(lane_vol: LaneVolume, target_cell_x: int, target_cell_y: int) -> Variant:
	var cont_width_cells = lane_vol.width_cells
	var cont_height_cells = lane_vol.height_cells
	
	var x_in_range = (target_cell_x >= 0 and target_cell_x <= cont_width_cells)
	var y_in_range = (target_cell_y >= 0 and target_cell_y <= cont_height_cells)
	
	var current_cell_x = target_cell_x
	var current_cell_y = target_cell_y
	var is_exact = true
	
	if not x_in_range or not y_in_range:
		current_cell_x = clampi(target_cell_x, 0, cont_width_cells)
		current_cell_y = clampi(target_cell_y, 0, cont_height_cells)
		is_exact = false
	
	var max_tries = 5
	for attempt in range(max_tries):
		var u = float(current_cell_x) / float(cont_width_cells) if cont_width_cells > 0 else 0.0
		var v = float(current_cell_y) / float(cont_height_cells) if cont_height_cells > 0 else 0.0
		
		var path_segment = lane_vol.get_path_segment_at_grid(u, v)
		
		var front_face = get_front_face_at_segment(path_segment["start"], path_segment["end"])
		
		var validation = lane_vol.validate_face_projection(front_face, u, v)
		
		if validation["valid"]:
			return {
				"start": path_segment["start"],
				"end": path_segment["end"],
				"is_exact": is_exact and (attempt == 0),
				"used_cell_x": current_cell_x,
				"used_cell_y": current_cell_y,
				"attempts": attempt + 1
			}
		
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
			is_exact = false
		else:
			break
	
	return null
	
func _move_away_from_plane(plane_name: String, current_x: int, current_y: int, 
						   max_width: int, max_height: int) -> Dictionary:
	var new_x = current_x
	var new_y = current_y
	
	match plane_name:
		"bottom":
			new_y = current_y + 1
		"top":
			new_y = current_y - 1
		"left":
			new_x = current_x + 1
		"right":
			new_x = current_x - 1
	
	if new_x < 0 or new_x > max_width or new_y < 0 or new_y > max_height:
		return {}
	
	return {
		"cell_x": new_x,
		"cell_y": new_y
	}

func build_front_face() -> Array:
	var direction = -global_transform.basis.z.normalized()
	
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

func get_front_face_at_segment(start: Vector3, end: Vector3) -> Array:
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
