class_name ImpactDebugHUD
extends Control

var _impact_xz_world: Vector2 = Vector2.ZERO
var _impact_xz_mag: float = 0.0
var _impact_y: float = 0.0
var _velocity_world: Vector2 = Vector2.ZERO
var _velocity_speed: float = 0.0
var _last_impact_dir: Vector2 = Vector2.ZERO
var _last_impact_magnitude: float = 0.0
var _ragdoll_threshold: float = 0.85
var _max_velocity: float = 1.0
var _ragdoll_active: bool = false
var _ragdoll_recovering: bool = false
var _fall_flash: float = 0.0
var _one_hit_threshold: float = 0.85

var _snapshot_capture_count: int = 0
var _snapshot_flag_at_capture: bool = false
var _snapshot_ragdoll_at_capture: int = 0
var _snapshot_acc_before: float = 0.0
var _snapshot_acc_after: float = 0.0

const FALL_FLASH_DUR := 1.5
const CR    := 26.0
const AH    := 5.0
const OW    := 1.5
const PAD   := 10.0
const FS    := 10
const FS_T  := 12
const W     := 178.0

const C_FG    := Color(0.82, 0.82, 0.82, 0.9)
const C_DIM   := Color(0.36, 0.36, 0.36, 0.8)
const C_WARN  := Color(1.0,  0.55, 0.08, 0.95)
const C_ALERT := Color(1.0,  0.18, 0.18, 1.0)
const C_OK    := Color(0.18, 0.88, 0.35, 0.9)
const C_BG    := Color(0.04, 0.04, 0.04, 0.82)
const C_SEP   := Color(0.22, 0.22, 0.22, 0.9)
const C_THOLD := Color(1.0,  0.45, 0.0,  0.55)

static func create() -> ImpactDebugHUD:
	var hud := ImpactDebugHUD.new()
	hud.anchor_left   = 1.0; hud.anchor_right  = 1.0
	hud.anchor_top    = 0.0; hud.anchor_bottom = 0.0
	hud.offset_left   = -(W + PAD)
	hud.offset_right  = -PAD
	hud.offset_top    = PAD
	hud.offset_bottom = PAD + 460.0
	hud.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	return hud

func notify_fall_triggered() -> void:
	_fall_flash = FALL_FLASH_DUR
	queue_redraw()

func update_impact_debug(
	p_impact_xz: Vector2,
	p_char_basis: Basis,
	p_impact_y: float,
	p_velocity_world: Vector3,
	p_last_impact_dir: Vector3,
	p_ragdoll_threshold: float,
	p_ragdoll_active: bool,
	p_ragdoll_recovering: bool,
	p_last_impact_magnitude: float,
	p_max_velocity: float,
	p_one_hit_threshold: float,
	p_snapshot_capture_count: int,
	p_snapshot_flag_at_capture: bool,
	p_snapshot_ragdoll_at_capture: int,
	p_snapshot_acc_before: float,
	p_snapshot_acc_after: float
) -> void:
	var w := p_char_basis * Vector3(p_impact_xz.x, 0.0, p_impact_xz.y)
	_impact_xz_world = Vector2(w.x, w.z)
	_impact_xz_mag = p_impact_xz.length()
	_impact_y = p_impact_y
	var vxz := Vector2(p_velocity_world.x, p_velocity_world.z)
	_velocity_speed = vxz.length()
	_velocity_world = vxz.normalized() if _velocity_speed > 0.01 else Vector2.ZERO
	_last_impact_dir = Vector2(p_last_impact_dir.x, p_last_impact_dir.z)
	_last_impact_magnitude = p_last_impact_magnitude
	_ragdoll_threshold = p_ragdoll_threshold
	_max_velocity = max(p_max_velocity, 0.001)
	_one_hit_threshold = max(p_one_hit_threshold, 0.001)
	_ragdoll_active = p_ragdoll_active
	_ragdoll_recovering = p_ragdoll_recovering
	_snapshot_capture_count = p_snapshot_capture_count
	_snapshot_flag_at_capture = p_snapshot_flag_at_capture
	_snapshot_ragdoll_at_capture = p_snapshot_ragdoll_at_capture
	_snapshot_acc_before = p_snapshot_acc_before
	_snapshot_acc_after = p_snapshot_acc_after
	queue_redraw()

func _process(delta: float) -> void:
	if _fall_flash > 0.0:
		_fall_flash = max(0.0, _fall_flash - delta)
		queue_redraw()

func _draw() -> void:
	var f := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	var y := PAD

	y = _lbl(f, "IMPACT  DEBUG", y, FS_T, C_FG)
	_sep(y); y += 8.0

	var s_col := C_OK
	var s_txt := "NONE"
	if _ragdoll_active:
		s_txt = "ACTIVE";     s_col = C_ALERT
	elif _ragdoll_recovering:
		s_txt = "RECOVERING"; s_col = C_WARN
	y = _lbl(f, "STATE    " + s_txt, y, FS, s_col)
	var ft := _fall_flash > 0.0
	y = _lbl(f, "FALL     " + ("YES" if ft else "NO"), y, FS, C_ALERT if ft else C_DIM)
	y += 4.0; _sep(y); y += 8.0

	y = _lbl(f, "ACCUMULATOR", y, FS, C_DIM)
	var cy1 := y + CR; var cx1 := PAD + CR
	_world_circle(Vector2(cx1, cy1), _impact_xz_world, _impact_xz_mag, 1.0, _ragdoll_threshold)
	_y_bar(Vector2(cx1 + CR + PAD + 2.0, cy1), _impact_y)
	var mc := C_WARN if _impact_xz_mag >= _ragdoll_threshold else C_FG
	var bx := cx1 + CR + PAD + 18.0
	draw_string(f, Vector2(bx, cy1 - 12.0), "xz  %.2f" % _impact_xz_mag, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, mc)
	draw_string(f, Vector2(bx, cy1 + 2.0),  "y   %.2f" % _impact_y,      HORIZONTAL_ALIGNMENT_LEFT, -1, FS, C_FG)
	draw_string(f, Vector2(bx, cy1 + 16.0), "thr %.2f" % _ragdoll_threshold, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, C_DIM)
	y += CR * 2.0 + 6.0; _sep(y); y += 8.0

	y = _lbl(f, "LAST IMPACT", y, FS, C_DIM)
	var cy2 := y + CR; var cx2 := PAD + CR
	_world_circle(Vector2(cx2, cy2), _last_impact_dir, _last_impact_magnitude, _ragdoll_threshold, _ragdoll_threshold)
	var bx2 := cx2 + CR + PAD + 18.0
	draw_string(f, Vector2(bx2, cy2 - 4.0), "mag %.2f" % _last_impact_magnitude, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, C_FG)
	y += CR * 2.0 + 6.0; _sep(y); y += 8.0

	y = _lbl(f, "VELOCITY", y, FS, C_DIM)
	var cy3 := y + CR; var cx3 := PAD + CR
	_world_circle(Vector2(cx3, cy3), _velocity_world, _velocity_speed, _max_velocity, -1.0)
	draw_string(f, Vector2(cx3 - 3.0, cy3 - CR - 3.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, FS, C_DIM)
	draw_string(f, Vector2(cx3 + CR + PAD + 2.0, cy3 - 4.0), "spd %.1f" % _velocity_speed,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS, C_FG)
	draw_string(f, Vector2(cx3 + CR + PAD + 2.0, cy3 + 10.0), "max %.1f" % _max_velocity,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS, C_DIM)
	y += CR * 2.0 + PAD; _sep(y); y += 8.0

	y = _lbl(f, "SNAPSHOT  META", y, FS_T, C_FG)
	y += 2.0
	var rc_txt: String
	var rc_col: Color
	match _snapshot_ragdoll_at_capture:
		0: rc_txt = "NONE";    rc_col = C_OK
		1: rc_txt = "ACTIVE";  rc_col = C_ALERT
		2: rc_txt = "RECOVER"; rc_col = C_WARN
		_: rc_txt = "?";       rc_col = C_DIM
	var fc := C_OK if _snapshot_flag_at_capture else C_ALERT
	y = _lbl(f, "flag     " + ("TRUE" if _snapshot_flag_at_capture else "FALSE"), y, FS, fc)
	y = _lbl(f, "ragdoll  " + rc_txt, y, FS, rc_col)
	y = _lbl(f, "count    %d" % _snapshot_capture_count, y, FS, C_FG)
	y += 2.0
	var before_col := C_WARN if _snapshot_acc_before > 0.3 else C_FG
	y = _lbl(f, "acc bef  %.2f" % _snapshot_acc_before, y, FS, before_col)
	_lbl(f, "acc aft  %.2f" % _snapshot_acc_after, y, FS, C_ALERT)

func _world_circle(center: Vector2, dir: Vector2, magnitude: float, scale: float, threshold: float) -> void:
	var t := magnitude / scale
	var ring_col := C_DIM
	if threshold > 0.0:
		var t_norm := t / (threshold / scale)
		ring_col = C_DIM.lerp(C_ALERT, clamp(t_norm, 0.0, 1.0))
	draw_arc(center, CR, 0.0, TAU, 48, ring_col, OW, true)
	if threshold > 0.0 and threshold < scale:
		var ring_r := CR * (threshold / scale)
		draw_arc(center, ring_r, 0.0, TAU, 36, C_THOLD, OW, true)
	draw_line(center + Vector2(0.0, -(CR - 4.0)), center + Vector2(0.0, -CR), C_DIM, OW)
	_arrow_scaled(center, dir, t)

func _arrow_scaled(center: Vector2, dir: Vector2, t: float) -> void:
	if dir.length_squared() < 0.0001:
		draw_circle(center, 2.5, C_DIM)
		return
	var dn := dir.normalized()
	var tip : Vector2 = center + dn * CR * clamp(t, 0.0, 1.2)
	var col := C_ALERT if t > 1.0 else C_FG
	draw_line(center, tip, col, OW, true)
	var perp := Vector2(-dn.y, dn.x)
	draw_line(tip, tip - dn * AH + perp * (AH * 0.5), col, OW, true)
	draw_line(tip, tip - dn * AH - perp * (AH * 0.5), col, OW, true)

func _y_bar(center: Vector2, value: float) -> void:
	var bh := CR * 1.8
	draw_line(center + Vector2(0.0, -bh * 0.5), center + Vector2(0.0, bh * 0.5), C_DIM, OW)
	draw_line(center + Vector2(-3.0, 0.0), center + Vector2(3.0, 0.0), C_DIM, OW)
	var dy : float = center.y - clamp(value, -1.0, 1.0) * bh * 0.5
	draw_circle(Vector2(center.x, dy), 3.0, C_FG)

func _lbl(f: Font, text: String, y: float, fs: int, col: Color) -> float:
	draw_string(f, Vector2(PAD, y + fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return y + fs + 5.0

func _sep(y: float) -> void:
	draw_line(Vector2(PAD, y), Vector2(W - PAD, y), C_SEP, 1.0)
