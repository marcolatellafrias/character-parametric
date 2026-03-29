class_name BoneInstantiator
extends Node3D

@export var is_active: bool = false
@export var master_seed: int = 0
var entity_instantiation: EntityInstantiation

var player_camera: Camera3D
var entity_archetype: EntityArchetype
var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil
var char_rigidbody: CharacterRigidBody3D
var ik_util: IkUtil
var locomotion_signals: LocomotionSignals
var procedural_animator: ProceduralBoneAnimator
var ragdoll_util: RagdollUtil

var anim_mod: AnimationModifiers
var bone_animations: BoneAnimations
var arms_controller: ArmsController

var player_controller: PlayerController

@onready var global_targets:   Node3D = $"global_targets"
@onready var local_targets:    Node3D = $"local_targets"
@onready var skel_rigidbodies: Node3D = $"skel_rigidbodies"
@onready var joints:           Node3D = $"joints"

var jump_squat_t: float = 0.0
var crouch_t:     float = 0.0

var grab_cone_mesh: MeshInstance3D = null
var show_grab_cone: bool = false
var grab_cone_half_angle: float = 40.0

var is_seated:    bool = false
var current_seat: Node = null

func _ready() -> void:
    if is_active:
        player_controller = PlayerController.new()
        add_child(player_controller)
    initialize_skeleton()

func initialize_skeleton() -> void:
    _clear_prior_generations()

    entity_instantiation = EntityInstantiation.create(master_seed)
    entity_archetype     = entity_instantiation.arch_final
    skel_sizes_util      = SkeletonSizesUtil.create(entity_instantiation)
    custom_bones_util    = CustomBonesUtil.create(skel_sizes_util, entity_instantiation)
    ik_util              = IkUtil.create(skel_sizes_util, self)

    var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
    var charRb      := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
    char_rigidbody  = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active, entity_instantiation)
    char_rigidbody.fall_triggered.connect(_on_fall_triggered)
    char_rigidbody.add_child(custom_bones_util.lower_spine)
    add_child(char_rigidbody)
    
    var cone_dist := entity_instantiation.arch_final.reach * entity_instantiation.arch_final.reach_multiplier
    var cone_radius : float = cone_dist * abs(tan(deg_to_rad(grab_cone_half_angle)))
    grab_cone_mesh = DebugUtil.create_debug_cone(Color(0.2, 0.8, 1.0, 0.15), cone_dist, cone_radius)
    grab_cone_mesh.visible = false
    char_rigidbody.add_child(grab_cone_mesh)
    _setup_char_grabbable()

    local_targets.add_child(ik_util.left_leg_raycast)
    local_targets.add_child(ik_util.right_leg_raycast)
    ik_util.left_leg_raycast.add_exception(char_rigidbody)
    ik_util.right_leg_raycast.add_exception(char_rigidbody)
    local_targets.add_child(ik_util.left_leg_next_target)
    local_targets.add_child(ik_util.right_leg_next_target)
    local_targets.add_child(ik_util.left_leg_airborne_target)
    local_targets.add_child(ik_util.right_leg_airborne_target)
    global_targets.add_child(ik_util.left_leg_current_target)
    global_targets.add_child(ik_util.right_leg_current_target)

    local_targets.add_child(ik_util.left_arm_ik_target)
    local_targets.add_child(ik_util.right_arm_ik_target)
    local_targets.add_child(ik_util.left_arm_pole)
    local_targets.add_child(ik_util.right_arm_pole)

    # Creamos anim_mod y arms_controller antes del player para que setup los reciba
    anim_mod = AnimationModifiers.new()
    add_child(anim_mod)
    anim_mod.bi = self

    arms_controller = ArmsController.new()
    add_child(arms_controller)
    arms_controller.bi = self
    arms_controller.setup(anim_mod)

    if is_active and is_instance_valid(player_controller):
        player_camera = Camera3D.new()
        player_camera.current = true
        char_rigidbody.add_child(player_camera)
        player_controller.setup(char_rigidbody, player_camera, custom_bones_util.head, skel_sizes_util.head_size, entity_instantiation)

    locomotion_signals = LocomotionSignals.create(ik_util, char_rigidbody, skel_sizes_util)

    ik_util.left_arm_ik_target.position  = skel_sizes_util.left_arm_tip_rest_local
    ik_util.right_arm_ik_target.position = skel_sizes_util.right_arm_tip_rest_local
    ik_util.left_arm_pole.position       = skel_sizes_util.left_arm_pole_rest_local
    ik_util.right_arm_pole.position      = skel_sizes_util.right_arm_pole_rest_local

    ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
        ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
    ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
        ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

    procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)

    bone_animations = BoneAnimations.new()
    add_child(bone_animations)
    bone_animations.bi = self
    bone_animations.register_all()

    ragdoll_util = RagdollUtil.create(custom_bones_util, skel_rigidbodies, joints)

    jump_squat_t = 0.0
    crouch_t     = 0.0

func _on_fall_triggered(world_dir: Vector3) -> void:
    if is_seated:
        return
    if not is_instance_valid(ragdoll_util) or ragdoll_util.is_active:
        return
    char_rigidbody.is_snapshot_active = false
    ragdoll_util.activate_with_impact(char_rigidbody, custom_bones_util.lower_spine, world_dir)

func _clear_prior_generations() -> void:
    if is_instance_valid(ragdoll_util):
        if ragdoll_util.is_active and is_instance_valid(char_rigidbody):
            char_rigidbody.freeze = false
            char_rigidbody.collider.disabled = false
        ragdoll_util.cleanup()
    ragdoll_util = null

    for child in global_targets.get_children():   child.queue_free()
    for child in local_targets.get_children():    child.queue_free()
    for child in skel_rigidbodies.get_children(): child.queue_free()
    for child in joints.get_children():           child.queue_free()

    if is_instance_valid(char_rigidbody):
        char_rigidbody.queue_free()

    if is_instance_valid(anim_mod):
        anim_mod.queue_free()
        anim_mod = null
    if is_instance_valid(arms_controller):
        arms_controller.queue_free()
        arms_controller = null
    if is_instance_valid(bone_animations):
        bone_animations.queue_free()
        bone_animations = null

    player_camera = null

func _physics_process(delta: float) -> void:
    _update_local_targets_positions()

    if is_instance_valid(char_rigidbody) and is_instance_valid(ragdoll_util):
        if ragdoll_util.is_active:
            char_rigidbody._ext_ragdoll_state = 1
        elif ragdoll_util.is_recovering:
            char_rigidbody._ext_ragdoll_state = 2
        else:
            char_rigidbody._ext_ragdoll_state = 0

    ik_util.update_leg_raycast_offsets(char_rigidbody, delta, true,  skel_sizes_util, entity_archetype)
    ik_util.update_leg_raycast_offsets(char_rigidbody, delta, false, skel_sizes_util, entity_archetype)

    if is_instance_valid(ragdoll_util):
        ragdoll_util.update(delta)
        if ragdoll_util.is_active:
            ik_util.update_ik_raycast(true,  custom_bones_util, skel_sizes_util, char_rigidbody)
            ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, char_rigidbody)
            return
        if ragdoll_util.is_recovering and not ik_util.recovery_targets_locked:
            ik_util.recovery_targets_locked = true
        elif not ragdoll_util.is_recovering and ik_util.recovery_targets_locked:
            ik_util.recovery_targets_locked = false
            char_rigidbody.is_snapshot_active = true

    skel_sizes_util.update(delta, char_rigidbody, entity_instantiation, ik_util)
    ik_util.update_ik_raycast(true,  custom_bones_util, skel_sizes_util, char_rigidbody)
    ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, char_rigidbody)

    if is_instance_valid(arms_controller):
        var effective_crouch_t := 1.0 if is_seated else crouch_t
        arms_controller.update_arm_compress(jump_squat_t, effective_crouch_t)

    locomotion_signals.update(delta)

    # 1. Reset arm targets a rest
    ik_util.left_arm_ik_target.position  = skel_sizes_util.left_arm_tip_rest_local
    ik_util.right_arm_ik_target.position = skel_sizes_util.right_arm_tip_rest_local

    # 2. Procedural animator acumula offsets sobre rest
    procedural_animator.update()

    # 3. AnimationModifiers aplica root offsets (crouch, jump squat, throw tilt)
    if is_instance_valid(anim_mod):
        anim_mod.jump_squat_t = jump_squat_t
        anim_mod.crouch_t = crouch_t
        anim_mod.apply(delta)

    # 4. Convertir posiciones locales a globales
    var rb_basis := custom_bones_util.lower_spine.global_transform.basis
    var left_anim_offset:  Vector3 = ik_util.left_arm_ik_target.position  - skel_sizes_util.left_arm_tip_rest_local
    var right_anim_offset: Vector3 = ik_util.right_arm_ik_target.position - skel_sizes_util.right_arm_tip_rest_local

    ik_util.left_arm_ik_target.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_tip_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_anim_offset)
    ik_util.right_arm_ik_target.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_tip_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_anim_offset)

    var left_pole_anim_offset:  Vector3 = ik_util.left_arm_pole.position  - skel_sizes_util.left_arm_pole_rest_local
    var right_pole_anim_offset: Vector3 = ik_util.right_arm_pole.position - skel_sizes_util.right_arm_pole_rest_local

    ik_util.left_arm_pole.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_pole_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_pole_anim_offset)
    ik_util.right_arm_pole.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_pole_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_pole_anim_offset)

    # 5. ArmsController aplica throw visual y grab visual sobre posiciones globales
    if is_instance_valid(arms_controller):
        arms_controller.apply_world_overrides(delta)

    # 6. Solve IK final
    ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
        ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
    ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
        ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

    if is_instance_valid(ragdoll_util) and not ragdoll_util.is_recovering:
        ragdoll_util.sync_to_bones()
        
    if is_seated and is_instance_valid(current_seat):
        current_seat.update_borrowed_mesh()
        var seat_pos : Vector3 = current_seat.global_position
        custom_bones_util.lower_spine.global_position = Vector3(
            seat_pos.x,
            seat_pos.y + current_seat.height,
            seat_pos.z
        )
        char_rigidbody.global_position.x = seat_pos.x
        char_rigidbody.global_position.z = seat_pos.z
        
    _update_grab_cone()

func _update_local_targets_positions() -> void:
    local_targets.global_position = char_rigidbody.global_position
    local_targets.global_rotation = Vector3(0, char_rigidbody.global_rotation.y, 0)

func refresh_camera_animations() -> void:
    if is_instance_valid(bone_animations):
        bone_animations.refresh_camera_animations()

func set_first_person_visibility(first_person: bool) -> void:
    var visible_bones: Array[CustomBone] = [
        custom_bones_util.left_upper_feet,
        custom_bones_util.right_upper_feet,
        custom_bones_util.left_lower_arm,
        custom_bones_util.right_lower_arm,
    ]
    var all_bones: Array[CustomBone] = [
        custom_bones_util.lower_spine,
        custom_bones_util.middle_spine,
        custom_bones_util.upper_spine,
        custom_bones_util.chest,
        custom_bones_util.left_hip,
        custom_bones_util.right_hip,
        custom_bones_util.left_upper_leg,
        custom_bones_util.left_lower_leg,
        custom_bones_util.right_upper_leg,
        custom_bones_util.right_lower_leg,
        custom_bones_util.left_upper_feet,
        custom_bones_util.right_upper_feet,
        custom_bones_util.left_shoulder,
        custom_bones_util.right_shoulder,
        custom_bones_util.left_upper_arm,
        custom_bones_util.left_lower_arm,
        custom_bones_util.right_upper_arm,
        custom_bones_util.right_lower_arm,
        custom_bones_util.neck,
        custom_bones_util.head,
    ]
    for bone in all_bones:
        if not is_instance_valid(bone):
            continue
        bone.set_mesh_visible(first_person == false or visible_bones.has(bone))

func _setup_char_grabbable() -> void:
    var grabbable := GrabbableInteractable.new()
    char_rigidbody.add_child(grabbable)

    var full_height    := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
    var ground_local_y := char_rigidbody._capsule_stand_y_offset - full_height * 0.5
    var handle_y       := ground_local_y + skel_sizes_util.leg_height \
        + skel_sizes_util.lower_spine_size.y + skel_sizes_util.middle_spine_size.y
    var handle_x := skel_sizes_util.shoulders_width * 0.5

    grabbable.add_handle_point_local(Vector3(-handle_x, handle_y, 0.0))
    grabbable.add_handle_point_local(Vector3( handle_x, handle_y, 0.0))
    grabbable.add_grab_point_local(Vector3(0.0, char_rigidbody._capsule_stand_y_offset, 0.0))

func _update_grab_cone() -> void:
    if not is_instance_valid(grab_cone_mesh) or not is_instance_valid(player_camera):
        return
    grab_cone_mesh.visible = is_active and show_grab_cone
    if not grab_cone_mesh.visible:
        return
    var chest := custom_bones_util.chest
    var origin := chest.global_position + chest.global_transform.basis.y * skel_sizes_util.chest_size.y
    var fwd := -player_camera.global_transform.basis.z
    grab_cone_mesh.global_position = origin
    grab_cone_mesh.global_transform.basis = Basis.looking_at(-fwd, Vector3.UP)
