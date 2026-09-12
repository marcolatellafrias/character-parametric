class_name CityTerrain
extends RefCounted

## EL RELIEVE DE LA CIUDAD — una altura por NODO del grafo, y nada más. Ver technical/city-generation.md.
##
## No es un campo libre del plano: es un dato de la TOPOLOGÍA. Cada nodo tiene su altura, y de ahí para
## abajo la altura VIAJA CON LA GEOMETRÍA, interpolada por la misma bilineal que ya calcula el XZ —la
## manzana desde sus 4 esquinas, la celda de grilla desde la manzana, el módulo desde la celda—.
##
## Eso no es una decisión de comodidad; es lo que hace que la ciudad salga bien sin reglas especiales:
##
##   · UNA CALLE SE INCLINA EN EL SENTIDO EN QUE CORRE, no de costado. Las dos manzanas que dan a una calle
##     comparten los dos nodos de esa arista, así que los dos bordes de la calzada interpolan entre las
##     MISMAS dos alturas y sobre el mismo eje. A lo ancho queda nivelada sola. Con un campo libre de ruido
##     cada borde caía en un valor distinto y la calle salía peraltada, que es lo que pasaba antes.
##   · NADA CLIPEA CONTRA EL SUELO. El suelo se arma con los mismos quads que usan las veredas y los
##     módulos, interpolados igual, así que son la misma superficie y no hay dónde asomarse.
##
## Las alturas salen de RUIDO sembrado con la seed del mundo —determinista: el tráfico predice rutas en red
## y la geometría tiene que ser idéntica en todas las máquinas—, con dos correcciones:
##   · SE ESTIRAN al rango entero. El ruido crudo no llega a sus extremos (en una ciudad medida, entre el
##     22% y el 77%), así que sin esto el relieve queda aplastado y flotando sobre el cero.
##   · SE CAPA LA PENDIENTE. Se mide la calle más empinada y, si pasa de `max_slope`, se baja la amplitud de
##     todo el relieve hasta que entre. El personaje es un rigidbody con fricción 0, sin límite de pendiente
##     ni lógica de escalón, y los autos rasantes van a tener que seguir el suelo.
##
## Con todas las alturas en 0 la ciudad vuelve a ser EXACTAMENTE la de antes: cada interpolación se degrada
## a lo que ya hacía.
##
## El relieve de ADENTRO de la manzana no vive acá. Ese es escalonado y discreto, va sobre la DistortedGrid
## y se apaga en el perímetro, para que el borde de la manzana valga lo que dicen estos nodos.

## Alto del nodo más alto, en metros. Queda por debajo de lo pedido si la pendiente no entraba.
var amplitude := 0.0
## Cada cuántos metros cambia el relieve.
var feature_size := 300.0
## Pendiente máxima admitida en una calle, en metros por metro.
var max_slope := 0.12

## La altura de cada nodo del grafo, por índice. Vacío mientras no se haya llamado a `fit_to_graph`.
var node_heights := PackedFloat32Array()

var _noise := FastNoiseLite.new()


func _init(terrain_seed: int, p_amplitude: float, p_feature_size: float, p_max_slope: float) -> void:
	amplitude = maxf(p_amplitude, 0.0)
	feature_size = maxf(p_feature_size, 1.0)
	max_slope = maxf(p_max_slope, 0.0001)
	_noise.seed = terrain_seed
	_noise.frequency = 1.0 / feature_size


## Le pone altura a cada nodo: ruido, estirado al rango entero y con la pendiente capada. Se llama una sola
## vez, apenas existe el grafo.
func fit_to_graph(points: Array[Vector3], edges: Array) -> void:
	node_heights.clear()
	if points.is_empty():
		return

	var lowest := INF
	var highest := -INF
	var raw := PackedFloat32Array()
	for point: Vector3 in points:
		var sample := _noise.get_noise_2d(point.x, point.z)
		raw.append(sample)
		lowest = minf(lowest, sample)
		highest = maxf(highest, sample)
	var spread := maxf(highest - lowest, 0.0001)

	node_heights.resize(raw.size())
	for i in raw.size():
		node_heights[i] = amplitude * (raw[i] - lowest) / spread
	if amplitude <= 0.0:
		return

	# La calle más empinada manda: si se pasa, baja todo el relieve en la misma proporción.
	var steepest := 0.0
	for edge: Array in edges:
		var a: Vector3 = points[edge[0]]
		var b: Vector3 = points[edge[1]]
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		if run < 0.001:
			continue
		steepest = maxf(steepest, absf(node_heights[edge[1]] - node_heights[edge[0]]) / run)
	if steepest > max_slope:
		var fit := max_slope / steepest
		amplitude *= fit
		for i in node_heights.size():
			node_heights[i] *= fit


## La altura de un nodo del grafo.
func height_of(node_idx: int) -> float:
	if node_idx < 0 or node_idx >= node_heights.size():
		return 0.0
	return node_heights[node_idx]
