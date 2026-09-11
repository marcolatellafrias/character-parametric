class_name RotatingComponent
extends ControllableInteractable

## Cómo se gira. Con la ruedita suma vueltas sin fin, como una válvula. Arrastrando el mouse de costado
## se gira como un volante.
enum InputMode { SCROLL, MOUSE_HORIZONTAL }

@export var input_mode:          InputMode = InputMode.SCROLL
@export var sensitivity:         float   = 0.05
## Tope de giro para cada lado, en radianes; 0 = sin tope. Con tope y el mouse es el volante del
## Cybertruck: a fondo sin llegar a dar una vuelta.
@export var max_rotation:        float   = 0.0
@export var rotation_axis_local: Vector3 = Vector3.UP
@export var height_offset:       float   = 0.0

# 1.0 = handles exactly on the disc circumference; lower values pull them inward.
@export var handle_radius_factor: float = 0.97

var total_rotation: float = 0.0

func get_prompt() -> String:
	return "[LMB] + drag left/right to turn" if input_mode == InputMode.MOUSE_HORIZONTAL else "[LMB] + scroll to rotate"

func apply_sync_state(state: Variant) -> void:
	total_rotation = state  # el visual y el control local leen de acá
	super(state)

func handle_scroll(delta: float) -> void:
	if input_mode == InputMode.SCROLL:
		_turn(delta * sensitivity)

## Arrastrar a la derecha gira en sentido horario visto de frente (con el eje hacia quien mira, BACK),
## como un volante: el valor baja.
func handle_mouse_motion(delta: Vector2) -> void:
	if input_mode == InputMode.MOUSE_HORIZONTAL:
		_turn(-delta.x * sensitivity)

func _turn(amount: float) -> void:
	total_rotation += amount
	if max_rotation > 0.0:
		total_rotation = clampf(total_rotation, -max_rotation, max_rotation)
	visual_value = total_rotation
	_emit_if_changed(total_rotation)
	_apply_visual()

func _do_auto_return(delta: float) -> void:
	total_rotation = move_toward(total_rotation, 0.0, return_speed * delta)
	visual_value   = total_rotation
	_emit_if_changed(total_rotation)
	_apply_visual()

func _apply_visual() -> void:
	rotation = _rest_rot() + rotation_axis_local * visual_value

func _get_mesh_offset() -> Vector3:
	return Vector3(0.0, 0.0, height_offset)

func _setup_handle_points(size: Vector3) -> void:
	var disc_radius  : float = min(size.x, size.y) * 0.42
	var radius       : float = disc_radius * clamp(handle_radius_factor, 0.0, 1.0)
	var handle_count : int   = clamp(int((radius * TAU) / 0.1), 3, 8)
	for i in handle_count:
		var angle := (TAU / handle_count) * i
		add_handle_point_local(Vector3(cos(angle) * radius, sin(angle) * radius, height_offset))

func _create_debug_meshes(size: Vector3) -> void:
	var radius    : float = min(size.x, size.y) * 0.42
	var thickness := size.z * 0.45
	var wheel := _make_debug_cylinder(
		radius, thickness,
		Color(0.7, 0.42, 0.85),
		Vector3(0.0, 0.0, height_offset),
		Vector3(PI * 0.5, 0.0, 0.0)
	)
	add_child(wheel)
	if height_offset > 0.001:
		var shaft := _make_debug_cylinder(
			radius * 0.08, height_offset,
			Color(0.5, 0.5, 0.5),
			Vector3(0.0, 0.0, height_offset * 0.5),
			Vector3(PI * 0.5, 0.0, 0.0)
		)
		add_child(shaft)
	var spoke_h := radius * 0.88
	var spoke   := _make_debug_box(
		Vector3(radius * 0.08, spoke_h, thickness * 0.8),
		Color(0.95, 0.95, 0.95),
		Vector3(0.0, spoke_h * 0.5, height_offset)
	)
	add_child(spoke)
