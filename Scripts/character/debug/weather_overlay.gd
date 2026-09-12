class_name WeatherOverlay
extends CanvasLayer

## LA LISTA DE CLIMAS — se abre y se cierra con F5, y se elige a mano con los números.
##
## Sigue el mismo criterio que el mapa de al lado (ver CityMapOverlay): NO se anota en UIState, así que el
## mouse sigue capturado y te seguís moviendo con la lista a la vista. Es a propósito — comparar dos
## iluminaciones significa alternar entre ellas parado en el mismo lugar, mirando lo mismo; si abrirla
## frenara el juego, no serviría para eso.
##
## Por la misma razón no hay clic: se elige con las teclas numéricas. Para una lista clickeable está la
## pestaña Clima del panel F1.
##
## Va arriba a la izquierda: arriba a la derecha están el gráfico de FPS y el debug de impactos, abajo a la
## izquierda el mapa y abajo al medio la barra de stamina.

const MARGIN := 16.0
const WIDTH := 330.0
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.55)
const SELECTED := Color(1.0, 0.85, 0.4)
const NORMAL := Color(0.85, 0.85, 0.85)

var _rows: Array[Label] = []
var _ids: Array[String] = []


func setup() -> void:
	layer = 90  # debajo del panel de debug, que es 100
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	var frame := PanelContainer.new()
	frame.offset_left = MARGIN
	frame.offset_top = MARGIN
	frame.offset_right = MARGIN + WIDTH
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)

	var title := Label.new()
	title.text = "CLIMA  (F5 cierra)"
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	box.add_child(title)

	_ids = WeatherPresets.ids()
	for i in _ids.size():
		var row := Label.new()
		row.text = "%d · %s" % [i + 1, WeatherPresets.get_preset(_ids[i])["name"]]
		box.add_child(row)
		_rows.append(row)
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


## Marca en amarillo el que está puesto. Se relee del mundo en vez de recordarlo acá, así la lista no se
## desincroniza si el clima se cambia desde la pestaña del F1.
func _refresh() -> void:
	var current := ""
	for node in get_tree().get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			current = fog.preset_id
			break
	for i in _rows.size():
		_rows[i].add_theme_color_override("font_color", SELECTED if _ids[i] == current else NORMAL)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_1
	if index < 0 or index >= _ids.size():
		return
	CityFog.apply_to_tree(get_tree(), _ids[index])
	_refresh()
	get_viewport().set_input_as_handled()
