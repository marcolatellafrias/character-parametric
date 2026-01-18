extends Node

var is_paused: bool = false
var manual_delta: float = 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		is_paused = not is_paused
		manual_delta = 0.0
	
	if is_paused and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			manual_delta = 0.016
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			manual_delta = -0.016
