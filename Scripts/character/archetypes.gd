class_name EntityStats

enum Archetype {fat_man, kid, tall_lanky, giga}
enum Specie {human, alien, robot}

#STATS
var weight : float
var speed_forw : float
var speed_back : float
var speed_side : float
var speed_multiplier : float = 2.0 
var time_to_max_speed : float
var vertical_forw_stability : float
var vertical_back_stability : float
var vertical_side_stability : float
var vertical_stability_spring : float
var vertical_stability_damp : float
var time_to_standup : float
var strenght : float
var throw_strenght : float
var reach : float
var reach_multiplier : float

var jump_strenght : float
var jump_multiplier : float
var time_to_max_jump : float

var vertical_turn_speed : float
var vertical_turn_spring : float
var vertical_turn_damp : float
var horizontal_turn_speed : float
var horizontal_turn_spring : float
var horizontal_turn_damp : float

var grip_strenght : float

#VISUAL
var fatness : float
var muscularity : float
var has_neck: bool = true

#PROPORTIONS
var height : float
var neck_to_head_proportion: float
var chest_to_low_spine_proportion : float
var legs_to_feet_proportion : float
var hips_width_proportion : float
var shoulder_width_proportion : float
var distance_from_ground_factor := 0.1  #tiene las piernas 10% flexionadas cuando esta en el piso

static func create(archetype: Archetype) -> EntityStats:
	if(archetype == Archetype.fat_man):
		return fat_man_arch()
	if(archetype == Archetype.tall_lanky):
		return tall_lanky_arch()
	if(archetype == Archetype.kid):
		return kid_arch()
	else:
		return giga_arch()

func as_alien(seed: float) -> EntityStats:
	return
func as_human(seed: float) -> EntityStats:
	return
func as_robot(seed: float) -> EntityStats:
	return

static func fat_man_arch() -> EntityStats:
	var arch = EntityStats.new()
	
	arch.weight = 120.0
	arch.speed_forw = 2.0
	arch.speed_back = 2.0
	arch.speed_side = 2.0
	arch.speed_multiplier = 2.0
	arch.time_to_max_speed = 4.0
	arch.vertical_forw_stability = 0.7
	arch.vertical_back_stability = 0.7
	arch.vertical_side_stability = 0.7
	arch.vertical_stability_spring = 0.7
	arch.vertical_stability_damp = 0.7
	arch.time_to_standup = 2.0
	arch.strenght = 1.0
	arch.throw_strenght = 0.7
	arch.reach = 0.5
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.3
	arch.jump_multiplier = 2.0
	arch.time_to_max_jump = 1.0

	arch.vertical_turn_speed = 0.8
	arch.vertical_turn_spring = 0.8
	arch.vertical_turn_damp = 0.8
	arch.horizontal_turn_speed = 0.8
	arch.horizontal_turn_spring = 0.8
	arch.horizontal_turn_damp = 0.8
	
	arch.fatness = 1.0
	arch.muscularity = 0.7
	
	arch.height = 1.7
	
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.35
	arch.legs_to_feet_proportion = 0.45
	arch.hips_width_proportion = 1.5
	arch.shoulder_width_proportion = 1.2
	
	arch.has_neck = true
	
	return arch
	
static func kid_arch() -> EntityStats:
	var arch = EntityStats.new()
	
	arch.weight = 30.0
	arch.speed_forw = 4.0
	arch.speed_back = 4.0
	arch.speed_side = 4.0
	arch.speed_multiplier = 2.0
	arch.time_to_max_speed = 1.5
	arch.vertical_forw_stability = 0.5
	arch.vertical_back_stability = 0.5
	arch.vertical_side_stability = 0.5
	arch.vertical_stability_spring = 0.7
	arch.vertical_stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.strenght = 0.3
	arch.throw_strenght = 0.2
	arch.reach = 0.2
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.jump_multiplier = 2.0
	arch.time_to_max_jump = 0.5

	arch.vertical_turn_speed = 0.8
	arch.vertical_turn_spring = 0.8
	arch.vertical_turn_damp = 0.8
	arch.horizontal_turn_speed = 0.8
	arch.horizontal_turn_spring = 0.8
	arch.horizontal_turn_damp = 0.8
	
	arch.fatness = 0.0
	arch.muscularity = 0.3
	
	arch.height = 1.2
	
	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.3
	arch.legs_to_feet_proportion = 0.5
	arch.hips_width_proportion = 1.5
	arch.shoulder_width_proportion = 1.2
	
	arch.has_neck = true
	
	return arch
	
static func tall_lanky_arch() -> EntityStats:
	var arch = EntityStats.new()
	
	arch.weight = 80.0
	arch.speed_forw = 3.0
	arch.speed_back = 3.0
	arch.speed_side = 3.0
	arch.speed_multiplier = 2.0
	arch.time_to_max_speed = 3.0
	arch.vertical_forw_stability = 0.5
	arch.vertical_back_stability = 0.5
	arch.vertical_side_stability = 0.5
	arch.vertical_stability_spring = 0.7
	arch.vertical_stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.strenght = 0.55
	arch.throw_strenght = 0.4
	arch.reach = 1.0
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.jump_multiplier = 2.0
	arch.time_to_max_jump = 0.5

	arch.vertical_turn_speed = 0.8
	arch.vertical_turn_spring = 0.8
	arch.vertical_turn_damp = 0.8
	arch.horizontal_turn_speed = 0.8
	arch.horizontal_turn_spring = 0.8
	arch.horizontal_turn_damp = 0.8
	
	arch.fatness = 0.0
	arch.muscularity = 0.5
	
	arch.height = 2.0

	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.hips_width_proportion = 1.5
	arch.shoulder_width_proportion = 1.2
	
	arch.has_neck = true
	
	return arch
	
static func giga_arch() -> EntityStats:
	var arch = EntityStats.new()
	
	arch.weight = 120.0
	arch.speed_forw = 2.0
	arch.speed_back = 2.0
	arch.speed_side = 2.0
	arch.speed_multiplier = 2.0
	arch.time_to_max_speed = 3.0
	arch.vertical_forw_stability = 0.5
	arch.vertical_back_stability = 0.5
	arch.vertical_side_stability = 0.5
	arch.vertical_stability_spring = 0.7
	arch.vertical_stability_damp = 0.7
	arch.time_to_standup = 1.0
	arch.strenght = 0.55
	arch.throw_strenght = 0.8
	arch.reach = 0.8
	arch.reach_multiplier = 1.0
	arch.jump_strenght = 0.6
	arch.jump_multiplier = 2.0
	arch.time_to_max_jump = 0.5

	arch.vertical_turn_speed = 0.8
	arch.vertical_turn_spring = 0.8
	arch.vertical_turn_damp = 0.8
	arch.horizontal_turn_speed = 0.8
	arch.horizontal_turn_spring = 0.8
	arch.horizontal_turn_damp = 0.8
	
	arch.fatness = 0.0
	arch.muscularity = 1.0
	
	arch.height = 1.8

	arch.neck_to_head_proportion = 0.2
	arch.chest_to_low_spine_proportion = 0.25
	arch.legs_to_feet_proportion = 0.55
	arch.hips_width_proportion = 1.5
	arch.shoulder_width_proportion = 1.2
	
	arch.has_neck = true
	
	return arch
	
	
