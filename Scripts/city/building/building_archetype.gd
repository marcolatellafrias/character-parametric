class_name BuildingArchetype extends SeededArchetype

# Clase base de arquetipo de edificio.
#
# Un arquetipo, dado un seed, produce los parámetros visuales / geométricos de un
# edificio. Es el equivalente de los arquetipos de personaje: el arquetipo dice
# QUÉ CLASE de edificio es, y el seed varía el individuo dentro de esa clase.
#
# HOY HAY UNO GENÉRICO POR DISTRITO y los tres son iguales salvo el color y las ventanas.
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

## De qué distrito es: lo pone el registro (ArchetypeDefinitions) al instanciarlo. Es lo que dice de qué
## manzana es muestra en el design sandbox.
var district: NeighborhoodTypes.District = NeighborhoodTypes.District.POOR

## LA MUESTRA DEL SANDBOX: una manzana entera sin distorsión ni relieve, a `SAMPLE_SCALE`, con UN edificio
## de este arquetipo completo y el resto en gris translúcido (ver City.generate_block_sample).
const SAMPLE_SIDE_M := 246.0
const SAMPLE_SCALE := 1.0 / 25.0

## EL COLOR DEL EDIFICIO, la familia del arquetipo; el seed lo corre apenas (ver `get_color`). Revoque y
## piedra de 1900: cremas, ocres, grises cálidos. Nunca blanco puro, que con la niebla clara de fondo se
## pierde. (El color saturado que distingue barrios es de la vista debug: NeighborhoodTypes.debug_color.)
var base_color := Color(0.66, 0.60, 0.50)

# Características arquitectónicas
var has_chamfered_street_corners: bool = false

## Cuánto espesor de pared se ve alrededor de cada abertura (ver BuildingSkin.add_opening). Es de la pared,
## no de la pieza: una ventana es más fina que la pared que la rodea.
var wall_thickness_m: float = 0.3

## CÓMO OCUPA SU LUGAR, cuando lo dice el arquetipo y no el sorteo: `fixed_floors` pisos (0 = los que
## sortee el nivel de la manzana, ver BuildingCluster) y, con `whole_section`, todas las celdas de su
## sección (ver BlockGenerator). Y si es HUECO: una cáscara con su espesor por dentro y sin losas entre
## pisos, para entrar (ver BuildingSkin.hollow); el collider es entonces la piel. Lo necesita una sucursal;
## un edificio común no lo toca.
var fixed_floors: int = 0
var whole_section: bool = false
var hollow: bool = false

## Cuánto levanta la pieza de techo, en metros. Es la pendiente: sobre una celda de edificio (~11 m de
## lado) un valor de 2 m da un techo de inclinación creíble sin volverse una carpa.
var roof_pitch_height: float = 2.2

## Cuánto se mete para adentro el faldón del techo francés, en CELDAS DE EDIFICIO (80 por módulo, ~0,15-0,2 m
## cada una). Va en celdas y no en una fracción del módulo para que el faldón tenga la misma medida sobre un
## edificio angosto que sobre uno ancho: el que antes medía media celda por construcción dejaba sin tapa a
## todo edificio de una celda de ancho. Con 2,2 m de alto y ~1,4 m de faldón queda la pendiente empinada de
## una mansarda.
var roof_skirt_building_cells: float = 8.0

## Probabilidad de que el techo salga PLANO del todo, aun cuando su forma permita aguas. No es un caso de
## descarte: los techos planos dan variedad al conjunto y son los únicos donde se apoya un tanque de agua.
var flat_roof_chance: float = 0.35
## Probabilidad de que un edificio de esquina lleve CÚPULA sobre la ochava (ver RoofPlanner.cupola).
var cupola_chance: float = 0.3

## LAS VENTANAS. Solo números: las reglas que los usan están en FacadePlanner.
var window_layout: int = FacadePlanner.Layout.STACKED
## Qué tipos de ventana y de puerta puede llevar (ver WindowArchetype, DoorArchetype): cada edificio elige
## uno de cada con su semilla (`pick_window`, `pick_door`), y ese es el tamaño real de sus piezas.
var window_archetypes: Array[WindowArchetype] = [WindowArchetype.tall()]
var door_archetypes: Array[DoorArchetype] = [DoorArchetype.delivery()]
## A qué altura del piso arranca la ventana. En RANDOM es la altura mínima.
var window_sill_m: float = 1.6
## Pared libre entre dos columnas de ventanas (STACKED). Más grande = menos ventanas.
var window_gap_m: float = 1.4
## Qué fracción de las columnas lleva ventana en cada piso (RANDOM): el desorden de una villa, sin que
## ninguna ventana se corra de la grilla.
var window_fill: float = 0.6

## El color de UN edificio: `base_color` corrido apenas por el seed en tono, saturación y valor, para que
## dos vecinos del mismo arquetipo no salgan idénticos sin dejar de ser de la misma familia.
func get_color(color_seed: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = color_seed
	return Color.from_hsv(
		wrapf(base_color.h + rng.randf_range(-0.015, 0.015), 0.0, 1.0),
		clampf(base_color.s + rng.randf_range(-0.06, 0.06), 0.0, 1.0),
		clampf(base_color.v + rng.randf_range(-0.07, 0.07), 0.0, 0.85),
		1.0
	)

func pick_window(color_seed: int) -> WindowArchetype:
	return window_archetypes[abs(color_seed) % window_archetypes.size()]


func pick_door(color_seed: int) -> DoorArchetype:
	return door_archetypes[abs(color_seed) % door_archetypes.size()]


# ── La muestra del sandbox (SeededArchetype) ─────────────────────────────────────────────────────

func max_footprint() -> Vector2:
	var side := SAMPLE_SIDE_M * SAMPLE_SCALE + 2.0
	return Vector2(side, side)


## Una manzana de este distrito, generada con `seed_value` y escalada, centrada en la parcela, con lo que
## la fila tenga elegido (distorsión, vista). `load` y no `preload`: la ciudad ya depende de los
## arquetipos, y un preload cruzado no carga.
func build(seed_value: int, parent: Node3D) -> Node3D:
	return _block_sample(seed_value, parent, SAMPLE_SIDE_M, SAMPLE_SCALE, false)


## La manzana de muestra: un City sin generar, a `scale`, centrado en la parcela, con lo que la fila tenga
## elegido (distorsión, vista) y lo que la subclase configure (`_configure_sample`), generado como manzana
## sola (ver City.generate_block_sample).
func _block_sample(seed_value: int, parent: Node3D, side_m: float, scale: float, colliders: bool) -> Node3D:
	var city: Node3D = load("res://Scripts/city/core/city.gd").new()
	city.name = "BlockSample"
	city.auto_generate = false
	city.scale = Vector3.ONE * scale
	var half := side_m * scale * 0.5
	city.position = Vector3(-half, SandboxParcel.PLANE_LIFT * 3.0, -half)
	for property in ["building_debug_view", "building_grid"] + BOX_FLAGS:
		if options.has(property):
			city.set(property, options[property])
	_configure_sample(city)
	parent.add_child(city)
	city.generate_block_sample(seed_value, self, side_m, _distortion(), colliders)
	return city


## Lo que una subclase cambia del City de su muestra antes de generarla (cuántos módulos, callejones).
func _configure_sample(_city: Node3D) -> void:
	pass


## Las teclas de la fila de edificios: la distorsión de la manzana por eje —en niveles fijos, sin azar,
## para ver el rango entero— y lo que en el juego es el menú de vista (F3): la malla debug, la grilla, las
## cajas de lo colocado, sobre todas las manzanas de la fila a la vez.
const DISTORTION_LEVELS: Array[float] = [0.0, 0.05, 0.1, 0.2]
## Las cajas de lo colocado, una por manera de colocar (ver CityIndex.Grid): la tecla las prende juntas.
const BOX_FLAGS: Array[String] = ["show_deformable_boxes", "show_rigid_boxes", "show_free_boxes"]


func category_options() -> Array[Dictionary]:
	return [
		{"key": KEY_X, "label": _distortion_label.bind("distortion_x", "X"), "apply": _cycle_distortion.bind("distortion_x")},
		{"key": KEY_Z, "label": _distortion_label.bind("distortion_z", "Z"), "apply": _cycle_distortion.bind("distortion_z")},
		{"key": KEY_B, "label": _flag_label.bind("building_debug_view", "B  vista debug de edificios"),
			"apply": _toggle_view.bind("building_debug_view")},
		{"key": KEY_G, "label": _grid_label, "apply": _cycle_grid},
		{"key": KEY_K, "label": _flag_label.bind("show_deformable_boxes", "K  cajas de lo colocado"),
			"apply": _toggle_boxes},
	]


func _distortion() -> Vector2:
	return Vector2(DISTORTION_LEVELS[int(options.get("distortion_x", 0))],
		DISTORTION_LEVELS[int(options.get("distortion_z", 0))])


func _distortion_label(axis: String, key_name: String) -> String:
	return "%s  distorsión en %s: %.2f" % [key_name, axis.substr(11), DISTORTION_LEVELS[int(options.get(axis, 0))]]


func _flag_label(property: String, text: String) -> String:
	return text + ("  ✓" if bool(options.get(property, false)) else "")


func _grid_label() -> String:
	return "G  grilla: %s" % ["ninguna", "deformable", "rígida"][int(options.get("building_grid", 0))]


## La distorsión pide regenerar: es geometría. Mismas semillas, así solo cambia eso.
func _cycle_distortion(parcels: Array, axis: String) -> void:
	options[axis] = (int(options.get(axis, 0)) + 1) % DISTORTION_LEVELS.size()
	for parcel in parcels:
		parcel.regenerate(parcel.seed_value, false)


## La vista no: es un `set` sobre las manzanas que ya están.
func _toggle_view(parcels: Array, property: String) -> void:
	options[property] = not bool(options.get(property, false))
	_apply_to_samples(parcels, property, options[property])


func _cycle_grid(parcels: Array) -> void:
	options["building_grid"] = (int(options.get("building_grid", 0)) + 1) % 3
	_apply_to_samples(parcels, "building_grid", options["building_grid"])


func _toggle_boxes(parcels: Array) -> void:
	var on := not bool(options.get(BOX_FLAGS[0], false))
	for flag in BOX_FLAGS:
		options[flag] = on
		_apply_to_samples(parcels, flag, on)


static func _apply_to_samples(parcels: Array, property: String, value: Variant) -> void:
	for parcel in parcels:
		for city in (parcel as Node).find_children("BlockSample", "", true, false):
			city.set(property, value)


func describe(seed_value: int) -> PackedStringArray:
	return PackedStringArray([
		"distrito: %s · manzana a 1:%d" % [NeighborhoodTypes.District.keys()[district], roundi(1.0 / SAMPLE_SCALE)],
		"ventana: %s · puerta: %s" % [pick_window(seed_value).display_name, pick_door(seed_value).display_name],
	])


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
# Acá es donde divergen: color, techo, ventanas, material, altura de pendiente.
# Hoy divergen el COLOR y las VENTANAS, y los números son de tanteo de estilo.
# ---------------------------------------------------------------------------

## Villa: ventanas chicas y desordenadas.
class GenericPoor extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "generic_poor"
		display_name = "Genérico pobre"
		base_color = Color(0.64, 0.55, 0.42)  # revoque ocre
		has_chamfered_street_corners = true
		window_layout = FacadePlanner.Layout.RANDOM
		window_archetypes = [WindowArchetype.small()]
		door_archetypes = [DoorArchetype.delivery()]
		window_sill_m = 1.0
		window_fill = 0.55
		cupola_chance = 0.15

## Rico: ventanas altas, apiladas, con ritmo apretado.
class GenericRich extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "generic_rich"
		display_name = "Genérico rico"
		base_color = Color(0.74, 0.69, 0.58)  # piedra crema
		has_chamfered_street_corners = true
		window_layout = FacadePlanner.Layout.STACKED
		window_archetypes = [WindowArchetype.tall()]
		door_archetypes = [DoorArchetype.delivery()]
		window_sill_m = 1.6
		window_gap_m = 1.4
		cupola_chance = 0.7

## Industrial: pocas ventanas, anchas y bajas, muy separadas.
class GenericIndustrial extends BuildingArchetype:
	func _init() -> void:
		archetype_id = "generic_industrial"
		display_name = "Genérico industrial"
		base_color = Color(0.52, 0.47, 0.42)  # ladrillo gris cálido
		has_chamfered_street_corners = true
		window_layout = FacadePlanner.Layout.STACKED
		window_archetypes = [WindowArchetype.wide()]
		door_archetypes = [DoorArchetype.gate(), DoorArchetype.delivery()]
		window_sill_m = 3.0
		window_gap_m = 5.0
		cupola_chance = 0.1
