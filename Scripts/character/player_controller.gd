class_name PlayerController
extends Node

var head_bone: CustomBone
var head_size: Vector3
var char_rigidbody: CharacterRigidBody3D
var player_camera: Camera3D
var is_ready: bool = false
var camera_pitch: float = 0.0
var camera_yaw: float = 0.0

var camera_y_smooth: float = 0.0
const CAMERA_Y_SMOOTH: float = 8.0

var grab_ray_length: float = 10.0
var grab_stiffness: float = 150.0
var grab_damping: float = 15.0
var grab_dist_min: float = 1.5
var grab_dist_max: float = 8.0
var grab_rotation_sensitivity: float = 0.005
var grab_rotation_stiffness: float = 50.0
var grab_rotation_damping: float = 8.0
var grab_sag_factor: float = 0.3
var outline_color: Color = Color(1, 1, 0, 1)
var outline_size: float = 0.01
var show_grab_curve: bool = true
var grab_curve_color: Color = Color(1, 1, 1, 1)
var _curve_mesh: MeshInstance3D = null

var _hovered_parent: Node = null
var _hovered_rb: RigidBody3D = null
var _hovered_meshes: Array[MeshInstance3D] = []
var _outline_material: ShaderMaterial = null

var _grabbed: RigidBody3D = null
var _grab_distance: float = 3.0
var _is_rotating: bool = false
var _grab_target_rotation: Quaternion = Quaternion.IDENTITY

var _hud: PlayerHUD = null

var stamina_max: float = 5.0
var stamina_drain_rate: float = 2.0
var stamina_regen_rate: float = 0.75
var stamina_refractory_time: float = 2.0

var _stamina: float = 5.0
var _refractory_timer: float = 0.0
var _was_sprinting: bool = false

func setup(rb: CharacterRigidBody3D, cam: Camera3D, head: CustomBone, h_size: Vector3, inst: EntityInstantiation) -> void:
    char_rigidbody = rb
    player_camera = cam
    head_bone = head
    head_size = h_size
    is_ready = true
    camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _build_outline_material()
    _hud = PlayerHUD.create(inst)
    char_rigidbody.add_child(_hud)

func _get_grab_origin() -> Vector3:
    return player_camera.global_position

func _is_ragdoll_active() -> bool:
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    return is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_active

func _input(event: InputEvent) -> void:
    if not is_ready:
        return

    if event is InputEventMouseMotion:
        if _is_rotating and is_instance_valid(_grabbed):
            var delta_rot := Quaternion(player_camera.global_transform.basis.x, -event.relative.y * grab_rotation_sensitivity) \
                          * Quaternion(player_camera.global_transform.basis.y, -event.relative.x * grab_rotation_sensitivity)
            _grab_target_rotation = delta_rot * _grab_target_rotation
        else:
            camera_pitch = clamp(camera_pitch - event.relative.y * 0.002, -1.2, 1.2)
            camera_yaw -= event.relative.x * 0.002
            player_camera.rotation.x = camera_pitch
            # During ragdoll, yaw is applied directly to the camera (not through char_rigidbody)
            player_camera.rotation.y = camera_yaw if _is_ragdoll_active() else 0.0

    if event is InputEventMouseButton:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                if event.pressed and is_instance_valid(_hovered_rb):
                    _start_grab()
                elif not event.pressed:
                    _stop_grab()
            MOUSE_BUTTON_RIGHT:
                _is_rotating = event.pressed and is_instance_valid(_grabbed)
            MOUSE_BUTTON_WHEEL_UP:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance - 0.3, grab_dist_min, grab_dist_max)
            MOUSE_BUTTON_WHEEL_DOWN:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance + 0.3, grab_dist_min, grab_dist_max)

    if event is InputEventKey and event.pressed and event.keycode == KEY_F:
        if is_instance_valid(_hovered_rb):
            var target_bi := _find_bone_instantiator(_hovered_rb)
            if target_bi and target_bi != char_rigidbody.get_parent():
                _switch_to(target_bi)

    if event is InputEventKey and event.pressed and event.keycode == KEY_G:
        _toggle_ragdoll()

    if event is InputEventKey and event.pressed and event.keycode == KEY_R:
        _respawn()

func _physics_process(_delta: float) -> void:
    if not is_ready:
        return

    if is_instance_valid(_hud):
        var hvel := Vector3(char_rigidbody.linear_velocity.x, 0.0, char_rigidbody.linear_velocity.z)
        _hud.update_speed(hvel.length())

    if _is_ragdoll_active():
        var bi := char_rigidbody.get_parent() as BoneInstantiator
        # Camera position is updated in ragdoll_util.update(), rotation handled here
        player_camera.rotation.x = camera_pitch
        player_camera.rotation.y = camera_yaw
        return

    var target_y: float = head_bone.global_position.y + head_size.y * 0.5
    var k: float = clamp(_delta * CAMERA_Y_SMOOTH, 0.0, 1.0)
    camera_y_smooth = lerp(camera_y_smooth, target_y, k)
    player_camera.global_position.y = camera_y_smooth

    char_rigidbody.rotation.y = camera_yaw

    _process_stamina(_delta)
    if not is_instance_valid(_grabbed):
        _process_grab_look()

    _apply_grab_force()
    _apply_grab_torque()
    if is_instance_valid(_grabbed):
        _update_curve()


func _toggle_ragdoll() -> void:
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if not is_instance_valid(bi) or not is_instance_valid(bi.ragdoll_util):
        return
    if bi.ragdoll_util.is_active:
        bi.ragdoll_util.deactivate(char_rigidbody, bi.custom_bones_util.lower_spine)
        # Restore camera local position/rotation after reparent (deactivate put it back in char_rb)
        player_camera.position = Vector3.ZERO
        player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)
        char_rigidbody.rotation.y = camera_yaw
        camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    else:
        _stop_grab()
        bi.ragdoll_util.activate(char_rigidbody, bi.custom_bones_util.lower_spine, player_camera)


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
    var target_pos := _get_grab_origin() + (-player_camera.global_transform.basis.z) * _grab_distance
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

func _find_bone_instantiator(node: Node) -> BoneInstantiator:
    var current := node.get_parent()
    while current:
        if current is BoneInstantiator:
            return current
        current = current.get_parent()
    return null

func _switch_to(target: BoneInstantiator) -> void:
    var current_bi := char_rigidbody.get_parent() as BoneInstantiator

    player_camera.get_parent().remove_child(player_camera)

    # Si el ragdoll anterior sigue activo, desvinculamos la camara de el
    if is_instance_valid(current_bi) and is_instance_valid(current_bi.ragdoll_util):
        current_bi.ragdoll_util._camera = null

    if not (is_instance_valid(current_bi.ragdoll_util) and current_bi.ragdoll_util.is_active):
        current_bi.char_rigidbody.is_active = false
    current_bi.is_active = false

    target.is_active = true
    char_rigidbody = target.char_rigidbody
    head_bone = target.custom_bones_util.head
    head_size = target.skel_sizes_util.head_size
    char_rigidbody.add_child(player_camera)
    player_camera.current = true
    player_camera.position = Vector3.ZERO
    player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)
    char_rigidbody.is_active = true
    camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    char_rigidbody.rotation.y = camera_yaw

    if is_instance_valid(_hud):
        _hud.queue_free()
    _hud = PlayerHUD.create(target.entity_instantiation)
    char_rigidbody.add_child(_hud)

    _stop_grab()
    _clear_outline()

func _build_outline_material() -> void:
    var shader := load("res://shaders/outline.gdshader") as Shader
    _outline_material = ShaderMaterial.new()
    _outline_material.shader = shader
    _outline_material.set_shader_parameter("color", outline_color)
    _outline_material.set_shader_parameter("outline_thickness", outline_size)

func _process_grab_look() -> void:
    if not is_instance_valid(player_camera): return

    var vp_size := player_camera.get_viewport().get_visible_rect().size
    var from    := _get_grab_origin()
    var dir     := player_camera.project_ray_normal(vp_size * 0.5)
    var query   := PhysicsRayQueryParameters3D.create(from, from + dir * grab_ray_length)
    query.exclude = [char_rigidbody.get_rid()]
    var hit := player_camera.get_world_3d().direct_space_state.intersect_ray(query)

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
            for i in mesh.mesh.get_surface_count():
                var mat := mesh.get_active_material(i)
                if mat:
                    mat.next_pass = _outline_material

func _clear_outline() -> void:
    for mesh in _hovered_meshes:
        if is_instance_valid(mesh):
            for i in mesh.mesh.get_surface_count():
                var mat := mesh.get_active_material(i)
                if mat:
                    mat.next_pass = null
    _hovered_meshes.clear()
    _hovered_parent = null
    _hovered_rb = null

func _update_curve() -> void:
    if is_instance_valid(_curve_mesh):
        _curve_mesh.queue_free()
        _curve_mesh = null

    if not show_grab_curve:
        return

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

    _curve_mesh = DebugUtil.create_debug_path3d(points, 16, grab_curve_color, 0.01)
    get_tree().current_scene.add_child(_curve_mesh)

func _respawn() -> void:
    var current_bi := char_rigidbody.get_parent() as BoneInstantiator
    if not current_bi:
        return

    if is_instance_valid(current_bi.ragdoll_util) and current_bi.ragdoll_util.is_active:
        current_bi.ragdoll_util.deactivate(char_rigidbody, current_bi.custom_bones_util.lower_spine)

    var prev_position := Vector3(char_rigidbody.global_position.x, 3.0, char_rigidbody.global_position.z)
    var prev_yaw := camera_yaw

    var new_seed := randi() % 100000
    current_bi.master_seed = new_seed
    current_bi.initialize_skeleton()

    char_rigidbody = current_bi.char_rigidbody
    head_bone = current_bi.custom_bones_util.head
    head_size = current_bi.skel_sizes_util.head_size
    char_rigidbody.global_position = prev_position
    char_rigidbody.rotation.y = prev_yaw
    camera_yaw = prev_yaw
    camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5

    player_camera.get_parent().remove_child(player_camera)
    char_rigidbody.add_child(player_camera)
    player_camera.current = true
    player_camera.position = Vector3.ZERO
    player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)

    if is_instance_valid(_hud):
        _hud.queue_free()
    _hud = PlayerHUD.create(current_bi.entity_instantiation)
    char_rigidbody.add_child(_hud)

    _stop_grab()
    _clear_outline()

func _process_stamina(delta: float) -> void:
    var input_y := Input.get_axis("move_forward", "move_backward")
    var is_sprinting := Input.is_action_pressed("sprint") and input_y < 0.0 and char_rigidbody.can_sprint

    if is_sprinting:
        _stamina = max(0.0, _stamina - stamina_drain_rate * delta)
        if _stamina == 0.0:
            char_rigidbody.can_sprint = false
        _refractory_timer = stamina_refractory_time
        _was_sprinting = true
    else:
        if _was_sprinting:
            _was_sprinting = false

        if _refractory_timer > 0.0:
            _refractory_timer = max(0.0, _refractory_timer - delta)
        else:
            if not char_rigidbody.can_sprint:
                char_rigidbody.can_sprint = true
            _stamina = min(stamina_max, _stamina + stamina_regen_rate * delta)

    if is_instance_valid(_hud):
        _hud.update_stamina(_stamina / stamina_max)
