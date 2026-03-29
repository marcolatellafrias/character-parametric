class_name InteractionController
extends Node

var char_rigidbody: CharacterRigidBody3D
var player_camera:  Camera3D
var arms_controller: ArmsController
var anim_mod: AnimationModifiers

var grab_stiffness:           float = 150.0
var grab_damping:             float = 15.0
var grab_dist_min:            float = 0.5
var grab_dist_max:            float = 5.0
var grab_rotation_sensitivity: float = 0.005
var grab_rotation_stiffness:  float = 50.0
var grab_rotation_damping:    float = 8.0
var grab_sag_factor:          float = 0.3
var show_grab_curve:          bool  = true
var grab_curve_color:         Color = Color(1, 1, 1)
var grab_cone_half_angle:     float = 120.0
var throw_strength:           float = 500.0
var throw_max_charge_time:    float = 0.5
var scroll_sensitivity:       float = 0.15
var effort_cone_fraction:     float = 0.6
var effort_time_threshold:    float = 0.5

var _grabbed:               RigidBody3D = null
var _grabbed_grab_point:    Node3D      = null
var _grab_distance:         float       = 3.0
var _is_rotating:           bool        = false
var _grab_target_rotation:  Quaternion  = Quaternion.IDENTITY
var _grab_relative_rotation: Quaternion = Quaternion.IDENTITY

var _curve_mesh:        MeshInstance3D = null
var _is_charging_throw: bool           = false
var _throw_charge:      float          = 0.0
var _effort_timer:      float          = 0.0
var _is_high_effort:    bool           = false

var _controlled:           ControllableInteractable = null
var _entity_instantiation: EntityInstantiation      = null

var detector: InteractionDetector = null

signal high_effort_started()
signal high_effort_ended()

func setup(rb: CharacterRigidBody3D, cam: Camera3D, arms: ArmsController, anim: AnimationModifiers, max_reach: float, inst: EntityInstantiation) -> void:
    char_rigidbody        = rb
    player_camera         = cam
    arms_controller       = arms
    anim_mod              = anim
    _entity_instantiation = inst
    set_reach(max_reach)
    _update_grab_strength()

    detector = InteractionDetector.new()
    add_child(detector)
    detector.setup(rb, cam, rb.get_parent() as BoneInstantiator)

func set_reach(max_reach: float) -> void:
    grab_dist_max = max_reach
    grab_dist_min = max_reach * 0.1
    if is_instance_valid(detector):
        detector.set_reach(max_reach)

func set_entity_instantiation(inst: EntityInstantiation) -> void:
    _entity_instantiation = inst
    _update_grab_strength()

func get_camera_sensitivity_factor() -> float:
    if is_instance_valid(_controlled):
        return _controlled.camera_sensitivity_factor
    return 1.0

func get_hovered_rb() -> RigidBody3D:
    var h := detector.get_hovered() if is_instance_valid(detector) else null
    if h is GrabbableInteractable:
        return h.get_parent() as RigidBody3D
    return null

func get_throw_charge_normalized() -> float:
    return _throw_charge / throw_max_charge_time

func is_charging_throw() -> bool:
    return _is_charging_throw

func handle_input(event: InputEvent) -> void:
    var bi     := char_rigidbody.get_parent() as BoneInstantiator
    var seated := is_instance_valid(bi) and bi.is_seated

    if event is InputEventKey and not event.echo:
        if event.keycode == KEY_E and event.pressed:
            if seated and is_instance_valid(bi.current_seat):
                bi.current_seat.activate(bi)
            else:
                var hovered := detector.get_hovered() if is_instance_valid(detector) else null
                if hovered is ActivatableInteractable:
                    (hovered as ActivatableInteractable).activate(bi)

        if event.keycode == KEY_R:
            if event.pressed and not _is_charging_throw:
                _is_charging_throw = true
                _throw_charge      = 0.0
            elif not event.pressed and _is_charging_throw:
                _release_throw()

    if event is InputEventMouseButton:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                if event.pressed:
                    var hovered := detector.get_hovered() if is_instance_valid(detector) else null
                    if is_instance_valid(hovered):
                        if hovered is GrabbableInteractable:
                            _start_grab(hovered as GrabbableInteractable)
                        elif hovered is ControllableInteractable:
                            _start_control(hovered as ControllableInteractable)
                else:
                    _stop_grab()
                    _stop_control()
            MOUSE_BUTTON_RIGHT:
                _is_rotating = event.pressed and is_instance_valid(_grabbed)
            MOUSE_BUTTON_WHEEL_UP:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance - scroll_sensitivity, grab_dist_min, grab_dist_max)
                elif is_instance_valid(_controlled):
                    _controlled.handle_scroll(-1.0)
            MOUSE_BUTTON_WHEEL_DOWN:
                if is_instance_valid(_grabbed):
                    _grab_distance = clamp(_grab_distance + scroll_sensitivity, grab_dist_min, grab_dist_max)
                elif is_instance_valid(_controlled):
                    _controlled.handle_scroll(1.0)

    if event is InputEventMouseMotion:
        if _is_rotating and is_instance_valid(_grabbed):
            var delta_rot := Quaternion(player_camera.global_transform.basis.x, -event.relative.y * grab_rotation_sensitivity) \
                          * Quaternion(player_camera.global_transform.basis.y, -event.relative.x * grab_rotation_sensitivity)
            _grab_target_rotation = delta_rot * _grab_target_rotation
        if is_instance_valid(_controlled):
            _controlled.handle_mouse_motion(event.relative)

func update(delta: float) -> void:
    if is_instance_valid(detector):
        if not is_instance_valid(_grabbed) and not is_instance_valid(_controlled):
            detector.update()

    if _is_charging_throw:
        _throw_charge = min(_throw_charge + delta, throw_max_charge_time)
        if is_instance_valid(anim_mod):
            anim_mod.set_throw_charge(_throw_charge / throw_max_charge_time, -player_camera.global_transform.basis.z)

    if not is_instance_valid(_grabbed):
        _reset_effort()
    else:
        _apply_grab_force()
        if not is_instance_valid(_grabbed):
            return
        _apply_grab_torque()
        _update_effort_zone(delta)
        if is_instance_valid(arms_controller):
            var grabbable := _get_grabbable(_grabbed)
            if is_instance_valid(grabbable):
                arms_controller.update_grab_handles(delta, grabbable, _get_grab_origin(), _grabbed_grab_point)
        _update_curve()

    if is_instance_valid(_controlled) and is_instance_valid(arms_controller):
        var grab_point := _controlled.get_nearest_handle_point(_get_grab_origin())
        
        # Cone check — misma logica que _apply_grab_force
        var origin  := _get_grab_origin()
        var cam_fwd := -player_camera.global_transform.basis.z
        var ctrl_world := grab_point.global_position if is_instance_valid(grab_point) else _controlled.global_position
        var to_ctrl := ctrl_world - origin
        if to_ctrl.length() > 0.001:
            if to_ctrl.normalized().dot(cam_fwd) < cos(deg_to_rad(grab_cone_half_angle)):
                _stop_control()
                if is_instance_valid(arms_controller):
                    arms_controller.stop_grab()
                return
        
        arms_controller.update_grab_handles(delta, _controlled, _get_grab_origin(), grab_point)
        
func stop_all() -> void:
    _stop_grab()
    _stop_control()
    if is_instance_valid(detector):
        detector.force_clear()
    cancel_throw()

func cancel_throw() -> void:
    _is_charging_throw = false
    _throw_charge      = 0.0
    if is_instance_valid(anim_mod):
        anim_mod.cancel_throw()

# ── Control ───────────────────────────────────────────────────────────────────

func _start_control(ctrl: ControllableInteractable) -> void:
    _controlled = ctrl
    _controlled.start_control()
    if is_instance_valid(arms_controller):
        var grab_point := ctrl.get_nearest_handle_point(_get_grab_origin())
        arms_controller.start_grab(ctrl, _get_grab_origin(), grab_point, grab_dist_min, grab_dist_max)

func _stop_control() -> void:
    if is_instance_valid(_controlled):
        _controlled.stop_control()
    _controlled = null
    if is_instance_valid(arms_controller):
        arms_controller.stop_grab()

# ── Grab ──────────────────────────────────────────────────────────────────────

func _start_grab(grabbable: GrabbableInteractable) -> void:
    var rb := grabbable.get_parent() as RigidBody3D
    if not is_instance_valid(rb):
        return
    _grabbed = rb
    var origin             := _get_grab_origin()
    _grabbed_grab_point    = grabbable.get_nearest_grab_point(origin)
    var grab_world         := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
    _grab_distance         = clamp(origin.distance_to(grab_world), grab_dist_min, grab_dist_max)
    _grabbed.sleeping      = false
    _grab_target_rotation  = _grabbed.global_transform.basis.get_rotation_quaternion()
    var player_rot         := Quaternion(char_rigidbody.global_transform.basis)
    _grab_relative_rotation = player_rot.inverse() * _grab_target_rotation
    if is_instance_valid(arms_controller):
        arms_controller.start_grab(grabbable, _get_grab_origin(), _grabbed_grab_point, grab_dist_min, grab_dist_max)

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
    var to_grab    := grab_world - origin
    if to_grab.length() > 0.001:
        if to_grab.normalized().dot(cam_fwd) < cos(deg_to_rad(grab_cone_half_angle)):
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
        _grabbed.apply_central_impulse(dir * throw_strength * t)
    elif is_instance_valid(detector):
        var h := detector.get_hovered()
        if h is GrabbableInteractable:
            var rb := h.get_parent() as RigidBody3D
            if is_instance_valid(rb):
                rb.apply_impulse(dir * throw_strength * t, rb.global_position - _get_grab_origin())
    if is_instance_valid(anim_mod):
        anim_mod.trigger_throw_push(dir)
    _is_charging_throw = false
    _throw_charge      = 0.0
    _stop_grab()

func _get_grab_origin() -> Vector3:
    var bi := char_rigidbody.get_parent() as BoneInstantiator
    if not is_instance_valid(bi):
        return player_camera.global_position
    var chest := bi.custom_bones_util.chest
    return chest.global_position + chest.global_transform.basis.y * bi.skel_sizes_util.chest_size.y

func _get_grabbable(rb: RigidBody3D) -> GrabbableInteractable:
    for child in rb.get_children():
        if child is GrabbableInteractable:
            return child as GrabbableInteractable
    return null

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
    _curve_mesh = DebugUtil.create_debug_path3d([
        { "pos": p0, "in": Vector3.ZERO, "out": cp0 - p0 },
        { "pos": p2, "in": cp1 - p2,     "out": Vector3.ZERO }
    ], 16, grab_curve_color, 0.01)
    get_tree().current_scene.add_child(_curve_mesh)

func _update_effort_zone(delta: float) -> void:
    var origin     := _get_grab_origin()
    var cam_fwd    := -player_camera.global_transform.basis.z
    var grab_world := _grabbed_grab_point.global_position if is_instance_valid(_grabbed_grab_point) else _grabbed.global_position
    var to_grab    := (grab_world - origin).normalized()
    if to_grab.dot(cam_fwd) >= cos(deg_to_rad(grab_cone_half_angle * effort_cone_fraction)):
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

func _update_grab_strength() -> void:
    if not is_instance_valid(_entity_instantiation):
        return
    var arch       := _entity_instantiation.arch_final
    grab_stiffness = arch.strenght * arch.weight * 9.8
    grab_damping   = grab_stiffness * 0.1
