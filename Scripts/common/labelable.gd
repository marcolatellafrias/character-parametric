@tool
extends Node3D

@export var label_text: String = "Label" : set = _set_text
@export var vertical_offset: float = 1.0 : set = _set_offset
@export var font_size: int = 64 : set = _set_font_size

var _label: Label3D

func _ready() -> void:
	_label = Label3D.new()
	_label.text = label_text
	_label.font_size = font_size
	_label.outline_size = 4
	_label.outline_modulate = Color.BLACK
	_label.modulate = Color.WHITE
	_label.position.y = vertical_offset
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 100
	add_child(_label)

func _set_text(value: String) -> void:
	label_text = value
	if _label:
		_label.text = value

func _set_offset(value: float) -> void:
	vertical_offset = value
	if _label:
		_label.position.y = value

func _set_font_size(value: int) -> void:
	font_size = value
	if _label:
		_label.font_size = value
