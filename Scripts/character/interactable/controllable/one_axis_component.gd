class_name OneAxisComponent
extends ControllableInteractable

enum InputAxis { HORIZONTAL, VERTICAL }

@export var input_axis:          InputAxis = InputAxis.VERTICAL
@export var sensitivity:         float     = 0.005
@export var min_value:           float     = 0.0
@export var max_value:           float     = 1.0
@export var rotation_axis_local: Vector3   = Vector3.RIGHT
@export var max_angle_degrees:   float     = 45.0

# Fraction of cell height kept as padding at each end of the arm.
# 0.0 = arm tip touches the cell edge; 0.1 = 10 % padding top and bottom.
@export var padding_factor: float = 0.1

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
	rotation = _rest_rot() + rotation_axis_local * deg_to_rad(lerpf(0.0, max_angle_degrees, t))

func _arm_length(size: Vector3) -> float:
	var pad :float= size.y * clamp(padding_factor, 0.0, 0.49)
	return size.y * 0.5 - pad

func _setup_handle_points(size: Vector3) -> void:
	add_handle_point_local(Vector3(0.0, _arm_length(size), 0.0))
