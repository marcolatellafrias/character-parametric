class_name TouchComponent
extends ControllableInteractable

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
	_update_debug_color()

func stop_control() -> void:
	super()
	if not is_toggle and is_pressed:
		is_pressed = false
		_emit_if_changed(0.0)
		released.emit()
	_update_debug_color()

func _create_debug_meshes(size: Vector3) -> void:
	var face := _make_debug_box(
		Vector3(size.x * 0.65, size.y * 0.65, size.z * 0.5),
		Color(0.35, 0.4, 0.65)
	)
	add_child(face)
	_debug_primary_mat = face.material_override as StandardMaterial3D

func _update_debug_color() -> void:
	if _debug_primary_mat == null:
		return
	_debug_primary_mat.albedo_color = Color(0.9, 0.5, 0.15) if is_pressed else Color(0.35, 0.4, 0.65)
