class_name CityInspector
extends Node3D

## APUNTÁ Y DECIME QUÉ ES — la herramienta general de identificación de la ciudad.
##
## Se prende desde la pestaña Acciones del panel F1 y se USA CON EL PANEL CERRADO: `UIState` libera el mouse
## con cualquier overlay abierto, y sin mouse capturado no se puede apuntar.
##
## Lo que muestra: una mira en el centro de la pantalla, un punto en el centro de la pieza apuntada, un
## cartel in-world al lado, y la pieza dibujada como un wireframe con RAYOS X: todas sus aristas, visibles
## aunque estén tapadas. No es el outline de los grabbables, que es una silueta pura pensada para despegar
## del fondo un objeto que se agarra; para inspeccionar hacen falta los ángulos, no el contorno.
##
## ⚠ NO SABE NADA DE EDIFICIOS, TECHOS NI PUENTES. Todo lo que hace es: tirar un rayo, leer el scope del
## cuerpo que lo frenó, y preguntarle a `CityIndex` qué pieza es. Un sistema nuevo —caños, escaleras,
## ventanas— aparece acá solo, sin tocar este archivo, con la única condición de anotarse en el índice
## cuando hornea su geometría. Esa es toda la gracia: la identificación no se reimplementa por tipo.
##
## El rango es FINITO a propósito: un rayo infinito en una ciudad llena de geometría identifica cosas que
## están lejísimos y confunde más de lo que ayuda.

const RANGE := 50.0
const MARKER_SIZE := 0.35
const CROSSHAIR_COLOR := Color(0.6, 1.0, 0.75)
const LABEL_OFFSET := 1.2
const LABEL_FONT_SIZE := 16
const WIRE_COLOR := Color(0.4, 1.0, 0.6)
## Las dos capas de relleno, oscuras para que el wireframe resalte encima: el OBJETO entero más atrás y más
## apagado, la PIEZA apuntada un escalón más clara y más opaca.
const MACRO_COLOR := Color(0.04, 0.06, 0.15, 0.40)
const MICRO_COLOR := Color(0.05, 0.20, 0.22, 0.70)

var enabled: bool = false

var _camera: Camera3D = null
## El cuerpo del propio jugador, para sacarlo del rayo (ver `_excludes`).
var _body: PhysicsBody3D = null
var _crosshair: Label = null
var _marker: MeshInstance3D = null
var _label: Label3D = null
## Tres capas, de atrás hacia adelante: el objeto entero, la pieza apuntada, y las aristas de la pieza.
var _macro_fill: MeshInstance3D = null
var _micro_fill: MeshInstance3D = null
var _highlight: MeshInstance3D = null
## La última pieza resaltada, para no reconstruir la malla del contorno en cada frame.
var _last_key := ""
## El texto de lo que se está mirando, en versión larga y plana para pegar en un chat. Se arma en cada
## frame junto con el cartel, y F4 lo copia (ver `copy_to_clipboard`).
var _report := ""
## Hasta cuándo el cartel avisa que se copió, en milisegundos de `Time.get_ticks_msec`.
var _copied_until_ms := 0
const COPIED_FEEDBACK_MS := 1500


func setup(camera: Camera3D, body: PhysicsBody3D = null) -> void:
	_camera = camera
	_body = body
	_build_crosshair()
	_build_marker()
	_build_highlight()
	set_enabled(false)


func set_enabled(on: bool) -> void:
	enabled = on
	if _crosshair != null:
		_crosshair.visible = on
	if not on:
		_hide_target()


func _process(_delta: float) -> void:
	if not enabled or not is_instance_valid(_camera):
		return
	_aim()


# ── LO QUE SE VE ────────────────────────────────────────────────────────────────────────────────

func _build_crosshair() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90  # debajo del panel de debug, que es 100
	add_child(layer)

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.anchor_right = 1.0
	_crosshair.anchor_bottom = 1.0
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_theme_color_override("font_color", CROSSHAIR_COLOR)
	_crosshair.add_theme_color_override("font_outline_color", Color.BLACK)
	_crosshair.add_theme_constant_override("outline_size", 4)
	layer.add_child(_crosshair)


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true  # la posición se fija en mundo, sin heredar la del jugador
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_SIZE * 0.5
	sphere.height = MARKER_SIZE
	sphere.radial_segments = 8
	sphere.rings = 4
	_marker.mesh = sphere
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CROSSHAIR_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 2
	_marker.material_override = mat
	_marker.visible = false
	add_child(_marker)

	# `fixed_size` es lo que lo hace legible: sin eso, a 40 m el cartel es un par de píxeles.
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.font_size = LABEL_FONT_SIZE
	_label.outline_size = 8
	_label.outline_modulate = Color.BLACK
	_label.modulate = Color.WHITE
	_label.position = Vector3(0, LABEL_OFFSET, 0)
	_marker.add_child(_label)


## WIREFRAME CON RAYOS X, y a propósito NO el contorno de los grabbables.
##
## Aquel es una silueta pura —un casco inflado recortado por stencil— pensada para que un objeto agarrable
## se despegue del fondo. Para inspeccionar sirve lo contrario: ver TODOS los ángulos de la pieza, y verlos
## aunque estén tapados. Por eso son líneas sin test de profundidad en vez de una silueta.
##
## ⚠ El ancho de línea en Godot es de 1 píxel y no se puede cambiar: es una limitación del rasterizado, no
## un parámetro que falte. Para aristas gruesas habría que generar tiras de quads por cada arista.
func _build_highlight() -> void:
	# EL ORDEN LO FIJA `render_priority`, NO LA PROFUNDIDAD. Las tres capas son copias de la geometría de la
	# ciudad puestas exactamente encima de sí misma: con test de profundidad pelearían con el original y
	# entre ellas. Sin test, el orden de dibujado es lo único que decide, y queda explícito.
	_macro_fill = _make_layer(MACRO_COLOR, 0)
	_micro_fill = _make_layer(MICRO_COLOR, 1)
	_highlight = _make_layer(WIRE_COLOR, 2)


func _make_layer(color: Color, priority: int) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = priority
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var layer := MeshInstance3D.new()
	layer.top_level = true
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.material_override = mat
	layer.visible = false
	add_child(layer)
	return layer


func _hide_target() -> void:
	if _marker != null:
		_marker.visible = false
	_hide_layers()
	_last_key = ""
	_report = ""


func _hide_layers() -> void:
	for layer in [_macro_fill, _micro_fill, _highlight]:
		if layer != null:
			layer.visible = false


# ── APUNTAR ─────────────────────────────────────────────────────────────────────────────────────

func _aim() -> void:
	var viewport := _camera.get_viewport()
	if viewport == null:
		return
	var from := _camera.global_position
	var to := from + _camera.project_ray_normal(viewport.get_visible_rect().size * 0.5) * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2
	query.exclude = _excludes()
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_hide_target()
		return

	var body: Object = hit.get("collider")
	if body == null or not (body is Node) or not (body as Node).has_meta(CityIndex.SCOPE_META):
		_show_unknown(hit["position"], body)
		return

	var city := get_tree().get_first_node_in_group("city_generator")
	if city == null:
		_hide_target()
		return
	var index: CityIndex = city.get_city_index()
	if index == null:
		_hide_target()
		return

	var node := body as Node
	var scope: int = node.get_meta(CityIndex.SCOPE_META)
	# `face_index` da el triángulo exacto cuando el rayo pega contra un trimesh. Si no viene, `find` cae
	# por contención de caja, que es igual de genérica y solo un poco menos precisa.
	var face_index := int(hit.get("face_index", -1))
	var piece := index.find(scope, hit["position"], face_index)
	if piece < 0:
		_show_unknown(hit["position"], body)
		return

	var info := index.describe(piece)
	var centre: Vector3 = info["centre"]
	_marker.global_position = centre
	_marker.visible = true

	var lines: Array[String] = []
	lines.append(str(info["kind_name"]).to_upper())
	for line: String in info["lines"]:
		lines.append(line)
	lines.append("a %.0f m" % from.distance_to(centre))
	_label.text = _with_copied_notice("\n".join(lines))

	# La versión para pegar: todo lo del cartel más lo que hace falta para reproducirlo sin estar mirando
	# —la seed, dónde pegó el rayo y los ids crudos—.
	var point: Vector3 = hit["position"]
	var report: Array[String] = []
	report.append("[inspector] %s" % str(info["kind_name"]))
	for line: String in info["lines"]:
		report.append("  " + line)
	report.append("  seed: %s" % str(city.generation_seed))
	report.append("  impacto: (%.2f, %.2f, %.2f)" % [point.x, point.y, point.z])
	report.append("  centro de la pieza: (%.2f, %.2f, %.2f)" % [centre.x, centre.y, centre.z])
	report.append("  ids crudos: a=%d b=%d c=%d d=%d · scope %d · pieza %d"
			% [int(info["id_a"]), int(info["id_b"]), int(info["id_c"]), int(info["id_d"]), scope, piece])
	_report = "\n".join(report)

	_refresh_highlight(index, piece)


## EL CUERPO PROPIO NO CUENTA. La cámara vive DENTRO de la cápsula del jugador, así que sin esto el rayo se
## choca con uno mismo: el impacto queda a centímetros, el cartel se va contra el plano cercano y parece que
## desapareciera. Moviéndose los brazos se corren y vuelve, que es exactamente el síntoma raro de "quieto no,
## caminando sí". `InteractionDetector` excluye lo mismo por la misma razón.
func _excludes() -> Array[RID]:
	var out: Array[RID] = []
	if not is_instance_valid(_body):
		return out
	out.append(_body.get_rid())
	var bi := _body.get_parent() as BoneInstantiator
	if is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util):
		for rid: RID in bi.ragdoll_util._ragdoll_rids:
			out.append(rid)
	return out


## COPIA LO QUE SE ESTÁ MIRANDO al portapapeles del sistema. Devuelve si había algo que copiar.
func copy_to_clipboard() -> bool:
	if not enabled or _report.is_empty():
		return false
	DisplayServer.clipboard_set(_report)
	_copied_until_ms = Time.get_ticks_msec() + COPIED_FEEDBACK_MS
	return true


func _with_copied_notice(text: String) -> String:
	if Time.get_ticks_msec() < _copied_until_ms:
		return text + "\n(copiado)"
	return text


func _show_unknown(point: Vector3, body: Object) -> void:
	_marker.global_position = point
	_marker.visible = true
	_hide_layers()
	_last_key = ""
	var name_hint := "?"
	var path_hint := "?"
	if body is Node:
		name_hint = (body as Node).name
		if (body as Node).is_inside_tree():
			path_hint = str((body as Node).get_path())
	_label.text = _with_copied_notice("sin identificar\n%s" % name_hint)
	# También se copia: es justo el caso que hay que reportar cuando un sistema no se anotó en el índice, y
	# la ruta del nodo es lo que dice de qué sistema es (ver "Making a new system identifiable").
	_report = "[inspector] sin identificar\n  nodo: %s\n  ruta: %s\n  impacto: (%.2f, %.2f, %.2f)" \
			% [name_hint, path_hint, point.x, point.y, point.z]


## LAS TRES CAPAS: el objeto entero de fondo, la pieza apuntada encima, y sus aristas arriba de todo.
##
## Es genérico: no sabe qué construyó esos triángulos, solo de qué pieza a qué pieza van. Se rearma solo
## cuando cambia la pieza apuntada, no por frame.
func _refresh_highlight(index: CityIndex, piece: int) -> void:
	var key := str(piece)
	if key == _last_key:
		_show_layers()
		return
	_last_key = key

	var micro := PackedInt32Array()
	micro.append(piece)
	_apply_mesh(_macro_fill, _collect(index, index.members_of_object(piece), false), Mesh.PRIMITIVE_TRIANGLES)
	_apply_mesh(_micro_fill, _collect(index, micro, false), Mesh.PRIMITIVE_TRIANGLES)
	_apply_mesh(_highlight, _collect(index, micro, true), Mesh.PRIMITIVE_LINES)


func _show_layers() -> void:
	for layer in [_macro_fill, _micro_fill, _highlight]:
		if layer != null and layer.mesh != null:
			layer.visible = true


func _apply_mesh(target: MeshInstance3D, verts: PackedVector3Array, primitive: Mesh.PrimitiveType) -> void:
	if target == null:
		return
	if verts.is_empty():
		target.mesh = null
		target.visible = false
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	target.mesh = mesh
	target.visible = true


## Copia la geometría de un conjunto de piezas, EN COORDENADAS DEL MUNDO.
##
## Va al mundo en vez de heredar la transformación de una malla porque un objeto puede abarcar VARIAS: las
## paredes de un edificio están en la malla de su cluster y su techo en la de la manzana entera, y encima
## `_fade_into_fog` recentra cada malla en su propio centro. No hay una sola transformación que sirva para
## las dos.
##
## Con `as_edges` devuelve las aristas de cada triángulo, deduplicadas — la que comparten dos triángulos se
## traza una sola vez, si no las diagonales de los quads quedarían al doble de intensidad.
func _collect(index: CityIndex, records: PackedInt32Array, as_edges: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cache := {}
	var seen := {}

	for r: int in records:
		var scope := index.scope_of(r)
		if not cache.has(scope):
			var source := index.mesh_for_scope(scope)
			if not is_instance_valid(source) or source.mesh == null or source.mesh.get_surface_count() == 0:
				cache[scope] = null
			else:
				var arrays := source.mesh.surface_get_arrays(0)
				cache[scope] = {
					"verts": arrays[Mesh.ARRAY_VERTEX],
					"idxs": arrays[Mesh.ARRAY_INDEX],
					"xf": source.global_transform,
				}
		var entry = cache[scope]
		if entry == null:
			continue

		var verts: PackedVector3Array = entry["verts"]
		var idxs: PackedInt32Array = entry["idxs"]
		var xf: Transform3D = entry["xf"]
		var span := index.range_of(r)
		if span.y <= span.x or span.y > idxs.size():
			continue

		if not as_edges:
			for i in range(span.x, span.y):
				out.append(xf * verts[idxs[i]])
			continue

		var t := span.x
		while t + 2 < span.y:
			var corners: Array[Vector3] = [
				xf * verts[idxs[t]], xf * verts[idxs[t + 1]], xf * verts[idxs[t + 2]]]
			for e in 3:
				var a: Vector3 = corners[e]
				var b: Vector3 = corners[(e + 1) % 3]
				var ka := str(a)
				var kb := str(b)
				var edge_key := (ka + "|" + kb) if ka < kb else (kb + "|" + ka)
				if seen.has(edge_key):
					continue
				seen[edge_key] = true
				out.append(a)
				out.append(b)
			t += 3

	return out
