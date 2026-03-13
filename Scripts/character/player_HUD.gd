class_name PlayerHUD
extends CanvasLayer

var _bar_fill: ColorRect
var _max_speed: float = 1.0

static func create(max_speed: float) -> PlayerHUD:
	var hud := PlayerHUD.new()
	hud._max_speed = max_speed

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -80
	panel.offset_right = 80
	panel.offset_top = -40
	panel.offset_bottom = -22

	var border_mat := StyleBoxFlat.new()
	border_mat.bg_color = Color(0, 0, 0, 0)
	border_mat.border_color = Color(1, 1, 0, 1)
	border_mat.border_width_left = 2
	border_mat.border_width_right = 2
	border_mat.border_width_top = 2
	border_mat.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", border_mat)

	var fill := ColorRect.new()
	fill.color = Color(1, 1, 0, 1)
	fill.size = Vector2(0, 14)
	fill.position = Vector2(2, 2)

	panel.add_child(fill)
	hud._bar_fill = fill
	hud.add_child(panel)
	return hud

func update_speed(current_speed: float) -> void:
	var ratio: float = clamp(current_speed / _max_speed, 0.0, 1.0)
	_bar_fill.size.x = ratio * 156.0
