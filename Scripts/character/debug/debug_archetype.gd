class_name DebugArchetype

## ARQUETIPO ELEGIDO A MANO PARA LOS SPAWNS DE DEBUG.
##
## Guarda SOLO la elección de la UI. Nunca decide cómo se resuelve un personaje: lo único que hace es
## fabricar la seed que después interpreta `EntityInstantiation.archetype_in_seed`. Por eso es estado
## estático sin ninguna consecuencia en red — lo que viaja es la seed, y la seed ya se explica sola.
##
## Es el mismo patrón que `CharacterDebugView`: el estado global vive acá y se consulta al spawnear,
## así lo que nazca DESPUÉS de elegir también lo hereda.
##
## Reemplaza al viejo `FORCE_GENERIC_ARCHETYPE`, que era un candado de compilación para todos los
## personajes a la vez. El candado global sigue existiendo (`EntityInstantiation.FORCE_ARCHETYPE`)
## para cuando querés que TODA la ciudad sea un arquetipo; esto es para elegir de a uno mientras jugás.

## Sin arquetipo elegido: manda el sorteo normal (o el candado global, si está puesto).
const NONE := -1

## Arquetipo con el que respawnea la P. Lo escribe el panel de debug.
static var selected: int = NONE


static func label() -> String:
	if selected == NONE:
		return "aleatorio"
	return str(EntityArchetype.Archetype.keys()[selected])


## Seed para un respawn: el arquetipo elegido con una variación distinta cada vez, o una seed normal
## si no hay ninguno elegido. La variación es lo que hace que apretar P dos veces no dé dos clones.
static func respawn_seed() -> int:
	if selected == NONE:
		return randi() % 100000
	return seed_for(selected)


## Seed para UN arquetipo puntual, sin tocar la selección. La usan los botones "Spawnear: X".
static func seed_for(archetype: int) -> int:
	return EntityInstantiation.debug_seed(archetype as EntityArchetype.Archetype, randi())
