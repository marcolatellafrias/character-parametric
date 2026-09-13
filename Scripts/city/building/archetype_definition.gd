class_name ArchetypeDefinitions extends RefCounted

# Registro distrito -> arquetipos. El estilo lo manda el DISTRITO, no la altura (ver NeighborhoodTypes):
# un mismo distrito se construye igual sea de 2 pisos o de 20.
#
# HOY HAY UN SOLO ARQUETIPO GENÉRICO POR DISTRITO, y el sorteo por seed queda de todas formas: cuando un
# distrito tenga varios (una fábrica y una iglesia en industrial, digamos), se agregan a su lista y nada
# más cambia. Antes había ocho arquetipos que solo se diferenciaban en el tono del color de debug, que es
# una diferencia que no existe para el jugador.
static var NEIGHBORHOOD_ARCHETYPES = {
	NeighborhoodTypes.District.POOR: [
		BuildingArchetype.GenericPoor,
	],
	NeighborhoodTypes.District.RICH: [
		BuildingArchetype.GenericRich,
	],
	NeighborhoodTypes.District.INDUSTRIAL: [
		BuildingArchetype.GenericIndustrial,
	],
}

# Selecciona (seed-based) uno de los archetypes del distrito y lo instancia.
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
