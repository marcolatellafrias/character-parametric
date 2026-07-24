extends Control
## Main menu (escena inicial). Host o Join-por-código. Front-end temporal hasta el Lounge
## diegético (conceptual/run-setup.md). Cuando la sesión se establece (session_ready) carga la
## escena del juego; si falla (session_failed) se queda en el menú mostrando el error.

const GAME_SCENE := "res://Scenes/Demo.tscn"

var _code_field: LineEdit
var _status: Label
var _host_btn: Button
var _join_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# En el menú el mouse tiene que estar visible; se recaptura al entrar al juego.
	UIState.open(UIState.MENU)
	_build()
	SessionManager.session_ready.connect(_on_session_ready)
	SessionManager.session_failed.connect(_on_session_failed)
	# Si Steam nos lanzó con +connect_lobby, la sesión ya se está estableciendo.
	if SessionManager.session_started:
		_go_to_game()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "NUEVOS AIRES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_host_btn = _button("Host", _on_host)
	vbox.add_child(_host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	_code_field = LineEdit.new()
	_code_field.placeholder_text = "código"
	_code_field.max_length = SessionManager.CODE_LENGTH
	_code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_field.text_submitted.connect(func(_t): _on_join())
	join_row.add_child(_code_field)
	_join_btn = _button("Join", _on_join)
	join_row.add_child(_join_btn)
	vbox.add_child(join_row)

	vbox.add_child(_button("Opciones", _on_options))
	vbox.add_child(_button("Salir", _on_quit))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status)

	if not SessionManager.enabled:
		_join_btn.disabled = true
		_code_field.editable = false
		_set_status("Steam no disponible — Host corre local")

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

# ── Acciones ──────────────────────────────────────────────────────────────────

func _on_host() -> void:
	_set_busy("Creando partida…")
	SessionManager.host()

func _on_join() -> void:
	var code := _code_field.text.strip_edges()
	if code == "":
		_set_status("Ingresá un código")
		return
	_set_busy("Uniéndose a %s…" % code.to_upper())
	SessionManager.join_by_code(code)

func _on_options() -> void:
	pass  # placeholder

func _on_quit() -> void:
	get_tree().quit()

# ── Sesión ────────────────────────────────────────────────────────────────────

func _on_session_ready(_id: int) -> void:
	_go_to_game()

func _on_session_failed(reason: String) -> void:
	_set_idle()
	_set_status("Error: " + reason)

func _go_to_game() -> void:
	UIState.close(UIState.MENU)  # el juego arranca con el mouse capturado
	get_tree().change_scene_to_file(GAME_SCENE)

# ── UI helpers ────────────────────────────────────────────────────────────────

func _set_busy(msg: String) -> void:
	_host_btn.disabled = true
	_join_btn.disabled = true
	_set_status(msg)

func _set_idle() -> void:
	_host_btn.disabled = false
	_join_btn.disabled = not SessionManager.enabled

func _set_status(msg: String) -> void:
	_status.text = msg
