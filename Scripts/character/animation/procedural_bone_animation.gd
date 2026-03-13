class_name ProceduralBoneAnimator

enum SignalType {
    STEP_PROGRESS,
    STEP_LENGTH,
    STEP_DRIVEN,
    H_VEL_X,
    H_VEL_Z,
    V_VEL,
    FOOT_SPREAD_X,
    FOOT_SPREAD_Z
}

enum Axis {
    ROT_X,
    ROT_Z,
    POS_Y
}

class BoneAnimEntry:
    var bone: CustomBone
    var axis: ProceduralBoneAnimator.Axis
    var driver: ProceduralBoneAnimator.SignalType
    var weight: float
    var curve: Curve
    var rest_local_position: Vector3
    var rest_signal_value: float = 0.0

var locomotion_signals: LocomotionSignals
var _entries: Array = []

static func create(signals: LocomotionSignals) -> ProceduralBoneAnimator:
    var a := ProceduralBoneAnimator.new()
    a.locomotion_signals = signals
    return a

func register(bone: CustomBone, axis: Axis, driver: SignalType, weight: float, curve: Curve = null) -> void:
    var entry := BoneAnimEntry.new()
    entry.bone = bone
    entry.axis = axis
    entry.driver = driver
    entry.weight = weight
    entry.curve = curve
    entry.rest_local_position = bone.position
    entry.rest_signal_value = _get_signal_value(driver)
    _entries.append(entry)

func update() -> void:
    for entry in _entries:
        var raw: float = _get_signal_value(entry.driver) - entry.rest_signal_value
        var shaped: float = entry.curve.sample_baked(clamp(raw, 0.0, 1.0)) if entry.curve else raw
        _apply(entry.bone, entry.axis, shaped * entry.weight, entry)

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
    return 0.0

func _apply(bone: CustomBone, axis: Axis, value: float, entry: BoneAnimEntry) -> void:
    match axis:
        Axis.ROT_X:
            bone.global_transform.basis = bone.global_transform.basis * Basis(Vector3.RIGHT, value)
        Axis.ROT_Z:
            bone.global_transform.basis = bone.global_transform.basis * Basis(Vector3.FORWARD, value)
        Axis.POS_Y:
            bone.position.y = entry.rest_local_position.y + value
