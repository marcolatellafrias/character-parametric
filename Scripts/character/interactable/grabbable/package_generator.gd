class_name PackageGenerator
extends RefCounted

static func create(cells_x: int, cells_y: int, cells_z: int, weight: float = 1.0) -> RigidBody3D:
	const CELL := 0.15
	var size := Vector3(cells_x, cells_y, cells_z) * CELL

	var rb := RigidBody3D.new()
	rb.mass = weight

	var mi := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mi.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mi.material_override = mat
	rb.add_child(mi)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	rb.add_child(col)

	var grabbable := GrabbableInteractable.new()
	rb.add_child(grabbable)
	grabbable.setup_from_cells(cells_x, cells_y, cells_z)

	return rb
