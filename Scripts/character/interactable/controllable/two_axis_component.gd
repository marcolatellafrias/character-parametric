class_name TwoAxisComponent
extends ControllableInteractable

# axis_value: Vector2 in (-1,-1)..(1,1), mapped to XZ tilt of this node
# state_changed_2d is the signal to broadcast for multiplayer (not the float state_changed)
# visual_value = axis_value.length() (magnitude, for base class compatibility)

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
		axis_value.y * deg_to_rad(max_angle_degrees),
		0.0,
		-axis_value.x * deg_to_rad(max_angle_degrees)
	)
