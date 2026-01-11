class_name Neighborhood
extends RefCounted

enum Type {
	SHANTY_TOWN = 0,
	RICH_RESIDENTIAL = 1,
	INDUSTRIAL = 2,
	DOWNTOWN = 3
}

# Configuración por defecto de cada tipo
const TYPE_CONFIGS = {
	Type.SHANTY_TOWN: {
		"min_floors": 1,
		"max_floors": 2,
		"block_heart_probability": 0.6,
		"traffic_density": 0.3
	},
	Type.RICH_RESIDENTIAL: {
		"min_floors": 2,
		"max_floors": 4,
		"block_heart_probability": 0.4,
		"traffic_density": 0.5
	},
	Type.INDUSTRIAL: {
		"min_floors": 5,
		"max_floors": 10,
		"block_heart_probability": 0.2,
		"traffic_density": 0.7
	},
	Type.DOWNTOWN: {
		"min_floors": 8,
		"max_floors": 15,
		"block_heart_probability": 0.1,
		"traffic_density": 1.0
	}
}

var type: Type
var seed: int
var index: int

# Datos de configuración de pisos
var min_floors: int
var max_floors: int
var block_heart_probability: float

# Datos de tránsito (0.0 - 1.0)
# Mayor tránsito = mayor jerarquía
var traffic_density: float

# Datos de expansión
var seed_face_idx: int = -1
var assigned_faces: Array[int] = []

func _init(p_type: Type, p_seed: int, p_index: int) -> void:
	type = p_type
	seed = p_seed
	index = p_index
	
	# Aplicar configuración por defecto
	var config = TYPE_CONFIGS[type]
	min_floors = config["min_floors"]
	max_floors = config["max_floors"]
	block_heart_probability = config["block_heart_probability"]
	traffic_density = config["traffic_density"]

func get_type_name() -> String:
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

# La jerarquía se basa directamente en el tránsito
# Mayor tránsito = mayor jerarquía
func get_hierarchy() -> float:
	return traffic_density

func set_floor_config(p_min: int, p_max: int, p_block_heart_prob: float) -> void:
	min_floors = p_min
	max_floors = p_max
	block_heart_probability = p_block_heart_prob

func set_traffic_density(p_density: float) -> void:
	traffic_density = clamp(p_density, 0.0, 1.0)

func add_face(face_idx: int) -> void:
	if face_idx not in assigned_faces:
		assigned_faces.append(face_idx)

func has_face(face_idx: int) -> bool:
	return face_idx in assigned_faces

func get_face_count() -> int:
	return assigned_faces.size()

# Compara jerarquías con otro barrio
# Retorna: 1 si self > other, -1 si self < other, 0 si igual
static func compare_hierarchy(a: Neighborhood, b: Neighborhood) -> int:
	var a_hierarchy = a.get_hierarchy()
	var b_hierarchy = b.get_hierarchy()
	
	if a_hierarchy > b_hierarchy:
		return 1  # a es mayor
	elif a_hierarchy < b_hierarchy:
		return -1  # b es mayor
	else:
		return 0  # igual jerarquía

# Retorna el barrio de mayor jerarquía entre dos
static func get_higher_hierarchy(a: Neighborhood, b: Neighborhood) -> Neighborhood:
	if a == null:
		return b
	if b == null:
		return a
	
	var comparison = compare_hierarchy(a, b)
	if comparison >= 0:
		return a
	else:
		return b
