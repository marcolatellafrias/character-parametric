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

var mesh_instance: MeshInstance3D
var path_debug_line: MeshInstance3D
var detection_area: Area3D
var start_position: Vector3
var end_position: Vector3
var has_path: bool = false
var travel_progress: float = 0.0
var world_node: Node3D

func _ready() -> void:
	_create_visual()
	_create_detection_area()

func _process(delta: float) -> void:
	if has_path:
		var total_distance = start_position.distance_to(end_position)
		travel_progress += delta * speed / total_distance
		
		if travel_progress >= 1.0:
			# Auto llegó al final del path
			queue_free()
			return
		
		global_position = start_position.lerp(end_position, travel_progress)
		
		var direction = (end_position - start_position).normalized()
		if direction.length() > 0.001:
			look_at(global_position + direction, Vector3.UP)

func _exit_tree() -> void:
	if path_debug_line and is_instance_valid(path_debug_line):
		path_debug_line.queue_free()

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
	detection_area.collision_layer = 1  # El auto está en layer 1
	detection_area.collision_mask = 0   # No necesita detectar nada
	detection_area.monitorable = true   # Puede ser detectado por otras áreas
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.5
	collision_shape.shape = sphere_shape
	
	detection_area.add_child(collision_shape)
	add_child(detection_area)

func set_path(start: Vector3, end: Vector3, initial_progress: float = 0.0) -> void:
	start_position = start
	end_position = end
	has_path = true
	travel_progress = initial_progress
	
	# Posicionar el auto en el progreso inicial
	global_position = start_position.lerp(end_position, travel_progress)
	
	var direction = (end_position - start_position).normalized()
	if direction.length() > 0.001:
		look_at(global_position + direction, Vector3.UP)
	
	if show_path_debug and world_node:
		path_debug_line = DebugUtil.create_debug_line_to_from(
			start_position, 
			end_position, 
			path_debug_color, 
			path_debug_width
		)
		world_node.add_child(path_debug_line)
