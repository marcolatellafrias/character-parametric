class_name FPSGraph
extends CanvasLayer

@export var enabled: bool = true
@export var target_fps: float = 60.0

const HISTORY_SIZE := 200
const GRAPH_W := 220
const GRAPH_H := 80

var _fps_history: Array[float] = []
var _label: Label
var _graph: Control

func _ready() -> void:
	if not enabled:
		visible = false
		set_process(false)
		return
	_build_ui()

func _build_ui() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.corner_radius_top_left = 4
	bg.corner_radius_bottom_right = 4

	var panel := Panel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -(GRAPH_W + 20)
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = 10 + GRAPH_H + 36
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.offset_left = 8
	_label.offset_top = 6
	_label.offset_right = GRAPH_W + 12
	_label.offset_bottom = 24
	panel.add_child(_label)

	_graph = Control.new()
	_graph.offset_left = 8
	_graph.offset_top = 28
	_graph.offset_right = 8 + GRAPH_W
	_graph.offset_bottom = 28 + GRAPH_H
	_graph.draw.connect(_draw_graph)
	panel.add_child(_graph)

func _process(_delta: float) -> void:
	var fps := float(Engine.get_frames_per_second())
	_fps_history.append(fps)
	if _fps_history.size() > HISTORY_SIZE:
		_fps_history.pop_front()
	var min_fps: float = _fps_history.min()
	_label.text = "fps  %d   min %d   target %d" % [int(fps), int(min_fps), int(target_fps)]
	_graph.queue_redraw()

func _draw_graph() -> void:
	if _fps_history.is_empty():
		return
	var w := float(GRAPH_W)
	var h := float(GRAPH_H)
	var max_fps: float = maxf(target_fps, _fps_history.max())

	# target fps line
	var target_y := h - (target_fps / max_fps) * h
	_graph.draw_line(Vector2(0.0, target_y), Vector2(w, target_y), Color(1, 1, 1, 0.3), 1.0)

	var count := _fps_history.size()
	var bar_w := w / float(HISTORY_SIZE)
	for i in count:
		var val := _fps_history[i]
		var bar_h := (val / max_fps) * h
		var x := float(HISTORY_SIZE - count + i) * bar_w
		var ratio := val / target_fps
		var col: Color
		if ratio >= 1.0:
			col = Color(0.3, 0.9, 0.4, 0.85)
		elif ratio >= 0.75:
			col = Color(1.0, 0.8, 0.2, 0.85)
		else:
			col = Color(1.0, 0.3, 0.2, 0.85)
		_graph.draw_rect(Rect2(x, h - bar_h, maxf(bar_w - 1.0, 1.0), bar_h), col)
