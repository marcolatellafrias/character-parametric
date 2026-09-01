class_name AppearancePreset

## PRESET DE APARIENCIA FIJO — pisa los colores que el seed haya elegido.
##
## El sistema por seed (paletas por specie en `species.gd`) sigue intacto y es el que va a quedar. Esto
## es un candado encima, para poder cerrar UN personaje con una combinación elegida a mano sin perder
## la variedad mientras tanto — el mismo patrón que `EntityInstantiation.FORCE_ARCHETYPE`.
##
## Se aplica al FINAL de `_resolve`, así que el rng se consume igual y sacar el candado devuelve
## exactamente el comportamiento anterior, sin desplazar ninguna otra tirada.
##
## Vale para todos los personajes por igual: el propio y los que spawnean.

## Preset activo. **Cadena vacía = ninguno**, y vuelve a mandar el seed.
const FORCE := "noir"

## Los presets. El nombre es la clave; los colores son el ALBEDO en sRGB 0–255.
const PRESETS := {
	"noir": {
		"skin":    Color8(180, 126, 98),
		"cloth":   Color8(86, 90, 104),
		"hair":    Color8(30, 30, 30),
		"leather": Color8(96, 60, 44),  # cuero cálido: contrasta con el traje frío sin romper la paleta
	},
}


## Pisa los colores de `inst` si hay un preset forzado. No toca nada más: proporciones, marcha y
## specie siguen saliendo del seed.
static func apply(inst: EntityInstantiation) -> void:
	if FORCE.is_empty():
		return
	var p: Dictionary = PRESETS.get(FORCE, {})
	if p.is_empty():
		push_warning("AppearancePreset: no existe el preset '%s'. Se usan los colores del seed." % FORCE)
		return
	inst.skin_color    = p["skin"]
	inst.cloth_color   = p["cloth"]
	inst.hair_color    = p["hair"]
	inst.leather_color = p["leather"]
