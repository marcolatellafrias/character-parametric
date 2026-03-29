class_name ControllableInteractable
extends Interactable

# positions: empty = continuous float, populated = discrete snap targets (e.g. [0.0, 1.0])
# auto_return: when released, visual_value returns to default_value
# visual_value: drives mesh/animation, always updated smoothly
# _network_state: what gets broadcast for multiplayer; for discrete types, only updates on release

@export var auto_return:               bool          = false
@export var default_value:             float         = 0.0
@export var positions:                 Array[float]  = []
@export var camera_sensitivity_factor: float         = 0.3
@export var snap_lerp_speed:           float         = 8.0
@export var return_speed:              float         = 3.0

var visual_value:       float = 0.0
var _network_state:     float = 0.0
var _is_being_controlled: bool = false

signal state_changed(value: float)

func _physics_process(delta: float) -> void:
	if _is_being_controlled:
		return
	if auto_return:
		_do_auto_return(delta)
	elif positions.size() > 0:
		# Lerp visual toward the snapped network state after release
		visual_value = lerp(visual_value, _network_state, clamp(delta * snap_lerp_speed, 0.0, 1.0))
		_apply_visual()

func get_network_state() -> float:
	return _network_state

func get_prompt() -> String:
	return "[LMB] to interact"

func start_control() -> void:
	_is_being_controlled = true

func stop_control() -> void:
	_is_being_controlled = false
	if not auto_return and positions.size() > 0:
		_snap_to_nearest()

# Override in subclasses to handle mouse drag input
func handle_mouse_motion(_delta: Vector2) -> void:
	pass

# Override in subclasses to handle scroll input (e.g. RotatingComponent)
func handle_scroll(_delta: float) -> void:
	pass

func _do_auto_return(delta: float) -> void:
	visual_value = move_toward(visual_value, default_value, return_speed * delta)
	_emit_if_changed(visual_value)
	_apply_visual()

func _snap_to_nearest() -> void:
	if positions.is_empty():
		return
	var nearest    := positions[0]
	var best_dist  : float = abs(visual_value - nearest)
	for p in positions:
		var d : float = abs(visual_value - p)
		if d < best_dist:
			best_dist = d
			nearest   = p
	_emit_if_changed(nearest)

# Emits state_changed only when value meaningfully changes; call from subclasses
func _emit_if_changed(new_state: float) -> void:
	if abs(new_state - _network_state) > 0.001:
		_network_state = new_state
		state_changed.emit(_network_state)

# Override in subclasses to apply visual_value to mesh rotation/position
func _apply_visual() -> void:
	pass
