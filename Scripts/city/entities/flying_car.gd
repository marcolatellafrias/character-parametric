extends Node3D
class_name FlyingCar

@export var width: float = 2.0
@export var height: float = 1.0
@export var depth: float = 4.0
@export var car_color: Color = Color(1.0, 0.0, 0.0, 1.0)

var mesh_instance: MeshInstance3D

func _ready() -> void:
	_create_visual()

func _create_visual() -> void:
	mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mesh_instance.mesh = box
	
	var material := StandardMaterial3D.new()
	material.albedo_color = car_color
	mesh_instance.material_override = material
	
	add_child(mesh_instance)
