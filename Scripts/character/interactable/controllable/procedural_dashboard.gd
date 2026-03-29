class_name ProceduralDashboard
extends Node3D

@export var grid_columns: int     = 4
@export var grid_rows:    int     = 3
@export var cell_size:    Vector3 = Vector3(0.3, 0.3, 0.06)
@export var cell_gap:     float   = 0.02
@export var seed_value:   int     = 0
@export var show_debug:   bool    = true

# [type_id, Vector2i size, weight]
# type_id: 0=Touch  1=OneAxis  2=TwoAxis  3=Rotating
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

var _grid: Array                  = []
var _rng:  RandomNumberGenerator  = null

func _ready() -> void:
	generate()

func generate() -> void:
	for child in get_children():
		child.queue_free()

	_rng       = RandomNumberGenerator.new()
	_rng.seed  = seed_value
	_grid      = []
	for _c in grid_columns:
		var col: Array[bool] = []
		for _r in grid_rows:
			col.append(false)
		_grid.append(col)

	var safety := grid_columns * grid_rows * 4
	while _has_empty() and safety > 0:
		safety -= 1
		var cell := _first_empty()
		if cell.x == -1:
			break
		_place_at(cell)

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
	var ctrl_size := Vector3(
		gs.x * step_x - cell_gap,
		gs.y * step_y - cell_gap,
		cell_size.z
	)

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
