class_name Bridge
extends RefCounted

var total_width: int
var pathway_height: int
var base_height: int
var arc_height: int
var arc_length: int
var railing_width: int
var railing_height: int

var railing_type: Array[String]
var arc_type: Array[String]
var base_type: Array[String]
var pathway_type: Array[String]

func get_cross_section_size() -> Vector2i:
	return Vector2i(total_width, pathway_height + base_height + arc_height)

func _init(archetype_key: String) -> void:
	var chosen: Dictionary = archetypes[archetype_key]

	total_width = chosen["total_width"]
	pathway_height = chosen["pathway_height"]
	base_height = chosen["base_height"]
	arc_height = chosen["arc_height"]
	arc_length = chosen["arc_length"]
	railing_width = chosen["railing_width"]
	railing_height = chosen["railing_height"]
	railing_type.assign(chosen["railing_type"])
	arc_type.assign(chosen["arc_type"])
	base_type.assign(chosen["base_type"])
	pathway_type.assign(chosen["pathway_type"])


static func select_archetype(rng: RandomNumberGenerator, context: Dictionary) -> String:
	var weights = _get_archetype_weights(context)
	var total = 0.0
	for key in weights:
		total += weights[key]
	var roll = rng.randf() * total
	var cumulative = 0.0
	for key in weights:
		cumulative += weights[key]
		if roll <= cumulative:
			return key
	return weights.keys().back()


static func _get_archetype_weights(context: Dictionary) -> Dictionary:
	var floor_idx: int = context.get("floor_idx", 1)
	var bridge_length_cells: float = context.get("bridge_length_cells", 999.0)
	var floor_t = clampf(float(floor_idx - 1) / 5.0, 0.0, 1.0)

	var weights = {
		"wooden_simple": lerpf(10.0, 1.0, floor_t),
		"stone_arched": lerpf(0.0, 5.0, floor_t),
		"iron_suspension": lerpf(0.0, 5.0, floor_t),
	}

	for key in archetypes:
		var arc_len: int = archetypes[key]["arc_length"]
		if arc_len > 0 and bridge_length_cells < arc_len * 3.0:
			weights[key] = 0.0

	return weights

static var archetypes: Dictionary = {
	"wooden_simple": {
		"total_width": 16,
		"pathway_height": 1,
		"base_height": 8,
		"arc_height": 0,
		"arc_length": 0,
		"railing_width": 4,
		"railing_height": 4,
		"railing_type": ["wood_post"],
		"arc_type": ["none"],
		"base_type": ["wood_beam"],
		"pathway_type": ["wood_plank"],
	},
	"stone_arched": {
		"total_width": 24,
		"pathway_height": 1,
		"base_height": 10,
		"arc_height": 8,
		"arc_length": 20,
		"railing_width": 4,
		"railing_height": 4,
		"railing_type": ["stone_baluster"],
		"arc_type": ["roman_arch"],
		"base_type": ["stone_pillar"],
		"pathway_type": ["stone_slab"],
	},
	"iron_suspension": {
		"total_width": 24,
		"pathway_height": 1,
		"base_height": 10,
		"arc_height": 10,
		"arc_length": 20,
		"railing_width": 4,
		"railing_height": 4,
		"railing_type": ["iron_cable", "iron_post"],
		"arc_type": ["suspension_cable"],
		"base_type": ["iron_pylon"],
		"pathway_type": ["iron_grate", "wood_plank"],
	},
}
