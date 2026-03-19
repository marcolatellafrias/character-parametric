class_name PlayerHUD
extends CanvasLayer

var _bar_fill: ColorRect
var _stamina_bar_fill: ColorRect
var _stability_hud: StabilityHUD
var _max_speed: float = 1.0

static func create(inst: EntityInstantiation) -> PlayerHUD:
	var hud := PlayerHUD.new()
	var arch := inst.arch_final
	var spec := inst.spec
	hud._max_speed = arch.speed * spec.speed_forw_multiplier * 10.0 * arch.sprint_multiplier

	# --- Stamina bar ---
	var stamina_panel := Panel.new()
	stamina_panel.anchor_left = 0.5
	stamina_panel.anchor_right = 0.5
	stamina_panel.anchor_top = 1.0
	stamina_panel.anchor_bottom = 1.0
	stamina_panel.offset_left = -80
	stamina_panel.offset_right = 80
	stamina_panel.offset_top = -56
	stamina_panel.offset_bottom = -44
	var stamina_border := StyleBoxFlat.new()
	stamina_border.bg_color = Color(0, 0, 0, 0)
	stamina_border.border_color = Color(1.0, 0.85, 0.2, 1.0)
	stamina_border.border_width_left = 2
	stamina_border.border_width_right = 2
	stamina_border.border_width_top = 2
	stamina_border.border_width_bottom = 2
	stamina_panel.add_theme_stylebox_override("panel", stamina_border)
	var stamina_fill := ColorRect.new()
	stamina_fill.color = Color(1.0, 0.85, 0.2, 1.0)
	stamina_fill.size = Vector2(156, 8)
	stamina_fill.position = Vector2(2, 2)
	stamina_panel.add_child(stamina_fill)
	hud._stamina_bar_fill = stamina_fill
	hud.add_child(stamina_panel)

	# --- Speed bar ---
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -80
	panel.offset_right = 80
	panel.offset_top = -34
	panel.offset_bottom = -26
	var border_mat := StyleBoxFlat.new()
	border_mat.bg_color = Color(0, 0, 0, 0)
	border_mat.border_color = Color(0.4, 0.85, 1.0, 1.0)
	border_mat.border_width_left = 2
	border_mat.border_width_right = 2
	border_mat.border_width_top = 2
	border_mat.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", border_mat)
	var fill := ColorRect.new()
	fill.color = Color(0.4, 0.85, 1.0, 1.0)
	fill.size = Vector2(0, 4)
	fill.position = Vector2(2, 2)
	panel.add_child(fill)
	hud._bar_fill = fill
	hud.add_child(panel)

	# --- Stability indicators ---
	# Layout: [impacto XZ] [velocidad] [impacto Y]
	# Posicionado encima de las barras, centrado en pantalla
	# Control de 180x72 px, offset_top=-140 offset_bottom=-68
	var stability := StabilityHUD.new()
	stability.anchor_left = 0.5
	stability.anchor_right = 0.5
	stability.anchor_top = 1.0
	stability.anchor_bottom = 1.0
	stability.offset_left = -90.0
	stability.offset_right = 90.0
	stability.offset_top = -140.0
	stability.offset_bottom = -68.0
	hud._stability_hud = stability
	hud.add_child(stability)

	# --- Stats panel ---
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
		"speed     %.1f" % arch.speed,
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

func update_stamina(ratio: float) -> void:
	_stamina_bar_fill.size.x = ratio * 156.0

func update_stability(v_ind: Vector2, imp_xz: Vector2, imp_y: float) -> void:
	if is_instance_valid(_stability_hud):
		_stability_hud.update_stability(v_ind, imp_xz, imp_y)
