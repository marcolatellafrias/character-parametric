extends Node3D
class_name AreaInstantiator

@export var radius: float = 1.0
@export var height: float = 2.0
@export var segments: int = 16
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.1)
@export var show_debug: bool = true

@export var world: Node3D
@export var spawn_interval: float = 3.0

@export_group("Car Size Ranges")
@export var debug_size_factor: float = 0.1
@export var min_car_width: float = 1.5 * debug_size_factor
@export var max_car_width: float = 2.5 * debug_size_factor
@export var min_car_height: float = 0.8 * debug_size_factor
@export var max_car_height: float = 1.5 * debug_size_factor
@export var min_car_depth: float = 3.0 * debug_size_factor
@export var max_car_depth: float = 5.0 * debug_size_factor

var debug_mesh: MeshInstance3D
var spawn_timer: Timer
var city = null

func _ready() -> void:
	city = get_tree().get_first_node_in_group("city_generator")
	
	if show_debug:
		_create_debug_visualization()
	
	_setup_spawn_timer()

func _create_debug_visualization() -> void:
	if debug_mesh:
		debug_mesh.queue_free()
	
	debug_mesh = DebugUtil.create_debug_cylinder(debug_color, radius, height, segments)
	add_child(debug_mesh)

func _setup_spawn_timer() -> void:
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_spawn_car)
	add_child(spawn_timer)
	spawn_timer.start()

func _spawn_car() -> void:
	if not world or not city:
		return
	
	var spawn_position = _get_random_cylinder_position()
	
	# Obtener lane volumes cercanos
	var volumes = city.get_lane_volumes_in_cylindrical_area(
		global_position,
		radius * 1.5,  # Un poco más grande para asegurar cobertura
		height
	)
	
	# Verificar si el spawn_position está dentro de algún lane volume
	var is_valid_position = false
	for vol in volumes:
		if _is_point_inside_lane_volume(spawn_position, vol["start_plane_vertices"], vol["end_plane_vertices"]):
			is_valid_position = true
			break
	
	if not is_valid_position:
		return
	
	# Spawn del car
	var car = FlyingCar.new()
	car.width = randf_range(min_car_width, max_car_width)
	car.height = randf_range(min_car_height, max_car_height)
	car.depth = randf_range(min_car_depth, max_car_depth)
	car.car_color = Color(randf(), randf(), randf(), 1.0)
	
	world.add_child(car)
	car.global_position = spawn_position

func _get_random_cylinder_position() -> Vector3:
	var random_angle = randf() * TAU
	var random_height = randf() * height
	
	var local_x = cos(random_angle) * radius
	var local_z = sin(random_angle) * radius
	var local_position = Vector3(local_x, random_height, local_z)
	
	return global_transform * local_position

func _is_point_inside_lane_volume(point: Vector3, plane1_verts: Array, plane2_verts: Array) -> bool:
	# Verificar las 6 caras del volumen
	# Cada cara define un plano, verificamos que el punto esté en el lado correcto
	
	# Cara frontal (plane1)
	if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[1], plane1_verts[2], true):
		return false
	
	# Cara trasera (plane2)
	if not _is_point_on_correct_side(point, plane2_verts[3], plane2_verts[2], plane2_verts[1], true):
		return false
	
	# Bottom face
	if not _is_point_on_correct_side(point, plane1_verts[0], plane2_verts[0], plane2_verts[1], true):
		return false
	
	# Top face
	if not _is_point_on_correct_side(point, plane1_verts[3], plane1_verts[2], plane2_verts[2], true):
		return false
	
	# Left face
	if not _is_point_on_correct_side(point, plane1_verts[0], plane1_verts[3], plane2_verts[3], true):
		return false
	
	# Right face
	if not _is_point_on_correct_side(point, plane1_verts[1], plane2_verts[1], plane2_verts[2], true):
		return false
	
	return true

func _is_point_on_correct_side(point: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, inside: bool) -> bool:
	var normal = (v2 - v1).cross(v3 - v1).normalized()
	var to_point = point - v1
	var dot = normal.dot(to_point)
	
	return dot >= 0 if inside else dot <= 0
