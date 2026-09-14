class_name PropertyTuner
extends RefCounted

## ARMA UN AFINADOR LEYENDO LAS PROPIEDADES EXPORTADAS DE UN OBJETO. No sabe de clima ni de nubes: le
## pasas un objeto con `@export`s y te devuelve un control por propiedad, ya conectado.
##
## Existe para que no pueda volver a pasar lo que pasaba antes: los controles se escribian a mano, uno
## por uno, y varios quedaron apuntando a campos que ya no se aplicaban —perillas que no hacian nada—.
## Aca no hay lista a mano: lo que se ve es lo que el objeto expone, y lo que se toca es lo que se aplica.
##
## Todo entra por un `spec`, un Diccionario con:
##   target     el objeto a afinar
##   include    nombres de grupo a mostrar; vacio muestra todo. Filtra por el grupo mas interno: si la
##              propiedad esta en un subgrupo manda el subgrupo, si no manda el grupo.
##   skip       nombres de propiedad que maneja el juego y no la mano
##   ranges     nombre de propiedad -> [min, max] que reemplaza al declarado, SOLO para el slider: el
##              valor guardado no se toca. Es para cuando el `@export_range` de un addon es honesto
##              para su escala y absurdo para la nuestra
##   help       nombre de propiedad -> una linea de que hace, que se dibuja debajo del control
##   on_change  se llama despues de cada escritura; puede ser vacia si el objeto se relee solo
##
## `dump()` usa el mismo spec, asi lo que se copia al portapapeles no puede desincronizarse de lo que se
## ve. El formato es `nombre = valor` de GDScript, que tambien es el de un `.tres`: se pega tal cual en
## el archivo de donde salio.

const GROUP_COLOR := Color(0.55, 0.55, 0.55)
const HELP_COLOR := Color(0.62, 0.66, 0.72)
const HELP_FONT_SIZE := 11
const NAME_WIDTH := 200.0

## Un slider lineal sobre un rango de 100 a 1.000.000 es inusable: toda la banda que sirve a escala de
## ciudad vive en el primer medio por ciento del recorrido. Cuando el rango llega a cuatro cifras Y
## abarca dos ordenes de magnitud o mas, el slider guarda un `t` de 0 a 1 y el valor se mapea con una
## curva. El archivo sigue guardando el numero real: la curva es solo como se lo agarra.
const CURVED_MIN_MAX := 1000.0
const CURVED_RATIO := 100.0

## Los unicos tipos que saben afinarse a mano. Todo lo demas que un objeto exporte —texturas, shaders,
## arrays, vectores— se ignora, que es lo que deja que `include` sea generoso sin llenar el panel.
const TUNABLE := [TYPE_BOOL, TYPE_COLOR, TYPE_FLOAT, TYPE_INT]


## Un control por propiedad, dentro de `box`.
static func build(box: VBoxContainer, spec: Dictionary) -> void:
	var target: Object = spec["target"]
	var help: Dictionary = spec.get("help", {})
	var on_change: Callable = spec.get("on_change", Callable())
	var group := ""
	for prop in _properties(spec):
		var section := str(prop["group"])
		if section != group:
			group = section
			var header := Label.new()
			header.text = "── " + group
			header.add_theme_color_override("font_color", GROUP_COLOR)
			box.add_child(header)

		var prop_name := str(prop["name"])
		var label := Label.new()
		label.text = prop_name
		label.custom_minimum_size = Vector2(NAME_WIDTH, 0.0)
		var row := HBoxContainer.new()
		row.add_child(label)
		var control := _control(spec, prop, label)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
		box.add_child(row)

		if help.has(prop_name):
			var note := Label.new()
			note.text = str(help[prop_name])
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			note.add_theme_color_override("font_color", HELP_COLOR)
			note.add_theme_font_size_override("font_size", HELP_FONT_SIZE)
			box.add_child(note)


## Las mismas propiedades como texto pegable.
static func dump(spec: Dictionary) -> String:
	var target: Object = spec["target"]
	var lines := PackedStringArray()
	for prop in _properties(spec):
		lines.append("%s = %s" % [prop["name"], var_to_str(target.get(prop["name"]))])
	return "\n".join(lines)


# ── Lectura de la lista de propiedades ───────────────────────────────────────────────────────────

## Las propiedades exportadas que pasan el filtro, cada una con el grupo en el que cayo. El grupo se
## arrastra de los marcadores que Godot intercala en la lista; un grupo nuevo borra el subgrupo.
static func _properties(spec: Dictionary) -> Array[Dictionary]:
	var target: Object = spec["target"]
	var include: PackedStringArray = spec.get("include", PackedStringArray())
	var skip: PackedStringArray = spec.get("skip", PackedStringArray())
	var out: Array[Dictionary] = []
	var group := ""
	var subgroup := ""
	for prop in target.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_GROUP:
			group = str(prop["name"])
			subgroup = ""
			continue
		if usage & PROPERTY_USAGE_SUBGROUP:
			subgroup = str(prop["name"])
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var section := subgroup if not subgroup.is_empty() else group
		if not include.is_empty() and not include.has(section):
			continue
		if skip.has(str(prop["name"])):
			continue
		# Los tipos que no se afinan a mano (texturas, shaders, arrays, vectores) se caen ACA y no en el
		# armado de controles, para que `build` y `dump` vean exactamente la misma lista: si no, el boton
		# de copiar escupe cosas que el panel no muestra y que no se pegan en ningun lado.
		if not TUNABLE.has(int(prop["type"])):
			continue
		out.append({"name": prop["name"], "type": prop["type"], "hint": prop["hint"],
			"hint_string": prop["hint_string"], "group": section})
	return out


# ── Armado de controles ──────────────────────────────────────────────────────────────────────────

## El control que le corresponde al tipo (`_properties` ya garantizo que es uno de `TUNABLE`). `label`
## muestra el valor vivo al lado del nombre.
static func _control(spec: Dictionary, prop: Dictionary, label: Label) -> Control:
	var target: Object = spec["target"]
	var on_change: Callable = spec.get("on_change", Callable())
	var prop_name := str(prop["name"])
	var type := int(prop["type"])
	if type == TYPE_BOOL:
		var check := CheckButton.new()
		check.button_pressed = bool(target.get(prop_name))
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(func(on: bool) -> void: _write(target, prop_name, on, on_change))
		return check
	if type == TYPE_COLOR:
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(0.0, 24.0)
		picker.color = target.get(prop_name)
		picker.color_changed.connect(func(c: Color) -> void: _write(target, prop_name, c, on_change))
		return picker
	if int(prop["hint"]) == PROPERTY_HINT_ENUM:
		var options := OptionButton.new()
		for item in str(prop["hint_string"]).split(","):
			options.add_item(item)
		options.selected = int(target.get(prop_name))
		options.item_selected.connect(func(i: int) -> void: _write(target, prop_name, i, on_change))
		return options

	# Sin rango declarado va un campo con flechas: inventarle un maximo a algo como `cloud_ceiling`
	# seria mentir, y un slider necesita dos extremos.
	var limits := _range(prop, spec.get("ranges", {}))
	if limits.is_empty():
		var spin := SpinBox.new()
		spin.min_value = -1000000.0
		spin.max_value = 1000000.0
		spin.step = 1.0 if type == TYPE_INT else 0.001
		spin.value = float(target.get(prop_name))
		spin.value_changed.connect(func(v: float) -> void: _write(target, prop_name, v, on_change))
		return spin

	var low := limits[0]
	var high := limits[1]
	var value := float(target.get(prop_name))
	var slider := HSlider.new()
	if _is_curved(low, high):
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.001
		slider.value = _to_t(value, low, high)
		label.text = "%s  %.1f" % [prop_name, value]
		slider.value_changed.connect(func(t: float) -> void:
			var mapped := _from_t(t, low, high)
			label.text = "%s  %.1f" % [prop_name, mapped]
			_write(target, prop_name, mapped, on_change))
		return slider
	slider.min_value = low
	slider.max_value = high
	slider.step = limits[2]
	slider.value = value
	label.text = "%s  %.3f" % [prop_name, value]
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%s  %.3f" % [prop_name, v]
		_write(target, prop_name, v, on_change))
	return slider


## `[min, max, step]` de un `@export_range`, o vacio si no lo tiene. `ranges` puede reemplazar los dos
## extremos: un slider esta limitado por sus PIXELES, no por su paso, asi que un rango diez veces mas
## grande que la banda util no se arregla afinando el step.
##
## Cuando el rango no declara paso —y el addon de nubes no lo declara NUNCA— hay que inventarle uno, y
## el obvio, un doscientosavo del rango, miente: `clouds_density` va de 0 a 20, asi que el paso daba 0,1
## y el valor mas chico que se podia poner era exactamente 0,1, con toda la banda translucida de abajo
## fuera de alcance. Va un paso fino, y de que igual se lea se encarga el numero al lado del slider.
static func _range(prop: Dictionary, ranges: Dictionary) -> PackedFloat64Array:
	if int(prop["hint"]) != PROPERTY_HINT_RANGE:
		return PackedFloat64Array()
	var parts := str(prop["hint_string"]).split(",")
	if parts.size() < 2:
		return PackedFloat64Array()
	var low := float(parts[0])
	var high := float(parts[1])
	if ranges.has(str(prop["name"])):
		var override: Array = ranges[str(prop["name"])]
		low = float(override[0])
		high = float(override[1])
	var fine := 1.0 if int(prop["type"]) == TYPE_INT else 0.001
	var step := float(parts[2]) if parts.size() > 2 else fine
	return PackedFloat64Array([low, high, step])


# ── Sliders curvos (ver CURVED_MIN_MAX) ──────────────────────────────────────────────────────────

static func _is_curved(low: float, high: float) -> bool:
	if low < 0.0 or high < CURVED_MIN_MAX:
		return false
	return high / maxf(low, high / 100000.0) >= CURVED_RATIO


## Geometrica si el minimo es positivo. Si arranca en cero no hay logaritmo posible, asi que va una
## cubica, que tambien reparte casi todo el recorrido en la parte baja y deja llegar al cero exacto.
static func _from_t(t: float, low: float, high: float) -> float:
	if low <= 0.0:
		return high * t * t * t
	return low * pow(high / low, t)


static func _to_t(value: float, low: float, high: float) -> float:
	if low <= 0.0:
		return pow(clampf(value / high, 0.0, 1.0), 1.0 / 3.0)
	return clampf(log(maxf(value, low) / low) / log(high / low), 0.0, 1.0)


static func _write(target: Object, prop_name: String, value: Variant, on_change: Callable) -> void:
	target.set(prop_name, value)
	if on_change.is_valid():
		on_change.call()
