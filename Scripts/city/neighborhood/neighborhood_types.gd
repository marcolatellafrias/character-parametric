class_name NeighborhoodTypes
extends RefCounted

enum Type {
	SHANTY_TOWN = 0,
	RICH_RESIDENTIAL = 1,
	INDUSTRIAL = 2,
	DOWNTOWN = 3
}

const CONFIGS = {
	Type.SHANTY_TOWN: {
		"min_floors": 1,
		"max_floors": 2,
		"block_heart_probability": 0.3,
		"traffic_density": 0.3,
		"min_crossings": 0,
		"max_crossings": 0
	},
	Type.RICH_RESIDENTIAL: {
		"min_floors": 2,
		"max_floors": 4,
		"block_heart_probability": 0.2,
		"traffic_density": 0.5,
		"min_crossings": 0,
		"max_crossings": 1
	},
	Type.INDUSTRIAL: {
		"min_floors": 5,
		"max_floors": 10,
		"block_heart_probability": 0.2,
		"traffic_density": 0.7,
		"min_crossings": 1,
		"max_crossings": 1
	},
	Type.DOWNTOWN: {
		"min_floors": 8,
		"max_floors": 15,
		"block_heart_probability": 0.2,
		"traffic_density": 1.0,
		"min_crossings": 1,
		"max_crossings": 2
	}
}

const CAR_WEIGHTS = {
	Type.SHANTY_TOWN: {
		CarArchetypes.Type.POOR_CAR: 0.45,
		CarArchetypes.Type.MOTORCYCLE: 0.25,
		CarArchetypes.Type.TAXI: 0.15,
		CarArchetypes.Type.UTILITY_TRUCK: 0.08,
		CarArchetypes.Type.GARBAGE_TRUCK: 0.05,
		CarArchetypes.Type.RICH_CAR: 0.02,
		CarArchetypes.Type.VENDING_TRUCK: 0.0,
		CarArchetypes.Type.ADVERTISEMENT_TRUCK: 0.0,
		CarArchetypes.Type.POLICE_CAR: 0.0
	},
	Type.RICH_RESIDENTIAL: {
		CarArchetypes.Type.RICH_CAR: 0.4,
		CarArchetypes.Type.TAXI: 0.2,
		CarArchetypes.Type.POOR_CAR: 0.15,
		CarArchetypes.Type.MOTORCYCLE: 0.1,
		CarArchetypes.Type.POLICE_CAR: 0.1,
		CarArchetypes.Type.UTILITY_TRUCK: 0.05,
		CarArchetypes.Type.GARBAGE_TRUCK: 0.0,
		CarArchetypes.Type.VENDING_TRUCK: 0.0,
		CarArchetypes.Type.ADVERTISEMENT_TRUCK: 0.0
	},
	Type.INDUSTRIAL: {
		CarArchetypes.Type.UTILITY_TRUCK: 0.3,
		CarArchetypes.Type.GARBAGE_TRUCK: 0.15,
		CarArchetypes.Type.POOR_CAR: 0.2,
		CarArchetypes.Type.ADVERTISEMENT_TRUCK: 0.15,
		CarArchetypes.Type.VENDING_TRUCK: 0.1,
		CarArchetypes.Type.MOTORCYCLE: 0.1,
		CarArchetypes.Type.RICH_CAR: 0.0,
		CarArchetypes.Type.POLICE_CAR: 0.0,
		CarArchetypes.Type.TAXI: 0.0
	},
	Type.DOWNTOWN: {
		CarArchetypes.Type.TAXI: 0.3,
		CarArchetypes.Type.RICH_CAR: 0.2,
		CarArchetypes.Type.POOR_CAR: 0.15,
		CarArchetypes.Type.POLICE_CAR: 0.15,
		CarArchetypes.Type.MOTORCYCLE: 0.1,
		CarArchetypes.Type.UTILITY_TRUCK: 0.1,
		CarArchetypes.Type.GARBAGE_TRUCK: 0.0,
		CarArchetypes.Type.VENDING_TRUCK: 0.0,
		CarArchetypes.Type.ADVERTISEMENT_TRUCK: 0.0
	}
}

static func get_type_name(type: Type) -> String:
	match type:
		Type.SHANTY_TOWN:
			return "Shanty Town"
		Type.RICH_RESIDENTIAL:
			return "Rich Residential"
		Type.INDUSTRIAL:
			return "Industrial"
		Type.DOWNTOWN:
			return "Downtown"
		_:
			return "Unknown"

static func get_hierarchy(type: Type) -> float:
	return CONFIGS[type]["traffic_density"]

static func get_car_weights(type: Type) -> Dictionary:
	return CAR_WEIGHTS.get(type, {})

static func get_higher_hierarchy_type(type_a: Type, type_b: Type) -> Type:
	var hierarchy_a = get_hierarchy(type_a)
	var hierarchy_b = get_hierarchy(type_b)
	return type_a if hierarchy_a >= hierarchy_b else type_b
	
static func get_crossings_range(type: Type) -> Vector2i:
	var cfg = CONFIGS[type]
	return Vector2i(cfg["min_crossings"], cfg["max_crossings"])
