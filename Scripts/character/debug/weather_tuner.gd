class_name WeatherTuner
extends CanvasLayer

## EL AFINADOR DEL CLIMA — se abre con F6 y deja tocar a mano lo que los presets traen fijo: el diámetro y
## el color de la niebla, los dos colores del filtro de pantalla, los colores del cielo, y el sol con su
## contraste, su disco y la dureza de su sombra.
##
## El color de la niebla es SUYO, no del cielo: los presets de San Andreas los hacen coincidir, pero el
## preset `original` tiene cielo stock con niebla azul. Por eso hay tres selectores y no dos.
##
## A diferencia de la lista de F5, este SÍ se anota en UIState: hay que arrastrar sliders y abrir selectores
## de color, y para eso el mouse tiene que estar libre. El juego sigue corriendo detrás (UIState no frena la
## simulación), así que los cambios se ven en vivo sobre la ciudad.
##
## Lo que se toca acá son OVERRIDES sobre el preset activo, no el preset en sí: `CityFog` los apila encima
## de la tabla y se borran solos al elegir otro clima desde F5 o desde el panel. El botón de abajo los
## limpia sin cambiar de clima. Nada de esto se guarda en disco — es para mirar y decidir, y lo que sirva
## se copia a mano a `WeatherPresets`.
##
## OJO con el diámetro: mover `render_distance` no alcanza. El corte por distancia de cada edificio se
## calcula UNA VEZ al generar la ciudad, así que además hay que recalcularlo (`CityDebugView.refresh_ranges`)
## o la niebla se movería y la geometría se seguiría cortando donde estaba antes.

const MARGIN := 16.0
const WIDTH := 420.0
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.75)

var _box: VBoxContainer = null


func setup() -> void:
	layer = 95  # debajo del panel de debug (100), encima del mapa y la lista de clima (90)
	visible = false
	UIState.changed.connect(_on_ui_changed)

	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	var frame := PanelContainer.new()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.offset_left = -(MARGIN + WIDTH)
	frame.offset_right = -MARGIN
	frame.offset_top = MARGIN
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	_box = VBoxContainer.new()
	frame.add_child(_box)

	var title := Label.new()
	title.text = "AFINAR CLIMA  (F6 cierra)"
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	_box.add_child(title)

	_header("Niebla")
	_slider("Empieza a", WorldSettings.fog_start_distance, 0.0, 600.0, 5.0,
		func(v: float) -> void:
			WorldSettings.fog_start_distance = v)
	_slider("Diámetro (tapa del todo a)", WorldSettings.render_distance, 200.0, 2000.0, 10.0,
		func(v: float) -> void:
			WorldSettings.render_distance = v
			CityDebugView.refresh_ranges(get_tree()))

	_header("Filtro de pantalla")
	_slider("Fuerza", _fog_value("tint_strength", 0.45), 0.0, 1.0, 0.01,
		func(v: float) -> void: _set_tint_strength(v))
	_color("Color 1 (multiplica)", "tint1")
	_color("Color 2 (lava)", "tint2")

	_header("Niebla y cielo")
	_color("Color de la niebla", "fog_color")
	_color("Cenit del cielo", "sky_top")
	_color("Horizonte del cielo", "sky_horizon")

	_header("Sol")
	_slider("Contraste (menos luz ambiente)", _fog_value("ambient_energy", 0.3), 0.0, 1.2, 0.01,
		func(v: float) -> void: _override("ambient_energy", v))
	_slider("Fuerza del sol", _fog_value("sun_energy", 1.35), 0.0, 4.0, 0.05,
		func(v: float) -> void: _override("sun_energy", v))
	_slider("Tamaño del disco (0 = sin sol)", _fog_value("sun_size", 3.2), 0.0, 12.0, 0.1,
		func(v: float) -> void: _override("sun_size", v))
	_slider("Dureza de la sombra (0 = dura)", _fog_value("shadow_softness", 0.2), 0.0, 4.0, 0.05,
		func(v: float) -> void: _override("shadow_softness", v))
	_slider("Altura del sol", _fog_value("sun_elevation", 62.0), -10.0, 90.0, 1.0,
		func(v: float) -> void: _override("sun_elevation", v))

	var reset := Button.new()
	reset.text = "Volver al preset"
	reset.pressed.connect(func() -> void:
		for node in get_tree().get_nodes_in_group("city_fog"):
			var fog := node as CityFog
			if fog != null:
				fog.clear_overrides())
	_box.add_child(reset)


func toggle() -> void:
	UIState.toggle(UIState.TUNER)


func _on_ui_changed() -> void:
	visible = UIState.is_open(UIState.TUNER)


# ── Armado de controles ──────────────────────────────────────────────────────────────────────────

func _header(text: String) -> void:
	var label := Label.new()
	label.text = "── " + text
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_box.add_child(label)


func _slider(label_text: String, value: float, min_value: float, max_value: float, step: float,
		on_change: Callable) -> void:
	var label := Label.new()
	label.text = "%s: %.2f" % [label_text, value]
	_box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%s: %.2f" % [label_text, v]
		on_change.call(v))
	_box.add_child(slider)


func _color(label_text: String, key: String) -> void:
	var label := Label.new()
	label.text = label_text
	_box.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(0.0, 24.0)
	picker.color = _fog_color(key)
	picker.color_changed.connect(func(c: Color) -> void: _override(key, c))
	_box.add_child(picker)


# ── Lectura y escritura del clima vivo ───────────────────────────────────────────────────────────

func _first_fog() -> CityFog:
	for node in get_tree().get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			return fog
	return null


func _override(key: String, value: Variant) -> void:
	for node in get_tree().get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			fog.set_override(key, value)


func _set_tint_strength(v: float) -> void:
	for node in get_tree().get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			fog.tint_strength = v


func _fog_value(key: String, fallback: float) -> float:
	var fog := _first_fog()
	if fog == null:
		return fallback
	if key == "tint_strength":
		return fog.tint_strength
	var value: Variant = fog.value_of(key)
	return float(value) if value != null else fallback


func _fog_color(key: String) -> Color:
	var fog := _first_fog()
	if fog == null:
		return Color.WHITE
	var value: Variant = fog.value_of(key)
	return value if value is Color else Color.WHITE
