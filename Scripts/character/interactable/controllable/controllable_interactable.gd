class_name ControllableInteractable
extends Interactable

@export var auto_return:               bool         = false
@export var default_value:             float        = 0.0
@export var positions:                 Array[float] = []
@export var camera_sensitivity_factor: float        = 0.3
@export var snap_lerp_speed:           float        = 8.0
@export var return_speed:              float        = 3.0

var grid_size:            Vector2i              = Vector2i(1, 1)
var visual_value:         float                 = 0.0
var _network_state:       float                 = 0.0
var _is_being_controlled: bool                  = false
var _debug_meshes:        Array[MeshInstance3D] = []
var _debug_primary_mat:   StandardMaterial3D    = null

signal state_changed(value: float)

func _physics_process(delta: float) -> void:
	if _is_being_controlled:
		return
	if auto_return:
		_do_auto_return(delta)
	elif positions.size() > 0:
		visual_value = lerp(visual_value, _network_state, clamp(delta * snap_lerp_speed, 0.0, 1.0))
		_apply_visual()

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

# ── Debug ─────────────────────────────────────────────────────────────────────

func build_debug_visuals(control_size: Vector3) -> void:
	for m in _debug_meshes:
		if is_instance_valid(m):
			m.queue_free()
	_debug_meshes.clear()
	_debug_primary_mat = null
	_create_debug_meshes(control_size)

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
