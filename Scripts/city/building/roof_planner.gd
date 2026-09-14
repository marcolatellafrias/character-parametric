class_name RoofPlanner
extends RefCounted

## EL PLAN DE UN TECHO: qué estilo lleva el edificio y qué PIEZAS del catálogo van en qué regiones.
##
## Es una función pura de datos —la huella del cluster, sus bordes, sus chaflanes y el seed— que no toca
## mallas. Devuelve una lista de piezas, cada una con su módulo, su región en celdas y su `UnitMesh`, y
## `City` las coloca una por una con `ModulePlacer.place`. Acá vive quién decide; las piezas viven en
## `RoofProps`; deformar, anotar y ocupar lo hace el placer.
##
## ── MODULAR, EN CELDAS ENTERAS ──
## Todo se razona sobre la GRILLA DE EDIFICIO del bloque, en coordenadas globales: la celda `(cx, cz)` del
## módulo aporta sus 80 celdas a partir de `cx * 80`. Los núcleos de dos celdas vecinas del mismo edificio
## se tocan exactos —retiro 0 en el borde compartido—, así que la huella es una unión de rectángulos enteros
## y su contorno cae siempre en líneas de celda. Sobre ese contorno se pone el catálogo:
##   · un FALDÓN por cada tramo recto,
##   · una ESQUINA en cada vértice convexo, un RINCÓN en cada vértice cóncavo, un CHAFLÁN en cada ochava,
##   · TAPAS rellenando lo que queda adentro.
## Las piezas se cortan donde cambia la exposición, no en cuadrantes fijos: la franja donde un vecino no
## llega (retiros distintos en el mismo lado) es un tramo de faldón más un rincón, y sale del mismo
## recorrido. Y cada pieza vive en UN módulo: un faldón que cruza tres módulos son tres faldones.
##
## ⚠ SUPERSEDED — dos versiones anteriores. Una pieza por celda elegida por vecindad daba techos rotos, porque
## dos piezas vecinas no coincidían en el perfil del borde que comparten. Un campo de alturas en media celda
## los cerraba, pero inventaba una resolución que la grilla no tiene: el faldón medía media celda por
## construcción y un edificio de una celda de ancho no tenía lugar para la tapa (651 de 929 franceses salían
## como dos aguas). Y un contorno procedural cortado por celdas daba las formas bien pero con muchas líneas
## de más, y no era la interfaz modular que el resto de los objetos va a usar.
##
## ⚠ DETERMINISMO: todo sale del seed del cluster y de datos de grilla, nunca del orden de iteración ni de
## nada del render. El tráfico asume que todos los peers generan geometría idéntica.

## El estilo del techo del edificio entero.
enum Style { FLAT, SHED, GABLE, FRENCH }

## Qué pieza del catálogo es. Es lo que el inspector nombra al apuntarle.
enum Piece { TOP, SKIRT, CORNER, INNER_CORNER, CHAMFER, SLOPE, TANK }

## Qué hay del otro lado de un borde, EN ORDEN DE PREFERENCIA para tirarle el agua. El orden del enum es la
## prioridad: gana el borde de mayor valor.
enum Exposure {
	INNER,              ## Otra celda del mismo edificio: nunca se drena para adentro.
	NEIGHBOUR_BLOCKED,  ## Edificio pegado igual de alto o más alto: el agua daría contra su pared.
	NEIGHBOUR_LOWER,    ## Edificio pegado más bajo: se puede drenar encima.
	ALLEY,              ## Callejón.
	STREET,             ## Calle. Siempre gana.
}

## La clase de huella, contando celdas de grilla distorsionada.
enum Footprint { SINGLE, SQUARE2, STRIP, RECT, ELL, IRREGULAR }

## Las cuatro direcciones de un borde: 0 = -z, 1 = +x, 2 = +z, 3 = -x. Es el orden de
## `BuildingModule.edge_types` y el que esperan las piezas de `RoofProps`.
const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

## Qué estilos admite cada huella. El PLANO está en todas a propósito: da variedad al conjunto y es el único
## techo donde se apoya un tanque, así que es una opción sorteada y no un caso de descarte.
##
## Un 1×1 NO lleva francés: una pirámide truncada sobre un solo módulo queda rara.
const OPTIONS := {
	Footprint.SINGLE: [Style.SHED, Style.GABLE],
	Footprint.SQUARE2: [Style.GABLE, Style.FRENCH],
	Footprint.STRIP: [Style.GABLE, Style.SHED, Style.FRENCH],
	Footprint.RECT: [Style.GABLE, Style.FRENCH],
	Footprint.ELL: [Style.FRENCH],
	Footprint.IRREGULAR: [],
}

const STYLE_NAMES: Array[String] = ["plano", "un agua", "dos aguas", "frances"]
const PIECE_NAMES: Array[String] = ["tapa", "faldon", "esquina", "rincon", "chaflan", "agua", "tanque de agua"]


static func style_name(style: int) -> String:
	return STYLE_NAMES[style] if style >= 0 and style < STYLE_NAMES.size() else "?"


static func piece_name(piece: int) -> String:
	return PIECE_NAMES[piece] if piece >= 0 and piece < PIECE_NAMES.size() else "?"


## EL PLAN: `{"style", "pieces", "fallback"}`.
##
## Cada pieza es `{"cell", "lo", "size", "mesh", "piece", "side"}`: la celda de grilla distorsionada cuyo
## módulo la coloca, la región LOCAL a ese módulo (`lo` y `size` en celdas, `y` = índice de altura), la
## `UnitMesh`, qué pieza del catálogo es y qué lado del contorno (o -1). Todas las regiones están validadas:
## no se superponen y ninguna cruza un módulo. Si el mosaico no cierra, `pieces` va vacío y `fallback` dice
## por qué; `City` cuenta esos casos.
static func layout(block: BlockGenerator, cluster: BuildingCluster, flat_chance: float,
		pitch_cells: int, skirt_cells: int, roof_index: int) -> Dictionary:
	var out := {"style": Style.FLAT, "pieces": [], "fallback": ""}
	if cluster.cells.is_empty() or pitch_cells <= 0:
		return out
	var rects := _core_rects(block, cluster)
	if rects.is_empty():
		return out
	var style := _pick_style(block, cluster, rects, flat_chance)
	if style == Style.FLAT:
		return out

	var regions: Array = []
	var fallback := ""
	match style:
		Style.FRENCH:
			fallback = _french(block, cluster, rects, skirt_cells, regions)
		Style.GABLE:
			fallback = _gable(block, cluster, rects, false, regions)
		Style.SHED:
			fallback = _gable(block, cluster, rects, true, regions)

	if fallback.is_empty():
		fallback = _validate(regions, block)
	if not fallback.is_empty():
		out["fallback"] = fallback
		return out

	var columns := _columns(block, cluster)
	var pieces: Array = []
	for r: Dictionary in regions:
		var rect: Rect2i = r["rect"]
		var cell := Vector2i(rect.position.x / columns, rect.position.y / columns)
		pieces.append({
			"cell": cell,
			"lo": Vector3i(rect.position.x - cell.x * columns, roof_index, rect.position.y - cell.y * columns),
			"size": Vector3i(rect.size.x, pitch_cells, rect.size.y),
			"mesh": r["mesh"],
			"piece": r["piece"],
			"side": r["side"],
		})
	out["style"] = style
	out["pieces"] = pieces
	return out


# ── LA HUELLA EN CELDAS GLOBALES ────────────────────────────────────────────────────────────────

## Celdas de edificio por módulo. Es la misma en `x` y en `z` (80 y 80) y en toda la ciudad.
static func _columns(block: BlockGenerator, cluster: BuildingCluster) -> int:
	var c: Vector2i = cluster.cells[0]
	var module: BuildingModule = block.get_building_module(c.x, c.y, 0)
	return module.columns if module != null else 80


## Los núcleos de las celdas del edificio como rectángulos en celdas GLOBALES del bloque, con su celda y su
## módulo: `[{"rect", "cell", "module"}]`.
static func _core_rects(block: BlockGenerator, cluster: BuildingCluster) -> Array:
	var out: Array = []
	for cell: Vector2i in cluster.cells:
		var module: BuildingModule = block.get_building_module(cell.x, cell.y, 0)
		if module == null:
			continue
		var core := module.get_core_info()
		var w: int = core["width"]
		var d: int = core["depth"]
		if w <= 0 or d <= 0:
			continue
		out.append({
			"rect": Rect2i(cell.x * module.columns + int(core["min_x"]), cell.y * module.rows + int(core["min_z"]), w, d),
			"cell": cell,
			"module": module,
		})
	return out


## Si la unión de los núcleos es UN rectángulo: ocupan exactamente su caja envolvente.
static func _union_is_rect(rects: Array) -> bool:
	var box: Rect2i = rects[0]["rect"]
	var area := 0
	for r: Dictionary in rects:
		var rect: Rect2i = r["rect"]
		box = box.merge(rect)
		area += rect.size.x * rect.size.y
	return area == box.size.x * box.size.y


static func _union_box(rects: Array) -> Rect2i:
	var box: Rect2i = rects[0]["rect"]
	for r: Dictionary in rects:
		box = box.merge(r["rect"])
	return box


static func _inside(rects: Array, cell: Vector2i) -> bool:
	for r: Dictionary in rects:
		var rect: Rect2i = r["rect"]
		if rect.has_point(cell):
			return true
	return false


## Qué cuadrantes alrededor del vértice `v` están dentro de la huella, como máscara de 4 bits:
## bit 0 = (+x, +z), bit 1 = (-x, +z), bit 2 = (-x, -z), bit 3 = (+x, -z).
static func _quadrants(rects: Array, v: Vector2i) -> int:
	var mask := 0
	if _inside(rects, v): mask |= 1
	if _inside(rects, v + Vector2i(-1, 0)): mask |= 2
	if _inside(rects, v + Vector2i(-1, -1)): mask |= 4
	if _inside(rects, v + Vector2i(0, -1)): mask |= 8
	return mask


static func _bit_count(mask: int) -> int:
	return (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1) + ((mask >> 3) & 1)


## En qué cuadrante (0..3, mismo orden que la máscara) hay que poner una pieza de esquina, y con qué giro:
## el giro `k` es el número del cuadrante, porque la pieza canónica tiene el vértice en el origen con el
## interior hacia (+x, +z) —cuadrante 0— y cada cuarto de vuelta la lleva al siguiente.
static func _quadrant_rect(v: Vector2i, quadrant: int, size: Vector2i) -> Rect2i:
	match quadrant:
		0: return Rect2i(v.x, v.y, size.x, size.y)
		1: return Rect2i(v.x - size.x, v.y, size.x, size.y)
		2: return Rect2i(v.x - size.x, v.y - size.y, size.x, size.y)
		_: return Rect2i(v.x, v.y - size.y, size.x, size.y)


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


## En qué clase de huella cae el cluster, contando celdas de grilla distorsionada.
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


## Una L es un rectángulo al que le falta un bloque RECTANGULAR pegado a una de sus esquinas.
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
	if missing.size() != hole.size.x * hole.size.y:
		return false
	var touches_x := hole.position.x == box.position.x \
			or hole.position.x + hole.size.x == box.position.x + box.size.x
	var touches_z := hole.position.y == box.position.y \
			or hole.position.y + hole.size.y == box.position.y + box.size.y
	return touches_x and touches_z


## De qué es esquina el chaflán del cluster, si tiene. Si hay de los dos tipos GANA EL DE CALLE.
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


static func _pick_style(block: BlockGenerator, cluster: BuildingCluster, rects: Array,
		flat_chance: float) -> Style:
	var rng := RandomNumberGenerator.new()
	rng.seed = block.cluster_seed + cluster.id * 7919
	var chamfer := _chamfer_kind(block, cluster)
	# El chaflán decide ANTES que la huella, porque habla de la posición en la manzana y no de la forma.
	if chamfer == BuildingModule.ChamferKind.ALLEY:
		return Style.FLAT
	var footprint := classify(cluster.cells)
	var options: Array = []
	if chamfer == BuildingModule.ChamferKind.STREET:
		options = [] if footprint == Footprint.SINGLE else [Style.FRENCH]
	else:
		options = OPTIONS.get(footprint, []).duplicate()
		# Dos aguas y un agua piden que la UNIÓN DE NÚCLEOS sea un rectángulo, no solo la huella en celdas:
		# con retiros distintos en un mismo lado el contorno queda escalonado.
		if rects.is_empty() or not _union_is_rect(rects):
			options.erase(Style.SHED)
			options.erase(Style.GABLE)
	if options.is_empty() or rng.randf() < flat_chance:
		return Style.FLAT
	return options[rng.randi_range(0, options.size() - 1)]


# ── FRANCÉS ─────────────────────────────────────────────────────────────────────────────────────

## Devuelve "" y llena `regions`, o el motivo por el que no se pudo.
static func _french(block: BlockGenerator, cluster: BuildingCluster, rects: Array, s: int,
		regions: Array) -> String:
	var color := RoofProps.color_for_style(Style.FRENCH)
	var consumed: Array[Rect2i] = []

	# 1. LOS CHAFLANES, primero, porque deciden qué vértices vecinos NO llevan pieza propia.
	#
	# Un chaflán de CALLE está en la ochava de la esquina de manzana: sus dos flancos dan al exterior. Un
	# chaflán de CALLEJÓN está en el fondo de un callejón, en la esquina de una celda cuyos dos vecinos están
	# pegados pero retirados del callejón (retiro 18 = el corte): el corte va justo de un escalón al otro, y
	# a cada lado del chaflán hay un rincón, no un faldón. La misma pieza cubre los dos casos, con cada
	# flanco en modo faldón o rincón según si la celda de al lado es propia (ver RoofProps.chamfer_unit).
	# Cuando un flanco es rincón, la pieza YA contiene ese rincón, así que el vértice cóncavo del escalón se
	# tacha para que no reciba su pieza aparte.
	var chamfered := {}   # vértice -> {"rect_i", "corner"}
	for i in rects.size():
		var r: Dictionary = rects[i]
		var rect: Rect2i = r["rect"]
		var module: BuildingModule = r["module"]
		for corner in 4:
			if module.get_chamfers().has(corner):
				chamfered[_rect_corner(rect, corner)] = {"rect_i": i, "corner": corner}

	var chamfer_rects: Array[Rect2i] = []
	var suppressed := {}
	var side_no := 0
	for v: Vector2i in chamfered:
		var mask := _quadrants(rects, v)
		if _bit_count(mask) != 1:
			return "chaflan en un vertice que no es convexo"
		var ch: Dictionary = chamfered[v]
		var module: BuildingModule = rects[ch["rect_i"]]["module"]
		var piece := _chamfer_piece(rects, v, _mask_to_quadrant(mask), module, ch["corner"], s, color)
		piece["side"] = side_no
		side_no += 1
		regions.append(piece)
		consumed.append(piece["rect"])
		chamfer_rects.append(piece["rect"])
		for sv: Vector2i in piece["suppress"]:
			suppressed[sv] = true

	# 2. LOS DEMÁS VÉRTICES: cada esquina de cada rectángulo, una sola vez, clasificada por sus cuadrantes.
	var vertices := {}
	for r: Dictionary in rects:
		var rect: Rect2i = r["rect"]
		for corner in 4:
			vertices[_rect_corner(rect, corner)] = true

	for v: Vector2i in vertices:
		if chamfered.has(v) or suppressed.has(v):
			continue
		var mask := _quadrants(rects, v)
		var count := _bit_count(mask)
		if count == 4 or count == 0:
			continue
		if count == 2:
			if mask == 5 or mask == 10:
				return "esquinas enfrentadas"
			continue  # recto
		if count == 1:
			var q := _mask_to_quadrant(mask)
			var rect := _quadrant_rect(v, q, Vector2i(s, s))
			regions.append({"rect": rect, "mesh": RoofProps.corner_unit(q, color),
				"piece": Piece.CORNER, "side": side_no})
			consumed.append(rect)
			side_no += 1
		else:  # count == 3: cóncavo; el rincón va en el cuadrante OPUESTO al exterior
			var exterior := _mask_to_quadrant(15 - mask)
			var q := (exterior + 2) % 4
			var rect := _quadrant_rect(v, q, Vector2i(s, s))
			regions.append({"rect": rect, "mesh": RoofProps.inner_corner_unit(q, color),
				"piece": Piece.INNER_CORNER, "side": side_no})
			consumed.append(rect)
			side_no += 1

	# 3. LOS TRAMOS: cada borde de rectángulo que da al exterior, recortado en las puntas por la pieza de
	#    esquina de cada vértice convexo, y menos lo que ya cubre una pieza de chaflán —que puede comerse un
	#    tramo entero: las dos patas de un chaflán de callejón viven dentro de su pieza—.
	for i in rects.size():
		var r: Dictionary = rects[i]
		var rect: Rect2i = r["rect"]
		for dir in 4:
			for seg: Vector2i in _exterior_intervals(rects, i, dir):
				var a := seg.x
				var b := seg.y
				var along_x := dir == 0 or dir == 2
				var line := rect.position.y if dir == 0 else (rect.end.y if dir == 2 else (rect.end.x if dir == 1 else rect.position.x))
				var va := Vector2i(a, line) if along_x else Vector2i(line, a)
				var vb := Vector2i(b, line) if along_x else Vector2i(line, b)
				a += _shorten(rects, chamfered, va, s)
				b -= _shorten(rects, chamfered, vb, s)
				if b < a:
					return "tramo mas corto que sus esquinas"
				if b == a:
					continue
				var strip: Rect2i
				match dir:
					0: strip = Rect2i(a, rect.position.y, b - a, s)
					2: strip = Rect2i(a, rect.end.y - s, b - a, s)
					1: strip = Rect2i(rect.end.x - s, a, s, b - a)
					_: strip = Rect2i(rect.position.x, a, s, b - a)
				var strips: Array[Rect2i] = [strip]
				for cut: Rect2i in chamfer_rects:
					strips = _subtract_all(strips, cut)
				for part: Rect2i in strips:
					regions.append({"rect": part, "mesh": RoofProps.skirt_unit(dir, color),
						"piece": Piece.SKIRT, "side": side_no})
					consumed.append(part)
				side_no += 1

	# 3. LAS TAPAS: lo que queda de cada núcleo después de sacarle sus piezas.
	for r: Dictionary in rects:
		var remaining: Array[Rect2i] = [r["rect"]]
		for cut: Rect2i in consumed:
			remaining = _subtract_all(remaining, cut)
		for top: Rect2i in remaining:
			regions.append({"rect": top, "mesh": RoofProps.top_unit(color), "piece": Piece.TOP, "side": -1})
	return ""


static func _rect_corner(rect: Rect2i, corner: int) -> Vector2i:
	match corner:
		0: return rect.position
		1: return Vector2i(rect.end.x, rect.position.y)
		2: return rect.end
		_: return Vector2i(rect.position.x, rect.end.y)


static func _mask_to_quadrant(mask: int) -> int:
	if mask & 1: return 0
	if mask & 2: return 1
	if mask & 4: return 2
	return 3


## El corte del chaflán de la esquina `corner` de un módulo, como `(a lo largo de x, a lo largo de z)`.
## `BuildingModule` guarda `[c1, c2]` con `c1` hacia la esquina anterior y `c2` hacia la siguiente, y qué
## eje es cada una alterna con la esquina.
static func _chamfer_cut(module: BuildingModule, corner: int) -> Vector2i:
	var ch: Array = module.get_chamfers()[corner]
	var c1 := int(ch[0])
	var c2 := int(ch[1])
	return Vector2i(c2, c1) if corner % 2 == 0 else Vector2i(c1, c2)


## LA PIEZA DE CHAFLÁN en el vértice convexo `v`, cuadrante `q`. Devuelve `{"rect", "mesh", "piece",
## "suppress"}`: la región, la mesh, y los vértices cóncavos de los escalones que la pieza ya cubre.
##
## La región mide `corte + s` en cada eje: es hasta donde llega el faldón del vecino cuando el flanco es un
## rincón, y como corte y `s` son enteros cae en celdas enteras sin redondear. Los puntos se calculan en
## CELDAS, en el marco canónico de la pieza (vértice en el origen, interior hacia +x, +z) y se pasan como
## fracción de la región. Un cuarto de vuelta lleva el eje x de la pieza al eje z del mundo, así que con
## giro impar el corte "a lo largo de x" es el corte a lo largo de z del mundo.
static func _chamfer_piece(rects: Array, v: Vector2i, q: int, module: BuildingModule, corner: int, s: int,
		color: Color) -> Dictionary:
	var cut_world := _chamfer_cut(module, corner)
	var cut := cut_world if q % 2 == 0 else Vector2i(cut_world.y, cut_world.x)
	var lx := cut.x + s
	var lz := cut.y + s
	var region_world := Vector2i(lx, lz) if q % 2 == 0 else Vector2i(lz, lx)
	var rect := _quadrant_rect(v, q, region_world)

	# Cada flanco: ¿la celda pegada al flanco, más allá del corte, es propia? Entonces es un rincón.
	var valley_a := _inside(rects, v + _rot_cell(Vector2(-0.5, float(cut.y) + 0.5), q))
	var valley_b := _inside(rects, v + _rot_cell(Vector2(float(cut.x) + 0.5, -0.5), q))

	var cx := float(cut.x)
	var cz := float(cut.y)
	var fs := float(s)
	# La línea donde el faldón del corte llega a la tapa: el corte corrido `s` hacia adentro, perpendicular.
	var n := sqrt(1.0 / (cx * cx) + 1.0 / (cz * cz))
	var rim := 1.0 + fs * n
	var p := Vector2(0.0, cz / float(lz))
	var qq := Vector2(cx / float(lx), 0.0)
	var pa := Vector2(cx * (rim - float(lz) / cz) / float(lx), 1.0) if valley_a \
			else Vector2(fs / float(lx), cz * (rim - fs / cx) / float(lz))
	var qb := Vector2(1.0, cz * (rim - float(lx) / cx) / float(lz)) if valley_b \
			else Vector2(cx * (rim - fs / cz) / float(lx), fs / float(lz))
	var mesh := RoofProps.chamfer_unit(q, p, qq, pa, qb, fs / float(lx), fs / float(lz), valley_a, valley_b, color)

	var suppress: Array[Vector2i] = []
	if valley_a:
		suppress.append(v + _rot_point(Vector2i(0, cut.y), q))
	if valley_b:
		suppress.append(v + _rot_point(Vector2i(cut.x, 0), q))
	return {"rect": rect, "mesh": mesh, "piece": Piece.CHAMFER, "suppress": suppress}


## Un punto del retículo girado `k` cuartos de vuelta alrededor del origen, con el mismo sentido que
## `UnitMesh.rotated`: cada cuarto lleva (x, z) a (-z, x).
static func _rot_point(p: Vector2i, k: int) -> Vector2i:
	var out := p
	for _i in posmod(k, 4):
		out = Vector2i(-out.y, out.x)
	return out


## La celda que contiene el punto `centre` (coordenadas de celda, no entero) después de girarlo.
static func _rot_cell(centre: Vector2, k: int) -> Vector2i:
	var out := centre
	for _i in posmod(k, 4):
		out = Vector2(-out.y, out.x)
	return Vector2i(floori(out.x), floori(out.y))


## Cuánto se recorta un tramo en el vértice `v`: `s` en un vértice convexo con pieza de esquina; nada en
## uno recto, cóncavo o con chaflán (al chaflán se le resta su región entera, aparte).
static func _shorten(rects: Array, chamfered: Dictionary, v: Vector2i, s: int) -> int:
	if chamfered.has(v):
		return 0
	return s if _bit_count(_quadrants(rects, v)) == 1 else 0


## Los intervalos del lado `dir` del rectángulo `i` que dan al EXTERIOR de la huella: el lado entero menos lo
## que tapan los otros rectángulos del otro lado de la línea. `(a, b)` a lo largo del eje del lado.
static func _exterior_intervals(rects: Array, i: int, dir: int) -> Array[Vector2i]:
	var rect: Rect2i = rects[i]["rect"]
	var along_x := dir == 0 or dir == 2
	var lo := rect.position.x if along_x else rect.position.y
	var hi := rect.end.x if along_x else rect.end.y
	# La fila (o columna) de celdas justo afuera del lado.
	var outside := rect.position.y - 1 if dir == 0 else (rect.end.y if dir == 2 else (rect.end.x if dir == 1 else rect.position.x - 1))

	var intervals: Array[Vector2i] = [Vector2i(lo, hi)]
	for j in rects.size():
		if j == i:
			continue
		var other: Rect2i = rects[j]["rect"]
		var covers := (other.position.y <= outside and outside < other.end.y) if along_x \
				else (other.position.x <= outside and outside < other.end.x)
		if not covers:
			continue
		var o_lo := other.position.x if along_x else other.position.y
		var o_hi := other.end.x if along_x else other.end.y
		var next: Array[Vector2i] = []
		for seg: Vector2i in intervals:
			if o_hi <= seg.x or o_lo >= seg.y:
				next.append(seg)
				continue
			if seg.x < o_lo:
				next.append(Vector2i(seg.x, o_lo))
			if o_hi < seg.y:
				next.append(Vector2i(o_hi, seg.y))
		intervals = next
	return intervals


## `rects` menos `cut`, como rectángulos.
static func _subtract_all(rects: Array[Rect2i], cut: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for r: Rect2i in rects:
		var inter := r.intersection(cut)
		if inter.size.x <= 0 or inter.size.y <= 0:
			out.append(r)
			continue
		if inter.position.y > r.position.y:
			out.append(Rect2i(r.position.x, r.position.y, r.size.x, inter.position.y - r.position.y))
		if inter.end.y < r.end.y:
			out.append(Rect2i(r.position.x, inter.end.y, r.size.x, r.end.y - inter.end.y))
		if inter.position.x > r.position.x:
			out.append(Rect2i(r.position.x, inter.position.y, inter.position.x - r.position.x, inter.size.y))
		if inter.end.x < r.end.x:
			out.append(Rect2i(inter.end.x, inter.position.y, r.end.x - inter.end.x, inter.size.y))
	return out


# ── DOS AGUAS Y UN AGUA ─────────────────────────────────────────────────────────────────────────

## Sobre la unión rectangular de los núcleos. `shed` = un agua (una sola pendiente, tres paredes); si no,
## dos aguas (dos pendientes que se encuentran en la cumbrera, dos frontones).
static func _gable(block: BlockGenerator, cluster: BuildingCluster, rects: Array, shed: bool,
		regions: Array) -> String:
	if not _union_is_rect(rects):
		return "contorno no rectangular"
	var box := _union_box(rects)
	var columns := _columns(block, cluster)
	var style := Style.SHED if shed else Style.GABLE
	var color := RoofProps.color_for_style(style)

	# El lado LARGO se mide en metros, no en celdas: las celdas no son cuadradas.
	var first: BuildingModule = rects[0]["module"]
	var cell_m := first.cell_metres()
	var ridge_along_x := float(box.size.x) * cell_m.x >= float(box.size.y) * cell_m.y

	# Las pendientes bajan hacia los dos lados largos (dos aguas) o hacia el más expuesto de ellos (un agua).
	var low_dir_a := 0 if ridge_along_x else 3
	var low_dir_b := 2 if ridge_along_x else 1
	var halves: Array = []
	if shed:
		var low := low_dir_a if _side_exposure(block, cluster, rects, low_dir_a) >= _side_exposure(block, cluster, rects, low_dir_b) else low_dir_b
		halves.append({"dir": low, "from": 0, "to": box.size.y if ridge_along_x else box.size.x})
	else:
		# Cada mitad se mide DESDE SU PROPIO lado bajo: las dos arrancan en 0 y juntas suman `depth`. Medir la
		# segunda desde el lado de la primera las hacía pisarse (395 techos planos por superposición).
		var depth := box.size.y if ridge_along_x else box.size.x
		halves.append({"dir": low_dir_a, "from": 0, "to": depth / 2})
		halves.append({"dir": low_dir_b, "from": 0, "to": depth - depth / 2})

	for half: Dictionary in halves:
		var dir: int = half["dir"]
		var from: int = half["from"]
		var to: int = half["to"]
		var depth := to - from
		if depth <= 0:
			return "sin profundidad"
		# `from`/`to` van medidos DESDE EL LADO BAJO hacia adentro; las bandas se cortan además en cada línea
		# de módulo, en los dos ejes, y cada banda es una pieza con sus alturas de arranque y de fin.
		for band: Vector2i in _split_at_modules(from, to, columns, box, dir):
			var h_low := float(band.x - from) / float(depth)
			var h_high := float(band.y - from) / float(depth)
			for run: Vector2i in _split_at_modules_along(box, dir, columns):
				var rect := _band_rect(box, dir, band, run)
				var at_left := run.x == (box.position.x if (dir == 0 or dir == 2) else box.position.y)
				var at_right := run.y == (box.end.x if (dir == 0 or dir == 2) else box.end.y)
				var walls := _canonical_walls(dir, at_left, at_right)
				var wall_high := shed and band.y == to
				var mesh := RoofProps.slope_unit(dir, h_low, h_high, walls.x, walls.y, wall_high, color)
				regions.append({"rect": rect, "mesh": mesh, "piece": Piece.SLOPE, "side": dir})
	return ""


## La profundidad `[from, to)` (medida desde el lado bajo) partida en cada línea de módulo.
static func _split_at_modules(from: int, to: int, columns: int, box: Rect2i, dir: int) -> Array[Vector2i]:
	# La coordenada global del lado bajo, y en qué sentido crece la profundidad.
	var origin := 0
	var sign := 1
	match dir:
		0: origin = box.position.y; sign = 1
		2: origin = box.end.y; sign = -1
		3: origin = box.position.x; sign = 1
		_: origin = box.end.x; sign = -1
	var out: Array[Vector2i] = []
	var d := from
	while d < to:
		var g := origin + sign * d
		# La próxima línea de módulo en el sentido de avance.
		var next_line := ((g / columns) + 1) * columns if sign > 0 else ((g - 1) / columns) * columns
		var next_d := mini(to, absi(next_line - origin))
		if next_d <= d:
			next_d = to
		out.append(Vector2i(d, next_d))
		d = next_d
	return out


## El largo del rectángulo a lo largo del lado bajo, partido en cada línea de módulo: `(a, b)` globales.
static func _split_at_modules_along(box: Rect2i, dir: int, columns: int) -> Array[Vector2i]:
	var along_x := dir == 0 or dir == 2
	var lo := box.position.x if along_x else box.position.y
	var hi := box.end.x if along_x else box.end.y
	var out: Array[Vector2i] = []
	var a := lo
	while a < hi:
		var b := mini(hi, ((a / columns) + 1) * columns)
		out.append(Vector2i(a, b))
		a = b
	return out


## El rectángulo global de una banda `[band.x, band.y)` de profundidad desde el lado `dir`, en el tramo
## `[run.x, run.y)` a lo largo de ese lado.
static func _band_rect(box: Rect2i, dir: int, band: Vector2i, run: Vector2i) -> Rect2i:
	match dir:
		0: return Rect2i(run.x, box.position.y + band.x, run.y - run.x, band.y - band.x)
		2: return Rect2i(run.x, box.end.y - band.y, run.y - run.x, band.y - band.x)
		3: return Rect2i(box.position.x + band.x, run.x, band.y - band.x, run.y - run.x)
		_: return Rect2i(box.end.x - band.y, run.x, band.y - band.x, run.y - run.x)


## Qué paredes lleva una pieza de agua, en términos de la pieza CANÓNICA (exterior en -z: izquierda = -x,
## derecha = +x). Con el giro, "izquierda" cae en un lado distinto del mundo: 0 → -x, 1 → -z, 2 → +x, 3 → +z.
## `at_left`/`at_right` dicen si la pieza toca el principio o el final del rectángulo a lo largo del lado.
static func _canonical_walls(dir: int, at_start: bool, at_end: bool) -> Vector2i:
	# Con giro 0 y 1, el principio del tramo (menor coordenada) es la izquierda canónica; con 2 y 3, la
	# derecha.
	if dir == 0 or dir == 1:
		return Vector2i(1 if at_start else 0, 1 if at_end else 0)
	return Vector2i(1 if at_end else 0, 1 if at_start else 0)


# ── HACIA DÓNDE ESCURRE ─────────────────────────────────────────────────────────────────────────

## Qué tan expuesto está el lado `dir` del edificio: el máximo entre sus celdas de ese lado.
static func _side_exposure(block: BlockGenerator, cluster: BuildingCluster, rects: Array, dir: int) -> int:
	var own := {}
	for c: Vector2i in cluster.cells:
		own[c] = true
	var best := -1
	for r: Dictionary in rects:
		var cell: Vector2i = r["cell"]
		if own.has(cell + DIR_OFFSETS[dir]):
			continue  # ese lado da a otra celda propia
		var module: BuildingModule = r["module"]
		best = maxi(best, _exposure(block, cluster, own, module, cell, dir))
	return best


static func _exposure(block: BlockGenerator, cluster: BuildingCluster, own: Dictionary,
		module: BuildingModule, cell: Vector2i, dir: int) -> int:
	var edge_type: int = module.edge_types[dir]
	if edge_type == DistortedGrid.CellType.FACADE or edge_type == DistortedGrid.CellType.BOUNDARY:
		return Exposure.STREET
	if edge_type != DistortedGrid.CellType.NORMAL:
		return Exposure.ALLEY
	var other: Vector2i = cell + DIR_OFFSETS[dir]
	if own.has(other):
		return Exposure.INNER
	var neighbour: BuildingCluster = block.get_cluster_for_cell(other.x, other.y)
	if neighbour == null:
		return Exposure.ALLEY
	if neighbour.get_floor_count() < cluster.get_floor_count():
		return Exposure.NEIGHBOUR_LOWER
	return Exposure.NEIGHBOUR_BLOCKED


# ── VALIDACIÓN ──────────────────────────────────────────────────────────────────────────────────

## El mosaico cierra si ninguna región se superpone con otra, todas tienen tamaño y ninguna cruza una línea
## de módulo. Si no, mejor un techo plano contado que un agujero.
static func _validate(regions: Array, block: BlockGenerator) -> String:
	var columns := 80
	if not regions.is_empty():
		var any_cell: Vector2i = Vector2i.ZERO
		var m: BuildingModule = block.get_building_module(any_cell.x, any_cell.y, 0)
		if m != null:
			columns = m.columns
	for i in regions.size():
		var a: Rect2i = regions[i]["rect"]
		if a.size.x <= 0 or a.size.y <= 0:
			return "region vacia"
		if a.position.x / columns != (a.end.x - 1) / columns or a.position.y / columns != (a.end.y - 1) / columns:
			return "pieza que cruza un modulo"
		for j in range(i + 1, regions.size()):
			var b: Rect2i = regions[j]["rect"]
			var inter := a.intersection(b)
			if inter.size.x > 0 and inter.size.y > 0:
				return "piezas superpuestas"
	return ""
