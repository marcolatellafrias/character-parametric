class_name RoofProps
extends RefCounted

## LAS PIEZAS DE TECHO, en el cubo unitario — más el tanque de agua.
##
## Acá NO se decide nada: qué pieza va dónde lo resuelve `RoofPlanner`, y colocarla —deformarla, anotarla,
## ocupar— lo hace `ModulePlacer`. Esto solo sabe cómo es cada pieza dentro de un cubo de 0 a 1.
##
## EL CATÁLOGO ES CHICO A PROPÓSITO. Cada pieza se diseña UNA vez, en una orientación canónica —el exterior
## hacia -z, o el vértice del contorno en el origen— y se rota de a 90° para las otras tres. Y las piezas
## tienen PARÁMETROS numéricos —a qué altura arrancan y terminan, dónde cae el corte de un chaflán— en vez
## de existir en una variante por cada medida: es lo que hace que un faldón que cruza tres módulos se
## coloque como tres piezas que empalman exactas, y que la cumbrera quede a la misma altura sin importar el
## ancho del edificio.
##
## Convención de direcciones, la de `RoofPlanner`: 0 = -z, 1 = +x, 2 = +z, 3 = -x.
##
## Todas las piezas de techo comparten la misma región en altura (`pitch` celdas), así que `y = 1` es la
## misma altura para todas y las tapas, los faldones y las cumbreras coinciden por construcción.

const TANK_COLOR := Color(0.42, 0.33, 0.27)
const TANK_LEG_COLOR := Color(0.30, 0.24, 0.20)
const TANK_CAP_COLOR := Color(0.35, 0.28, 0.23)

## Un color por estilo, para poder distinguirlos de un vistazo mientras esto sea debug. El francés va
## claramente aparte —gris azulado de pizarra, que además es el material real de una mansarda— porque es el
## que hay que poder reconocer a simple vista.
const COLOR_SHED := Color(0.40, 0.30, 0.26)
const COLOR_GABLE := Color(0.46, 0.29, 0.24)
const COLOR_FRENCH := Color(0.30, 0.35, 0.46)
const COLOR_SIDE := Color(0.52, 0.48, 0.45)


static func color_for_style(style: int) -> Color:
	match style:
		RoofPlanner.Style.GABLE:
			return COLOR_GABLE
		RoofPlanner.Style.FRENCH:
			return COLOR_FRENCH
		_:
			return COLOR_SHED


# ── ROTACIÓN ────────────────────────────────────────────────────────────────────────────────────

## La mesh girada `k` cuartos de vuelta alrededor de Y, dentro del cubo. Un cuarto de vuelta lleva el lado
## -z al lado +x, así que una pieza canónica con el exterior en -z (dirección 0) queda con el exterior en
## la dirección `k`.
static func rotated(mesh: UnitMesh, k: int) -> UnitMesh:
	k = posmod(k, 4)
	if k == 0:
		return mesh
	var out := UnitMesh.new()
	for v: Vector3 in mesh.vertices:
		out.vertices.append(_rot_point(v, k))
	out.indices = mesh.indices.duplicate()
	out.colors = mesh.colors.duplicate()
	for f: Vector3 in mesh.facings:
		out.facings.append(_rot_dir(f, k))
	return out


static func _rot_point(p: Vector3, k: int) -> Vector3:
	var x := p.x
	var z := p.z
	for _i in k:
		var nx := 1.0 - z
		var nz := x
		x = nx
		z = nz
	return Vector3(x, p.y, z)


static func _rot_dir(d: Vector3, k: int) -> Vector3:
	var x := d.x
	var z := d.z
	for _i in k:
		var nx := -z
		var nz := x
		x = nx
		z = nz
	return Vector3(x, d.y, z)


# ── FRANCÉS ─────────────────────────────────────────────────────────────────────────────────────

## TAPA: la azotea plana del francés, a la altura del cubo.
static func top_unit(color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	m.add_quad_facing(Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3.UP, color)
	return m


## FALDÓN: sube del exterior (dirección `outward`) hasta la tapa. Canónico: bajo en z = 0, alto en z = 1.
static func skirt_unit(outward: int, color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	m.add_quad_facing(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3.UP, color)
	return rotated(m, outward)


## ESQUINA CONVEXA (lima tesa): el vértice del contorno en el origen y los dos faldones subiendo hasta la
## esquina opuesta. La superficie es `min(x, z)`: dos triángulos que se encuentran en la arista diagonal.
## `k` gira la pieza para que el vértice quede en la esquina de la región que toca el contorno.
static func corner_unit(k: int, color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	m.add_tri_facing(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 1), Vector3.UP, color)
	m.add_tri_facing(Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(0, 0, 1), Vector3.UP, color)
	return rotated(m, k)


## RINCÓN (lima hoya): el vértice cóncavo del contorno en el origen. Los dos faldones que llegan por los
## lados se prolongan hasta cruzarse en la diagonal, y la superficie es `max(x, z)`: a lo largo del borde
## x = 0 sigue el faldón que viene por ahí, a lo largo de z = 0 el otro, y en x = 1 y z = 1 ya está la tapa.
static func inner_corner_unit(k: int, color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	m.add_tri_facing(Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3.UP, color)
	m.add_tri_facing(Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3.UP, color)
	return rotated(m, k)


## CHAFLÁN: la esquina ochavada, convexa o cóncava. El vértice recortado del contorno está en el origen y
## el corte va de `p` (sobre el borde x = 0) a `q` (sobre el borde z = 0). Del corte sube siempre un faldón
## hasta la línea `pa`–`qb`, que ya está a la altura de la tapa. Cada FLANCO —lo que queda del borde x = 0 a
## partir de `p`, y del borde z = 0 a partir de `q`— va en uno de dos modos:
##   · faldón (`valley = false`): el flanco da al exterior, como en la ochava de una esquina de manzana. Sube
##     desde el borde hasta `sx`/`sz`, y `pa`/`qb` es el punto de inglete donde se cruza con el del corte.
##   · rincón (`valley = true`): el flanco da a una celda PROPIA, como en el chaflán del fondo de un
##     callejón. El faldón del vecino llega por ahí a la altura de la tapa en la esquina lejana, y se
##     encuentra con el del corte en una lima hoya; `pa`/`qb` es donde la línea del corte toca ese borde.
## `RoofPlanner` calcula todos los puntos, como fracción de la región. La tapa es lo que queda.
static func chamfer_unit(k: int, p: Vector2, q: Vector2, pa: Vector2, qb: Vector2, sx: float, sz: float,
		valley_a: bool, valley_b: bool, color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	var cut_a := Vector3(p.x, 0, p.y)
	var cut_b := Vector3(q.x, 0, q.y)
	var top_a := Vector3(pa.x, 1, pa.y)
	var top_b := Vector3(qb.x, 1, qb.y)

	if valley_a:
		m.add_tri_facing(cut_a, Vector3(0, 1, 1), top_a, Vector3.UP, color)
	else:
		m.add_quad_facing(cut_a, Vector3(0, 0, 1), Vector3(sx, 1, 1), top_a, Vector3.UP, color)
	m.add_quad_facing(cut_a, cut_b, top_b, top_a, Vector3.UP, color)
	if valley_b:
		m.add_tri_facing(cut_b, Vector3(1, 1, 0), top_b, Vector3.UP, color)
	else:
		m.add_quad_facing(cut_b, Vector3(1, 0, 0), Vector3(1, 1, sz), top_b, Vector3.UP, color)

	# La tapa: un abanico desde `top_a` por el contorno que dejan los flancos.
	var ring: Array[Vector3] = [top_a]
	if not valley_a:
		ring.append(Vector3(sx, 1, 1))
	ring.append(Vector3(1, 1, 1))
	if not valley_b:
		ring.append(Vector3(1, 1, sz))
	ring.append(top_b)
	for i in range(1, ring.size() - 1):
		m.add_tri_facing(ring[0], ring[i], ring[i + 1], Vector3.UP, color)
	return rotated(m, k)


# ── DOS AGUAS Y UN AGUA ─────────────────────────────────────────────────────────────────────────

## AGUA: un plano que sube desde `h_low` en el lado `outward` hasta `h_high` en el opuesto. Con `wall_left`
## y `wall_right` cierra con una pared vertical los lados perpendiculares (mirando desde afuera, izquierda
## es -x cuando el exterior está en -z), y con `wall_high` cierra el lado alto: es lo que hace el frontón de
## un dos aguas y las tres paredes de un un agua.
static func slope_unit(outward: int, h_low: float, h_high: float, wall_left: bool, wall_right: bool,
		wall_high: bool, color: Color) -> UnitMesh:
	var m := UnitMesh.new()
	m.add_quad_facing(Vector3(0, h_low, 0), Vector3(1, h_low, 0), Vector3(1, h_high, 1), Vector3(0, h_high, 1),
		Vector3.UP, color)
	if wall_left:
		m.add_quad_facing(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, h_high, 1), Vector3(0, h_low, 0),
			Vector3.LEFT, COLOR_SIDE)
	if wall_right:
		m.add_quad_facing(Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, h_high, 1), Vector3(1, h_low, 0),
			Vector3.RIGHT, COLOR_SIDE)
	if wall_high:
		m.add_quad_facing(Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, h_high, 1), Vector3(0, h_high, 1),
			Vector3.BACK, COLOR_SIDE)
	return rotated(m, outward)


# ── TANQUE ──────────────────────────────────────────────────────────────────────────────────────

## Las medidas del tanque en metros. Es un objeto RÍGIDO: la región donde se coloca sale de acá por
## `RigidMatrix.cells_for`, y la mesh se diseña en proporciones del cubo unitario que esa región llena.
const TANK_DIAMETER_M := 3.2
const TANK_LEG_M := 1.6
const TANK_BODY_M := 3.4
const TANK_CAP_M := 0.7
const TANK_LEG_WIDTH_M := 0.35


static func tank_height_m() -> float:
	return TANK_LEG_M + TANK_BODY_M + TANK_CAP_M


## TANQUE DE AGUA estilo americano —cuatro patas, un cilindro y un cono chato de tapa— en el cubo unitario.
## El diámetro llena el cubo en `x` y `z`; en `y` las tres partes van en proporción a sus metros.
static func water_tank_unit() -> UnitMesh:
	var mesh := UnitMesh.new()
	var total := tank_height_m()
	var leg_top := TANK_LEG_M / total
	var body_top := (TANK_LEG_M + TANK_BODY_M) / total
	var leg_w := TANK_LEG_WIDTH_M / TANK_DIAMETER_M

	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0 - leg_w, 0.0),
			Vector2(0.0, 1.0 - leg_w), Vector2(1.0 - leg_w, 1.0 - leg_w)]
	for corner: Vector2 in corners:
		mesh.add_box(Vector3(corner.x, 0.0, corner.y), Vector3(corner.x + leg_w, leg_top, corner.y + leg_w),
			TANK_LEG_COLOR)
	mesh.add_cylinder(Vector3(0.0, leg_top, 0.0), Vector3(1.0, body_top, 1.0), TANK_COLOR)
	mesh.add_cone(Vector3(0.0, body_top, 0.0), Vector3(1.0, 1.0, 1.0), TANK_CAP_COLOR)
	return mesh
