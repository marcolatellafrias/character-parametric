extends Object
class_name CarArchetypes

static var speed_debug_factor: float = 0.8
static var size_debug_factor: float = 10.0

enum Type {
	VENDING_TRUCK,
	RICH_CAR,
	POOR_CAR,
	MOTORCYCLE,
	UTILITY_TRUCK,
	ADVERTISEMENT_TRUCK,
	GARBAGE_TRUCK,
	POLICE_CAR,
	TAXI
}

# Tabla de afinidad: qué tan probable es que un tipo de auto elija un tipo de barrio
const NEIGHBORHOOD_AFFINITY = {
	Type.RICH_CAR: {
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 1.0,
		NeighborhoodTypes.Type.DOWNTOWN: 0.7,
		NeighborhoodTypes.Type.INDUSTRIAL: 0.2,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.1
	},
	Type.POOR_CAR: {
		NeighborhoodTypes.Type.SHANTY_TOWN: 1.0,
		NeighborhoodTypes.Type.INDUSTRIAL: 0.6,
		NeighborhoodTypes.Type.DOWNTOWN: 0.4,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.2
	},
	Type.TAXI: {
		NeighborhoodTypes.Type.DOWNTOWN: 1.0,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.8,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.6,
		NeighborhoodTypes.Type.INDUSTRIAL: 0.5
	},
	Type.UTILITY_TRUCK: {
		NeighborhoodTypes.Type.INDUSTRIAL: 1.0,
		NeighborhoodTypes.Type.DOWNTOWN: 0.5,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.4,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.3
	},
	Type.MOTORCYCLE: {
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.8,
		NeighborhoodTypes.Type.DOWNTOWN: 0.7,
		NeighborhoodTypes.Type.INDUSTRIAL: 0.6,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.5
	},
	Type.GARBAGE_TRUCK: {
		NeighborhoodTypes.Type.INDUSTRIAL: 0.9,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.7,
		NeighborhoodTypes.Type.DOWNTOWN: 0.5,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.4
	},
	Type.VENDING_TRUCK: {
		NeighborhoodTypes.Type.INDUSTRIAL: 0.8,
		NeighborhoodTypes.Type.DOWNTOWN: 0.7,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.6,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.5
	},
	Type.ADVERTISEMENT_TRUCK: {
		NeighborhoodTypes.Type.DOWNTOWN: 1.0,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.7,
		NeighborhoodTypes.Type.INDUSTRIAL: 0.6,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.3
	},
	Type.POLICE_CAR: {
		NeighborhoodTypes.Type.DOWNTOWN: 0.9,
		NeighborhoodTypes.Type.RICH_RESIDENTIAL: 0.8,
		NeighborhoodTypes.Type.SHANTY_TOWN: 0.7,
		NeighborhoodTypes.Type.INDUSTRIAL: 0.6
	}
}

class Archetype:
	var name: String
	var width: float
	var height: float
	var depth: float
	var min_speed: float
	var max_speed: float
	var color: Color
	var weight: float
	var max_per_volume: int
	var max_global: int
	var min_spawn_v: float

	func _init(
		p_name: String,
		p_width: float,
		p_height: float,
		p_depth: float,
		p_min_speed: float,
		p_max_speed: float,
		p_color: Color,
		p_weight: float = 1.0,
		p_max_per_volume: int = -1,
		p_max_global: int = -1,
		p_min_spawn_v: float = 0.0
	):
		name = p_name
		width = p_width
		height = p_height
		depth = p_depth
		min_speed = p_min_speed
		max_speed = p_max_speed
		color = p_color
		weight = p_weight
		max_per_volume = p_max_per_volume
		max_global = p_max_global
		min_spawn_v = p_min_spawn_v
	
	func get_random_dimensions() -> Dictionary:
		return {
			"width": width,
			"height": height,
			"depth": depth,
			"speed": randf_range(min_speed, max_speed)
		}
	
	func get_random_color() -> Color:
		return color

static var archetypes: Dictionary = {}

static func _static_init() -> void:
	archetypes[Type.VENDING_TRUCK] = Archetype.new(
		"Vending Truck",
		0.35 * size_debug_factor,
		0.4 * size_debug_factor,
		1.0 * size_debug_factor,
		4.0 * speed_debug_factor,
		6.0 * speed_debug_factor,
		Color(0.9, 0.5, 0.1),
		0.05,
		1,
		1,
		0.15
	)
	
	archetypes[Type.RICH_CAR] = Archetype.new(
		"Rich Car",
		0.18 * size_debug_factor,
		0.09 * size_debug_factor,
		0.42 * size_debug_factor,
		18.0 * speed_debug_factor,
		50.0 * speed_debug_factor,
		Color(0.1, 0.1, 0.1),
		0.15,
		30,
		100
	)
	
	archetypes[Type.POOR_CAR] = Archetype.new(
		"Poor Car",
		0.16 * size_debug_factor,
		0.1 * size_debug_factor,
		0.35 * size_debug_factor,
		14.0 * speed_debug_factor,
		18.0 * speed_debug_factor,
		Color(0.6, 0.5, 0.4),
		0.3,
		30,
		150
	)
	
	archetypes[Type.MOTORCYCLE] = Archetype.new(
		"Motorcycle",
		0.05 * size_debug_factor,
		0.035 * size_debug_factor,
		0.2 * size_debug_factor,
		22.0 * speed_debug_factor,
		40.0 * speed_debug_factor,
		Color(0.9, 0.1, 0.1),
		0.2,
		10,
		30
	)
	
	archetypes[Type.UTILITY_TRUCK] = Archetype.new(
		"Utility Truck",
		0.15 * size_debug_factor,
		0.2 * size_debug_factor,
		0.6 * size_debug_factor,
		5.0 * speed_debug_factor,
		7.0 * speed_debug_factor,
		Color(0.9, 0.8, 0.1),
		0.08,
		1,
		1,
		0.1
	)
	
	archetypes[Type.ADVERTISEMENT_TRUCK] = Archetype.new(
		"Advertisement Truck",
		0.35 * size_debug_factor,
		0.6 * size_debug_factor,
		1.5 * size_debug_factor,
		3.5 * speed_debug_factor,
		5.0 * speed_debug_factor,
		Color(0.9, 0.1, 0.9),
		0.03,
		1,
		1,
		0.2
	)
	
	archetypes[Type.GARBAGE_TRUCK] = Archetype.new(
		"Garbage Truck",
		0.35 * size_debug_factor,
		0.45 * size_debug_factor,
		1.3 * size_debug_factor,
		4.0 * speed_debug_factor,
		6.0 * speed_debug_factor,
		Color(0.2, 0.6, 0.2),
		0.04,
		1,
		1,
		0.15
	)
	
	archetypes[Type.POLICE_CAR] = Archetype.new(
		"Police Car",
		0.18 * size_debug_factor,
		0.1 * size_debug_factor,
		0.4 * size_debug_factor,
		16.0 * speed_debug_factor,
		24.0 * speed_debug_factor,
		Color(0.1, 0.3, 0.9),
		0.1,
		10,
		15
	)
	
	archetypes[Type.TAXI] = Archetype.new(
		"Taxi",
		0.17 * size_debug_factor,
		0.1 * size_debug_factor,
		0.38 * size_debug_factor,
		15.0 * speed_debug_factor,
		20.0 * speed_debug_factor,
		Color(0.95, 0.9, 0.1),
		0.05,
		15,
		20
	)

static func get_archetype(type: Type) -> Archetype:
	return archetypes.get(type)

static func get_random_archetype() -> Archetype:
	return get_weighted_random_archetype({})

static func get_weighted_random_archetype(custom_weights: Dictionary = {}) -> Archetype:
	var total_weight = 0.0
	var weighted_types = []
	
	for type in archetypes.keys():
		var archetype = archetypes[type]
		var weight = custom_weights.get(type, archetype.weight)
		total_weight += weight
		weighted_types.append({"type": type, "weight": weight})
	
	var random_value = randf() * total_weight
	var cumulative_weight = 0.0
	
	for item in weighted_types:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return archetypes[item["type"]]
	
	return archetypes[archetypes.keys()[0]]

static func get_neighborhood_affinity(car_type: Type, neighborhood_type: int) -> float:
	var affinity_table = NEIGHBORHOOD_AFFINITY.get(car_type, {})
	return affinity_table.get(neighborhood_type, 0.5)
