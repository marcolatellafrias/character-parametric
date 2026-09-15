class_name TunerPanel
extends CanvasLayer

## EL PANEL DE UN AFINADOR — el marco, el scroll, el botón de copiar y el alta en `UIState`. No sabe qué
## afina: cada afinador hereda de acá y solo escribe `sections()`.
##
## Existe porque hay más de uno (clima y nubes en F6, terreno y afueras en F7) y todo lo que los rodea es
## idéntico. Lo único propio de cada uno es QUÉ objetos toca, y eso es una lista de specs.
##
## Estos paneles SÍ se anotan en `UIState`, a diferencia del mapa de F2: hay que arrastrar sliders y abrir
## selectores de color, y para eso el mouse tiene que estar libre. El juego sigue corriendo detrás, así
## que los cambios se ven en vivo.
##
## Nada se guarda en disco. El botón de copiar escupe cada sección con el archivo donde se pega, y lo que
## funcione se copia a mano.

const MARGIN := 16.0
const WIDTH := 520.0
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.85)

var _ui_key := ""
var _box: VBoxContainer = null
var _copy_button: Button = null
var _built := false


## `extra` son botones propios del afinador —regenerar, por ejemplo—, que van arriba de todo junto al de
## copiar.
func setup(ui_key: String, title_text: String, extra: Array[Button] = []) -> void:
	_ui_key = ui_key
	layer = 95  # debajo del panel de debug (100), encima del mapa (90)
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
	frame.anchor_bottom = 1.0
	frame.offset_left = -(MARGIN + WIDTH)
	frame.offset_right = -MARGIN
	frame.offset_top = MARGIN
	frame.offset_bottom = -MARGIN
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	var column := VBoxContainer.new()
	frame.add_child(column)

	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	column.add_child(title)

	for button in extra:
		button.focus_mode = Control.FOCUS_NONE
		column.add_child(button)

	_copy_button = Button.new()
	_copy_button.text = "Copiar todo al portapapeles"
	_copy_button.focus_mode = Control.FOCUS_NONE
	_copy_button.pressed.connect(_copy)
	column.add_child(_copy_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)


func toggle() -> void:
	UIState.toggle(_ui_key)


## Qué afina este panel: una lista de specs de `PropertyTuner`, cada uno con un `title` que dice en qué
## archivo se pegan sus valores. Lo escribe cada afinador.
func sections() -> Array[Dictionary]:
	return []


func _on_ui_changed() -> void:
	visible = UIState.is_open(_ui_key)
	# Se arma la primera vez que se abre, no al spawnear: los controles nacen con el valor que el mundo
	# tiene en ese momento, y un panel que casi nunca se abre no cuesta nada.
	if visible and not _built:
		_built = true
		for section in sections():
			var title := Label.new()
			title.text = str(section["title"])
			title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
			_box.add_child(title)
			PropertyTuner.build(_box, section)
			_box.add_child(HSeparator.new())


## El estado entero como texto pegable, sección por sección, con el archivo de destino de cada una.
func _copy() -> void:
	var blocks := PackedStringArray()
	for section in sections():
		blocks.append("# %s\n%s" % [section["title"], PropertyTuner.dump(section)])
	DisplayServer.clipboard_set("\n\n".join(blocks))
	_copy_button.text = "Copiado ✓"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_copy_button):
		_copy_button.text = "Copiar todo al portapapeles"
