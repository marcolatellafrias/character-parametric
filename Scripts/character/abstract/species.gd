class_name EntitySpecie

enum Specie {human, alien, robot}

# BASE STATS
var strenght_multiplier : float = 1.0
var speed_forw_multiplier : float = 1.0
var speed_back_multiplier : float = 1.0
var speed_side_multiplier : float = 1.0
var acceleration_multiplier : float = 1.0
var forward_stability_multiplier : float = 1.0
var backwards_stability_multiplier : float = 1.0
var sideways_stability_multiplier : float = 1.0
var stability_spring_multiplier : float = 1.0
var stability_damp_multiplier : float = 1.0

# REACH/ARMS
var throw_strenght_multiplier : float = 1.0
var reach_multiplier : float = 1.0

# JUMP
var jump_strenght_multiplier : float

# ANIMATIONS
var shoulder_swing_multiplier : float = 1.0
var hip_swing_multiplier : float = 1.0
var root_bounciness_multiplier  : float = 1.0
var step_height_multiplier : float = 1.0
var step_radius_multiplier : float = 1.0
var leg_cripple_chance_multiplier : float = 1.0

var skin_colors : Array # array of possible skin colors


static func human_specie() -> EntitySpecie:
	var specie = EntitySpecie.new()
	specie.strenght_multiplier = 1.0
	specie.speed_forw_multiplier = 1.0
	specie.speed_back_multiplier = 1.0
	specie.speed_side_multiplier = 1.0
	specie.acceleration_multiplier = 1.0
	specie.forward_stability_multiplier = 1.0
	specie.backwards_stability_multiplier = 1.0
	specie.sideways_stability_multiplier = 1.0
	specie.stability_spring_multiplier = 1.0
	specie.stability_damp_multiplier = 1.0
	specie.throw_strenght_multiplier = 1.0
	specie.reach_multiplier = 1.0
	specie.jump_strenght_multiplier = 1.2
	specie.shoulder_swing_multiplier = 1.0
	specie.hip_swing_multiplier = 1.0
	specie.root_bounciness_multiplier = 1.0
	specie.step_height_multiplier = 1.0
	specie.step_radius_multiplier = 1.0
	specie.leg_cripple_chance_multiplier = 1.0
	specie.skin_colors = [
		Color(1.0, 0.85, 0.7),
		Color(0.9, 0.7, 0.5),
		Color(0.75, 0.55, 0.35),
		Color(0.5, 0.35, 0.2),
		Color(0.3, 0.2, 0.12),
	]
	return specie

static func alien_specie() -> EntitySpecie:
	var specie = EntitySpecie.new()
	specie.strenght_multiplier = 0.7
	specie.speed_forw_multiplier = 1.0
	specie.speed_back_multiplier = 1.0
	specie.speed_side_multiplier = 1.0
	specie.acceleration_multiplier = 1.0
	specie.forward_stability_multiplier = 1.0
	specie.backwards_stability_multiplier = 1.0
	specie.sideways_stability_multiplier = 1.0
	specie.stability_spring_multiplier = 1.0
	specie.stability_damp_multiplier = 1.0
	specie.throw_strenght_multiplier = 1.0
	specie.reach_multiplier = 1.5
	specie.jump_strenght_multiplier = 1.0
	specie.shoulder_swing_multiplier = 1.0
	specie.hip_swing_multiplier = 1.0
	specie.root_bounciness_multiplier = 1.0
	specie.step_height_multiplier = 1.0
	specie.step_radius_multiplier = 1.0
	specie.leg_cripple_chance_multiplier = 0.0
	specie.skin_colors = [
		Color(0.3, 0.8, 0.4),
		Color(0.4, 0.6, 0.9),
		Color(0.7, 0.3, 0.8),
		Color(0.2, 0.7, 0.7),
	]
	return specie

static func robot_specie() -> EntitySpecie:
	var specie = EntitySpecie.new()
	specie.strenght_multiplier = 1.5
	specie.speed_forw_multiplier = 0.7
	specie.speed_back_multiplier = 0.4
	specie.speed_side_multiplier = 0.5
	specie.acceleration_multiplier = 0.7
	specie.forward_stability_multiplier = 0.9
	specie.backwards_stability_multiplier = 0.6
	specie.sideways_stability_multiplier = 0.3
	specie.stability_spring_multiplier = 1.0
	specie.stability_damp_multiplier = 1.0
	specie.throw_strenght_multiplier = 1.0
	specie.reach_multiplier = 1.0
	specie.jump_strenght_multiplier = 1.0
	specie.shoulder_swing_multiplier = 1.0
	specie.hip_swing_multiplier = 1.0
	specie.root_bounciness_multiplier = 1.0
	specie.step_height_multiplier = 0.5
	specie.step_radius_multiplier = 0.6
	specie.leg_cripple_chance_multiplier = 0.0
	specie.skin_colors = [
		Color(0.75, 0.75, 0.75),
		Color(0.4, 0.4, 0.4),
		Color(0.8, 0.6, 0.2),
		Color(0.3, 0.5, 0.7),
	]
	return specie
