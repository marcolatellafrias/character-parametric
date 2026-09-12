class_name RoofProps
extends RefCounted

## LO QUE SE PONE ARRIBA DE UN EDIFICIO — por ahora tres cosas, todas placeholder: un tanque de agua, un
## techo de una agua y uno de dos aguas.
##
## Todo se construye con PropGeometry, o sea en coordenadas normalizadas del quad del techo, así que cada
## objeto sale ya deformado con la grilla distorsionada y ya inclinado con el terreno. No hay una operación
## de skew aparte: no hace falta.
##
## ⚠ El quad tiene que venir de la convención de la MALLA (`get_core_vertices(0)` más el desplazamiento del
## piso), no de la de colocación. Las dos superficies difieren hasta 1,35 m en los pisos altos, y el techo
## que el jugador ve es el de la malla (ver "The terrain plan" en technical/city-generation.md).
##
## Las medidas van en metros y se convierten a fracciones del quad con el tamaño real que tenga ese techo,
## porque una celda de edificio no mide lo mismo en toda la ciudad.

const TANK_COLOR := Color(0.42, 0.33, 0.27)
const TANK_LEG_COLOR := Color(0.30, 0.24, 0.20)
const TANK_CAP_COLOR := Color(0.35, 0.28, 0.23)
const ROOF_COLOR := Color(0.38, 0.30, 0.28)
const ROOF_SIDE_COLOR := Color(0.46, 0.42, 0.40)


## El lado del quad en metros, promediando sus dos direcciones. Sirve para pasar de metros a fracción.
static func _span(quad: Array) -> Vector2:
	# Tipos explicitos: `quad` es un Array sin tipar, asi que su acceso devuelve Variant y `:=` no puede
	# inferir. Vale para todo lo que salga de un Array o un Dictionary.
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


## TECHO DE UNA AGUA: el plano inclinado más los cuatro laterales que lo cierran. `low_edge` dice de qué
## lado baja (0 = norte, 1 = este, 2 = sur, 3 = oeste).
static func shed_roof(buffer: Dictionary, quad: Array, height: float = 1.8, low_edge: int = 0) -> void:
	var inside := PropGeometry.center(quad, height * 0.5)

	# Altura de cada esquina del quad: el lado bajo en 0 y el opuesto en `height`.
	var corner_y: Array[float] = [0.0, 0.0, 0.0, 0.0]
	match low_edge:
		0: corner_y = [0.0, 0.0, height, height]
		1: corner_y = [height, 0.0, 0.0, height]
		2: corner_y = [height, height, 0.0, 0.0]
		_: corner_y = [0.0, height, height, 0.0]

	var base: Array[Vector3] = []
	var top: Array[Vector3] = []
	var uv: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for i in 4:
		base.append(PropGeometry.point(quad, uv[i].x, uv[i].y, 0.0))
		top.append(PropGeometry.point(quad, uv[i].x, uv[i].y, corner_y[i]))

	# El plano del techo mira PARA ARRIBA por definición, no por el truco del punto interior: su
	# centroide coincide con ese punto y el test se degenera (ver PropGeometry.add_tri_facing).
	PropGeometry.add_quad_facing(buffer, top[0], top[1], top[2], top[3], Vector3.UP, ROOF_COLOR)
	# Los cuatro laterales. Donde el lado baja a cero el quad degenera en una línea y no aporta nada.
	for i in 4:
		var j := (i + 1) % 4
		PropGeometry.add_quad(buffer, base[i], base[j], top[j], top[i], inside, ROOF_SIDE_COLOR)


## TECHO DE DOS AGUAS: dos planos que se encuentran en una cumbrera, dos frontones triangulares y dos
## laterales rectangulares. `ridge_along_u` elige en qué dirección corre la cumbrera.
static func gable_roof(buffer: Dictionary, quad: Array, height: float = 2.2,
		ridge_along_u: bool = true) -> void:
	var inside := PropGeometry.center(quad, height * 0.4)
	var uv: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var base: Array[Vector3] = []
	for i in 4:
		base.append(PropGeometry.point(quad, uv[i].x, uv[i].y, 0.0))

	if ridge_along_u:
		var ridge_a := PropGeometry.point(quad, 0.0, 0.5, height)
		var ridge_b := PropGeometry.point(quad, 1.0, 0.5, height)
		# Las dos aguas, cada una mirando hacia arriba y hacia su lado.
		PropGeometry.add_quad_facing(buffer, base[0], base[1], ridge_b, ridge_a,
			Vector3.UP + (base[0] - base[3]).normalized(), ROOF_COLOR)
		PropGeometry.add_quad_facing(buffer, base[3], base[2], ridge_b, ridge_a,
			Vector3.UP + (base[3] - base[0]).normalized(), ROOF_COLOR)
		# Los dos frontones.
		PropGeometry.add_tri(buffer, base[0], base[3], ridge_a, inside, ROOF_SIDE_COLOR)
		PropGeometry.add_tri(buffer, base[1], base[2], ridge_b, inside, ROOF_SIDE_COLOR)
	else:
		var ridge_c := PropGeometry.point(quad, 0.5, 0.0, height)
		var ridge_d := PropGeometry.point(quad, 0.5, 1.0, height)
		PropGeometry.add_quad_facing(buffer, base[0], base[3], ridge_d, ridge_c,
			Vector3.UP + (base[0] - base[1]).normalized(), ROOF_COLOR)
		PropGeometry.add_quad_facing(buffer, base[1], base[2], ridge_d, ridge_c,
			Vector3.UP + (base[1] - base[0]).normalized(), ROOF_COLOR)
		PropGeometry.add_tri(buffer, base[0], base[1], ridge_c, inside, ROOF_SIDE_COLOR)
		PropGeometry.add_tri(buffer, base[3], base[2], ridge_d, inside, ROOF_SIDE_COLOR)
