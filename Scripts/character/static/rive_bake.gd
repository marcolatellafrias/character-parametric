class_name RiveBake

## HERRAMIENTA DE DESARROLLO — se borra cuando el arte esté cerrado.
##
## Corre `Tools/rive_bake/bake.js` al arrancar, que lee `Art/rive/character_face.riv` y escribe un PNG
## por artboard en `Textures/character/`. Con eso el bucle de iteración sobre el arte es:
##
##   dibujar en Rive → Publish → correr el juego → verlo puesto
##
## en vez de renderizar ocho presets, bajarlos y acomodarlos a mano.
##
## Está deliberadamente aislado: un archivo y **una** llamada en CharacterAppearance.apply_to. Cuando
## el arte esté cerrado, se borran los dos y no queda nada colgando.
##
## Solo corre desde el editor. Un build exportado no tiene Node, ni el .riv, ni por qué re-hornear
## nada — las texturas ya están importadas.

const SCRIPT_DIR := "res://Tools/rive_bake"
const RIV_PATH := "res://Art/rive/character_face.riv"

static var _done := false


## Hornea una vez por sesión. Bloquea unos segundos (arrancar Chromium), y va donde va porque el
## primer personaje es lo primero que necesita las texturas.
static func ensure_baked() -> void:
	if _done:
		return
	_done = true  # también en los caminos de error: no reintentar en cada personaje
	if not OS.has_feature("editor"):
		return
	if not FileAccess.file_exists(ProjectSettings.globalize_path(RIV_PATH)):
		return

	var dir := ProjectSettings.globalize_path(SCRIPT_DIR)
	var out: Array = []
	var start := Time.get_ticks_msec()
	# `node` tiene que estar en el PATH. Si no está, `execute` devuelve −1 y seguimos con los PNG que
	# ya estén en disco: la ausencia de la herramienta no puede romper el juego.
	var code := OS.execute("node", [dir.path_join("bake.js")], out, true)
	var took := Time.get_ticks_msec() - start

	if code != 0:
		push_warning("RiveBake: no se pudo hornear (código %d). Se usan los PNG que haya en disco.\n%s"
			% [code, "\n".join(out)])
		return
	print("[RiveBake] listo en %d ms" % took)
