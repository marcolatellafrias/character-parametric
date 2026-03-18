class_name RagdollUtil
extends RefCounted



const RAGDOLL_LAYER := 2
const RAGDOLL_MASK  := 1

var is_active: bool = false
var is_recovering: bool = false
var recovery_duration: float = 0.6
var debug_ragdoll_color: bool = false

var trip_force_multiplier: float = 1.0
var trip_twist_multiplier: float = 0.5

var _recovery_timer: float = 0.0
var _skeleton_root: CustomBone = null
var _recovery_start_transforms: Dictionary = {}

var head_body: RigidBody3D = null

var _skel_rb_node: Node3D
var _joints_node: Node3D
var _bones_util: CustomBonesUtil
var _bodies: Dictionary = {}
var _ragdoll_rids: Array[RID] = []
var _joints: Array[Generic6DOFJoint3D] = []
var _pending_bodies: Array[RigidBody3D] = []
var _char_rid: RID
var _char_rb: CharacterRigidBody3D = null
var _recovering_char_rb: CharacterRigidBody3D = null
var _lower_spine_body: RigidBody3D = null
var _camera: Camera3D = null


static func create(bones_util: CustomBonesUtil, skel_rb_node: Node3D, joints_node: Node3D) -> RagdollUtil:
    var ru := RagdollUtil.new()
    ru._skel_rb_node = skel_rb_node
    ru._joints_node  = joints_node
    ru._bones_util   = bones_util
    ru._build_bodies(bones_util)
    return ru


func _build_bodies(bu: CustomBonesUtil) -> void:
    var all_bones: Array = [
        bu.lower_spine, bu.middle_spine, bu.upper_spine, bu.chest,
        bu.left_hip, bu.right_hip,
        bu.left_upper_leg, bu.left_lower_leg,
        bu.right_upper_leg, bu.right_lower_leg,
        bu.right_upper_feet, bu.left_upper_feet,
        bu.neck, bu.head,
        bu.left_shoulder, bu.right_shoulder,
        bu.right_upper_arm, bu.right_lower_arm,
        bu.left_upper_arm, bu.left_lower_arm,
    ]
    for bone in all_bones:
        if not is_instance_valid(bone):
            continue
        var rb := _make_body(bone)
        _bodies[bone] = rb
        _skel_rb_node.add_child(rb)
        _ragdoll_rids.append(rb.get_rid())

    _lower_spine_body = _bodies.get(bu.lower_spine, null)
    head_body         = _bodies.get(bu.head, null)


func _make_body(bone: CustomBone) -> RigidBody3D:
    var rb := RigidBody3D.new()
    rb.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
    rb.freeze          = true
    rb.collision_layer = RAGDOLL_LAYER
    rb.collision_mask  = RAGDOLL_MASK
    rb.can_sleep       = false
    rb.mass            = 1.0
    rb.linear_damp     = 0.5
    rb.angular_damp    = 1.0
    rb.global_transform = bone.global_transform

    var d := bone.capsule_dimensions
    var caps := CapsuleShape3D.new()
    caps.radius = min(d.x, d.z) * 0.45
    caps.height = max(d.y, caps.radius * 2.1)

    var shape := CollisionShape3D.new()
    shape.shape    = caps
    shape.position = Vector3(0.0, d.y * 0.5, 0.0)
    rb.add_child(shape)

    for child in bone.get_children():
        if child is MeshInstance3D:
            var mesh_copy := child.duplicate() as MeshInstance3D
            mesh_copy.material_override = child.material_override
            mesh_copy.visible = false
            rb.add_child(mesh_copy)
            break

    return rb


func _build_joints() -> void:
    var bu := _bones_util

    var pairs: Array = [
        [bu.lower_spine,  bu.middle_spine,    55.0, 6.0, -20.0, 20.0, -30.0, 30.0, -20.0, 20.0],
        [bu.middle_spine, bu.upper_spine,     55.0, 6.0, -20.0, 20.0, -30.0, 30.0, -20.0, 20.0],
        [bu.upper_spine,  bu.chest,           50.0, 6.0, -20.0, 20.0, -25.0, 25.0, -20.0, 20.0],
        [bu.lower_spine,  bu.left_hip,        40.0, 5.0, -30.0, 30.0, -40.0, 40.0, -30.0, 30.0],
        [bu.lower_spine,  bu.right_hip,       40.0, 5.0, -30.0, 30.0, -40.0, 40.0, -30.0, 30.0],
        [bu.left_hip,     bu.left_upper_leg,  35.0, 5.0, -40.0, 40.0, -80.0, 40.0, -30.0, 30.0],
        [bu.right_hip,    bu.right_upper_leg, 35.0, 5.0, -40.0, 40.0, -80.0, 40.0, -30.0, 30.0],
        [bu.left_upper_leg,  bu.left_lower_leg,  25.0, 4.0, -10.0, 10.0,   0.0, 130.0, -10.0, 10.0],
        [bu.right_upper_leg, bu.right_lower_leg, 25.0, 4.0, -10.0, 10.0,   0.0, 130.0, -10.0, 10.0],
        [bu.left_lower_leg,  bu.left_upper_feet,  10.0, 3.0, -20.0, 20.0, -30.0, 30.0, -15.0, 15.0],
        [bu.right_lower_leg, bu.right_upper_feet, 10.0, 3.0, -20.0, 20.0, -30.0, 30.0, -15.0, 15.0],
        [bu.chest, bu.left_shoulder,  35.0, 5.0, -50.0, 50.0, -60.0, 60.0, -40.0, 40.0],
        [bu.chest, bu.right_shoulder, 35.0, 5.0, -50.0, 50.0, -60.0, 60.0, -40.0, 40.0],
        [bu.left_shoulder,  bu.left_upper_arm,  25.0, 4.0, -70.0, 70.0, -70.0, 70.0, -70.0, 70.0],
        [bu.right_shoulder, bu.right_upper_arm, 25.0, 4.0, -70.0, 70.0, -70.0, 70.0, -70.0, 70.0],
        [bu.left_upper_arm,  bu.left_lower_arm,  15.0, 3.0, -10.0, 10.0,   0.0, 140.0, -10.0, 10.0],
        [bu.right_upper_arm, bu.right_lower_arm, 15.0, 3.0, -10.0, 10.0,   0.0, 140.0, -10.0, 10.0],
    ]

    if is_instance_valid(bu.neck):
        pairs.append([bu.chest, bu.neck, 50.0, 6.0, -35.0, 35.0, -40.0, 40.0, -30.0, 30.0])
        pairs.append([bu.neck,  bu.head, 45.0, 6.0, -25.0, 25.0, -30.0, 30.0, -20.0, 20.0])
    else:
        pairs.append([bu.chest, bu.head, 45.0, 6.0, -35.0, 35.0, -40.0, 40.0, -30.0, 30.0])

    for pair in pairs:
        var pa: CustomBone = pair[0]
        var ch: CustomBone = pair[1]
        if not is_instance_valid(pa) or not is_instance_valid(ch):
            continue
        if not _bodies.has(pa) or not _bodies.has(ch):
            continue
        _create_joint(
            _bodies[pa], _bodies[ch], ch.global_position, pa, ch,
            pair[2], pair[3],
            deg_to_rad(pair[4]), deg_to_rad(pair[5]),
            deg_to_rad(pair[6]), deg_to_rad(pair[7]),
            deg_to_rad(pair[8]), deg_to_rad(pair[9])
        )


func _create_joint(
        body_a: RigidBody3D, body_b: RigidBody3D, anchor: Vector3,
        bone_a: CustomBone, bone_b: CustomBone,
        stiffness: float, damping: float,
        xl: float, xh: float,
        yl: float, yh: float,
        zl: float, zh: float) -> void:

    var j := Generic6DOFJoint3D.new()
    _joints_node.add_child(j)
    j.global_position = anchor
    j.node_a = j.get_path_to(body_a)
    j.node_b = j.get_path_to(body_b)

    var LL   := Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT
    var LU   := Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT
    var AL   := Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT
    var AU   := Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT
    var LF   := Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT
    var AF   := Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT
    var ASF  := Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING
    var ASST := Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS
    var ASSD := Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING
    var AEQ  := Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT

    j.set_flag_x(LF, true); j.set_flag_y(LF, true); j.set_flag_z(LF, true)
    j.set_param_x(LL, 0.0); j.set_param_x(LU, 0.0)
    j.set_param_y(LL, 0.0); j.set_param_y(LU, 0.0)
    j.set_param_z(LL, 0.0); j.set_param_z(LU, 0.0)

    j.set_flag_x(AF, true); j.set_flag_y(AF, true); j.set_flag_z(AF, true)
    j.set_param_x(AL, xl); j.set_param_x(AU, xh)
    j.set_param_y(AL, yl); j.set_param_y(AU, yh)
    j.set_param_z(AL, zl); j.set_param_z(AU, zh)

    var rest_basis_a  := Basis.from_euler(bone_a.rest_rotation)
    var rest_basis_b  := Basis.from_euler(bone_b.rest_rotation)
    var rest_relative := rest_basis_a.inverse() * rest_basis_b
    var anim_relative := body_a.global_basis.inverse() * body_b.global_basis
    var offset_quat   := anim_relative.get_rotation_quaternion().inverse() \
                        * rest_relative.get_rotation_quaternion()
    var offset_euler  := offset_quat.get_euler()

    j.set_flag_x(ASF, true); j.set_flag_y(ASF, true); j.set_flag_z(ASF, true)
    j.set_param_x(ASST, stiffness); j.set_param_y(ASST, stiffness); j.set_param_z(ASST, stiffness)
    j.set_param_x(ASSD, damping);   j.set_param_y(ASSD, damping);   j.set_param_z(ASSD, damping)
    j.set_param_x(AEQ, offset_euler.x)
    j.set_param_y(AEQ, offset_euler.y)
    j.set_param_z(AEQ, offset_euler.z)

    _joints.append(j)


func sync_to_bones() -> void:
    for bone in _bodies:
        var rb: RigidBody3D = _bodies[bone]
        if is_instance_valid(rb) and is_instance_valid(bone):
            rb.global_transform = bone.global_transform


func activate(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone, camera: Camera3D) -> void:
    if is_recovering:
        is_recovering        = false
        _recovery_timer      = 0.0
        _recovering_char_rb  = null
        _recovery_start_transforms.clear()

    is_active       = true
    _char_rid       = char_rb.get_rid()
    _char_rb        = char_rb
    _camera         = camera
    _skeleton_root  = skeleton_root

    char_rb.is_active         = false
    char_rb.collider.disabled = true
    char_rb.freeze_mode       = RigidBody3D.FREEZE_MODE_STATIC
    char_rb.freeze            = true

    if is_instance_valid(skeleton_root):
        skeleton_root.visible = false

    _set_meshes_visible(true)
    _build_joints()

    if is_instance_valid(_camera):
        _camera.reparent(_skel_rb_node, true)
        _camera.current = true

    var space: PhysicsDirectSpaceState3D = _skel_rb_node.get_world_3d().direct_space_state
    var exclude: Array[RID]              = _make_exclude()
    _pending_bodies.clear()

    for bone: CustomBone in _bodies:
        var rb: RigidBody3D = _bodies[bone]
        if not is_instance_valid(rb):
            continue
        rb.collision_layer  = RAGDOLL_LAYER
        rb.collision_mask   = RAGDOLL_MASK
        rb.linear_velocity  = char_rb.linear_velocity
        rb.angular_velocity = Vector3.ZERO
        rb.freeze           = false

        if _is_overlapping(rb, space, exclude):
            rb.collision_layer = 0
            rb.collision_mask  = 0
            if debug_ragdoll_color:
                _set_body_mesh_color(rb, Color.RED)
            else:
                _clear_body_mesh_color(rb)
            _pending_bodies.append(rb)
        else:
            if debug_ragdoll_color:
                _set_body_mesh_color(rb, Color.GREEN)
            else:
                _clear_body_mesh_color(rb)

    if is_instance_valid(_lower_spine_body):
        var vel: Vector3     = char_rb.linear_velocity
        var speed: float     = max(vel.length(), 3.0)
        var forward: Vector3 = vel.normalized() if vel.length() > 0.1 else -char_rb.global_basis.z

        var base_y: float = _lower_spine_body.global_position.y
        var top_y: float  = head_body.global_position.y if is_instance_valid(head_body) else base_y + 1.5

        var upper_bones: Array = [
            _bodies.get(_bones_util.lower_spine,    null),
            _bodies.get(_bones_util.middle_spine,   null),
            _bodies.get(_bones_util.upper_spine,    null),
            _bodies.get(_bones_util.chest,          null),
            _bodies.get(_bones_util.left_shoulder,  null),
            _bodies.get(_bones_util.right_shoulder, null),
            _bodies.get(_bones_util.left_upper_arm, null),
            _bodies.get(_bones_util.right_upper_arm,null),
            _bodies.get(_bones_util.neck,           null),
            _bodies.get(_bones_util.head,           null),
        ]

        for rb: RigidBody3D in upper_bones:
            if not is_instance_valid(rb):
                continue
            var height_t: float  = clamp((rb.global_position.y - base_y) / max(top_y - base_y, 0.001), 0.0, 1.0)
            var impulse: Vector3 = (forward + Vector3.UP * height_t * 0.5).normalized() * speed * trip_force_multiplier * (0.3 + height_t * 0.7)
            rb.apply_central_impulse(impulse)

        var lower_bones: Array = [
            _bodies.get(_bones_util.left_hip,         null),
            _bodies.get(_bones_util.right_hip,        null),
            _bodies.get(_bones_util.left_upper_leg,   null),
            _bodies.get(_bones_util.right_upper_leg,  null),
            _bodies.get(_bones_util.left_lower_leg,   null),
            _bodies.get(_bones_util.right_lower_leg,  null),
        ]

        for rb: RigidBody3D in lower_bones:
            if not is_instance_valid(rb):
                continue
            var height_t: float  = clamp((rb.global_position.y - base_y) / max(top_y - base_y, 0.001), 0.0, 1.0)
            var impulse: Vector3 = (-forward - Vector3.UP * 0.3).normalized() * speed * trip_force_multiplier * (0.3 + (1.0 - height_t) * 0.7)
            rb.apply_central_impulse(impulse)

        var trip_axis: Vector3   = forward.cross(Vector3.UP).normalized()
        var trip_torque: Vector3 = trip_axis * speed * trip_twist_multiplier
        _lower_spine_body.apply_torque_impulse(trip_torque)


func deactivate(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone) -> void:
    is_active            = false
    is_recovering        = true
    _recovery_timer      = recovery_duration
    _skeleton_root       = skeleton_root
    _char_rb             = null
    _recovering_char_rb  = char_rb
    _pending_bodies.clear()
    _clear_joints()

    _recovery_start_transforms.clear()
    for bone in _bodies:
        var rb: RigidBody3D = _bodies[bone]
        if is_instance_valid(rb):
            _recovery_start_transforms[bone] = rb.global_transform
            rb.freeze          = true
            rb.collision_layer = 0
            rb.collision_mask  = 0

    var safe_pos := _find_safe_spawn(char_rb)
    char_rb.global_position   = safe_pos
    char_rb.linear_velocity   = Vector3.ZERO
    char_rb.angular_velocity  = Vector3.ZERO
    char_rb.collider.disabled = false
    char_rb.freeze            = false
    char_rb.is_active         = true

    if is_instance_valid(_skeleton_root):
        _skeleton_root.visible = false

    # Camera stays in _skel_rb_node and keeps following head_body during recovery.
    # It will be reparented to char_rb in _finish_recovery().


func update(delta: float) -> void:
    if is_active:
        _update_active(delta)
    elif is_recovering:
        _update_recovery(delta)


func _update_active(_delta: float) -> void:
    if is_instance_valid(_char_rb) and is_instance_valid(_lower_spine_body):
        _char_rb.global_position = _lower_spine_body.global_position

    if is_instance_valid(_camera) and is_instance_valid(head_body):
        _camera.global_position = head_body.global_position

    if _pending_bodies.is_empty():
        return
    var space   := _skel_rb_node.get_world_3d().direct_space_state
    var exclude := _make_exclude()
    var still_pending: Array[RigidBody3D] = []
    for rb in _pending_bodies:
        if not is_instance_valid(rb):
            continue
        if _is_overlapping(rb, space, exclude):
            still_pending.append(rb)
        else:
            rb.collision_layer = RAGDOLL_LAYER
            rb.collision_mask  = RAGDOLL_MASK
            if debug_ragdoll_color:
                _set_body_mesh_color(rb, Color.GREEN)
            else:
                _clear_body_mesh_color(rb)
    _pending_bodies = still_pending


func _update_recovery(delta: float) -> void:
    _recovery_timer -= delta
    var t: float = 1.0 - clamp(_recovery_timer / recovery_duration, 0.0, 1.0)
    var t_eased: float = t * t * (3.0 - 2.0 * t)

    var root_bone: CustomBone  = _bones_util.lower_spine
    var root_body: RigidBody3D = _lower_spine_body

    if is_instance_valid(root_body) and is_instance_valid(root_bone):
        var start: Transform3D = _recovery_start_transforms.get(root_bone, root_body.global_transform)
        root_body.global_position = start.origin.lerp(root_bone.global_position, t_eased)
        root_body.global_basis    = start.basis.slerp(root_bone.global_transform.basis, t_eased)

    for bone: CustomBone in _bodies:
        if bone == root_bone:
            continue
        var rb: RigidBody3D = _bodies[bone]
        if not is_instance_valid(rb) or not is_instance_valid(bone):
            continue

        var start: Transform3D = _recovery_start_transforms.get(bone, rb.global_transform)
        rb.global_basis = start.basis.slerp(bone.global_transform.basis, t_eased)

        if is_instance_valid(root_body) and is_instance_valid(root_bone):
            var local_anim_pos: Vector3 = root_bone.to_local(bone.global_position)
            rb.global_position = root_body.to_global(local_anim_pos)

    # Camera keeps following head throughout recovery
    if is_instance_valid(_camera) and is_instance_valid(head_body):
        _camera.global_position = head_body.global_position

    if _recovery_timer <= 0.0:
        _finish_recovery()


func _finish_recovery() -> void:
    is_recovering = false
    _recovery_start_transforms.clear()
    _set_meshes_visible(false)
    for bone in _bodies:
        var rb: RigidBody3D = _bodies[bone]
        if is_instance_valid(rb) and is_instance_valid(bone):
            rb.global_transform = bone.global_transform
            rb.collision_layer  = RAGDOLL_LAYER
            rb.collision_mask   = RAGDOLL_MASK
    if is_instance_valid(_skeleton_root):
        _skeleton_root.visible = true
    _skeleton_root = null

    # Now that recovery is done, move camera to char_rb where it belongs
    if is_instance_valid(_camera) and is_instance_valid(_recovering_char_rb):
        _camera.reparent(_recovering_char_rb, true)
        _camera.current = true
    _camera             = null
    _recovering_char_rb = null


func cleanup() -> void:
    is_recovering   = false
    _recovery_timer = 0.0
    _recovery_start_transforms.clear()
    _clear_joints()
    for bone in _bodies:
        var rb: RigidBody3D = _bodies[bone]
        if is_instance_valid(rb):
            rb.queue_free()
    _bodies.clear()
    _ragdoll_rids.clear()
    head_body           = null
    _lower_spine_body   = null
    _char_rb            = null
    _recovering_char_rb = null
    _camera             = null
    _skeleton_root      = null


func _find_safe_spawn(char_rb: CharacterRigidBody3D) -> Vector3:
    if not is_instance_valid(_lower_spine_body):
        return char_rb.global_position

    var base_pos := _lower_spine_body.global_position
    var space    := _skel_rb_node.get_world_3d().direct_space_state
    var capsule  := char_rb.collider.shape as CapsuleShape3D
    if not capsule:
        return base_pos + Vector3(0.0, 1.0, 0.0)

    var params := PhysicsShapeQueryParameters3D.new()
    params.shape          = capsule
    params.collision_mask = RAGDOLL_MASK
    params.exclude        = _make_exclude()

    var collider_local := char_rb.collider.transform

    for i in range(12):
        var test_pos := Vector3(base_pos.x, base_pos.y + i * 0.35, base_pos.z)
        params.transform = Transform3D(Basis.IDENTITY, test_pos) * collider_local
        if space.intersect_shape(params, 1).is_empty():
            return test_pos

    return Vector3(base_pos.x, base_pos.y + 4.0, base_pos.z)


func _clear_joints() -> void:
    for j in _joints:
        if is_instance_valid(j):
            j.queue_free()
    _joints.clear()


func _set_meshes_visible(value: bool) -> void:
    for bone in _bodies:
        var rb: RigidBody3D = _bodies[bone]
        if not is_instance_valid(rb):
            continue
        for child in rb.get_children():
            if child is MeshInstance3D:
                child.visible = value


func _set_body_mesh_color(rb: RigidBody3D, color: Color) -> void:
    for child in rb.get_children():
        if child is MeshInstance3D:
            var mat := StandardMaterial3D.new()
            mat.albedo_color = color
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            child.material_override = mat
            break


func _clear_body_mesh_color(rb: RigidBody3D) -> void:
    var original_bone: CustomBone = null
    for bone in _bodies:
        if _bodies[bone] == rb:
            original_bone = bone
            break
    for child in rb.get_children():
        if child is MeshInstance3D:
            if is_instance_valid(original_bone):
                for bone_child in original_bone.get_children():
                    if bone_child is MeshInstance3D:
                        child.material_override = bone_child.material_override
                        break
            else:
                child.material_override = null
            break


func _make_exclude() -> Array[RID]:
    var arr: Array[RID] = []
    for rid in _ragdoll_rids:
        arr.append(rid)
    if _char_rid.is_valid():
        arr.append(_char_rid)
    return arr


func _is_overlapping(rb: RigidBody3D, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
    var shape_node := rb.get_child(0) as CollisionShape3D
    if not shape_node or not shape_node.shape:
        return false
    var params := PhysicsShapeQueryParameters3D.new()
    params.shape          = shape_node.shape
    params.transform      = rb.global_transform * shape_node.transform
    params.exclude        = exclude
    params.collision_mask = RAGDOLL_MASK
    return not space.intersect_shape(params, 1).is_empty()
