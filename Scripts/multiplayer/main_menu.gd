extends Control

# Este script genera una interfaz básica de red automáticamente al iniciar.
# Solo necesitas añadirlo a un nodo Control vacío en tu escena inicial.

var ip_input: LineEdit

func _ready() -> void:
	# Configuración básica del contenedor
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(300, 0)
	add_child(vbox)

	# Título
	var label = Label.new()
	label.text = "NUEVOS AIRES - MULTIPLAYER"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# Separador
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Botón Host
	var host_btn = Button.new()
	host_btn.text = "HOST GAME (Server)"
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	# Separador
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)

	# Campo de IP
	var ip_label = Label.new()
	ip_label.text = "Server IP:"
	vbox.add_child(ip_label)
	
	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1"
	ip_input.placeholder_text = "Enter IP Address"
	vbox.add_child(ip_input)

	# Botón Join
	var join_btn = Button.new()
	join_btn.text = "JOIN GAME (Client)"
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)

func _on_host_pressed():
	if get_node_or_null("/root/NetworkManager"):
		get_node("/root/NetworkManager").host_game()
		self.queue_free() # Elimina el menú al empezar
	else:
		printerr("ERROR: NetworkManager Autoload no encontrado.")

func _on_join_pressed():
	var ip = ip_input.text.strip_edges()
	if ip == "": ip = "127.0.0.1"
	
	if get_node_or_null("/root/NetworkManager"):
		get_node("/root/NetworkManager").join_game(ip)
		self.queue_free()
	else:
		printerr("ERROR: NetworkManager Autoload no encontrado.")
