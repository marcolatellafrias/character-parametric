class_name GrabbableInteractable
extends Interactable

var grab_points: Array[Node3D] = []

const CELL_SIZE      := 0.15
const GRAB_DENSITY   := 6
const HANDLE_DENSITY := 4

func add_grab_point_local(local_pos: Vector3) -> void:
	var pt := Node3D.new()
	pt.position = local_pos
	add_child(pt)
	grab_points.append(pt)

func get_nearest_grab_point(world_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for pt in grab_points:
		if not is_instance_valid(pt):
			continue
		var d := pt.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = pt
	return best

func setup_from_cells(cells_x: int, cells_y: int, cells_z: int) -> void:
	var sx := cells_x * CELL_SIZE
	var sy := cells_y * CELL_SIZE
	var sz := cells_z * CELL_SIZE
	_generate_grab_points(cells_x, cells_y, cells_z, sx, sy, sz)
	_generate_handle_points(cells_x, cells_y, cells_z, sx, sy, sz)

func get_prompt() -> String:
	return "[LMB] to grab"

func _generate_grab_points(cx: int, cy: int, cz: int, sx: float, sy: float, sz: float) -> void:
	var nx := ceili(cx / float(GRAB_DENSITY))
	var ny := ceili(cy / float(GRAB_DENSITY))
	var nz := ceili(cz / float(GRAB_DENSITY))
	for ix in nx:
		for iy in ny:
			for iz in nz:
				add_grab_point_local(Vector3(
					-sx * 0.5 + (ix + 0.5) * sx / nx,
					-sy * 0.5 + (iy + 0.5) * sy / ny,
					-sz * 0.5 + (iz + 0.5) * sz / nz
				))

func _generate_handle_points(cx: int, cy: int, cz: int, sx: float, sy: float, sz: float) -> void:
	var faces: Array = [
		[ sx * 0.5, cy, cz, sy, sz, 0],
		[-sx * 0.5, cy, cz, sy, sz, 0],
		[ sy * 0.5, cx, cz, sx, sz, 1],
		[-sy * 0.5, cx, cz, sx, sz, 1],
		[ sz * 0.5, cx, cy, sx, sy, 2],
		[-sz * 0.5, cx, cy, sx, sy, 2],
	]
	for face in faces:
		var fc: float  = face[0]
		var na         := ceili((face[1] as int) / float(HANDLE_DENSITY))
		var nb         := ceili((face[2] as int) / float(HANDLE_DENSITY))
		var sa: float  = face[3]
		var sb: float  = face[4]
		var axis: int  = face[5]
		for ia in na:
			for ib in nb:
				var pa  := -sa * 0.5 + (ia + 0.5) * sa / na
				var pb  := -sb * 0.5 + (ib + 0.5) * sb / nb
				var pos := Vector3.ZERO
				match axis:
					0: pos = Vector3(fc, pa, pb)
					1: pos = Vector3(pa, fc, pb)
					2: pos = Vector3(pa, pb, fc)
				add_handle_point_local(pos)

func show_debug_points() -> void:
	for pt in grab_points:
		if not is_instance_valid(pt):
			continue
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.CYAN
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # visibles atravesando el mesh
		mi.material_override = mat
		pt.add_child(mi)

	for pt in handle_points:
		if not is_instance_valid(pt):
			continue
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.YELLOW
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # visibles atravesando el mesh
		mi.material_override = mat
		pt.add_child(mi)
