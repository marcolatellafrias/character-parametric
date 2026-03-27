class_name StabilityHUD
extends Control

var velocity_indicator: Vector2 = Vector2.ZERO
var impact_xz: Vector2 = Vector2.ZERO
var impact_y: float = 0.0

const CIRCLE_RADIUS := 24.0
const DOT_RADIUS := 3.5
const LINE_HALF_HEIGHT := 24.0
const LINE_TICK_SIZE := 6.0
const OUTLINE_WIDTH := 1.5
const WHITE := Color(0.038, 0.038, 0.038, 0.85)

# Centros de cada indicador dentro del control (coordenadas locales)
const CENTER_Y := 36.0
const LEFT_CX := 28.0   # impacto XZ
const MID_CX  := 90.0   # velocidad
const RIGHT_CX := 152.0 # impacto Y

func update_stability(v_ind: Vector2, imp_xz: Vector2, imp_y: float) -> void:
	velocity_indicator = v_ind
	impact_xz = imp_xz
	impact_y = imp_y
	queue_redraw()

func _draw() -> void:
	_draw_circle_indicator(Vector2(LEFT_CX, CENTER_Y), impact_xz)
	_draw_circle_indicator(Vector2(MID_CX, CENTER_Y), velocity_indicator)
	_draw_line_indicator(Vector2(RIGHT_CX, CENTER_Y))

func _draw_circle_indicator(center: Vector2, value: Vector2) -> void:
	draw_arc(center, CIRCLE_RADIUS, 0.0, TAU, 48, WHITE, OUTLINE_WIDTH, true)
	var dot := center + value.limit_length(1.0) * CIRCLE_RADIUS
	draw_circle(dot, DOT_RADIUS, WHITE)

func _draw_line_indicator(center: Vector2) -> void:
	draw_line(center + Vector2(0.0, -LINE_HALF_HEIGHT), center + Vector2(0.0, LINE_HALF_HEIGHT), WHITE, OUTLINE_WIDTH)
	# tick central de referencia
	draw_line(
		center + Vector2(-LINE_TICK_SIZE * 0.5, 0.0),
		center + Vector2( LINE_TICK_SIZE * 0.5, 0.0),
		WHITE, OUTLINE_WIDTH
	)
	var dot_y : float = center.y - clamp(impact_y, -1.0, 1.0) * LINE_HALF_HEIGHT
	draw_circle(Vector2(center.x, dot_y), DOT_RADIUS, WHITE)
