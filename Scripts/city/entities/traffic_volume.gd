# TrafficPlane.gd
extends Area3D
class_name TrafficPlane

var lane_volume: LaneVolume
var traffic_index: int = -1
var collision_shape: CollisionShape3D

const THICKNESS: float = 0.5

func _init(parent_lane: LaneVolume, initial_traffic_index: int) -> void:
    lane_volume = parent_lane
    traffic_index = initial_traffic_index
    _setup_area()

func _setup_area() -> void:
    monitoring = false
    monitorable = true
    
    collision_layer = 0
    collision_mask = 0
    
    add_to_group("traffic_planes")
    
    set_meta("lane_id", lane_volume.get_id())
    set_meta("traffic_index", traffic_index)

func setup_collision() -> void:
    if lane_volume.end_plane_vertices.size() != 4:
        push_error("[TrafficPlane] End plane vertices no tiene 4 vértices")
        return
    
    var end_verts = lane_volume.end_plane_vertices
    
    var center_start = lane_volume.get_point_at_grid(0.5, 0.5, true)
    var center_end = lane_volume.get_point_at_grid(0.5, 0.5, false)
    var backward_dir = (center_start - center_end).normalized()
    
    var front_verts = end_verts
    var back_verts = []
    
    for v in front_verts:
        back_verts.append(v + backward_dir * THICKNESS)
    
    collision_shape = DebugUtil.create_collision_shape_from_planes(
        front_verts,
        back_verts
    )
    
    if collision_shape:
        add_child(collision_shape)

func update_layer_for_active_index(active_index: int) -> void:
    if traffic_index == -1:
        collision_layer = 0
        return
    
    if traffic_index == active_index:
        collision_layer = 0
    else:
        collision_layer = 2

func get_end_vertices() -> Array:
    return lane_volume.end_plane_vertices
