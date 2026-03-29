class_name TwoAxisComponent
extends ControllableInteractable

@export var sensitivity:       float = 0.005
@export var max_angle_degrees: float = 30.0

var axis_value: Vector2 = Vector2.ZERO

signal state_changed_2d(value: Vector2)

func get_prompt() -> String:
	return "[LMB] + drag to move"

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

func _apply_visual() -> void:
	rotation = Vector3(
		axis_value.y  * deg_to_rad(max_angle_degrees),
		0.0,
		-axis_value.x * deg_to_rad(max_angle_degrees)
	)

func _create_debug_meshes(size: Vector3) -> void:
	var t        := size.z * 0.5
	var platform := _make_debug_box(
		Vector3(size.x * 0.65, t, size.y * 0.65),
		Color(0.4, 0.75, 0.55),
		Vector3(0.0, t * 0.5, 0.0)
	)
	add_child(platform)
	var stick_h := size.y * 0.38
	var stick   := _make_debug_box(
		Vector3(t * 0.45, stick_h, t * 0.45),
		Color(0.85, 0.85, 0.3),
		Vector3(0.0, t + stick_h * 0.5, 0.0)
	)
	add_child(stick)

func _setup_handle_points(size: Vector3) -> void:
	var t       := size.z * 0.5
	var stick_h := size.y * 0.38
	add_handle_point_local(Vector3(0.0, t + stick_h, 0.0))
