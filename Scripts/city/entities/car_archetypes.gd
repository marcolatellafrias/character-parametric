extends Object
class_name CarArchetypes

static var speed_debug_factor: float = 0.533
static var size_debug_factor: float = 7.2

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

class Archetype:
	var name: String
	var width: float
	var height: float
	var depth: float
	var min_speed: float
	var max_speed: float
	var color: Color
	var weight: float
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
	# Big trucks are rare ambient spawns: small weight, low global cap.
	archetypes[Type.VENDING_TRUCK] = Archetype.new(
		"Vending Truck",
		0.175 * size_debug_factor,
		0.2 * size_debug_factor,
		0.5 * size_debug_factor,
		8.0 * speed_debug_factor,
		12.0 * speed_debug_factor,
		Color(0.9, 0.5, 0.1),
		0.03,
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
		150
	)
	
	archetypes[Type.MOTORCYCLE] = Archetype.new(
		"Motorcycle",
		0.05 * size_debug_factor,
		0.049 * size_debug_factor,
		0.2 * size_debug_factor,
		22.0 * speed_debug_factor,
		40.0 * speed_debug_factor,
		Color(0.9, 0.1, 0.1),
		0.2,
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
		0.03,
		3,
		0.1
	)
	
	archetypes[Type.ADVERTISEMENT_TRUCK] = Archetype.new(
		"Advertisement Truck",
		0.175 * size_debug_factor,
		0.3 * size_debug_factor,
		0.75 * size_debug_factor,
		7.0 * speed_debug_factor,
		10.0 * speed_debug_factor,
		Color(0.9, 0.1, 0.9),
		0.03,
		1,
		0.2
	)
	
	archetypes[Type.GARBAGE_TRUCK] = Archetype.new(
		"Garbage Truck",
		0.175 * size_debug_factor,
		0.225 * size_debug_factor,
		0.65 * size_debug_factor,
		8.0 * speed_debug_factor,
		12.0 * speed_debug_factor,
		Color(0.2, 0.6, 0.2),
		0.03,
		2,
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

# Seeded type selection shared by spawner and car so both derive the same
# archetype from the same seed (multiplayer/prediction friendly).
static func select_type_seeded(rng: RandomNumberGenerator, custom_weights: Dictionary = {}) -> Type:
	var total_weight = 0.0
	var weighted_types = []

	for type in Type.values():
		var archetype = get_archetype(type)
		var weight = custom_weights.get(type, archetype.weight)
		total_weight += weight
		weighted_types.append({"type": type, "weight": weight})

	var random_value = rng.randf() * total_weight
	var cumulative_weight = 0.0

	for item in weighted_types:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return item["type"]

	return Type.POOR_CAR
