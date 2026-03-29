class_name OneAxisComponent
extends ControllableInteractable

enum InputAxis { HORIZONTAL, VERTICAL }

@export var input_axis:          InputAxis = InputAxis.VERTICAL
@export var sensitivity:         float     = 0.005
@export var min_value:           float     = 0.0
@export var max_value:           float     = 1.0
@export var rotation_axis_local: Vector3   = Vector3.RIGHT
@export var max_angle_degrees:   float     = 45.0

func get_prompt() -> String:
	return "[LMB] + drag to move"

func handle_mouse_motion(delta: Vector2) -> void:
	var raw := delta.x if input_axis == InputAxis.HORIZONTAL else delta.y
	visual_value = clamp(visual_value + raw * sensitivity, min_value, max_value)
	if positions.is_empty():
		_emit_if_changed(visual_value)
	_apply_visual()

func _do_auto_return(delta: float) -> void:
	visual_value = move_toward(visual_value, default_value, return_speed * delta)
	_emit_if_changed(visual_value)
	_apply_visual()

func _apply_visual() -> void:
	var t := inverse_lerp(min_value, max_value, visual_value)
	rotation = rotation_axis_local * deg_to_rad(lerpf(-max_angle_degrees, max_angle_degrees, t))

func _create_debug_meshes(size: Vector3) -> void:
	var t      :float= min(size.x, size.y) * 0.15
	var length := size.y * 0.55
	var arm    := _make_debug_box(
		Vector3(t, length, t),
		Color(0.45, 0.65, 1.0),
		Vector3(0.0, length * 0.5, 0.0)
	)
	add_child(arm)
	var tip := _make_debug_box(
		Vector3(t * 2.0, t * 2.0, t * 2.0),
		Color(0.95, 0.55, 0.2),
		Vector3(0.0, length, 0.0)
	)
	add_child(tip)
