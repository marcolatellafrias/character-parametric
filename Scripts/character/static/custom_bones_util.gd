class_name CustomBonesUtil

var lower_spine : CustomBone
var middle_spine : CustomBone
var higher_spine : CustomBone
var chest : CustomBone
var left_hip : CustomBone
var right_hip : CustomBone
var left_higher_leg : CustomBone
var left_lower_leg : CustomBone
var right_higher_leg : CustomBone
var right_lower_leg : CustomBone
var right_foot : CustomBone
var left_foot : CustomBone
var neck : CustomBone
var head : CustomBone
var left_shoulder : CustomBone
var right_shoulder : CustomBone
var right_upper_arm : CustomBone
var right_lower_arm : CustomBone
var left_upper_arm : CustomBone
var left_lower_arm : CustomBone

## Todos los huesos, para lo que necesite recorrerlos enteros (visibilidad, debug). `neck` puede ser
## null si el arquetipo no tiene cuello, así que el que la use tiene que chequear validez.
func get_all_bones() -> Array[CustomBone]:
	return [
		lower_spine, middle_spine, higher_spine, chest,
		left_hip, right_hip,
		left_higher_leg, left_lower_leg, right_higher_leg, right_lower_leg,
		left_foot, right_foot,
		left_shoulder, right_shoulder,
		left_upper_arm, left_lower_arm, right_upper_arm, right_lower_arm,
		neck, head,
	]

static func create(sizes: SkeletonSizesUtil, inst: EntityInstantiation) -> CustomBonesUtil:
	var bones_util = CustomBonesUtil.new()
	var entity_stats := inst.arch_final

	bones_util.lower_spine  = CustomBone.create(sizes.lower_spine_size, Vector3.ZERO, Color.WHITE_SMOKE, sizes.lower_spine_offset)
	bones_util.middle_spine = CustomBone.createFromToUp(bones_util.lower_spine, sizes.middle_spine_size, sizes.middle_spine_offset, 0.0, sizes.slouchiness_center_spine, Color.ROYAL_BLUE, true)
	bones_util.higher_spine  = CustomBone.createFromToUp(bones_util.middle_spine, sizes.higher_spine_size, sizes.higher_spine_offset, 0.0, 0.0, Color.BURLYWOOD, true)
	bones_util.chest        = CustomBone.createFromToUp(bones_util.higher_spine, sizes.chest_size, sizes.chest_offset, 0.0, -sizes.slouchiness_chest, Color.BURLYWOOD, true)
	bones_util.left_hip     = CustomBone.createFromToLeft(bones_util.lower_spine, sizes.hip_size, sizes.hip_offset, 0.0, 0.0, Color.ROYAL_BLUE, false)
	bones_util.right_hip    = CustomBone.createFromToRight(bones_util.lower_spine, sizes.hip_size, sizes.hip_offset, 0.0, 0.0, Color.ROYAL_BLUE, false)

	bones_util.left_higher_leg  = CustomBone.createFromToDown(bones_util.left_hip, sizes.higher_leg_size, sizes.higher_leg_offset, 0.0, 0.0, Color.DARK_ORANGE, true)
	bones_util.left_lower_leg  = CustomBone.createFromToDown(bones_util.left_higher_leg, sizes.lower_leg_size, sizes.lower_leg_offset, 0.0, 0.0, Color.ORANGE, true)
	bones_util.right_higher_leg = CustomBone.createFromToDown(bones_util.right_hip, sizes.higher_leg_size, sizes.higher_leg_offset, 0.0, 0.0, Color.DARK_ORANGE, true)
	bones_util.right_lower_leg = CustomBone.createFromToDown(bones_util.right_higher_leg, sizes.lower_leg_size, sizes.lower_leg_offset, 0.0, 0.0, Color.ORANGE, true)
	bones_util.right_foot = CustomBone.createFromToForward(bones_util.right_lower_leg, sizes.foot_size, sizes.foot_offset, 0.0, 0.0, Color.SIENNA, true)
	bones_util.left_foot  = CustomBone.createFromToForward(bones_util.left_lower_leg, sizes.foot_size, sizes.foot_offset, 0.0, 0.0, Color.SIENNA, true)

	if entity_stats.has_neck:
		bones_util.neck = CustomBone.createFromToUp(bones_util.chest, sizes.neck_size, sizes.neck_offset, 0.0, -sizes.slouchiness_neck, Color.CORAL, true)
	bones_util.head = CustomBone.createFromToUp(bones_util.neck if bones_util.neck else bones_util.chest, sizes.head_size, sizes.head_offset, 0.0, 0.0, Color.DEEP_PINK, true,false)

	bones_util.left_shoulder  = CustomBone.createFromToLeft(bones_util.chest, sizes.shoulder_width, sizes.shoulder_offset, sizes.shoulder_back, -sizes.shoulder_height, Color.CHOCOLATE, true)
	bones_util.right_shoulder = CustomBone.createFromToRight(bones_util.chest, sizes.shoulder_width, sizes.shoulder_offset, -sizes.shoulder_back, sizes.shoulder_height, Color.ROYAL_BLUE, true)

	bones_util.right_upper_arm = CustomBone.createFromToDown(bones_util.right_shoulder, sizes.upper_arm_size, sizes.upper_arm_offset, 0.0, 0.0, Color.VIOLET, true)
	bones_util.left_upper_arm  = CustomBone.createFromToDown(bones_util.left_shoulder,  sizes.upper_arm_size, sizes.upper_arm_offset, 0.0, 0.0, Color.VIOLET, true)
	bones_util.right_lower_arm = CustomBone.createFromToDown(bones_util.right_upper_arm, sizes.lower_arm_size, sizes.lower_arm_offset, 0.0, 0.0, Color.DEEP_PINK, true)
	bones_util.left_lower_arm  = CustomBone.createFromToDown(bones_util.left_upper_arm,  sizes.lower_arm_size, sizes.lower_arm_offset, 0.0, 0.0, Color.DEEP_PINK, true)

	return bones_util
