class_name SeatController
extends Node

var char_rigidbody:    CharacterRigidBody3D
var player_camera:     Camera3D
var player_controller: PlayerController

var _hovered_seat: Seat = null
var _current_seat: Seat = null
var is_seated: bool = false

var _spine_rb_offset: Vector3 = Vector3.ZERO

const SEAT_RAY_LENGTH := 3.0
const SEAT_LAYER      := 4

func setup(rb: CharacterRigidBody3D, cam: Camera3D, pc: PlayerController) -> void:
    char_rigidbody    = rb
    player_camera     = cam
    player_controller = pc

func update_references(rb: CharacterRigidBody3D, cam: Camera3D) -> void:
    if is_seated:
        stand_up()
    char_rigidbody = rb
    player_camera  = cam

func handle_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or event.echo or not event.pressed:
        return
    if event.keycode == KEY_E:
        if is_seated:
            stand_up()
        elif is_instance_valid(_hovered_seat):
            sit_down(_hovered_seat)

func update(_delta: float) -> void:
    if is_seated:
        _update_seated()
    else:
        _process_seat_hover()

func sit_down(seat: Seat) -> void:
    if is_seated:
        return
    _current_seat = seat
    is_seated     = true

    player_controller.camera_yaw   = seat.global_rotation.y
    player_controller.camera_pitch = 0.0
    player_camera.rotation.x       = 0.0
    char_rigidbody.rotation.y      = seat.global_rotation.y

    var bi := _get_bi()
    if is_instance_valid(bi):
        _spine_rb_offset = bi.custom_bones_util.lower_spine.global_position \
            - char_rigidbody.global_position
        bi.is_seated    = true
        bi.current_seat = seat

    char_rigidbody.freeze_mode              = RigidBody3D.FREEZE_MODE_KINEMATIC
    char_rigidbody.freeze                   = true
    char_rigidbody.linear_velocity          = Vector3.ZERO
    char_rigidbody.angular_velocity         = Vector3.ZERO
    char_rigidbody.movement_enabled         = false
    char_rigidbody.impact_detection_enabled = false
    char_rigidbody.reset_impact_state()
    char_rigidbody.global_position = seat.seat_point.global_position - _spine_rb_offset

    # Ahora sí, después de mover el rb
    if is_instance_valid(bi):
        bi.procedural_animator.lock_bone_position(bi.custom_bones_util.lower_spine)

    seat.borrow_mesh(char_rigidbody)

    if is_instance_valid(_hovered_seat):
        _hovered_seat.set_hovered(false)
    _hovered_seat = null

func stand_up() -> void:
    if not is_seated:
        return
    is_seated = false

    if is_instance_valid(_current_seat):
        _current_seat.return_mesh()

    var bi := _get_bi()
    if is_instance_valid(bi):
        bi.is_seated    = false
        bi.current_seat = null
        bi.procedural_animator.unlock_bone_position(bi.custom_bones_util.lower_spine)

    char_rigidbody.freeze                   = false
    char_rigidbody.movement_enabled         = true
    char_rigidbody.impact_detection_enabled = true
    char_rigidbody.reset_impact_state()
    _current_seat = null

func _update_seated() -> void:
    if not is_instance_valid(_current_seat):
        stand_up()
        return
    char_rigidbody.rotation.y      = player_controller.camera_yaw
    char_rigidbody.global_position = _current_seat.seat_point.global_position - _spine_rb_offset

func _process_seat_hover() -> void:
    if not is_instance_valid(player_camera):
        return
    var vp_size := player_camera.get_viewport().get_visible_rect().size
    var from    := player_camera.global_position
    var dir     := player_camera.project_ray_normal(vp_size * 0.5)
    var query   := PhysicsRayQueryParameters3D.create(from, from + dir * SEAT_RAY_LENGTH)
    query.collision_mask = SEAT_LAYER

    var hit := player_camera.get_world_3d().direct_space_state.intersect_ray(query)
    var new_hovered: Seat = null
    if not hit.is_empty() and hit.collider is Seat:
        new_hovered = hit.collider as Seat

    if new_hovered != _hovered_seat:
        if is_instance_valid(_hovered_seat):
            _hovered_seat.set_hovered(false)
        _hovered_seat = new_hovered
        if is_instance_valid(_hovered_seat):
            _hovered_seat.set_hovered(true)

func _get_bi() -> BoneInstantiator:
    return char_rigidbody.get_parent() as BoneInstantiator
