class_name StableSizesUtil

var leg_height : float
var torso_height : float
var head_height : float
var hips_width : float
var shoulders_width : float
var skel : BoneInstantiator

static func create(new_skel: BoneInstantiator, new_leg_height: float, new_torso_height: float, new_head_height: float, new_hips_width: float, new_shoulders_width: float) -> StableSizesUtil:
	var newStableUtil = StableSizesUtil.new()
	newStableUtil.leg_height = new_leg_height
	newStableUtil.torso_height = new_torso_height
	newStableUtil.head_height = new_head_height
	newStableUtil.hips_width = new_hips_width
	newStableUtil.shoulders_width = new_shoulders_width
	newStableUtil.skel = new_skel
	return newStableUtil

func set_sizes() -> void:
	# CABEZA Y CUELLO
	if skel.has_neck:
		skel.neck_size = Vector3(0.1, head_height * 0.4, 0.1)
		skel.head_size = Vector3(0.3, head_height * 0.6, 0.3)
	else:
		skel.neck_size = Vector3.ZERO
		skel.head_size = Vector3(0.3, head_height, 0.3)
	# TORSO
	skel.lower_spine_size = Vector3(0.1, torso_height * 0.1, 0.1)
	skel.middle_spine_size = Vector3(0.1, torso_height * 0.2, 0.1)
	skel.upper_spine_size = Vector3(0.1, torso_height * 0.3, 0.1)
	skel.chest_size = Vector3(0.2, torso_height * 0.4, 0.2)
	# PIERNAS
	skel.upper_leg_size = Vector3(0.1, leg_height * 0.45, 0.1)
	skel.lower_leg_size = Vector3(0.1, leg_height * 0.55, 0.1)
	skel.upper_feet_size = Vector3(0.1, leg_height * 0.2, 0.1)
	skel.lower_feet_size = Vector3(0.1, leg_height * 0.02, 0.1)
	# BRAZOS
	var arm_total := leg_height *0.5#torso_height * arms_proportion
	skel.upper_arm_size = Vector3(0.1, arm_total * 0.45, 0.1)
	skel.lower_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	# ANCHURAS HORIZONTALES
	skel.hip_width = Vector3( 0.1, hips_width, 0.1)
	skel.shoulder_width = Vector3( 0.1, shoulders_width, 0.1)
	
	skel.raycast_leg_lenght = leg_height
	skel.distance_from_ground = leg_height * (skel.distance_from_ground_factor)
	
