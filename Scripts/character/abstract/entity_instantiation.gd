class_name EntityInstantiation

var master_seed: int
var archetype_type: EntityArchetype.Archetype
var specie_type: EntitySpecie.Specie

# BASE STATS
var strength: float
var weight: float
var speed_forw: float
var speed_back: float
var speed_side: float
var sprint_multiplier: float
var acceleration: float
var forward_stability: float
var backwards_stability: float
var sideways_stability: float
var stability_spring: float
var stability_damp: float
var time_to_standup: float

# REACH/ARMS
var throw_strength: float
var reach: float
var reach_multiplier: float

# JUMP
var jump_strength: float
var time_to_max_jump: float

# AGE
var age: int

# ANIMATIONS
var shoulder_swing: float
var hip_swing: float
var root_bounciness: float
var step_height: float
var step_radius: float
var leg_cripple_chance: float

# POSTURE
var slouch: float
var shoulders_height: float
var shoulders_back: float
var arms_openness: float

# VISUAL
var fatness: float
var muscularity: float
var has_neck: bool
var skin_color: Color

# PROPORTIONS
var height: float
var neck_to_head_proportion: float
var chest_to_low_spine_proportion: float
var legs_to_feet_proportion: float
var hips_width_proportion: float
var shoulder_width_proportion: float
var distance_from_ground_factor: float


static func create(seed: int) -> EntityInstantiation:
	var inst := EntityInstantiation.new()
	inst.master_seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	inst.archetype_type = _pick_archetype(rng)
	var arch := EntityArchetype.create(inst.archetype_type)

	inst.specie_type = _pick_specie(rng, arch)
	var spec := _make_specie(inst.specie_type)

	inst._resolve(rng, arch, spec)
	return inst


static func _pick_archetype(rng: RandomNumberGenerator) -> EntityArchetype.Archetype:
	var all: Array[EntityArchetype.Archetype] = [
		EntityArchetype.Archetype.fat_man,
		EntityArchetype.Archetype.kid,
		EntityArchetype.Archetype.tall_lanky,
		EntityArchetype.Archetype.giga,
		EntityArchetype.Archetype.old,
		EntityArchetype.Archetype.normal,
	]
	var freqs: Array[float] = []
	var total := 0.0
	for a in all:
		var f := EntityArchetype.create(a).archetype_frequency
		freqs.append(f)
		total += f
	var roll := rng.randf() * total
	var acc := 0.0
	for i in all.size():
		acc += freqs[i]
		if roll <= acc:
			return all[i]
	return EntityArchetype.Archetype.normal


static func _pick_specie(rng: RandomNumberGenerator, arch: EntityArchetype) -> EntitySpecie.Specie:
	var species: Array[EntitySpecie.Specie] = [
		EntitySpecie.Specie.human,
		EntitySpecie.Specie.alien,
		EntitySpecie.Specie.robot,
	]
	var weights := [arch.human_chance, arch.alien_chance, arch.robot_chance]
	var total := arch.human_chance + arch.alien_chance + arch.robot_chance
	var roll := rng.randf() * total
	var acc := 0.0
	for i in species.size():
		acc += weights[i]
		if roll <= acc:
			return species[i]
	return EntitySpecie.Specie.human


static func _make_specie(specie: EntitySpecie.Specie) -> EntitySpecie:
	match specie:
		EntitySpecie.Specie.human: return EntitySpecie.human_specie()
		EntitySpecie.Specie.alien: return EntitySpecie.alien_specie()
		EntitySpecie.Specie.robot: return EntitySpecie.robot_specie()
	return EntitySpecie.human_specie()


func _resolve(rng: RandomNumberGenerator, arch: EntityArchetype, spec: EntitySpecie) -> void:
	strength            = arch.strenght * spec.strenght_multiplier
	weight              = arch.weight
	speed_forw          = arch.speed_forw * spec.speed_forw_multiplier
	speed_back          = arch.speed_back * spec.speed_back_multiplier
	speed_side          = arch.speed_side * spec.speed_side_multiplier
	sprint_multiplier   = arch.sprint_multiplier
	acceleration        = arch.acceleration * spec.acceleration_multiplier
	forward_stability   = arch.foward_stability * spec.forward_stability_multiplier
	backwards_stability = arch.backwards_stability * spec.backwards_stability_multiplier
	sideways_stability  = arch.sideways_stability * spec.sideways_stability_multiplier
	stability_spring    = arch.stability_spring * spec.stability_spring_multiplier
	stability_damp      = arch.stability_damp * spec.stability_damp_multiplier
	time_to_standup     = arch.time_to_standup
	throw_strength      = arch.throw_strenght * spec.throw_strenght_multiplier
	reach               = arch.reach * spec.reach_multiplier
	reach_multiplier    = arch.reach_multiplier
	jump_strength       = arch.jump_strenght * spec.jump_strenght_multiplier
	time_to_max_jump    = arch.time_to_max_jump
	age                 = roundi(rng.randf_range(arch.min_age, arch.max_age))
	shoulder_swing      = rng.randf_range(arch.shoulder_swing_min, arch.shoulder_swing_max) * spec.shoulder_swing_multiplier
	hip_swing           = rng.randf_range(arch.hip_swing_min, arch.hip_swing_max) * spec.hip_swing_multiplier
	root_bounciness     = rng.randf_range(arch.root_bounciness_min, arch.root_bounciness_max) * spec.root_bounciness_multiplier
	step_height         = rng.randf_range(arch.step_height_min, arch.step_height_max) * spec.step_height_multiplier
	step_radius         = rng.randf_range(arch.step_radius_min, arch.step_radius_max) * spec.step_radius_multiplier
	leg_cripple_chance  = arch.leg_cripple_chance * spec.leg_cripple_chance_multiplier
	slouch              = arch.slouch
	shoulders_height    = arch.shoulders_height
	shoulders_back      = arch.shoulders_back
	arms_openness       = arch.arms_openness
	fatness             = arch.fatness
	muscularity         = arch.muscularity
	has_neck            = arch.has_neck
	skin_color          = spec.skin_colors[rng.randi() % spec.skin_colors.size()]
	height                       = arch.height
	neck_to_head_proportion      = arch.neck_to_head_proportion
	chest_to_low_spine_proportion = arch.chest_to_low_spine_proportion
	legs_to_feet_proportion      = arch.legs_to_feet_proportion
	hips_width_proportion        = arch.hips_width_proportion
	shoulder_width_proportion    = arch.shoulder_width_proportion
	distance_from_ground_factor  = arch.distance_from_ground_factor
	
	
	
	
