class_name TwoAxisComponent
extends ControllableInteractable

@export var sensitivity:       float = 0.005
@export var max_angle_degrees: float = 30.0

var axis_value: Vector2 = Vector2.ZERO

signal state_changed_2d(value: Vector2)

func get_prompt() -> String:
	return "[LMB] + drag to move"

func get_sync_state() -> Variant:
	return axis_value

func apply_sync_state(state: Variant) -> void:
	axis_value   = state
	visual_value = axis_value.length()
	_apply_visual()
	state_changed_2d.emit(axis_value)

func handle_mouse_motion(delta: Vector2) -> void:
	axis_value   = (axis_value + delta * sensitivity).limit_length(1.0)
	visual_value = axis_value.length()
	state_changed_2d.emit(axis_value)
	_apply_visual()

func _do_auto_return(delta: float) -> void:
	axis_value   = axis_value.move_toward(Vector2.ZERO, return_speed * delta)
	visual_value = axis_value.length()
	state_changed_2d.emit(axis_value)
	_apply_visual()

# Stick protrudes along local +Z (toward player).
# Mouse up   → axis_value.y negative → positive X rotation → stick leans "forward".
# Mouse right → axis_value.x positive → negative Y rotation → stick leans "right".
func _apply_visual() -> void:
	rotation = _rest_rot() + Vector3(
		-axis_value.y * deg_to_rad(max_angle_degrees),
		-axis_value.x * deg_to_rad(max_angle_degrees),
		0.0
	)

func _setup_handle_points(size: Vector3) -> void:
	var t       := size.z * 0.5
	var stick_h : float = min(size.x, size.y) * 0.55
	add_handle_point_local(Vector3(0.0, 0.0, t + stick_h))

func _create_debug_meshes(size: Vector3) -> void:
	var t        := size.z * 0.5
	var stick_h  : float = min(size.x, size.y) * 0.55
	# Flat platform sitting on the dashboard surface
	var platform := _make_debug_box(
		Vector3(size.x * 0.65, size.y * 0.65, t),
		Color(0.4, 0.75, 0.55),
		Vector3(0.0, 0.0, t * 0.5)
	)
	add_child(platform)
	# Stick protruding in +Z
	var stick := _make_debug_box(
		Vector3(t * 0.45, t * 0.45, stick_h),
		Color(0.85, 0.85, 0.3),
		Vector3(0.0, 0.0, t + stick_h * 0.5)
	)
	add_child(stick)
