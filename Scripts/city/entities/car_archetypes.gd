extends Object
class_name CarArchetypes

enum Type {
	CAR,
	TRUCK,
	MOTORCYCLE
}

class Archetype:
	var name: String
	var min_width: float
	var max_width: float
	var min_height: float
	var max_height: float
	var min_depth: float
	var max_depth: float
	var min_speed: float
	var max_speed: float
	var color_palette: Array[Color]
	var weight: float  # Peso para spawning
	
	func _init(
		p_name: String,
		p_min_width: float, p_max_width: float,
		p_min_height: float, p_max_height: float,
		p_min_depth: float, p_max_depth: float,
		p_min_speed: float, p_max_speed: float,
		p_color_palette: Array[Color],
		p_weight: float = 1.0
	):
		name = p_name
		min_width = p_min_width
		max_width = p_max_width
		min_height = p_min_height
		max_height = p_max_height
		min_depth = p_min_depth
		max_depth = p_max_depth
		min_speed = p_min_speed
		max_speed = p_max_speed
		color_palette = p_color_palette
		weight = p_weight
	
	func get_random_dimensions() -> Dictionary:
		return {
			"width": randf_range(min_width, max_width),
			"height": randf_range(min_height, max_height),
			"depth": randf_range(min_depth, max_depth),
			"speed": randf_range(min_speed, max_speed)
		}
	
	func get_random_color() -> Color:
		if color_palette.is_empty():
			return Color(randf(), randf(), randf(), 1.0)
		return color_palette[randi() % color_palette.size()]

static var archetypes: Dictionary = {}

static func _static_init() -> void:
	# Definir arquetipos con pesos
	archetypes[Type.CAR] = Archetype.new(
		"Car",
		0.15, 0.2,    # width
		0.08, 0.12,   # height
		0.5, 0.7,    # depth
		8.0, 15.0,    # speed
		[
			Color(0.8, 0.1, 0.1),  # Rojo
			Color(0.1, 0.1, 0.8),  # Azul
			Color(0.1, 0.1, 0.1),  # Negro
			Color(0.9, 0.9, 0.9),  # Blanco
			Color(0.6, 0.6, 0.6),  # Gris
		],
		0.7  # 70% probabilidad
	)
	
	archetypes[Type.TRUCK] = Archetype.new(
		"Truck",
		0.4, 0.6,     # width
		0.35, 0.40,   # height
		0.9, 1.3,     # depth
		4.0, 6.0,    # speed
		[
			Color(0.3, 0.3, 0.3),  # Gris oscuro
			Color(0.5, 0.2, 0.1),  # Café
			Color(0.1, 0.3, 0.6),  # Azul oscuro
		],
		0.1  # 10% probabilidad
	)
	
	archetypes[Type.MOTORCYCLE] = Archetype.new(
		"Motorcycle",
		0.08, 0.12,   # width
		0.06, 0.1,    # height
		0.15, 0.25,   # depth
		12.0, 20.0,   # speed
		[
			Color(0.9, 0.1, 0.1),  # Rojo brillante
			Color(0.1, 0.9, 0.1),  # Verde brillante
			Color(0.1, 0.1, 0.1),  # Negro
		],
		0.2  # 20% probabilidad
	)

static func get_archetype(type: Type) -> Archetype:
	return archetypes.get(type)

static func get_random_archetype() -> Archetype:
	return get_weighted_random_archetype({})

static func get_weighted_random_archetype(custom_weights: Dictionary = {}) -> Archetype:
	# Calcular el peso total
	var total_weight = 0.0
	var weighted_types = []
	
	for type in archetypes.keys():
		var archetype = archetypes[type]
		# Usar peso personalizado si existe, sino usar el peso del arquetipo
		var weight = custom_weights.get(type, archetype.weight)
		total_weight += weight
		weighted_types.append({"type": type, "weight": weight})
	
	# Seleccionar aleatoriamente basado en pesos
	var random_value = randf() * total_weight
	var cumulative_weight = 0.0
	
	for item in weighted_types:
		cumulative_weight += item["weight"]
		if random_value <= cumulative_weight:
			return archetypes[item["type"]]
	
	# Fallback (no debería llegar aquí)
	return archetypes[archetypes.keys()[0]]
