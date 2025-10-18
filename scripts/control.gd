extends CanvasLayer

@onready var bone_instantiator: Node = $"../player_root/player_controller/BoneInstantiator"

@onready var vbox := VBoxContainer.new()

func _ready():
	if bone_instantiator == null:
		push_error("BoneInstantiator not found in scene tree.")
		return

	# Panel arriba a la izquierda
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = 280
	panel.offset_bottom = 200
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	vbox.anchor_right = 1
	vbox.anchor_bottom = 1
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Sliders conectados directamente a variables del BoneInstantiator
	_add_slider("Feet→Head Height", 1.4, 2.2, 0.01, "feet_to_head_height")
	_add_slider("Legs→Feet", 0.0, 1.0, 0.01, "legs_to_feet_proportion")
	_add_slider("Chest→Hip", 0.0, 1.0, 0.01, "chest_to_low_spine_proportion")
	_add_slider("Neck→Head", 0.0, 1.0, 0.01, "neck_to_head_proportion")
	_add_slider("Arms", 0.0, 1.0, 0.01, "arms_proportion")

func _add_slider(label_text: String, min_v: float, max_v: float, step_v: float, property_name: String):
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(row)

	var label := Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 120
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(slider)

	var val := Label.new()
	val.custom_minimum_size.x = 60
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = str(snapped(bone_instantiator.get(property_name), step_v))
	row.add_child(val)

	# Valor inicial
	slider.value = bone_instantiator.get(property_name)

	# Cuando cambia el slider → actualiza la propiedad
	slider.value_changed.connect(func(v):
		v = snapped(v, step_v)
		bone_instantiator.set(property_name, v)
		val.text = str(v)
	)
