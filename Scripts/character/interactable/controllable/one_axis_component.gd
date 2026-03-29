class_name OneAxisComponent
extends ControllableInteractable

# visual_value in [min_value, max_value]
# For discrete (positions not empty): network_state snaps on release, visual lerps after
# For continuous (positions empty): network_state == visual_value, broadcast each frame

enum InputAxis { HORIZONTAL, VERTICAL }

@export var input_axis:           InputAxis = InputAxis.VERTICAL
@export var sensitivity:          float     = 0.005   # value units per pixel
@export var min_value:            float     = 0.0
@export var max_value:            float     = 1.0
@export var rotation_axis_local:  Vector3   = Vector3.RIGHT
@export var max_angle_degrees:    float     = 45.0

func get_prompt() -> String:
	return "[LMB] + drag to move"

func handle_mouse_motion(delta: Vector2) -> void:
	var raw := delta.x if input_axis == InputAxis.HORIZONTAL else delta.y
	visual_value = clamp(visual_value + raw * sensitivity, min_value, max_value)
	if positions.is_empty():
		_emit_if_changed(visual_value)
	# Discrete: don't emit here; _snap_to_nearest() fires on stop_control
	_apply_visual()

func _do_auto_return(delta: float) -> void:
	visual_value = move_toward(visual_value, default_value, return_speed * delta)
	_emit_if_changed(visual_value)
	_apply_visual()

func _apply_visual() -> void:
	var t := inverse_lerp(min_value, max_value, visual_value)
	rotation = rotation_axis_local * deg_to_rad(lerpf(-max_angle_degrees, max_angle_degrees, t))
