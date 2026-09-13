class_name RoofProps
extends RefCounted

## LA GEOMETRÍA DE UN TECHO — dibuja el campo de alturas que arma `RoofPlanner`, más el tanque de agua.
##
## Acá NO se decide nada: qué forma tiene el techo y cuánto levanta en cada punto lo resuelve el planner.
## Esto recorre una celda y emite los parches que le tocan.
##
## ⚠ EL TECHO NO ES UNA PIEZA POR CELDA, es un campo. La versión anterior tenía una función por forma —un
## agua, dos aguas, esquina— y elegía una para cada celda: los techos salían ROTOS, porque dos piezas
## vecinas no coincidían en el perfil del borde que comparten (ver la explicación larga en RoofPlanner).
## Ahora la altura vive en los VÉRTICES de una retícula de media celda y las celdas vecinas comparten esos
## vértices, así que la continuidad es estructural y no hay forma de que falle.
##
## Todo se construye con PropGeometry, o sea en coordenadas normalizadas del quad del techo, así que cada
## parche sale ya deformado con la grilla distorsionada y ya inclinado con el terreno. No hay una operación
## de skew aparte: no hace falta.
##
## El quad se le pide a la grilla en la altura del último piso (ver `City._visualize_roof_props`). Dos celdas
## vecinas del mismo edificio comparten la arista exacta —el borde entre ellas es `NORMAL`, cuyo offset de
## núcleo es 0, y sobre una arista compartida la bilineal de cada celda se reduce a la misma interpolación
## lineal—, así que los parches de una y otra empalman en el mundo y no solo en el campo.

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

## Las cuatro esquinas de un parche en orden de recorrido, y las direcciones de sus bordes: 0 = -z, 1 = +x,
## 2 = +z, 3 = -x, igual que en `RoofPlanner`.
const EPSILON := 0.001


static func color_for_style(style: int) -> Color:
	match style:
		RoofPlanner.Style.GABLE:
			return COLOR_GABLE
		RoofPlanner.Style.FRENCH:
			return COLOR_FRENCH
		_:
			return COLOR_SHED


## EL TECHO DE UNA CELDA: los cuatro parches de media celda, con la altura de cada esquina sacada del campo.
##
## `heights` va indexado por vértice ABSOLUTO de media celda (ver `RoofPlanner.plan`), así que los vértices
## del borde de esta celda son los mismos objetos que lee la celda de al lado: de ahí sale la continuidad.
static func roof_from_field(buffer: Dictionary, quad: Array, cell: Vector2i, heights: Dictionary,
		own: Dictionary, color: Color) -> void:
	var base_i := cell.x * 2
	var base_j := cell.y * 2
	var centre := PropGeometry.point(quad, 0.5, 0.5, 0.0)

	for sj in 2:
		for si in 2:
			var u0 := float(si) * 0.5
			var v0 := float(sj) * 0.5
			var u1 := u0 + 0.5
			var v1 := v0 + 0.5

			# Tipos explícitos: lo que sale de un Dictionary es Variant y `:=` no puede inferir.
			var h00: float = heights.get(Vector2i(base_i + si, base_j + sj), 0.0)
			var h10: float = heights.get(Vector2i(base_i + si + 1, base_j + sj), 0.0)
			var h11: float = heights.get(Vector2i(base_i + si + 1, base_j + sj + 1), 0.0)
			var h01: float = heights.get(Vector2i(base_i + si, base_j + sj + 1), 0.0)

			var p00 := PropGeometry.point(quad, u0, v0, h00)
			var p10 := PropGeometry.point(quad, u1, v0, h10)
			var p11 := PropGeometry.point(quad, u1, v1, h11)
			var p01 := PropGeometry.point(quad, u0, v1, h01)
			# Mira PARA ARRIBA por definición, no por el truco del punto interior: cuando el parche es plano
			# su centroide coincide con ese punto y el test se degenera (ver PropGeometry.add_tri_facing).
			PropGeometry.add_quad_facing(buffer, p00, p10, p11, p01, Vector3.UP, color)

			# LAS FALDAS van solo donde el techo termina contra el aire y encima quedó levantado: el frontón
			# de un dos aguas. Hacia adentro de la huella nunca, porque ahí sigue el techo del vecino; y en un
			# francés el borde baja a cero, así que no hace falta ninguna.
			_skirt(buffer, quad, centre, own, cell, 0, sj == 0, u0, v0, u1, v0, h00, h10)
			_skirt(buffer, quad, centre, own, cell, 1, si == 1, u1, v0, u1, v1, h10, h11)
			_skirt(buffer, quad, centre, own, cell, 2, sj == 1, u1, v1, u0, v1, h11, h01)
			_skirt(buffer, quad, centre, own, cell, 3, si == 0, u0, v1, u0, v0, h01, h00)


## La pared vertical bajo un borde de parche, si ese borde da al exterior de la huella y el techo no llega
## al suelo ahí.
static func _skirt(buffer: Dictionary, quad: Array, centre: Vector3, own: Dictionary, cell: Vector2i,
		dir: int, on_cell_border: bool, ua: float, va: float, ub: float, vb: float,
		ha: float, hb: float) -> void:
	if not on_cell_border:
		return
	if maxf(ha, hb) <= EPSILON:
		return
	if own.has(cell + RoofPlanner.DIR_OFFSETS[dir]):
		return

	var ga := PropGeometry.point(quad, ua, va, 0.0)
	var gb := PropGeometry.point(quad, ub, vb, 0.0)
	var ta := PropGeometry.point(quad, ua, va, ha)
	var tb := PropGeometry.point(quad, ub, vb, hb)
	var facing := (ga + gb) * 0.5 - centre
	facing.y = 0.0
	PropGeometry.add_quad_facing(buffer, ga, gb, tb, ta, facing, COLOR_SIDE)


## El lado del quad en metros, promediando sus dos direcciones. Sirve para pasar de metros a fracción.
static func _span(quad: Array) -> Vector2:
	var along_u: float = (quad[0].distance_to(quad[1]) + quad[3].distance_to(quad[2])) * 0.5
	var along_v: float = (quad[0].distance_to(quad[3]) + quad[1].distance_to(quad[2])) * 0.5
	return Vector2(maxf(along_u, 0.001), maxf(along_v, 0.001))


## TANQUE DE AGUA estilo americano: cuatro patas rectangulares, un cilindro y un cono chato de tapa.
## Se centra en el techo y se dimensiona en metros; si el techo es más chico que el tanque, no se pone.
static func water_tank(buffer: Dictionary, quad: Array, diameter: float = 3.2,
		body_height: float = 3.4, leg_height: float = 1.6) -> bool:
	var span := _span(quad)
	var du := diameter / span.x
	var dv := diameter / span.y
	if du >= 0.9 or dv >= 0.9:
		return false

	var u0 := 0.5 - du * 0.5
	var u1 := 0.5 + du * 0.5
	var v0 := 0.5 - dv * 0.5
	var v1 := 0.5 + dv * 0.5

	# Patas: cuatro cajitas en las esquinas del pie del tanque.
	var leg_u := (0.35 / span.x)
	var leg_v := (0.35 / span.y)
	var leg_corners: Array[Vector2] = [
		Vector2(u0, v0), Vector2(u1 - leg_u, v0),
		Vector2(u0, v1 - leg_v), Vector2(u1 - leg_u, v1 - leg_v),
	]
	for corner: Vector2 in leg_corners:
		PropGeometry.add_box(buffer, quad, corner.x, corner.y,
			corner.x + leg_u, corner.y + leg_v, 0.0, leg_height, TANK_LEG_COLOR)

	PropGeometry.add_cylinder(buffer, quad, u0, v0, u1, v1, leg_height, body_height, TANK_COLOR)
	PropGeometry.add_cone(buffer, quad, u0, v0, u1, v1, leg_height + body_height,
		diameter * 0.22, TANK_CAP_COLOR)
	return true
