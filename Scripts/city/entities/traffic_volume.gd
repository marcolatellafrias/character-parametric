# TrafficPlane.gd
extends Area3D
class_name TrafficPlane

var lane_volume: LaneVolume
var traffic_index: int = -1  # -1 = sin semáforo, 0 o 1 = índice de grupo

var collision_shape: CollisionShape3D

const THICKNESS: float = 0.5  # Espesor del plano de tráfico

func _init(parent_lane: LaneVolume) -> void:
    lane_volume = parent_lane
    _setup_area()

func _setup_area() -> void:
    monitoring = true
    monitorable = true
    
    # Inicialmente sin colisión, se configurará después
    collision_layer = 0
    collision_mask = 0
    
    add_to_group("traffic_planes")
    
    set_meta("lane_id", lane_volume.get_id())
    set_meta("traffic_index", traffic_index)

func setup_collision() -> void:
    if lane_volume.end_plane_vertices.size() != 4:
        push_error("[TrafficPlane] End plane vertices no tiene 4 vértices")
        return
    
    # Crear plano con espesor
    var end_verts = lane_volume.end_plane_vertices
    
    # Calcular dirección hacia atrás (inversa al flujo)
    var center_start = lane_volume.get_point_at_grid(0.5, 0.5, true)
    var center_end = lane_volume.get_point_at_grid(0.5, 0.5, false)
    var backward_dir = (center_start - center_end).normalized()
    
    # Crear vértices del plano con espesor
    var front_verts = end_verts
    var back_verts = []
    
    for v in front_verts:
        back_verts.append(v + backward_dir * THICKNESS)
    
    # Crear collision shape
    collision_shape = DebugUtil.create_collision_shape_from_planes(
        front_verts,
        back_verts
    )
    
    if collision_shape:
        add_child(collision_shape)

func set_traffic_index(index: int) -> void:
    traffic_index = index
    set_meta("traffic_index", traffic_index)

func update_layer_for_active_index(active_index: int) -> void:
    if traffic_index == -1:
        collision_layer = 0
        return
    
    if traffic_index == active_index:
        # Verde - layer 4
        collision_layer = 4
        print("[TrafficPlane %s] VERDE - Layer 4 (índice %d == activo %d)" % [lane_volume.get_id(), traffic_index, active_index])
    else:
        # Rojo - layer 3
        collision_layer = 3
        print("[TrafficPlane %s] ROJO - Layer 3 (índice %d != activo %d)" % [lane_volume.get_id(), traffic_index, active_index])

func get_end_vertices() -> Array:
    return lane_volume.end_plane_vertices
