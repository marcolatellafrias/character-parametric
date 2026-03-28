class_name PackageSpawner
extends Node3D

@export var cells_x: int = 4
@export var cells_y: int = 4
@export var cells_z: int = 4
@export var weight: float = 1.0

func _ready() -> void:
	var rb := PackageGenerator.create(cells_x, cells_y, cells_z, weight)
	add_child(rb)
	rb.global_position = global_position
