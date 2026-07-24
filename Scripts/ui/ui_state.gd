extends Node
## UIState (autoload). Único dueño del mouse_mode y de qué overlays están abiertos por
## encima del gameplay (pausa, menú, consola, panel de debug). El gameplay solo está
## "activo" cuando no hay ningún overlay: ahí se captura el mouse. Cualquier overlay
## libera el mouse y bloquea el input de gameplay — player_controller y la cápsula
## consultan gameplay_active() antes de leer input. No frena la simulación (co-op: el
## mundo sigue). Ver technical/ui.md.

const PAUSE := "pause"
const MENU := "menu"
const CONSOLE := "console"
const DEBUG := "debug"

signal changed()

## layer(String) -> true. Un overlay está abierto si su clave está presente.
var _open: Dictionary = {}

func _ready() -> void:
	_refresh()

func open(layer: String) -> void:
	if _open.has(layer):
		return
	_open[layer] = true
	_refresh()

func close(layer: String) -> void:
	if not _open.has(layer):
		return
	_open.erase(layer)
	_refresh()

func toggle(layer: String) -> void:
	if _open.has(layer):
		close(layer)
	else:
		open(layer)

func is_open(layer: String) -> bool:
	return _open.has(layer)

## True cuando no hay ningún overlay abierto: el mouse está capturado y el input de
## gameplay fluye.
func gameplay_active() -> bool:
	return _open.is_empty()

func _refresh() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _open.is_empty() else Input.MOUSE_MODE_VISIBLE
	changed.emit()
