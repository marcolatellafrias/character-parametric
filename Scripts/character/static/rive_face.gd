class_name RiveFace

## TEXTURAS DE CARA EN VIVO, renderizadas por Rive en vez de horneadas a PNG.
##
## Es el reemplazo de `RiveBake` a futuro, pero por ahora convive con él: mientras esto esté apagado o
## falle, `CharacterAppearance._source_texture` sigue cayendo al PNG y no se nota nada.
##
## ── POR QUÉ ─────────────────────────────────────────────────────────────────────────────────────
## Un PNG horneado obliga a teñir MULTIPLICANDO al dibujar, y eso no distingue una línea blanca de un
## relleno rosa una vez que el rasterizador promedió el borde entre las dos. Con Rive vivo el color se
## setea ANTES de rasterizar (`RiveViewModelColor.set_value`), así que el borde se promedia entre
## colores ya correctos y no hay nada que adivinar después. Ver character_plane.gdshader.
##
## ── CÓMO ────────────────────────────────────────────────────────────────────────────────────────
## `RiveGD` no tiene nodo 3D, y no hace falta: `RiveCanvas2D` renderiza a una Texture y los planos de
## cara ya consumen una textura. El canvas vive fuera de la vista, en un contenedor propio.
##
## El nombre del artboard ES el nombre de la malla — la misma convención que ya usa `bake.js`.
##
## ⚠ ESTADO: primer paso. Una textura COMPARTIDA por artboard, sin color por personaje todavía. El
## color por instancia necesita un canvas (o una copia de `RiveMultiInstance`) por personaje, que es la
## decisión de escala que hay que tomar después: hoy una textura la comparte toda la ciudad.

const RIV_PATH := "res://Art/rive/character_face.riv"

## LOS ARTBOARDS QUE EXISTEN. Tabla explícita, y hace falta que lo sea: `RiveGD` no expone forma de
## listarlos, y pedirle uno que no existe **no falla** — devuelve otro. Sin esta lista, pedir
## `eye_left_plane_mesh` (que no es un artboard) daba las cejas en los ojos.
##
## Es la misma lista que `Tools/rive_bake/bake.js`, y tiene que seguir siéndolo.
const ARTBOARDS: Array[String] = [
	"forehead_plane_mesh",
	"brows_plane_mesh",
	"eye_plane_mesh",
	"mouth_plane_mesh",
	"chin_plane_mesh",
	"cheekbones_plane_mesh",
	"teartrough_plane_mesh",
	"nose_plane_mesh",
]

## Apagado por default A PROPÓSITO. `RiveGD` es un GDExtension marcado WIP por sus propios autores, y
## un fallo acá tiene que costar "se ven los PNG de siempre", nunca una partida rota. Lo prende el panel.
static var ENABLED := false

static var _container: Node = null
static var _canvases: Dictionary = {}
static var _tried := false
## Traza en consola cada paso de la construcción. Se apaga cuando esto funcione.
static var VERBOSE := true


static func _log(msg: String) -> void:
	if VERBOSE:
		print("[RiveFace] ", msg)


## Textura viva de un artboard, o `null` para que el llamador caiga al PNG.
##
## Nunca tira: cualquier cosa que falte —el addon, el .riv, el artboard— devuelve null y el sistema
## viejo sigue funcionando.
static func texture_for(mesh_name: String, tree: SceneTree) -> Texture2D:
	if not ENABLED or tree == null:
		return null
	if not ARTBOARDS.has(mesh_name):
		return null  # no es un artboard: que el llamador siga con su cadena de fallbacks
	if not ClassDB.class_exists("RiveCanvas2D"):
		_log("RiveCanvas2D no existe en ClassDB — el addon no cargó")
		return null
	_ensure_container(tree)
	if _container == null:
		_log("sin contenedor (current_scene nulo?)")
		return null
	if not _canvases.has(mesh_name):
		_canvases[mesh_name] = _build_canvas(mesh_name)
	var canvas = _canvases[mesh_name]
	if canvas == null or not is_instance_valid(canvas):
		_log("%s: no hay canvas" % mesh_name)
		return null
	var raw = canvas.get_texture()
	if raw == null:
		_log("%s: get_texture() devolvió null (¿todavía no renderizó un frame?)" % mesh_name)
		return null
	var tex := raw as Texture2D
	if tex == null:
		_log("%s: get_texture() devolvió %s, que NO es Texture2D" % [mesh_name, raw.get_class()])
		return null
	_live[tex.get_instance_id()] = true
	_log("%s: textura viva OK, %s" % [mesh_name, str(tex.get_size())])
	return tex


## Registro de qué texturas salieron de Rive. Lo consulta `CharacterAppearance` para decidir si hay que
## decodificar sRGB a mano: un render target no trae la marca que sí trae un PNG importado, así que el
## `source_color` del shader no lo convierte y la imagen sale lavada.
static var _live: Dictionary = {}

## Artboards cuyo color de línea se setea ANTES de rasterizar. Malla → nombre de la propiedad Color en
## el ViewModel del artboard.
##
## Es LA razón de tener Rive en runtime. Con un PNG el color solo se puede aplicar multiplicando encima
## de la imagen ya hecha, y ahí el borde entre una línea blanca y un relleno rosa ya se promedió: esos
## píxeles no son blancos ni rosas, y no hay forma de saber cuánto de cada uno eran. Seteando el color
## en el artboard, el outline se DIBUJA en su color final y el antialiasing mezcla lo correcto.
##
## Un nombre que no exista en el .riv no rompe nada: la propiedad vuelve null y no se escribe.
const COLOR_BINDINGS := {
	"mouth_plane_mesh": "line_color",
}

static func is_live(tex: Texture2D) -> bool:
	return tex != null and _live.has(tex.get_instance_id())


## Escribe el color de línea de un artboard, si tiene binding declarado. Devuelve true si se aplicó.
##
## ⚠ HOY LA TEXTURA ES COMPARTIDA por toda la ciudad, así que esto pinta a TODOS con el último color que
## se escribió. Para color por personaje hace falta un canvas por personaje — esa es la decisión de
## escala que queda pendiente. Con un solo personaje en escena se ve bien.
static func set_line_color(mesh_name: String, color: Color, tree: SceneTree) -> bool:
	if not ENABLED or not COLOR_BINDINGS.has(mesh_name):
		return false
	var canvas = _canvases.get(mesh_name)
	if canvas == null or not is_instance_valid(canvas) or canvas.get_child_count() == 0:
		return false
	var inst = canvas.get_child(0)
	if not inst.has_method("get_view_model_instance"):
		return false
	var vm = inst.get_view_model_instance()
	if vm == null:
		_log("%s: el artboard no tiene ViewModel" % mesh_name)
		return false
	var path: String = COLOR_BINDINGS[mesh_name]
	var prop = vm.get_color_property(path)
	if prop == null:
		_log("%s: no existe la propiedad Color '%s' en el ViewModel" % [mesh_name, path])
		return false
	prop.set_value(color)
	_log("%s: %s = %s (antes de rasterizar)" % [mesh_name, path, color.to_html(false)])
	return true


## Lo llama el toggle del panel: tira los canvas para que se reconstruyan con la bandera nueva.
static func reset() -> void:
	if is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_canvases.clear()
	_live.clear()
	_tried = false


## El contenedor va LEJOS del origen en coordenadas de canvas, no invisible: un nodo oculto puede no
## renderizar, y lo que necesitamos es justamente que renderice sin verse en pantalla.
static func _ensure_container(tree: SceneTree) -> void:
	if is_instance_valid(_container) or _tried:
		return
	_tried = true
	var root := tree.current_scene
	if root == null:
		_tried = false  # todavía no hay escena: reintentar en el próximo repintado
		return
	var n := Node2D.new()
	n.name = "RiveFaceCanvases"
	n.position = Vector2(-100000.0, -100000.0)
	root.add_child(n)
	_container = n


static func _build_canvas(mesh_name: String):
	var file := ResourceLoader.load(RIV_PATH)
	if file == null:
		_log("no se pudo cargar %s" % RIV_PATH)
		return null
	_log("%s cargado como %s" % [RIV_PATH, file.get_class()])
	var canvas = ClassDB.instantiate("RiveCanvas2D")
	if canvas == null:
		_log("ClassDB.instantiate(RiveCanvas2D) devolvió null")
		return null
	canvas.name = mesh_name
	canvas.set_size(_size_for(mesh_name))
	_container.add_child(canvas)

	var inst = ClassDB.instantiate("RiveFileInstance")
	if inst == null:
		canvas.queue_free()
		return null
	inst.set_rive_file(file)
	inst.set_artboard_name(mesh_name)
	inst.set_auto_play(true)
	canvas.add_child(inst)
	_log("canvas %s creado, tamaño %s, artboard '%s'" % [mesh_name, str(canvas.get_size()), mesh_name])
	return canvas


## El tamaño sale del PNG horneado del mismo artboard, que ya está a la resolución con la que se autoró.
## Si no hay PNG, un cuadrado razonable.
static func _size_for(mesh_name: String) -> Vector2i:
	var path := "res://Textures/character/%s.png" % mesh_name
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex.get_size()
	return Vector2i(256, 256)
