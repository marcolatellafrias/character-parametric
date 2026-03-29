class_name RotatingComponent
extends ControllableInteractable

@export var sensitivity:         float   = 0.05
@export var rotation_axis_local: Vector3 = Vector3.UP

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

func _create_debug_meshes(size: Vector3) -> void:
	var radius    :float= min(size.x, size.y) * 0.42
	var thickness := size.z * 0.35
	var wheel     := _make_debug_box(
		Vector3(radius * 2.0, radius * 2.0, thickness),
		Color(0.7, 0.42, 0.85)
	)
	add_child(wheel)
	var spoke_h := radius * 0.88
	var spoke   := _make_debug_box(
		Vector3(radius * 0.12, spoke_h, thickness * 1.3),
		Color(0.95, 0.95, 0.95),
		Vector3(0.0, spoke_h * 0.5, 0.0)
	)
	add_child(spoke)
