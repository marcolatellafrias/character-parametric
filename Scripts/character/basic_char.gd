extends CharacterBody3D

# UI + debug line
@export var crosshair_size := 10.0
@export var crosshair_color := Color(0, 0, 0, 0.9)
@export var grab_line_radius := 0.01
@export var grab_line_color := Color(0.2, 0.8, 1.0, 0.95)

@export var jump_velocity: float = 20.0
@export var ground_push_impulse: float = 0.4
@export var ground_push_max_dist: float = 1.2  

var _crosshair: ColorRect
var _ui_layer: CanvasLayer

var _grab_line: MeshInstance3D
var _grab_line_mesh: CylinderMesh
var _grab_line_mat: StandardMaterial3D
var _drag_start_world := Vector3.ZERO

@export var grab_ray_length: float = 12.0
@export var grab_kp: float = 180.0
@export var grab_kd: float = 22.0
@export var grab_max_force: float = 100.0
@export var grab_dist_limits := Vector2(0.6, 8.0)

var _grabbed: RigidBody3D
var _grab_local: Vector3
var _grab_distance: float = 0.0

@export var walk_speed: float = 3.5
@export var sprint_speed: float = 50.0
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false
@export var show_mesh: bool = false

# Creative mode
@export var creative_mode := false
@export var creative_fly_speed := 20.0
@export var creative_fly_speed_fast := 60.0

# Camera export
@export var camera: Camera3D
@export var camera_pivot: Node3D

var _yaw: float = 0.0
var _pitch: float = 0.0

const _PITCH_LIMIT := deg_to_rad(89.0)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_build_rig()
	_ensure_input_map()

@export var push_impulse_scale := 2.0

func _physics_process(delta: float) -> void:
	if creative_mode:
		_physics_creative(delta)
	else:
		_physics_normal(delta)
	
	move_and_slide()
	_update_grab(delta)
	_check_sphere_look()

func _physics_normal(delta: float) -> void:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	if not is_on_floor():
		velocity.y -= g * delta

	var input_vec := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back")  - Input.get_action_strength("move_forward")
	)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var wish_dir := (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y))
	wish_dir.y = 0.0
	if wish_dir.length() > 0.0:
		wish_dir = wish_dir.normalized()

	velocity.x = wish_dir.x * speed
	velocity.z = wish_dir.z * speed

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		_push_ground_down()

func _physics_creative(delta: float) -> void:
	var input_vec := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("jump") - Input.get_action_strength("crouch"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	
	var wish_dir := transform.basis * input_vec
	var speed := creative_fly_speed_fast if Input.is_action_pressed("sprint") else creative_fly_speed
	velocity = wish_dir * speed

func _push_ground_down() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_transform.origin
	var to : Vector3 = from + Vector3.DOWN * ground_push_max_dist

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var hit := space.intersect_ray(query)
	if hit:
		var collider : CollisionObject3D = hit["collider"]
		var normal: Vector3 = hit["normal"]
		if collider is RigidBody3D and normal.dot(Vector3.UP) > 0.4:
			var body := collider as RigidBody3D
			var contact_point: Vector3 = hit["position"]
			body.apply_impulse(Vector3.DOWN * ground_push_impulse, contact_point)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var dy: float = event.relative.y
		var dx: float = event.relative.x
		_yaw -= dx * mouse_sensitivity
		_pitch -= (-dy if invert_y else dy) * mouse_sensitivity
		_pitch = clamp(_pitch, -_PITCH_LIMIT, _PITCH_LIMIT)
		
		rotation.y = _yaw
		if is_instance_valid(camera_pivot):
			camera_pivot.rotation.x = _pitch

	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_ESCAPE:
		var mode := Input.get_mouse_mode()
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		)

	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_C:
		creative_mode = !creative_mode

	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return

	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_grab()
		else:
			_stop_grab()

	if event is InputEventMouseButton and is_instance_valid(_grabbed):
		if event.button_index == MouseButton.MOUSE_BUTTON_WHEEL_UP:
			_grab_distance = clamp(_grab_distance - 0.3, grab_dist_limits.x, grab_dist_limits.y)
		elif event.button_index == MouseButton.MOUSE_BUTTON_WHEEL_DOWN:
			_grab_distance = clamp(_grab_distance + 0.3, grab_dist_limits.x, grab_dist_limits.y)

func _build_rig() -> void:
	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.4
	collider.shape = shape
	add_child(collider)

	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = shape.radius
	cap_mesh.height = shape.height*2
	mesh.mesh = cap_mesh
	mesh.visible = show_mesh
	mesh.position = Vector3(0.0, shape.height * 0.5, 0.0)
	add_child(mesh)

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "HUD"
	add_child(_ui_layer)

	_crosshair = ColorRect.new()
	_crosshair.color = crosshair_color
	_crosshair.size = Vector2(crosshair_size, crosshair_size)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.position = -_crosshair.size * 0.5
	_ui_layer.add_child(_crosshair)

	_grab_line_mesh = CylinderMesh.new()
	_grab_line_mesh.top_radius = grab_line_radius
	_grab_line_mesh.bottom_radius = grab_line_radius
	_grab_line_mesh.height = 1.0

	_grab_line = MeshInstance3D.new()
	_grab_line.mesh = _grab_line_mesh

	_grab_line_mat = StandardMaterial3D.new()
	_grab_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grab_line_mat.albedo_color = grab_line_color
	_grab_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grab_line.material_override = _grab_line_mat

	_grab_line.visible = false
	add_child(_grab_line)

func _ensure_input_map() -> void:
	var map := {
		"move_forward": [Key.KEY_W, Key.KEY_UP],
		"move_back":    [Key.KEY_S, Key.KEY_DOWN],
		"move_left":    [Key.KEY_A, Key.KEY_LEFT],
		"move_right":   [Key.KEY_D, Key.KEY_RIGHT],
		"jump":         [Key.KEY_SPACE],
		"sprint":       [Key.KEY_SHIFT],
		"crouch":       [Key.KEY_CTRL]
	}
	for action in map.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
	
	if not InputMap.has_action("grab"):
		InputMap.add_action("grab")
	var mbe := InputEventMouseButton.new()
	mbe.button_index = MouseButton.MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("grab", mbe):
		InputMap.action_add_event("grab", mbe)
		
func _try_start_grab() -> void:
	if not is_instance_valid(camera):
		return
	var vp_size := get_viewport().get_visible_rect().size
	var screen_center := vp_size * 0.5
	var from := camera.project_ray_origin(screen_center)
	var dir := camera.project_ray_normal(screen_center)
	var to := from + dir * grab_ray_length

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var rb := hit.collider as RigidBody3D
	if rb == null:
		return

	_grabbed = rb
	_grab_local = rb.to_local(hit.position)
	_grab_distance = clamp(from.distance_to(hit.position), grab_dist_limits.x, grab_dist_limits.y)
	_grabbed.sleeping = false
	_drag_start_world = hit.position
	_grab_line.visible = true

func _stop_grab() -> void:
	_grabbed = null
	if is_instance_valid(_grab_line):
		_grab_line.visible = false

func _update_grab(_delta: float) -> void:
	if not is_instance_valid(_grabbed):
		_grabbed = null
		return
	var mass := _grabbed.mass
	var vp_size := get_viewport().get_visible_rect().size
	var screen_center := vp_size * 0.5
	var from := camera.project_ray_origin(screen_center)
	var dir := camera.project_ray_normal(screen_center).normalized()
	var desired := from + dir * _grab_distance

	var world_pt := _grabbed.to_global(_grab_local)
	var com := _grabbed.global_transform.origin
	var r := world_pt - com

	var v_point := _grabbed.linear_velocity + _grabbed.angular_velocity.cross(r)

	var scaled_kp := grab_kp * mass
	var scaled_kd := grab_kd * mass
	
	var error := desired - world_pt
	var force := error * scaled_kp + (-v_point) * scaled_kd

	var f_len := force.length()
	if f_len > grab_max_force:
		force = force * (grab_max_force / max(f_len, 0.0001))

	_grabbed.apply_central_force(force)
	_grabbed.apply_torque(r.cross(force))
	_grabged_sleep_guard()
	
	if not is_instance_valid(_grab_line):
		return

	var start := _drag_start_world
	var end := desired
	var dir3 := end - start
	var dist := dir3.length()

	if dist < 0.002:
		_grab_line.visible = false
	else:
		_grab_line.visible = true
		_grab_line_mesh.height = dist

		var mid := start + dir3 * 0.5
		_grab_line.global_transform.origin = mid

		var y := dir3.normalized()
		var x := y.cross(Vector3.FORWARD)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(y)

		_grab_line.global_transform.basis = Basis(x, y, z)

func _grabged_sleep_guard() -> void:
	if _grabbed.sleeping:
		_grabbed.sleeping = false

func _check_sphere_look() -> void:
	if not is_instance_valid(camera):
		return
	
	var vp_size := get_viewport().get_visible_rect().size
	var screen_center := vp_size * 0.5
	var from := camera.project_ray_origin(screen_center)
	var dir := camera.project_ray_normal(screen_center)
	var to := from + dir * 10.0
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	
	if hit:
		var collider = hit.collider
		if collider and collider.get_parent() and collider.get_parent().has_meta("grid_coords"):
			var grid_coords: Vector2i = collider.get_parent().get_meta("grid_coords")
			var world_pos: Vector3 = collider.get_parent().get_meta("world_position")
