class_name BuildingArchetype extends RefCounted

# Clase base de arquetipo de edificio.
#
# Un arquetipo, dado un seed, produce los parámetros visuales / geométricos de
# un edificio. Por ahora solo produce un color (variable temporal de debug,
# probablemente se deprecará). En el futuro cada subclase implementará
# `generate_geometry(seed)` para la geometría procedural.
#
# Las subclases concretas viven como inner classes al final de este archivo,
# mientras son pequeñas. Cuando la lógica de un arquetipo crezca, se puede
# promover ese arquetipo a su propio archivo (`archetypes/office_tower.gd`) y
# actualizar la referencia en ArchetypeDefinitions — sin tocar a los callers,
# porque todo habla con esta interfaz base.

# Identificador único del arquetipo
var archetype_id: String = "default"

# Familia de tono (0..1) para el color de debug. El seed varía saturación/valor
# dentro de esta familia, así que dos arquetipos del mismo neighborhood se
# distinguen a simple vista.
var base_hue: float = 0.0

# Características arquitectónicas
var has_chamfered_street_corners: bool = false

## Color de debug derivado del arquetipo + seed.
## Tono fijo por arquetipo; el seed varía saturación y valor.
func get_color(color_seed: int) -> Color:
	var rng = RandomNumberGenerator.new()
	rng.seed = color_seed
	return Color.from_hsv(
		base_hue,
		rng.randf_range(0.5, 0.8),
		rng.randf_range(0.6, 0.9),
		1.0
	)

## Determina si aplicar chamfer a una esquina de calle basado en seed.
## Retorna el valor de chamfer (en celdas) o 0 si no aplica.
func get_street_corner_chamfer_value(vertex_seed: int) -> int:
	if not has_chamfered_street_corners:
		return 0

	var rng = RandomNumberGenerator.new()
	rng.seed = vertex_seed

	# 100% de probabilidad (para debugging)
	if rng.randf() < 1.0:
		return 16  # Hardcoded: 16 celdas (4x grid)

	return 0

# Seam para el futuro — geometría procedural por arquetipo:
# func generate_geometry(geometry_seed: int) -> ...:
#     pass


# ---------------------------------------------------------------------------
# Arquetipos concretos (2 por neighborhood).
# Pequeños por ahora: solo id, tono y chamfer. Aquí crecerá la lógica propia
# de cada arquetipo hasta que amerite su propio archivo.
# ---------------------------------------------------------------------------

# --- Shanty Town ---
class ShantyBasic extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "shanty_basic"
		base_hue = 0.05
		has_chamfered_street_corners = true

class ShantyMakeshift extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "shanty_makeshift"
		base_hue = 0.10
		has_chamfered_street_corners = true

# --- Rich Residential ---
class MansionClassic extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "mansion_classic"
		base_hue = 0.28
		has_chamfered_street_corners = true

class MansionModern extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "mansion_modern"
		base_hue = 0.33
		has_chamfered_street_corners = true

# --- Industrial ---
class WarehouseBasic extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "warehouse_basic"
		base_hue = 0.55
		has_chamfered_street_corners = true

class FactoryModern extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "factory_modern"
		base_hue = 0.60
		has_chamfered_street_corners = true

# --- Downtown ---
class OfficeTower extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "office_tower"
		base_hue = 0.75
		has_chamfered_street_corners = true

class MixedUse extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "mixed_use"
		base_hue = 0.83
		has_chamfered_street_corners = true
