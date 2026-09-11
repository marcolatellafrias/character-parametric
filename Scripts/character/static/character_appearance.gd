class_name CharacterAppearance

## COLOR DE PERSONAJE POR SEED, con UN material compartido.
##
## Cada malla del modelo cumple un ROL (piel, tela, pelo, cuero), y cada rol tiene un color que sale
## del seed. Lo que NO pasa es que cada personaje tenga su propio material: el color viaja por un
## `instance uniform`, que vive en el MeshInstance3D y no en el material, así que toda la ciudad
## comparte un material y un pipeline.
##
## Esa decisión es barata hoy y cara después: con material por personaje, una calle de peatones
## multiplica draw calls y memoria de textura, y sacarlo implica reescribir cómo se pinta todo.
## Ver technical/character-appearance-system.md.

enum Role { SKIN, CLOTH, HAIR, LEATHER }

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
}

const SHADER_PATH := "res://Materials/character.gdshader"

## Un material por ROL, compartido por TODOS los personajes. Se crean una vez por sesión: cada rol
## necesita su propio material porque el look base difiere (la piel casi no se sombrea, la tela sí),
## pero el COLOR no vive acá — viaja por instancia.
static var _materials: Dictionary = {}
## Materiales de FLAT_GEOMETRY, cacheados por color. Ver _flat_material_for.
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
	# Corta seco y antes que nada: en wireframe no hay rol ni tinte que valga. Ver WIREFRAME_BLACK.
	if WIREFRAME_BLACK:
		for m in bi.skinned_body.meshes:
			if is_instance_valid(m):
				m.material_override = _wire_material()
		return

	for m in bi.skinned_body.meshes:
		if not is_instance_valid(m) or not MESH_ROLE.has(m.name):
			continue
		var role: Role = MESH_ROLE[m.name]
		var col := _color_for(role, inst)
		if FLAT_GEOMETRY:
			m.material_override = _flat_material_for(col)
		else:
			m.material_override = _material_for(role)
			m.set_instance_shader_parameter("tint", col)


static func _color_for(role: Role, inst: EntityInstantiation) -> Color:
	if MONOCHROME:
		var g: float = MONOCHROME_GREYS.get(role, 0.8)
		return Color(g, g, g, 1.0)
	match role:
		Role.SKIN:    return inst.skin_color
		Role.CLOTH:   return inst.cloth_color
		Role.HAIR:    return inst.hair_color
		Role.LEATHER: return inst.leather_color
		_:            return Color.WHITE


## Material de FLAT_GEOMETRY: PBR estándar, sin shader propio.
##
## Se cachea por color y no por rol, porque acá el color vive EN el material: dos personajes del mismo
## color siguen compartiendo uno.
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


## El look base por rol. Son los números que se van a tunear cuando se mire el personaje de verdad;
## lo que importa acá es que sean POCOS materiales, no cuáles.
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
	_materials[role] = mat
	return mat
