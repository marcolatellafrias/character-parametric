class_name EntityArchetype

enum Archetype {fat_man, kid, tall_lanky, giga, old}

# BASE STATS
var strenght : float = 1.0
var weight : float = 60.0
var speed : float = 1.0
var back_speed_factor : float = 1.0
var lateral_speed_factor : float = 1.0
var sprint_multiplier : float = 2.0
var acceleration : float = 4.0
var foward_stability : float = 1.0
var backwards_stability : float = 1.0
var sideways_stability : float = 1.0
var stability_spring : float = 1.0
var stability_damp : float = 1.0
var time_to_standup : float = 4.0

# REACH/ARMS
var throw_strenght : float = 1.0
var reach : float = 1.0
var reach_multiplier : float = 1.2

# JUMP
var jump_strenght : float = 0.5
var time_to_max_jump : float = 1.0

# AGE RANGE
var min_age : float = 1
var max_age : float = 99

# SPECIE PROBABILITIES
var robot_chance : float = 0.3
var alien_chance : float = 0.3
var human_chance : float = 1.0

# ANIMATIONS
var shoulder_swing_min : float = 0.5
var shoulder_swing_max : float = 0.5
var hip_swing_min : float = 0.5
var hip_swing_max : float = 0.5
var root_bounciness_min  : float = 0.5
var root_bounciness_max  : float = 0.5
var step_height_min : float = 0.5
var step_height_max : float = 0.5
var step_radius_min : float = 0.5
var step_radius_max : float = 0.5
var leg_cripple_chance : float = 0.0

# POSTURE
var slouch : float = 0.0
var shoulders_height : float = 0.5
var shoulders_back : float = 0.5
var arms_openness : float = 0.5

# VISUAL
var fatness : float = 0.5
var muscularity : float = 0.5
var has_neck: bool = true

# PROPORTIONS
var height : float = 1.8
var neck_to_head_proportion: float = 1.0
var chest_to_low_spine_proportion : float = 1.0
var legs_to_feet_proportion : float = 1.0
var hips_width_proportion : float = 1.0
var shoulder_width_proportion : float = 1.0
var distance_from_ground_factor := 0.15

var uncompatible_archetypes : Array[Archetype] = []
var archetype_frequency : float = 1.0

static func create(archetype: Archetype) -> EntityArchetype:
	if(archetype == Archetype.fat_man):
		return fat_man_arch()
	if(archetype == Archetype.tall_lanky):
		return tall_lanky_arch()
	if(archetype == Archetype.kid):
		return kid_arch()
	if(archetype == Archetype.giga):
		return giga_arch()
	else:
		return old_arch()

static func fat_man_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 1.0
	arch.weight = 120.0
	arch.speed = 2.0
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 4.0
	arch.foward_stability = 0.7
	arch.backwards_stability = 0.7
	arch.sideways_stability = 0.7
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 2.0
	arch.throw_strenght = 0.7
	arch.reach = 0.65
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.3
	arch.time_to_max_jump = 1.0
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.3
	arch.alien_chance = 0.6
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing_min = 0.5
	arch.shoulder_swing_max = 0.5
	arch.hip_swing_min = 0.5
	arch.hip_swing_max = 0.5
	arch.root_bounciness_min = 0.5
	arch.root_bounciness_max = 0.5
	arch.step_height_min = 0.5
	arch.step_height_max = 0.5
	arch.step_radius_min = 0.5
	arch.step_radius_max = 0.5
	arch.leg_cripple_chance = 0.1
	arch.slouch = 0.0
	arch.shoulders_height = 0.8
	arch.shoulders_back = 0.7
	arch.arms_openness = 1.0
	arch.fatness = 1.0
	arch.muscularity = 0.7
	arch.has_neck = true
	arch.height = 1.9
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.35
	arch.legs_to_feet_proportion = 0.45
	arch.hips_width_proportion = 0.12
	arch.shoulder_width_proportion = 0.12
	arch.distance_from_ground_factor = 0.15
	return arch

static func kid_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.3
	arch.weight = 30.0
	arch.speed = 4.0
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 1.5
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.2
	arch.reach = 0.38
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.time_to_max_jump = 0.5
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing_min = 0.5
	arch.shoulder_swing_max = 0.5
	arch.hip_swing_min = 0.5
	arch.hip_swing_max = 0.5
	arch.root_bounciness_min = 0.5
	arch.root_bounciness_max = 0.5
	arch.step_height_min = 0.5
	arch.step_height_max = 0.5
	arch.step_radius_min = 0.5
	arch.step_radius_max = 0.5
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.0
	arch.shoulders_height = 0.0
	arch.shoulders_back = 0.0
	arch.arms_openness = 0.8
	arch.fatness = 0.2
	arch.muscularity = 0.25
	arch.has_neck = true
	arch.height = 1.35
	arch.neck_to_head_proportion = 0.25
	arch.chest_to_low_spine_proportion = 0.27
	arch.legs_to_feet_proportion = 0.48
	arch.hips_width_proportion = 0.1
	arch.shoulder_width_proportion = 0.15
	arch.distance_from_ground_factor = 0.06
	return arch

static func tall_lanky_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 80.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 0.4
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.4
	arch.reach = 1.0
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.time_to_max_jump = 0.5
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.7
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing_min = 0.5
	arch.shoulder_swing_max = 0.5
	arch.hip_swing_min = 0.5
	arch.hip_swing_max = 0.5
	arch.root_bounciness_min = 0.5
	arch.root_bounciness_max = 0.5
	arch.step_height_min = 0.4
	arch.step_height_max = 0.4
	arch.step_radius_min = 0.4
	arch.step_radius_max = 0.4
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.3
	arch.shoulders_height = 0.0
	arch.shoulders_back = 0.0
	arch.arms_openness = 0.25
	arch.fatness = 0.5
	arch.muscularity = 0.4
	arch.has_neck = true
	arch.height = 2.2
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.hips_width_proportion = 0.065
	arch.shoulder_width_proportion = 0.14
	arch.distance_from_ground_factor = 0.04
	return arch

static func giga_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 120.0
	arch.speed = 0.3
	arch.back_speed_factor = 1.0
	arch.lateral_speed_factor = 1.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 0.3
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.8
	arch.reach = 0.8
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.time_to_max_jump = 0.5
	arch.min_age = 20
	arch.max_age = 90
	arch.robot_chance = 0.0
	arch.alien_chance = 1.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing_min = 0.5
	arch.shoulder_swing_max = 0.5
	arch.hip_swing_min = 0.5
	arch.hip_swing_max = 0.5
	arch.root_bounciness_min = 0.5
	arch.root_bounciness_max = 0.5
	arch.step_height_min = 0.5
	arch.step_height_max = 0.5
	arch.step_radius_min = 0.5
	arch.step_radius_max = 0.5
	arch.leg_cripple_chance = 0.0
	arch.slouch = 0.0
	arch.shoulders_height = 1.0
	arch.shoulders_back = 1.0
	arch.arms_openness = 0.6
	arch.fatness = 0.5
	arch.muscularity = 1.0
	arch.has_neck = true
	arch.height = 1.75
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.37
	arch.legs_to_feet_proportion = 0.43
	arch.hips_width_proportion = 0.08
	arch.shoulder_width_proportion = 0.22
	arch.distance_from_ground_factor = 0.06
	return arch

static func old_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 120.0
	arch.speed = 0.15
	arch.back_speed_factor = 0.6
	arch.lateral_speed_factor = 0.8
	arch.sprint_multiplier = 2.0
	arch.acceleration = 0.5
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.8
	arch.reach = 0.5
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.time_to_max_jump = 0.5
	arch.min_age = 50
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	arch.shoulder_swing_min = 0.5
	arch.shoulder_swing_max = 0.5
	arch.hip_swing_min = 0.5
	arch.hip_swing_max = 0.5
	arch.root_bounciness_min = 0.5
	arch.root_bounciness_max = 0.5
	arch.step_height_min = 0.3
	arch.step_height_max = 0.3
	arch.step_radius_min = 0.3
	arch.step_radius_max = 0.3
	arch.leg_cripple_chance = 0.0
	arch.slouch = 1.0
	arch.shoulders_height = 0.5
	arch.shoulders_back = 0.0
	arch.arms_openness = 0.5
	arch.fatness = 0.1
	arch.muscularity = 0.1
	arch.has_neck = true
	arch.height = 1.65
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.hips_width_proportion = 0.065
	arch.shoulder_width_proportion = 0.11
	arch.distance_from_ground_factor = 0.03
	return arch

static func max_leg_lenght() -> float:
	var leg_lenght : float = tall_lanky_arch().legs_to_feet_proportion * tall_lanky_arch().height
	return leg_lenght

func blend_with(b: EntityArchetype, t: float) -> EntityArchetype:
	var r := EntityArchetype.new()
	r.strenght                      = lerpf(strenght, b.strenght, t)
	r.weight                        = lerpf(weight, b.weight, t)
	r.speed                         = lerpf(speed, b.speed, t)
	r.back_speed_factor             = lerpf(back_speed_factor, b.back_speed_factor, t)
	r.lateral_speed_factor          = lerpf(lateral_speed_factor, b.lateral_speed_factor, t)
	r.sprint_multiplier             = lerpf(sprint_multiplier, b.sprint_multiplier, t)
	r.acceleration                  = lerpf(acceleration, b.acceleration, t)
	r.foward_stability              = lerpf(foward_stability, b.foward_stability, t)
	r.backwards_stability           = lerpf(backwards_stability, b.backwards_stability, t)
	r.sideways_stability            = lerpf(sideways_stability, b.sideways_stability, t)
	r.stability_spring              = lerpf(stability_spring, b.stability_spring, t)
	r.stability_damp                = lerpf(stability_damp, b.stability_damp, t)
	r.time_to_standup               = lerpf(time_to_standup, b.time_to_standup, t)
	r.throw_strenght                = lerpf(throw_strenght, b.throw_strenght, t)
	r.reach                         = lerpf(reach, b.reach, t)
	r.reach_multiplier              = lerpf(reach_multiplier, b.reach_multiplier, t)
	r.jump_strenght                 = lerpf(jump_strenght, b.jump_strenght, t)
	r.time_to_max_jump              = lerpf(time_to_max_jump, b.time_to_max_jump, t)
	r.min_age                       = lerpf(min_age, b.min_age, t)
	r.max_age                       = lerpf(max_age, b.max_age, t)
	r.robot_chance                  = lerpf(robot_chance, b.robot_chance, t)
	r.alien_chance                  = lerpf(alien_chance, b.alien_chance, t)
	r.human_chance                  = lerpf(human_chance, b.human_chance, t)
	r.shoulder_swing_min            = lerpf(shoulder_swing_min, b.shoulder_swing_min, t)
	r.shoulder_swing_max            = lerpf(shoulder_swing_max, b.shoulder_swing_max, t)
	r.hip_swing_min                 = lerpf(hip_swing_min, b.hip_swing_min, t)
	r.hip_swing_max                 = lerpf(hip_swing_max, b.hip_swing_max, t)
	r.root_bounciness_min           = lerpf(root_bounciness_min, b.root_bounciness_min, t)
	r.root_bounciness_max           = lerpf(root_bounciness_max, b.root_bounciness_max, t)
	r.step_height_min               = lerpf(step_height_min, b.step_height_min, t)
	r.step_height_max               = lerpf(step_height_max, b.step_height_max, t)
	r.step_radius_min               = lerpf(step_radius_min, b.step_radius_min, t)
	r.step_radius_max               = lerpf(step_radius_max, b.step_radius_max, t)
	r.leg_cripple_chance            = lerpf(leg_cripple_chance, b.leg_cripple_chance, t)
	r.slouch                        = lerpf(slouch, b.slouch, t)
	r.shoulders_height              = lerpf(shoulders_height, b.shoulders_height, t)
	r.shoulders_back                = lerpf(shoulders_back, b.shoulders_back, t)
	r.arms_openness                 = lerpf(arms_openness, b.arms_openness, t)
	r.fatness                       = lerpf(fatness, b.fatness, t)
	r.muscularity                   = lerpf(muscularity, b.muscularity, t)
	r.has_neck                      = has_neck
	r.height                        = lerpf(height, b.height, t)
	r.neck_to_head_proportion       = lerpf(neck_to_head_proportion, b.neck_to_head_proportion, t)
	r.chest_to_low_spine_proportion = lerpf(chest_to_low_spine_proportion, b.chest_to_low_spine_proportion, t)
	r.legs_to_feet_proportion       = lerpf(legs_to_feet_proportion, b.legs_to_feet_proportion, t)
	r.hips_width_proportion         = lerpf(hips_width_proportion, b.hips_width_proportion, t)
	r.shoulder_width_proportion     = lerpf(shoulder_width_proportion, b.shoulder_width_proportion, t)
	r.distance_from_ground_factor   = lerpf(distance_from_ground_factor, b.distance_from_ground_factor, t)
	return r
