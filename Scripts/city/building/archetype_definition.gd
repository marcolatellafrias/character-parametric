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

## EL ARQUETIPO FORZADO: mientras no es null, todo cluster nuevo sale de esta clase sin sortear. Lo usa el
## design sandbox para que la manzana de muestra de un arquetipo lleve ese arquetipo (ver
## City.generate_block_sample), que con varios por distrito el sorteo no garantiza. Se pone y se saca
## alrededor de una sola generación.
static var forced_archetype: GDScript = null


## Todos los arquetipos, uno por clase y con su distrito puesto: las parcelas del design sandbox.
static func all() -> Array[BuildingArchetype]:
	var out: Array[BuildingArchetype] = []
	for district: NeighborhoodTypes.District in NEIGHBORHOOD_ARCHETYPES:
		for archetype_class: GDScript in NEIGHBORHOOD_ARCHETYPES[district]:
			var instance: BuildingArchetype = archetype_class.new()
			instance.district = district
			out.append(instance)
	return out


# Selecciona (seed-based) uno de los archetypes del distrito y lo instancia.
static func get_archetype_for_cluster(
	neighborhood_type: NeighborhoodTypes.District,
	cluster_seed: int
) -> BuildingArchetype:
	if forced_archetype != null:
		var forced: BuildingArchetype = forced_archetype.new()
		forced.district = neighborhood_type
		return forced

	var classes = NEIGHBORHOOD_ARCHETYPES.get(neighborhood_type, [])

	if classes.is_empty():
		push_warning("[ArchetypeDefinitions] No hay archetypes para el distrito %d, usando default" % neighborhood_type)
		return BuildingArchetype.new()

	var rng = RandomNumberGenerator.new()
	rng.seed = cluster_seed

	var selected_index = rng.randi_range(0, classes.size() - 1)
	var instance: BuildingArchetype = classes[selected_index].new()
	instance.district = neighborhood_type
	return instance
