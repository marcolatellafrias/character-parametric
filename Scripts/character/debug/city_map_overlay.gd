class_name CityMapOverlay
extends CanvasLayer

## EL MAPA DE AL LADO — el mismo mapa de la pestaña Mapa del panel F1 (ver CityMap), pero chico, en una
## esquina y MIENTRAS JUGÁS: se abre y se cierra con F2. No se anota en UIState, así que el mouse sigue
## capturado y te seguís moviendo con el mapa a la vista. Ver technical/ui.md.
##
## Por eso mismo acá no hay puntero: no hay clic ni arrastre. El mapa te sigue siempre centrado y el zoom
## va con + y −. Para el mapa grande —arrastrarlo, teletransportarte— está la pestaña del F1.
##
## Va abajo a la izquierda: arriba a la derecha están el gráfico de FPS y el debug de impactos, y abajo al
## medio la barra de stamina.

const SIZE := Vector2(320.0, 320.0)
const MARGIN := 16.0
const ZOOM_STEP := 1.2
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.35)

var _map: CityMap = null


## Lo arma escondido, siguiendo a `player`. Se abre con F2 (ver PlayerController).
func setup(player: CharacterRigidBody3D) -> void:
	layer = 90  # debajo del panel de debug, que es 100
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	var frame := Panel.new()
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = MARGIN
	frame.offset_right = MARGIN + SIZE.x
	frame.offset_top = -(MARGIN + SIZE.y)
	frame.offset_bottom = -MARGIN
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_map = CityMap.new()
	_map.follow_player = true
	_map.player = player
	frame.add_child(_map)
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func toggle() -> void:
	visible = not visible


## El zoom, lo único que se maneja acá: con el mouse capturado no llega la rueda al mapa.
func _input(event: InputEvent) -> void:
	if not visible or _map == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
		_map.zoom_by(ZOOM_STEP)
	elif key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		_map.zoom_by(1.0 / ZOOM_STEP)
	else:
		return
	get_viewport().set_input_as_handled()
