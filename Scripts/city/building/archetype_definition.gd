class_name ArchetypeDefinitions extends RefCounted

# Registro neighborhood -> arquetipos. Exactamente 2 arquetipos distintos por
# neighborhood: la garantía es estructural (no se deriva de escanear una lista).
# Cada entrada es la clase concreta (inner class de BuildingArchetype); se
# instancia con `.new()`.
static var NEIGHBORHOOD_ARCHETYPES = {
	NeighborhoodTypes.Type.SHANTY_TOWN: [
		BuildingArchetype.ShantyBasic,
		BuildingArchetype.ShantyMakeshift,
	],
	NeighborhoodTypes.Type.RICH_RESIDENTIAL: [
		BuildingArchetype.MansionClassic,
		BuildingArchetype.MansionModern,
	],
	NeighborhoodTypes.Type.INDUSTRIAL: [
		BuildingArchetype.WarehouseBasic,
		BuildingArchetype.FactoryModern,
	],
	NeighborhoodTypes.Type.DOWNTOWN: [
		BuildingArchetype.OfficeTower,
		BuildingArchetype.MixedUse,
	],
}

# Selecciona (seed-based) uno de los 2 arquetipos del neighborhood y lo instancia.
static func get_archetype_for_cluster(
	neighborhood_type: NeighborhoodTypes.Type,
	cluster_seed: int
) -> BuildingArchetype:

	var classes = NEIGHBORHOOD_ARCHETYPES.get(neighborhood_type, [])

	if classes.is_empty():
		push_warning("[ArchetypeDefinitions] No hay archetypes para tipo %d, usando default" % neighborhood_type)
		return BuildingArchetype.new()

	var rng = RandomNumberGenerator.new()
	rng.seed = cluster_seed

	var selected_index = rng.randi_range(0, classes.size() - 1)
	return classes[selected_index].new()
