class_name EntityInstantiation

## Por ahora todas las personas que spawnean son humanas. Poner en false para volver a sortear la
## specie por seed (alien/robot siguen definidos en EntitySpecie y sus multiplicadores se aplican
## igual, solo que hoy son siempre los del humano = 1.0).
const FORCE_HUMAN_SPECIE := true

## Vista de la FASE 1 de la migración: todos los personajes usan el arquetipo `generic`, que tiene las
## tres cadenas de hueso en 0.5 y por lo tanto reproduce el modelo esculpido con DEFORMACIÓN CERO.
## Sirve para mirar la malla sin que la variación de arquetipos meta ruido: si algo se ve torcido con
## esto prendido, es un bug del espejo y no una proporción para tunear.
##
## En false (fase 2 en adelante) los arquetipos vuelven a variar, cada uno con su 0..1 por cadena
## dentro de los rangos del modelo. Ver technical/skinned-character-migration.md.
const FORCE_GENERIC_ARCHETYPE := true

var blend_range := 0.5

var master_seed: int
var archetype_type: EntityArchetype.Archetype
var secondary_archetype_type: EntityArchetype.Archetype
var archetype_blend: float
var specie_type: EntitySpecie.Specie

var arch_final: EntityArchetype
var spec: EntitySpecie

var age: int
var skin_color: Color

# Parámetros de animación resueltos: arquetipo (ya blendeado) × multiplicador de specie. No hay
# sorteo por seed acá — la variación entre personajes viene del arquetipo, del blend de dos
# arquetipos y de la specie. Ver technical/character-animation.md.
var shoulder_swing: float
var hip_swing: float
var root_bounciness: float
var step_height: float
var stride: float
var side_swing: float


static func create(seed: int) -> EntityInstantiation:
	var inst := EntityInstantiation.new()
	inst.master_seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	if FORCE_GENERIC_ARCHETYPE:
		inst.archetype_type = EntityArchetype.Archetype.generic
		inst.archetype_blend = 0.0
		inst.arch_final = EntityArchetype.create(EntityArchetype.Archetype.generic)
		inst.specie_type = _resolve_specie(rng, inst.arch_final)
		inst.spec = _make_specie(inst.specie_type)
		inst._resolve(rng)
		return inst

	if seed >= 0 and seed <= 4:
		var debug_archetypes: Array[EntityArchetype.Archetype] = [
			EntityArchetype.Archetype.fat_man,
			EntityArchetype.Archetype.kid,
			EntityArchetype.Archetype.tall_lanky,
			EntityArchetype.Archetype.giga,
			EntityArchetype.Archetype.old,
		]
		inst.archetype_type = debug_archetypes[seed]
		inst.archetype_blend = 0.0
		inst.arch_final = EntityArchetype.create(inst.archetype_type)
		inst.specie_type = _resolve_specie(rng, inst.arch_final)
		inst.spec = _make_specie(inst.specie_type)
		inst._resolve(rng)
		return inst

	inst.archetype_type = _pick_archetype(rng)
	var arch_a := EntityArchetype.create(inst.archetype_type)

	if rng.randf() < 0.5:
		inst.archetype_blend = 0.0
		inst.arch_final = arch_a
	else:
		var secondary := _pick_secondary_archetype(rng, inst.archetype_type, arch_a)
		if secondary != inst.archetype_type:
			inst.secondary_archetype_type = secondary
			inst.archetype_blend = 0.5
			var arch_b := EntityArchetype.create(secondary)
			inst.arch_final = arch_a.blend_with(arch_b, 0.5)
		else:
			inst.archetype_blend = 0.0
			inst.arch_final = arch_a

	inst.specie_type = _resolve_specie(rng, inst.arch_final)
	inst.spec = _make_specie(inst.specie_type)
	inst._resolve(rng)
	return inst


func _resolve(rng: RandomNumberGenerator) -> void:
	age             = roundi(rng.randf_range(arch_final.min_age, arch_final.max_age))
	shoulder_swing  = arch_final.shoulder_swing  * spec.shoulder_swing_multiplier
	hip_swing       = arch_final.hip_swing       * spec.hip_swing_multiplier
	side_swing      = arch_final.side_swing      * spec.side_swing_multiplier
	root_bounciness = arch_final.root_bounciness * spec.root_bounciness_multiplier
	step_height     = arch_final.step_height     * spec.step_height_multiplier
	stride          = clampf(arch_final.stride   * spec.stride_multiplier, 0.0, 1.0)
	skin_color      = spec.skin_colors[rng.randi() % spec.skin_colors.size()]


static func _pick_archetype(rng: RandomNumberGenerator) -> EntityArchetype.Archetype:
	var all: Array[EntityArchetype.Archetype] = [
		EntityArchetype.Archetype.fat_man,
		EntityArchetype.Archetype.kid,
		EntityArchetype.Archetype.tall_lanky,
		EntityArchetype.Archetype.giga,
		EntityArchetype.Archetype.old,
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
	return EntityArchetype.Archetype.fat_man


static func _pick_secondary_archetype(rng: RandomNumberGenerator, primary: EntityArchetype.Archetype, arch: EntityArchetype) -> EntityArchetype.Archetype:
	var all: Array[EntityArchetype.Archetype] = [
		EntityArchetype.Archetype.fat_man,
		EntityArchetype.Archetype.kid,
		EntityArchetype.Archetype.tall_lanky,
		EntityArchetype.Archetype.giga,
		EntityArchetype.Archetype.old,
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


## Punto único donde se decide la specie. Con FORCE_HUMAN_SPECIE no se consume el rng, así que el
## seed sigue determinando todo lo demás igual en todas las máquinas (que es lo que importa para el
## proxy remoto); lo que cambia es que el sorteo ponderado queda en pausa, no roto.
static func _resolve_specie(rng: RandomNumberGenerator, arch: EntityArchetype) -> EntitySpecie.Specie:
	if FORCE_HUMAN_SPECIE:
		return EntitySpecie.Specie.human
	return _pick_specie(rng, arch)


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
