class_name SandboxParcel
extends Node3D

## UNA PARCELA DEL DESIGN SANDBOX: un arquetipo con su semilla actual, el individuo construido encima, y
## las tres zonas alrededor (ver DesignSandbox): la parcela —un plano apenas más oscuro que el piso—, la
## zona de interacción —un marco— y, sin dibujar, la separación con los vecinos. El tamaño sale del
## `max_footprint` del arquetipo una sola vez: regenerar cambia el individuo, nunca la parcela.

## El plano de la parcela va apenas sobre el piso, y lo que se muestra apenas sobre él (ver
## BuildingArchetype.build): una vereda de 8 mm a escala tiene que quedar encima, no debajo.
const PLANE_LIFT := 0.002
const FRAME_LIFT := 0.02
const FRAME_WIDTH := 0.08
const PARCEL_COLOR := Color(0.74, 0.72, 0.68)
const FRAME_COLOR := Color(0.55, 0.53, 0.5)
const LABEL_COLOR := Color(0.3, 0.29, 0.27)
const FLASH_SECONDS := 0.35
const FLASH_ALPHA := 0.7

var archetype: SeededArchetype = null
var category := ""
var seed_value := 0
## Ancho y profundidad de la parcela, en metros.
var size := Vector2.ZERO
## Cuánto sale la zona de interacción alrededor de la parcela.
var interact_pad := 0.0

var _root: Node3D = null
var _flashing: Array[GeometryInstance3D] = []


func setup(p_archetype: SeededArchetype, p_category: String, p_size: Vector2, p_pad: float,
		p_seed: int) -> void:
	archetype = p_archetype
	category = p_category
	size = p_size
	interact_pad = p_pad
	name = "%s · %s" % [category, archetype.display_name]
	_draw()
	regenerate(p_seed, false)


## La zona de interacción en el plano XZ del mundo.
func interaction_rect() -> Rect2:
	var half := size * 0.5 + Vector2.ONE * interact_pad
	var centre := Vector2(global_position.x, global_position.z)
	return Rect2(centre - half, half * 2.0)


func contains(point: Vector3) -> bool:
	return interaction_rect().has_point(Vector2(point.x, point.z))


## Otro individuo: se libera el anterior, se construye el nuevo con `new_seed` y, si se pide, destella en
## blanco para que se note que hubo regeneración.
func regenerate(new_seed: int, flash := true) -> void:
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	seed_value = new_seed
	_root = archetype.build(new_seed, self)
	if _root == null:
		_root = Node3D.new()
		add_child(_root)
	_check_footprint()
	if flash:
		_flash()


## Lo que dice el panel de este individuo.
func info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("%s · %s" % [category, archetype.display_name])
	lines.append("semilla: %d" % seed_value)
	lines.append_array(archetype.describe(seed_value))
	return lines


# ── Dibujo ───────────────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var plane := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = size
	plane.mesh = quad
	plane.material_override = _flat(PARCEL_COLOR)
	plane.position = Vector3(0.0, PLANE_LIFT, 0.0)
	add_child(plane)

	# El marco de la zona de interacción: cuatro listones sobre sus bordes.
	var half := size * 0.5 + Vector2.ONE * interact_pad
	for edge in 4:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		var along_x := edge < 2
		box.size = Vector3(half.x * 2.0 if along_x else FRAME_WIDTH, FRAME_WIDTH,
			FRAME_WIDTH if along_x else half.y * 2.0)
		bar.mesh = box
		bar.material_override = _flat(FRAME_COLOR)
		var sign := 1.0 if edge % 2 == 0 else -1.0
		bar.position = Vector3(0.0 if along_x else half.x * sign, FRAME_LIFT,
			half.y * sign if along_x else 0.0)
		add_child(bar)

	var label := Label3D.new()
	label.text = archetype.display_name
	label.font_size = 48
	label.modulate = LABEL_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.4, half.y + 0.3)
	add_child(label)


static func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Un destello aditivo sobre toda la geometría del individuo, que se apaga solo.
func _flash() -> void:
	_clear_flash()
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.albedo_color = Color(1.0, 1.0, 1.0, FLASH_ALPHA)
	for node in _root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry == null or not geometry.visible:
			continue
		geometry.material_overlay = overlay
		_flashing.append(geometry)
	if _root is GeometryInstance3D:
		(_root as GeometryInstance3D).material_overlay = overlay
		_flashing.append(_root)
	var tween := create_tween()
	tween.tween_property(overlay, "albedo_color:a", 0.0, FLASH_SECONDS)
	tween.finished.connect(_clear_flash)


func _clear_flash() -> void:
	for geometry in _flashing:
		if is_instance_valid(geometry):
			geometry.material_overlay = null
	_flashing.clear()


## Si el individuo se sale de la parcela en XZ, es el `max_footprint` del arquetipo el que está mal.
func _check_footprint() -> void:
	var bounds := AABB()
	var first := true
	for node in _root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var box := visual.global_transform * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	var local := bounds.position - global_position
	var over := Vector2(maxf(-local.x, local.x + bounds.size.x) - size.x * 0.5,
		maxf(-local.z, local.z + bounds.size.z) - size.y * 0.5)
	if over.x > 0.05 or over.y > 0.05:
		push_warning("[Sandbox] %s se sale de su parcela por (%.2f, %.2f) m: corregir max_footprint"
			% [name, maxf(over.x, 0.0), maxf(over.y, 0.0)])
