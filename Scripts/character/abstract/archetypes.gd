class_name EntityArchetype

enum Archetype {fat_man, kid, tall_lanky, giga, old, normal}

# BASE STATS
var strenght : float = 1.0
var weight : float = 60.0
var speed_forw : float = 1.0
var speed_back : float = 1.0
var speed_side : float = 1.0
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
var distance_from_ground_factor := 0.15  #tiene las piernas 15% flexionadas cuando esta en el piso


var uncompatible_archetypes : Array[Archetype] = [] # con que otros arquetipos no se puede mezclar
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
	if(archetype == Archetype.normal):
		return normal_arch()
	else:
		return old_arch()

static func fat_man_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 1.0
	arch.weight = 120.0
	arch.speed_forw = 2.0
	arch.speed_back = 2.0
	arch.speed_side = 2.0
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
	arch.shoulders_back = 0.8
	arch.arms_openness = 1.0
	arch.fatness = 1.0
	arch.muscularity = 0.7
	arch.has_neck = true
	arch.height = 1.9
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.35
	arch.legs_to_feet_proportion = 0.45
	arch.hips_width_proportion = 0.12
	arch.shoulder_width_proportion = 0.16
	arch.distance_from_ground_factor = 0.15
	arch.uncompatible_archetypes = [Archetype.kid] as Array[Archetype]
	arch.archetype_frequency = 1.0
	return arch

static func kid_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.3
	arch.weight = 30.0
	arch.speed_forw = 4.0
	arch.speed_back = 4.0
	arch.speed_side = 4.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 1.5
	arch.foward_stability = 0.5
	arch.backwards_stability = 0.5
	arch.sideways_stability = 0.5
	arch.stability_spring = 0.7
	arch.stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.throw_strenght = 0.2
	arch.reach = 0.35
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.time_to_max_jump = 0.5
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
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
	arch.fatness = 0.0
	arch.muscularity = 0.3
	arch.has_neck = true
	arch.height = 1.3
	arch.neck_to_head_proportion = 0.25
	arch.chest_to_low_spine_proportion = 0.3
	arch.legs_to_feet_proportion = 0.45
	arch.hips_width_proportion = 0.1
	arch.shoulder_width_proportion = 0.15
	arch.distance_from_ground_factor = 0.15
	arch.uncompatible_archetypes = [Archetype.fat_man, Archetype.tall_lanky, Archetype.giga, Archetype.old] as Array[Archetype]
	arch.archetype_frequency = 1.0
	return arch

static func tall_lanky_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 80.0
	arch.speed_forw = 3.0
	arch.speed_back = 3.0
	arch.speed_side = 3.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 3.0
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
	arch.slouch = 0.3
	arch.shoulders_height = 0.0
	arch.shoulders_back = 0.0
	arch.arms_openness = 0.2
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
	arch.uncompatible_archetypes = [Archetype.fat_man, Archetype.tall_lanky, Archetype.giga, Archetype.old] as Array[Archetype]
	arch.archetype_frequency = 0.75
	return arch

static func giga_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 120.0
	arch.speed_forw = 2.0
	arch.speed_back = 2.0
	arch.speed_side = 2.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 3.0
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
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 1.0
	arch.human_chance = 1.0
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
	arch.height = 1.8
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.35
	arch.legs_to_feet_proportion = 0.45
	arch.hips_width_proportion = 0.08
	arch.shoulder_width_proportion = 0.22
	arch.distance_from_ground_factor = 0.06
	arch.uncompatible_archetypes = [Archetype.kid] as Array[Archetype]
	arch.archetype_frequency = 0.6
	return arch

static func old_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 120.0
	arch.speed_forw = 2.0
	arch.speed_back = 2.0
	arch.speed_side = 2.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 3.0
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
	arch.min_age = 1
	arch.max_age = 99
	arch.robot_chance = 0.0
	arch.alien_chance = 0.0
	arch.human_chance = 1.0
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
	arch.slouch = 1.0
	arch.shoulders_height = 0.5
	arch.shoulders_back = 0.0
	arch.arms_openness = 0.5
	arch.fatness = 0.1
	arch.muscularity = 0.1
	arch.has_neck = true
	arch.height = 1.7
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.hips_width_proportion = 0.065
	arch.shoulder_width_proportion = 0.11
	arch.distance_from_ground_factor = 0.03
	arch.uncompatible_archetypes = [Archetype.kid] as Array[Archetype]
	arch.archetype_frequency = 0.5
	return arch

static func normal_arch() -> EntityArchetype:
	var arch = EntityArchetype.new()
	arch.strenght = 0.55
	arch.weight = 80.0
	arch.speed_forw = 3.0
	arch.speed_back = 3.0
	arch.speed_side = 3.0
	arch.sprint_multiplier = 2.0
	arch.acceleration = 3.0
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
	arch.min_age = 20
	arch.max_age = 40
	arch.robot_chance = 1.0
	arch.alien_chance = 1.0
	arch.human_chance = 1.0
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
	arch.slouch = 0.3
	arch.shoulders_height = 0.0
	arch.shoulders_back = 0.0
	arch.arms_openness = 0.2
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
	arch.uncompatible_archetypes = [] as Array[Archetype]
	arch.archetype_frequency = 1.0
	return arch

static func max_leg_lenght() -> float:
	var leg_lenght : float = tall_lanky_arch().legs_to_feet_proportion * tall_lanky_arch().height
	return leg_lenght
