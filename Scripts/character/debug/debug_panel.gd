class_name DebugPanel
extends CanvasLayer

# Panel de debug con tabs (Info / Acciones / Arquetipos / Spawn). Se registra desde afuera vía
# add_info / add_text / add_action; el panel solo renderiza. Su visibilidad y el mouse
# los maneja UIState (tecla F1). Solo se crea para un personaje con debug_enabled = true.
# La consola global (tecla º) es aparte. Ver technical/ui.md.

var _tabs: TabContainer
var _tab_boxes: Dictionary = {}  # tab_name -> VBoxContainer

func _ready() -> void:
	layer = 100
	visible = false
	UIState.changed.connect(_on_ui_changed)

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(300, 380)
	add_child(panel)

	_tabs = TabContainer.new()
	panel.add_child(_tabs)

	# Orden fijo de las tabs.
	for tab_name in ["Info", "Acciones", "Arquetipos", "Spawn"]:
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
