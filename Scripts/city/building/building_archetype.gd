class_name BuildingArchetype extends RefCounted

# Clase base de arquetipo de edificio.
#
# Un arquetipo, dado un seed, produce los parámetros visuales / geométricos de un
# edificio. Es el equivalente de los arquetipos de personaje: el arquetipo dice
# QUÉ CLASE de edificio es, y el seed varía el individuo dentro de esa clase.
#
# HOY HAY UNO GENÉRICO POR DISTRITO y los tres son iguales salvo el tono de debug.
# Es a propósito: la capa de arquetipos existe para que cambiar el techo, las
# ventanas o el material de un barrio sea cambiar DATOS acá, sin tocar las reglas.
# Los arquetipos con nombre propio (fábrica, iglesia, conventillo) entran cuando
# haya con qué diferenciarlos.
#
# ⚠ El arquetipo NO contiene las reglas, solo los parámetros que las alimentan.
# Quién decide la forma de un techo es `RoofPlanner`, y lee de acá cuánta
# probabilidad de techo plano hay y qué pendiente usar.
#
# Las subclases concretas viven como inner classes al final de este archivo,
# mientras son pequeñas. Cuando la lógica de un arquetipo crezca, se puede
# promover ese arquetipo a su propio archivo (`archetypes/factory.gd`) y
# actualizar la referencia en ArchetypeDefinitions — sin tocar a los callers,
# porque todo habla con esta interfaz base.

# Identificador único del arquetipo
var archetype_id: String = "default"

# Familia de tono (0..1) para el color de debug. El seed varía saturación/valor
# dentro de esta familia, así que dos arquetipos distintos se distinguen a simple
# vista.
var base_hue: float = 0.0

# Características arquitectónicas
var has_chamfered_street_corners: bool = false

## Cuánto levanta la pieza de techo, en metros. Es la pendiente: sobre una celda de edificio (~11 m de
## lado) un valor de 2 m da un techo de inclinación creíble sin volverse una carpa.
var roof_pitch_height: float = 2.2

## Probabilidad de que el techo salga PLANO del todo, aun cuando su forma permita aguas. No es un caso de
## descarte: los techos planos dan variedad al conjunto y son los únicos donde se apoya un tanque de agua.
var flat_roof_chance: float = 0.35

## Color de debug derivado del arquetipo + seed.
## Tono fijo por arquetipo; el seed varía saturación y valor.
func get_color(color_seed: int) -> Color:
	var rng = RandomNumberGenerator.new()
	rng.seed = color_seed
	# Saturación como siempre: el color de debug está para DISTINGUIR arquetipos de un vistazo, y lavarlo
	# —se probó en pastel— los vuelve indistinguibles entre sí. El valor sí va un escalón por debajo del
	# original (era 0.6–0.9): con la niebla clara de fondo, los tonos claros se le confundían encima.
	return Color.from_hsv(
		base_hue,
		rng.randf_range(0.5, 0.8),
		rng.randf_range(0.45, 0.75),
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
# Arquetipos concretos: UNO GENÉRICO POR DISTRITO.
#
# Los tres son iguales salvo el tono, que se mantiene distinto para poder leer el
# distrito de un cluster de un vistazo mientras el color siga siendo debug. Acá es
# donde van a divergir: techo, ventanas, material, altura de pendiente.
# ---------------------------------------------------------------------------

class GenericPoor extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "generic_poor"
		base_hue = 0.05
		has_chamfered_street_corners = true

class GenericRich extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "generic_rich"
		base_hue = 0.28
		has_chamfered_street_corners = true

class GenericIndustrial extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "generic_industrial"
		base_hue = 0.55
		has_chamfered_street_corners = true
