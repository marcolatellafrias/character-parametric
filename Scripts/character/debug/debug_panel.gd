class_name DebugPanel
extends CanvasLayer

# Panel de debug con tabs (Info / Acciones / Arquetipos / Spawn / Performance). Se registra desde afuera
# vía add_info / add_text / add_action / add_toggle / add_control; el panel solo renderiza. Ocupa todo el
# alto de la pantalla, así casi no hace falta scrollear. Su visibilidad y el mouse
# los maneja UIState (tecla F1). Solo se crea para un personaje con debug_enabled = true.
# La consola global (tecla º) es aparte. Ver technical/ui.md.

const WIDTH := 480.0
const MARGIN := 20.0

var _tabs: TabContainer
var _tab_boxes: Dictionary = {}  # tab_name -> VBoxContainer

func _ready() -> void:
	layer = 100
	visible = false
	UIState.changed.connect(_on_ui_changed)

	# Pegado a la izquierda, de `WIDTH` de ancho y de todo el alto menos `MARGIN`: sigue a la pantalla.
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = MARGIN
	panel.offset_top = MARGIN
	panel.offset_right = MARGIN + WIDTH
	panel.offset_bottom = -MARGIN
	add_child(panel)

	_tabs = TabContainer.new()
	panel.add_child(_tabs)

	# Orden fijo de las tabs.
	for tab_name in ["Info", "Acciones", "Arquetipos", "Spawn", "Performance"]:
		_get_tab(tab_name)

func _get_tab(tab_name: String) -> VBoxContainer:
	if _tab_boxes.has(tab_name):
		return _tab_boxes[tab_name]
	var scroll := ScrollContainer.new()
	scroll.name = tab_name  # el nombre del hijo es el título de la tab
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_tabs.add_child(scroll)
	_tab_boxes[tab_name] = box
	return box

func add_action(tab_name: String, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(cb)
	_get_tab(tab_name).add_child(btn)

# Un interruptor que muestra su estado; `cb` recibe el nuevo.
func add_toggle(tab_name: String, label: String, pressed: bool, cb: Callable) -> void:
	var check := CheckButton.new()
	check.text = label
	check.button_pressed = pressed
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(cb)
	_get_tab(tab_name).add_child(check)

# Cualquier control armado afuera (un texto que se refresca, un separador…).
func add_control(tab_name: String, control: Control) -> void:
	_get_tab(tab_name).add_child(control)

func add_info(label: String, value: String) -> void:
	var lbl := Label.new()
	lbl.text = "%s: %s" % [label, value]
	_get_tab("Info").add_child(lbl)

func add_text(tab_name: String, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	_get_tab(tab_name).add_child(lbl)

func add_line_edit(tab_name: String, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(200, 0)
	_get_tab(tab_name).add_child(le)
	return le

func toggle() -> void:
	UIState.toggle(UIState.DEBUG)

func is_open() -> bool:
	return UIState.is_open(UIState.DEBUG)

func _on_ui_changed() -> void:
	visible = UIState.is_open(UIState.DEBUG)
