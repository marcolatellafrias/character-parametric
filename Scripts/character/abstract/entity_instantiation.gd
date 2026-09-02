class_name EntityInstantiation

## Por ahora todas las personas que spawnean son humanas. Poner en false para volver a sortear la
## specie por seed (alien/robot siguen definidos en EntitySpecie y sus multiplicadores se aplican
## igual, solo que hoy son siempre los del humano = 1.0).
const FORCE_HUMAN_SPECIE := true

## ── CANDADO GLOBAL DE ARQUETIPO ───────────────────────────────────────────────────────────────────
## Todos los personajes usan este arquetipo y se saltea el sorteo. `-1` = sorteo normal, que es lo que
## hace el juego de verdad.
##
## Es CONST y no una variable, a propósito: al valer lo mismo en todas las máquinas no rompe la
## determinación por seed. Estado mutable acá haría que el proxy resuelva otro personaje con la misma
## seed y se viera distinto en cada pantalla.
##
## Hoy apunta a `generic`, que es la vista de la fase 1 de la migración: sirve para mirar la malla sin
## que la variación de arquetipos meta ruido, así que si algo se ve torcido con esto puesto es un bug
## del espejo y no una proporción para tunear. Poniendo `-1` la ciudad vuelve a variar.
##
## Para mirar UN arquetipo sin tocar código está el panel de debug — ver DEBUG_SEED_BASE.
## Ver technical/skinned-character-migration.md.
const FORCE_ARCHETYPE: int = EntityArchetype.Archetype.generic

## ── SEEDS DE DEBUG: EL ARQUETIPO VA CODIFICADO EN LA SEED ─────────────────────────────────────────
## Una seed en esta banda fuerza un arquetipo y GANA sobre el candado global. La variación que va
## adentro sigue alimentando el rng, así que color, edad y specie varían igual: se pueden spawnear
## diez `giga` distintos y no diez clones.
##
## VA EN LA SEED, y esa es la decisión que importa: la seed es lo ÚNICO que viaja a las otras máquinas
## (`CharacterNetSync.broadcast_seed`). Un forzado guardado en una variable estática haría que el
## proxy resuelva otro arquetipo con la misma seed. Codificado acá, todas las máquinas llegan al mismo
## personaje sin mandar un byte de más y sin tocar el protocolo.
##
## La banda arranca en 900000 y las seeds normales salen de `randi() % 100000`, así que no se pisan.
## Antes esto eran las seeds 0..4, que sí podían salir sorteadas y no alcanzaban para todos los
## arquetipos. La elección de la UI vive en DebugArchetype.
const DEBUG_SEED_BASE := 900000
const DEBUG_SEED_SPAN := 1000

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
var cloth_color: Color
var hair_color: Color
var leather_color: Color

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

	# El arquetipo puede venir forzado por dos vías, y LA SEED GANA: es una elección explícita hecha
	# desde el panel, mientras que el candado global es apenas el default de la sesión.
	# Tres casos, no dos: la seed nombra un arquetipo, la seed pide sorteo libre, o la seed no dice
	# nada y recién ahí manda el candado global.
	var forced := archetype_in_seed(seed)
	if forced == SEED_FREE_DRAW:
		forced = -1
	elif forced < 0:
		forced = FORCE_ARCHETYPE
	if forced >= 0:
		inst.archetype_type = forced as EntityArchetype.Archetype
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


## Lo que devuelve `archetype_in_seed` cuando la seed pide SORTEO LIBRE: el arquetipo se rifa como en
## la ciudad —mezclas incluidas— **ignorando `FORCE_ARCHETYPE`**.
##
## Hace falta un valor propio y no alcanza con −1 porque −1 significa "esta seed no dice nada", y ahí
## es justamente donde entra el candado global. Sin distinguir los dos casos, con el candado puesto el
## botón "aleatorio" devolvía siempre el mismo arquetipo — que es lo que pasaba hasta ahora.
const SEED_FREE_DRAW := -2

## Seed que reproduce `archetype` con una variación propia. La usa el panel de debug.
static func debug_seed(archetype: EntityArchetype.Archetype, variation: int) -> int:
	return DEBUG_SEED_BASE + int(archetype) * DEBUG_SEED_SPAN + posmod(variation, DEBUG_SEED_SPAN)


## Seed de sorteo libre. Vive en la banda inmediatamente posterior a la del último arquetipo, así que
## no hay tabla que mantener: agregar un arquetipo la corre sola.
static func free_draw_seed(variation: int) -> int:
	return DEBUG_SEED_BASE + EntityArchetype.Archetype.size() * DEBUG_SEED_SPAN 		+ posmod(variation, DEBUG_SEED_SPAN)


## El arquetipo codificado en una seed, `SEED_FREE_DRAW` si pide sorteo libre, o −1 si es normal.
static func archetype_in_seed(seed: int) -> int:
	if seed < DEBUG_SEED_BASE:
		return -1
	@warning_ignore("integer_division")
	var idx: int = (seed - DEBUG_SEED_BASE) / DEBUG_SEED_SPAN
	if idx < EntityArchetype.Archetype.size():
		return idx
	return SEED_FREE_DRAW if idx == EntityArchetype.Archetype.size() else -1


func _resolve(rng: RandomNumberGenerator) -> void:
	age             = roundi(rng.randf_range(arch_final.min_age, arch_final.max_age))
	shoulder_swing  = arch_final.shoulder_swing  * spec.shoulder_swing_multiplier
	hip_swing       = arch_final.hip_swing       * spec.hip_swing_multiplier
	side_swing      = arch_final.side_swing      * spec.side_swing_multiplier
	root_bounciness = arch_final.root_bounciness * spec.root_bounciness_multiplier
	step_height     = arch_final.step_height     * spec.step_height_multiplier
	stride          = clampf(arch_final.stride   * spec.stride_multiplier, 0.0, 1.0)
	skin_color      = _pick(rng, spec.skin_colors,    Color(0.9, 0.7, 0.5))
	cloth_color     = _pick(rng, spec.cloth_colors,   Color(0.35, 0.35, 0.42))
	hair_color      = _pick(rng, spec.hair_colors,    Color(0.15, 0.11, 0.09))
	leather_color   = _pick(rng, spec.leather_colors, Color(0.25, 0.18, 0.14))
	# Va AL FINAL: el rng ya se consumió, así que sacar el candado devuelve el comportamiento de antes
	# sin desplazar ninguna otra tirada. Ver AppearancePreset.
	AppearancePreset.apply(self)


## Un color de la paleta, o el fallback si la specie todavía no tiene esa paleta cargada. El fallback
## existe para que agregar un rol nuevo no rompa las species viejas — se ven grises, no crashean.
static func _pick(rng: RandomNumberGenerator, palette: Array, fallback: Color) -> Color:
	if palette == null or palette.is_empty():
		return fallback
	return palette[rng.randi() % palette.size()]


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
