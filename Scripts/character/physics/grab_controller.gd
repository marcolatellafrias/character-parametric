# GrabController completo
class_name GrabController
extends Node

var char_rigidbody: CharacterRigidBody3D
var player_camera: Camera3D
var arms_controller: ArmsController
var anim_mod: AnimationModifiers

var grab_stiffness: float = 150.0
var grab_damping: float = 15.0
var grab_dist_min: float = 0.5
var grab_dist_max: float = 5.0
var grab_rotation_sensitivity: float = 0.005
var grab_rotation_stiffness: float = 50.0
var grab_rotation_damping: float = 8.0
var grab_sag_factor: float = 0.3
var grab_ray_length: float = 10.0
var outline_color: Color = Color(1, 1, 0, 1)
var outline_size: float = 0.01
var show_grab_curve: bool = true
var grab_curve_color: Color = Color(1, 1, 1)
var grab_cone_half_angle: float = 40.0

var throw_strength: float = 500.0
var throw_max_charge_time: float = 0.5

var _grabbed: RigidBody3D = null
var _grabbed_grab_point: Node3D = null
var _grab_distance: float = 3.0
var _is_rotating: bool = false
var _grab_target_rotation: Quaternion = Quaternion.IDENTITY
var _grab_relative_rotation: Quaternion = Quaternion.IDENTITY

var _hovered_parent: Node = null
var _hovered_rb: RigidBody3D = null
var _hovered_meshes: Array[MeshInstance3D] = []
var _outline_material: ShaderMaterial = null

var _curve_mesh: MeshInstance3D = null

var _is_charging_throw: bool = false
var _throw_charge: float = 0.0

var _max_reach_distance: float = 1.0

var _entity_instantiation: EntityInstantiation = null

var _show_cone: bool = true
var _cone_mesh_instance: MeshInstance3D = null
var _cone_immediate_mesh: ImmediateMesh = null

var scroll_sensitivity: float = 0.15

var effort_cone_fraction: float = 0.6
var effort_time_threshold: float = 0.5

var _effort_timer: float = 0.0
var _is_high_effort: bool = false

signal high_effort_started()
signal high_effort_ended()

func setup(rb: CharacterRigidBody3D, cam: Camera3D, arms: ArmsController, anim: AnimationModifiers, max_reach: float, inst: EntityInstantiation) -> void:
    char_rigidbody        = rb
    player_camera         = cam
    arms_controller       = arms
    anim_mod              = anim
    _entity_instantiation = inst
    set_reach(max_reach)
    _build_outline_material()
    _build_cone_mesh()
    _update_grab_strength()

func set_anim_mod(anim: AnimationModifiers) -> void:
    anim_mod = anim

func set_reach(max_reach: float) -> void:
    _max_reach_distance = max_reach
    grab_dist_max       = max_reach
    grab_dist_min       = max_reach * 0.1
    grab_ray_length     = grab_dist_max + 2.0

func set_entity_instantiation(inst: EntityInstantiation) -> void:
    _entity_instantiation = inst
    _update_grab_strength()

func _update_grab_strength() -> void:
    if not is_instance_valid(_entity_instantiation):
        return
    var arch        := _entity_instantiation.arch_final
    var gravity     := 9.8
    grab_stiffness  = arch.strenght * arch.weight * gravity
    grab_damping    = grab_stiffness * 0.1

func handle_input(event: InputEvent) -> void:
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
                    _grab_distance = clamp(_grab_distance - scroll_sensitivity, grab_dist_min, grab_dist_max)
            MOUSE_BUTTON_WHEEL_DOWN:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance + scroll_sensitivity, grab_dist_min, grab_dist_max)

    if event is InputEventMouseMotion and _is_rotating and is_instance_valid(_grabbed):
        var delta_rot := Quaternion(player_camera.global_transform.basis.x, -event.relative.y * grab_rotation_sensitivity) \
                      * Quaternion(player_camera.global_transform.basis.y, -event.relative.x * grab_rotation_sensitivity)
        _grab_target_rotation = delta_rot * _grab_target_rotation

    if event is InputEventKey and not event.echo:
        if event.keycode == KEY_R:
            if event.pressed and not _is_charging_throw:
                _is_charging_throw = true
                _throw_charge      = 0.0
            elif not event.pressed and _is_charging_throw:
                _release_throw()
        if event.keycode == KEY_V and event.pressed:
            _toggle_cone_vis()

func update(delta: float) -> void:
    if _is_charging_throw:
        _throw_charge = min(_throw_charge + delta, throw_max_charge_time)
        if is_instance_valid(anim_mod):
            anim_mod.set_throw_charge(_throw_charge / throw_max_charge_time, -player_camera.global_transform.basis.z)

    if not is_instance_valid(_grabbed):
        _process_hover()
        _reset_effort()
    else:
        _apply_grab_force()
        if not is_instance_valid(_grabbed):
            _update_cone_vis()
            return
        _apply_grab_torque()
        _update_effort_zone(delta)
        if is_instance_valid(arms_controller):
            arms_controller.update_grab_handles(delta, _grabbed, _get_grabbable, _get_grab_origin(), _grabbed_grab_point)
        _update_curve()

    _update_cone_vis()

func _start_grab() -> void:
    var grabbable := _get_grabbable(_hovered_rb)
    if not grabbable:
        return
    _grabbed = _hovered_rb
    var origin := _get_grab_origin()
    _grabbed_grab_point = grabbable.get_nearest_grab_point(origin)
    var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
    _grab_distance = clamp(origin.distance_to(grab_world), grab_dist_min, grab_dist_max)
    _grabbed.sleeping = false
    _grab_target_rotation   = _grabbed.global_transform.basis.get_rotation_quaternion()
    var player_rot          := Quaternion(char_rigidbody.global_transform.basis)
    _grab_relative_rotation = player_rot.inverse() * _grab_target_rotation
    if is_instance_valid(arms_controller):
        arms_controller.start_grab(_grabbed, _get_grabbable, _get_grab_origin(), _grabbed_grab_point, grab_dist_min, grab_dist_max)

func _stop_grab() -> void:
    _reset_effort()
    _grabbed            = null
    _grabbed_grab_point = null
    _is_rotating        = false
    if is_instance_valid(_curve_mesh):
        _curve_mesh.queue_free()
        _curve_mesh = null
    if is_instance_valid(arms_controller):
        arms_controller.stop_grab()

func _apply_grab_force() -> void:
    if not is_instance_valid(_grabbed):
        _grabbed = null
        return

    var origin     := _get_grab_origin()
    var cam_fwd    := -player_camera.global_transform.basis.z
    var target_pos := origin + cam_fwd * _grab_distance
    var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position

    var to_grab := grab_world - origin
    if to_grab.length() > 0.001:
        var cos_threshold := cos(deg_to_rad(grab_cone_half_angle))
        if to_grab.normalized().dot(cam_fwd) < cos_threshold:
            _stop_grab()
            return

    var force := (target_pos - grab_world) * grab_stiffness - _grabbed.linear_velocity * grab_damping
    _grabbed.apply_central_force(force)
    _grabbed.sleeping = false

func _apply_grab_torque() -> void:
    if not is_instance_valid(_grabbed):
        return
    if not _is_rotating:
        var player_rot          := Quaternion(char_rigidbody.global_transform.basis)
        _grab_target_rotation   = player_rot * _grab_relative_rotation
    else:
        var player_rot          := Quaternion(char_rigidbody.global_transform.basis)
        _grab_relative_rotation = player_rot.inverse() * _grab_target_rotation
    var current := _grabbed.global_transform.basis.get_rotation_quaternion()
    var error   := (_grab_target_rotation * current.inverse()).normalized()
    var angle   := error.get_angle()
    if angle > PI: angle -= TAU
    _grabbed.apply_torque(error.get_axis() * angle * grab_rotation_stiffness - _grabbed.angular_velocity * grab_rotation_damping)

func _release_throw() -> void:
    var dir := -player_camera.global_transform.basis.z
    var t   := _throw_charge / throw_max_charge_time

    if is_instance_valid(_grabbed):
        # Objeto agarrado: impulso al centro de masa, sin offset
        _grabbed.apply_central_impulse(dir * throw_strength * t)
    elif is_instance_valid(_hovered_rb):
        # Sin objeto agarrado: push con offset original
        var origin := _get_grab_origin()
        _hovered_rb.apply_impulse(dir * throw_strength * t, _hovered_rb.global_position - origin)

    if is_instance_valid(anim_mod):
        anim_mod.trigger_throw_push(dir)
    _is_charging_throw = false
    _throw_charge      = 0.0
    _stop_grab()

func cancel_throw() -> void:
    _is_charging_throw = false
    _throw_charge      = 0.0
    if is_instance_valid(anim_mod):
        anim_mod.cancel_throw()

func get_throw_charge_normalized() -> float:
    return _throw_charge / throw_max_charge_time

func is_charging_throw() -> bool:
    return _is_charging_throw

func get_hovered_rb() -> RigidBody3D:
    return _hovered_rb

func stop_all() -> void:
    _stop_grab()
    _clear_outline()
    cancel_throw()

func _process_hover() -> void:
    if not is_instance_valid(player_camera):
        return
    var vp_size := player_camera.get_viewport().get_visible_rect().size
    var from    := player_camera.global_position
    var dir     := player_camera.project_ray_normal(vp_size * 0.5)
    var query   := PhysicsRayQueryParameters3D.create(from, from + dir * grab_ray_length)
    query.collision_mask = 1 | 2
    var own_bi  := char_rigidbody.get_parent() as BoneInstantiator
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
            var chest     := own_bi.custom_bones_util.chest
            var chest_tip := chest.global_position + chest.global_transform.basis.y * own_bi.skel_sizes_util.chest_size.y
            if hit["position"].distance_to(chest_tip) > _max_reach_distance:
                _clear_outline()
                return
        if not _get_grabbable(hit.collider as RigidBody3D):
            _clear_outline()
            return
        var parent: Node = hit.collider.get_parent()
        if parent != _hovered_parent:
            _clear_outline()
            _hovered_parent = parent
            _hovered_rb     = hit.collider as RigidBody3D
            _hovered_meshes = _collect_meshes(parent)
            _apply_outline()
    else:
        _clear_outline()

func _get_grab_origin() -> Vector3:
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if not is_instance_valid(bi):
        return player_camera.global_position
    var chest := bi.custom_bones_util.chest
    return chest.global_position + chest.global_transform.basis.y * bi.skel_sizes_util.chest_size.y

func _get_grabbable(rb: RigidBody3D) -> Grabbable:
    for child in rb.get_children():
        if child is Grabbable:
            return child as Grabbable
    return null

func _find_bone_instantiator(node: Node) -> BoneInstantiator:
    var current := node.get_parent()
    while current:
        if current is BoneInstantiator:
            return current
        current = current.get_parent()
    return null

func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    _collect_meshes_recursive(node, result)
    return result

func _collect_meshes_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        _collect_meshes_recursive(child, result)

func _build_outline_material() -> void:
    var shader        := load("res://shaders/outline.gdshader") as Shader
    _outline_material  = ShaderMaterial.new()
    _outline_material.shader = shader
    _outline_material.set_shader_parameter("color", outline_color)
    _outline_material.set_shader_parameter("outline_thickness", outline_size)

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
    _hovered_rb     = null

func _update_curve() -> void:
    if is_instance_valid(_curve_mesh):
        _curve_mesh.queue_free()
        _curve_mesh = null
    if not show_grab_curve:
        return
    var p0   := _get_grab_origin()
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

# ── Cone visualization ────────────────────────────────────────────────────────

func _build_cone_mesh() -> void:
    var length := grab_dist_max
    var radius : float = length * abs(tan(deg_to_rad(grab_cone_half_angle)))
    _cone_mesh_instance = DebugUtil.create_debug_cone(Color(0.2, 0.8, 1.0, 0.15), length, radius)
    char_rigidbody.get_parent().add_child(_cone_mesh_instance)

func _toggle_cone_vis() -> void:
    _show_cone = not _show_cone
    if is_instance_valid(_cone_mesh_instance):
        _cone_mesh_instance.visible = _show_cone

func _update_cone_vis() -> void:
    if not _show_cone or not is_instance_valid(player_camera) or not is_instance_valid(_cone_mesh_instance):
        return
    var origin := _get_grab_origin()
    var fwd    := -player_camera.global_transform.basis.z
    _cone_mesh_instance.global_position = origin
    _cone_mesh_instance.global_transform.basis = Basis.looking_at(-fwd, Vector3.UP)

func _update_effort_zone(delta: float) -> void:
    var origin  := _get_grab_origin()
    var cam_fwd := -player_camera.global_transform.basis.z
    var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
    var to_grab := (grab_world - origin).normalized()

    var easy_half_angle := grab_cone_half_angle * effort_cone_fraction
    var cos_easy := cos(deg_to_rad(easy_half_angle))
    var in_easy_cone := to_grab.dot(cam_fwd) >= cos_easy

    if in_easy_cone:
        _reset_effort()
    else:
        _effort_timer += delta
        if not _is_high_effort and _effort_timer >= effort_time_threshold:
            _is_high_effort = true
            high_effort_started.emit()

func _reset_effort() -> void:
    _effort_timer = 0.0
    if _is_high_effort:
        _is_high_effort = false
        high_effort_ended.emit()
