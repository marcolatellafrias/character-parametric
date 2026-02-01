class_name ArchetypeDefinitions extends RefCounted

# Definiciones centralizadas de todos los arquetipos
static var DEFINITIONS: Dictionary = {
	"shanty_basic": {
		"neighborhoods": [NeighborhoodTypes.Type.SHANTY_TOWN],
		"has_chamfered_street_corners": false,
	},
	"shanty_makeshift": {
		"neighborhoods": [NeighborhoodTypes.Type.SHANTY_TOWN],
		"has_chamfered_street_corners": false,
	},
	"mansion_classic": {
		"neighborhoods": [NeighborhoodTypes.Type.RICH_RESIDENTIAL],
		"has_chamfered_street_corners": true,
	},
	"mansion_modern": {
		"neighborhoods": [NeighborhoodTypes.Type.RICH_RESIDENTIAL],
		"has_chamfered_street_corners": false,
	},
	"warehouse_basic": {
		"neighborhoods": [NeighborhoodTypes.Type.INDUSTRIAL],
		"has_chamfered_street_corners": false,
	},
	"factory_modern": {
		"neighborhoods": [NeighborhoodTypes.Type.INDUSTRIAL],
		"has_chamfered_street_corners": false,
	},
	"office_tower": {
		"neighborhoods": [NeighborhoodTypes.Type.DOWNTOWN],
		"has_chamfered_street_corners": true,
	},
	"mixed_use": {
		"neighborhoods": [
			NeighborhoodTypes.Type.DOWNTOWN,
			NeighborhoodTypes.Type.RICH_RESIDENTIAL
		],
		"has_chamfered_street_corners": true,
	},
}

# Factory method para crear un BuildingArchetype desde las definiciones
static func create_archetype(archetype_id: String) -> BuildingArchetype:
	if archetype_id not in DEFINITIONS:
		push_warning("[ArchetypeDefinitions] Arquetipo '%s' no encontrado, usando default" % archetype_id)
		return BuildingArchetype.new("default", false)
	
	var definition = DEFINITIONS[archetype_id]
	
	return BuildingArchetype.new(
		archetype_id,
		definition.get("has_chamfered_street_corners", false)
	)

# Filtra arquetipos por neighborhood type
static func get_archetype_ids_for_neighborhood(neighborhood_type: NeighborhoodTypes.Type) -> Array[String]:
	var result: Array[String] = []
	
	for archetype_id in DEFINITIONS:
		var definition = DEFINITIONS[archetype_id]
		var neighborhoods = definition.get("neighborhoods", [])
		
		if neighborhood_type in neighborhoods:
			result.append(archetype_id)
	
	return result

# Selecciona un arquetipo random para un cluster (antes en ArchetypeRegistry)
static func get_archetype_for_cluster(
	neighborhood_type: NeighborhoodTypes.Type,
	cluster_seed: int
) -> BuildingArchetype:
	
	var available_ids = get_archetype_ids_for_neighborhood(neighborhood_type)
	
	if available_ids.is_empty():
		push_warning("[ArchetypeDefinitions] No hay archetypes para tipo %d, usando default" % neighborhood_type)
		return create_archetype("default")
	
	var rng = RandomNumberGenerator.new()
	rng.seed = cluster_seed
	
	var selected_index = rng.randi_range(0, available_ids.size() - 1)
	var selected_id = available_ids[selected_index]
	
	return create_archetype(selected_id)
