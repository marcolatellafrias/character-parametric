class_name BranchArchetype
extends BuildingArchetype

## LA SUCURSAL, v1: el edificio de una compañía —el lounge y el garaje, ver conceptual/run-setup.md— como
## edificio de la ciudad de `MODULES` × `MODULES` módulos y `FLOORS` pisos, HUECO, con un portón a la calle
## y su interruptor. Adentro no hay nada todavía. Es un BuildingArchetype como cualquiera: pasa por el
## generador de manzanas, la cáscara, la piel y las fachadas; lo único suyo es cómo ocupa su lugar
## (`whole_section`, `fixed_floors`, `hollow`) y qué puerta lleva (`DoorArchetype.garage`). No está en el
## registro de distritos: dónde va en la ciudad se decide aparte (cuatro por compañía). En el sandbox se
## muestra a escala 1:1, en una manzana de sus dos módulos con sus medias calles.

## Con el módulo de la ciudad (~37 m) y pisos de ~6,8 m, 2 × 2 × 2 es un galpón de ~73 m de lado y 13,6 m
## de alto: grande para una nave de 10 m. Achicarla es cambiar estos dos números; la geometría no cambia.
const MODULES := 2
const FLOORS := 2
## Módulos por lado de una manzana de la ciudad (`City.distorted_grid_rows`): los de la sucursal miden lo
## mismo que los de la manzana de muestra de los edificios.
const CITY_MODULES_PER_SIDE := 6


func _init() -> void:
	archetype_id = "branch"
	display_name = "Sucursal"
	district = NeighborhoodTypes.District.INDUSTRIAL
	base_color = Color(0.58, 0.5, 0.42)
	fixed_floors = FLOORS
	whole_section = true
	hollow = true
	wall_thickness_m = 0.5
	flat_roof_chance = 1.0
	window_layout = FacadePlanner.Layout.STACKED
	window_archetypes = [WindowArchetype.wide()]
	door_archetypes = [DoorArchetype.garage()]
	window_sill_m = 3.0
	window_gap_m = 5.0


## Las sucursales que hay: una por ahora (van a ser una por compañía).
static func catalogue() -> Array[BranchArchetype]:
	return [BranchArchetype.new()]


func max_footprint() -> Vector2:
	var side := _side_m() + 2.0
	return Vector2(side, side)


## Una manzana de `MODULES` módulos por lado, con las medias calles medianas alrededor.
func _side_m() -> float:
	var streets := 2.0 * BlockGenerator.STREET_HALF_WIDTH_M[BlockGenerator.StreetType.MEDIUM]
	return (SAMPLE_SIDE_M - streets) / CITY_MODULES_PER_SIDE * MODULES + streets


func build(seed_value: int, parent: Node3D) -> Node3D:
	return _block_sample(seed_value, parent, _side_m(), 1.0, true)


func _configure_sample(city: Node3D) -> void:
	city.distorted_grid_rows = MODULES
	city.distorted_grid_columns = MODULES
	city.small_alleyways_count = 0
	city.big_alleyways_count = 0


func describe(_seed_value: int) -> PackedStringArray:
	return PackedStringArray(["%d × %d módulos · %d pisos · hueca · 1:1" % [MODULES, MODULES, FLOORS],
		"portón de %.0f × %.0f m con botón a cada lado" % [door_archetypes[0].width_m, door_archetypes[0].height_m]])
