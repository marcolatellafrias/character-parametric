class_name NeighborhoodTypes
extends RefCounted

## DOS EJES INDEPENDIENTES — el DISTRITO dice de qué está hecho el lugar, la ALTURA dice qué tan difícil es
## volarlo. Ver technical/city-generation.md.
##
## Antes eran un solo enum de cuatro tipos, y ahí estaba el error: "Downtown" no es una cultura, es una
## densidad. Un centro rico son torres de vidrio, uno pobre son conventillos apilados y uno industrial son
## silos pegados. Mezclados en una sola etiqueta, subir la altura de una villa obligaba a convertirla en
## otro barrio.
##
##   · DISTRITO (`District`): quién vive ahí y de qué está construido. Manda sobre el estilo de los
##     edificios (ver ArchetypeDefinitions), qué autos circulan, cuánto tráfico hay y qué tan seguido una
##     manzana tiene patio interno. Son tres: pobre, rico e industrial.
##   · ALTURA (`Height`): cuántos pisos tienen sus edificios, y con eso cuántos puentes cruzan sus calles.
##     Es el eje de GAMEPLAY, y está calibrado contra la nave (ver `FLOORS`).
##
## Los dos se reparten en PARCHES independientes por toda la ciudad, sin regla radial: así una villa puede
## ser un cañón de conventillos en el centro y un barrio rico puede ser bajo y abierto contra la muralla.

## Los tres distritos.
enum District {
	POOR = 0,
	RICH = 1,
	INDUSTRIAL = 2
}

## Los tres niveles de altura, calibrados contra la nave: su meta de altura topa en 8 PISOS (53,5 m, ver
## `Ship.max_altitude`). El "propulsor vertical que se gasta" es intención de diseño y TODAVÍA NO EXISTE en
## código, así que la calibración se hace contra los 8 pisos que la nave alcanza de verdad.
##   · BAJO: se sobrevuela sin tocar nada. Es el respiro, y abre la vista.
##   · MEDIO: su mitad baja (7 y 8) se pasa justo por arriba; de 9 para arriba ya obliga a rodear.
##   · ALTO: no existe el "por arriba". Se vuela entre ellos, y es la norma del juego.
##
## El HUECO entre BAJO y MEDIO (4→7) es a propósito: son los dos niveles que el jugador mira para decidir
## si pasa por arriba o rodea, y si se tocan deja de distinguirlos de un vistazo.
##
## Entre MEDIO y ALTO NO hay hueco, y eso también es a propósito. ALTO arranca en 11, tres pisos por encima
## del techo de la nave (8): sigue siendo infranqueable con margen, y arrancarlo en 15 —como estaba— no
## compraba ni un piso de gameplay mientras dejaba a todas las torres dentro de una franja de ±23%, que a la
## vista es una pared pareja.
enum Height {
	LOW = 0,
	MID = 1,
	TALL = 2
}

## Pisos de cada nivel, y cuánto empuja sobre la cantidad de puentes de sus calles (ver
## GraphCityGenerator._get_bridge_count): sin edificios altos no hay de dónde colgarlos.
##
## `skew` sesga el sorteo DENTRO de la franja (ver `draw_floor_count`): 1.0 es parejo, 2.0 amontona la
## mayoría contra el piso bajo y deja unas pocas llegando al techo. ALTO lo usa porque con sorteo parejo
## sus ~11 clusters por manzana caían todos al medio de la franja y la manzana leía como una loza; sesgado,
## la manzana es una masa media con dos o tres picos, que es lo que la hace ver orgánica.
##
## El techo de ALTO bajó de 22 a 18: con 22 el salto entre vecinos era tan grande que la silueta leía
## desprolija en vez de orgánica. Las GRIETAS no se tocan —siguen cayendo a 1–4 pisos— porque su gracia es
## justamente el contraste.
const FLOORS = {
	Height.LOW: {"min_floors": 1, "max_floors": 4, "bridge_bias": -1, "skew": 1.0},
	Height.MID: {"min_floors": 7, "max_floors": 11, "bridge_bias": 0, "skew": 1.0},
	Height.TALL: {"min_floors": 11, "max_floors": 18, "bridge_bias": 1, "skew": 2.0},
}

## Qué proporción de los edificios de una manzana NO baja rompe el nivel y se construye bajo. Son las
## GRIETAS: huecos por donde la nave puede cortar camino entre torres si el jugador los ve. Un cluster es
## de 1 a 8 celdas y una celda mide ~27 m, así que hasta la grieta más chica es mucho más ancha que un
## callejón — no rompe la regla de que la nave no entra en callejones. La mayoría sigue siendo alta, así
## que el laberinto se mantiene.
const CRACK_CHANCE := 0.12

## Cada cuántas manzanas aparece un nivel: la norma es el cañón, y el respiro es la excepción corta.
const HEIGHT_WEIGHTS = {
	Height.TALL: 0.55,
	Height.MID: 0.25,
	Height.LOW: 0.20,
}

## Lo del distrito: nada de alturas acá.
const CONFIGS = {
	District.POOR: {
		"block_heart_probability": 0.3,
		"traffic_density": 0.5
	},
	District.RICH: {
		"block_heart_probability": 0.2,
		"traffic_density": 0.6
	},
	District.INDUSTRIAL: {
		"block_heart_probability": 0.2,
		"traffic_density": 0.8
	}
}

# Pesos de spawn ambiental. Los "one-of" (camiones) no figuran: su peso por defecto en el arquetipo es 0,
# así que no estar en la tabla los deja afuera. Los 0.0 explícitos SÍ hacen falta — una entrada ausente cae
# al peso por defecto del arquetipo.
const CAR_WEIGHTS = {
	District.POOR: {
		CarArchetypes.Type.POOR_CAR: 0.45,
		CarArchetypes.Type.MOTORCYCLE: 0.25,
		CarArchetypes.Type.TAXI: 0.15,
		CarArchetypes.Type.RICH_CAR: 0.02,
		CarArchetypes.Type.POLICE_CAR: 0.0
	},
	District.RICH: {
		CarArchetypes.Type.RICH_CAR: 0.4,
		CarArchetypes.Type.TAXI: 0.25,
		CarArchetypes.Type.POOR_CAR: 0.15,
		CarArchetypes.Type.MOTORCYCLE: 0.1,
		CarArchetypes.Type.POLICE_CAR: 0.1
	},
	District.INDUSTRIAL: {
		CarArchetypes.Type.POOR_CAR: 0.2,
		CarArchetypes.Type.MOTORCYCLE: 0.1,
		CarArchetypes.Type.RICH_CAR: 0.0,
		CarArchetypes.Type.POLICE_CAR: 0.0,
		CarArchetypes.Type.TAXI: 0.0
	}
}


static func get_type_name(district: District) -> String:
	match district:
		District.POOR:
			return "Pobre"
		District.RICH:
			return "Rico"
		District.INDUSTRIAL:
			return "Industrial"
		_:
			return "Desconocido"


static func get_height_name(height: Height) -> String:
	match height:
		Height.LOW:
			return "Bajo"
		Height.MID:
			return "Medio"
		Height.TALL:
			return "Alto"
		_:
			return "Desconocido"


## Los pisos que le tocan a una manzana de ese nivel.
static func get_floor_range(height: Height) -> Vector2i:
	var row: Dictionary = FLOORS.get(height, FLOORS[Height.MID])
	return Vector2i(row["min_floors"], row["max_floors"])


## Cuánto se sesga el sorteo de pisos dentro de la franja de ese nivel.
static func get_floors_skew(height: Height) -> float:
	var row: Dictionary = FLOORS.get(height, FLOORS[Height.MID])
	return row["skew"]


## Los pisos de UN edificio. El sorteo vive acá y no en BuildingCluster para que el sesgo sea una propiedad
## del NIVEL —declarada en `FLOORS`— y no una decisión escondida en el constructor de cada cluster.
static func draw_floor_count(min_floors: int, max_floors: int, skew: float, rng: RandomNumberGenerator) -> int:
	if max_floors <= min_floors:
		return min_floors
	var t: float = pow(rng.randf(), skew)
	return min_floors + int(round(t * float(max_floors - min_floors)))


static func get_bridge_bias(height: Height) -> int:
	var row: Dictionary = FLOORS.get(height, FLOORS[Height.MID])
	return row["bridge_bias"]


## Sortea un nivel de altura con los pesos de `HEIGHT_WEIGHTS`.
static func draw_height(rng: RandomNumberGenerator) -> Height:
	var total := 0.0
	for weight: float in HEIGHT_WEIGHTS.values():
		total += weight
	var pick := rng.randf() * total
	for height: Height in HEIGHT_WEIGHTS:
		pick -= HEIGHT_WEIGHTS[height]
		if pick <= 0.0:
			return height
	return Height.TALL


static func get_hierarchy(district: District) -> float:
	return CONFIGS[district]["traffic_density"]


static func get_car_weights(district: District) -> Dictionary:
	return CAR_WEIGHTS.get(district, {})


## De dos distritos vecinos, el de más tráfico: es el que manda en la calle que comparten.
static func get_higher_hierarchy_type(district_a: District, district_b: District) -> District:
	return district_a if get_hierarchy(district_a) >= get_hierarchy(district_b) else district_b


## EL COLOR DEBUG DE UN DISTRITO: tono fijo por distrito, saturado a propósito para distinguir barrios de un
## vistazo —lavado en pastel se probó y se volvían indistinguibles—, y el seed varía saturación y valor para
## que dos edificios pegados no se fundan. Solo lo usa la malla debug de los edificios (ver BuildingShell):
## el color que el juego muestra es el del arquetipo (BuildingArchetype.get_color).
const DEBUG_HUE := {
	District.POOR: 0.05,
	District.RICH: 0.28,
	District.INDUSTRIAL: 0.55,
}


static func debug_color(district: District, color_seed: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = color_seed
	# El valor va un escalón por debajo de lo obvio: con la niebla clara de fondo, los tonos claros se le
	# confundían encima.
	return Color.from_hsv(DEBUG_HUE.get(district, 0.0), rng.randf_range(0.5, 0.8), rng.randf_range(0.45, 0.75), 1.0)
