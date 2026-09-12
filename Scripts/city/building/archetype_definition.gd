class_name ArchetypeDefinitions extends RefCounted

# Registro distrito -> arquetipos. El estilo lo manda el DISTRITO, no la altura (ver NeighborhoodTypes):
# un mismo distrito se construye igual sea de 2 pisos o de 20. Los dos arquetipos que antes eran de
# "Downtown" pasaron a ser la cara densa de pobre (MixedUse, el conventillo con local abajo) y de rico
# (OfficeTower); Downtown dejó de existir como distrito porque era una densidad, no una cultura.
static var NEIGHBORHOOD_ARCHETYPES = {
	NeighborhoodTypes.District.POOR: [
		BuildingArchetype.ShantyBasic,
		BuildingArchetype.ShantyMakeshift,
		BuildingArchetype.MixedUse,
	],
	NeighborhoodTypes.District.RICH: [
		BuildingArchetype.MansionClassic,
		BuildingArchetype.MansionModern,
		BuildingArchetype.OfficeTower,
	],
	NeighborhoodTypes.District.INDUSTRIAL: [
		BuildingArchetype.WarehouseBasic,
		BuildingArchetype.FactoryModern,
	],
}

# Selecciona (seed-based) uno de los arquetipos del distrito y lo instancia.
static func get_archetype_for_cluster(
	neighborhood_type: NeighborhoodTypes.District,
	cluster_seed: int
) -> BuildingArchetype:

	var classes = NEIGHBORHOOD_ARCHETYPES.get(neighborhood_type, [])

	if classes.is_empty():
		push_warning("[ArchetypeDefinitions] No hay archetypes para el distrito %d, usando default" % neighborhood_type)
		return BuildingArchetype.new()

	var rng = RandomNumberGenerator.new()
	rng.seed = cluster_seed

	var selected_index = rng.randi_range(0, classes.size() - 1)
	return classes[selected_index].new()
