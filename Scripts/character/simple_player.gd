extends CharacterBody3D

@export var walk_speed: float = 3.5
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 8.0
@export var mouse_sensitivity: float = 0.002
@export var invert_y: bool = false

@export var creative_mode := false
@export var creative_fly_speed := 20.0
@export var creative_fly_speed_fast := 60.0

@export var grab_ray_length: float = 10.0
@export var grab_stiffness: float = 150.0
@export var grab_damping: float = 15.0
@export var grab_dist_min: float = 1.5
@export var grab_dist_max: float = 8.0
@export var grab_rotation_sensitivity: float = 0.005
@export var grab_rotation_stiffness: float = 50.0
@export var grab_rotation_damping: float = 8.0
@export var grab_sag_factor: float = 0.3
@export var grab_height_offset: float = -0.3

@export var outline_color: Color = Color(1, 0, 1, 1)
@export var outline_size: float = 2.05
@export var crosshair_size := 6.0
@export var crosshair_color := Color(1, 1, 1, 0.9)

var camera: Camera3D
var camera_pivot: Node3D

var _yaw: float = 0.0
var _pitch: float = 0.0
const _PITCH_LIMIT := deg_to_rad(89.0)

var _hovered_parent: Node = null
var _hovered_rb: RigidBody3D = null
var _hovered_meshes: Array[MeshInstance3D] = []
var _outline_material: ShaderMaterial = null

var _grabbed: RigidBody3D = null
var _grab_distance: float = 3.0
var _is_rotating: bool = false
var _grab_target_rotation: Quaternion = Quaternion.IDENTITY
var _curve_mesh: MeshInstance3D = null

func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    _build_collider()
    _build_camera()
    _ensure_input_map()
    _build_outline_material()
    _yaw = rotation.y
    _pitch = camera_pivot.rotation.x

    var layer := CanvasLayer.new()
    add_child(layer)
    var ch := ColorRect.new()
    ch.color = crosshair_color
    ch.size = Vector2(crosshair_size, crosshair_size)
    ch.anchor_left = 0.5; ch.anchor_top = 0.5
    ch.position = -ch.size * 0.5
    ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(ch)

func _get_grab_origin() -> Vector3:
    return camera.global_position + camera.global_transform.basis.y * grab_height_offset

func _process(_delta: float) -> void:
    rotation.y = _yaw
    camera_pivot.rotation.x = _pitch
    if not is_instance_valid(_grabbed):
        _process_grab_look()

func _physics_process(delta: float) -> void:
    if creative_mode:
        _physics_creative()
    else:
        _physics_normal(delta)
    move_and_slide()
    _apply_grab_force()
    _apply_grab_torque()
    if is_instance_valid(_grabbed):
        _update_curve()

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

func _physics_creative() -> void:
    var input_vec := Vector3(
        Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
        Input.get_action_strength("jump")        - Input.get_action_strength("crouch"),
        Input.get_action_strength("move_back")   - Input.get_action_strength("move_forward")
    )
    if input_vec.length() > 1.0:
        input_vec = input_vec.normalized()

    var speed := creative_fly_speed_fast if Input.is_action_pressed("sprint") else creative_fly_speed
    velocity = (transform.basis * input_vec) * speed

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("toggle_creative"):
        creative_mode = !creative_mode
        velocity = Vector3.ZERO
        return

    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        if _is_rotating and is_instance_valid(_grabbed):
            var delta_rot := Quaternion(camera.global_transform.basis.x, -event.relative.y * grab_rotation_sensitivity) \
                          * Quaternion(camera.global_transform.basis.y, -event.relative.x * grab_rotation_sensitivity)
            _grab_target_rotation = delta_rot * _grab_target_rotation
        else:
            _yaw   -= event.relative.x * mouse_sensitivity
            _pitch -= (-event.relative.y if invert_y else event.relative.y) * mouse_sensitivity
            _pitch  = clamp(_pitch, -_PITCH_LIMIT, _PITCH_LIMIT)

    if event is InputEventMouseButton:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                if event.pressed:
                    if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
                        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
                    elif is_instance_valid(_hovered_rb):
                        _start_grab()
                else:
                    _stop_grab()
            MOUSE_BUTTON_RIGHT:
                _is_rotating = event.pressed and is_instance_valid(_grabbed)
            MOUSE_BUTTON_WHEEL_UP:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance - 0.3, grab_dist_min, grab_dist_max)
            MOUSE_BUTTON_WHEEL_DOWN:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance + 0.3, grab_dist_min, grab_dist_max)

# --- GRAB ---

func _start_grab() -> void:
    _grabbed = _hovered_rb
    _grab_distance = clamp(
        _get_grab_origin().distance_to(_grabbed.global_position),
        grab_dist_min, grab_dist_max
    )
    _grabbed.sleeping = false
    _grab_target_rotation = _grabbed.global_transform.basis.get_rotation_quaternion()

func _stop_grab() -> void:
    _grabbed = null
    _is_rotating = false
    if is_instance_valid(_curve_mesh):
        _curve_mesh.queue_free()
        _curve_mesh = null

func _apply_grab_force() -> void:
    if not is_instance_valid(_grabbed):
        if _grabbed != null: _stop_grab()
        return
    var target_pos := _get_grab_origin() + (-camera.global_transform.basis.z) * _grab_distance
    var force := (target_pos - _grabbed.global_position) * grab_stiffness \
               - _grabbed.linear_velocity * grab_damping
    _grabbed.apply_central_force(force)
    _grabbed.sleeping = false

func _apply_grab_torque() -> void:
    if not is_instance_valid(_grabbed):
        return
    var damping_torque: Vector3 = -_grabbed.angular_velocity * grab_rotation_damping
    if _is_rotating:
        var current := _grabbed.global_transform.basis.get_rotation_quaternion()
        var error := (_grab_target_rotation * current.inverse()).normalized()
        var axis := error.get_axis()
        var angle := error.get_angle()
        if angle > PI:
            angle -= TAU
        _grabbed.apply_torque(axis * angle * grab_rotation_stiffness + damping_torque)
    else:
        _grabbed.apply_torque(damping_torque)

func _update_curve() -> void:
    if is_instance_valid(_curve_mesh):
        _curve_mesh.queue_free()
        _curve_mesh = null

    var p0 := _get_grab_origin()
    var p2 := _grabbed.global_position
    var dist := p0.distance_to(p2)
    var p1 := (p0 + p2) * 0.5 + Vector3.UP * dist * grab_sag_factor

    var cp0 := p0 + (p1 - p0) * (2.0 / 3.0)
    var cp1 := p2 + (p1 - p2) * (2.0 / 3.0)

    var points := [
        { "pos": p0, "in": Vector3.ZERO, "out": cp0 - p0 },
        { "pos": p2, "in": cp1 - p2,     "out": Vector3.ZERO }
    ]

    _curve_mesh = DebugUtil.create_debug_path3d(points, 16, Color(0.4, 0.9, 1.0), 0.005)
    get_tree().current_scene.add_child(_curve_mesh)

# --- OUTLINE ---

func _build_outline_material() -> void:
    var shader := load("res://shaders/outline.gdshader") as Shader
    _outline_material = ShaderMaterial.new()
    _outline_material.shader = shader
    _outline_material.set_shader_parameter("color", outline_color)
    _outline_material.set_shader_parameter("size", outline_size)

func _process_grab_look() -> void:
    if not is_instance_valid(camera): return

    var vp_size := get_viewport().get_visible_rect().size
    var from    := _get_grab_origin()
    var dir     := camera.project_ray_normal(vp_size * 0.5)
    var query   := PhysicsRayQueryParameters3D.create(from, from + dir * grab_ray_length)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)

    if not hit.is_empty() and hit.collider is RigidBody3D:
        var parent: Node = hit.collider.get_parent()
        if parent != _hovered_parent:
            _clear_outline()
            _hovered_parent = parent
            _hovered_rb = hit.collider as RigidBody3D
            _hovered_meshes = _collect_meshes(parent)
            _apply_outline()
    else:
        _clear_outline()

func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    _collect_meshes_recursive(node, result)
    return result

func _collect_meshes_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        _collect_meshes_recursive(child, result)

func _apply_outline() -> void:
    for mesh in _hovered_meshes:
        if is_instance_valid(mesh):
            mesh.material_overlay = _outline_material

func _clear_outline() -> void:
    for mesh in _hovered_meshes:
        if is_instance_valid(mesh):
            mesh.material_overlay = null
    _hovered_meshes.clear()
    _hovered_parent = null
    _hovered_rb = null

# --- SETUP ---

func _build_collider() -> void:
    var collider := CollisionShape3D.new()
    collider.name = "Collider"
    var shape := CapsuleShape3D.new()
    shape.radius = 0.4
    shape.height = 1.4
    collider.shape = shape
    add_child(collider)

func _build_camera() -> void:
    camera_pivot = Node3D.new()
    camera_pivot.name = "CameraPivot"
    camera_pivot.position = Vector3(0, 1.1, 0)
    add_child(camera_pivot)

    camera = Camera3D.new()
    camera.name = "Camera"
    camera.current = true
    camera_pivot.add_child(camera)

func _ensure_input_map() -> void:
    var map := {
        "move_forward": [Key.KEY_W],
        "move_back":    [Key.KEY_S],
        "move_left":    [Key.KEY_A],
        "move_right":   [Key.KEY_D],
        "jump":         [Key.KEY_SPACE],
        "sprint":       [Key.KEY_SHIFT],
        "crouch":       [Key.KEY_CTRL],
    }
    for action in map.keys():
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        for k in map[action]:
            var ev := InputEventKey.new()
            ev.physical_keycode = k
            if not InputMap.action_has_event(action, ev):
                InputMap.action_add_event(action, ev)

    if not InputMap.has_action("toggle_creative"):
        InputMap.add_action("toggle_creative")
    var cev := InputEventKey.new()
    cev.physical_keycode = Key.KEY_C
    if not InputMap.action_has_event("toggle_creative", cev):
        InputMap.action_add_event("toggle_creative", cev)
