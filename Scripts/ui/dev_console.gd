extends CanvasLayer
## DevConsole (autoload). Consola estilo Source: overlay global por encima de todo, se abre/
## cierra con la tecla física a la izquierda del 1 (º / ~). Anda en el menú y en el juego, es
## independiente de que exista un jugador o una escena. Un registro de comandos (register) es
## la fuente única de acciones de dev — los botones del panel F1 llamarán a estos comandos
## (paso 7). Ver technical/ui.md.

## Tecla física a la izquierda del 1 (en teclado español es "º", en US es "~").
const TOGGLE_KEY := KEY_QUOTELEFT

## nombre -> {callable: Callable(args: PackedStringArray), help: String}
var _commands: Dictionary = {}
var _output: RichTextLabel
var _input_field: LineEdit

func _ready() -> void:
	layer = 200  # por encima de pausa, menú y panel de debug
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	UIState.changed.connect(_on_ui_changed)
	_register_builtins()

## Registra un comando. `callable` recibe los argumentos como PackedStringArray.
func register(command_name: String, callable: Callable, help: String = "") -> void:
	_commands[command_name] = {"callable": callable, "help": help}

func log_line(msg: String) -> void:
	if is_instance_valid(_output):
		_output.append_text(msg + "\n")

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == TOGGLE_KEY:
		UIState.toggle(UIState.CONSOLE)
		get_viewport().set_input_as_handled()
	elif UIState.is_open(UIState.CONSOLE) and event.keycode == KEY_ESCAPE:
		UIState.close(UIState.CONSOLE)
		get_viewport().set_input_as_handled()

func _on_ui_changed() -> void:
	var console_open := UIState.is_open(UIState.CONSOLE)
	visible = console_open
	if console_open:
		_input_field.grab_focus()
	else:
		_input_field.release_focus()

func _on_submit(text: String) -> void:
	_input_field.clear()
	_run(text)

func _run(line: String) -> void:
	line = line.strip_edges()
	if line == "":
		return
	log_line("[color=gray]> %s[/color]" % line)
	var parts := line.split(" ", false)
	var cmd: String = parts[0]
	var args := parts.slice(1)
	if _commands.has(cmd):
		(_commands[cmd]["callable"] as Callable).call(args)
	else:
		log_line("comando desconocido: %s (probá 'help')" % cmd)

# ── Comandos base ─────────────────────────────────────────────────────────────

func _register_builtins() -> void:
	register("help", _cmd_help, "lista los comandos")
	register("clear", func(_a): _output.clear(), "limpia la consola")
	register("quit", func(_a): get_tree().quit(), "cierra el juego")
	register("host", func(_a): SessionManager.host(), "hostea una partida")
	register("join", _cmd_join, "join <código> — se une por código")

func _cmd_help(_args: PackedStringArray) -> void:
	log_line("Comandos:")
	for command_name in _commands:
		log_line("  %s — %s" % [command_name, _commands[command_name]["help"]])

func _cmd_join(args: PackedStringArray) -> void:
	if args.is_empty():
		log_line("uso: join <código>")
		return
	SessionManager.join_by_code(args[0])

# ── UI ────────────────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.anchor_right = 1.0
	root.offset_bottom = 320.0
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_output)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "comando…  (help)"
	_input_field.text_submitted.connect(_on_submit)
	vbox.add_child(_input_field)
