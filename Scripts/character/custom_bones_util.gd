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
	# Hueso raíz
	bones_util.lower_spine = CustomBone.create(sizes.lower_spine_size, Vector3.ZERO, Color.WHITE_SMOKE, sizes.lower_spine_offset)
	# Chest and spine
	bones_util.middle_spine = CustomBone.createFromToUp(bones_util.lower_spine, sizes.middle_spine_size, sizes.middle_spine_offset, 0.0,0.0, Color.SKY_BLUE, true)
	bones_util.upper_spine = CustomBone.createFromToUp(bones_util.middle_spine, sizes.upper_spine_size, sizes.upper_spine_offset, 0.0,0.0, Color.BURLYWOOD , true)
	bones_util.chest = CustomBone.createFromToUp(bones_util.upper_spine, sizes.chest_size, sizes.chest_offset, 0.0,0.0, Color.BURLYWOOD , true)
	bones_util.left_hip = CustomBone.createFromToLeft(bones_util.lower_spine, sizes.hip_size, sizes.hip_offset, 0.0,0.0, Color.ROYAL_BLUE , false)
	bones_util.right_hip = CustomBone.createFromToRight(bones_util.lower_spine, sizes.hip_size, sizes.hip_offset, 0.0,0.0, Color.ROYAL_BLUE , false)

	# Legs
	bones_util.left_upper_leg = CustomBone.createFromToDown(bones_util.left_hip, sizes.upper_leg_size, sizes.upper_leg_offset, 0.0,0.0, Color.YELLOW , true)
	bones_util.left_lower_leg = CustomBone.createFromToDown(bones_util.left_upper_leg, sizes.lower_leg_size, sizes.lower_leg_offset, 0.0,0.0, Color.ORANGE , true)
	bones_util.right_upper_leg = CustomBone.createFromToDown(bones_util.right_hip, sizes.upper_leg_size, sizes.upper_leg_offset, 0.0,0.0, Color.YELLOW , true)
	bones_util.right_lower_leg = CustomBone.createFromToDown(bones_util.right_upper_leg, sizes.lower_leg_size, sizes.lower_leg_offset, 0.0,0.0, Color.ORANGE , true)
	bones_util.right_upper_feet = CustomBone.createFromToForward(bones_util.right_lower_leg, sizes.upper_feet_size, sizes.upper_feet_offset, 0.0,0.0, Color.ORANGE , true)
	bones_util.left_upper_feet = CustomBone.createFromToForward(bones_util.left_lower_leg, sizes.upper_feet_size, sizes.upper_feet_offset, 0.0,0.0, Color.ORANGE , true)
	
	var slouchiness =  SkeletonSizesUtil.lerp_range(0.1,0.6,entity_stats.slouch)
	if entity_stats.has_neck:
		bones_util.neck = CustomBone.createFromToUp(bones_util.chest, sizes.neck_size, sizes.neck_offset, 0.0,-slouchiness, Color.RED , true)
	bones_util.head = CustomBone.createFromToUp(bones_util.neck if bones_util.neck else bones_util.chest, sizes.head_size, sizes.head_offset, 0.0,0.0, Color.GREEN , true)
	# Shoulders
	bones_util.left_shoulder = CustomBone.createFromToLeft(bones_util.chest, sizes.shoulder_width, sizes.shoulder_offset, 0.0,0.3, Color.CHOCOLATE , true)
	bones_util.right_shoulder = CustomBone.createFromToRight(bones_util.chest, sizes.shoulder_width, sizes.shoulder_offset, 0.0,-0.3, Color.GREEN , true)

	# Arms
	bones_util.right_upper_arm = CustomBone.createFromToDown(bones_util.right_shoulder, sizes.upper_arm_size, sizes.upper_arm_offset, -1.0,0.0, Color.VIOLET , true)
	bones_util.left_upper_arm = CustomBone.createFromToDown(bones_util.left_shoulder, sizes.upper_arm_size, sizes.upper_arm_offset, 0.0,0.0, Color.VIOLET , true)
	
	bones_util.right_lower_arm = CustomBone.createFromToDown(bones_util.right_upper_arm, sizes.lower_arm_size, sizes.lower_arm_offset, 0.0,0.0, Color.RED , true)
	bones_util.left_lower_arm = CustomBone.createFromToDown(bones_util.left_upper_arm, sizes.lower_arm_size, sizes.lower_arm_offset, 0.0,0.0, Color.RED , true)
	return bones_util
