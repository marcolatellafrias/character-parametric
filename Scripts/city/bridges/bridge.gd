class_name Bridge
extends RefCounted

var total_width: int
var pathway_height: int
var base_height: int
var arc_height: int
var railing_width: int
var railing_height: int

var railing_type: Array[String]
var arc_type: Array[String]
var base_type: Array[String]
var pathway_type: Array[String]

func get_cross_section_size() -> Vector2i:
	return Vector2i(total_width, pathway_height + base_height + arc_height)

func _init(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	
	var keys := archetypes.keys()
	var chosen: Dictionary = archetypes[keys[rng.randi() % keys.size()]]
	
	total_width = chosen["total_width"]
	pathway_height = chosen["pathway_height"]
	base_height = chosen["base_height"]
	arc_height = chosen["arc_height"]
	railing_width = chosen["railing_width"]
	railing_height = chosen["railing_height"]
	railing_type = chosen["railing_type"]
	arc_type = chosen["arc_type"]
	base_type = chosen["base_type"]
	pathway_type = chosen["pathway_type"]

static var archetypes: Dictionary = {
	"wooden_simple": {
		"total_width": 4,
		"pathway_height": 1,
		"base_height": 2,
		"arc_height": 0,
		"railing_width": 1,
		"railing_height": 2,
		"railing_type": ["wood_post"],
		"arc_type": ["none"],
		"base_type": ["wood_beam"],
		"pathway_type": ["wood_plank"],
	},
	"stone_arched": {
		"total_width": 6,
		"pathway_height": 1,
		"base_height": 4,
		"arc_height": 3,
		"railing_width": 1,
		"railing_height": 3,
		"railing_type": ["stone_baluster"],
		"arc_type": ["roman_arch"],
		"base_type": ["stone_pillar"],
		"pathway_type": ["stone_slab"],
	},
	"iron_suspension": {
		"total_width": 8,
		"pathway_height": 1,
		"base_height": 3,
		"arc_height": 6,
		"railing_width": 1,
		"railing_height": 4,
		"railing_type": ["iron_cable", "iron_post"],
		"arc_type": ["suspension_cable"],
		"base_type": ["iron_pylon"],
		"pathway_type": ["iron_grate", "wood_plank"],
	},
}
