@tool
class_name ProceduralDashboard
extends Node3D

enum PresetType { NONE, STEERING_WHEEL }

## ── LA CELDA ────────────────────────────────────────────────────────────────────────────────────
## Unidad mínima de ubicación: 4 cm, sin separación entre celdas. Es chica A PROPÓSITO: un control
## ocupa muchas (un botón 2 × 2, una palanca 6 × 12), y a cambio los controles pueden ser tan chicos
## como uno real y ubicarse con precisión. Más fina no sirve: 4 cm es lo más chico que se apunta bien
## con la mira a un brazo de distancia.
##
## La nave se mide en esta misma celda (ver ShipHull). Cambiarla cambia el tamaño de todo lo que está
## contado en celdas —dashboards, controles y casco—: es una decisión de diseño, no una perilla.
const CELL := 0.04
## Profundidad de la caja de cada control.
const CONTROL_DEPTH := 0.06
## Aire que deja cada control de su lado, dentro de su área, para que dos vecinos no se toquen.
const CONTROL_MARGIN := 0.01

## Tamaños estándar de control, en celdas.
const BUTTON := Vector2i(2, 2)
const LEVER  := Vector2i(6, 12)
const WHEEL  := Vector2i(12, 12)

## Por defecto, 1.28 × 0.96 m.
@export var grid_columns: int        = 32
@export var grid_rows:    int        = 24
@export var seed_value:   int        = 0
@export var show_debug:   bool       = true
@export var preset_type:  PresetType = PresetType.NONE
## Preset armado desde código. Si está, manda sobre `preset_type`. Existe para quien construye
## dashboards en tiempo de ejecución —la nave arma los suyos según su layout— sin tener que agregar
## cada disposición como un caso nuevo del enum.
@export var custom_preset: DashboardPreset = null

# [type_id, tamaño en celdas, peso]
const _DEFS: Array = [
	[0, BUTTON, 3.0],
	[1, Vector2i(6, 6), 2.0],
	[1, Vector2i(12, 6), 1.5],
	[1, LEVER, 1.5],
	[2, Vector2i(6, 6), 2.0],
	[2, Vector2i(12, 12), 1.0],
	[3, Vector2i(6, 6), 2.0],
	[3, WHEEL, 1.2],
]

var _grid: Array                 = []
var _rng:  RandomNumberGenerator = null
## Índice incremental por control colocado (orden determinístico) → nombre estable "ctrl_N" para que
## el path del control coincida en todas las máquinas y el sync por RPC rutee. Ver ControllableInteractable.
var _ctrl_index: int             = 0

func _ready() -> void:
	if Engine.is_editor_hint():
		generate()
		return
	generate()
	# Cliente que se une: pedir al host el estado actual de los controles. El dashboard se regenera
	# determinístico (en default); los que alguien movió hay que traerlos (permanencia). Ver multiplayer.md.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_control_states.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_control_states() -> void:
	if not multiplayer.is_server():
		return
	var states: Array = []
	for i in _ctrl_index:
		var ctrl := get_node_or_null("ctrl_%d/Control" % i) as ControllableInteractable
		states.append(ctrl.get_sync_state() if is_instance_valid(ctrl) else null)
	_receive_control_states.rpc_id(multiplayer.get_remote_sender_id(), states)

@rpc("authority", "reliable", "call_remote")
func _receive_control_states(states: Array) -> void:
	for i in mini(_ctrl_index, states.size()):
		var ctrl := get_node_or_null("ctrl_%d/Control" % i) as ControllableInteractable
		if is_instance_valid(ctrl) and states[i] != null:
			ctrl.apply_sync_state(states[i])

func generate() -> void:
	for child in get_children():
		child.queue_free()

	_rng        = RandomNumberGenerator.new()
	_rng.seed   = seed_value
	_ctrl_index = 0
	_grid       = []
	for _c in grid_columns:
		var col: Array[bool] = []
		for _r in grid_rows:
			col.append(false)
		_grid.append(col)

	var preset := _build_preset()

	# ── 1. Place fixed slots from preset ──────────────────────────────────────
	if is_instance_valid(preset):
		for slot in preset.fixed_slots:
			var c := slot.cell
			if c.x < 0 or c.x >= grid_columns or c.y < 0 or c.y >= grid_rows:
				continue
			if not is_instance_valid(slot.definition):
				_grid[c.x][c.y] = true
				continue
			var def := slot.definition
			if not _fits(c, def.grid_size):
				# Can't place — mark only the origin cell as empty so the
				# random pass doesn't try to fill it with something unexpected.
				_grid[c.x][c.y] = true
				continue
			_place_definition(c, def)
			_occupy(c, def.grid_size)

		if not preset.fill_remaining_random:
			return

	# ── 2. Fill remaining cells with seeded random ────────────────────────────
	var safety := grid_columns * grid_rows * 4
	while _has_empty() and safety > 0:
		safety -= 1
		var cell := _first_empty()
		if cell.x == -1:
			break
		_place_at(cell)

# ── Preset builder ────────────────────────────────────────────────────────────

func _build_preset() -> DashboardPreset:
	if is_instance_valid(custom_preset):
		return custom_preset
	match preset_type:
		PresetType.STEERING_WHEEL:
			return _preset_steering_wheel()
	return null

# Layout en áreas de 8 × 8 celdas, cada control centrado en la suya:
#   fila 0: [btn][btn][btn][btn]
#   fila 1: [btn][volante  ][palanca]
#   fila 2: [btn][volante  ][palanca]
func _preset_steering_wheel() -> DashboardPreset:
	var p                  := DashboardPreset.new()
	p.fill_remaining_random = false

	# ── Volante, en las áreas (1..2, 1..2) ─────────────────────────────────────
	var wheel_def                := ControlDefinition.new()
	wheel_def.type                = ControlDefinition.ControlType.ROTATING
	wheel_def.grid_size           = WHEEL
	wheel_def.rotation_axis_local = Vector3.BACK
	wheel_def.rotate_sensitivity  = 0.2
	wheel_def.height_offset       = 0.16
	wheel_def.auto_return         = true

	var wheel_slot      := DashboardSlot.new()
	wheel_slot.cell      = Vector2i(10, 10)
	wheel_slot.definition = wheel_def

	# ── Palanca, en las áreas (3, 1..2) ────────────────────────────────────────
	var lever_def                := ControlDefinition.new()
	lever_def.type                = ControlDefinition.ControlType.ONE_AXIS
	lever_def.grid_size           = LEVER
	lever_def.rotation_axis_local = Vector3.RIGHT
	lever_def.sensitivity         = 0.005
	lever_def.max_angle_degrees   = 180.0
	lever_def.auto_return         = false

	var lever_slot      := DashboardSlot.new()
	lever_slot.cell      = Vector2i(25, 10)
	lever_slot.definition = lever_def

	# ── Un botón en cada área libre ───────────────────────────────────────────
	var button_cells: Array[Vector2i] = [
		Vector2i(3, 3), Vector2i(11, 3), Vector2i(19, 3), Vector2i(27, 3),
		Vector2i(3, 11), Vector2i(3, 19),
	]

	var slots: Array[DashboardSlot] = [wheel_slot, lever_slot]
	for cell in button_cells:
		var btn_def      := ControlDefinition.new()
		btn_def.type      = ControlDefinition.ControlType.TOUCH
		btn_def.grid_size = BUTTON
		btn_def.is_toggle = false

		var btn_slot      := DashboardSlot.new()
		btn_slot.cell      = cell
		btn_slot.definition = btn_def
		slots.append(btn_slot)

	p.fixed_slots = slots
	return p

# ── Grid helpers ──────────────────────────────────────────────────────────────

func _has_empty() -> bool:
	for c in grid_columns:
		for r in grid_rows:
			if not _grid[c][r]:
				return true
	return false

func _first_empty() -> Vector2i:
	for r in grid_rows:
		for c in grid_columns:
			if not _grid[c][r]:
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func _fits(cell: Vector2i, size: Vector2i) -> bool:
	if cell.x + size.x > grid_columns or cell.y + size.y > grid_rows:
		return false
	for dc in size.x:
		for dr in size.y:
			if _grid[cell.x + dc][cell.y + dr]:
				return false
	return true

func _occupy(cell: Vector2i, size: Vector2i) -> void:
	for dc in size.x:
		for dr in size.y:
			_grid[cell.x + dc][cell.y + dr] = true

# ── Placement ─────────────────────────────────────────────────────────────────

func _place_definition(cell: Vector2i, def: ControlDefinition) -> void:
	_spawn(cell, def.grid_size, _make_control_from_def(def))

func _place_at(cell: Vector2i) -> void:
	var valid: Array = []
	var total: float = 0.0
	for def in _DEFS:
		if _fits(cell, def[1]):
			valid.append(def)
			total += float(def[2])

	if valid.is_empty():
		_grid[cell.x][cell.y] = true
		return

	var pick   := _rng.randf() * total
	var chosen: Array = valid[0]
	for def in valid:
		pick -= float(def[2])
		if pick <= 0.0:
			chosen = def
			break

	var type_id: int      = chosen[0]
	var gs:      Vector2i = chosen[1]
	_occupy(cell, gs)
	_spawn(cell, gs, _make_control(type_id))

## Coloca un control que ocupa `size` celdas desde `cell`, su esquina superior izquierda. La grilla
## crece hacia +X y −Y, con la cara hacia +Z.
func _spawn(cell: Vector2i, size: Vector2i, interactable: ControllableInteractable) -> void:
	var area    := Vector2(size) * CELL
	var ctrl_sz := Vector3(area.x - 2.0 * CONTROL_MARGIN, area.y - 2.0 * CONTROL_MARGIN, CONTROL_DEPTH)
	interactable.grid_size = size
	interactable.name      = "Control"

	var body := StaticBody3D.new()
	body.name = "ctrl_%d" % _ctrl_index  # path estable en todas las máquinas (sync de controllables)
	_ctrl_index += 1
	var shape  := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = ctrl_sz
	shape.shape = bshape
	body.add_child(shape)
	body.add_child(interactable)
	add_child(body)
	body.position = Vector3(cell.x * CELL + area.x * 0.5, -(cell.y * CELL + area.y * 0.5), 0.0)

	if show_debug:
		_add_area_mesh(body, ctrl_sz)
		interactable.build_debug_visuals(ctrl_sz)
	else:
		interactable.build(ctrl_sz)

# ── Factory ───────────────────────────────────────────────────────────────────

func _make_control(type_id: int) -> ControllableInteractable:
	match type_id:
		0: return TouchComponent.new()
		1:
			var c := OneAxisComponent.new()
			c.rotation_axis_local = Vector3.RIGHT
			return c
		2: return TwoAxisComponent.new()
		3:
			var c := RotatingComponent.new()
			c.rotation_axis_local = Vector3.BACK
			return c
	return TouchComponent.new()

func _make_control_from_def(def: ControlDefinition) -> ControllableInteractable:
	var ctrl: ControllableInteractable
	match def.type:
		ControlDefinition.ControlType.TOUCH:
			var c     := TouchComponent.new()
			c.is_toggle = def.is_toggle
			ctrl        = c
		ControlDefinition.ControlType.ONE_AXIS:
			var c                := OneAxisComponent.new()
			c.sensitivity         = def.sensitivity
			c.max_angle_degrees   = def.max_angle_degrees
			c.rotation_axis_local = def.rotation_axis_local
			ctrl                  = c
		ControlDefinition.ControlType.TWO_AXIS:
			var c              := TwoAxisComponent.new()
			c.sensitivity       = def.sensitivity
			c.max_angle_degrees = def.max_angle_degrees
			ctrl                = c
		ControlDefinition.ControlType.ROTATING:
			var c                := RotatingComponent.new()
			c.sensitivity         = def.rotate_sensitivity
			c.rotation_axis_local = def.rotation_axis_local
			c.height_offset       = def.height_offset
			ctrl                  = c
		_:
			ctrl = TouchComponent.new()

	ctrl.auto_return       = def.auto_return
	ctrl.default_value     = def.default_value
	ctrl.positions         = def.positions.duplicate()
	ctrl.custom_mesh       = def.custom_mesh
	ctrl.rest_rotation_deg = def.rest_rotation_deg
	return ctrl

# ── Debug helpers ─────────────────────────────────────────────────────────────

func _add_area_mesh(body: StaticBody3D, size: Vector3) -> void:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh  = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color            = Color(0.3, 0.55, 1.0, 0.1)
	mat.transparency            = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode               = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override        = mat
	mi.set_meta("no_outline", true)
	body.add_child(mi)
