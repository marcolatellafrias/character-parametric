class_name ControllableInteractable
extends Interactable

@export var auto_return:               bool         = false
@export var default_value:             float        = 0.0
@export var positions:                 Array[float] = []
@export var camera_sensitivity_factor: float        = 0.3
@export var snap_lerp_speed:           float        = 8.0
@export var return_speed:              float        = 3.0

# Applied as a constant offset in every _apply_visual call.
# Lets you set the resting orientation of any control at instantiation time.
@export var rest_rotation_deg: Vector3 = Vector3.ZERO

# When set, replaces the debug geometry with this mesh (positioned at _get_mesh_offset).
@export var custom_mesh: Mesh = null

var grid_size:            Vector2i              = Vector2i(1, 1)
var visual_value:         float                 = 0.0
var _network_state:       float                 = 0.0
var _is_being_controlled: bool                  = false
var _debug_meshes:        Array[MeshInstance3D] = []
var _debug_primary_mat:   StandardMaterial3D    = null

signal state_changed(value: float)

# ── Build ─────────────────────────────────────────────────────────────────────

func build(control_size: Vector3) -> void:
	_clear_handle_points()
	_setup_handle_points(control_size)
	_apply_custom_mesh()

func build_debug_visuals(control_size: Vector3) -> void:
	_clear_handle_points()
	_clear_debug_meshes()
	_setup_handle_points(control_size)
	if is_instance_valid(custom_mesh):
		_apply_custom_mesh()
	else:
		_create_debug_meshes(control_size)
	_visualize_handle_points()

# ── Physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _is_being_controlled:
		return
	if auto_return:
		_do_auto_return(delta)
	elif positions.size() > 0:
		visual_value = lerp(visual_value, _network_state, clamp(delta * snap_lerp_speed, 0.0, 1.0))
		_apply_visual()

# ── API ───────────────────────────────────────────────────────────────────────

func get_network_state() -> float:
	return _network_state

func get_prompt() -> String:
	return "[LMB] to interact"

func start_control() -> void:
	_is_being_controlled = true
	_set_debug_emit(true)

func stop_control() -> void:
	_is_being_controlled = false
	_set_debug_emit(false)
	if not auto_return and positions.size() > 0:
		_snap_to_nearest()

func handle_mouse_motion(_delta: Vector2) -> void:
	pass

func handle_scroll(_delta: float) -> void:
	pass

# ── Internals ─────────────────────────────────────────────────────────────────

func _do_auto_return(delta: float) -> void:
	visual_value = move_toward(visual_value, default_value, return_speed * delta)
	_emit_if_changed(visual_value)
	_apply_visual()

func _snap_to_nearest() -> void:
	if positions.is_empty():
		return
	var nearest   := positions[0]
	var best_dist : float = abs(visual_value - nearest)
	for p in positions:
		var d : float = abs(visual_value - p)
		if d < best_dist:
			best_dist = d
			nearest   = p
	_emit_if_changed(nearest)

func _emit_if_changed(new_state: float) -> void:
	if abs(new_state - _network_state) > 0.001:
		_network_state = new_state
		state_changed.emit(_network_state)

func _apply_visual() -> void:
	pass

# ── Helpers for subclasses ────────────────────────────────────────────────────

# Returns rest_rotation_deg converted to radians as a Vector3, for use in _apply_visual.
func _rest_rot() -> Vector3:
	return Vector3(
		deg_to_rad(rest_rotation_deg.x),
		deg_to_rad(rest_rotation_deg.y),
		deg_to_rad(rest_rotation_deg.z)
	)

# Override in subclasses that need the mesh offset from origin (e.g. RotatingComponent).
func _get_mesh_offset() -> Vector3:
	return Vector3.ZERO

func _apply_custom_mesh() -> void:
	if not is_instance_valid(custom_mesh):
		return
	var mi      := MeshInstance3D.new()
	mi.mesh      = custom_mesh
	mi.position  = _get_mesh_offset()
	add_child(mi)

# ── Debug ─────────────────────────────────────────────────────────────────────

func _create_debug_meshes(_control_size: Vector3) -> void:
	pass

func _make_debug_box(size: Vector3, color: Color, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh  = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = offset
	_debug_meshes.append(mi)
	return mi

func _make_debug_cylinder(radius: float, height: float, color: Color, offset: Vector3 = Vector3.ZERO, euler_rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius      = radius
	cyl.bottom_radius   = radius
	cyl.height          = height
	cyl.radial_segments = 16
	mi.mesh             = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = offset
	mi.rotation = euler_rot
	_debug_meshes.append(mi)
	return mi

func _set_debug_emit(active: bool) -> void:
	for m in _debug_meshes:
		if not is_instance_valid(m):
			continue
		var mat := m.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = active
		if active:
			mat.emission                   = Color(0.05, 0.45, 0.1)
			mat.emission_energy_multiplier = 1.2

func _clear_debug_meshes() -> void:
	for m in _debug_meshes:
		if is_instance_valid(m):
			m.queue_free()
	_debug_meshes.clear()
	_debug_primary_mat = null

func _setup_handle_points(_control_size: Vector3) -> void:
	pass

func _visualize_handle_points() -> void:
	for pt in handle_points:
		if not is_instance_valid(pt):
			continue
		pt.add_child(DebugUtil.create_debug_sphere(Color(1.0, 0.75, 0.0), 0.035, true))
