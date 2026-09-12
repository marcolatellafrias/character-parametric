class_name CityMap
extends Control

## MAPA DE LA CIUDAD — la pestaña Mapa del panel F1: la ciudad desde arriba y en vivo, con los autos, las
## naves, los personajes y vos. Es una herramienta de debug: sirve para mirar el tráfico y para ir a una
## zona sin volar hasta allá, con un clic. Ver technical/ui.md.
##
## Lo QUIETO se hornea una sola vez (ver `_bake`), porque la ciudad no cambia mientras se juega: las
## manzanas —las caras del grafo, del color de su barrio—, las calles y los puentes. Las calles se dibujan
## con su ANCHO REAL: la huella de su volumen de carril, que ya viene medida en metros. Las de borde no
## tienen volumen, así que van como línea fina. Cada puente es una marca cruzando su calle, repartidas a lo
## largo de ella: es dónde hay uno y cuántos, no su forma.
##
## Lo que se MUEVE se lee en cada frame, mientras la pestaña esté abierta: los autos, las naves, los
## personajes y el círculo de donde viven los autos (`WorldSettings.spawn_radius` alrededor tuyo).
##
## La vista arranca con la ciudad entera; la rueda acerca hacia donde está el mouse, arrastrar la mueve, un
## clic sin arrastrar te teletransporta ahí y el botón de arriba te vuelve a centrar.
##
## Con `follow_player` prendido es el mapa chico de al lado, el de F2 (ver CityMapOverlay): va siempre
## centrado en vos, no toca el mouse —el puntero queda capturado y seguís jugando— y su zoom se maneja
## desde afuera, con `zoom_by`.

## Con cuánto zoom arranca el mapa de al lado, en píxeles por metro: entran unos 300 m a la redonda.
const FOLLOW_ZOOM := 1.0
## Cuánto acerca o aleja un paso de rueda, y los topes del zoom, en píxeles por metro.
const ZOOM_STEP := 1.15
const MIN_ZOOM := 0.05
const MAX_ZOOM := 8.0
## Aire que queda alrededor de la ciudad cuando entra entera.
const FIT_MARGIN := 12.0
## Cuánto se puede mover el mouse con el botón apretado y que siga contando como clic.
const DRAG_SLOP := 4.0
## El teletransporte cae desde acá hasta lo primero que haya abajo, y aparece esto por encima. Si no hay
## nada —afuera de la ciudad—, queda flotando a `TELEPORT_FALLBACK_HEIGHT`.
const TELEPORT_FROM_HEIGHT := 400.0
const TELEPORT_CLEARANCE := 1.2
const TELEPORT_FALLBACK_HEIGHT := 40.0

## Radios en píxeles: los autos y los personajes son siempre del mismo tamaño —a la escala de la ciudad no
## se verían—, y las naves, de su tamaño real, pero nunca más chicas que esto.
const CAR_RADIUS := 1.8
const CHARACTER_RADIUS := 3.0
const SHIP_MIN_RADIUS := 3.0
## La flecha que sos vos: su largo, y cuánto se abre hacia los costados.
const ARROW_LENGTH := 11.0
const ARROW_HALF_WIDTH := 5.0
## Largo de la marca de un puente, en metros: cruza la calle de lado a lado más o menos.
const BRIDGE_SPAN := 10.0

const BACKGROUND := Color(0.08, 0.09, 0.11)
## Las manzanas, por distrito (ver NeighborhoodTypes.District).
const BLOCK_COLORS: Array[Color] = [
	Color(0.30, 0.26, 0.22),  # pobre
	Color(0.24, 0.32, 0.26),  # rico
	Color(0.28, 0.27, 0.32),  # industrial
]
## Las calles, por tipo (ver BlockGenerator.StreetType): más grande, más clara.
const STREET_COLORS := {
	BlockGenerator.StreetType.SMALL: Color(0.40, 0.42, 0.46),
	BlockGenerator.StreetType.MEDIUM: Color(0.50, 0.52, 0.56),
	BlockGenerator.StreetType.LARGE: Color(0.62, 0.64, 0.68),
}
const BOUNDARY_COLOR := Color(0.35, 0.35, 0.40)
## Los puentes, bien lejos del amarillo de los autos: si no, se confunden.
const BRIDGE_COLOR := Color(0.72, 0.40, 1.0)
const CAR_COLOR := Color(1.0, 0.85, 0.3)
const SHIP_COLOR := Color(0.4, 0.85, 1.0)
const CHARACTER_COLOR := Color(1.0, 0.45, 0.45)
const PLAYER_COLOR := Color(0.4, 1.0, 0.5)
const SPAWN_RING_COLOR := Color(1.0, 0.85, 0.3, 0.25)
const TEXT_COLOR := Color(0.8, 0.82, 0.85)
const TEXT_SIZE := 12

## El personaje propio: el centro del mapa cuando lo centrás, la flecha, y lo que se teletransporta.
var player: CharacterRigidBody3D = null
## Prendido, el mapa va siempre centrado en `player` y no toca el mouse: es el de al lado (ver
## CityMapOverlay). Se elige ANTES de meterlo al árbol.
var follow_player := false

var _zoom := 1.0
## Qué punto de la ciudad —en metros, x y z— cae en el medio del mapa.
var _center := Vector2.ZERO
var _bounds := Rect2()
var _fitted := false

## Lo horneado (ver `_bake`), ya aplanado a x/z y en metros.
var _baked_for: Object = null
var _blocks: Array[PackedVector2Array] = []
var _block_colors: PackedColorArray = PackedColorArray()
var _streets: Array[PackedVector2Array] = []
var _street_colors: PackedColorArray = PackedColorArray()
var _boundaries: Array[PackedVector2Array] = []
var _bridges: Array[PackedVector2Array] = []

var _dragging := false
var _drag_travel := 0.0


func _ready() -> void:
	clip_contents = true
	resized.connect(_on_resized)
	if follow_player:
		# El de al lado no recibe mouse: el puntero está capturado, porque seguís jugando.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	custom_minimum_size = Vector2(440.0, 620.0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


## Redibuja solo con la pestaña abierta: cerrada, el mapa no cuesta nada.
func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## Te pone en el medio del mapa sin cambiar el zoom (el botón "Centrar en mí").
func center_on_player() -> void:
	if is_instance_valid(player):
		_center = _flat(player.global_position)
		queue_redraw()


func _draw() -> void:
	_bake()
	if follow_player and is_instance_valid(player):
		_center = _flat(player.global_position)
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	for i in _blocks.size():
		draw_colored_polygon(_to_screen(_blocks[i]), _block_colors[i])
	for i in _streets.size():
		draw_colored_polygon(_to_screen(_streets[i]), _street_colors[i])
	for line in _boundaries:
		draw_polyline(_to_screen(line), BOUNDARY_COLOR, 1.0)
	for bridge in _bridges:
		draw_polyline(_to_screen(bridge), BRIDGE_COLOR, 2.0)

	var tree := get_tree()
	var cars := 0
	for node in tree.get_nodes_in_group("car_manager"):
		for car in (node as CarManager).cars:
			draw_circle(_to_pixels(_flat(car.sim_transform.origin)), CAR_RADIUS, CAR_COLOR)
			cars += 1
	var ships := tree.get_nodes_in_group(Ship.GROUP)
	for node in ships:
		var ship := node as Ship
		var radius := SHIP_MIN_RADIUS
		if ship.hull != null:
			radius = maxf(ship.hull.bounding_radius() * _zoom, SHIP_MIN_RADIUS)
		draw_circle(_to_pixels(_flat(ship.global_position)), radius, SHIP_COLOR)
	for node in tree.get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		var body := node as Node3D
		if body != player:
			draw_circle(_to_pixels(_flat(body.global_position)), CHARACTER_RADIUS, CHARACTER_COLOR)

	if is_instance_valid(player):
		var at := _to_pixels(_flat(player.global_position))
		# Los autos viven en un anillo alrededor tuyo: afuera de este círculo no hay ninguno.
		draw_arc(at, WorldSettings.spawn_radius * _zoom, 0.0, TAU, 72, SPAWN_RING_COLOR, 1.0)
		_draw_player_arrow(at)

	var font := get_theme_default_font()
	if font != null:
		var hint := "+ / −: zoom" if follow_player else "rueda: zoom · clic: teletransporte"
		draw_string(font, Vector2(8.0, size.y - 8.0),
			"%d autos · %d naves · %.0f m de ancho · %s" % [cars, ships.size(), size.x / _zoom, hint],
			HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, TEXT_COLOR)


## Vos: una flecha apuntando hacia donde mirás (el frente del personaje es −Z).
func _draw_player_arrow(at: Vector2) -> void:
	var facing := -player.global_transform.basis.z
	var ahead := Vector2(facing.x, facing.z)
	if ahead.length_squared() < 0.0001:
		ahead = Vector2.UP
	ahead = ahead.normalized()
	var side := Vector2(-ahead.y, ahead.x)
	draw_colored_polygon(PackedVector2Array([
		at + ahead * ARROW_LENGTH,
		at + side * ARROW_HALF_WIDTH - ahead * ARROW_HALF_WIDTH,
		at - side * ARROW_HALF_WIDTH - ahead * ARROW_HALF_WIDTH]), PLAYER_COLOR)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, 1.0 / ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_drag_travel = 0.0
			else:
				# Apretar y soltar sin moverse es un clic: te lleva ahí. Moverse es arrastrar el mapa.
				if _dragging and _drag_travel < DRAG_SLOP:
					_teleport_to(_to_metres(button.position))
				_dragging = false
		else:
			return
		accept_event()
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_center -= motion.relative / _zoom
		_drag_travel += motion.relative.length()
		queue_redraw()
		accept_event()


## Acerca o aleja desde el medio: el zoom con teclas del mapa de al lado, que no tiene mouse.
func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


## Acerca o aleja dejando quieto el punto de la ciudad que está bajo el mouse.
func _zoom_at(at: Vector2, factor: float) -> void:
	var before := _to_metres(at)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_center += before - _to_metres(at)
	queue_redraw()


## Te deja en ese punto de la ciudad, cayendo desde arriba de todo hasta lo primero que haya abajo. Es
## debug puro: no mira si el lugar es razonable.
func _teleport_to(at: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var from := Vector3(at.x, TELEPORT_FROM_HEIGHT, at.y)
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (TELEPORT_FROM_HEIGHT * 2.0))
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		player.global_position = Vector3(at.x, TELEPORT_FALLBACK_HEIGHT, at.y)
	else:
		player.global_position = (hit.position as Vector3) + Vector3.UP * TELEPORT_CLEARANCE
	player.linear_velocity = Vector3.ZERO


func _on_resized() -> void:
	if not _fitted:
		_fit()
	queue_redraw()


## La ciudad entera, centrada y con un poco de aire. El de al lado no se achica tanto: arranca con un zoom
## fijo, y el centro se lo da el jugador en cada frame.
func _fit() -> void:
	if follow_player:
		_zoom = FOLLOW_ZOOM
		_fitted = true
		return
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	_zoom = clampf(minf((size.x - 2.0 * FIT_MARGIN) / _bounds.size.x,
		(size.y - 2.0 * FIT_MARGIN) / _bounds.size.y), MIN_ZOOM, MAX_ZOOM)
	_center = _bounds.get_center()
	_fitted = true


## Hornea la ciudad —manzanas, calles y puentes— la primera vez que se la ve, y de nuevo si se regeneró.
func _bake() -> void:
	var city := get_tree().get_first_node_in_group("city_generator") as Node3D
	var generator: GraphCityGenerator = city.get_generator() if city != null else null
	if generator == _baked_for:
		return
	_baked_for = generator
	_blocks.clear()
	_block_colors.clear()
	_streets.clear()
	_street_colors.clear()
	_boundaries.clear()
	_bridges.clear()
	_fitted = false
	if generator == null or generator.plain_graph == null:
		return

	# Todo lo de la ciudad está en el espacio de su nodo; los autos y los personajes, en el del mundo.
	var to_world := city.global_transform
	var graph := generator.plain_graph
	for face_idx in graph.faces.size():
		var block := PackedVector2Array()
		for node_idx: int in graph.faces[face_idx]:
			block.append(_flat(to_world * (graph.points[node_idx] as Vector3)))
		_blocks.append(block)
		_block_colors.append(BLOCK_COLORS[int(generator.face_to_type.get(face_idx, 0)) % BLOCK_COLORS.size()])

	# Las calles, con su ancho real: la huella del volumen de carril, del piso de un plano al del otro.
	for node in get_tree().get_nodes_in_group("lane_volumes"):
		var lane := node as LaneVolume
		if lane.start_plane_vertices.size() < 4 or lane.end_plane_vertices.size() < 4:
			continue
		_streets.append(PackedVector2Array([
			_flat(to_world * (lane.start_plane_vertices[0] as Vector3)),
			_flat(to_world * (lane.start_plane_vertices[1] as Vector3)),
			_flat(to_world * (lane.end_plane_vertices[1] as Vector3)),
			_flat(to_world * (lane.end_plane_vertices[0] as Vector3))]))
		_street_colors.append(STREET_COLORS.get(lane.street_type, BOUNDARY_COLOR))

	for edge: Array in graph.edges:
		var a := _flat(to_world * (graph.points[edge[0]] as Vector3))
		var b := _flat(to_world * (graph.points[edge[1]] as Vector3))
		# Las de borde no tienen volumen de carril —no tienen ancho—: van como línea fina.
		if generator.get_street_type(edge[0], edge[1]) == BlockGenerator.StreetType.BOUNDARY:
			_boundaries.append(PackedVector2Array([a, b]))
		var over: Array = generator.bridges.get(GraphGenerator._get_edge_key(edge[0], edge[1]), [])
		var across := (b - a).normalized().orthogonal() * BRIDGE_SPAN * 0.5
		for k in over.size():
			var at := a.lerp(b, float(k + 1) / float(over.size() + 1))
			_bridges.append(PackedVector2Array([at - across, at + across]))

	_bounds = Rect2(_blocks[0][0], Vector2.ZERO) if not _blocks.is_empty() else Rect2()
	for block in _blocks:
		for corner in block:
			_bounds = _bounds.expand(corner)
	_fit()


## De metros a píxeles del mapa, y al revés.
func _to_pixels(at: Vector2) -> Vector2:
	return (at - _center) * _zoom + size * 0.5


func _to_metres(at: Vector2) -> Vector2:
	return (at - size * 0.5) / _zoom + _center


func _to_screen(points: PackedVector2Array) -> PackedVector2Array:
	var screen := PackedVector2Array()
	for point in points:
		screen.append(_to_pixels(point))
	return screen


## El mapa es de arriba: la altura no cuenta.
static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
