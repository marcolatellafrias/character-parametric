class_name PlayerHUD
extends CanvasLayer

var _bar_fill: ColorRect
var _max_speed: float = 1.0

static func create(max_speed: float, inst: EntityInstantiation) -> PlayerHUD:
	var hud := PlayerHUD.new()
	hud._max_speed = max_speed

	# --- Barra de velocidad (existente) ---
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

	# --- Panel de stats (nuevo) ---
	var arch := inst.arch_final
	var primary_str := str(EntityArchetype.Archetype.keys()[inst.archetype_type])
	var secondary_str := ""
	if inst.archetype_blend > 0.0:
		secondary_str = "secondary  %s (%.0f%%)" % [
			str(EntityArchetype.Archetype.keys()[inst.secondary_archetype_type]),
			inst.archetype_blend * 100
		]

	var lines := [
		"seed      %d" % inst.master_seed,
		"arch      %s" % primary_str,
		secondary_str if secondary_str != "" else "arch      (no blend)",
		"%s  |  age %d" % [EntitySpecie.Specie.keys()[inst.specie_type], inst.age],
		"",
		"height    %.2f m" % arch.height,
		"weight    %.1f kg" % arch.weight,
		"speed     %.1f" % arch.speed_forw,
		"strength  %.2f" % arch.strenght,
		"jump      %.2f" % arch.jump_strenght,
		"reach     %.2f" % arch.reach,
		"fatness   %.2f" % arch.fatness,
		"muscle    %.2f" % arch.muscularity,
	]

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.corner_radius_top_left = 4
	bg.corner_radius_bottom_right = 4

	var stats_panel := Panel.new()
	stats_panel.anchor_left = 0.0
	stats_panel.anchor_top = 0.0
	stats_panel.offset_left = 10
	stats_panel.offset_top = 10
	stats_panel.offset_right = 210
	stats_panel.offset_bottom = 10 + lines.size() * 22 + 14
	stats_panel.add_theme_stylebox_override("panel", bg)

	var label := Label.new()
	label.text = "\n".join(lines)
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.offset_left = 10
	label.offset_top = 7
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_font_size_override("font_size", 13)

	stats_panel.add_child(label)
	hud.add_child(stats_panel)

	return hud

func update_speed(current_speed: float) -> void:
	var ratio: float = clamp(current_speed / _max_speed, 0.0, 1.0)
	_bar_fill.size.x = ratio * 156.0
