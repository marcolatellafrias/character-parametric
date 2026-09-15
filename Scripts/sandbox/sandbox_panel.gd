class_name SandboxPanel
extends CanvasLayer

## EL PANEL DEL DESIGN SANDBOX: a la derecha, mientras el ente está en la zona de interacción de una
## parcela, qué es lo que tiene delante (categoría, nombre, semilla y lo que el arquetipo diga de sí), las
## teclas de siempre y las de su fila (ver SeededArchetype.category_options). El mouse está capturado, así
## que todo es tecla y no botón.

const MARGIN := 16.0
const WIDTH := 360.0
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.7)
const HINT := "R  regenerar con otra semilla\nC  copiar esta información"

var _text: Label = null
var _hint: Label = null
var _copied_until := 0.0
var _hint_text := HINT


func _ready() -> void:
	layer = 90
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_left = 4
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

	var column := VBoxContainer.new()
	frame.add_child(column)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 24.0, 0.0)
	column.add_child(_text)
	column.add_child(HSeparator.new())
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_hint.add_theme_font_size_override("font_size", 12)
	column.add_child(_hint)


func show_parcel(parcel: SandboxParcel, options: Array) -> void:
	_text.text = "\n".join(parcel.info_lines())
	var lines := PackedStringArray([HINT])
	for option: Dictionary in options:
		var label = option["label"]
		lines.append(str(label.call()) if label is Callable else str(label))
	_hint_text = "\n".join(lines)
	_hint.text = _hint_text
	visible = true


func hide_panel() -> void:
	visible = false


## Lo mismo que se ve, al portapapeles, y un aviso breve en el panel.
func copy(parcel: SandboxParcel) -> void:
	DisplayServer.clipboard_set("\n".join(parcel.info_lines()))
	_hint.text = "Copiado ✓\n" + _hint_text
	_copied_until = Time.get_ticks_msec() / 1000.0 + 1.5


func _process(_delta: float) -> void:
	if _copied_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _copied_until:
		_copied_until = 0.0
		_hint.text = _hint_text
