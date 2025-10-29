class_name CustomBonesUtil

var lower_spine : CustomBone
var middle_spine : CustomBone
var upper_spine : CustomBone
var chest : CustomBone
var left_hip : CustomBone
var right_hip : CustomBone
var left_upper_leg : CustomBone
var left_lower_leg : CustomBone
var right_upper_leg : CustomBone
var right_lower_leg : CustomBone
var right_upper_feet : CustomBone
var left_upper_feet : CustomBone
var neck : CustomBone
var head : CustomBone
var left_shoulder : CustomBone
var right_shoulder : CustomBone
var right_upper_arm : CustomBone
var right_lower_arm : CustomBone
var left_upper_arm : CustomBone
var left_lower_arm : CustomBone

static func create(sizes: SkeletonSizesUtil, entity_stats: EntityStats) -> CustomBonesUtil:
	var bones_util = CustomBonesUtil.new()
	
	
	
	# Chest and spine
	var slouchiness_chest =  SkeletonSizesUtil.lerp_range(0.0,0.6,entity_stats.slouch)
	var slouchiness_center_spine =  SkeletonSizesUtil.lerp_range(0.0,0.6,entity_stats.slouch)
	bones_util.lower_spine = CustomBone.create(sizes.lower_spine_size, Vector3.ZERO, Color.WHITE_SMOKE, sizes.lower_spine_offset)# Hueso raíz
	bones_util.middle_spine = CustomBone.createFromToUp(bones_util.lower_spine, sizes.middle_spine_size, sizes.middle_spine_offset, 0.0,slouchiness_center_spine, Color.ROYAL_BLUE, true)
	bones_util.upper_spine = CustomBone.createFromToUp(bones_util.middle_spine, sizes.upper_spine_size, sizes.upper_spine_offset, 0.0,0.0, Color.BURLYWOOD , true)
	bones_util.chest = CustomBone.createFromToUp(bones_util.upper_spine, sizes.chest_size, sizes.chest_offset, 0.0,-slouchiness_chest, Color.BURLYWOOD , true)
	bones_util.left_hip = CustomBone.createFromToLeft(bones_util.lower_spine, sizes.hip_size, sizes.hip_offset, 0.0,0.0, Color.ROYAL_BLUE , false)
	bones_util.right_hip = CustomBone.createFromToRight(bones_util.lower_spine, sizes.hip_size, sizes.hip_offset, 0.0,0.0, Color.ROYAL_BLUE , false)

	# Legs
	bones_util.left_upper_leg = CustomBone.createFromToDown(bones_util.left_hip, sizes.upper_leg_size, sizes.upper_leg_offset, 0.0,0.0, Color.DARK_ORANGE , true)
	bones_util.left_lower_leg = CustomBone.createFromToDown(bones_util.left_upper_leg, sizes.lower_leg_size, sizes.lower_leg_offset, 0.0,0.0, Color.ORANGE , true)
	bones_util.right_upper_leg = CustomBone.createFromToDown(bones_util.right_hip, sizes.upper_leg_size, sizes.upper_leg_offset, 0.0,0.0, Color.DARK_ORANGE , true)
	bones_util.right_lower_leg = CustomBone.createFromToDown(bones_util.right_upper_leg, sizes.lower_leg_size, sizes.lower_leg_offset, 0.0,0.0, Color.ORANGE , true)
	bones_util.right_upper_feet = CustomBone.createFromToForward(bones_util.right_lower_leg, sizes.upper_feet_size, sizes.upper_feet_offset, 0.0,0.0, Color.SIENNA , true)
	bones_util.left_upper_feet = CustomBone.createFromToForward(bones_util.left_lower_leg, sizes.upper_feet_size, sizes.upper_feet_offset, 0.0,0.0, Color.SIENNA , true)
	
	var slouchiness_neck =  SkeletonSizesUtil.lerp_range(0.2,0.6,entity_stats.slouch)
	if entity_stats.has_neck:
		bones_util.neck = CustomBone.createFromToUp(bones_util.chest, sizes.neck_size, sizes.neck_offset, 0.0,-slouchiness_neck, Color.CORAL , true)
	bones_util.head = CustomBone.createFromToUp(bones_util.neck if bones_util.neck else bones_util.chest, sizes.head_size, sizes.head_offset, 0.0,0.0, Color.DEEP_PINK , true)
	
	# Shoulders
	var shoulder_height =  SkeletonSizesUtil.lerp_range(-0.3,0.3,entity_stats.shoulders_height)
	var shoulder_back =  SkeletonSizesUtil.lerp_range(0.0,0.3,entity_stats.shoulders_back)
	bones_util.left_shoulder = CustomBone.createFromToLeft(bones_util.chest, sizes.shoulder_width, sizes.shoulder_offset, shoulder_back,-shoulder_height, Color.CHOCOLATE , true)
	bones_util.right_shoulder = CustomBone.createFromToRight(bones_util.chest, sizes.shoulder_width, sizes.shoulder_offset, -shoulder_back,shoulder_height, Color.ROYAL_BLUE , true)
	
	# Arms
	var upper_arms_openness =  SkeletonSizesUtil.lerp_range(0.0,0.6,entity_stats.arms_openness)
	bones_util.right_upper_arm = CustomBone.createFromToDown(bones_util.right_shoulder, sizes.upper_arm_size, sizes.upper_arm_offset, -upper_arms_openness,0.0, Color.VIOLET , true)
	bones_util.left_upper_arm = CustomBone.createFromToDown(bones_util.left_shoulder, sizes.upper_arm_size, sizes.upper_arm_offset, upper_arms_openness,0.0, Color.VIOLET , true)
	
	var lower_arms_openness =  SkeletonSizesUtil.lerp_range(0.0,0.3, entity_stats.arms_openness)
	bones_util.right_lower_arm = CustomBone.createFromToDown(bones_util.right_upper_arm, sizes.lower_arm_size, sizes.lower_arm_offset, -lower_arms_openness,0.0, Color.DEEP_PINK , true)
	bones_util.left_lower_arm = CustomBone.createFromToDown(bones_util.left_upper_arm, sizes.lower_arm_size, sizes.lower_arm_offset, lower_arms_openness,0.0, Color.DEEP_PINK , true)
	return bones_util
