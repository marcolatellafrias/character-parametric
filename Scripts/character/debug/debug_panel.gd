class_name DebugPanel
extends CanvasLayer

# Data-driven debug/creative panel (Gmod-style). Actions are registered from the
# outside via add_action(category, label, callable); the panel just renders them.
# Only spawned when a character has debug_enabled = true (see BoneInstantiator / PlayerController).

var _vbox: VBoxContainer = null
var _categories: Dictionary = {}
var _open: bool = false

func _ready() -> void:
	layer = 100
	visible = false

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	_vbox = VBoxContainer.new()
	margin.add_child(_vbox)

	var title := Label.new()
	title.text = "DEBUG PANEL"
	_vbox.add_child(title)

func add_action(category: String, label: String, cb: Callable) -> void:
	var box := _get_category(category)
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(cb)
	box.add_child(btn)

func add_info(label: String, value: String) -> void:
	var box := _get_category("Info")
	var lbl := Label.new()
	lbl.text = "%s: %s" % [label, value]
	box.add_child(lbl)

func _get_category(cat: String) -> VBoxContainer:
	if _categories.has(cat):
		return _categories[cat]
	var lbl := Label.new()
	lbl.text = "— %s —" % cat
	_vbox.add_child(lbl)
	var box := VBoxContainer.new()
	_vbox.add_child(box)
	_categories[cat] = box
	return box

func toggle() -> void:
	_open = not _open
	visible = _open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _open else Input.MOUSE_MODE_CAPTURED

func is_open() -> bool:
	return _open
