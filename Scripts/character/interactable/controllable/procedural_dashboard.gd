class_name ProceduralDashboard
extends Node3D

enum PresetType { NONE, STEERING_WHEEL }

@export var grid_columns: int        = 4
@export var grid_rows:    int        = 3
@export var cell_size:    Vector3    = Vector3(0.3, 0.3, 0.06)
@export var cell_gap:     float      = 0.02
@export var seed_value:   int        = 0
@export var show_debug:   bool       = true
@export var preset_type:  PresetType = PresetType.NONE

# [type_id, Vector2i size, weight]
const _DEFS: Array = [
	[0, Vector2i(1, 1), 3.0],
	[1, Vector2i(1, 1), 2.0],
	[1, Vector2i(2, 1), 1.5],
	[1, Vector2i(1, 2), 1.5],
	[2, Vector2i(1, 1), 2.0],
	[2, Vector2i(2, 2), 1.0],
	[3, Vector2i(1, 1), 2.0],
	[3, Vector2i(2, 2), 1.2],
]

var _grid: Array                 = []
var _rng:  RandomNumberGenerator = null

func _ready() -> void:
	generate()

func generate() -> void:
	for child in get_children():
		child.queue_free()

	_rng      = RandomNumberGenerator.new()
	_rng.seed = seed_value
	_grid     = []
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
	match preset_type:
		PresetType.STEERING_WHEEL:
			return _preset_steering_wheel()
	return null

# 4×3 grid layout:
#   row 0: [btn][btn][btn][btn]
#   row 1: [btn][wheel  ][lever]
#   row 2:      [wheel  ][lever]
func _preset_steering_wheel() -> DashboardPreset:
	var p                  := DashboardPreset.new()
	p.fill_remaining_random = false

	# ── Steering wheel — 2×2 RotatingComponent at (1,1) ──────────────────────
	var wheel_def                := ControlDefinition.new()
	wheel_def.type                = ControlDefinition.ControlType.ROTATING
	wheel_def.grid_size           = Vector2i(2, 2)
	wheel_def.rotation_axis_local = Vector3.BACK
	wheel_def.rotate_sensitivity  = 0.3
	wheel_def.height_offset       = 0.16
	wheel_def.auto_return         = true

	var wheel_slot      := DashboardSlot.new()
	wheel_slot.cell      = Vector2i(1, 1)
	wheel_slot.definition = wheel_def

	# ── Lever — 1×2 OneAxisComponent at (3,1) ────────────────────────────────
	var lever_def                := ControlDefinition.new()
	lever_def.type                = ControlDefinition.ControlType.ONE_AXIS
	lever_def.grid_size           = Vector2i(1, 2)
	lever_def.rotation_axis_local = Vector3.RIGHT
	lever_def.sensitivity         = 0.001
	lever_def.max_angle_degrees   = 180.0
	lever_def.auto_return         = true

	var lever_slot      := DashboardSlot.new()
	lever_slot.cell      = Vector2i(3, 1)
	lever_slot.definition = lever_def

	# ── Buttons — 1×1 TouchComponent for all remaining cells ─────────────────
	# Occupied after wheel+lever: (1,1),(2,1),(1,2),(2,2),(3,1),(3,2)
	# Free: (0,0),(1,0),(2,0),(3,0),(0,1),(0,2)
	var free_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(0, 1), Vector2i(0, 2),
	]

	var slots: Array[DashboardSlot] = [wheel_slot, lever_slot]
	for cell in free_cells:
		var btn_def      := ControlDefinition.new()
		btn_def.type      = ControlDefinition.ControlType.TOUCH
		btn_def.grid_size = Vector2i(1, 1)
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
	var step_x  := cell_size.x + cell_gap
	var step_y  := cell_size.y + cell_gap
	var gs      := def.grid_size
	var cx      := cell.x * step_x + (gs.x * step_x - cell_gap) * 0.5
	var cy      := -(cell.y * step_y + (gs.y * step_y - cell_gap) * 0.5)
	var ctrl_sz := Vector3(gs.x * step_x - cell_gap, gs.y * step_y - cell_gap, cell_size.z)

	var interactable       := _make_control_from_def(def)
	interactable.grid_size  = gs

	var body   := StaticBody3D.new()
	var shape  := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = ctrl_sz
	shape.shape  = bshape
	body.add_child(shape)
	body.add_child(interactable)
	add_child(body)
	body.position = Vector3(cx, cy, 0.0)

	if show_debug:
		_add_area_mesh(body, ctrl_sz)
		interactable.build_debug_visuals(ctrl_sz)
	else:
		interactable.build(ctrl_sz)

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

	var step_x    := cell_size.x + cell_gap
	var step_y    := cell_size.y + cell_gap
	var cx        := cell.x * step_x + (gs.x * step_x - cell_gap) * 0.5
	var cy        := -(cell.y * step_y + (gs.y * step_y - cell_gap) * 0.5)
	var ctrl_size := Vector3(gs.x * step_x - cell_gap, gs.y * step_y - cell_gap, cell_size.z)

	var interactable            := _make_control(type_id)
	interactable.grid_size       = gs

	var body   := StaticBody3D.new()
	var shape  := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size  = ctrl_size
	shape.shape  = bshape
	body.add_child(shape)
	body.add_child(interactable)
	add_child(body)
	body.position = Vector3(cx, cy, 0.0)

	if show_debug:
		_add_area_mesh(body, ctrl_size)
		interactable.build_debug_visuals(ctrl_size)
	else:
		interactable.build(ctrl_size)

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
