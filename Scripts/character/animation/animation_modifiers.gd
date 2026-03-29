class_name AnimationModifiers
extends Node

var bi: BoneInstantiator

const JUMP_SQUAT_Y    := -0.3
const JUMP_SQUAT_Z    :=  0.13
const JUMP_SQUAT_TILT :=  0.3
const CROUCH_Y        := -0.3
const CROUCH_Z        :=  0.13
const CROUCH_TILT     :=  0.3
const THROW_CHARGE_TILT: float = 0.3
const THROW_PUSH_TILT:   float = 0.48
const THROW_PUSH_DECAY:  float = 2.5

var jump_squat_t:    float = 0.0
var crouch_t:        float = 0.0
var throw_t:         float = 0.0
var throw_push_t:    float = 0.0
var throw_world_dir: Vector3 = Vector3.FORWARD

func _ready() -> void:
	bi = get_parent() as BoneInstantiator

func apply(delta: float) -> void:
	if not is_instance_valid(bi):
		return
	if throw_push_t > 0.0:
		throw_push_t = max(0.0, throw_push_t - delta * THROW_PUSH_DECAY)
	_apply_root_offsets()

func _apply_root_offsets() -> void:
	var y          := JUMP_SQUAT_Y    * jump_squat_t + CROUCH_Y    * crouch_t
	var z          := JUMP_SQUAT_Z    * jump_squat_t + CROUCH_Z    * crouch_t
	var tilt       := JUMP_SQUAT_TILT * jump_squat_t + CROUCH_TILT * crouch_t
	var throw_tilt := -THROW_CHARGE_TILT * throw_t + THROW_PUSH_TILT * throw_push_t
	var spine      := bi.custom_bones_util.lower_spine
	spine.position.z += z
	spine.position.y += y
	spine.transform.basis *= Basis(Vector3.RIGHT, -(tilt + throw_tilt))

func trigger_throw_push(world_dir: Vector3) -> void:
	throw_world_dir = world_dir
	throw_push_t    = 1.0
	throw_t         = 0.0

func set_throw_charge(t: float, world_dir: Vector3) -> void:
	throw_t         = t
	throw_world_dir = world_dir

func cancel_throw() -> void:
	throw_t = 0.0

func reset() -> void:
	jump_squat_t = 0.0
	crouch_t     = 0.0
	throw_t      = 0.0
	throw_push_t = 0.0
