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

var mesh_instance: MeshInstance3D
var path_debug_mesh: MeshInstance3D
var detection_area: Area3D
var path_3d: Path3D
var path_follow: PathFollow3D
var has_path: bool = false
var world_node: Node3D

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
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()
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

func set_path(start: Vector3, end: Vector3, initial_progress: float = 0.0) -> void:
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
	
	# Visualizar el path
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

func _check_path_complete() -> void:
	if path_follow and path_3d:
		var curve_length = path_3d.curve.get_baked_length()
		if path_follow.progress >= curve_length:
			queue_free()
