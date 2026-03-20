class_name ProceduralBoneAnimator

enum SignalType {
	STEP_PROGRESS, STEP_LENGTH, STEP_DRIVEN,
	H_VEL_X, H_VEL_Z, V_VEL,
	FOOT_SPREAD_X, FOOT_SPREAD_Z,
	LEFT_FOOT_X, LEFT_FOOT_Z,
	RIGHT_FOOT_X, RIGHT_FOOT_Z,
	FOOT_SPREAD_UNIFIED_X,
	FOOT_SPREAD_UNIFIED_Z
}
enum Axis {
	ROT_X, ROT_Y, ROT_Z, POS_Y
}

class BoneAnimEntry:
	var bone: CustomBone
	var axis: ProceduralBoneAnimator.Axis
	var driver: Callable
	var weight: float
	var curve: Curve
	var rest_local_position: Vector3
	var rest_signal_value: float = 0.0
	var rest_local_basis: Basis

class NodeAnimEntry:
	var node: Node3D
	var direction: Vector3
	var driver: Callable
	var weight: float
	var curve: Curve
	var rest_local_position: Vector3
	var rest_signal_value: float = 0.0

var locomotion_signals: LocomotionSignals
var _entries: Array = []
var _node_entries: Array = []

static func create(signals: LocomotionSignals) -> ProceduralBoneAnimator:
	var a := ProceduralBoneAnimator.new()
	a.locomotion_signals = signals
	return a

func register(bone: CustomBone, axis: Axis, driver: SignalType, weight: float, curve: Curve = null) -> void:
	_register_internal(bone, axis, func(): return _get_signal_value(driver), weight, curve)

func register_formula(bone: CustomBone, axis: Axis, formula: Callable, weight: float = 1.0, curve: Curve = null) -> void:
	_register_internal(bone, axis, formula, weight, curve)

func register_node(node: Node3D, direction: Vector3, driver: SignalType, weight: float, curve: Curve = null) -> void:
	_register_node_internal(node, direction, func(): return _get_signal_value(driver), weight, curve)

func register_node_formula(node: Node3D, direction: Vector3, formula: Callable, weight: float = 1.0, curve: Curve = null) -> void:
	_register_node_internal(node, direction, formula, weight, curve)

func _register_internal(bone: CustomBone, axis: Axis, driver_fn: Callable, weight: float, curve: Curve) -> void:
	var entry := BoneAnimEntry.new()
	entry.bone = bone
	entry.axis = axis
	entry.driver = driver_fn
	entry.weight = weight
	entry.curve = curve
	entry.rest_local_position = bone.position
	entry.rest_signal_value = driver_fn.call()
	entry.rest_local_basis = bone.transform.basis
	_entries.append(entry)

func _register_node_internal(node: Node3D, direction: Vector3, driver_fn: Callable, weight: float, curve: Curve) -> void:
	var entry := NodeAnimEntry.new()
	entry.node = node
	entry.direction = direction
	entry.driver = driver_fn
	entry.weight = weight
	entry.curve = curve
	entry.rest_local_position = node.position
	entry.rest_signal_value = driver_fn.call()
	_node_entries.append(entry)

func update() -> void:
	for entry in _entries:
		entry.bone.position.y = entry.rest_local_position.y
		entry.bone.transform.basis = entry.rest_local_basis
	for entry in _entries:
		var raw: float = entry.driver.call() - entry.rest_signal_value
		var shaped: float = entry.curve.sample_baked(clamp(raw, 0.0, 1.0)) if entry.curve else raw
		_apply(entry.bone, entry.axis, shaped * entry.weight, entry)

	for entry in _node_entries:
		entry.node.position = entry.rest_local_position
	for entry in _node_entries:
		var raw: float = entry.driver.call() - entry.rest_signal_value
		var shaped: float = entry.curve.sample_baked(clamp(raw, 0.0, 1.0)) if entry.curve else raw
		entry.node.position += entry.direction * shaped * entry.weight

func _get_signal_value(driver: SignalType) -> float:
	match driver:
		SignalType.STEP_PROGRESS:
			return locomotion_signals.step_progress
		SignalType.STEP_LENGTH:
			return locomotion_signals.step_length_norm
		SignalType.STEP_DRIVEN:
			return locomotion_signals.step_progress * locomotion_signals.step_length_norm
		SignalType.H_VEL_X:
			return locomotion_signals.horizontal_velocity_smooth.x
		SignalType.H_VEL_Z:
			return locomotion_signals.horizontal_velocity_smooth.y
		SignalType.V_VEL:
			return locomotion_signals.vertical_velocity_smooth
		SignalType.FOOT_SPREAD_X:
			return locomotion_signals.foot_spread_norm.x
		SignalType.FOOT_SPREAD_Z:
			return locomotion_signals.foot_spread_norm.y
		SignalType.LEFT_FOOT_X:
			return locomotion_signals.left_foot_local_norm.x
		SignalType.LEFT_FOOT_Z:
			return locomotion_signals.left_foot_local_norm.y
		SignalType.RIGHT_FOOT_X:
			return locomotion_signals.right_foot_local_norm.x
		SignalType.RIGHT_FOOT_Z:
			return locomotion_signals.right_foot_local_norm.y
		SignalType.FOOT_SPREAD_UNIFIED_X:
			return locomotion_signals.foot_spread_unified.x
		SignalType.FOOT_SPREAD_UNIFIED_Z:
			return locomotion_signals.foot_spread_unified.y
	return 0.0

func _apply(bone: CustomBone, axis: Axis, value: float, _entry: BoneAnimEntry) -> void:
	match axis:
		Axis.ROT_X:
			bone.transform.basis = bone.transform.basis * Basis(Vector3.RIGHT, value)
		Axis.ROT_Y:
			bone.transform.basis = bone.transform.basis * Basis(Vector3.UP, value)
		Axis.ROT_Z:
			bone.transform.basis = bone.transform.basis * Basis(Vector3.FORWARD, value)
		Axis.POS_Y:
			bone.position.y += value
