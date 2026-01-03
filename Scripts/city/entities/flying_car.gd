extends Node3D
class_name FlyingCar

@export var width: float = 2.0
@export var height: float = 1.0
@export var depth: float = 4.0
@export var car_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var speed: float = 10.0

var mesh_instance: MeshInstance3D
var start_position: Vector3
var end_position: Vector3
var has_path: bool = false
var travel_progress: float = 0.0

func _ready() -> void:
	_create_visual()

func _process(delta: float) -> void:
	if has_path:
		travel_progress += delta * speed / start_position.distance_to(end_position)
		
		if travel_progress >= 1.0:
			queue_free()
		else:
			global_position = start_position.lerp(end_position, travel_progress)

func _create_visual() -> void:
	mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mesh_instance.mesh = box
	
	var material := StandardMaterial3D.new()
	material.albedo_color = car_color
	mesh_instance.material_override = material
	
	add_child(mesh_instance)

func set_path(start: Vector3, end: Vector3) -> void:
	start_position = start
	end_position = end
	has_path = true
	travel_progress = 0.0
