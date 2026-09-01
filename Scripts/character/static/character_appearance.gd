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
	"hands_mesh": Role.SKIN,
	"body_mesh":  Role.CLOTH,
	"arms_mesh":  Role.CLOTH,
	"hair_mesh":  Role.HAIR,
	"hair_mesh2": Role.HAIR,   # el nombre que tiene hoy en Blender
	"wrist_mesh": Role.SKIN,   # piel, igual que la mano
	"shoes_mesh": Role.LEATHER,
}

## PLANOS DE FEATURE → de qué color se tiñen. La textura aporta la FORMA (por el alpha) y opcionalmente
## sombreado interno en escala de grises; el color sale del seed.
##
## Por eso las arrugas se tiñen con la PIEL y las cejas con el PELO: una sola textura compartida por
## toda la ciudad se adapta sola a cualquier tono. `Role.PROP` = sin teñir, la textura manda (ojos,
## boca, nariz, tarjeta).
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
	"eye_left_plane_mesh":    Role.PROP,
	"eye_right_plane_mesh":   Role.PROP,
	"eyes_plane_mesh":        Role.PROP,   # por si no se separan
	"mouth_plane_mesh":       Role.PROP,
	"nose_plane_mesh":        Role.PROP,
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
static var FLAT_GEOMETRY := false

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
	Role.PROP:    0.72,
}

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
const LINE_DARKEN := 0.28

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
	RiveBake.ensure_baked()  # DEV: borrar junto con rive_bake.gd cuando el arte esté cerrado
	for m in bi.skinned_body.meshes:
		if not is_instance_valid(m):
			continue
		if MESH_ROLE.has(m.name):
			var role: Role = MESH_ROLE[m.name]
			var col := _color_for(role, inst)
			if FLAT_GEOMETRY:
				m.material_override = _flat_material_for(col, null)
			else:
				m.material_override = _material_for(role)
				m.set_instance_shader_parameter("tint", col)
		elif PLANE_ROLE.has(m.name):
			var plane_role: Role = PLANE_ROLE[m.name]
			var plane_col := _color_for(plane_role, inst)
			if FLAT_GEOMETRY:
				var tex := _source_texture(m)
				if tex != null:
					m.material_override = _flat_material_for(plane_col, tex)
			else:
				var mat := _plane_material_for(m)
				if mat != null:
					m.material_override = mat
					m.set_instance_shader_parameter("tint", plane_col)


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
	var tex := _load_png(mi.name)
	if tex != null:
		return tex
	# Un par L/R cae al nombre SIN lado: `eye_left_plane_mesh` → `eye_plane_mesh`. Así un solo artboard
	# de Rive viste los dos ojos, que es el caso normal, y el día que uno tenga un parche alcanza con
	# dejar `eye_right_plane_mesh.png` en la carpeta — lo específico gana sobre lo genérico, sin código.
	var generic := mi.name.replace("_left", "").replace("_right", "")
	if generic != mi.name:
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
static func _darken(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


static func _color_for(role: Role, inst: EntityInstantiation) -> Color:
	if MONOCHROME:
		var g: float = MONOCHROME_GREYS.get(role, 0.8)
		return Color(g, g, g, 1.0)
	match role:
		Role.SKIN:    return inst.skin_color
		Role.CLOTH:   return inst.cloth_color
		Role.HAIR:    return inst.hair_color
		Role.LEATHER: return inst.leather_color
		# ⚠ NO `skin_color * LINE_DARKEN`: en Godot multiplicar un Color por un float multiplica TAMBIÉN
		# el alpha. El tint salía con a=0.28, el shader hace `ALPHA = tex.a * tint.a`, y el alpha
		# scissor (0.5) descartaba el plano ENTERO. No es que la línea se viera tenue — no se dibujaba.
		Role.LINE:    return _darken(inst.skin_color, LINE_DARKEN)
		_:            return Color.WHITE


## El look base por rol. Son los números que se van a tunear cuando se mire el personaje de verdad;
## lo que importa acá es que sean POCOS materiales, no cuáles.
## Material de FLAT_GEOMETRY: PBR estándar, sin shader propio. Con textura sale con alpha scissor,
## igual que el shader de recorte, para que un plano de cara no se dibuje como un cuadrado negro.
##
## Se cachea por (color, textura) y no por rol, porque acá el color vive EN el material: dos personajes
## del mismo color siguen compartiendo uno.
static func _flat_material_for(color: Color, tex: Texture2D) -> StandardMaterial3D:
	var key := "%s|%d" % [color.to_html(false), tex.get_instance_id() if tex != null else 0]
	if _flat_materials.has(key):
		return _flat_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	if tex != null:
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flat_materials[key] = mat
	return mat


static func _material_for(role: Role) -> ShaderMaterial:
	if _materials.has(role):
		return _materials[role]
	var shader: Shader = load(SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	match role:
		Role.SKIN:
			# Estos tres números NO son a ojo: son la solución de `shadow_of()` para que la piel del
			# preset (81,54,47) dé la sombra de referencia (60,32,20). Despejado en espacio LINEAL,
			# que es donde el shader trabaja — hacer la cuenta en sRGB da otro resultado.
			#
			#   piel   → lineal (0.0825, 0.0370, 0.0283), luminancia 0.0460
			#   sombra → lineal (0.0450, 0.0143, 0.0069)
			#   ⇒ value 0.42, saturation 1.67  →  reproduce (60, 30, 20) contra (60, 32, 20) pedido
			#
			# El sesgo de tono va en CERO: la sombra de referencia es más CÁLIDA que la piel, no más
			# fría, así que el azul del cielo empujaría para el lado contrario. Es el caso donde
			# "la sombra es el propio color, más oscuro y más saturado" se cumple literal.
			mat.set_shader_parameter("shadow_value", 0.42)
			mat.set_shader_parameter("shadow_saturation", 1.67)
			mat.set_shader_parameter("shadow_hue_amount", 0.0)
			mat.set_shader_parameter("rim_strength", 0.25)
		Role.CLOTH:
			mat.set_shader_parameter("shadow_value", 0.34)
			mat.set_shader_parameter("shadow_saturation", 1.2)
			mat.set_shader_parameter("shadow_hue_amount", 0.3)
			mat.set_shader_parameter("rim_strength", 0.35)
		Role.HAIR:
			mat.set_shader_parameter("shadow_value", 0.30)
			mat.set_shader_parameter("shadow_saturation", 1.15)
			mat.set_shader_parameter("shadow_hue_amount", 0.25)
			mat.set_shader_parameter("rim_strength", 0.35)
		Role.LEATHER:
			mat.set_shader_parameter("shadow_value", 0.28)
			mat.set_shader_parameter("shadow_saturation", 1.1)
			mat.set_shader_parameter("shadow_hue_amount", 0.3)
			mat.set_shader_parameter("rim_strength", 0.5)
		_:
			pass
	_materials[role] = mat
	return mat
