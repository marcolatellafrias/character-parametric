class_name ControlArchetype
extends SeededArchetype

## UN TIPO DE CONTROL —botón, palanca, volante, perilla— como arquetipo: QUÉ es (su componente, su tamaño
## en celdas y cómo se maneja: ver `definition`) y CÓMO SE VE, en dos mallas separadas de su lógica
## (ControllableInteractable): la BASE, que no se mueve y cuelga del cuerpo del control, y la PARTE
## MÓVIL, lo que el jugador agarra, que cuelga del componente y por eso rota o se hunde con él.
##
## Las dos se diseñan en el cubo unitario del control —`x` a lo largo del tablero, `y` subiendo por él,
## `z` hacia quien lo mira, con z = 0 en la superficie del tablero— y se escalan a la caja del control:
## sus celdas menos el margen, por CONTROL_DEPTH de profundidad (ver ProceduralDashboard). Así el mismo
## estilo sirve para un botón de 2 × 2 y para el de la compuerta, de 4 × 4. Lo que tiene que ser redondo
## de verdad (la bola de una palanca) se calcula con el tamaño en metros.
##
## Todo tablero viste sus controles con esto (`dress`), y toda definición de control sale de acá
## (`definition_of`): la nave solo agrega lo suyo —cuánto recorre, dónde descansa—. Un estilo nuevo es
## una entrada más del catálogo, y aparece solo en la fila "Controles" del sandbox. La semilla no varía
## nada todavía.

const BASE_COLOR := Color(0.32, 0.33, 0.36)
## El pivote de las mallas: el centro del control sobre la superficie del tablero, que es donde está el
## origen de su cuerpo y de su componente.
const ON_PANEL := Vector3(0.5, 0.5, 0.0)
## El atril del sandbox: alto del poste y cuánto se inclina la placa hacia arriba.
const STAND_HEIGHT := 1.05
const STAND_TILT_DEG := 30.0

## Por qué nombre lo pide una definición (`ControlDefinition.archetype_name`).
var key := "button"
var type: ControlDefinition.ControlType = ControlDefinition.ControlType.TOUCH
var grid_size := Vector2i(2, 2)
var moving_color := Color(0.85, 0.35, 0.25)

static var _by_key: Dictionary = {}


func _init(p_key := "button", p_name := "Botón", p_type: ControlDefinition.ControlType = ControlDefinition.ControlType.TOUCH,
		p_grid := Vector2i(2, 2), p_color := Color(0.85, 0.35, 0.25)) -> void:
	key = p_key
	display_name = p_name
	type = p_type
	grid_size = p_grid
	moving_color = p_color


## Los estilos que hay: la fila "Controles" del sandbox.
static func catalogue() -> Array[ControlArchetype]:
	return [
		ControlArchetype.new("button", "Botón", ControlDefinition.ControlType.TOUCH, ProceduralDashboard.BUTTON,
			Color(0.85, 0.35, 0.25)),
		ControlArchetype.new("power", "Botón de encendido", ControlDefinition.ControlType.TOUCH,
			ProceduralDashboard.BUTTON, Color(0.3, 0.8, 0.4)),
		ControlArchetype.new("lever", "Palanca", ControlDefinition.ControlType.ONE_AXIS, ProceduralDashboard.LEVER,
			Color(0.9, 0.6, 0.2)),
		ControlArchetype.new("wheel", "Volante", ControlDefinition.ControlType.ROTATING, ProceduralDashboard.WHEEL,
			Color(0.36, 0.24, 0.2)),
		ControlArchetype.new("knob", "Perilla", ControlDefinition.ControlType.ROTATING, Vector2i(6, 6),
			Color(0.75, 0.75, 0.72)),
		ControlArchetype.new("stick", "Palanca de dos ejes", ControlDefinition.ControlType.TWO_AXIS, Vector2i(6, 6),
			Color(0.85, 0.85, 0.3)),
	]


## El estilo `key`; el botón si no existe.
static func of(key: String) -> ControlArchetype:
	if _by_key.is_empty():
		for archetype in catalogue():
			_by_key[archetype.key] = archetype
	return _by_key.get(key, _by_key["button"])


static func definition_of(key: String) -> ControlDefinition:
	return of(key).definition()


## El estilo que pide una definición: por nombre, o si no lo dice —una armada a mano—, el de su tipo.
static func for_definition(definition: ControlDefinition) -> ControlArchetype:
	if definition.archetype_name != "":
		return of(definition.archetype_name)
	match definition.type:
		ControlDefinition.ControlType.ONE_AXIS:
			return of("lever")
		ControlDefinition.ControlType.TWO_AXIS:
			return of("stick")
		ControlDefinition.ControlType.ROTATING:
			return of("wheel" if definition.grid_size.x >= ProceduralDashboard.WHEEL.x else "knob")
	return of("button")


## La definición de un control de este estilo: su tipo, su tamaño y cómo se maneja. Quien lo coloca
## agrega lo suyo encima.
func definition() -> ControlDefinition:
	var d := ControlDefinition.new()
	d.archetype_name = key
	d.type = type
	d.grid_size = grid_size
	match key:
		"power":
			d.is_toggle = true
		"lever":
			d.rotation_axis_local = Vector3.RIGHT
		"wheel":
			# Como el del Cybertruck: se gira arrastrando el mouse de costado y a fondo hace tope, sin dar
			# una vuelta; suelto vuelve al centro. Sale del tablero sobre un eje.
			d.rotation_axis_local = Vector3.BACK
			d.rotate_input = RotatingComponent.InputMode.MOUSE_HORIZONTAL
			d.rotate_sensitivity = 0.0015
			d.rotate_max = 1.2
			d.height_offset = 0.16
			d.auto_return = true
		"knob":
			# Gira con la ruedita alrededor de la normal del tablero, como un dial, apenas despegada de él.
			d.rotation_axis_local = Vector3.BACK
			d.height_offset = 0.02
		"stick":
			d.auto_return = true
	return d


# ── Las mallas ───────────────────────────────────────────────────────────────────────────────────

## La base: lo que no se mueve, apoyado en el tablero.
func base_unit(_size: Vector3) -> UnitMesh:
	var m := UnitMesh.new()
	match key:
		"power":
			m.add_box(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 0.25), BASE_COLOR)
			m.add_cylinder_z(Vector3(0.1, 0.1, 0.25), Vector3(0.9, 0.9, 0.4), BASE_COLOR.lightened(0.2), 16)
		"lever":
			m.add_box(Vector3(0.25, 0.0, 0.0), Vector3(0.75, 1.0, 0.2), BASE_COLOR)
			m.add_box(Vector3(0.3, 0.42, 0.2), Vector3(0.7, 0.58, 0.45), BASE_COLOR.darkened(0.3))
		"wheel":
			m.add_cylinder_z(Vector3(0.3, 0.3, 0.0), Vector3(0.7, 0.7, 0.25), BASE_COLOR, 16)
		"knob":
			m.add_cylinder_z(Vector3(0.05, 0.05, 0.0), Vector3(0.95, 0.95, 0.3), BASE_COLOR, 16)
		"stick":
			m.add_box(Vector3(0.1, 0.1, 0.0), Vector3(0.9, 0.9, 0.3), BASE_COLOR)
			m.add_cylinder_z(Vector3(0.3, 0.3, 0.3), Vector3(0.7, 0.7, 0.6), BASE_COLOR.darkened(0.3), 16)
		_:
			m.add_box(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 0.25), BASE_COLOR)
	return m


## La parte móvil: lo que el componente rota o hunde, desde el tablero hacia afuera.
func moving_unit(size: Vector3) -> UnitMesh:
	var m := UnitMesh.new()
	match key:
		"power":
			m.add_cylinder_z(Vector3(0.25, 0.25, 0.3), Vector3(0.75, 0.75, 0.8), moving_color, 16)
		"lever":
			m.add_box(Vector3(0.45, 0.5, 0.28), Vector3(0.55, 0.9, 0.5), moving_color.darkened(0.35))
			m.add_box(Vector3(0.36, 0.84, 0.2), Vector3(0.64, 1.0, 0.6), moving_color)
		"wheel":
			m.add_ring_z(Vector3(0.02, 0.02, 0.0), Vector3(0.98, 0.98, 0.45), 0.14, moving_color, 24)
			m.add_cylinder_z(Vector3(0.36, 0.36, 0.05), Vector3(0.64, 0.64, 0.5), BASE_COLOR, 16)
			m.add_box(Vector3(0.47, 0.1, 0.1), Vector3(0.53, 0.9, 0.35), moving_color.lightened(0.4))
			m.add_box(Vector3(0.1, 0.47, 0.1), Vector3(0.9, 0.53, 0.35), moving_color.lightened(0.4))
		"knob":
			m.add_cylinder_z(Vector3(0.22, 0.22, 0.0), Vector3(0.78, 0.78, 0.7), moving_color, 16)
			m.add_box(Vector3(0.47, 0.5, 0.55), Vector3(0.53, 0.76, 0.8), BASE_COLOR)
		"stick":
			# La punta está donde el componente pone la mano (ver TwoAxisComponent), y la bola es redonda.
			var tip := (0.5 * size.z + 0.55 * minf(size.x, size.y)) / size.z
			var r := Vector3(0.02, 0.02, 0.02) / size
			m.add_box(Vector3(0.47, 0.47, 0.4), Vector3(0.53, 0.53, tip), BASE_COLOR.lightened(0.3))
			m.add_cylinder_z(Vector3(0.5, 0.5, tip) - r, Vector3(0.5, 0.5, tip) + r, moving_color, 16)
		_:
			m.add_cylinder_z(Vector3(0.15, 0.15, 0.2), Vector3(0.85, 0.85, 0.65), moving_color, 16)
	return m


## Viste un control ya colocado: la base bajo su cuerpo, la parte móvil bajo el componente —donde éste la
## quiera: un volante sale del tablero— y, si sale, el eje que la sostiene.
func dress(body: StaticBody3D, interactable: ControllableInteractable, size: Vector3) -> void:
	body.add_child(_instance(base_unit(size), size))
	var offset := interactable.mesh_offset()
	var moving := _instance(moving_unit(size), size)
	moving.position = offset
	interactable.add_child(moving)
	interactable.highlighted.append(moving)
	if offset.z > 0.0:
		var shaft := UnitMesh.new()
		shaft.add_cylinder_z(Vector3(0.44, 0.44, 0.0), Vector3(0.56, 0.56, 1.0), BASE_COLOR)
		body.add_child(_instance(shaft, Vector3(size.x, size.y, offset.z)))


static func _instance(unit: UnitMesh, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit.build_mesh(size, ON_PANEL)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mi.material_override = material
	return mi


# ── La muestra del sandbox ───────────────────────────────────────────────────────────────────────

func max_footprint() -> Vector2:
	return Vector2(1.0, 1.0)


## Un atril: un poste con una placa inclinada, y un tablero de un solo control en el medio.
func build(_seed_value: int, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Stand"
	parent.add_child(root)
	var material := StandardMaterial3D.new()
	material.albedo_color = BASE_COLOR.darkened(0.4)
	# La placa mira a -Z, como todo en el sandbox, inclinada hacia arriba.
	var plate := Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-STAND_TILT_DEG)),
		Vector3(0.0, STAND_HEIGHT, 0.0))
	var cells := grid_size + Vector2i(2, 2)
	var plate_size := Vector2(cells) * ProceduralDashboard.CELL + Vector2(0.08, 0.08)
	_box(root, Vector3(0.08, STAND_HEIGHT, 0.08), Transform3D(Basis(), Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)), material)
	_box(root, Vector3(plate_size.x, plate_size.y, 0.04), plate * Transform3D(Basis(), Vector3(0.0, 0.0, -0.02)), material)

	var slot := DashboardSlot.new()
	slot.cell = Vector2i(1, 1)
	slot.definition = definition()
	var preset := DashboardPreset.new()
	preset.fill_remaining_random = false
	var slots: Array[DashboardSlot] = [slot]
	preset.fixed_slots = slots
	var dash := ProceduralDashboard.new()
	dash.name = "Dashboard"
	dash.grid_columns = cells.x
	dash.grid_rows = cells.y
	dash.custom_preset = preset
	# La grilla arranca en su esquina superior izquierda: corrida, queda centrada en la placa.
	dash.transform = plate * Transform3D(Basis(), Vector3(-cells.x * 0.5, cells.y * 0.5, 0.0) * ProceduralDashboard.CELL)
	root.add_child(dash)
	return root


static func _box(parent: Node3D, size: Vector3, xf: Transform3D, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = material
	mi.transform = xf
	parent.add_child(mi)


func describe(_seed_value: int) -> PackedStringArray:
	return PackedStringArray(["%s · %d × %d celdas" % [ControlDefinition.ControlType.keys()[type], grid_size.x, grid_size.y]])
