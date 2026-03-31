class_name PackageSpawner
extends Node3D

const CELL := 0.15

@export var cells_x: int   = 4
@export var cells_y: int   = 4
@export var cells_z: int   = 4
@export var weight:  float = 1.0

func _ready() -> void:
	var rb := _create(cells_x, cells_y, cells_z, weight)
	add_child(rb)
	rb.global_position = global_position

static func _create(cx: int, cy: int, cz: int, weight: float) -> RigidBody3D:
	var size := Vector3(cx, cy, cz) * CELL

	var rb       := RigidBody3D.new()
	rb.mass       = weight

	var mi        := MeshInstance3D.new()
	var box_mesh  := BoxMesh.new()
	box_mesh.size  = size
	mi.mesh        = box_mesh
	var mat        := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mi.material_override = mat
	rb.add_child(mi)

	var col        := CollisionShape3D.new()
	var box_shape  := BoxShape3D.new()
	box_shape.size  = size
	col.shape       = box_shape
	rb.add_child(col)

	var grabbable := GrabbableInteractable.new()
	rb.add_child(grabbable)
	grabbable.setup_from_cells(cx, cy, cz)
	grabbable.show_debug_points()

	return rb
