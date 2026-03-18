class_name BoneInstantiator
extends Node3D

@export var is_active: bool = false
@export var master_seed: int = 0
var entity_instantiation: EntityInstantiation

var player_camera: Camera3D
var entity_archetype : EntityArchetype
var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil 
var char_rigidbody : CharacterRigidBody3D
var ik_util : IkUtil
var locomotion_signals: LocomotionSignals
var procedural_animator: ProceduralBoneAnimator
var ragdoll_util: RagdollUtil

var player_controller: PlayerController
@onready var global_targets : Node3D = $"global_targets"
@onready var local_targets : Node3D = $"local_targets"
@onready var skel_rigidbodies : Node3D = $"skel_rigidbodies"
@onready var joints : Node3D = $"joints"

var previous_transform : Transform3D 

func _ready() -> void:
    if is_active:
        player_controller = PlayerController.new()
        add_child(player_controller)
    initialize_skeleton()

func initialize_skeleton() -> void:
    _clear_prior_generations()
    entity_instantiation = EntityInstantiation.create(master_seed)
    entity_archetype = entity_instantiation.arch_final
    skel_sizes_util = SkeletonSizesUtil.create(entity_instantiation)
    custom_bones_util = CustomBonesUtil.create(skel_sizes_util, entity_instantiation)
    ik_util = IkUtil.create(skel_sizes_util, self)
    var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
    var charRb := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
    char_rigidbody = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active, entity_instantiation)
    char_rigidbody.add_child(custom_bones_util.lower_spine)
    add_child(char_rigidbody)
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

    if is_active and is_instance_valid(player_controller):
        player_camera = Camera3D.new()
        player_camera.current = true
        char_rigidbody.add_child(player_camera)
        player_controller.setup(char_rigidbody, player_camera, custom_bones_util.head, skel_sizes_util.head_size, entity_instantiation)

    locomotion_signals = LocomotionSignals.create(ik_util, char_rigidbody, skel_sizes_util)
    procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)
    _register_bone_animations()
    ragdoll_util = RagdollUtil.create(custom_bones_util, skel_rigidbodies, joints)
    

func _register_bone_animations() -> void:
    var PA := ProceduralBoneAnimator	
    var ls := locomotion_signals
    
    var vertical_bobbing := entity_instantiation.root_bounciness
    var shoulder_swing   := entity_instantiation.shoulder_swing
    var hip_swing :=  0.5
       
    var _top_spine_rotation := 0.5 * shoulder_swing
    var _bottom_spine_rotation := -0.5 * hip_swing
    
    var right_hip := custom_bones_util.right_hip	
    var left_hip := custom_bones_util.left_hip		
    var lower_spine := custom_bones_util.lower_spine
    var middle_spine := custom_bones_util.middle_spine
    var upper_spine := custom_bones_util.upper_spine
    var chest := custom_bones_util.chest
    var right_shoulder := custom_bones_util.right_shoulder	
    var left_shoulder := custom_bones_util.left_shoulder	
        
    procedural_animator.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.99)
    procedural_animator.register(left_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, 0.99)
    procedural_animator.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.1)
    procedural_animator.register(left_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  -0.1)
    
    var hips_rotation := spine_local_weight(0, 5, _bottom_spine_rotation, _top_spine_rotation)
    procedural_animator.register(right_hip, PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -hips_rotation)
    procedural_animator.register(left_hip, PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, hips_rotation)    
    
    procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_X, vertical_bobbing * -0.14)
    procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_Z, vertical_bobbing * -0.14)
    
    procedural_animator.register_formula(lower_spine, PA.Axis.ROT_Z,
        func(): return ls.foot_spread_unified.x * (0.01 + 0.04 * ls.speed_norm),
        1.0)
    
    var lower_spine_rotation := spine_local_weight(1, 5, _bottom_spine_rotation, _top_spine_rotation)
    procedural_animator.register(lower_spine, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, lower_spine_rotation)
    
    var middle_spine_rotation := spine_local_weight(2, 5, _bottom_spine_rotation, _top_spine_rotation)
    procedural_animator.register(middle_spine, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, middle_spine_rotation)
    
    var upper_spine_rotation := spine_local_weight(3, 5, _bottom_spine_rotation, _top_spine_rotation)
    procedural_animator.register(upper_spine, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, upper_spine_rotation)
    
    var chest_rotation := spine_local_weight(4, 5, _bottom_spine_rotation, _top_spine_rotation)
    procedural_animator.register(chest, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, chest_rotation)
    
    procedural_animator.register(right_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, shoulder_swing * 0.1)
    procedural_animator.register(left_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, shoulder_swing * 0.1)

func _clear_prior_generations() -> void:
    if is_instance_valid(ragdoll_util):
        if ragdoll_util.is_active and is_instance_valid(char_rigidbody):
            char_rigidbody.freeze = false
            char_rigidbody.collider.disabled = false
        ragdoll_util.cleanup()
    ragdoll_util = null

    for global_target in global_targets.get_children(): 
        global_target.queue_free()
    for local_target in local_targets.get_children(): 
        local_target.queue_free()
    for skel_rigidbody in skel_rigidbodies.get_children(): 
        skel_rigidbody.queue_free()
    for joint in joints.get_children(): 
        joint.queue_free()
    if is_instance_valid(char_rigidbody):
        char_rigidbody.queue_free()
    player_camera = null

func _physics_process(_delta: float) -> void:
    _update_local_targets_positions()

    # Raycasts siempre se actualizan, incluso durante ragdoll,
    # para que lerpen solos a 0 cuando char_rb está congelado
    ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, true, skel_sizes_util, entity_archetype)
    ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, false, skel_sizes_util, entity_archetype)

    if is_instance_valid(ragdoll_util):
        ragdoll_util.update(_delta)
        if ragdoll_util.is_active:
            return

    skel_sizes_util.update(_delta, char_rigidbody, entity_instantiation, ik_util)
    ik_util.update_ik_raycast(true, custom_bones_util, skel_sizes_util, char_rigidbody)
    ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, char_rigidbody)
    locomotion_signals.update(_delta)
    procedural_animator.update()
    if is_instance_valid(ragdoll_util) and not ragdoll_util.is_recovering:
        ragdoll_util.sync_to_bones()

func _update_local_targets_positions() -> void:
    pass
    local_targets.global_position = char_rigidbody.global_position
    local_targets.global_rotation = Vector3(0, char_rigidbody.global_rotation.y, 0)

func spine_local_weight(index: int, count: int, min_rot: float, max_rot: float) -> float:
    var global_weight := func(i: int) -> float:
        if i < 0:
            return 0.0
        var t := float(i) / float(count - 1)
        return lerp(max_rot, min_rot, t)
    return global_weight.call(index) - global_weight.call(index - 1)
