class_name TouchComponent
extends ControllableInteractable

## Cuánto se hunde la parte móvil al apretarlo, como fracción de la profundidad del control.
const PRESS_TRAVEL := 0.2

@export var is_toggle: bool = false

var is_pressed: bool = false
var _travel := 0.0

signal pressed()
signal released()

func get_prompt() -> String:
	return "[LMB] to press"

func start_control() -> void:
	super()
	TestSounds.click(self)
	if is_toggle:
		is_pressed = !is_pressed
		_emit_if_changed(1.0 if is_pressed else 0.0)
		if is_pressed: pressed.emit()
		else:          released.emit()
	else:
		is_pressed = true
		_emit_if_changed(1.0)
		pressed.emit()
	_apply_visual()

func stop_control() -> void:
	# Actualizamos is_pressed ANTES de super(): ahí la base transmite el estado final por red.
	if not is_toggle and is_pressed:
		is_pressed = false
		_emit_if_changed(0.0)
		released.emit()
	_apply_visual()
	super()

func get_sync_state() -> Variant:
	return 1.0 if is_pressed else 0.0

func apply_sync_state(state: Variant) -> void:
	var now_pressed: bool = state >= 0.5
	if now_pressed != is_pressed:
		is_pressed = now_pressed
		if is_pressed: pressed.emit()
		else:          released.emit()
	_emit_if_changed(state)
	_apply_visual()

## Apretado, se hunde en su base.
func _apply_visual() -> void:
	position = Vector3(0.0, 0.0, -_travel if is_pressed else 0.0)

func _setup_handle_points(size: Vector3) -> void:
	_travel = size.z * PRESS_TRAVEL
	add_handle_point_local(Vector3(0.0, 0.0, size.z * 0.25))
