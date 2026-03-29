class_name TouchComponent
extends ControllableInteractable

# is_toggle: true = stays pressed on click, releases on next click
#            false = momentary, pressed while held

@export var is_toggle: bool = false

var is_pressed: bool = false

signal pressed()
signal released()

func get_prompt() -> String:
	return "[LMB] to press"

func start_control() -> void:
	super()
	if is_toggle:
		is_pressed = !is_pressed
		_emit_if_changed(1.0 if is_pressed else 0.0)
		if is_pressed: pressed.emit()
		else:          released.emit()
	else:
		is_pressed = true
		_emit_if_changed(1.0)
		pressed.emit()

func stop_control() -> void:
	super()
	if not is_toggle and is_pressed:
		is_pressed = false
		_emit_if_changed(0.0)
		released.emit()
