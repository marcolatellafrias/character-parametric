class_name DynamicSizesUtil

var leg_height : float
var bone_inst : BoneInstantiator
var collision_shape:
	get:
		return bone_inst.collision_shape
	set(value):
		bone_inst.collision_shape = value
var stable_sizes:
	get:
		return bone_inst.stable_sizes_util

static func create(new_bone_inst: BoneInstantiator, new_leg_height: float) -> DynamicSizesUtil:
	var newDynamicUtil = DynamicSizesUtil.new()
	newDynamicUtil.bone_inst = new_bone_inst
	newDynamicUtil.leg_height = new_leg_height
	return newDynamicUtil

func set_base() -> void:
	_set_step_base_duration()
	_set_capsule_base_dimensions()

func update() -> void:
	_update_step_duration()

func _update_step_duration() -> void:
	var v : Vector3 = bone_inst.character_controller.velocity
	var horizontal_speed : float = Vector2(v.x, v.z).length()
	var sprint_mult : float = bone_inst.character_controller.sprint_multiplier
	var effective_speed := horizontal_speed * sprint_mult
	var speed_term := pow(1.0 + (effective_speed / bone_inst.speed_ref), bone_inst.beta)
	bone_inst.step_duration = bone_inst.base_step_duration / speed_term

func _set_step_base_duration() -> void:
	bone_inst.character_controller.speed = leg_height * 0.7 + 1
	bone_inst.step_radius_walk = leg_height * 0.32
	bone_inst.step_radius_turn = leg_height * 0.2
	bone_inst.step_duration = (leg_height) * 0.2 
	bone_inst.step_height = leg_height * 0.4
	bone_inst.pole_distance = leg_height
	bone_inst.raycast_max_offset = leg_height * 0.2
	var leg_term   := pow( max(leg_height, 0.001) / bone_inst.leg_ref, bone_inst.alpha)
	var speed_term := pow( 1.0 / bone_inst.speed_ref, bone_inst.beta)
	bone_inst.step_duration = bone_inst.base_step_duration * leg_term / speed_term
	bone_inst.base_step_duration = bone_inst.base_step_duration * leg_term

func _set_capsule_base_dimensions() -> void:
	if collision_shape is CollisionShape3D:
		if collision_shape.shape is CapsuleShape3D:
			var radius :=  bone_inst.hip_width.y * 2
			var height := bone_inst.feet_to_head_height
			var y_offset : float = stable_sizes.torso_height + stable_sizes.head_height + height/2 - height + bone_inst.distance_from_ground
			collision_shape.shape.height = height
			collision_shape.shape.radius = radius
			collision_shape.position = (Vector3(0, y_offset ,0))
			bone_inst.character_controller.add_child.call_deferred(DebugUtil.create_debug_capsule(radius,  height, y_offset))
