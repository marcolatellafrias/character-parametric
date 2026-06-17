class_name SkeletonSizesUtil

var leg_height : float
var torso_height : float
var head_height : float
var hips_width : float
var shoulders_width : float

var head_size: Vector3
var head_offset: Vector3
var neck_size: Vector3
var neck_offset: Vector3
var chest_size: Vector3
var chest_offset: Vector3
var upper_spine_size: Vector3
var upper_spine_offset: Vector3
var middle_spine_size: Vector3
var middle_spine_offset: Vector3
var lower_spine_size: Vector3
var lower_spine_offset: Vector3
var upper_leg_size: Vector3
var upper_leg_offset: Vector3
var lower_leg_size: Vector3
var lower_leg_offset: Vector3
var upper_feet_size: Vector3
var upper_feet_offset: Vector3
var lower_feet_size: Vector3
var lower_feet_offset: Vector3
var upper_arm_size: Vector3
var upper_arm_offset: Vector3
var lower_arm_size: Vector3
var lower_arm_offset: Vector3
var shoulder_width: Vector3
var shoulder_offset: Vector3
var hip_size: Vector3
var hip_offset: Vector3
var raycast_stance_offset: float

var step_radius_min: float
var step_radius_max: float
var step_height: float
var distance_from_ground: float
var raycast_leg_lenght: float
var pole_distance: float
var raycast_max_offset: float
var raycast_amount := 11.5
var speed_for_max := 10.0
var axis_weight_lateral:  float = 0.6
var axis_weight_forward:  float = 0.8
var axis_weight_backward: float = 1.0
var speed_curve: Curve
const raycast_accel_gain := 0.06
const raycast_vel_gain   := 0.02
const raycast_smooth     := 8.0 

var slouchiness_chest: float
var slouchiness_center_spine: float
var slouchiness_neck: float
var shoulder_height: float
var shoulder_back: float

var arm_openness_angle: float
var arm_bentness: float
var elbow_pole_direction: float
var left_arm_tip_rest_local: Vector3
var right_arm_tip_rest_local: Vector3
var left_arm_pole_rest_local: Vector3
var right_arm_pole_rest_local: Vector3

var left_arm_shoulder_rest_local: Vector3
var right_arm_shoulder_rest_local: Vector3

var step_duration_scale: float = 1.0

var raycast_start_y_offset: float = 0.0

const CONST_HEAD_HEIGHT    := 0.378
const CONST_HEAD_RADIUS_XZ := 0.19

static func create(inst: EntityInstantiation) -> SkeletonSizesUtil:
	var skelSizes = SkeletonSizesUtil.new()
	var entityStats := inst.arch_final

	var new_head_height  := CONST_HEAD_HEIGHT
	var remaining_height := entityStats.height - new_head_height
	var leg_torso_sum    := entityStats.legs_to_feet_proportion + entityStats.chest_to_low_spine_proportion
	if leg_torso_sum == 0.0:
		leg_torso_sum = 1.0
	var new_leg_height   := remaining_height * (entityStats.legs_to_feet_proportion / leg_torso_sum)
	var new_torso_height := remaining_height * (entityStats.chest_to_low_spine_proportion / leg_torso_sum)
	var new_hips_width        := entityStats.hips_width_proportion * entityStats.height
	var new_shoulders_width   := entityStats.shoulder_width_proportion * entityStats.height
	skelSizes.leg_height      = new_leg_height
	skelSizes.torso_height    = new_torso_height
	skelSizes.head_height     = new_head_height
	skelSizes.hips_width      = new_hips_width
	skelSizes.raycast_stance_offset = new_hips_width * inst.arch_final.stance_width
	skelSizes.shoulders_width = new_shoulders_width

	if entityStats.has_neck:
		var neck_radius := lerp_range(0.05, 0.12, entityStats.muscularity)
		skelSizes.neck_size = Vector3(neck_radius, new_head_height * entityStats.head_neck_ratio, neck_radius)
		skelSizes.head_size = Vector3(CONST_HEAD_RADIUS_XZ, new_head_height * (1.0 - entityStats.head_neck_ratio), CONST_HEAD_RADIUS_XZ * 0.75)
	else:
		skelSizes.neck_size = Vector3.ZERO
		skelSizes.head_size = Vector3(CONST_HEAD_RADIUS_XZ, new_head_height, CONST_HEAD_RADIUS_XZ * 0.85)
	skelSizes.head_offset = Vector3(0.8, 1.0, -0.8)

	var chest_u_radius : float = lerp_range(0.16, 0.45, entityStats.muscularity)
	var chest_l_radius : float = lerp_range(0.16, 0.45, entityStats.muscularity)
	var chest_new_offset : float = lerp_range(0.0, -0.35, entityStats.muscularity)
	skelSizes.chest_offset = Vector3(0.4, 0.4, chest_new_offset)
	skelSizes.chest_size = Vector3(chest_u_radius, new_torso_height * 0.3, chest_l_radius)

	var upper_spine_u_radius : float = lerp_range(0.1, 0.3, entityStats.fatness)
	var upper_spine_l_radius : float = lerp_range(0.1, 0.3, entityStats.fatness)
	var upper_spine_new_offset : float = lerp_range(0.0, -0.55, entityStats.fatness)
	skelSizes.upper_spine_size = Vector3(upper_spine_u_radius, new_torso_height * 0.25, upper_spine_l_radius)
	skelSizes.upper_spine_offset = Vector3(0.0, 0.0, upper_spine_new_offset)

	var middle_spine_u_radius : float = lerp_range(0.1, 0.55, entityStats.fatness)
	var middle_spine_l_radius : float = lerp_range(0.1, 0.5, entityStats.fatness)
	var middle_spine_new_offset : float = lerp_range(0.0, -0.35, entityStats.fatness)
	skelSizes.middle_spine_size = Vector3(middle_spine_u_radius, new_torso_height * 0.25, middle_spine_l_radius)
	skelSizes.middle_spine_offset = Vector3(0.0, 0.0, middle_spine_new_offset)

	var lower_spine_u_radius : float = lerp_range(0.1, 0.35, entityStats.fatness)
	var lower_spine_l_radius : float = lerp_range(0.1, 0.35, entityStats.fatness)
	var lower_spine_new_offset : float = lerp_range(0.0, -0.1, entityStats.fatness)
	skelSizes.lower_spine_size = Vector3(lower_spine_u_radius, new_torso_height * 0.2, lower_spine_l_radius)
	skelSizes.lower_spine_offset = Vector3(0.0, 0.0, lower_spine_new_offset)

	var shoulder_u_radius : float = lerp_range(0.08, 0.2, entityStats.muscularity)
	var shoulder_l_radius : float = lerp_range(0.08, 0.25, entityStats.muscularity)
	skelSizes.shoulder_width = Vector3(shoulder_u_radius, new_shoulders_width, shoulder_l_radius)

	var arm_total := entityStats.reach
	var upper_arm_u_radius : float = lerp_range(0.06, 0.2, entityStats.muscularity)
	var upper_arm_l_radius : float = lerp_range(0.06, 0.23, entityStats.muscularity)
	skelSizes.upper_arm_size = Vector3(upper_arm_u_radius, arm_total * 0.45, upper_arm_l_radius)
	skelSizes.upper_arm_offset = Vector3(1.0, 1.0, 0.0)
	var lower_arm_u_radius : float = lerp_range(0.06, 0.13, entityStats.muscularity)
	var lower_arm_l_radius : float = lerp_range(0.06, 0.18, entityStats.muscularity)
	skelSizes.lower_arm_size = Vector3(lower_arm_u_radius, arm_total * 0.55, lower_arm_l_radius)
	skelSizes.lower_arm_offset = Vector3(0.0, 1.0, 0.0)

	var upper_leg_u_radius : float = lerp_range(0.06, 0.2, entityStats.fatness)
	var upper_leg_l_radius : float = lerp_range(0.06, 0.23, entityStats.fatness)
	skelSizes.upper_leg_size = Vector3(upper_leg_u_radius, new_leg_height * 0.45, upper_leg_l_radius)
	skelSizes.upper_leg_offset = Vector3(1.0, 0.0, 0.0)
	var lower_leg_u_radius : float = lerp_range(0.06, 0.2, entityStats.fatness)
	var lower_leg_l_radius : float = lerp_range(0.06, 0.23, entityStats.fatness)
	skelSizes.lower_leg_size = Vector3(lower_leg_u_radius, new_leg_height * 0.55, lower_leg_l_radius)
	skelSizes.lower_leg_offset = Vector3(1.0, 1.0, 0.0)
	skelSizes.upper_feet_size = Vector3(0.1, new_leg_height * 0.2, 0.1)
	skelSizes.lower_feet_size = Vector3(0.1, new_leg_height * 0.02, 0.1)
	var hip_u_radius : float = lerp_range(0.1, 0.2, entityStats.fatness)
	var hip_l_radius : float = lerp_range(0.1, 0.2, entityStats.fatness)
	skelSizes.hip_size = Vector3(hip_u_radius, new_hips_width, hip_l_radius)
	skelSizes.hip_offset = Vector3(1.0, 1.0, 0.0)

	skelSizes.raycast_leg_lenght = new_leg_height
	skelSizes.distance_from_ground = new_leg_height * entityStats.distance_from_ground_factor
	skelSizes.step_radius_max = new_leg_height * inst.step_radius
	skelSizes.step_radius_min = new_leg_height * inst.step_radius * 0.2
	skelSizes.step_height = new_leg_height * inst.step_height
	skelSizes.pole_distance = new_leg_height
	skelSizes.step_duration_scale    = entityStats.step_duration_scale
	skelSizes.raycast_max_offset     = new_leg_height * 0.20 * entityStats.step_duration_scale
	skelSizes.raycast_start_y_offset = new_leg_height * 0.35

	skelSizes.slouchiness_chest        = lerp_range(0.0, 0.6, entityStats.slouch)
	skelSizes.slouchiness_center_spine = lerp_range(0.0, 0.6, entityStats.slouch)
	skelSizes.slouchiness_neck         = lerp_range(0.2, 0.6, entityStats.slouch)
	skelSizes.shoulder_height          = lerp_range(-0.3, 0.3, entityStats.shoulders_height)
	skelSizes.shoulder_back            = lerp_range(0.0, 0.3, entityStats.shoulders_back)

	skelSizes.arm_openness_angle   = lerp_range(0.0, -PI * 0.25, entityStats.arm_openness)
	skelSizes.arm_bentness         = entityStats.arm_bentness
	skelSizes.elbow_pole_direction = entityStats.arm_elbow_openness

	skelSizes.left_arm_tip_rest_local   = _compute_arm_tip_local(true,  skelSizes)
	skelSizes.right_arm_tip_rest_local  = _compute_arm_tip_local(false, skelSizes)
	skelSizes.left_arm_pole_rest_local  = _compute_arm_pole_local(true,  skelSizes)
	skelSizes.right_arm_pole_rest_local = _compute_arm_pole_local(false, skelSizes)

	skelSizes.left_arm_shoulder_rest_local  = _compute_arm_shoulder_local(true,  skelSizes)
	skelSizes.right_arm_shoulder_rest_local = _compute_arm_shoulder_local(false, skelSizes)

	return skelSizes


static func _compute_arm_shoulder_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var pos := Vector3.ZERO
	pos += Vector3(0, s.lower_spine_size.y, 0)
	var b := Basis.from_euler(Vector3(s.slouchiness_center_spine, 0, 0))
	pos += b * Vector3(0, s.middle_spine_size.y, 0)
	pos += Vector3(0, s.upper_spine_size.y, 0)
	b = Basis.from_euler(Vector3(-s.slouchiness_chest, 0, 0))
	pos += b * Vector3(0, s.chest_size.y, 0)
	if left:
		b = Basis.from_euler(Vector3(0, s.shoulder_back, deg_to_rad(90) - s.shoulder_height))
	else:
		b = Basis.from_euler(Vector3(0, -s.shoulder_back, deg_to_rad(-90) + s.shoulder_height))
	pos += b * Vector3(0, s.shoulder_width.y, 0)
	return pos

static func _compute_arm_tip_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var shoulder := _compute_arm_shoulder_local(left, s)
	var arm_length := s.upper_arm_size.y + s.lower_arm_size.y \
		+ 0.4 * s.upper_arm_size.x \
		+ 0.4 * s.lower_arm_size.z
	var actual_distance: float = lerp(arm_length, 0.0, s.arm_bentness)
	var arm_dir := Basis(Vector3.FORWARD, s.arm_openness_angle * sign_x) * Vector3.DOWN
	return shoulder + arm_dir * actual_distance

static func _compute_arm_pole_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var shoulder := _compute_arm_shoulder_local(left, s)
	var arm_dir := Basis(Vector3.FORWARD, s.arm_openness_angle * sign_x) * Vector3.DOWN
	var elbow := shoulder + arm_dir * s.upper_arm_size.y

	var backward := Vector3(0, 0, 1)
	var outward  := Vector3(sign_x, 0, 0)
	var pole_dir: Vector3
	if s.elbow_pole_direction >= 0.5:
		pole_dir = backward.lerp(outward,  (s.elbow_pole_direction - 0.5) * 2.0).normalized()
	else:
		pole_dir = backward.lerp(-outward, (0.5 - s.elbow_pole_direction) * 2.0).normalized()

	return elbow + pole_dir * s.upper_arm_size.y * 0.8 + Vector3(0, 0, 0.5)


func update(_delta: float, char_rigidbody: CharacterRigidBody3D, inst: EntityInstantiation, ik_util: IkUtil) -> void:
	_update_step_radius(char_rigidbody, inst.arch_final, ik_util)

func _update_step_radius(char_rigidbody: CharacterRigidBody3D, entity_stats: EntityArchetype, ik_util: IkUtil) -> void:
	var dxz := Vector2(char_rigidbody.linear_velocity.x, char_rigidbody.linear_velocity.z)
	var instant_speed = dxz.length()
	var min_speed = 0.01
	var max_speed: float = entity_stats.speed * entity_stats.sprint_multiplier * CharacterRigidBody3D.SPEED_SCALE
	var speed_range = max(max_speed - min_speed, 0.01)
	var t = clamp((instant_speed - min_speed) / speed_range, 0.0, 1.0)
	ik_util.current_step_radius = lerp(step_radius_min, step_radius_max, t)

static func lerp_range(min_val: float, max_val: float, t: float) -> float:
	return min_val + (max_val - min_val) * clamp(t, 0.0, 1.0)
