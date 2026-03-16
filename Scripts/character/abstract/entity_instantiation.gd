class_name EntityInstantiation

var blend_chance := 0.30

var master_seed: int
var archetype_type: EntityArchetype.Archetype
var secondary_archetype_type: EntityArchetype.Archetype
var archetype_blend: float
var specie_type: EntitySpecie.Specie

var arch_final: EntityArchetype
var spec: EntitySpecie

# únicos valores que necesitan colapso aleatorio
var age: int
var shoulder_swing: float
var hip_swing: float
var root_bounciness: float
var step_height: float
var step_radius: float
var skin_color: Color


static func create(seed: int) -> EntityInstantiation:
	var inst := EntityInstantiation.new()
	inst.master_seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	inst.archetype_type = _pick_archetype(rng)
	var arch_a := EntityArchetype.create(inst.archetype_type)

	if rng.randf() < inst.blend_chance:
		var secondary := _pick_secondary_archetype(rng, inst.archetype_type, arch_a)
		if secondary != inst.archetype_type:
			inst.secondary_archetype_type = secondary
			inst.archetype_blend = rng.randf_range(0.0, 0.3)
			var arch_b := EntityArchetype.create(secondary)
			inst.arch_final = arch_a.blend_with(arch_b, inst.archetype_blend)
		else:
			inst.archetype_blend = 0.0
			inst.arch_final = arch_a
	else:
		inst.archetype_blend = 0.0
		inst.arch_final = arch_a

	inst.specie_type = _pick_specie(rng, inst.arch_final)
	inst.spec = _make_specie(inst.specie_type)
	inst._resolve(rng)
	return inst


func _resolve(rng: RandomNumberGenerator) -> void:
	age             = roundi(rng.randf_range(arch_final.min_age, arch_final.max_age))
	shoulder_swing  = rng.randf_range(arch_final.shoulder_swing_min, arch_final.shoulder_swing_max) * spec.shoulder_swing_multiplier
	hip_swing       = rng.randf_range(arch_final.hip_swing_min, arch_final.hip_swing_max) * spec.hip_swing_multiplier
	root_bounciness = rng.randf_range(arch_final.root_bounciness_min, arch_final.root_bounciness_max) * spec.root_bounciness_multiplier
	step_height     = rng.randf_range(arch_final.step_height_min, arch_final.step_height_max) * spec.step_height_multiplier
	step_radius     = rng.randf_range(arch_final.step_radius_min, arch_final.step_radius_max) * spec.step_radius_multiplier
	skin_color      = spec.skin_colors[rng.randi() % spec.skin_colors.size()]


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


static func _pick_secondary_archetype(rng: RandomNumberGenerator, primary: EntityArchetype.Archetype, arch: EntityArchetype) -> EntityArchetype.Archetype:
	var all: Array[EntityArchetype.Archetype] = [
		EntityArchetype.Archetype.fat_man,
		EntityArchetype.Archetype.kid,
		EntityArchetype.Archetype.tall_lanky,
		EntityArchetype.Archetype.giga,
		EntityArchetype.Archetype.old,
		EntityArchetype.Archetype.normal,
	]
	var candidates: Array[EntityArchetype.Archetype] = []
	var freqs: Array[float] = []
	var total := 0.0
	for a in all:
		if a == primary or arch.uncompatible_archetypes.has(a):
			continue
		var other := EntityArchetype.create(a)
		if other.uncompatible_archetypes.has(primary):
			continue
		candidates.append(a)
		freqs.append(other.archetype_frequency)
		total += other.archetype_frequency
	if candidates.is_empty():
		return primary
	var roll := rng.randf() * total
	var acc := 0.0
	for i in candidates.size():
		acc += freqs[i]
		if roll <= acc:
			return candidates[i]
	return candidates[-1]


static func _pick_specie(rng: RandomNumberGenerator, arch: EntityArchetype) -> EntitySpecie.Specie:
	var species: Array[EntitySpecie.Specie] = [EntitySpecie.Specie.human, EntitySpecie.Specie.alien, EntitySpecie.Specie.robot]
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
