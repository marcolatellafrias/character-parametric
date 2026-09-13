class_name RoofPlanner
extends RefCounted

## EL PLAN DE UN TECHO: un CAMPO DE ALTURAS sobre la huella del edificio.
##
## Es una función pura de datos —la huella del cluster, el tipo de cada borde, sus chaflanes y el seed— que
## no toca geometría. La geometría la ejecuta `RoofProps`; acá vive quién decide.
##
## ⚠ POR QUÉ UN CAMPO Y NO UNA PIEZA POR CELDA. La primera versión elegía una pieza para cada celda mirando
## su vecindad, y producía TECHOS ROTOS: en una tira de 1×5 las celdas del medio daban un dos aguas, con su
## punto alto en el medio del borde, y las de las puntas una esquina a cuatro aguas, con el punto alto en un
## vértice. Dos piezas vecinas no compartían el perfil del borde que comparten, así que no había forma de que
## empalmaran. Una celda NO PUEDE decidir sola.
##
## Con un campo, la altura se define en los VÉRTICES de una retícula de MEDIA CELDA, y cada celda solo dibuja
## los parches que le tocan. Dos celdas vecinas comparten vértices, así que la continuidad no es algo que
## haya que lograr: es imposible que falle. Y la media celda es lo que permite que una cumbrera caiga en el
## medio de una celda, que con vértices de celda entera no se podría representar.
##
## Los tres estilos son tres formas de medir una distancia sobre esa retícula:
##   · UN AGUA   — rampa lineal de un borde de la huella al opuesto.
##   · DOS AGUAS — carpa: la cumbrera en el centro de la HUELLA (no de cada celda), faldones a los lados y
##                 frontón vertical en las puntas.
##   · FRANCÉS   — mansarda: `min(distancia al borde, tope)`. Sube en el primer anillo y se aplana arriba,
##                 que es el techo francés de faldón empinado y azotea plana. Sobre una celda sola sale
##                 piramidal a cuatro aguas. Es el único que dobla bien en una L, porque la distancia no
##                 sabe de ejes.
##
## ⚠ DETERMINISMO: todo sale del seed del cluster y de datos de grilla, nunca del orden de iteración ni de
## nada del render. El tráfico asume que todos los peers generan geometría idéntica.

## El estilo del techo del edificio entero.
enum Style { FLAT, SHED, GABLE, FRENCH }

## Qué hay del otro lado de un borde, EN ORDEN DE PREFERENCIA para tirarle el agua. El orden del enum es la
## prioridad: gana el borde de mayor valor.
enum Exposure {
	INNER,              ## Otra celda del mismo edificio: nunca se drena para adentro.
	NEIGHBOUR_BLOCKED,  ## Edificio pegado igual de alto o más alto: el agua daría contra su pared.
	NEIGHBOUR_LOWER,    ## Edificio pegado más bajo: se puede drenar encima.
	ALLEY,              ## Callejón.
	STREET,             ## Calle. Siempre gana.
}

## La clase de huella. Los clusters son poliominós de 1 a 8 celdas crecidos por frontera al azar (ver
## `BlockGenerator._grow_cluster`), así que las formas irregulares son la mayoría, no la excepción.
enum Footprint { SINGLE, SQUARE2, STRIP, RECT, ELL, IRREGULAR }

## Las cuatro direcciones de un borde de celda: 0 = -z, 1 = +x, 2 = +z, 3 = -x. Es el orden de
## `BuildingModule.edge_types`.
const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

## Qué estilos admite cada huella. El PLANO está en casi todas a propósito: da variedad al conjunto y es el
## único techo donde se apoya un tanque, así que es una opción sorteada y no un caso de descarte.
##
## El dos aguas pide huella RECTANGULAR, porque su carpa se mide sobre el ancho de la huella y en una forma
## escalonada ese ancho cambia de una fila a la otra. En la L, el francés es el que dobla sin costuras.
const OPTIONS := {
	Footprint.SINGLE: [Style.SHED, Style.GABLE, Style.FRENCH],
	Footprint.SQUARE2: [Style.GABLE, Style.FRENCH],
	Footprint.STRIP: [Style.GABLE, Style.SHED, Style.FRENCH],
	Footprint.RECT: [Style.GABLE, Style.FRENCH],
	Footprint.ELL: [Style.FRENCH],
	Footprint.IRREGULAR: [],
}


## Nombres para el picker de debug (ver RoofPicker). En el mismo orden que sus enums.
const STYLE_NAMES: Array[String] = ["plano", "un agua", "dos aguas", "frances"]
const FOOTPRINT_NAMES: Array[String] = ["1x1", "2x2", "tira", "rectangulo", "L", "irregular"]
const DIR_NAMES: Array[String] = ["norte (-z)", "este (+x)", "sur (+z)", "oeste (-x)"]


## QUÉ LE TOCÓ A ESTE EDIFICIO, en texto. Para el picker de debug, que necesita poder nombrar lo que ve sin
## meter mano en los internos de acá.
##
## Repite la misma decisión que `plan` —mismo seed, mismo orden de sorteo—, así que el estilo que informa es
## exactamente el que se dibujó.
static func describe(block: BlockGenerator, cluster: BuildingCluster, flat_chance: float,
		pitch: float) -> Dictionary:
	var cells: Array[Vector2i] = cluster.cells
	if cells.is_empty():
		return {}

	var rng := RandomNumberGenerator.new()
	rng.seed = block.cluster_seed + cluster.id * 7919

	var chamfer := _chamfer_kind(block, cluster)
	var style := _pick_style(cells, chamfer, rng, flat_chance)
	var footprint := classify(cells)
	var drain := _best_drain(block, cluster)

	var chamfer_name := "ninguno"
	if chamfer == BuildingModule.ChamferKind.STREET:
		chamfer_name = "de CALLE (esquina de manzana)"
	elif chamfer == BuildingModule.ChamferKind.ALLEY:
		chamfer_name = "de callejon"

	return {
		"style": style,
		"style_name": STYLE_NAMES[style],
		"footprint": footprint,
		"footprint_name": FOOTPRINT_NAMES[footprint],
		"chamfer": chamfer,
		"chamfer_name": chamfer_name,
		"drain": drain,
		"drain_name": DIR_NAMES[drain],
		"pitch": pitch,
	}


## EL PLAN: `{"style": Style, "heights": {Vector2i vértice de media celda: float metros}}`.
##
## Los vértices van en coordenadas ABSOLUTAS de media celda sobre la grilla del bloque: el vértice `(i, j)`
## corresponde a la celda `(i / 2, j / 2)`. Un estilo plano devuelve el campo vacío.
static func plan(block: BlockGenerator, cluster: BuildingCluster, flat_chance: float,
		pitch: float) -> Dictionary:
	var cells: Array[Vector2i] = cluster.cells
	if cells.is_empty():
		return {"style": Style.FLAT, "heights": {}}

	var rng := RandomNumberGenerator.new()
	rng.seed = block.cluster_seed + cluster.id * 7919

	var style := _pick_style(cells, _chamfer_kind(block, cluster), rng, flat_chance)
	if style == Style.FLAT:
		return {"style": Style.FLAT, "heights": {}}

	var bounds := _bounds(cells)
	var drain := _best_drain(block, cluster)
	var heights := _build_field(cells, bounds, style, drain, pitch)
	return {"style": style, "heights": heights}


# ── QUÉ TECHO ───────────────────────────────────────────────────────────────────────────────────

static func _bounds(cells: Array[Vector2i]) -> Rect2i:
	var min_x := cells[0].x
	var max_x := cells[0].x
	var min_z := cells[0].y
	var max_z := cells[0].y
	for c: Vector2i in cells:
		min_x = mini(min_x, c.x); max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y); max_z = maxi(max_z, c.y)
	return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)


## En qué clase de huella cae el cluster.
static func classify(cells: Array[Vector2i]) -> Footprint:
	var box := _bounds(cells)
	var is_rect := cells.size() == box.size.x * box.size.y

	if box.size.x == 1 and box.size.y == 1:
		return Footprint.SINGLE
	if is_rect:
		if box.size.x == 2 and box.size.y == 2:
			return Footprint.SQUARE2
		if box.size.x == 1 or box.size.y == 1:
			return Footprint.STRIP
		return Footprint.RECT
	if _is_ell(cells, box):
		return Footprint.ELL
	return Footprint.IRREGULAR


## Una L es un rectángulo al que le falta un bloque RECTANGULAR pegado a una de sus esquinas. Cubre también
## el rectángulo con una muesca en la esquina, que visualmente es lo mismo.
static func _is_ell(cells: Array[Vector2i], box: Rect2i) -> bool:
	if cells.size() < 3:
		return false
	var present := {}
	for c: Vector2i in cells:
		present[c] = true

	var missing: Array[Vector2i] = []
	for dz in range(box.size.y):
		for dx in range(box.size.x):
			var c := Vector2i(box.position.x + dx, box.position.y + dz)
			if not present.has(c):
				missing.append(c)
	if missing.is_empty():
		return false

	var hole := _bounds(missing)
	# El hueco tiene que ser un rectángulo LLENO...
	if missing.size() != hole.size.x * hole.size.y:
		return false
	# ...y tocar una esquina del bounding box.
	var touches_x := hole.position.x == box.position.x \
			or hole.position.x + hole.size.x == box.position.x + box.size.x
	var touches_z := hole.position.y == box.position.y \
			or hole.position.y + hole.size.y == box.position.y + box.size.y
	return touches_x and touches_z


## De qué es esquina el chaflán del cluster, si tiene: `ChamferKind.STREET`, `ChamferKind.ALLEY`, o -1.
##
## Si hay de los dos tipos GANA EL DE CALLE: la esquina noble manda sobre la forma rara de fondo.
static func _chamfer_kind(block: BlockGenerator, cluster: BuildingCluster) -> int:
	var found := -1
	for cell: Vector2i in cluster.cells:
		var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
		if module == null:
			continue
		for kind: int in module.get_chamfer_kinds().values():
			if kind == BuildingModule.ChamferKind.STREET:
				return BuildingModule.ChamferKind.STREET
			found = kind
	return found


static func _pick_style(cells: Array[Vector2i], chamfer_kind: int,
		rng: RandomNumberGenerator, flat_chance: float) -> Style:
	# El chaflán decide ANTES que la huella, porque habla de la posición en la manzana y no de la forma.
	if chamfer_kind == BuildingModule.ChamferKind.ALLEY:
		# Chaflán solo contra callejón: forma rara de fondo, va plano.
		return Style.FLAT

	var options: Array = []
	if chamfer_kind == BuildingModule.ChamferKind.STREET:
		# Esquina de manzana ochavada: francés o plano, nada más.
		options = [Style.FRENCH]
	else:
		options = OPTIONS.get(classify(cells), [])

	if options.is_empty() or rng.randf() < flat_chance:
		return Style.FLAT
	return options[rng.randi_range(0, options.size() - 1)]


# ── HACIA DÓNDE ESCURRE ─────────────────────────────────────────────────────────────────────────

## La dirección por la que conviene que baje un techo de UN AGUA: la más expuesta de todo el edificio.
##
## El tipo de borde ya está resuelto en `BuildingModule.edge_types`, que lo saca del PathGenerator: FACADE y
## BOUNDARY son calle, SMALL/BIG (y sus ORIGIN) son callejón, y NORMAL significa que no hay separación, o sea
## que del otro lado hay edificio pegado. Ahí se mira de quién es esa celda para distinguir la propia huella
## de un vecino, y la ALTURA del vecino para saber si se le puede tirar el agua encima.
static func _best_drain(block: BlockGenerator, cluster: BuildingCluster) -> int:
	var own := {}
	for c: Vector2i in cluster.cells:
		own[c] = true

	var best_dir := 0
	var best_score := -1
	for cell: Vector2i in cluster.cells:
		var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
		if module == null:
			continue
		for dir in 4:
			var score := _exposure(block, cluster, own, module, cell, dir)
			if score > best_score:
				best_score = score
				best_dir = dir
	return best_dir


static func _exposure(block: BlockGenerator, cluster: BuildingCluster, own: Dictionary,
		module: BuildingModule, cell: Vector2i, dir: int) -> int:
	var edge_type: int = module.edge_types[dir]
	if edge_type == DistortedGrid.CellType.FACADE or edge_type == DistortedGrid.CellType.BOUNDARY:
		return Exposure.STREET
	if edge_type != DistortedGrid.CellType.NORMAL:
		return Exposure.ALLEY
	# Borde sin separación: hay algo pegado del otro lado.
	var other: Vector2i = cell + DIR_OFFSETS[dir]
	if own.has(other):
		return Exposure.INNER
	var neighbour: BuildingCluster = block.get_cluster_for_cell(other.x, other.y)
	if neighbour == null:
		return Exposure.ALLEY
	if neighbour.get_floor_count() < cluster.get_floor_count():
		return Exposure.NEIGHBOUR_LOWER
	return Exposure.NEIGHBOUR_BLOCKED


# ── EL CAMPO DE ALTURAS ─────────────────────────────────────────────────────────────────────────

## Una sub-celda pertenece a la huella si su celda pertenece. Las sub-celdas van en unidades de media celda.
static func _sub_cell_inside(si: int, sj: int, own: Dictionary) -> bool:
	return own.has(Vector2i(si >> 1, sj >> 1))


## Los vértices de la retícula de media celda que toca la huella, y cuáles están en su BORDE.
##
## El vértice `(i, j)` toca las cuatro sub-celdas `(i-1,j-1)`, `(i,j-1)`, `(i-1,j)`, `(i,j)`. Pertenece si
## alguna está dentro, y es de borde si alguna está afuera — que es justo donde el techo tiene que bajar a 0.
static func _collect_vertices(own: Dictionary, box: Rect2i) -> Dictionary:
	var verts := {}
	for j in range(box.position.y * 2, (box.position.y + box.size.y) * 2 + 1):
		for i in range(box.position.x * 2, (box.position.x + box.size.x) * 2 + 1):
			var inside := false
			var outside := false
			for dj in [-1, 0]:
				for di in [-1, 0]:
					if _sub_cell_inside(i + di, j + dj, own):
						inside = true
					else:
						outside = true
			if inside:
				verts[Vector2i(i, j)] = outside
	return verts


static func _build_field(cells: Array[Vector2i], box: Rect2i, style: Style, drain: int,
		pitch: float) -> Dictionary:
	var own := {}
	for c: Vector2i in cells:
		own[c] = true
	var verts := _collect_vertices(own, box)

	match style:
		Style.SHED:
			return _field_shed(verts, box, drain, pitch)
		Style.GABLE:
			return _field_gable(verts, box, pitch)
		_:
			return _field_french(verts, pitch)


## UN AGUA: rampa lineal desde el borde `drain` de la huella hasta el opuesto. Al ser función de una sola
## coordenada, es continua en toda la huella por construcción.
static func _field_shed(verts: Dictionary, box: Rect2i, drain: int, pitch: float) -> Dictionary:
	var along_x := drain == 1 or drain == 3
	var lo := (box.position.x if along_x else box.position.y) * 2
	var hi := lo + (box.size.x if along_x else box.size.y) * 2
	var span := maxi(hi - lo, 1)

	var field := {}
	for v: Vector2i in verts:
		var c: int = v.x if along_x else v.y
		var t := float(c - lo) / float(span)
		# El agua baja hacia `drain`, así que ese borde es el 0.
		if drain == 1 or drain == 2:
			t = 1.0 - t
		field[v] = t * pitch
	return field


## DOS AGUAS: una carpa cuya cumbrera cae en el CENTRO DE LA HUELLA —no de cada celda— y corre a lo largo de
## su lado más largo. En las puntas la altura no baja, y ahí `RoofProps` cierra el frontón vertical.
static func _field_gable(verts: Dictionary, box: Rect2i, pitch: float) -> Dictionary:
	var ridge_along_x := box.size.x >= box.size.y
	var lo := (box.position.y if ridge_along_x else box.position.x) * 2
	var hi := lo + (box.size.y if ridge_along_x else box.size.x) * 2
	var centre := (float(lo) + float(hi)) * 0.5
	var half := maxf((float(hi) - float(lo)) * 0.5, 1.0)

	var field := {}
	for v: Vector2i in verts:
		var c: int = v.y if ridge_along_x else v.x
		field[v] = (1.0 - absf(float(c) - centre) / half) * pitch
	return field


## FRANCÉS (mansarda): `min(distancia al borde, tope)`. Sube en el primer anillo y se aplana arriba, que es
## el faldón empinado con azotea plana de la arquitectura francesa. Sobre una celda sola no hay anillo
## interior más que el centro, así que sale una pirámide a cuatro aguas.
##
## La distancia se mide con un BFS multi-fuente desde los vértices del borde, o sea sin saber de ejes: por
## eso es el único estilo que dobla bien en una L o en cualquier forma rara.
static func _field_french(verts: Dictionary, pitch: float) -> Dictionary:
	var dist := {}
	var queue: Array[Vector2i] = []
	for v: Vector2i in verts:
		if verts[v]:
			dist[v] = 0
			queue.append(v)

	var head := 0
	while head < queue.size():
		var v: Vector2i = queue[head]
		head += 1
		var d: int = dist[v]
		for off: Vector2i in DIR_OFFSETS:
			var n: Vector2i = v + off
			if not verts.has(n) or dist.has(n):
				continue
			dist[n] = d + 1
			queue.append(n)

	var field := {}
	for v: Vector2i in verts:
		var d: int = dist.get(v, 1)
		# El faldón gana toda su altura en el primer anillo (media celda) y de ahí es azotea plana.
		field[v] = pitch if d >= 1 else 0.0
	return field
