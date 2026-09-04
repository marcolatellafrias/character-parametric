class_name StyleLab
extends CanvasLayer

## LABORATORIO DE ESTILO — TEMPORAL. Se borra entero cuando el look esté cerrado.
##
## Panel para tunear el shader de personaje y las máscaras de vertex paint EN VIVO, sin recompilar ni
## reiniciar. Existe porque encontrar un estilo es un problema de iteración, no de cálculo: hay que ver
## veinte variantes, no despejar una.
##
## ── POR QUÉ ES UN PANEL APARTE Y NO UNA TAB MÁS ───────────────────────────────────────────────────
## `DebugPanel` es una lista de botones (`add_action` / `add_text`). Esto necesita sliders, pickers y
## valores en vivo — otro vocabulario de widgets. Y sobre todo: esto **se va a borrar**. Aparte se saca
## con una línea y una carpeta; adentro habría que ir sacándole pedazos.
##
## Para borrarlo: esta carpeta + la línea que lo instancia en `player_controller.gd` + `COLOR_OVERRIDE`
## y `material_for_role` en `character_appearance.gd`.
##
## ── CÓMO ESCRIBE ──────────────────────────────────────────────────────────────────────────────────
## Directo sobre el `ShaderMaterial` cacheado por rol. Hay **uno por rol para toda la ciudad**, así que
## mover un slider se ve al instante en todos los personajes sin repintar nada ni tocar los nodos.
##
## El COLOR es la excepción: no es un uniform del material sino un `instance uniform` por personaje, así
## que va por `CharacterAppearance.COLOR_OVERRIDE` y sí necesita un repintado.

const LAYER := "style_lab"
const PRESETS_PATH := "user://style_lab_presets.json"

## Los roles que se pueden tunear. `PROP` queda afuera: no se tiñe ni se sombrea.
const ROLES := {
	"Piel": CharacterAppearance.Role.SKIN,
	"Ropa": CharacterAppearance.Role.CLOTH,
	"Pelo": CharacterAppearance.Role.HAIR,
	"Cuero": CharacterAppearance.Role.LEATHER,
}

## LA TABLA MANDA. Agregar un uniform al shader es agregar UNA fila acá — no hay código de UI que tocar.
##
## `type`: "float" o "color". El resto de las claves son el rango del slider.
const PARAMS: Array[Dictionary] = [
	{"group": "Terminador"},
	{"name": "light_wrap", "label": "Wrap (0 = estándar)", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "light_bias", "label": "Corrimiento", "type": "float", "min": -0.5, "max": 0.5},

	{"group": "Sombra"},
	{"name": "shadow_value", "label": "Brillo (0 = negra)", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "shadow_saturation", "label": "Saturación", "type": "float", "min": 0.0, "max": 2.0},
	{"name": "shadow_hue", "label": "Tono", "type": "color"},
	{"name": "shadow_hue_amount", "label": "Cuánto tono", "type": "float", "min": 0.0, "max": 1.0},

	{"group": "Luz"},
	{"name": "ambient_amount", "label": "Ambiente (baja = negro)", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "light_value", "label": "Brillo (1 = albedo)", "type": "float", "min": 0.0, "max": 2.0},
	{"name": "light_saturation", "label": "Saturación", "type": "float", "min": 0.0, "max": 2.0},
	{"name": "light_hue", "label": "Tono", "type": "color"},
	{"name": "light_hue_amount", "label": "Cuánto tono", "type": "float", "min": 0.0, "max": 1.0},

	{"group": "Máscaras de vértice"},
	{"name": "mask_shadow_grad", "label": "R · sombra degradé", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "mask_shadow_paint", "label": "G · sombra pintada", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "mask_shadow_desat", "label": "R+G · desaturación", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "mask_b_amount", "label": "B · cuánto", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "mask_b_color", "label": "B · color (flush / mancha)", "type": "color"},
	{"name": "mask_a_amount", "label": "A · cuánto", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "mask_a_color", "label": "A · color (desteñido)", "type": "color"},

	{"group": "Ruido"},
	{"name": "noise_amount", "label": "Brillo", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "noise_saturation", "label": "Saturación", "type": "float", "min": 0.0, "max": 2.0},
	{"name": "noise_scale", "label": "Escala", "type": "float", "min": 1.0, "max": 300.0},
	{"name": "noise_scale_x", "label": "Escala X (vetas)", "type": "float", "min": 0.05, "max": 20.0},
	{"name": "noise_scale_y", "label": "Escala Y (vetas)", "type": "float", "min": 0.05, "max": 20.0},
	{"name": "noise_space", "label": "0 = UV (anclado) · 1 = modelo", "type": "float", "min": 0.0, "max": 1.0},

	{"group": "Extras (apagados por default)"},
	{"name": "band_amount", "label": "Bandas", "type": "float", "min": 0.0, "max": 1.0},
	{"name": "band_softness", "label": "Suavidad de banda", "type": "float", "min": 0.01, "max": 1.0},
	{"name": "rim_strength", "label": "Rim", "type": "float", "min": 0.0, "max": 2.0},
	{"name": "rim_power", "label": "Rim: cierre", "type": "float", "min": 0.5, "max": 8.0},
]

var _role_name: String = "Piel"
var _controls: Dictionary = {}            # uniform -> Control
var _value_labels: Dictionary = {}        # uniform -> Label
var _color_button: ColorPickerButton
var _preset_list: OptionButton
var _preset_name: LineEdit
var _presets: Dictionary = {}
## Los dos que alterna el botón A/B. Comparar es el cuello de botella real al tunear: dos looks
## parecidos vistos con diez segundos de diferencia se confunden; alternándolos al instante, no.
var _ab: Array[String] = ["", ""]
var _ab_current := 0


func _ready() -> void:
	layer = 101  # arriba del DebugPanel
	visible = false
	UIState.changed.connect(func(): visible = UIState.is_open(LAYER))
	_load_presets()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	UIState.toggle(LAYER)
	if UIState.is_open(LAYER):
		# No se puede tunear un shader que no se está usando: el modo plano lo puentea entero.
		CharacterAppearance.FLAT_GEOMETRY = false
		CharacterAppearance.reapply_all(get_tree())
		_pull_from_material()


# ── Construcción de la UI ─────────────────────────────────────────────────────────────────────────

func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(340, 20)
	panel.custom_minimum_size = Vector2(340, 620)
	add_child(panel)

	var root := VBoxContainer.new()
	panel.add_child(root)

	var title := Label.new()
	title.text = "STYLE LAB  (F2)"
	root.add_child(title)

	# Selector de rol. "Todos" escribe en los cuatro a la vez, que es como se arranca: mover algo
	# global y después diferenciar.
	var role_row := HBoxContainer.new()
	role_row.add_child(_label("Material"))
	var roles := OptionButton.new()
	roles.add_item("Todos")
	for r in ROLES:
		roles.add_item(r)
	roles.selected = 1
	roles.item_selected.connect(func(i: int):
		_role_name = "Todos" if i == 0 else roles.get_item_text(i)
		_pull_from_material())
	role_row.add_child(roles)
	root.add_child(role_row)

	# Color base del material. Va por COLOR_OVERRIDE, no por el shader.
	var col_row := HBoxContainer.new()
	col_row.add_child(_label("Color base"))
	_color_button = ColorPickerButton.new()
	_color_button.custom_minimum_size = Vector2(80, 24)
	_color_button.color_changed.connect(_on_base_color)
	col_row.add_child(_color_button)
	root.add_child(col_row)

	# Ver una máscara aislada. Es la contraparte de no poder verlas separadas en Blender.
	var mask_row := HBoxContainer.new()
	mask_row.add_child(_label("Ver máscara"))
	var masks := OptionButton.new()
	for m in ["off", "R grad", "G pintada", "B tinte", "A tinte"]:
		masks.add_item(m)
	masks.item_selected.connect(func(i: int): _write_all("debug_mask", i))
	mask_row.add_child(masks)
	root.add_child(mask_row)

	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	for p in PARAMS:
		if p.has("group"):
			var g := Label.new()
			g.text = "── " + str(p["group"])
			box.add_child(g)
			continue
		if p["type"] == "float":
			_add_slider(box, p)
		else:
			_add_color(box, p)

	root.add_child(HSeparator.new())
	_build_presets(root)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(120, 0)
	return l


func _add_slider(box: VBoxContainer, p: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(str(p["label"])))
	var s := HSlider.new()
	s.min_value = p["min"]
	s.max_value = p["max"]
	s.step = 0.001
	s.custom_minimum_size = Vector2(140, 0)
	var v := Label.new()
	v.custom_minimum_size = Vector2(48, 0)
	var uniform := str(p["name"])
	s.value_changed.connect(func(val: float):
		v.text = "%.3f" % val
		_write_all(uniform, val))
	row.add_child(s)
	row.add_child(v)
	box.add_child(row)
	_controls[uniform] = s
	_value_labels[uniform] = v


func _add_color(box: VBoxContainer, p: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(str(p["label"])))
	var c := ColorPickerButton.new()
	c.custom_minimum_size = Vector2(80, 24)
	var uniform := str(p["name"])
	c.color_changed.connect(func(col: Color): _write_all(uniform, col))
	row.add_child(c)
	box.add_child(row)
	_controls[uniform] = c


# ── Escritura y lectura de los materiales ─────────────────────────────────────────────────────────

func _roles_in_scope() -> Array:
	if _role_name == "Todos":
		return ROLES.values()
	return [ROLES[_role_name]]


func _write_all(uniform: String, value: Variant) -> void:
	for role in _roles_in_scope():
		CharacterAppearance.material_for_role(role).set_shader_parameter(uniform, value)


## Trae los valores del material al panel. Se llama al abrir y al cambiar de rol, así los controles
## nunca mienten sobre lo que está puesto.
##
## Con "Todos" se muestra el primer rol: no hay un valor único que mostrar, y mentir con un cero sería
## peor que mostrar uno de los cuatro.
func _pull_from_material() -> void:
	var role = _roles_in_scope()[0]
	var mat := CharacterAppearance.material_for_role(role)
	for p in PARAMS:
		if p.has("group"):
			continue
		var uniform := str(p["name"])
		var value = mat.get_shader_parameter(uniform)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), uniform)
		if value == null:
			continue
		var ctrl = _controls.get(uniform)
		if ctrl is HSlider:
			ctrl.set_value_no_signal(value)
			_value_labels[uniform].text = "%.3f" % value
		elif ctrl is ColorPickerButton:
			ctrl.color = value
	if _role_name != "Todos":
		_color_button.color = CharacterAppearance.COLOR_OVERRIDE.get(role, Color.WHITE)


func _on_base_color(col: Color) -> void:
	for role in _roles_in_scope():
		CharacterAppearance.COLOR_OVERRIDE[role] = col
	# El color es `instance uniform`: vive por personaje, no en el material, así que sí hay que repintar.
	CharacterAppearance.reapply_all(get_tree())


# ── Presets ───────────────────────────────────────────────────────────────────────────────────────

func _build_presets(root: VBoxContainer) -> void:
	var save_row := HBoxContainer.new()
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "nombre"
	_preset_name.custom_minimum_size = Vector2(150, 0)
	save_row.add_child(_preset_name)
	var save := Button.new()
	save.text = "Guardar"
	save.pressed.connect(_save_current)
	save_row.add_child(save)
	root.add_child(save_row)

	var load_row := HBoxContainer.new()
	_preset_list = OptionButton.new()
	_preset_list.custom_minimum_size = Vector2(150, 0)
	load_row.add_child(_preset_list)
	var load_btn := Button.new()
	load_btn.text = "Cargar"
	load_btn.pressed.connect(func():
		if _preset_list.selected >= 0:
			_apply_preset(_preset_list.get_item_text(_preset_list.selected)))
	load_row.add_child(load_btn)
	root.add_child(load_row)

	var ab_row := HBoxContainer.new()
	var set_a := Button.new()
	set_a.text = "→A"
	set_a.pressed.connect(func(): _ab[0] = _selected_preset())
	var set_b := Button.new()
	set_b.text = "→B"
	set_b.pressed.connect(func(): _ab[1] = _selected_preset())
	var swap := Button.new()
	swap.text = "A / B"
	swap.pressed.connect(func():
		_ab_current = 1 - _ab_current
		if _ab[_ab_current] != "":
			_apply_preset(_ab[_ab_current]))
	ab_row.add_child(set_a)
	ab_row.add_child(set_b)
	ab_row.add_child(swap)
	root.add_child(ab_row)

	_refresh_preset_list()


func _selected_preset() -> String:
	if _preset_list.selected < 0:
		return ""
	return _preset_list.get_item_text(_preset_list.selected)


## Un preset guarda los CUATRO roles enteros, no solo el que estás editando: un look es la relación
## entre los materiales, y guardar uno solo daría combinaciones que nunca existieron.
func _save_current() -> void:
	var name := _preset_name.text.strip_edges()
	if name.is_empty():
		return
	var data := {}
	for role_name in ROLES:
		var role = ROLES[role_name]
		var mat := CharacterAppearance.material_for_role(role)
		var vals := {}
		for p in PARAMS:
			if p.has("group"):
				continue
			var uniform := str(p["name"])
			var v = mat.get_shader_parameter(uniform)
			if v == null:
				continue
			vals[uniform] = ("#" + (v as Color).to_html(false)) if p["type"] == "color" else float(v)
		if CharacterAppearance.COLOR_OVERRIDE.has(role):
			vals["_base"] = "#" + CharacterAppearance.COLOR_OVERRIDE[role].to_html(false)
		data[role_name] = vals
	_presets[name] = data
	_write_presets()
	_refresh_preset_list()
	print("[StyleLab] guardado '%s'" % name)


func _apply_preset(name: String) -> void:
	var data = _presets.get(name)
	if data == null:
		return
	for role_name in data:
		if not ROLES.has(role_name):
			continue
		var role = ROLES[role_name]
		var mat := CharacterAppearance.material_for_role(role)
		for uniform in data[role_name]:
			var raw = data[role_name][uniform]
			var value = Color.from_string(str(raw), Color.WHITE) if raw is String else float(raw)
			if uniform == "_base":
				CharacterAppearance.COLOR_OVERRIDE[role] = value
			else:
				mat.set_shader_parameter(uniform, value)
	CharacterAppearance.reapply_all(get_tree())
	_pull_from_material()


func _refresh_preset_list() -> void:
	_preset_list.clear()
	for name in _presets:
		_preset_list.add_item(name)


## En `user://`, no en el repo: son pruebas, no arte cerrado. Cuando encuentres el look, el preset se
## copia a mano a `_material_for` y a `AppearancePreset.PRESETS`, que es donde vive lo definitivo.
func _load_presets() -> void:
	if not FileAccess.file_exists(PRESETS_PATH):
		return
	var f := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_presets = parsed


func _write_presets() -> void:
	var f := FileAccess.open(PRESETS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_presets, "\t"))
