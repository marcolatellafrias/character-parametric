class_name Grabbable
extends Node3D

var grab_points: Array[Node3D] = []
var handle_points: Array[Node3D] = []

const CELL_SIZE := 0.15

func setup_from_cells(cells_x: int, cells_y: int, cells_z: int) -> void:
	var sx := cells_x * CELL_SIZE
	var sy := cells_y * CELL_SIZE
	var sz := cells_z * CELL_SIZE
	_generate_grab_points(cells_x, cells_y, cells_z, sx, sy, sz)
	_generate_handle_points(cells_x, cells_y, cells_z, sx, sy, sz)

func add_grab_point_local(local_pos: Vector3) -> void:
	var pt := Node3D.new()
	pt.position = local_pos
	add_child(pt)
	grab_points.append(pt)
	pt.add_child(_make_debug_sphere(Color.BLUE))

func add_handle_point_local(local_pos: Vector3) -> void:
	var pt := Node3D.new()
	pt.position = local_pos
	add_child(pt)
	handle_points.append(pt)
	pt.add_child(_make_debug_sphere(Color.RED))

func get_nearest_grab_point(world_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for pt in grab_points:
		if not is_instance_valid(pt): continue
		var d := pt.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = pt
	return best

func get_nearest_handle_point(world_pos: Vector3, exclude: Node3D = null) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for pt in handle_points:
		if not is_instance_valid(pt) or pt == exclude: continue
		var d := pt.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = pt
	return best

func _generate_grab_points(cx: int, cy: int, cz: int, sx: float, sy: float, sz: float) -> void:
	var nx := ceili(cx / 4.0)
	var ny := ceili(cy / 4.0)
	var nz := ceili(cz / 4.0)
	for ix in nx:
		for iy in ny:
			for iz in nz:
				add_grab_point_local(Vector3(
					-sx * 0.5 + (ix + 0.5) * sx / nx,
					-sy * 0.5 + (iy + 0.5) * sy / ny,
					-sz * 0.5 + (iz + 0.5) * sz / nz
				))

func _generate_handle_points(cx: int, cy: int, cz: int, sx: float, sy: float, sz: float) -> void:
	# [face_coord, dim_a_cells, dim_b_cells, size_a, size_b, fixed_axis]
	var faces: Array = [
		[ sx * 0.5, cy, cz, sy, sz, 0],
		[-sx * 0.5, cy, cz, sy, sz, 0],
		[ sy * 0.5, cx, cz, sx, sz, 1],
		[-sy * 0.5, cx, cz, sx, sz, 1],
		[ sz * 0.5, cx, cy, sx, sy, 2],
		[-sz * 0.5, cx, cy, sx, sy, 2],
	]
	for face in faces:
		var fc: float = face[0]
		var na := ceili((face[1] as int) / 4.0)
		var nb := ceili((face[2] as int) / 4.0)
		var sa: float = face[3]
		var sb: float = face[4]
		var axis: int = face[5]
		for ia in na:
			for ib in nb:
				var pa := -sa * 0.5 + (ia + 0.5) * sa / na
				var pb := -sb * 0.5 + (ib + 0.5) * sb / nb
				var pos := Vector3.ZERO
				match axis:
					0: pos = Vector3(fc, pa, pb)
					1: pos = Vector3(pa, fc, pb)
					2: pos = Vector3(pa, pb, fc)
				add_handle_point_local(pos)

# no_depth_test = true es lo correcto para "on top", no DEPTH_DRAW_ALWAYS
func _make_debug_sphere(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 8
	mi.mesh = sphere
	mi.scale = Vector3.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	return mi
