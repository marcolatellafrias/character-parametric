class_name RotatingComponent
extends ControllableInteractable

# total_rotation is unbounded (tracks multiple full rotations, like a real steering wheel)
# network_state = total_rotation (float, broadcast continuously while interacting)
# auto_return lerps total_rotation back toward 0, not wrapping

@export var sensitivity:          float   = 0.05         # radians per scroll unit
@export var rotation_axis_local:  Vector3 = Vector3.UP

var total_rotation: float = 0.0

func get_prompt() -> String:
	return "[LMB] + scroll to rotate"

func handle_scroll(delta: float) -> void:
	total_rotation += delta * sensitivity
	visual_value    = total_rotation
	_emit_if_changed(total_rotation)
	_apply_visual()

func _do_auto_return(delta: float) -> void:
	total_rotation = move_toward(total_rotation, 0.0, return_speed * delta)
	visual_value   = total_rotation
	_emit_if_changed(total_rotation)
	_apply_visual()

func _apply_visual() -> void:
	rotation = rotation_axis_local * visual_value
