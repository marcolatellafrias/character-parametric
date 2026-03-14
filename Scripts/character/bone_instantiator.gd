class_name BoneInstantiator
extends Node3D

@export var is_active: bool = false
@export var archetype: EntityStats.Archetype = EntityStats.Archetype.fat_man

var player_camera: Camera3D
var entity_stats : EntityStats
var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil 
var char_rigidbody : CharacterRigidBody3D
var ik_util : IkUtil
# NEW
var locomotion_signals: LocomotionSignals
var procedural_animator: ProceduralBoneAnimator

@onready var player_controller: PlayerController
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
    entity_stats = EntityStats.create(archetype)
    skel_sizes_util = SkeletonSizesUtil.create(entity_stats)
    custom_bones_util = CustomBonesUtil.create(skel_sizes_util, entity_stats)
    ik_util = IkUtil.create(skel_sizes_util, self)
    var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
    var charRb := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
    char_rigidbody = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active)
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

    if is_active:
        player_camera = Camera3D.new()
        player_camera.current = true
        char_rigidbody.add_child(player_camera)
        player_controller.setup(char_rigidbody, player_camera, custom_bones_util.head, skel_sizes_util.head_size)

    # NEW — create signals and animator
    locomotion_signals = LocomotionSignals.create(ik_util, char_rigidbody, skel_sizes_util)
    procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)
    _register_bone_animations()

# NEW — wire up which bones get animated and how
func _register_bone_animations() -> void:
    var PA := ProceduralBoneAnimator	
    
    var vertical_bobbing :=  1.0
    var hip_swing :=  0.5
    var shoulder_swing :=  0.8
       
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
        
    # HIPS   
    # Hip Z rotation: el pie que va adelante rota su cadera hacia adelante (ROT_Z en hips)
    procedural_animator.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.99)
    procedural_animator.register(left_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, 0.99)
    procedural_animator.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.1)
    procedural_animator.register(left_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  -0.1)
    
    # Hip Y rotation: el pie que va adelante empuja su cadera hacia adelante (ROT_Y en hips)
    var hips_rotation := spine_local_weight(0, 5, _bottom_spine_rotation, _top_spine_rotation)
    procedural_animator.register(right_hip, PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -hips_rotation)
    procedural_animator.register(left_hip, PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, hips_rotation)    
    
    # LOWER SPINE 
    # Root Y position: dips down mid-step, scaled by foot spread
    procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_X, vertical_bobbing * -0.14)
    procedural_animator.register(lower_spine, PA.Axis.POS_Y, PA.SignalType.FOOT_SPREAD_Z, vertical_bobbing * -0.14)
    
    # Root Y rotation: el pie que va adelante gira la columna en su direccion (ROT_Y en lower_spine)    
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


func _clear_prior_generations()-> void:
    for global_target in global_targets.get_children(): 
        global_target.queue_free()
    for local_target in local_targets.get_children(): 
        local_target.queue_free()
    for skel_rigidbody in skel_rigidbodies.get_children(): 
        skel_rigidbody.queue_free()
    for joint in joints.get_children(): 
        joint.queue_free()
    if (char_rigidbody):
        char_rigidbody.queue_free()
    player_camera = null

func _physics_process(_delta: float) -> void:
    _update_local_targets_positions()
    ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, true, skel_sizes_util, entity_stats) 
    ik_util.update_leg_raycast_offsets(char_rigidbody, _delta, false, skel_sizes_util, entity_stats) 
    skel_sizes_util.update(_delta,char_rigidbody,entity_stats,ik_util)
    ik_util.update_ik_raycast(true, custom_bones_util, skel_sizes_util,char_rigidbody)
    ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util,char_rigidbody)
    # NEW — update signals first, then apply bone animations after IK
    locomotion_signals.update(_delta)
    procedural_animator.update()

func _update_local_targets_positions()-> void:
    pass
    local_targets.global_position = char_rigidbody.global_position
    local_targets.global_rotation = Vector3(0,char_rigidbody.global_rotation.y,0)

func spine_local_weight(index: int, count: int, min_rot: float, max_rot: float) -> float:
    var global_weight := func(i: int) -> float:
        if i < 0:
            return 0.0
        var t := float(i) / float(count - 1)
        return lerp(max_rot, min_rot, t)
    return global_weight.call(index) - global_weight.call(index - 1)
