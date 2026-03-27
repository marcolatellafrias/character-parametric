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
var grab_curve_color: Color = Color(1, 1, 1)

var stamina_max: float = 5.0
var stamina_drain_rate: float = 0.01
var stamina_regen_rate: float = 0.75
var stamina_refractory_time: float = 2.0

var _stamina: float = 5.0
var _refractory_timer: float = 0.0
var _was_sprinting: bool = false

var _hovered_parent: Node = null
var _hovered_rb: RigidBody3D = null
var _hovered_meshes: Array[MeshInstance3D] = []
var _outline_material: ShaderMaterial = null

var _grabbed: RigidBody3D = null
var _grab_distance: float = 3.0
var _is_rotating: bool = false
var _grab_target_rotation: Quaternion = Quaternion.IDENTITY
var _curve_mesh: MeshInstance3D = null

var _hud: PlayerHUD = null
var _impact_debug_hud: ImpactDebugHUD = null
var _prev_fall_rb: CharacterRigidBody3D = null

var _was_ragdoll_active: bool = false

var _is_charging_jump: bool = false
var _jump_charge: float = 0.0
var _is_crouched: bool = false

var _max_reach_distance: float = 1.0

# Debug cameras
var _debug_camera: Camera3D = null
var _debug_cam_mode: int = 0
const DEBUG_CAM_DISTANCE: float = 5.0
const DEBUG_CAM_HEIGHT: float = 1.5

var throw_strength: float = 500.0
var throw_max_charge_time: float = 0.5

var _is_charging_throw: bool = false
var _throw_charge: float = 0.0

var _grabbed_grab_point: Node3D = null
var _grab_relative_rotation: Quaternion = Quaternion.IDENTITY

func setup(rb: CharacterRigidBody3D, cam: Camera3D, head: CustomBone, h_size: Vector3, inst: EntityInstantiation) -> void:
    char_rigidbody = rb
    player_camera = cam
    head_bone = head
    head_size = h_size
    is_ready = true
    camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    _max_reach_distance = inst.arch_final.reach * inst.arch_final.reach_multiplier
    grab_ray_length = _max_reach_distance + 2.0
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _build_outline_material()
    _hud = PlayerHUD.create(inst)
    char_rigidbody.add_child(_hud)
    _impact_debug_hud = ImpactDebugHUD.create()
    #add_child(_impact_debug_hud)
    _connect_fall_signal(char_rigidbody)
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if is_instance_valid(bi):
        bi.set_first_person_visibility(_debug_cam_mode == 0)

    _debug_camera = Camera3D.new()
    _debug_camera.current = false
    add_child(_debug_camera)


func _get_bi() -> BoneInstantiator:
    return char_rigidbody.get_parent() as BoneInstantiator


func _get_arch() -> EntityArchetype:
    var bi := _get_bi()
    return bi.entity_instantiation.arch_final if is_instance_valid(bi) else null


func _connect_fall_signal(rb: CharacterRigidBody3D) -> void:
    if is_instance_valid(_prev_fall_rb) and is_instance_valid(_impact_debug_hud):
        if _prev_fall_rb.fall_triggered.is_connected(_impact_debug_hud.notify_fall_triggered):
            _prev_fall_rb.fall_triggered.disconnect(_impact_debug_hud.notify_fall_triggered)
    _prev_fall_rb = rb
    if is_instance_valid(_impact_debug_hud):
        rb.fall_triggered.connect(func(_d): _impact_debug_hud.notify_fall_triggered())


func _get_ragdoll() -> RagdollUtil:
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    return bi.ragdoll_util if is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) else null


func _is_ragdoll_active() -> bool:
    var rd := _get_ragdoll()
    return rd != null and (rd.is_active or rd.is_recovering)


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
            if not _is_ragdoll_active():
                player_camera.rotation.x = camera_pitch

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

    if event is InputEventKey and not event.echo:
        if event.pressed:
            match event.keycode:
                KEY_SPACE:
                    if not _is_crouched and char_rigidbody.is_grounded:
                        _is_charging_jump = true
                KEY_R:
                    if not _is_charging_throw:
                        _is_charging_throw = true
                        _throw_charge = 0.0
                KEY_CTRL:
                    if not _is_crouched:
                        _start_crouch()
                KEY_F:
                    if is_instance_valid(_hovered_rb):
                        var target_bi := _find_bone_instantiator(_hovered_rb)
                        if target_bi and target_bi != char_rigidbody.get_parent():
                            _switch_to(target_bi)
                KEY_G:
                    _toggle_ragdoll()
                KEY_P:
                    _respawn()
                KEY_KP_5:
                    _set_debug_cam(0)
                KEY_KP_1:
                    _set_debug_cam(1)
                KEY_KP_2:
                    _set_debug_cam(2)
                KEY_KP_3:
                    _set_debug_cam(3)
                KEY_KP_4:
                    _set_debug_cam(4)
                KEY_KP_6:
                    _set_debug_cam(6)
                KEY_KP_7:
                    _set_debug_cam(7)
                KEY_KP_8:
                    _set_debug_cam(8)
                KEY_KP_9:
                    _set_debug_cam(9)
        else:
            match event.keycode:
                KEY_SPACE:
                    if _is_charging_jump:
                        _release_jump()
                        _is_charging_jump = false
                KEY_CTRL:
                    if _is_crouched:
                        _stop_crouch()
                KEY_R:
                    if _is_charging_throw:
                        _release_throw()
                        _is_charging_throw = false
                        _throw_charge = 0.0


func _set_debug_cam(mode: int) -> void:
    _debug_cam_mode = mode
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if mode == 0:
        player_camera.current = true
        _debug_camera.current = false
        if is_instance_valid(bi):
            bi.set_first_person_visibility(true)
    else:
        _debug_camera.current = true
        player_camera.current = false
        if is_instance_valid(bi):
            bi.set_first_person_visibility(false)


func _update_debug_camera() -> void:
    if _debug_cam_mode == 0 or not is_instance_valid(_debug_camera):
        return

    var yaw_basis := Basis(Vector3.UP, camera_yaw)
    var forward   := -yaw_basis.z
    var right     := yaw_basis.x

    var look_target := char_rigidbody.global_position + Vector3(0.0, DEBUG_CAM_HEIGHT, 0.0)

    var flat_offset := Vector3.ZERO
    match _debug_cam_mode:
        1:
            flat_offset = (-forward - right).normalized() * DEBUG_CAM_DISTANCE
        2:
            flat_offset = -forward * DEBUG_CAM_DISTANCE
        3:
            flat_offset = (-forward + right).normalized() * DEBUG_CAM_DISTANCE
        4:
            flat_offset = -right * DEBUG_CAM_DISTANCE
        6:
            flat_offset = right * DEBUG_CAM_DISTANCE
        7:
            flat_offset = (forward - right).normalized() * DEBUG_CAM_DISTANCE
        8:
            flat_offset = forward * DEBUG_CAM_DISTANCE
        9:
            flat_offset = (forward + right).normalized() * DEBUG_CAM_DISTANCE

    _debug_camera.global_position = look_target + Vector3(flat_offset.x, 0.0, flat_offset.z)
    _debug_camera.look_at(look_target, Vector3.UP)


func _physics_process(delta: float) -> void:
    if not is_ready:
        return

    var ragdoll_active := _is_ragdoll_active()

    if ragdoll_active and not _was_ragdoll_active:
        _stop_grab()
        _clear_outline()
    _was_ragdoll_active = ragdoll_active

    if is_instance_valid(_hud):
        var hvel := Vector3(char_rigidbody.linear_velocity.x, 0.0, char_rigidbody.linear_velocity.z)
        _hud.update_speed(hvel.length())
        _hud.update_stability(char_rigidbody.velocity_indicator, char_rigidbody.impact_xz, char_rigidbody.impact_y)

    if is_instance_valid(_impact_debug_hud):
        var bi := char_rigidbody.get_parent() as BoneInstantiator
        _impact_debug_hud.update_impact_debug(
            char_rigidbody.impact_xz,
            char_rigidbody.global_transform.basis,
            char_rigidbody.impact_y,
            char_rigidbody.linear_velocity,
            char_rigidbody._last_impact_world_dir,
            char_rigidbody.ragdoll_threshold,
            is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_active,
            is_instance_valid(bi) and is_instance_valid(bi.ragdoll_util) and bi.ragdoll_util.is_recovering,
            char_rigidbody._last_impact_xz_magnitude,
            max(char_rigidbody.max_speed_forward, char_rigidbody.max_speed_side) * char_rigidbody.sprint_multiplier,
            char_rigidbody.ragdoll_threshold,
            char_rigidbody._snapshot_capture_count,
            char_rigidbody._snapshot_flag_at_capture,
            char_rigidbody._snapshot_ragdoll_at_capture,
            char_rigidbody._snapshot_acc_before,
            char_rigidbody._snapshot_acc_after
        )

    _update_debug_camera()

    if ragdoll_active:
        _update_ragdoll_camera(delta)
        return

    char_rigidbody.rotation.y = camera_yaw

    if _debug_cam_mode == 0:
        var target_y := head_bone.global_position.y + head_size.y * 0.5
        camera_y_smooth = lerp(camera_y_smooth, target_y, clamp(delta * CAMERA_Y_SMOOTH, 0.0, 1.0))
        player_camera.global_position.y = camera_y_smooth
        player_camera.rotation.x = camera_pitch

    _process_stamina(delta)

    if _is_charging_jump:
        if char_rigidbody.is_grounded and not _is_crouched:
            var arch := _get_arch()
            _jump_charge = min(_jump_charge + delta, arch.time_to_max_jump)
            _get_bi().jump_squat_t = _jump_charge / arch.time_to_max_jump
        else:
            _cancel_jump_charge()

    if _is_charging_throw:
        _throw_charge = min(_throw_charge + delta, throw_max_charge_time)

    # Actualizar animación de brazos para throw
    var bi := _get_bi()
    if is_instance_valid(bi):
        bi.throw_t = (_throw_charge / throw_max_charge_time) if _is_charging_throw else 0.0
        if _is_charging_throw:
            bi.throw_world_dir = -player_camera.global_transform.basis.z

    if is_instance_valid(_hud):
        var arch := _get_arch()
        var jump_max := arch.time_to_max_jump if arch else 1.0
        _hud.update_throw(_throw_charge / throw_max_charge_time)
        _hud.update_jump(_jump_charge / jump_max)

    if not is_instance_valid(_grabbed):
        _process_grab_look()

    _apply_grab_force()
    _apply_grab_torque()
    if is_instance_valid(_grabbed):
        _update_curve()
        

func _update_ragdoll_camera(_delta: float) -> void:
    var rd := _get_ragdoll()
    if _debug_cam_mode == 0:
        if rd != null and is_instance_valid(rd.head_body):
            player_camera.global_position = rd.head_body.global_position
        player_camera.global_rotation = Vector3(camera_pitch, camera_yaw, 0.0)
    if rd != null and rd.is_recovering:
        char_rigidbody.rotation.y = camera_yaw


func _release_jump() -> void:
    var arch := _get_arch()
    if arch == null or not char_rigidbody.is_grounded:
        _cancel_jump_charge()
        return
    var t := _jump_charge / arch.time_to_max_jump
    var max_impulse := arch.jump_strenght * char_rigidbody.mass * CharacterRigidBody3D.JUMP_SCALE
    char_rigidbody.jump(lerpf(max_impulse * 0.3, max_impulse, t))
    _cancel_jump_charge()


func _cancel_jump_charge() -> void:
    _jump_charge = 0.0
    var bi := _get_bi()
    if is_instance_valid(bi):
        var tw := create_tween()
        tw.tween_property(bi, "jump_squat_t", 0.0, 0.08)


func _start_crouch() -> void:
    var bi := _get_bi()
    if not is_instance_valid(bi):
        return
    _is_crouched = true
    if _is_charging_jump:
        _is_charging_jump = false
        _jump_charge = 0.0
    var tw := create_tween()
    tw.tween_property(bi, "crouch_t", 1.0, 0.12)
    tw.tween_callback(func(): char_rigidbody.set_crouched(true))
    char_rigidbody.crouch_speed_factor = 0.6


func _stop_crouch() -> void:
    var bi := _get_bi()
    if not is_instance_valid(bi):
        return
    _is_crouched = false
    char_rigidbody.set_crouched(false)
    var tw := create_tween()
    tw.tween_property(bi, "crouch_t", 0.0, 0.12)
    char_rigidbody.crouch_speed_factor = 1.0


func _toggle_ragdoll() -> void:
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if not is_instance_valid(bi) or not is_instance_valid(bi.ragdoll_util):
        return
    if bi.ragdoll_util.is_active:
        bi.ragdoll_util.deactivate(char_rigidbody, bi.custom_bones_util.lower_spine)
        char_rigidbody.rotation.y = camera_yaw
        camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    else:
        char_rigidbody.is_snapshot_active = false
        bi.ragdoll_util.activate(char_rigidbody, bi.custom_bones_util.lower_spine)


func _start_grab() -> void:
    var grabbable := _get_grabbable(_hovered_rb)
    if not grabbable: return
    _grabbed = _hovered_rb
    var origin := _get_grab_origin()
    _grabbed_grab_point = grabbable.get_nearest_grab_point(origin)
    var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
    _grab_distance = clamp(origin.distance_to(grab_world), grab_dist_min, grab_dist_max)
    _grabbed.sleeping = false
    _grab_target_rotation = _grabbed.global_transform.basis.get_rotation_quaternion()

    var bi := _get_bi()
    if is_instance_valid(bi):
        var left_h := grabbable.get_nearest_handle_point(bi.custom_bones_util.left_upper_arm.global_position)
        var right_h := grabbable.get_nearest_handle_point(bi.custom_bones_util.right_upper_arm.global_position, left_h)
        bi.set_grab_handles(left_h, right_h)
        var tw := create_tween()
        tw.tween_property(bi, "_grab_arm_blend", 1.0, 0.15)
    _grab_target_rotation = _grabbed.global_transform.basis.get_rotation_quaternion()
    var player_rot := Quaternion(char_rigidbody.global_transform.basis)
    _grab_relative_rotation = player_rot.inverse() * _grab_target_rotation


func _stop_grab() -> void:
    _grabbed = null
    _grabbed_grab_point = null
    _is_rotating = false
    if is_instance_valid(_curve_mesh):
        _curve_mesh.queue_free()
        _curve_mesh = null
    var bi := _get_bi()
    if is_instance_valid(bi):
        var tw := create_tween()
        tw.tween_property(bi, "_grab_arm_blend", 0.0, 0.15)
        tw.tween_callback(func(): bi.clear_grab_handles())


func _apply_grab_force() -> void:
    if not is_instance_valid(_grabbed):
        _grabbed = null
        return
    var origin := _get_grab_origin()
    var target_pos := origin + (-player_camera.global_transform.basis.z) * _grab_distance
    var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
    var force := (target_pos - grab_world) * grab_stiffness - _grabbed.linear_velocity * grab_damping
    _grabbed.apply_central_force(force)
    _grabbed.sleeping = false

func _apply_grab_torque() -> void:
    if not is_instance_valid(_grabbed):
        return
    if not _is_rotating:
        var player_rot := Quaternion(char_rigidbody.global_transform.basis)
        _grab_target_rotation = player_rot * _grab_relative_rotation
    var current := _grabbed.global_transform.basis.get_rotation_quaternion()
    var error := (_grab_target_rotation * current.inverse()).normalized()
    var angle := error.get_angle()
    if angle > PI: angle -= TAU
    _grabbed.apply_torque(error.get_axis() * angle * grab_rotation_stiffness - _grabbed.angular_velocity * grab_rotation_damping)


func _find_bone_instantiator(node: Node) -> BoneInstantiator:
    var current := node.get_parent()
    while current:
        if current is BoneInstantiator:
            return current
        current = current.get_parent()
    return null


func _switch_to(target: BoneInstantiator) -> void:
    var current_bi := char_rigidbody.get_parent() as BoneInstantiator

    if not (is_instance_valid(current_bi.ragdoll_util) and current_bi.ragdoll_util.is_active):
        current_bi.char_rigidbody.is_active = false
    current_bi.is_active = false

    target.is_active = true
    char_rigidbody = target.char_rigidbody
    head_bone = target.custom_bones_util.head
    head_size = target.skel_sizes_util.head_size

    _max_reach_distance = target.entity_instantiation.arch_final.reach * target.entity_instantiation.arch_final.reach_multiplier
    grab_ray_length = _max_reach_distance + 2.0

    player_camera.get_parent().remove_child(player_camera)
    char_rigidbody.add_child(player_camera)
    target.player_camera = player_camera
    player_camera.current = _debug_cam_mode == 0
    player_camera.position = Vector3.ZERO
    player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)
    char_rigidbody.is_active = true
    char_rigidbody.rotation.y = camera_yaw
    camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    _was_ragdoll_active = false

    var bones_to_clear := [
        target.custom_bones_util.head,
        target.custom_bones_util.neck,
        target.custom_bones_util.chest,
        target.custom_bones_util.upper_spine,
        target.custom_bones_util.middle_spine,
    ]
    for bone in bones_to_clear:
        if is_instance_valid(bone):
            target.procedural_animator.unregister_bone(bone)
    target.refresh_camera_animations()

    if _is_crouched:
        char_rigidbody.set_crouched(false)
    _is_crouched = false
    _is_charging_jump = false
    _jump_charge = 0.0
    char_rigidbody.crouch_speed_factor = 1.0

    if is_instance_valid(_hud):
        _hud.queue_free()
    _hud = PlayerHUD.create(target.entity_instantiation)
    char_rigidbody.add_child(_hud)

    _connect_fall_signal(char_rigidbody)
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if is_instance_valid(bi):
        bi.set_first_person_visibility(_debug_cam_mode == 0)
    _stop_grab()
    _clear_outline()


func _build_outline_material() -> void:
    var shader := load("res://shaders/outline.gdshader") as Shader
    _outline_material = ShaderMaterial.new()
    _outline_material.shader = shader
    _outline_material.set_shader_parameter("color", outline_color)
    _outline_material.set_shader_parameter("outline_thickness", outline_size)


func _process_grab_look() -> void:
    if not is_instance_valid(player_camera):
        return
    var vp_size := player_camera.get_viewport().get_visible_rect().size
    var from := player_camera.global_position
    var dir  := player_camera.project_ray_normal(vp_size * 0.5)
    var query := PhysicsRayQueryParameters3D.create(from, from + dir * grab_ray_length)
    query.collision_mask = 1 | 2
    var own_bi := char_rigidbody.get_parent() as BoneInstantiator
    var excludes: Array[RID] = [char_rigidbody.get_rid()]
    if is_instance_valid(own_bi) and is_instance_valid(own_bi.ragdoll_util):
        for rid in own_bi.ragdoll_util._ragdoll_rids:
            excludes.append(rid)
    query.exclude = excludes

    var hit := player_camera.get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty() and hit.collider is RigidBody3D:
        var hit_bi := _find_bone_instantiator(hit.collider)
        if hit_bi != null and hit_bi == own_bi:
            _clear_outline()
            return
        if is_instance_valid(own_bi):
             var chest := own_bi.custom_bones_util.chest
             var chest_tip := chest.global_position + chest.global_transform.basis.y * own_bi.skel_sizes_util.chest_size.y
             if hit["position"].distance_to(chest_tip) > _max_reach_distance:
                _clear_outline()
                return
          # solo objetos con Grabbable son agarrables
        if not _get_grabbable(hit.collider as RigidBody3D):
            _clear_outline()
            return
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
    var p2   := _grabbed.global_position
    var dist := p0.distance_to(p2)
    var p1   := (p0 + p2) * 0.5 + Vector3.UP * dist * grab_sag_factor
    var cp0  := p0 + (p1 - p0) * (2.0 / 3.0)
    var cp1  := p2 + (p1 - p2) * (2.0 / 3.0)

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

    var prev_pos := Vector3(char_rigidbody.global_position.x, 3.0, char_rigidbody.global_position.z)

    current_bi.master_seed = randi() % 100000
    current_bi.initialize_skeleton()

    char_rigidbody = current_bi.char_rigidbody
    head_bone      = current_bi.custom_bones_util.head
    head_size      = current_bi.skel_sizes_util.head_size
    _max_reach_distance = current_bi.entity_instantiation.arch_final.reach * current_bi.entity_instantiation.arch_final.reach_multiplier
    grab_ray_length = _max_reach_distance + 2.0
    char_rigidbody.global_position = prev_pos
    char_rigidbody.rotation.y = camera_yaw
    camera_y_smooth = head_bone.global_position.y + head_size.y * 0.5
    _was_ragdoll_active = false

    if _is_crouched:
        char_rigidbody.set_crouched(false)
    _is_crouched = false
    _is_charging_jump = false
    _jump_charge = 0.0
    char_rigidbody.crouch_speed_factor = 1.0

    player_camera.get_parent().remove_child(player_camera)
    char_rigidbody.add_child(player_camera)
    player_camera.current = _debug_cam_mode == 0
    player_camera.position = Vector3.ZERO
    player_camera.rotation = Vector3(camera_pitch, 0.0, 0.0)

    if is_instance_valid(_hud):
        _hud.queue_free()
    _hud = PlayerHUD.create(current_bi.entity_instantiation)
    char_rigidbody.add_child(_hud)

    _connect_fall_signal(char_rigidbody)
    _stop_grab()
    _clear_outline()


func _process_stamina(delta: float) -> void:
    var is_sprinting := Input.is_action_pressed("sprint") \
        and Input.get_axis("move_forward", "move_backward") < 0.0 \
        and char_rigidbody.can_sprint

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

func _release_throw() -> void:
    var bi := _get_bi()
    var dir := -player_camera.global_transform.basis.z
    if is_instance_valid(_hovered_rb) and is_instance_valid(bi):
        var chest_bone := bi.custom_bones_util.chest
        var origin := chest_bone.global_position + chest_bone.global_transform.basis.y * bi.skel_sizes_util.chest_size.y
        var t := _throw_charge / throw_max_charge_time
        _hovered_rb.apply_impulse(dir * throw_strength * t, _hovered_rb.global_position - origin)
    if is_instance_valid(bi):
        bi.throw_push_t = 1.0
        bi.throw_world_dir = dir
    _throw_charge = 0.0

func _get_grab_origin() -> Vector3:
    var bi := _get_bi()
    if not is_instance_valid(bi): return player_camera.global_position
    var chest := bi.custom_bones_util.chest
    return chest.global_position + chest.global_transform.basis.y * bi.skel_sizes_util.chest_size.y

func _get_grabbable(rb: RigidBody3D) -> Grabbable:
    for child in rb.get_children():
        if child is Grabbable:
            return child as Grabbable
    return null
