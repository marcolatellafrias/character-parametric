class_name CharacterAppearance

## COLOR DE PERSONAJE POR SEED, con UN material compartido.
##
## Cada malla del modelo cumple un ROL (piel, tela, pelo, cuero…), y cada rol tiene un color que sale
## del seed. Lo que NO pasa es que cada personaje tenga su propio material: el color viaja por un
## `instance uniform`, que vive en el MeshInstance3D y no en el material, así que toda la ciudad
## comparte un material y un pipeline.
##
## Esa decisión es barata hoy y cara después: con material por personaje, una calle de peatones
## multiplica draw calls y memoria de textura, y sacarlo implica reescribir cómo se pinta todo.
## Ver technical/character-appearance-system.md.

enum Role { SKIN, CLOTH, HAIR, LEATHER, LINE, PROP }

## Malla del .glb → rol de color. Tabla explícita y no una convención de nombres, por la misma razón
## que ReferenceRig.BONE_MAP lo es: el modelo se sigue moviendo en Blender, y un nombre que cambia
## tiene que romper acá con un aviso, no pintar algo del color equivocado en silencio.
##
## Una malla que no esté acá no se toca: conserva el material con el que vino del .glb. Eso es lo
## correcto para cosas con color propio (la tarjeta, el cigarrillo) y es lo seguro para las que se
## agreguen después.
const MESH_ROLE := {
	"head_mesh":  Role.SKIN,
	"neck_mesh":  Role.SKIN,   # separada de la cabeza para poder pintarle máscaras propias
	"hands_mesh": Role.SKIN,
	# Piezas 3D de la cara. Los nombres traen espacios porque así salieron del modelo de los ojos.
	# Los párpados y la nariz son piel: si conservaran el material del .glb se leerían como una pieza
	# pegada encima en vez de como parte de la cara.
	"nose":                Role.SKIN,
	"left higher eyelid":  Role.SKIN,
	"left lower eyelid":   Role.SKIN,
	"right higher eyelid": Role.SKIN,
	"right lower eyelid":  Role.SKIN,
	"body_mesh":  Role.CLOTH,
	"arms_mesh":  Role.CLOTH,
	"shirt_mesh": Role.CLOTH,
	"hair_mesh":  Role.HAIR,
	"hair_mesh2": Role.HAIR,   # el nombre que tiene hoy en Blender
	"wrist_mesh": Role.SKIN,   # piel, igual que la mano
	"shoes_mesh": Role.LEATHER,
}

## PLANOS DE FEATURE → de qué color se tiñen. La textura aporta la FORMA (por el alpha) y opcionalmente
## sombreado interno en escala de grises; el color sale del seed.
##
## Por eso las arrugas se tiñen con la PIEL y las cejas con el PELO: una sola textura compartida por
## toda la ciudad se adapta sola a cualquier tono. `Role.PROP` = tinte blanco, o sea la textura entera
## sale literal.
##
## BOCA Y OJOS VAN EN `LINE`, no en `PROP`: con la regla de neutro/literal del shader un mismo plano
## puede tener las dos cosas, así que el delineado va en gris y se tiñe con la piel mientras el color
## propio (labio, esclerótica en #FFFFEE) sale literal.
##
## Depende de que el arte esté SEPARADO EN CAPAS — ver la advertencia en character_plane.gdshader.
##
## Un plano que no esté acá conserva el material del .glb, que es lo seguro para lo que se agregue.
const PLANE_ROLE := {
	"brows_plane_mesh":       Role.HAIR,
	"chest_hair_plane_mesh":  Role.HAIR,
	"back_hair_plane_mesh":   Role.HAIR,
	"hands_plane_mesh":       Role.HAIR,
	"forehead_plane_mesh":    Role.LINE,
	"cheekbones_plane_mesh":  Role.LINE,
	"teartrough_plane_mesh":  Role.LINE,   # sin la h, como está en Blender
	"chin_plane_mesh":        Role.LINE,
	"eye_left_plane_mesh":    Role.LINE,
	"eye_right_plane_mesh":   Role.LINE,
	"eyes_plane_mesh":        Role.LINE,   # por si no se separan
	"mouth_plane_mesh":       Role.LINE,
	"nose_plane_mesh":        Role.LINE,
	"nametag_plane_mesh":     Role.PROP,
}

## ── MODO GEOMETRÍA ────────────────────────────────────────────────────────────────────────────────
## En true los personajes se pintan con iluminación estándar en vez de con el shader toon.
##
## Existe porque el toon tiene UNA sola banda: la superficie es luz plana o sombra plana, y el volumen
## no se lee. Perfecto para juzgar el ESTILO, inútil para juzgar una ESCULTURA — que es lo que hace
## falta mientras se autoran `fat_max` y `muscle_max`.
##
## Conserva los colores. Lo que se pierde es el `instance uniform`: `StandardMaterial3D` no lo tiene,
## así que el color va en el material y hay uno por (rol, color) en vez de uno por rol. Con el preset
## activo eso es exactamente un material por rol, o sea el mismo costo. Sin preset, uno por
## combinación — aceptable para un modo de autoría, y otra razón para no dejarlo prendido.
##
## Poner en `false` para volver al shader. No hay nada más que tocar.
static var FLAT_GEOMETRY := true

## ── MODO MONOCROMO ────────────────────────────────────────────────────────────────────────────────
## Pinta TODO de un solo color neutro, con el shader normal. Sirve para juzgar el SOMBREADO aislado:
## el escalón del terminador, el tinte de la sombra, el rim y cómo la silueta lee el volumen — sin que
## el color de piel, traje y pelo compitan por la atención.
##
## NO es un solo color: es una ESCALA DE GRISES por rol. Con todo del mismo valor la silueta se
## empasta y no se distingue el pelo del gorro ni el zapato del pantalón. Separando los valores se
## sigue leyendo el modelo, y el sombreado se juzga igual porque no hay tono que compita.
##
## ⚠ EL TECHO ESTÁ BAJO A PROPÓSITO, y más de lo que parece necesario. El shader solo le da forma a la
## luz DIRECTA; el ambiente de la escena se suma encima, sin escalón. Cuanto más alto el albedo, más
## pesa ese término plano: a 0.90 la parte iluminada y la sombreada terminan las dos contra el blanco y
## el terminador desaparece — se ve como si el material fuera unlit, y no lo es.
##
## 0.72 es lo más claro que deja ver el escalón. Si necesitás más contraste todavía, la otra perilla es
## `shadow_value` de SKIN en `_material_for` (0.42): más bajo = sombra más oscura.
##
## Se apaga poniendo esto en `false`. No toca el sistema de color por seed ni el preset.
static var MONOCHROME := true
const MONOCHROME_GREYS := {
	Role.SKIN:    0.72,   # gris muy claro
	Role.CLOTH:   0.55,   # gris medio-claro
	Role.HAIR:    0.07,   # casi negro
	Role.LEATHER: 0.32,   # gris medio — zapatos
	Role.LINE:    0.44,   # arrugas: más oscuro que la piel, o no se ven
	# PROP NO ESTÁ ACÁ A PROPÓSITO: es el rol "sin teñir", y eso vale también en monocromo. Ver
	# _color_for. Estuvo en 0.72 y el efecto era que los blancos de los ojos salían grises.
}

## ── QUÉ PLANOS DE CARA SE VEN — TEMPORAL ──────────────────────────────────────────────────────────
## Mientras los planos dibujados conviven con las piezas 3D nuevas (ojos, nariz, boca), la decisión no
## es un toggle de debug: depende de la pieza y del arquetipo. Por eso vive acá y no en
## `CharacterDebugView` — ahí solo quedó un "esconder todo" manual, encima de esto.
##
## Se borra cuando el modelo termine de migrar a 3D y la tabla deje de tener excepciones.
##
## REEMPLAZADOS por malla 3D. No se muestran nunca, ni con el toggle de debug prendido.
const PLANES_REPLACED := [
	"eye_left_plane_mesh", "eye_right_plane_mesh", "eyes_plane_mesh",
	"mouth_plane_mesh", "nose_plane_mesh",
]
## Arrugas: solo si el arquetipo las pide (`has_wrinkles`). Hoy, únicamente el viejo.
const PLANES_WRINKLE := [
	"forehead_plane_mesh", "cheekbones_plane_mesh", "teartrough_plane_mesh", "chin_plane_mesh",
]

## Esconde TODOS los planos de cara. Es un override manual del panel, por encima de la regla de arriba.
static var HIDE_FACE_PLANES := false

static func toggle_face_planes(tree: SceneTree) -> void:
	HIDE_FACE_PLANES = not HIDE_FACE_PLANES
	reapply_all(tree)


## Las cejas y cualquier plano que no esté en las dos tablas se ven siempre.
static func _plane_visible(mesh_name: String, inst: EntityInstantiation) -> bool:
	if HIDE_FACE_PLANES or PLANES_REPLACED.has(mesh_name):
		return false
	if PLANES_WRINKLE.has(mesh_name):
		return inst.arch_final.has_wrinkles
	return true


const SHADER_PATH := "res://Materials/character.gdshader"
const PLANE_SHADER_PATH := "res://Materials/character_plane.gdshader"
## Carpeta donde se buscan las texturas de los planos, por nombre de malla. Ver _source_texture.
const PLANE_TEXTURE_DIR := "res://Textures/character/"

## Cuánto se oscurece la piel para dibujar una arruga encima. MÁS CHICO = MÁS OSCURO.
##
## Es piel oscurecida y no negro: una línea negra sobre piel clara se lee bien, pero sobre piel oscura
## salta como un rayón de tinta. Derivarla del color de piel la hace correcta en todos los tonos.
##
## Y no es `skin_color` a secas, que fue el primer intento: una línea del mismo color que la
## superficie sobre la que está, sencillamente no se ve.
## ── COLOR DE LAS ARRUGAS ──────────────────────────────────────────────────────────────────────────
## No es "la piel multiplicada por un número". Eso daba una línea gris sucia: multiplicar en RGB baja
## el brillo Y desatura, así que a 0.28 la arruga perdía toda relación con el tono del personaje.
##
## Se hace en HSV y con tres movimientos separados, que es como se ve una arruga de verdad — piel en
## sombra, no tinta:
##
##   - **Valor** bastante más bajo, pero no al 28%: sigue siendo piel.
##   - **Saturación** un poco más ALTA. La piel en pliegue se ve más roja, no más gris.
##   - **Hue corrido hacia el rojo**, apenas. Es lo que la despega del tono base y evita que se lea como
##     una capa de opacidad encima.
const LINE_VALUE := 0.62
const LINE_SATURATION := 1.25
const LINE_HUE_SHIFT := -0.02

## OPACIDAD de la arruga, 0..1. 1 = el color de arriba tal cual; 0 = invisible (igual a la piel).
##
## ⚠ NO se puede bajar el ALPHA para esto, y es la trampa central de estos planos: el shader hace
## `ALPHA = tex.a * tint.a` con alpha scissor en 0.5, así que un alpha bajo no atenúa la línea —
## **descarta el plano entero**. Ya pasó una vez.
##
## Se hace mezclando hacia la PIEL, que sobre un fondo de piel da exactamente el mismo resultado que
## mezclar por alpha: la arruga está apoyada sobre la cara, así que el fondo siempre es piel.
const LINE_OPACITY := 0.45

## Planos cuya textura se espeja en X. Ver `uv_flip_x` en character_plane.gdshader.
##
## Tabla explícita y no "el que termina en _right", por la misma razón que MESH_ROLE lo es: si mañana
## el par espejado es otro, se ve acá y no hay que deducirlo de una convención.
const PLANE_UV_FLIP_X: Array[String] = ["eye_right_plane_mesh"]

## Un material por ROL, compartido por TODOS los personajes. Se crean una vez por sesión: cada rol
## necesita su propio material porque el look base difiere (la piel casi no se sombrea, la tela sí),
## pero el COLOR no vive acá — viaja por instancia.
static var _materials: Dictionary = {}
## Materiales de plano, cacheados POR TEXTURA — dos personajes con la misma ceja comparten material.
static var _plane_materials: Dictionary = {}
## Materiales de FLAT_GEOMETRY, cacheados por (color, textura). Ver _flat_material_for.
static var _flat_materials: Dictionary = {}


## Repinta TODOS los personajes de la escena. La usan los toggles del panel de debug: como el material
## se decide una sola vez al construir, cambiar una bandera no se ve hasta que alguien vuelve a pasar.
static func reapply_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for rb in tree.get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		apply_to((rb as Node).get_parent() as BoneInstantiator)


## WIREFRAME: pinta TODO el personaje de negro plano, sin sombreado.
##
## Vive acá y no en `CharacterDebugView` por una razón estructural: el modo de alambre del viewport no
## tiene color propio —dibuja los mismos materiales en modo línea— así que el color de las líneas **es**
## el material. Y el material lo decide este archivo, en un solo lugar, para todos los personajes.
##
## Que la decisión esté DENTRO de `apply_to` es lo que hace que no haya nada que mantener: `apply_to`
## ya corre al final de cada `initialize_skeleton`, así que un personaje que spawnee con el wireframe
## prendido nace negro solo. Y apagarlo no restaura nada guardado — simplemente vuelve a pasar por el
## camino normal, que reconstruye el material desde cero.
static var WIREFRAME_BLACK := false

static var _wire_mat: StandardMaterial3D = null

static func _wire_material() -> StandardMaterial3D:
	if _wire_mat == null:
		_wire_mat = StandardMaterial3D.new()
		_wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_mat.albedo_color = Color.BLACK
	return _wire_mat


## TEMPORAL — rol → Color, escrito por el StyleLab. Ver `_color_for`. Se borra con el lab.
static var COLOR_OVERRIDE: Dictionary = {}


## El ShaderMaterial de un rol, creándolo si hace falta. Existe para que el StyleLab pueda escribirle
## uniforms sin meter mano en `_materials`: es UNO por rol y lo comparte toda la ciudad, así que mover
## un valor acá se ve al instante en todos los personajes, sin repintar nada.
static func material_for_role(role: Role) -> ShaderMaterial:
	return _material_for(role)


static func toggle_flat_geometry(tree: SceneTree) -> void:
	FLAT_GEOMETRY = not FLAT_GEOMETRY
	reapply_all(tree)


static func toggle_monochrome(tree: SceneTree) -> void:
	MONOCHROME = not MONOCHROME
	reapply_all(tree)


## Pinta un personaje entero. La llama initialize_skeleton al final, así el spawn y cada respawn
## quedan pintados sin que nadie más se acuerde.
static func apply_to(bi: BoneInstantiator) -> void:
	if not is_instance_valid(bi) or not is_instance_valid(bi.skinned_body):
		return
	var inst := bi.entity_instantiation
	if inst == null:
		return
	# Corta seco y antes que nada: en wireframe no hay rol, ni tinte, ni textura que valga. Ver
	# WIREFRAME_BLACK.
	if WIREFRAME_BLACK:
		for m in bi.skinned_body.meshes:
			if is_instance_valid(m):
				m.material_override = _wire_material()
		return

	RiveBake.ensure_baked()  # DEV: borrar junto con rive_bake.gd cuando el arte esté cerrado
	for m in bi.skinned_body.meshes:
		if not is_instance_valid(m):
			continue
		if MESH_ROLE.has(m.name):
			var role: Role = MESH_ROLE[m.name]
			var col := _color_for(role, inst)
			if FLAT_GEOMETRY:
				m.material_override = _flat_material_for(col)
			else:
				m.material_override = _material_for(role)
				m.set_instance_shader_parameter("tint", col)
		elif PLANE_ROLE.has(m.name):
			# LOS PLANOS NO MIRAN `FLAT_GEOMETRY`. Esa bandera existe para juzgar la ESCULTURA con
			# iluminación estándar, y un plano de feature no es escultura: es un dibujo. Mandarlo por
			# `StandardMaterial3D` además perdía la regla de neutro/literal, que solo sabe hacer el
			# shader — o sea que en el modo por defecto los ojos salían teñidos.
			# ⚠ NO ALCANZA CON ESCRIBIR `visible`. `SkinnedBodyUtil.set_first_person(false)` pone
			# `visible = true` en TODAS las mallas y corre DESPUÉS de esto (vía
			# `CharacterDebugView.apply_to` → `set_character_visible`), así que pisaba la decisión: al
			# nene le aparecían arrugas y seguían viéndose los planos reemplazados por malla 3D.
			#
			# La marca queda en el nodo y `set_first_person` la respeta. Así el dueño de la decisión
			# sigue siendo este archivo, sin que las dos clases tengan que conocerse.
			var vis := _plane_visible(m.name, inst)
			m.set_meta("face_hidden", not vis)
			m.visible = vis
			var mat := _plane_material_for(m)
			if mat != null:
				m.material_override = mat
				m.set_instance_shader_parameter("tint", _color_for(PLANE_ROLE[m.name], inst))
				m.set_instance_shader_parameter("uv_flip_x",
					1.0 if PLANE_UV_FLIP_X.has(m.name) else 0.0)
				m.set_instance_shader_parameter("srgb_decode",
					1.0 if RiveFace.is_live(_source_texture(m)) else 0.0)
				# Si el artboard acepta el color ANTES de rasterizar, se lo damos ahí y el tinte de
				# arriba pasa a ser blanco: teñir dos veces oscurecería de más.
				var line_col := _line_color(inst.skin_color)
				if RiveFace.set_line_color(m.name, line_col, m.get_tree()):
					m.set_instance_shader_parameter("tint", Color.WHITE)
		else:
			_disable_vertex_color_albedo(m)


## ⚠ RED DE SEGURIDAD PARA MALLAS NO REGISTRADAS.
##
## Una malla que no está en `MESH_ROLE` ni en `PLANE_ROLE` conserva el material del .glb — y ese
## material MULTIPLICA POR EL COLOR DE VÉRTICE, porque el importador de glTF le prende
## `vertex_color_use_as_albedo` a todo lo que traiga COLOR_0.
##
## Desde que el color de vértice pasó a ser DATO (las máscaras de `pack_vertex_masks.py`) eso es una
## bomba: una malla cuyas máscaras están casi todas en cero se dibuja casi negra. Ya pasó — una cabeza
## duplicada que no estaba en las tablas salió completamente negra, y el síntoma no apunta para nada a
## su causa.
##
## En este proyecto el color de vértice NUNCA es color. Apagando esto, olvidarse de registrar una malla
## cuesta "se ve con el material de Blender" en vez de "se ve negra".
static func _disable_vertex_color_albedo(m: MeshInstance3D) -> void:
	var mesh := m.mesh
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s) as BaseMaterial3D
		if mat != null and mat.vertex_color_use_as_albedo:
			mat.vertex_color_use_as_albedo = false


## Material de `FLAT_GEOMETRY`: PBR estándar, sin shader propio. Solo para las mallas de CUERPO — los
## planos de feature ya no pasan por acá, así que no necesita textura, ni recorte, ni volteo de UV.
static func _flat_material_for(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if _flat_materials.has(key):
		return _flat_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	_flat_materials[key] = mat
	return mat


## Material de recorte para un plano de feature, con la textura que trajo el .glb.
##
## La textura se AUTORA EN BLENDER (asignás el PNG al material del plano) y acá se la re-monta sobre
## el shader de recorte. Así el flujo de trabajo es "pegá el PNG en Blender y listo", sin que haya que
## registrar cada textura del lado de Godot.
##
## Se cachea POR TEXTURA, no por personaje: dos personajes con la misma ceja comparten material y
## pipeline. Solo las texturas que sean únicas por personaje (la animada de Rive, el nametag) van a
## necesitar su propia instancia, y son las únicas que deberían.
static func _plane_material_for(mi: MeshInstance3D) -> ShaderMaterial:
	var tex := _source_texture(mi)
	if tex == null:
		return null  # todavía sin textura: se deja el material del .glb, que al menos se ve
	if _plane_materials.has(tex):
		return _plane_materials[tex]
	var mat := ShaderMaterial.new()
	mat.shader = load(PLANE_SHADER_PATH)
	mat.set_shader_parameter("albedo_texture", tex)
	_plane_materials[tex] = mat
	return mat


## La textura de un plano, buscada POR NOMBRE en la carpeta de texturas antes que en el .glb.
##
## `forehead_plane_mesh` → `res://Textures/character/forehead_plane_mesh.png`.
##
## Buscar por convención y no por una tabla es a propósito: exportás el PNG desde Rive, lo guardás
## encima del archivo, y Godot lo recarga — sin re-exportar el .glb ni tocar código. Iterar sobre el
## dibujo es el bucle que más veces se va a repetir, así que es el que tiene que ser corto.
##
## Si no hay archivo, cae al material del .glb, así que asignar la textura en Blender también sirve.
static func _source_texture(mi: MeshInstance3D) -> Texture2D:
	# RIVE VIVO PRIMERO, PNG DESPUÉS. Cuando `RiveFace` está apagado o falla devuelve null y esto sigue
	# igual que siempre, así que la migración se puede hacer de a un artboard sin ramas nuevas.
	var live := RiveFace.texture_for(mi.name, mi.get_tree())
	if live != null:
		return live
	var tex := _load_png(mi.name)
	if tex != null:
		return tex
	# Un par L/R cae al nombre SIN lado: `eye_left_plane_mesh` → `eye_plane_mesh`. Así un solo artboard
	# de Rive viste los dos ojos, que es el caso normal, y el día que uno tenga un parche alcanza con
	# dejar `eye_right_plane_mesh.png` en la carpeta — lo específico gana sobre lo genérico, sin código.
	var generic := mi.name.replace("_left", "").replace("_right", "")
	if generic != mi.name:
		var live_generic := RiveFace.texture_for(generic, mi.get_tree())
		if live_generic != null:
			return live_generic
		tex = _load_png(generic)
		if tex != null:
			return tex
	var mesh := mi.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var src := mesh.surface_get_material(0) as BaseMaterial3D
	return src.albedo_texture if src != null else null


## En el EDITOR lee el PNG del disco, no el recurso importado.
##
## Godot importa los PNG a su propio caché, y un juego ya corriendo no se entera de que el archivo
## cambió. Como RiveBake reescribe las texturas justo antes de que se usen, leer el recurso importado
## mostraría siempre el dibujo de la corrida ANTERIOR — el bucle de iteración quedaría desfasado un
## run, que es exactamente lo que este camino venía a evitar.
##
## Exportado no aplica: ahí no hay bake, el PNG fuente puede no estar, y el recurso importado es lo
## correcto y lo más rápido.
static func _load_png(base: String) -> Texture2D:
	var path := PLANE_TEXTURE_DIR + base + ".png"
	if OS.has_feature("editor"):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			return ImageTexture.create_from_image(img)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Oscurece un color CONSERVANDO el alpha en 1. Ver el aviso en _color_for.
## Color de arruga a partir del de piel. Ver LINE_VALUE.
##
## ⚠ EL ALPHA VUELVE EN 1.0 SIEMPRE, y no es cosmético: el shader hace `ALPHA = tex.a * tint.a` y el
## alpha scissor descarta a 0.5, así que un tinte con alpha bajo no atenúa la línea — **borra el plano
## entero**. Fue el bug de `skin_color * LINE_DARKEN`, que en Godot multiplica también el alpha.
static func _line_color(skin: Color) -> Color:
	var full := Color.from_hsv(
		fposmod(skin.h + LINE_HUE_SHIFT, 1.0),
		clampf(skin.s * LINE_SATURATION, 0.0, 1.0),
		clampf(skin.v * LINE_VALUE, 0.0, 1.0),
		1.0)
	var out := skin.lerp(full, LINE_OPACITY)
	out.a = 1.0
	return out


static func _color_for(role: Role, inst: EntityInstantiation) -> Color:
	# PROP ES "SIN TEÑIR" POR DEFINICIÓN, y eso manda también en monocromo — por eso va ANTES.
	#
	# El tinte multiplica (`ALBEDO = tex.rgb * tint.rgb`), así que devolver blanco es lo mismo que
	# multiplicar por 1: la textura pasa literal. Es lo que hace que un plano de ojo dibujado en Rive
	# conserve su contorno negro Y su blanco interior, y en general su escala de grises entera.
	#
	# Con el gris de monocromo encima, el negro seguía negro —negro por cualquier cosa es negro— pero
	# todo lo claro se apagaba. O sea que el filtro se comía justo el rango que el dibujo usa.
	#
	# Esto NO rompe el propósito del monocromo: el arte de features ya viene en escala de grises, así
	# que dejarlo literal sigue siendo monocromo. El día que un prop tenga color de verdad (una tarjeta,
	# por ejemplo), va a aparecer a todo color en este modo — y ahí sí querrá su propio rol.
	if role == Role.PROP:
		return Color.WHITE
	# TEMPORAL — lo escribe el StyleLab. Pisa el color del preset para poder probar combinaciones sin
	# editar `AppearancePreset.PRESETS`, que es `const`. Vacío = no interfiere.
	if COLOR_OVERRIDE.has(role):
		return COLOR_OVERRIDE[role]
	if MONOCHROME:
		var g: float = MONOCHROME_GREYS.get(role, 0.8)
		return Color(g, g, g, 1.0)
	match role:
		Role.SKIN:    return inst.skin_color
		Role.CLOTH:   return inst.cloth_color
		Role.HAIR:    return inst.hair_color
		Role.LEATHER: return inst.leather_color
		Role.LINE:    return _line_color(inst.skin_color)
		_:            return Color.WHITE


## Un material por ROL, compartido por TODOS los personajes. Se crea una vez por sesión: cada rol puede
## querer un look base distinto (la piel casi no se sombrea, la tela sí), pero el COLOR no vive acá —
## viaja por `instance uniform`, o sea por personaje.
##
## SIN VALORES POR ROL: los cuatro arrancan en los defaults del shader, que son el NEUTRO — iluminación
## estándar, indistinguible del modo sin shader. Ese es el punto de partida elegido: el estilo se
## construye desde ahí con el StyleLab (F2), no desde un preset que ya decidió cosas.
##
## Acá vivía una calibración por rol despejada a mano (piel `shadow_value` 0.42, `shadow_saturation`
## 1.67, y equivalentes para tela, pelo y cuero). Estaba resuelta para el modelo ANTERIOR del shader,
## donde el terminador era half-lambert fijo y las bandas siempre activas, así que esos números ya no
## significan lo mismo. Quedan en el historial de git como referencia.
##
## Cuando el StyleLab devuelva un look cerrado, los valores vuelven acá como un `match role:` otra vez
## y el lab se borra.
static func _material_for(role: Role) -> ShaderMaterial:
	if _materials.has(role):
		return _materials[role]
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	_materials[role] = mat
	return mat
