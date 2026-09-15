class_name FacadePlanner
extends RefCounted

## DÓNDE VA CADA COSA EN UNA FACHADA — el hermano de RoofPlanner para las paredes.
##
## Separa las tres preguntas de siempre: el ARQUETIPO dice qué criterio usa el edificio y con qué números
## (solo datos); ESTE ARCHIVO tiene las reglas y devuelve regiones candidatas en celdas de la matriz de la
## pared; y `GridPlacer.place` coloca, indexa, ocupa y rechaza lo que choca. Por eso acá no se
## verifica nada contra lo ya colocado: la matriz lo resuelve.
##
## ⚠ INFRAESTRUCTURA PRIMITIVA A PROPÓSITO. Hoy hay dos criterios de ventana para tantear estilo. Las puertas
## —en planta baja y en altura— van a ser otro criterio de este mismo archivo.

## Cómo reparte las ventanas un edificio.
##   STACKED — en columnas fijas por lado, iguales en todos los pisos: quedan apiladas.
##   RANDOM  — posiciones sorteadas piso por piso.
enum Layout { STACKED, RANDOM }

const LAYOUT_NAMES: Array[String] = ["apiladas", "aleatorias"]

## El vecino de cada lado del módulo: 0 norte (z−1), 1 este (x+1), 2 sur (z+1), 3 oeste (x−1).
const NEIGHBOUR: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SIDES: Array[String] = ["north", "east", "south", "west"]

## Espesor de una ventana hacia la calle.
const WINDOW_DEPTH_M := 0.12


static func layout_name(layout: int) -> String:
	return LAYOUT_NAMES[layout] if layout >= 0 and layout < LAYOUT_NAMES.size() else "?"


## SI ESE LADO DEL MÓDULO TIENE PARED A LA VISTA EN ESE PISO: si del otro lado no hay edificio en ese piso.
##
## No alcanza con el tipo de borde. Hacia la calle o un callejón siempre hay pared; contra el límite del
## mundo, nunca. Pero un lado ADOSADO (NORMAL) también queda a la vista si el vecino es otro edificio más
## bajo que este piso —los pisos que asoman por encima—, o un corazón de manzana, que no tiene pisos: las
## paredes que dan a una plaza son fachada. Solo contra una celda del MISMO edificio el lado es interior.
static func has_wall(block: BlockGenerator, cluster: BuildingCluster, cell: Vector2i,
		module: BuildingModule, side: int, floor_idx: int) -> bool:
	var edge_type: int = module.get_edge_type(SIDES[side])
	if edge_type == DistortedGrid.CellType.BOUNDARY:
		return false
	if edge_type != DistortedGrid.CellType.NORMAL:
		return true
	var n := cell + NEIGHBOUR[side]
	var other: BuildingCluster = block.get_cluster_for_cell(n.x, n.y)
	if other == null:
		return true
	if other == cluster:
		return false
	return other.floor_count <= floor_idx


## Cuántas celdas de la matriz ocupa una ventana de ese tipo (a lo largo, hacia afuera, hacia arriba).
static func window_size(window: WindowArchetype, facade: RigidMatrix) -> Vector3i:
	return facade.cells_for(window.width_m, WINDOW_DEPTH_M, window.height_m)


## LAS VENTANAS CANDIDATAS DE UNA FACHADA EN UN PISO, como esquinas `lo` de regiones de `size` celdas.
## Pueden pisarse con lo ya colocado: quien coloca descarta las que no entran.
static func window_positions(archetype: BuildingArchetype, facade: RigidMatrix, size: Vector3i,
		rng: RandomNumberGenerator) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not facade.is_valid() or size.x <= 0 or size.x > facade.count.x or size.z > facade.count.z:
		return out
	match archetype.window_layout:
		Layout.STACKED:
			var sill := roundi(archetype.window_sill_m / facade.cell.z)
			if sill + size.z > facade.count.z:
				return out
			var gap := maxi(1, roundi(archetype.window_gap_m / facade.cell.x))
			for u in _stacked_columns(facade.count.x, size.x, gap):
				out.append(Vector3i(u, 0, sill))
		Layout.RANDOM:
			# EL DESORDEN ES POR PISO, NO POR VENTANA: las columnas son las de STACKED —la misma grilla en
			# todos los pisos— y cada piso deja vacías al azar algunas. Una fachada de villa se lee
			# desordenada sin que ninguna ventana quede corrida respecto de las de arriba; antes cada una
			# caía donde caía, se pisaban y llenaban la pared de geometría.
			var sill := roundi(archetype.window_sill_m / facade.cell.z)
			if sill + size.z > facade.count.z:
				return out
			var gap := maxi(1, roundi(archetype.window_gap_m / facade.cell.x))
			for u in _stacked_columns(facade.count.x, size.x, gap):
				if rng.randf() < archetype.window_fill:
					out.append(Vector3i(u, 0, sill))
	return out


## Las columnas de un lado: tantas ventanas de `width` separadas por `gap` como entren, centradas. Depende
## solo del ancho de la matriz, que es el mismo en todos los pisos —cada piso es el de abajo subido—, así que
## sin guardar nada las ventanas de un lado quedan alineadas de arriba abajo.
static func _stacked_columns(count: int, width: int, gap: int) -> Array[int]:
	var out: Array[int] = []
	var n := (count + gap) / (width + gap)
	if n <= 0:
		return out
	var start := (count - (n * width + (n - 1) * gap)) / 2
	for i in n:
		out.append(start + i * (width + gap))
	return out
