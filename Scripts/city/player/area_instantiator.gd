extends Node3D
class_name AreaInstantiator

@export var radius: float = 1.0
@export var height: float = 2.0
@export var segments: int = 16
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.3)
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

func _ready() -> void:
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
	if not world:
		return
	
	var car = FlyingCar.new()
	car.width = randf_range(min_car_width, max_car_width)
	car.height = randf_range(min_car_height, max_car_height)
	car.depth = randf_range(min_car_depth, max_car_depth)
	car.car_color = Color(randf(), randf(), randf(), 1.0)
	
	world.add_child(car)
	
	var spawn_position = _get_random_cylinder_position()
	car.global_position = spawn_position

func _get_random_cylinder_position() -> Vector3:
	var random_angle = randf() * TAU
	var random_height = randf() * height
	
	var local_x = cos(random_angle) * radius
	var local_z = sin(random_angle) * radius
	var local_position = Vector3(local_x, random_height, local_z)
	
	return global_transform * local_position
